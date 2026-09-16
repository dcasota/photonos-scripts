//! Generate the Hyper-V config and build the kernel RPMs in the emulated root.
//!
//! Three things here are hard-won rather than obvious, and each has a comment
//! at the place it matters:
//!
//! * The config is generated from the PRISTINE `config_<arch>`, not from the
//!   `.config` that `%prep` leaves behind. `%prep` seds CONFIG_LOCALVERSION and
//!   the toolchain version strings into it, so writing that file back to SPECS
//!   would bake one build's Release into the config of every later build.
//! * `rpmbuild -bb --short-circuit` stamps `Requires: rpmlib(ShortCircuited)`,
//!   which nothing provides, so tdnf and the installer refuse the package. The
//!   packages that reach the media are produced by `-bb --noprep`.
//! * The build runs in its own process group so the disk guard can stop and
//!   resume it without losing hours of compilation.

use super::buildroot::{chroot_capture, chroot_logged, mount_pseudo};
use super::guard::{self, Decision};
use super::{run, Ctx};
use crate::kconfig::{self, Kconfig};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// Everything heavy lives under one directory that is bind-mounted into the
/// build root at /work, so the tree can be measured and guarded from outside
/// the chroot and survives rebuilding the root itself.
pub fn build_base(c: &Ctx) -> PathBuf {
    c.spec.workdir.join("build")
}
fn rpmtop_host(c: &Ctx) -> PathBuf {
    build_base(c).join("rpmbuild")
}
fn builddir_host(c: &Ctx) -> PathBuf {
    build_base(c).join("BUILD")
}

/// `photon_subrelease`, read from the tree that is being built.
///
/// linux.spec gates real behaviour on it - at >= 92 it rewrites the toolchain
/// version strings in .config for gcc 12.5.0 and binutils 2.46.1 - so guessing
/// it produces a config that does not match the compiler that will read it.
pub fn photon_subrelease(tree: &Path) -> Result<u32, String> {
    let p = tree.join("build-config.json");
    let text = fs::read_to_string(&p).map_err(|e| format!("{}: {e}", p.display()))?;
    for line in text.lines() {
        let Some(rest) = line.split_once("\"photon-subrelease\"") else { continue };
        let v: String = rest.1.chars().filter(|ch| ch.is_ascii_digit()).collect();
        if let Ok(n) = v.parse::<u32>() {
            return Ok(n);
        }
    }
    Err(format!(
        "no photon-subrelease in {}; linux.spec changes behaviour at >= 92, so it \
         cannot be defaulted",
        p.display()
    ))
}

/// The spec's `Version:` as this subrelease sees it.
pub fn spec_version(c: &Ctx, flavour: &str) -> Result<String, String> {
    let spec = c.spec.photon_tree.join("SPECS/linux").join(format!("{flavour}.spec"));
    let sr = photon_subrelease(&c.spec.photon_tree)?;
    let dir = c.spec.photon_tree.join("SPECS/linux");
    let read = crate::specresolve::dir_reader(&dir);
    let text = crate::specresolve::resolve(&read, &format!("{flavour}.spec"), Some(sr))
        .ok_or_else(|| format!("cannot read {}", spec.display()))?;
    // "Version:" WITH the colon: `field` matches a line prefix, so "Version"
    // returns ":        6.12.109" and every predicted RPM name is then wrong.
    crate::specresolve::field(&text, "Version:")
        .ok_or_else(|| format!("no Version: in {}", spec.display()))
}

/// Stage the spec and a FLAT SOURCES directory.
///
/// Flat because rpm resolves `SourceN:` and `PatchN:` by basename against
/// `%_sourcedir`, while the tree keeps them in subdirectories (CVE/, aarch64/,
/// generic/, crypto/, ...). Copying the tree shape would leave every patch
/// unfindable.
///
/// The spec and the source FILES are re-copied on every call; only the
/// tarballs are guarded by a marker. That asymmetry is the fix for a silent
/// and expensive failure: `rpmbuild` reads `Source1: config_%{_arch}` out of
/// this staged directory, NOT out of the tree, so a run that staged the
/// pristine config and then rewrote the tree's copy would build the kernel
/// from the config it was supposed to replace - producing a "successful"
/// kernel with no Hyper-V support at all. The same applies to the Release
/// bump in linux.spec. The files are small; the tarballs are hundreds of
/// megabytes and never change, so only those are skipped.
pub fn stage(c: &mut Ctx) -> Result<(), String> {
    let top = rpmtop_host(c);
    let marker = c.spec.marker("tarballs");
    for d in ["SOURCES", "SPECS", "RPMS", "SRPMS"] {
        fs::create_dir_all(top.join(d)).map_err(|e| format!("{}: {e}", top.display()))?;
    }
    fs::create_dir_all(builddir_host(c)).map_err(|e| format!("{e}"))?;
    fs::create_dir_all(build_base(c).join("BUILDROOT")).map_err(|e| format!("{e}"))?;
    if c.spec.dry {
        c.say("  would stage the spec and a flat SOURCES tree");
        return Ok(());
    }

    let specdir = c.spec.photon_tree.join("SPECS/linux");
    let mut files = 0usize;
    copy_flat(&specdir, &top.join("SOURCES"), &mut files)?;
    for f in &c.spec.flavours {
        let s = specdir.join(format!("{f}.spec"));
        fs::copy(&s, top.join("SPECS").join(format!("{f}.spec")))
            .map_err(|e| format!("{}: {e}", s.display()))?;
    }
    c.say(&format!("  staged {files} source files, {} spec(s)", c.spec.flavours.len()));

    // The declared tarballs, guarded by the marker because they are hundreds of
    // megabytes and never change. The spec and the config above are NOT
    // guarded: see the function comment.
    if marker.is_file() {
        c.skip("stage:tarballs", "already staged");
        return Ok(());
    }
    let mut staged = Vec::new();
    for entry in fs::read_dir(&c.spec.sources)
        .map_err(|e| format!("{}: {e}", c.spec.sources.display()))?
        .flatten()
    {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.ends_with(".tar.xz") || name.ends_with(".tar.gz") || name.ends_with(".tar.bz2") {
            fs::copy(entry.path(), top.join("SOURCES").join(&name))
                .map_err(|e| format!("{name}: {e}"))?;
            staged.push(name);
        }
    }
    c.say(&format!("  staged {} tarball(s)", staged.len()));
    fs::write(&marker, "").map_err(|e| format!("{}: {e}", marker.display()))?;
    Ok(())
}

/// Copy every non-spec file under `from`, recursively, into one flat directory.
fn copy_flat(from: &Path, to: &Path, n: &mut usize) -> Result<(), String> {
    for e in fs::read_dir(from).map_err(|e| format!("{}: {e}", from.display()))?.flatten() {
        let p = e.path();
        if p.is_dir() {
            copy_flat(&p, to, n)?;
            continue;
        }
        let name = e.file_name().to_string_lossy().to_string();
        if name.ends_with(".spec") {
            continue;
        }
        fs::copy(&p, to.join(&name)).map_err(|e| format!("{}: {e}", p.display()))?;
        *n += 1;
    }
    Ok(())
}

