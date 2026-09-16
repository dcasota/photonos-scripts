//! Remaster: make an Azure variant of an ISO that already exists.
//!
//! A full Photon build of an aarch64 ISO on an x86_64 host means hundreds of
//! packages under qemu-user at ~13x slowdown - days, not hours. But the ONLY
//! thing an Azure variant changes is the kernel config. So this rebuilds the
//! kernel spec alone, in a build root bootstrapped from the input ISO's own
//! RPMs, and swaps the results into the media.
//!
//! "From the ISO's own RPMs" is the load-bearing part. The kernel has to be
//! compiled by the toolchain generation that produced the rest of the media -
//! at c6db6a0d6 that is gcc 12.5.0, binutils 2.46.1, glibc 2.43, rpm 6.1.0 -
//! because a kernel built against a different glibc/binutils lands modules
//! whose vermagic and build flags do not match the userland around them. The
//! toolchain is therefore READ OFF THE INPUT, never named by this code.
//!
//! The phases are separately resumable because BuildKernel takes hours: a
//! restart must not redo a compile that already finished.

pub mod buildroot;
pub mod cc1;
pub mod guard;
pub mod initrd;
pub mod iso;
pub mod kernel;
pub mod repo;

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Which architecture is being remastered. Carries the three different names
/// the same architecture has in rpm, in the kernel Makefile and in docker,
/// because mixing them up is a whole class of silent failure: `ARCH=aarch64`
/// is not an error to make, it just builds nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Arch {
    X86_64,
    Aarch64,
}

impl Arch {
    pub fn parse(s: &str) -> Result<Self, String> {
        Ok(match s {
            "x86_64" => Arch::X86_64,
            "aarch64" | "arm64" => Arch::Aarch64,
            other => {
                return Err(format!(
                    "unsupported arch '{other}'; valid: x86_64, aarch64"
                ))
            }
        })
    }
    /// The rpm architecture, which is also the RPMS/<dir> on the media.
    pub fn rpm(&self) -> &'static str {
        match self {
            Arch::X86_64 => "x86_64",
            Arch::Aarch64 => "aarch64",
        }
    }
    /// `make ARCH=` - NOT the rpm name.
    pub fn kbuild(&self) -> &'static str {
        match self {
            Arch::X86_64 => "x86",
            Arch::Aarch64 => "arm64",
        }
    }
    /// `docker --platform`.
    pub fn platform(&self) -> &'static str {
        match self {
            Arch::X86_64 => "linux/amd64",
            Arch::Aarch64 => "linux/arm64",
        }
    }
    /// Whether producing this needs qemu-user emulation on this host.
    pub fn emulated_here(&self) -> bool {
        self.rpm() != std::env::consts::ARCH
    }
    /// Where the built kernel image lands in the tree, relative to the build
    /// directory. x86 produces a compressed bzImage, arm64 a flat Image - which
    /// is also why ikconfig extraction is straightforward on arm64 and not on
    /// x86.
    pub fn boot_image(&self) -> &'static str {
        match self {
            Arch::X86_64 => "arch/x86/boot/bzImage",
            Arch::Aarch64 => "arch/arm64/boot/Image",
        }
    }
}

/// One step of the remaster, in execution order.
///
/// Named rather than numbered so a resumed run says which phase it is skipping
/// and why, the way the build cascade's stages do.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    Bootstrap,
    GenConfig,
    BuildKernel,
    Initrd,
    Repo,
    Iso,
    Verify,
}

impl Stage {
    pub fn name(&self) -> &'static str {
        match self {
            Stage::Bootstrap => "bootstrap",
            Stage::GenConfig => "gen-config",
            Stage::BuildKernel => "build-kernel",
            Stage::Initrd => "initrd",
            Stage::Repo => "repo",
            Stage::Iso => "iso",
            Stage::Verify => "verify",
        }
    }
    pub fn parse(s: &str) -> Result<Self, String> {
        Ok(match s {
            "bootstrap" => Stage::Bootstrap,
            "gen-config" => Stage::GenConfig,
            "build-kernel" => Stage::BuildKernel,
            "initrd" => Stage::Initrd,
            "repo" => Stage::Repo,
            "iso" => Stage::Iso,
            "verify" => Stage::Verify,
            other => {
                return Err(format!(
                    "unknown remaster stage '{other}'; valid: bootstrap, gen-config, \
                     build-kernel, initrd, repo, iso, verify"
                ))
            }
        })
    }
    pub fn all() -> Vec<Stage> {
        vec![
            Stage::Bootstrap,
            Stage::GenConfig,
            Stage::BuildKernel,
            Stage::Initrd,
            Stage::Repo,
            Stage::Iso,
            Stage::Verify,
        ]
    }
}