/// The rpmbuild argument vector every phase shares.
/// Takes no `Ctx`: an argv borrowed from the context would pin an immutable
/// borrow for as long as the vector lives, and every runner that consumes it
/// needs `&mut Ctx` to log through.
fn rpmbuild_argv<'a>(
    mode: &'a str,
    extra: &[&'a str],
    spec_in_root: &'a str,
    sr: &'a str,
    jobs: &'a str,
) -> Vec<&'a str> {
    let mut v = vec![
        "/usr/bin/rpmbuild",
        mode,
        "--nodeps",
        "--define",
        "_topdir /work/rpmbuild",
        "--define",
        "_builddir /work/BUILD",
        "--define",
        "_buildrootdir /work/BUILDROOT",
        "--define",
        "dist .ph5",
        "--define",
        sr,
        "--define",
        jobs,
        // dwz across a kernel debug tree is hours of emulated work for a
        // package that never reaches the media.
        "--define",
        "_find_debuginfo_dwz_opts %{nil}",
    ];
    v.extend_from_slice(extra);
    v.push(spec_in_root);
    v
}

/// Photon's applicability check, made non-fatal FOR THE CONFIG-GENERATION PASS
/// ONLY.
///
/// The upstream check ends in `diff -u .config.old .config`, and `%prep` runs
/// under `set -e`, so any difference aborts the build. That is the correct gate
/// for a real build. It is circular for the pass that exists to COMPUTE what
/// the gate demands: there is no prepared tree to run `olddefconfig` in until
/// `%prep` succeeds, and `%prep` cannot succeed until the config is already a
/// fixed point.
///
/// It bites here because the media's config is not a fixed point under the
/// media's OWN toolchain: binutils 2.46.1 supports RELR relocations, so
/// `olddefconfig` adds CONFIG_TOOLS_SUPPORT_RELR and CONFIG_RELR, which the
/// shipped config - written against binutils 2.39 - does not carry.
///
/// The build pass restores the upstream file, so the gate that decides whether
/// a kernel ships is never weakened. It passes there because `gen_config` wrote
/// a config it has already PROVEN to be a fixed point.
const TOLERANT_APPLICABILITY: &str = "\
echo \"Check for .config applicability (sharukhan config-generation pass)\"
make LC_ALL= olddefconfig
sed -i '3d' .config
if [[ -f .config.old ]]; then diff -u .config.old .config || true; fi
";

/// Swap the applicability check between the tolerant and the upstream form.
fn set_applicability_check(c: &mut Ctx, tolerant: bool) -> Result<(), String> {
    let name = "check_for_config_applicability.inc";
    let dst = rpmtop_host(c).join("SOURCES").join(name);
    if tolerant {
        fs::write(&dst, TOLERANT_APPLICABILITY).map_err(|e| format!("{}: {e}", dst.display()))?;
        c.say("  applicability check made non-fatal for the config-generation pass only");
    } else {
        let src = c.spec.photon_tree.join("SPECS/linux").join(name);
        fs::copy(&src, &dst).map_err(|e| format!("{}: {e}", src.display()))?;
        c.say("  upstream applicability check restored: the build pass uses the real gate");
    }
    Ok(())
}

/// Where `%prep` actually left the kernel tree.
///
/// rpm 4.18 extracts into `_builddir/linux-<ver>`. rpm 6 wraps every build in
/// `_builddir/<name>-<ver>-build/` and extracts inside THAT. The media here
/// carries rpm 6.1.0 and the previous media carried 4.18, so hardcoding either
/// layout makes a perfectly good `-bp` look like it produced nothing.
///
/// Identified by the Makefile rather than by name: that is what makes it a
/// kernel tree, and it is the file every later step needs.
fn find_kernel_tree(builddir: &Path, version: &str) -> Option<PathBuf> {
    let want = format!("linux-{version}");
    let direct = builddir.join(&want);
    if direct.join("Makefile").is_file() {
        return Some(direct);
    }
    for e in fs::read_dir(builddir).ok()?.flatten() {
        if !e.path().is_dir() {
            continue;
        }
        let nested = e.path().join(&want);
        if nested.join("Makefile").is_file() {
            return Some(nested);
        }
    }
    None
}

/// A fingerprint of everything `%prep` consumes: the STAGED spec and the
/// STAGED config, which are the two files that actually reach rpmbuild.
///
/// Recorded in the prep marker so a restart can distinguish "already prepared
/// from exactly these inputs" from "prepared from something else". Without it
/// the only safe answer is to re-prep, and `rpmbuild -bp` does `rm -rf` on the
/// tree - so an unconditional re-prep discards every compiled object and makes
/// the resumable phases resumable in name only.
fn prep_fingerprint(c: &Ctx, flavour: &str) -> Result<String, String> {
    let sr = photon_subrelease(&c.spec.photon_tree)?;
    let cfgp = kernel_config_path(&c.spec.photon_tree, c.spec.arch, flavour, sr)?;
    let name = cfgp
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| format!("{} has no file name", cfgp.display()))?;
    let top = rpmtop_host(c);
    let spec_path = top.join("SPECS").join(format!("{flavour}.spec"));
    let cfg_path = top.join("SOURCES").join(name);
    let spec = fs::read(&spec_path).map_err(|e| format!("{}: {e}", spec_path.display()))?;
    let cfg = fs::read(&cfg_path).map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    let mut h = crate::sha256::Sha256::default();
    h.update(&spec);
    h.update(&cfg);
    Ok(h.hex())
}

/// `%prep` only: a patched tree for the config step to run `olddefconfig` in.
pub fn prep(c: &mut Ctx, flavour: &str) -> Result<PathBuf, String> {
    let marker = c.spec.marker(&format!("prep-{flavour}"));
    let version = spec_version(c, flavour)?;
    // Skip only when the tree was prepared from EXACTLY the staged spec and
    // config that are there now. Anything else re-preps, because %prep is the
    // step that applies them.
    let fp = if c.spec.dry { String::new() } else { prep_fingerprint(c, flavour)? };
    if !c.spec.dry && fs::read_to_string(&marker).map(|p| p.trim() == fp).unwrap_or(false) {
        if let Some(t) = find_kernel_tree(&builddir_host(c), &version) {
            c.skip(
                &format!("prep[{flavour}]"),
                "the tree is already prepared from these exact spec and config",
            );
            return Ok(t);
        }
    }
    if c.spec.dry {
        c.say(&format!("  would run rpmbuild -bp for {flavour}"));
        return Ok(builddir_host(c).join(format!("linux-{version}")));
    }
    mount_pseudo(c, &build_base(c))?;
    let sr = format!("photon_subrelease {}", photon_subrelease(&c.spec.photon_tree)?);
    let jobs = format!("_smp_mflags -j{}", c.spec.jobs);
    let spec = format!("/work/rpmbuild/SPECS/{flavour}.spec");
    let log = c.spec.workdir.join(format!("prep-{flavour}.log"));
    let argv = rpmbuild_argv("-bp", &[], &spec, &sr, &jobs);
    c.say(&format!("  rpmbuild -bp {flavour} (emulated; several minutes)"));
    chroot_logged(c, &argv, &log)?;
    let tree_host = find_kernel_tree(&builddir_host(c), &version).ok_or_else(|| {
        format!(
            "rpmbuild -bp reported success but no linux-{version} tree with a Makefile \
             exists under {} (checked both the rpm 4 and rpm 6 layouts)",
            builddir_host(c).display()
        )
    })?;
    c.say(&format!("  prepared tree: {}", tree_host.display()));
    fs::write(&marker, &fp).map_err(|e| format!("{}: {e}", marker.display()))?;
    Ok(tree_host)
}