/// Everything a remaster needs, resolved before anything is touched.
#[derive(Debug, Clone)]
pub struct RemasterSpec {
    pub input: PathBuf,
    pub output: PathBuf,
    pub arch: Arch,
    /// Which kernel flavours get the config. Default `linux` only: see the
    /// ESX caveat in `flavours_default`.
    pub flavours: Vec<String>,
    /// A checkout of the Photon release tree AT THE COMMIT THAT BUILT THE
    /// INPUT. The specs have to match the media, or the rebuilt kernel is a
    /// different kernel with the same name.
    pub photon_tree: PathBuf,
    /// Where the declared source tarballs live.
    pub sources: PathBuf,
    /// Scratch. Everything heavy lands here; the disk guard watches it.
    pub workdir: PathBuf,
    /// The container image used to bootstrap the build root.
    pub builder_image: String,
    pub jobs: usize,
    pub dry: bool,
    /// Run only these stages. Empty means all of them.
    pub only: Vec<Stage>,
    /// Permit the native-cc1 accelerator, still gated on byte identity.
    pub accel: bool,
}

/// The default flavour set, and the reason it is one entry.
///
/// The installer offers `linux` and `linux-esx`, and `linux_flavor` defaults to
/// `linux` unless VMware virtualization is detected - so an Azure VM installs
/// the generic kernel without any kickstart override. `linux-esx` additionally
/// needs PTP_1588_CLOCK raised from m to y for HYPERV_UTILS, which is a real
/// change to a VMware-tuned flavour for no benefit on Azure. Opt in explicitly
/// with --hyperv-flavours if that is genuinely wanted.
pub fn flavours_default() -> Vec<String> {
    vec!["linux".to_string()]
}

pub fn parse_flavours(s: &str) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    for f in s.split(',').map(str::trim).filter(|f| !f.is_empty()) {
        match f {
            "linux" | "linux-esx" => {
                if !out.contains(&f.to_string()) {
                    out.push(f.to_string());
                }
            }
            other => {
                return Err(format!(
                    "unknown kernel flavour '{other}'; valid: linux, linux-esx"
                ))
            }
        }
    }
    if out.is_empty() {
        return Err("--hyperv-flavours needs at least one flavour".to_string());
    }
    Ok(out)
}

impl RemasterSpec {
    /// Where the input ISO is mounted read-only.
    pub fn isomnt(&self) -> PathBuf {
        self.workdir.join("isomnt")
    }
    /// The bootstrapped build root.
    pub fn buildroot(&self) -> PathBuf {
        self.workdir.join("buildroot")
    }
    /// A phase-completion marker. Phases are resumable because BuildKernel
    /// takes hours and a restart must not redo a finished compile.
    pub fn marker(&self, name: &str) -> PathBuf {
        self.workdir.join(format!(".{name}.done"))
    }
    pub fn runs(&self, s: Stage) -> bool {
        self.only.is_empty() || self.only.contains(&s)
    }
}

/// The remaster context: the spec plus the one logging closure everything
/// writes through, mirroring `buildexec::Ctx`.
pub struct Ctx<'a> {
    pub spec: &'a RemasterSpec,
    pub log: &'a mut dyn FnMut(&str),
    /// Facts discovered by earlier phases and needed by later ones. Carried
    /// rather than re-derived, so a resumed run cannot disagree with the run
    /// that produced the RPMs.
    pub old_uname: String,
    pub new_uname: String,
}

impl Ctx<'_> {
    pub fn say(&mut self, s: &str) {
        (self.log)(s);
    }
    pub fn skip(&mut self, phase: &str, why: &str) {
        (self.log)(&format!("  [skip] {phase}: {why}"));
    }
}