/// The config file this arch and flavour uses, resolved against the tree.
///
/// **Never `config_x86_64_acvp`.** ACVP and KAT configs are FIPS certification
/// artefacts: changing one does not produce a Hyper-V kernel, it invalidates a
/// certification submission. It is not reachable from here by any flavour.
pub fn kernel_config_path(
    tree: &Path,
    arch: super::Arch,
    flavour: &str,
    subrelease: u32,
) -> Result<PathBuf, String> {
    let base = tree.join("SPECS/linux");
    // The single-source branch keeps the 6.1 kernel's configs in a 6.1/
    // subdirectory with a -6.1 suffix and leaves the 6.12 configs at the plain
    // names, selected by photon_subrelease. Resolve, never guess: a missing
    // file is a typed error, because silently falling back to the other
    // kernel's config produces a kernel that will not boot.
    let stem = match flavour {
        "linux" => format!("config_{}", arch.rpm()),
        "linux-esx" => format!("config-esx_{}", arch.rpm()),
        other => return Err(format!("unknown kernel flavour '{other}'")),
    };
    let candidates = if subrelease <= 90 {
        vec![
            base.join("6.1").join(format!("{stem}-6.1")),
            base.join(format!("{stem}-6.1")),
        ]
    } else {
        vec![base.join(&stem)]
    };
    for p in &candidates {
        if p.is_file() {
            return Ok(p.clone());
        }
    }
    Err(format!(
        "no kernel config for arch={} flavour={flavour} subrelease={subrelease}; looked for {}",
        arch.rpm(),
        candidates.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")
    ))
}

/// Generate the Hyper-V config and write it back into the tree.
///
/// Starts from the PRISTINE config, not from the `.config` `%prep` leaves: see
/// the module comment. Ends by proving the result is a FIXED POINT of
/// `olddefconfig`, which is the same property Photon's own
/// `check_for_config_applicability.inc` asserts at build time - if it were not,
/// the build would fail its own check hours later.
pub fn gen_config(c: &mut Ctx, flavour: &str) -> Result<Vec<kconfig::Forced>, String> {
    let version = spec_version(c, flavour)?;
    let sr = photon_subrelease(&c.spec.photon_tree)?;
    let cfg_path = kernel_config_path(&c.spec.photon_tree, c.spec.arch, flavour, sr)?;
    c.say(&format!("  config file: {}", cfg_path.display()));

    let pristine = fs::read_to_string(&cfg_path).map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    let before = Kconfig::parse(&pristine);
    c.say(&format!("  {} symbols in the pristine config", before.len()));

    // What has to be raised, computed from THIS config.
    let forced = kconfig::dependency_closure(&before, kconfig::HYPERV_FRAGMENT, kconfig::HYPERV_EDGES)?;
    if forced.is_empty() {
        c.say("  dependency closure: nothing to raise (every enabling symbol is already y)");
    } else {
        c.say(&format!("  dependency closure raised {} symbol(s):", forced.len()));
        for f in &forced {
            c.say(&format!("    {}", f.line()));
        }
    }
    let want = kconfig::expected_y(kconfig::HYPERV_FRAGMENT, &forced);

    // The fragment plus its computed closure, kept as the reviewable artefact:
    // it says what was asked for and what had to be raised to get it.
    let fragfile = c.spec.workdir.join(format!("hyperv-{flavour}.fragment"));
    if let Err(e) = fs::write(&fragfile, kconfig::merged_fragment(kconfig::HYPERV_FRAGMENT, &forced))
    {
        c.say(&format!("  [warn] could not write {}: {e}", fragfile.display()));
    } else {
        c.say(&format!("  fragment + closure: {}", fragfile.display()));
    }

    if c.spec.dry {
        c.say(&format!("  would write {} symbols as =y", want.len()));
        return Ok(forced);
    }

    // Only now. `%prep` is minutes of emulated work and nothing above it needs
    // a prepared tree - the closure is computed from the config FILE. Running
    // it earlier made a dry run do real work, which is the one thing a dry run
    // must never do.
    //
    // The check is restored whether or not %prep succeeded: leaving a weakened
    // gate behind for the build pass is the one outcome that must not happen.
    set_applicability_check(c, true)?;
    let prepped = prep(c, flavour);
    set_applicability_check(c, false)?;
    let tree_host = prepped?;

    let rel = tree_host
        .strip_prefix(build_base(c))
        .map_err(|_| "build tree is not under the work base".to_string())?;
    let in_root = format!("/work/{}", rel.display());

    // Start from the pristine config.
    fs::copy(&cfg_path, tree_host.join(".config"))
        .map_err(|e| format!("seeding .config: {e}"))?;

    // scripts/config, one symbol per call: an argv per symbol rather than a
    // composed shell loop, so a symbol name can never become shell syntax.
    for sym in &want {
        let dotcfg = format!("{in_root}/.config");
        let script = format!("{in_root}/scripts/config");
        chroot_capture(
            &c.spec.buildroot(),
            &[&script, "--file", &dotcfg, "--set-val", sym, "y"],
        )
        .map_err(|e| format!("scripts/config --set-val {sym} y: {e}"))?;
    }
    c.say(&format!("  applied {} symbols with scripts/config", want.len()));

    olddefconfig(c, &in_root, flavour, "1")?;

    // The authority on what the config MEANS. If an edge in the table is wrong
    // or the kernel moved, a target comes back below y and this names it.
    let after = Kconfig::parse(
        &fs::read_to_string(tree_host.join(".config")).map_err(|e| format!("re-reading .config: {e}"))?,
    );
    kconfig::assert_all_y(&after, &want)?;
    c.say(&format!("  all {} symbols survived olddefconfig as =y", want.len()));

    // Photon stores the file without the "Linux/arm64 x.y.z Kernel
    // Configuration" line, which carries the kernel version and would make the
    // file differ from itself on the next release.
    let generated = drop_line_3(
        &fs::read_to_string(tree_host.join(".config")).map_err(|e| format!("{e}"))?,
    );

    // Fixed point: feeding the result back through olddefconfig must change
    // nothing. This is exactly check_for_config_applicability.inc, run now
    // rather than discovered three hours into %build.
    fs::write(tree_host.join(".config"), &generated).map_err(|e| format!("{e}"))?;
    olddefconfig(c, &in_root, flavour, "2")?;
    let again = drop_line_3(
        &fs::read_to_string(tree_host.join(".config")).map_err(|e| format!("{e}"))?,
    );
    if again != generated {
        let d = first_difference(&generated, &again);
        return Err(format!(
            "the generated config is not a fixed point of olddefconfig, so Photon's own \
             check_for_config_applicability would fail this build. First difference: {d}"
        ));
    }
    c.say("  fixed point of olddefconfig confirmed");

    let n_before = before.len();
    let n_after = Kconfig::parse(&generated).len();
    fs::write(&cfg_path, &generated).map_err(|e| format!("{}: {e}", cfg_path.display()))?;
    c.say(&format!(
        "  wrote {} ({n_before} -> {n_after} symbols) for linux-{version}",
        cfg_path.display()
    ));
    // Keep a copy beside the logs: the diff is the reviewable artefact.
    let copy = c.spec.workdir.join(format!("config_{}-hyperv-{flavour}", c.spec.arch.rpm()));
    let _ = fs::write(&copy, &generated);
    Ok(forced)
}