/// Run a command as an ARGUMENT VECTOR, never a shell string, capturing both
/// streams.
///
/// `cmd | grep -q` under `set -o pipefail` reports SIGPIPE as failure, and a
/// composed shell string is how caller data becomes an injection. Both classes
/// disappear here by construction.
pub fn run(prog: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(prog)
        .args(args)
        .output()
        .map_err(|e| format!("running {prog}: {e}"))?;
    let so = String::from_utf8_lossy(&out.stdout).to_string();
    if out.status.success() {
        Ok(so)
    } else {
        let se = String::from_utf8_lossy(&out.stderr).trim().to_string();
        Err(format!(
            "{prog} {} failed ({}): {}",
            args.join(" "),
            out.status.code().map(|c| c.to_string()).unwrap_or_else(|| "signal".into()),
            if se.is_empty() { so.trim().to_string() } else { se }
        ))
    }
}

/// Whether a command succeeded, for a probe where failure is an answer rather
/// than an error.
pub fn ok(prog: &str, args: &[&str]) -> bool {
    Command::new(prog)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Run a long command, streaming both streams to `logfile` and to the log
/// closure's tail. Returns the exit status as an error with the last lines of
/// output - a multi-hour build that fails must say WHY at the point of
/// failure, not "exit 1".
pub fn run_logged(
    c: &mut Ctx,
    prog: &str,
    args: &[&str],
    logfile: &Path,
) -> Result<(), String> {
    use std::fs::OpenOptions;
    let f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(logfile)
        .map_err(|e| format!("{}: {e}", logfile.display()))?;
    let f2 = f.try_clone().map_err(|e| format!("{}: {e}", logfile.display()))?;
    c.say(&format!("  $ {prog} {}", args.join(" ")));
    c.say(&format!("    log: {}", logfile.display()));
    let st = Command::new(prog)
        .args(args)
        .stdout(Stdio::from(f))
        .stderr(Stdio::from(f2))
        .status()
        .map_err(|e| format!("running {prog}: {e}"))?;
    if st.success() {
        return Ok(());
    }
    let tail = tail_of(logfile, 40);
    Err(format!(
        "{prog} failed ({}). Last lines of {}:\n{tail}",
        st.code().map(|c| c.to_string()).unwrap_or_else(|| "signal".into()),
        logfile.display()
    ))
}

/// The last `n` lines of a file, for an error that names what went wrong.
pub fn tail_of(p: &Path, n: usize) -> String {
    let Ok(text) = std::fs::read_to_string(p) else {
        return format!("(could not read {})", p.display());
    };
    let lines: Vec<&str> = text.lines().collect();
    lines[lines.len().saturating_sub(n)..].join("\n")
}

/// `%{VERSION}-%{RELEASE}` of an RPM file - the uname the kernel will carry.
pub fn rpm_vr(rpm: &Path) -> Result<String, String> {
    let out = run(
        "rpm",
        &["-qp", "--qf", "%{VERSION}-%{RELEASE}", &rpm.to_string_lossy()],
    )?;
    let vr = out.trim().to_string();
    if vr.is_empty() || vr.contains("(none)") {
        return Err(format!("{} has no VERSION-RELEASE", rpm.display()));
    }
    Ok(vr)
}

/// One RPM header tag, as a string.
pub fn rpm_tag(rpm: &Path, tag: &str) -> Result<String, String> {
    Ok(run(
        "rpm",
        &["-qp", "--qf", &format!("%{{{tag}}}"), &rpm.to_string_lossy()],
    )?
    .trim()
    .to_string())
}

/// Facts one phase establishes and later phases consume.
///
/// Carried rather than re-derived: a resumed run must not be able to disagree
/// with the run that produced the RPMs about which kernel they are.
#[derive(Debug, Clone, Default)]
pub struct Produced {
    pub old_vr: String,
    pub new_vr: String,
    pub rpms: Vec<PathBuf>,
    pub forced: Vec<crate::kconfig::Forced>,
    pub sha256: String,
}

/// Drive the whole remaster.
///
/// The phases are ordered by what they depend on, and each one that is skipped
/// says why. `Verify` is not optional in a normal run: an ISO nobody read back
/// is an ISO nobody knows the contents of.
pub fn execute(spec: &RemasterSpec, log: &mut dyn FnMut(&str)) -> Result<Produced, String> {
    let mut c = Ctx { spec, log, old_uname: String::new(), new_uname: String::new() };
    let mut p = Produced::default();
    let flavour = spec
        .flavours
        .first()
        .cloned()
        .ok_or("no kernel flavour selected")?;
    std::fs::create_dir_all(&spec.workdir).map_err(|e| format!("{}: {e}", spec.workdir.display()))?;

    for stage in Stage::all() {
        if !spec.runs(stage) {
            continue;
        }
        c.say(&format!("[{}]", stage.name()));
        match stage {
            Stage::Bootstrap => {
                buildroot::bootstrap(&mut c)?;
                p.old_vr = buildroot::media_kernel_vr(&mut c, &flavour)?;
                c.old_uname = p.old_vr.clone();
                c.say(&format!("  the media carries {flavour} {}", p.old_vr));
            }
            Stage::GenConfig => {
                kernel::stage(&mut c)?;
                for f in &spec.flavours.clone() {
                    p.forced = kernel::gen_config(&mut c, f)?;
                }
            }
            Stage::BuildKernel => {
                for f in &spec.flavours.clone() {
                    p.new_vr = kernel::release_bump(&mut c, f)?;
                    c.new_uname = p.new_vr.clone();
                    c.say(&format!("  building {f} {}", p.new_vr));
                    p.rpms = kernel::build(&mut c, f)?;
                }
                if !spec.dry {
                    for r in &p.rpms {
                        kernel::assert_installable(r)?;
                    }
                    c.say(&format!(
                        "  {} package(s) pass the installability guards",
                        p.rpms.len()
                    ));
                }
            }
            Stage::Initrd => {
                hydrate(&mut c, &mut p, &flavour)?;
                initrd_phase(&mut c, &p)?
            }
            Stage::Repo => {
                hydrate(&mut c, &mut p, &flavour)?;
                repo_phase(&mut c, &p)?
            }
            Stage::Iso => {
                hydrate(&mut c, &mut p, &flavour)?;
                p.sha256 = iso_phase(&mut c, &p)?
            }
            Stage::Verify => {
                hydrate(&mut c, &mut p, &flavour)?;
                verify_phase(&mut c, &p)?
            }
        }
    }
    Ok(p)
}

/// Recover the facts earlier stages would have established, when those stages
/// were not run.
///
/// `--stage initrd,repo,iso,verify` skips Bootstrap and BuildKernel, so the
/// kernel NEVRs and the package list are empty and every later stage fails with
/// "no linux RPM among the built packages". The stages are individually
/// runnable by design - that is what `--stage` is for - so they have to be able
/// to read back what they need instead of depending on having been run in one
/// process.
///
/// Everything here is READ-ONLY and re-derived from the same sources the
/// original stages used: the media for the old NEVR, the tree's spec for the
/// new one, the output directory for the packages.
fn hydrate(c: &mut Ctx, p: &mut Produced, flavour: &str) -> Result<(), String> {
    if c.spec.dry {
        return Ok(());
    }
    if p.old_vr.is_empty() {
        buildroot::ensure_iso_mounted(c)?;
        p.old_vr = buildroot::media_kernel_vr(c, flavour)?;
        c.say(&format!("  recovered: the media carries {flavour} {}", p.old_vr));
    }
    if p.new_vr.is_empty() {
        p.new_vr = kernel::current_vr(c, flavour)?;
        c.say(&format!("  recovered: the rebuilt {flavour} is {}", p.new_vr));
    }
    if p.rpms.is_empty() {
        p.rpms = kernel::built_rpms(c)?;
        c.say(&format!("  recovered: {} built package(s)", p.rpms.len()));
    }
    c.old_uname = p.old_vr.clone();
    c.new_uname = p.new_vr.clone();
    Ok(())
}

/// Which built RPM is the kernel package itself.
pub fn kernel_rpm(rpms: &[PathBuf], flavour: &str, vr: &str) -> Option<PathBuf> {
    let want = format!("{flavour}-{vr}.");
    rpms.iter()
        .find(|p| {
            p.file_name()
                .map(|n| n.to_string_lossy().starts_with(&want))
                .unwrap_or(false)
        })
        .cloned()
}

fn initrd_phase(c: &mut Ctx, p: &Produced) -> Result<(), String> {
    if c.spec.dry {
        c.say("  would rebuild the installer initrd around the new module tree");
        return Ok(());
    }
    let flavour = c.spec.flavours[0].clone();
    let rpm = kernel_rpm(&p.rpms, &flavour, &p.new_vr)
        .ok_or_else(|| format!("no {flavour}-{} RPM among the built packages", p.new_vr))?;
    let work = c.spec.workdir.join("initrd");
    let _ = std::fs::remove_dir_all(&work);
    let root = work.join("root");
    let rpmdir = work.join("rpm");
    let n = initrd::unpack(c, &c.spec.isomnt().join("isolinux/initrd.img"), &root)?;
    c.say(&format!("  unpacked the installer initrd ({n} top-level entries)"));
    initrd::unpack_rpm(c, &rpm, &rpmdir)?;
    let tree = rpmdir.join("lib/modules").join(&p.new_vr);
    initrd::swap_module_tree(c, &root, &p.old_vr, &tree, &p.new_vr)?;
    initrd::depmod(c, &root, &p.new_vr)?;
    let out = c.spec.workdir.join("out/isolinux/initrd.img");
    initrd::repack(c, &root, &out)?;
    Ok(())
}

fn repo_phase(c: &mut Ctx, p: &Produced) -> Result<(), String> {
    if c.spec.dry {
        c.say("  would overlay the RPMS tree and regenerate the metadata");
        return Ok(());
    }
    let flavour = c.spec.flavours[0].clone();
    let srpm = format!("{flavour}-{}.src.rpm", p.old_vr);
    let set = repo::replacement_set(&c.spec.isomnt(), &srpm)?;
    c.say(&format!(
        "  replacement set from the media's own metadata: {}",
        set.iter().map(|x| x.name.clone()).collect::<Vec<_>>().join(", ")
    ));
    // Every package the media built from this SRPM must have been rebuilt, or
    // the repo ends up with a package requiring a version that is gone.
    let built: Vec<String> = p
        .rpms
        .iter()
        .filter_map(|r| r.file_name().map(|n| n.to_string_lossy().to_string()))
        .collect();
    let missing: Vec<&str> = set
        .iter()
        .map(|x| x.name.as_str())
        .filter(|n| !built.iter().any(|b| b.starts_with(&format!("{n}-{}.", p.new_vr))))
        .collect();
    if !missing.is_empty() {
        return Err(format!(
            "the media carries {} package(s) from {srpm} that were not rebuilt: {}. \
             Shipping the old ones would leave unresolvable Requires on the media.",
            missing.len(),
            missing.join(", ")
        ));
    }
    let keep: Vec<PathBuf> = p
        .rpms
        .iter()
        .filter(|r| {
            let n = r.file_name().map(|x| x.to_string_lossy().to_string()).unwrap_or_default();
            set.iter().any(|s| n.starts_with(&format!("{}-{}.", s.name, p.new_vr)))
        })
        .cloned()
        .collect();
    let rd = repo::build_repo(c, &set, &keep)?;
    repo::assert_metadata(&rd, &p.new_vr, &p.old_vr, keep.len())?;
    c.say(&format!("  metadata lists {} rebuilt package(s) and no stale kernel", keep.len()));
    repo::unmount_overlay(c);
    Ok(())
}

fn iso_phase(c: &mut Ctx, p: &Produced) -> Result<String, String> {
    if c.spec.dry {
        c.say("  would write the ISO by replaying the input's boot image");
        return Ok(String::new());
    }
    let flavour = c.spec.flavours[0].clone();
    let srpm = format!("{flavour}-{}.src.rpm", p.old_vr);
    let set = repo::replacement_set(&c.spec.isomnt(), &srpm)?;
    let arch = c.spec.arch.rpm().to_string();
    let out = c.spec.workdir.join("out");

    // /boot files come out of the new kernel RPM, not from the build tree:
    // what the media ships must be what the package ships.
    let rpm = kernel_rpm(&p.rpms, &flavour, &p.new_vr).ok_or("no kernel RPM")?;
    let bootsrc = c.spec.workdir.join("bootfiles");
    let _ = std::fs::remove_dir_all(&bootsrc);
    initrd::unpack_rpm(c, &rpm, &bootsrc)?;

    let mut plan = iso::IsoPlan {
        input: c.spec.input.clone(),
        output: c.spec.output.clone(),
        volid: iso::volid(&c.spec.input)?,
        ..Default::default()
    };
    for s in &set {
        plan.rm.push(format!("/{}", s.href.trim_start_matches('/')));
        let newname = format!("{}-{}.{arch}.rpm", s.name, p.new_vr);
        let src = p
            .rpms
            .iter()
            .find(|r| {
                r.file_name().map(|n| n.to_string_lossy() == newname).unwrap_or(false)
            })
            .ok_or_else(|| format!("{newname} was not built"))?;
        plan.map.push((src.clone(), format!("/RPMS/{arch}/{newname}")));
    }
    plan.rm_r.push("/RPMS/repodata".into());
    plan.map.push((c.spec.workdir.join("repodata-out/repodata"), "/RPMS/repodata".into()));

    for f in ["config", "System.map"] {
        plan.rm.push(format!("/boot/{f}-{}", p.old_vr));
        plan.map.push((
            bootsrc.join(format!("boot/{f}-{}", p.new_vr)),
            format!("/boot/{f}-{}", p.new_vr),
        ));
    }
    plan.rm.push(format!("/boot/linux-{}.cfg", p.old_vr));
    plan.map.push((
        bootsrc.join(format!("boot/linux-{}.cfg", p.new_vr)),
        format!("/boot/linux-{}.cfg", p.new_vr),
    ));
    // The installer kernel IS the packaged kernel; verify asserts they are
    // byte-identical afterwards.
    plan.map.push((
        bootsrc.join(format!("boot/vmlinuz-{}", p.new_vr)),
        "/isolinux/vmlinuz".into(),
    ));
    plan.map.push((out.join("isolinux/initrd.img"), "/isolinux/initrd.img".into()));

    for (src, _) in &plan.map {
        if !src.exists() {
            return Err(format!("{} does not exist; refusing to write a partial ISO", src.display()));
        }
    }
    iso::write(c, &plan)
}

fn verify_phase(c: &mut Ctx, p: &Produced) -> Result<(), String> {
    if c.spec.dry {
        c.say("  would read the finished ISO back and assert the symbols");
        return Ok(());
    }
    // The symbol list. In a full run it is the closure THIS process computed.
    // In a stage-limited run (`--stage verify`) that closure never ran, so fall
    // back to the fragment gen_config recorded, which carries the fragment plus
    // its computed closure. Falling back to the bare fragment would silently
    // assert seven symbols instead of ten and call that a pass.
    let want = if p.forced.is_empty() {
        let f = c.spec.workdir.join(format!("hyperv-{}.fragment", c.spec.flavours[0]));
        match std::fs::read_to_string(&f) {
            Ok(text) => {
                let syms: Vec<String> = crate::kconfig::fragment_symbols(&text)
                    .into_iter()
                    .map(|(s, _)| s)
                    .collect();
                c.say(&format!("  symbol list from {} ({} symbols)", f.display(), syms.len()));
                syms
            }
            Err(e) => {
                c.say(&format!(
                    "  [warn] no recorded fragment at {} ({e}); asserting only the \
                     fragment's own symbols, NOT the computed closure",
                    f.display()
                ));
                crate::kconfig::expected_y(crate::kconfig::HYPERV_FRAGMENT, &[])
            }
        }
    } else {
        crate::kconfig::expected_y(crate::kconfig::HYPERV_FRAGMENT, &p.forced)
    };
    let r = crate::oracle::media_hyperv(
        &c.spec.output,
        c.spec.arch.rpm(),
        &c.spec.flavours[0],
        &want,
        &p.old_vr,
    )?;
    for line in r.lines() {
        c.say(&format!("  {line}"));
    }
    Ok(())
}

#[cfg(test)]
pub mod tests_support {
    use super::*;
    /// A spec pointing at scratch paths, for unit tests that need a Ctx but
    /// touch no real tree.
    pub fn spec() -> RemasterSpec {
        RemasterSpec {
            input: "/in.iso".into(),
            output: "/out.iso".into(),
            arch: Arch::Aarch64,
            flavours: flavours_default(),
            photon_tree: "/photon".into(),
            sources: "/sources".into(),
            workdir: std::env::temp_dir().join("shk-remaster-test"),
            builder_image: "photon:5.0-arm64".into(),
            jobs: 2,
            dry: false,
            only: vec![],
            accel: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// aarch64 has three names and they are not interchangeable. `ARCH=aarch64`
    /// is not rejected by the kernel Makefile, it simply builds the wrong
    /// thing, so the mapping is pinned here rather than spelled at each call.
    #[test]
    fn each_arch_knows_its_rpm_kbuild_and_docker_names_separately() {
        assert_eq!(Arch::Aarch64.rpm(), "aarch64");
        assert_eq!(Arch::Aarch64.kbuild(), "arm64");
        assert_eq!(Arch::Aarch64.platform(), "linux/arm64");
        assert_eq!(Arch::Aarch64.boot_image(), "arch/arm64/boot/Image");
        assert_eq!(Arch::X86_64.rpm(), "x86_64");
        assert_eq!(Arch::X86_64.kbuild(), "x86");
        assert_eq!(Arch::X86_64.boot_image(), "arch/x86/boot/bzImage");
        // `arm64` is accepted as an input spelling because it is what the
        // kernel calls it, but it normalises to the rpm name.
        assert_eq!(Arch::parse("arm64").unwrap(), Arch::Aarch64);
        let e = Arch::parse("ppc64le").unwrap_err();
        assert!(e.contains("ppc64le") && e.contains("aarch64"), "{e}");
    }

    /// The default targets the generic flavour ONLY. linux-esx would need
    /// PTP_1588_CLOCK raised on a VMware-tuned kernel for no gain on Azure, so
    /// it has to be asked for by name.
    #[test]
    fn hyperv_flavours_default_to_linux_only() {
        assert_eq!(flavours_default(), vec!["linux".to_string()]);
        assert_eq!(parse_flavours("linux").unwrap(), vec!["linux".to_string()]);
        assert_eq!(
            parse_flavours("linux,linux-esx").unwrap(),
            vec!["linux".to_string(), "linux-esx".to_string()]
        );
        // Duplicates collapse rather than building the same spec twice.
        assert_eq!(parse_flavours("linux,linux").unwrap().len(), 1);
        let e = parse_flavours("linux-rt").unwrap_err();
        assert!(e.contains("linux-rt"), "{e}");
        assert!(parse_flavours("").is_err(), "an empty list is not a default");
    }

    #[test]
    fn a_stage_list_round_trips_through_its_names() {
        for s in Stage::all() {
            assert_eq!(Stage::parse(s.name()).unwrap(), s);
        }
        let e = Stage::parse("remaster").unwrap_err();
        assert!(e.contains("remaster") && e.contains("build-kernel"), "{e}");
    }

    /// An empty `only` means every stage, not no stages - the difference
    /// between a full run and a silent no-op.
    #[test]
    fn an_empty_stage_filter_runs_everything() {
        let mut sp = spec_for_test();
        assert!(Stage::all().iter().all(|s| sp.runs(*s)));
        sp.only = vec![Stage::Iso];
        assert!(sp.runs(Stage::Iso));
        assert!(!sp.runs(Stage::BuildKernel));
    }

    fn spec_for_test() -> RemasterSpec {
        RemasterSpec {
            input: "/in.iso".into(),
            output: "/out.iso".into(),
            arch: Arch::Aarch64,
            flavours: flavours_default(),
            photon_tree: "/photon".into(),
            sources: "/sources".into(),
            workdir: "/work".into(),
            builder_image: "photon:5.0-arm64".into(),
            jobs: 4,
            dry: false,
            only: vec![],
            accel: true,
        }
    }

    /// A failing argv runner must report the command and the reason, because a
    /// bare "exit 1" from a phase that ran for hours is not actionable.
    #[test]
    fn a_failed_command_names_itself_and_its_output() {
        let e = run("false", &[]).unwrap_err();
        assert!(e.contains("false"), "{e}");
        assert!(ok("true", &[]));
        assert!(!ok("false", &[]));
        // A missing binary is a different failure from a failing one.
        let missing = run("sharukhan-no-such-binary-xyz", &[]).unwrap_err();
        assert!(missing.contains("sharukhan-no-such-binary-xyz"), "{missing}");
    }
}