fn olddefconfig(c: &mut Ctx, in_root: &str, flavour: &str, pass: &str) -> Result<(), String> {
    let log = c.spec.workdir.join(format!("olddefconfig-{flavour}-{pass}.log"));
    let arch = format!("ARCH={}", c.spec.arch.kbuild());
    let dir = format!("-C{in_root}");
    // `LC_ALL=` as a make variable is what Photon's own include does; the
    // environment is already scrubbed to C by the chroot runner.
    chroot_logged(
        c,
        &["/usr/bin/make", &dir, &arch, "LC_ALL=", "olddefconfig"],
        &log,
    )
}

/// Photon stores configs without line 3, the kernel-version comment.
fn drop_line_3(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for (i, line) in text.lines().enumerate() {
        if i == 2 {
            continue;
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

fn first_difference(a: &str, b: &str) -> String {
    for (i, (x, y)) in a.lines().zip(b.lines()).enumerate() {
        if x != y {
            return format!("line {}: {:?} vs {:?}", i + 1, x, y);
        }
    }
    format!("lengths {} vs {} lines", a.lines().count(), b.lines().count())
}

/// Bump Release and prepend a changelog entry.
///
/// A config change MUST yield a distinguishable NEVR: without one, the repo
/// metadata, the predicted RPM names and the verify oracle cannot tell the
/// Hyper-V kernel from the stock one, and `tdnf` would consider them the same
/// package.
///
/// `N -> N+1.azure` rather than `N.azure1`: rpmvercmp orders `4.azure.ph5`
/// above `3.ph5` and BELOW an eventual upstream `4.ph5` (because `azure` sorts
/// before `ph5`), so a later official build still upgrades this kernel rather
/// than being blocked by it.
///
/// Idempotent: a Release that already carries `.azure` is left alone, or a
/// resumed run would bump it again every time.
pub fn release_bump(c: &mut Ctx, flavour: &str) -> Result<String, String> {
    let spec = c.spec.photon_tree.join("SPECS/linux").join(format!("{flavour}.spec"));
    let text = fs::read_to_string(&spec).map_err(|e| format!("{}: {e}", spec.display()))?;
    let version = spec_version(c, flavour)?;

    let Some((idx, line)) = text
        .lines()
        .enumerate()
        .find(|(_, l)| l.starts_with("Release:"))
    else {
        return Err(format!("no Release: line in {}", spec.display()));
    };
    let value = line["Release:".len()..].trim();
    if value.contains(".azure") {
        let rel = azure_release(value)?;
        c.say(&format!("  {flavour}: Release already {rel} (idempotent)"));
        return Ok(format!("{version}-{rel}"));
    }
    let bumped = bump_release(value)?;
    let new_rel = azure_release(&bumped)?;
    if c.spec.dry {
        c.say(&format!("  would bump {flavour} Release {value} -> {bumped}"));
        return Ok(format!("{version}-{new_rel}"));
    }

    let author = std::env::var("MC_CHANGELOG_AUTHOR")
        .unwrap_or_else(|_| "Daniel Casota <dcasota@gmail.com>".to_string());
    let entry = format!(
        "* {} {author} {version}-{new_rel}\n- {}: build Hyper-V guest support in \
         (CONFIG_HYPERV, HYPERV_STORAGE, HYPERV_NET, HYPERV_UTILS, HYPERV_BALLOON, \
         HYPERV_VSOCKETS, PCI_HYPERV all =y) for Azure guests\n",
        changelog_date(),
        c.spec.arch.rpm()
    );

    let mut out = String::with_capacity(text.len() + entry.len() + 64);
    for (i, l) in text.lines().enumerate() {
        if i == idx {
            out.push_str(&format!("Release:        {bumped}\n"));
            continue;
        }
        out.push_str(l);
        out.push('\n');
        if l.trim() == "%changelog" {
            out.push_str(&entry);
        }
    }
    if !out.contains(&entry) {
        return Err(format!("{} has no %changelog section", spec.display()));
    }
    fs::write(&spec, out).map_err(|e| format!("{}: {e}", spec.display()))?;
    c.say(&format!("  {flavour}: Release {value} -> {bumped}, changelog entry added"));
    Ok(format!("{version}-{new_rel}"))
}

/// `3%{?acvp_build:.acvp}...` -> `4.azure%{?acvp_build:.acvp}...`
pub fn bump_release(value: &str) -> Result<String, String> {
    let digits: String = value.chars().take_while(|ch| ch.is_ascii_digit()).collect();
    if digits.is_empty() {
        return Err(format!("Release '{value}' does not start with a number"));
    }
    let n: u32 = digits.parse().map_err(|_| format!("Release '{value}' is not a number"))?;
    Ok(format!("{}.azure{}", n + 1, &value[digits.len()..]))
}

/// The Release as it will appear in the RPM name: macros expanded to what this
/// build actually sets (no acvp, no kat, dist .ph5).
pub fn azure_release(value: &str) -> Result<String, String> {
    let base: String = value
        .chars()
        .take_while(|ch| ch.is_ascii_digit() || *ch == '.' || ch.is_ascii_alphabetic())
        .collect();
    let base = base.trim_end_matches('.').to_string();
    if base.is_empty() {
        return Err(format!("cannot read a Release out of '{value}'"));
    }
    Ok(format!("{base}.ph5"))
}

fn changelog_date() -> String {
    // `date` rather than a date crate; the format rpm wants is fixed.
    run("date", &["-u", "+%a %b %d %Y"])
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "Thu Jan 01 1970".to_string())
}

/// The NEVR the tree's spec currently describes, read-only.
///
/// `release_bump` answers the same question but is allowed to WRITE. A stage
/// that only needs to know the name of the kernel it is handling must not be
/// able to change it as a side effect of asking.
pub fn current_vr(c: &Ctx, flavour: &str) -> Result<String, String> {
    let spec = c.spec.photon_tree.join("SPECS/linux").join(format!("{flavour}.spec"));
    let text = fs::read_to_string(&spec).map_err(|e| format!("{}: {e}", spec.display()))?;
    let version = spec_version(c, flavour)?;
    let line = text
        .lines()
        .find(|l| l.starts_with("Release:"))
        .ok_or_else(|| format!("no Release: line in {}", spec.display()))?;
    let value = line["Release:".len()..].trim();
    Ok(format!("{version}-{}", azure_release(value)?))
}

/// The packages the build produced, from the output directory.
pub fn built_rpms(c: &Ctx) -> Result<Vec<PathBuf>, String> {
    let out = rpmtop_host(c).join("RPMS").join(c.spec.arch.rpm());
    let mut v: Vec<PathBuf> = fs::read_dir(&out)
        .map_err(|e| format!("{}: {e}", out.display()))?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "rpm").unwrap_or(false))
        .collect();
    v.sort();
    if v.is_empty() {
        return Err(format!("no RPMs in {}", out.display()));
    }
    Ok(v)
}

/// Compile and package the kernel, resumably, under the disk guard.
///
/// `-bp`, then `-bc --short-circuit` (make is incremental, so a restart
/// continues rather than restarting), then `-bb --noprep` for the packages that
/// reach the media.
pub fn build(c: &mut Ctx, flavour: &str) -> Result<Vec<PathBuf>, String> {
    let sr = format!("photon_subrelease {}", photon_subrelease(&c.spec.photon_tree)?);
    let jobs = format!("_smp_mflags -j{}", c.spec.jobs);
    let spec = format!("/work/rpmbuild/SPECS/{flavour}.spec");

    if c.spec.dry {
        c.say(&format!("  would build {flavour} (-bp, -bc --short-circuit, -bb --noprep)"));
        return Ok(vec![]);
    }
    mount_pseudo(c, &build_base(c))?;

    // Re-stage first: release_bump has just edited the tree's spec and
    // gen_config has rewritten the tree's config, and rpmbuild reads BOTH out
    // of the staged directory rather than out of the tree.
    stage(c)?;

    // The real gate, always, for the pass that decides what ships. If the
    // generated config were not a fixed point this %prep fails - which is
    // exactly what it is for.
    set_applicability_check(c, false)?;

    // %prep, but only if the tree is not already prepared from exactly this
    // spec and config - prep() decides by fingerprint. Deleting the marker
    // unconditionally re-prepped every time, and `rpmbuild -bp` does `rm -rf`
    // on the tree, so a restart threw away every object compiled so far.
    let tree_host = prep(c, flavour)?;

    // The accelerator, if one was built AND it can be proven equivalent.
    // Order matters: the gate compares against objects the MEDIA'S OWN
    // compiler produced in this very tree, so a seeding pass has to run first.
    // Refusing the swap costs time; taking it without the proof costs a kernel
    // nobody can vouch for.
    if c.spec.accel && super::cc1::available(&c.spec.workdir) {
        match accelerate(c, flavour, &tree_host) {
            Ok(true) => c.say("  native cc1 in use for -nostdinc compiles"),
            Ok(false) => c.say("  staying on the media's own compiler"),
            Err(e) => {
                // Never fatal: the slow path is always available and correct.
                c.say(&format!("  [warn] accelerator not used: {e}"));
                let _ = super::cc1::unswap(c);
            }
        }
    } else if c.spec.accel {
        c.say("  no native cross cc1 available; compiling fully emulated");
    }

    let compile = c.spec.marker(&format!("compile-{flavour}"));
    if compile.is_file() {
        c.skip(&format!("compile[{flavour}]"), "already finished");
    } else {
        let log = c.spec.workdir.join(format!("build-{flavour}.log"));
        let argv = rpmbuild_argv("-bc", &["--short-circuit"], &spec, &sr, &jobs);
        c.say(&format!("  rpmbuild -bc {flavour}: the long phase, hours under emulation"));
        run_guarded(c, &argv, &log)?;
        fs::write(&compile, "").map_err(|e| format!("{e}"))?;
    }

    // Release packaging. NOT `-bb --short-circuit`: that stamps
    // `Requires: rpmlib(ShortCircuited)`, which no rpm provides, so tdnf and
    // the installer refuse every package. `-bb --noprep` re-runs %build
    // incrementally (recompiling nothing), then %install and packaging.
    // The payload matches the media: Photon's build-config.json compresses
    // with w19.zstdio and the input ISO's RPMs are zstd.
    let log = c.spec.workdir.join(format!("package-{flavour}.log"));
    let argv = rpmbuild_argv(
        "-bb",
        &[
            "--noprep",
            "--define",
            "_binary_payload w19.zstdio",
            "--define",
            "_source_payload w19.zstdio",
        ],
        &spec,
        &sr,
        &jobs,
    );
    c.say(&format!("  rpmbuild -bb --noprep {flavour}: %install and packaging"));
    run_guarded(c, &argv, &log)?;

    let out = rpmtop_host(c).join("RPMS").join(c.spec.arch.rpm());
    let mut rpms: Vec<PathBuf> = fs::read_dir(&out)
        .map_err(|e| format!("{}: {e}", out.display()))?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "rpm").unwrap_or(false))
        .collect();
    rpms.sort();
    if rpms.is_empty() {
        return Err(format!("rpmbuild reported success but {} is empty", out.display()));
    }
    c.say(&format!("  {} RPM(s) in {}", rpms.len(), out.display()));
    Ok(rpms)
}

/// Compile enough real objects for the byte-identity gate to have evidence.
///
/// These are built by the MEDIA'S OWN compiler, in the real build tree, with
/// the real build flags - which is precisely what makes them a valid reference.
/// A handful of subdirectories spanning scheduler, memory, library and crypto
/// code is a few hundred objects: minutes, against the hours the accelerator
/// then saves on the remaining thousands.
pub fn seed_objects(c: &mut Ctx, flavour: &str, in_root: &str) -> Result<usize, String> {
    let log = c.spec.workdir.join(format!("seed-{flavour}.log"));
    let arch = format!("ARCH={}", c.spec.arch.kbuild());
    let dir = format!("-C{in_root}");
    let jobs = format!("-j{}", c.spec.jobs);
    c.say("  seeding reference objects with the media's own compiler");
    chroot_logged(
        c,
        &[
            "/usr/bin/make",
            &dir,
            &arch,
            &jobs,
            "KBUILD_BUILD_VERSION=1-photon",
            "KBUILD_BUILD_HOST=photon",
            "kernel/",
            "mm/",
            "lib/",
            "crypto/",
        ],
        &log,
    )?;
    Ok(0)
}

/// Seed, gate, and swap in the native compiler only on a clean sweep.
///
/// Returns whether the swap happened. Any doubt returns false: the emulated
/// compiler is slower, but it is the one the media was built with.
fn accelerate(c: &mut Ctx, flavour: &str, tree_host: &Path) -> Result<bool, String> {
    let rel = tree_host
        .strip_prefix(build_base(c))
        .map_err(|_| "build tree is not under the work base".to_string())?;
    let in_root = format!("/work/{}", rel.display());

    let seeded = c.spec.marker(&format!("seed-{flavour}"));
    if !seeded.is_file() {
        seed_objects(c, flavour, &in_root)?;
        fs::write(&seeded, "").map_err(|e| format!("{e}"))?;
    } else {
        c.skip(&format!("seed[{flavour}]"), "reference objects already built");
    }

    let r = super::cc1::gate(c, tree_host, &in_root)?;
    if !r.passed() {
        c.say(&format!(
            "  byte-identity gate REFUSED the native compiler: {}. Compiling fully emulated.",
            r.summary()
        ));
        return Ok(false);
    }
    super::cc1::swap(c, &r)?;
    Ok(true)
}

/// Run a phase in its OWN PROCESS GROUP, watched by the disk guard.
///
/// The group matters: rpmbuild forks make, which forks several hundred
/// compilers, and stopping only the parent leaves all of them running into the
/// wall the guard just detected. The guard pauses and resumes; it never kills,
/// because the build tree is hours of work.
fn run_guarded(c: &mut Ctx, argv: &[&str], log: &Path) -> Result<(), String> {
    use std::os::unix::process::CommandExt;

    let br = c.spec.buildroot();
    let brs = br.to_string_lossy().to_string();
    let mut full: Vec<String> = vec![
        brs,
        "/usr/bin/env".into(),
        "-i".into(),
        "HOME=/root".into(),
        "PATH=/usr/bin:/usr/sbin:/bin:/sbin".into(),
        "LANG=C".into(),
        "LC_ALL=C".into(),
        "TERM=dumb".into(),
        "/usr/bin/nice".into(),
        "-n".into(),
        "10".into(),
    ];
    full.extend(argv.iter().map(|s| s.to_string()));

    let f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log)
        .map_err(|e| format!("{}: {e}", log.display()))?;
    let f2 = f.try_clone().map_err(|e| format!("{e}"))?;
    c.say(&format!("    log: {}", log.display()));

    let mut cmd = Command::new("chroot");
    cmd.args(&full[..]).stdout(Stdio::from(f)).stderr(Stdio::from(f2));
    // Its own process group, so the guard can signal the whole tree.
    unsafe {
        cmd.pre_exec(|| {
            // setpgid(0, 0): become a group leader.
            extern "C" {
                fn setpgid(pid: i32, pgid: i32) -> i32;
            }
            if setpgid(0, 0) != 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = cmd.spawn().map_err(|e| format!("spawning chroot: {e}"))?;
    let pgid = child.id() as i32;

    let stop = Arc::new(AtomicBool::new(false));
    let work = build_base(c);
    let outdir = c
        .spec
        .output
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("/"));
    let guard_log = c.spec.workdir.join("guard.log");
    let stop2 = stop.clone();
    let watcher = std::thread::spawn(move || {
        let t = guard::Thresholds::default();
        let mut paused = false;
        let note = |s: String| {
            if let Ok(mut fh) = fs::OpenOptions::new().create(true).append(true).open(&guard_log) {
                use std::io::Write;
                let _ = writeln!(fh, "{s}");
            }
        };
        while !stop2.load(Ordering::Relaxed) {
            // The build can finish between polls; signalling a recycled pgid
            // would hit whatever inherited it.
            if !guard::group_alive(pgid) {
                break;
            }
            let free = guard::measure(&work, &outdir);
            match guard::decision(&free, paused, &t) {
                Decision::Pause(why) => {
                    if guard::signal_group(pgid, guard::SIGSTOP) {
                        paused = true;
                        note(format!("PAUSED pgid {pgid}: {why}"));
                    }
                }
                Decision::Resume(detail) => {
                    if guard::signal_group(pgid, guard::SIGCONT) {
                        paused = false;
                        note(format!("RESUMED pgid {pgid}: {detail}"));
                    }
                }
                Decision::Continue => {}
            }
            for _ in 0..30 {
                if stop2.load(Ordering::Relaxed) {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_secs(1));
            }
        }
        // Never leave a stopped process group behind.
        if paused {
            let _ = guard::signal_group(pgid, guard::SIGCONT);
            note(format!("RESUMED pgid {pgid}: phase ending"));
        }
    });

    let status = child.wait().map_err(|e| format!("waiting for the build: {e}"));
    stop.store(true, Ordering::Relaxed);
    let _ = watcher.join();
    let status = status?;
    if status.success() {
        return Ok(());
    }
    Err(format!(
        "the build phase failed ({}). Last lines of {}:\n{}",
        status.code().map(|c| c.to_string()).unwrap_or_else(|| "signal".into()),
        log.display(),
        super::tail_of(log, 40)
    ))
}

/// Guards on a package that is about to reach the media.
///
/// Both properties were violated by the obvious way of building these: a
/// short-circuited package carries `rpmlib(ShortCircuited)` and cannot be
/// installed by anything, and a default-compressed one does not match the
/// media's zstd payloads.
pub fn assert_installable(rpm: &Path) -> Result<(), String> {
    let req = run("rpm", &["-qp", "--requires", &rpm.to_string_lossy()])?;
    if req.lines().any(|l| l.contains("rpmlib(ShortCircuited)")) {
        return Err(format!(
            "{} carries Requires: rpmlib(ShortCircuited), which no rpm provides - tdnf and \
             the installer would both refuse it. It came from `rpmbuild -b* --short-circuit`; \
             release packages must come from `-bb --noprep`.",
            rpm.display()
        ));
    }
    let payload = super::rpm_tag(rpm, "PAYLOADCOMPRESSOR")?;
    if payload != "zstd" {
        return Err(format!(
            "{} has a {payload} payload; the media's packages are zstd, so this was built \
             without _binary_payload w19.zstdio",
            rpm.display()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A stage-limited run has to be able to READ the kernel's NEVR without
    /// bumping it. release_bump answers the same question but writes, and a
    /// stage that merely needs the name must not change it by asking.
    #[test]
    fn the_current_nevr_is_readable_without_bumping_the_release() {
        let tmp = std::env::temp_dir().join(format!("shk-curvr-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let specs = tmp.join("photon/SPECS/linux");
        fs::create_dir_all(&specs).unwrap();
        fs::write(
            specs.join("linux.spec"),
            "Name:           linux\nVersion:        6.12.109\n\
             Release:        4.azure%{?acvp_build:.acvp}%{?dist}\n%changelog\n",
        )
        .unwrap();
        fs::write(
            tmp.join("photon/build-config.json"),
            "{\"photon-build-param\": {\"photon-subrelease\": \"92\"}}",
        )
        .unwrap();

        let mut sp = crate::remaster::tests_support::spec();
        sp.photon_tree = tmp.join("photon");
        let mut seen = Vec::new();
        let c = Ctx {
            spec: &sp,
            log: &mut |l: &str| seen.push(l.to_string()),
            old_uname: String::new(),
            new_uname: String::new(),
        };

        assert_eq!(current_vr(&c, "linux").unwrap(), "6.12.109-4.azure.ph5");
        // and the spec is untouched by having been read
        let after = fs::read_to_string(specs.join("linux.spec")).unwrap();
        assert!(after.contains("Release:        4.azure%{?acvp_build:.acvp}%{?dist}"), "{after}");
        assert!(!after.contains("5.azure"), "reading must not bump: {after}");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// %prep is destructive - rpmbuild -bp does `rm -rf` on the tree - so the
    /// decision to re-run it must be keyed on the inputs it consumes. A
    /// fingerprint that ignored the config would skip a needed prep; one that
    /// changed spuriously would discard every compiled object.
    #[test]
    fn the_prep_fingerprint_tracks_the_staged_spec_and_config_and_nothing_else() {
        let tmp = std::env::temp_dir().join(format!("shk-fp-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let specs = tmp.join("photon/SPECS/linux");
        fs::create_dir_all(&specs).unwrap();
        fs::write(specs.join("config_aarch64"), "CONFIG_A=y\n").unwrap();
        fs::write(
            tmp.join("photon/build-config.json"),
            "{\"photon-build-param\": {\"photon-subrelease\": \"92\"}}",
        )
        .unwrap();

        let mut sp = crate::remaster::tests_support::spec();
        sp.photon_tree = tmp.join("photon");
        sp.workdir = tmp.join("work");
        let staged = tmp.join("work/build/rpmbuild");
        fs::create_dir_all(staged.join("SPECS")).unwrap();
        fs::create_dir_all(staged.join("SOURCES")).unwrap();
        fs::write(staged.join("SPECS/linux.spec"), "Release: 4.azure\n").unwrap();
        fs::write(staged.join("SOURCES/config_aarch64"), "CONFIG_A=y\n").unwrap();

        let mut seen = Vec::new();
        let c = Ctx {
            spec: &sp,
            log: &mut |l: &str| seen.push(l.to_string()),
            old_uname: String::new(),
            new_uname: String::new(),
        };

        let a = prep_fingerprint(&c, "linux").unwrap();
        assert_eq!(a.len(), 64, "a sha256 hex digest");
        // Stable across calls: a spurious change discards a compiled tree.
        assert_eq!(a, prep_fingerprint(&c, "linux").unwrap());

        // A changed CONFIG must change it - that is the case that must re-prep.
        fs::write(staged.join("SOURCES/config_aarch64"), "CONFIG_A=y\nCONFIG_HYPERV=y\n").unwrap();
        let b = prep_fingerprint(&c, "linux").unwrap();
        assert_ne!(a, b, "a changed config must force a re-prep");

        // So must a changed Release.
        fs::write(staged.join("SPECS/linux.spec"), "Release: 5.azure\n").unwrap();
        assert_ne!(b, prep_fingerprint(&c, "linux").unwrap());

        let _ = fs::remove_dir_all(&tmp);
    }

    /// rpmbuild reads Source1 out of the STAGED SOURCES directory, not out of
    /// the tree. A marker that skipped re-staging left the build consuming the
    /// pristine config after gen_config had rewritten the tree's copy - a
    /// "successful" build with no Hyper-V support in it. Only the tarballs may
    /// be skipped.
    #[test]
    fn staging_refreshes_the_spec_and_config_even_when_the_tarball_marker_exists() {
        let tmp = std::env::temp_dir().join(format!("shk-restage-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let specs = tmp.join("photon/SPECS/linux");
        fs::create_dir_all(&specs).unwrap();
        fs::write(specs.join("linux.spec"), "Release:        4.azure%{?dist}\n").unwrap();
        fs::write(specs.join("config_aarch64"), "CONFIG_HYPERV=y\n").unwrap();
        fs::create_dir_all(tmp.join("sources")).unwrap();

        let mut sp = crate::remaster::tests_support::spec();
        sp.photon_tree = tmp.join("photon");
        sp.sources = tmp.join("sources");
        sp.workdir = tmp.join("work");
        fs::create_dir_all(&sp.workdir).unwrap();
        // The tarball marker is already present, as on any resumed run.
        fs::write(sp.marker("tarballs"), "").unwrap();

        let mut seen = Vec::new();
        let mut c = Ctx {
            spec: &sp,
            log: &mut |l: &str| seen.push(l.to_string()),
            old_uname: String::new(),
            new_uname: String::new(),
        };
        stage(&mut c).unwrap();

        let staged_cfg = tmp.join("work/build/rpmbuild/SOURCES/config_aarch64");
        let staged_spec = tmp.join("work/build/rpmbuild/SPECS/linux.spec");
        assert_eq!(
            fs::read_to_string(&staged_cfg).unwrap(),
            "CONFIG_HYPERV=y\n",
            "the config the build reads must be the one gen_config wrote"
        );
        assert!(
            fs::read_to_string(&staged_spec).unwrap().contains("4.azure"),
            "the Release bump must reach the staged spec"
        );
        // and the tarball step really was skipped
        assert!(seen.iter().any(|l| l.contains("stage:tarballs")), "{seen:?}");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// The tolerant check must still DO the work - olddefconfig and the line-3
    /// removal - and differ from upstream only in not aborting on the diff.
    /// A version that skipped olddefconfig would leave the tree unprepared and
    /// the computed fixed point meaningless.
    #[test]
    fn the_tolerant_applicability_check_still_runs_olddefconfig_and_only_softens_the_diff() {
        let t = TOLERANT_APPLICABILITY;
        assert!(t.contains("make LC_ALL= olddefconfig"), "{t}");
        assert!(t.contains("sed -i '3d' .config"), "{t}");
        // the diff still runs (it is the useful output) but cannot abort %prep
        assert!(t.contains("diff -u .config.old .config || true"), "{t}");
        // and it must not carry a bare failing diff anywhere
        assert!(
            !t.lines().any(|l| l.trim().starts_with("diff ") && !l.contains("|| true")),
            "a bare diff would abort %prep under set -e: {t}"
        );
    }

    /// rpm 4.18 and rpm 6 lay the build directory out differently, and the two
    /// media this has run against use one each. Hardcoding either makes a
    /// successful `-bp` look like it produced nothing.
    #[test]
    fn the_prepared_tree_is_found_under_both_the_rpm_4_and_rpm_6_layouts() {
        let d = std::env::temp_dir().join(format!("shk-treefind-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);

        // rpm 4.18: _builddir/linux-<ver>
        let flat = d.join("a");
        fs::create_dir_all(flat.join("linux-6.12.109")).unwrap();
        fs::write(flat.join("linux-6.12.109/Makefile"), "x").unwrap();
        assert_eq!(
            find_kernel_tree(&flat, "6.12.109").unwrap(),
            flat.join("linux-6.12.109")
        );

        // rpm 6: _builddir/linux-<ver>-build/linux-<ver>
        let nested = d.join("b");
        let inner = nested.join("linux-6.12.109-build/linux-6.12.109");
        fs::create_dir_all(&inner).unwrap();
        fs::write(inner.join("Makefile"), "x").unwrap();
        assert_eq!(find_kernel_tree(&nested, "6.12.109").unwrap(), inner);

        // A directory of the right NAME but with no Makefile is not a kernel
        // tree - that is the wrapper directory itself.
        let bare = d.join("c");
        fs::create_dir_all(bare.join("linux-6.12.109-build")).unwrap();
        assert!(find_kernel_tree(&bare, "6.12.109").is_none());
        // and the wrong version is not silently accepted
        assert!(find_kernel_tree(&flat, "6.1.128").is_none());

        let _ = fs::remove_dir_all(&d);
    }

    /// N -> N+1.azure, with the spec's conditional macros preserved verbatim.
    /// Losing the `%{?acvp_build:.acvp}` tail would silently change what an
    /// ACVP build produces.
    #[test]
    fn a_release_bump_adds_azure_and_keeps_the_conditional_macros() {
        let v = "3%{?acvp_build:.acvp}%{?kat_build:.kat}%{?dist}";
        let b = bump_release(v).unwrap();
        assert_eq!(b, "4.azure%{?acvp_build:.acvp}%{?kat_build:.kat}%{?dist}");
        assert_eq!(bump_release("12%{?dist}").unwrap(), "13.azure%{?dist}");
        let e = bump_release("%{?dist}").unwrap_err();
        assert!(e.contains("does not start with a number"), "{e}");
    }

    /// The RPM name the bump implies. post_assert and the verify oracle both
    /// predict file names from this, so it has to expand the macros the way
    /// this build sets them.
    #[test]
    fn the_azure_release_expands_to_what_the_rpm_will_be_called() {
        let b = bump_release("3%{?acvp_build:.acvp}%{?kat_build:.kat}%{?dist}").unwrap();
        assert_eq!(azure_release(&b).unwrap(), "4.azure.ph5");
        // and rpmvercmp orders it where the design says it must: above the
        // stock release, below a future official one.
        assert!("4.azure.ph5" > "3.ph5");
        assert!("4.azure.ph5" < "4.ph5", "azure must sort below ph5");
    }

    /// A resumed run must not bump the Release again. The guard is that an
    /// existing `.azure` is recognised, not that the run is tracked.
    #[test]
    fn release_bump_is_idempotent_on_rerun() {
        let already = "4.azure%{?dist}";
        assert!(already.contains(".azure"), "the idempotence test is the substring");
        assert_eq!(azure_release(already).unwrap(), "4.azure.ph5");
        // Bumping an already-bumped value would give 5.azure.azure, which is
        // exactly what the guard prevents.
        assert_eq!(bump_release(already).unwrap(), "5.azure.azure%{?dist}");
    }

    /// Photon stores configs without the kernel-version comment on line 3.
    /// Removing the wrong line silently corrupts the config.
    #[test]
    fn dropping_line_three_removes_the_version_comment_and_nothing_else() {
        let src = "#\n# Automatically generated file\n# Linux/arm64 6.12.109 Kernel Configuration\n#\nCONFIG_A=y\n";
        let out = drop_line_3(src);
        assert!(!out.contains("Kernel Configuration"), "{out}");
        assert!(out.contains("Automatically generated file"), "{out}");
        assert!(out.contains("CONFIG_A=y"), "{out}");
        assert_eq!(out.lines().count(), 4);
    }

    #[test]
    fn a_config_that_is_not_a_fixed_point_reports_the_first_differing_line() {
        let d = first_difference("a\nb\nc\n", "a\nX\nc\n");
        assert!(d.contains("line 2"), "{d}");
        assert!(d.contains("\"b\"") && d.contains("\"X\""), "{d}");
    }

    /// ACVP and KAT configs are FIPS certification artefacts. No flavour may
    /// resolve to one, and a missing file is a typed error rather than a
    /// fallback to the other kernel's config.
    #[test]
    fn kernel_config_path_never_resolves_to_the_acvp_config() {
        let d = std::env::temp_dir().join(format!("shk-cfgpath-{}", std::process::id()));
        let base = d.join("SPECS/linux");
        fs::create_dir_all(base.join("6.1")).unwrap();
        for f in ["config_aarch64", "config-esx_aarch64", "config_x86_64", "config_x86_64_acvp"] {
            fs::write(base.join(f), "CONFIG_A=y\n").unwrap();
        }
        for f in ["config_x86_64-6.1", "config_aarch64-6.1"] {
            fs::write(base.join("6.1").join(f), "CONFIG_A=y\n").unwrap();
        }

        let p = kernel_config_path(&d, super::super::Arch::Aarch64, "linux", 92).unwrap();
        assert!(p.ends_with("config_aarch64"), "{}", p.display());
        let e = kernel_config_path(&d, super::super::Arch::Aarch64, "linux-esx", 92).unwrap();
        assert!(e.ends_with("config-esx_aarch64"), "{}", e.display());

        // Nothing reachable is the ACVP config.
        for arch in [super::super::Arch::X86_64, super::super::Arch::Aarch64] {
            for fl in ["linux", "linux-esx"] {
                for sr in [90u32, 92] {
                    if let Ok(got) = kernel_config_path(&d, arch, fl, sr) {
                        assert!(
                            !got.to_string_lossy().contains("acvp"),
                            "{arch:?}/{fl}/{sr} resolved to {}",
                            got.display()
                        );
                    }
                }
            }
        }
        let _ = fs::remove_dir_all(&d);
    }

    /// The single-source branch selects the 6.1 configs by subrelease. Falling
    /// back to the 6.12 config for a 6.1 build produces a kernel that will not
    /// boot, so the resolver must pick by number and fail loudly.
    #[test]
    fn kernel_config_path_resolves_6_1_single_source_names_by_subrelease() {
        let d = std::env::temp_dir().join(format!("shk-cfg61-{}", std::process::id()));
        let base = d.join("SPECS/linux");
        fs::create_dir_all(base.join("6.1")).unwrap();
        fs::write(base.join("config_aarch64"), "x").unwrap();
        fs::write(base.join("6.1/config_aarch64-6.1"), "x").unwrap();

        let a = kernel_config_path(&d, super::super::Arch::Aarch64, "linux", 90).unwrap();
        assert!(a.ends_with("6.1/config_aarch64-6.1"), "{}", a.display());
        let b = kernel_config_path(&d, super::super::Arch::Aarch64, "linux", 92).unwrap();
        assert!(b.ends_with("config_aarch64"), "{}", b.display());
        assert_ne!(a, b);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_missing_config_file_is_a_typed_error() {
        let d = std::env::temp_dir().join(format!("shk-cfgmiss-{}", std::process::id()));
        fs::create_dir_all(d.join("SPECS/linux")).unwrap();
        let e = kernel_config_path(&d, super::super::Arch::Aarch64, "linux", 92).unwrap_err();
        assert!(e.contains("config_aarch64"), "{e}");
        assert!(e.contains("aarch64") && e.contains("linux"), "{e}");
        let _ = fs::remove_dir_all(&d);
    }

    /// photon_subrelease changes what linux.spec DOES (>= 92 rewrites the
    /// toolchain strings in .config), so an unreadable one must stop the build
    /// rather than default.
    #[test]
    fn the_photon_subrelease_is_read_from_the_tree_and_never_defaulted() {
        let d = std::env::temp_dir().join(format!("shk-sr-{}", std::process::id()));
        fs::create_dir_all(&d).unwrap();
        fs::write(
            d.join("build-config.json"),
            "{\n \"photon-build-param\": {\n  \"photon-subrelease\": \"92\"\n }\n}\n",
        )
        .unwrap();
        assert_eq!(photon_subrelease(&d).unwrap(), 92);

        fs::write(d.join("build-config.json"), "{}\n").unwrap();
        let e = photon_subrelease(&d).unwrap_err();
        assert!(e.contains("photon-subrelease"), "{e}");
        assert!(e.contains("92"), "the message must say why it matters: {e}");
        let _ = fs::remove_dir_all(&d);
    }
}
