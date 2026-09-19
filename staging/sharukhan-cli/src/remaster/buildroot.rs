//! Bootstrap a build root from the INPUT ISO's own RPMs.
//!
//! Not from a published container image, and not from the newest packages: the
//! kernel has to be compiled by the toolchain generation that produced the rest
//! of the media. A kernel built against a different glibc or binutils ships
//! modules whose vermagic and build flags disagree with the userland around
//! them, and the failure shows up at boot rather than at build time.
//!
//! So the package set is installed with `tdnf --installroot` from a repo
//! pointed at the mounted ISO, and the resulting toolchain is REPORTED with
//! versions rather than assumed. On the 6.12.109-3 aarch64 media that is gcc
//! 12.5.0, binutils 2.46.1, glibc 2.43, rpm 6.1.0, kmod 34.1 - all different
//! from the 6.1.128 media the proof of concept used, which is exactly why this
//! reads them instead of naming them.

use super::{ok, run, run_logged, Ctx};
use std::fs;
use std::path::Path;

/// linux.spec's BuildRequires plus the base tooling rpmbuild itself needs.
///
/// Taken from the spec at the commit that built the input, not from a list
/// someone maintained by hand: every name here appears either in a
/// `BuildRequires:` line or in the set `rpmbuild` cannot run without. The
/// x86_64-only ones (pciutils-devel, libcap-devel) are absent because this
/// list is shared and the spec guards them with `%ifarch`; a missing package
/// is reported by tdnf rather than silently skipped.
pub const BUILD_REQUIRES: &[&str] = &[
    // rpmbuild and the shell it runs scriptlets in
    "bash",
    "coreutils",
    "filesystem",
    "photon-release",
    "rpm",
    "rpm-build",
    "tdnf",
    // the toolchain
    "gcc",
    "glibc-devel",
    "binutils",
    "make",
    "patch",
    "which",
    "perl",
    // archive and text tools %prep and %install use
    "tar",
    "xz",
    "gzip",
    "bzip2",
    "cpio",
    "diffutils",
    "findutils",
    "gawk",
    "grep",
    "sed",
    "file",
    "util-linux",
    "kmod",
    // linux.spec BuildRequires
    "bc",
    "mpc-devel",
    "kmod-devel",
    "glib-devel",
    "elfutils-devel",
    "openssl-devel",
    "procps-ng-devel",
    "audit-devel",
    "elfutils-libelf-devel",
    "binutils-devel",
    "xz-devel",
    "slang-devel",
    "python3-devel",
    "python3-setuptools",
    "cmake",
    "bison",
    "flex",
    "dwarves-devel",
    "gmp-devel",
    "mpfr-devel",
    "libtraceevent-devel",
    "clang-devel",
    "readline-devel",
    "gdb",
    "zlib-devel",
    // the kernel config step needs the userspace headers present
    "linux-api-headers",
    // the repo phase runs inside the same root on an emulated host
    "createrepo_c",
];

/// The toolchain components whose versions are reported, because a
/// version-skewed one presents exactly like a broken build.
const TOOLCHAIN: &[&str] = &["gcc", "binutils", "glibc", "rpm", "kmod", "dwarves", "make"];

/// Mount the input ISO read-only, if it is not already.
///
/// Read-only and by loop device: the input must be unmodifiable by
/// construction, because it is also the fallback if the remaster goes wrong.
pub fn ensure_iso_mounted(c: &mut Ctx) -> Result<(), String> {
    let mnt = c.spec.isomnt();
    let input = c.spec.input.clone();
    if !input.is_file() {
        return Err(format!("input ISO {} is not a file", input.display()));
    }
    fs::create_dir_all(&mnt).map_err(|e| format!("{}: {e}", mnt.display()))?;
    if ok("mountpoint", &["-q", &mnt.to_string_lossy()]) {
        c.say(&format!("  {} already mounted", mnt.display()));
        return Ok(());
    }
    if c.spec.dry {
        c.say(&format!(
            "  would mount {} at {}",
            input.display(),
            mnt.display()
        ));
        return Ok(());
    }
    run(
        "mount",
        &[
            "-o",
            "loop,ro",
            &input.to_string_lossy(),
            &mnt.to_string_lossy(),
        ],
    )?;
    // Prove it is the media that was asked for, not a stale mount.
    let rpms = mnt.join("RPMS").join(c.spec.arch.rpm());
    if !rpms.is_dir() {
        return Err(format!(
            "{} has no RPMS/{} directory: this is not a Photon {} ISO",
            input.display(),
            c.spec.arch.rpm(),
            c.spec.arch.rpm()
        ));
    }
    let n = fs::read_dir(&rpms).map(|d| d.count()).unwrap_or(0);
    c.say(&format!(
        "  mounted {} at {} ({n} RPMs)",
        input.display(),
        mnt.display()
    ));
    Ok(())
}

/// The kernel NEVR the input media carries: the uname the remaster replaces.
///
/// Read off the media, never assumed. The whole remaster keys on this string,
/// and guessing it produces an ISO that silently keeps its old kernel.
pub fn media_kernel_vr(c: &mut Ctx, flavour: &str) -> Result<String, String> {
    let dir = c.spec.isomnt().join("RPMS").join(c.spec.arch.rpm());
    let prefix = format!("{flavour}-");
    let mut hits: Vec<String> = fs::read_dir(&dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .flatten()
        .filter_map(|e| e.file_name().to_str().map(str::to_string))
        .filter(|n| {
            // `linux-` must not match `linux-devel-`: the next field after the
            // prefix has to be the version.
            n.strip_prefix(&prefix)
                .map(|r| r.starts_with(|ch: char| ch.is_ascii_digit()))
                .unwrap_or(false)
                && n.ends_with(".rpm")
        })
        .collect();
    hits.sort();
    match hits.len() {
        0 => Err(format!(
            "no {flavour} package on the media under {}; this ISO cannot be remastered \
             for a flavour it does not ship",
            dir.display()
        )),
        1 => super::rpm_vr(&dir.join(&hits[0])),
        _ => Err(format!(
            "{} {flavour} packages on the media ({}); the one to replace is ambiguous",
            hits.len(),
            hits.join(", ")
        )),
    }
}

/// Install the build set into `spec.buildroot()` from the ISO's own repo.
///
/// Idempotent: a completed bootstrap leaves a marker, because this takes
/// several minutes under emulation and a resumed run must not redo it.
pub fn bootstrap(c: &mut Ctx) -> Result<(), String> {
    let br = c.spec.buildroot();
    let marker = c.spec.marker("bootstrap");
    if marker.is_file() {
        c.skip("bootstrap", &format!("{} exists", marker.display()));
        report_toolchain(c)?;
        return Ok(());
    }
    ensure_iso_mounted(c)?;
    fs::create_dir_all(&br).map_err(|e| format!("{}: {e}", br.display()))?;

    if c.spec.dry {
        c.say(&format!(
            "  would install {} packages into {} from the ISO repo",
            BUILD_REQUIRES.len(),
            br.display()
        ));
        return Ok(());
    }

    let mnt = c.spec.isomnt();
    let iso_bind = format!("{}:/iso:ro", mnt.display());
    let br_bind = format!("{}:/br", br.display());
    // rpm 6.x runs scriptlets through an unshare plugin that an unprivileged
    // container is not permitted to use. Disabling it for this ephemeral
    // container only is the difference between a bootstrap and a wall of
    // "failed to unshare" scriptlet errors.
    let script = format!(
        "set -e; echo '%__transaction_unshare %{{nil}}' > /etc/rpm/macros.nounshare; \
         tdnf -y --installroot /br --releasever 5.0 --nogpgcheck --disablerepo='*' \
         --repofrompath iso,file:///iso/RPMS --enablerepo=iso install {}; \
         tdnf --installroot /br clean all",
        BUILD_REQUIRES.join(" ")
    );
    let log = c.spec.workdir.join("bootstrap.log");
    c.say(&format!(
        "  installing {} packages into {} from the input ISO's own repo",
        BUILD_REQUIRES.len(),
        br.display()
    ));
    let platform = c.spec.arch.platform().to_string();
    let image = c.spec.builder_image.clone();
    run_logged(
        c,
        "docker",
        &[
            "run",
            "--rm",
            "--platform",
            &platform,
            "-v",
            &iso_bind,
            "-v",
            &br_bind,
            &image,
            "sh",
            "-c",
            &script,
        ],
        &log,
    )?;

    // The same rpm 6 unshare problem applies to rpmbuild INSIDE this root,
    // which is where the kernel is actually built.
    let macros_dir = br.join("etc/rpm");
    fs::create_dir_all(&macros_dir).map_err(|e| format!("{}: {e}", macros_dir.display()))?;
    fs::write(
        macros_dir.join("macros.nounshare"),
        "%__transaction_unshare %{nil}\n",
    )
    .map_err(|e| format!("writing macros.nounshare: {e}"))?;

    report_toolchain(c)?;
    fs::write(&marker, "").map_err(|e| format!("{}: {e}", marker.display()))?;
    Ok(())
}

/// Report the toolchain the root actually got, with versions.
///
/// "Print measured values, never a bare OK/FAIL": a build root that came up
/// with the wrong gcc is indistinguishable from a healthy one until the kernel
/// modules fail to load, hours later.
pub fn report_toolchain(c: &mut Ctx) -> Result<(), String> {
    let br = c.spec.buildroot();
    if !br.join("usr/bin/gcc").exists() {
        return Err(format!(
            "{} has no usr/bin/gcc: the bootstrap did not produce a usable build root",
            br.display()
        ));
    }
    let mut seen = Vec::new();
    for pkg in TOOLCHAIN {
        let v = chroot_capture(
            &br,
            &["/usr/bin/rpm", "-q", "--qf", "%{VERSION}-%{RELEASE}", pkg],
        )
        .unwrap_or_else(|_| "ABSENT".to_string());
        seen.push(format!("{pkg} {}", v.trim()));
    }
    c.say(&format!("  toolchain from the media: {}", seen.join(", ")));
    // The architecture is the one property a wrong answer here would make
    // catastrophic and invisible, so it is proved by running something.
    let m = chroot_capture(&br, &["/usr/bin/uname", "-m"])?;
    let want = c.spec.arch.rpm();
    if m.trim() != want {
        return Err(format!(
            "the build root reports uname -m = {} but {want} was requested; \
             qemu-user binfmt for {want} is not registered, or the root is the wrong arch",
            m.trim()
        ));
    }
    c.say(&format!(
        "  build root executes as {} (qemu-user binfmt)",
        m.trim()
    ));
    Ok(())
}

/// The environment every chroot command runs with.
///
/// `env -i` on purpose: the host's LANG, LC_ALL and PATH leak into the build
/// otherwise, and `make olddefconfig` in particular sorts differently under a
/// non-C locale - which silently produces a config that is not a fixed point.
fn chroot_argv<'a>(br: &'a str, argv: &[&'a str]) -> Vec<&'a str> {
    let mut v = vec![
        br,
        "/usr/bin/env",
        "-i",
        "HOME=/root",
        "PATH=/usr/bin:/usr/sbin:/bin:/sbin",
        "LANG=C",
        "LC_ALL=C",
        "TERM=dumb",
    ];
    v.extend_from_slice(argv);
    v
}

/// Run a command inside the build root and return its stdout.
pub fn chroot_capture(br: &Path, argv: &[&str]) -> Result<String, String> {
    let brs = br.to_string_lossy().to_string();
    run("chroot", &chroot_argv(&brs, argv))
}

/// Run a command inside the build root, streaming to a log.
pub fn chroot_logged(c: &mut Ctx, argv: &[&str], log: &Path) -> Result<(), String> {
    let br = c.spec.buildroot();
    let brs = br.to_string_lossy().to_string();
    let full = chroot_argv(&brs, argv);
    run_logged(c, "chroot", &full, log)
}

/// Bind-mount the pseudo-filesystems rpmbuild needs, and the work tree.
///
/// Idempotent, and it never unmounts anything it did not mount: this runs on a
/// host with other people's work on it.
pub fn mount_pseudo(c: &mut Ctx, work: &Path) -> Result<(), String> {
    let br = c.spec.buildroot();
    for (what, kind, at) in [
        ("proc", "-t", "proc"),
        ("/dev", "--bind", "dev"),
        ("/sys", "--bind", "sys"),
    ] {
        let target = br.join(at);
        fs::create_dir_all(&target).map_err(|e| format!("{}: {e}", target.display()))?;
        if ok("mountpoint", &["-q", &target.to_string_lossy()]) {
            continue;
        }
        let ts = target.to_string_lossy().to_string();
        let args: Vec<&str> = if kind == "-t" {
            vec!["-t", "proc", "proc", &ts]
        } else {
            vec!["--bind", what, &ts]
        };
        run("mount", &args)?;
        c.say(&format!("  mounted {what} at {}", target.display()));
    }
    // The build tree lives outside the root so it can be measured, guarded and
    // kept across a rebuild of the root itself.
    let target = br.join("work");
    fs::create_dir_all(&target).map_err(|e| format!("{}: {e}", target.display()))?;
    fs::create_dir_all(work).map_err(|e| format!("{}: {e}", work.display()))?;
    if !ok("mountpoint", &["-q", &target.to_string_lossy()]) {
        run(
            "mount",
            &["--bind", &work.to_string_lossy(), &target.to_string_lossy()],
        )?;
        c.say(&format!(
            "  mounted {} at {}",
            work.display(),
            target.display()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The package list is the spec's, and a few entries carry the whole
    /// build: dropping dwarves-devel loses BTF, dropping linux-api-headers
    /// breaks the config step, and neither fails in a way that names itself.
    #[test]
    fn the_build_set_carries_the_packages_whose_absence_fails_late() {
        for p in [
            "dwarves-devel",
            "linux-api-headers",
            "elfutils-libelf-devel",
            "openssl-devel",
            "bc",
            "rpm-build",
            "cmake",
            "clang-devel",
        ] {
            assert!(BUILD_REQUIRES.contains(&p), "{p} must be in the build set");
        }
        // x86_64-only BuildRequires must NOT be in the shared list: the spec
        // guards them with %ifarch and tdnf would fail the whole bootstrap.
        for p in ["pciutils-devel", "libcap-devel"] {
            assert!(!BUILD_REQUIRES.contains(&p), "{p} is x86_64-only");
        }
        // No duplicates: tdnf tolerates them, but a duplicate is a sign the
        // list was edited twice for the same reason.
        let mut sorted = BUILD_REQUIRES.to_vec();
        sorted.sort_unstable();
        let before = sorted.len();
        sorted.dedup();
        assert_eq!(before, sorted.len(), "duplicate entries in BUILD_REQUIRES");
    }

    /// `linux-` must not match `linux-devel-`. Getting this wrong makes the
    /// media kernel version ambiguous and the remaster replaces the wrong set.
    #[test]
    fn the_media_kernel_lookup_does_not_match_a_subpackage() {
        let name_matches = |n: &str, prefix: &str| -> bool {
            n.strip_prefix(prefix)
                .map(|r| r.starts_with(|ch: char| ch.is_ascii_digit()))
                .unwrap_or(false)
                && n.ends_with(".rpm")
        };
        assert!(name_matches("linux-6.12.109-3.ph5.aarch64.rpm", "linux-"));
        assert!(!name_matches(
            "linux-devel-6.12.109-3.ph5.aarch64.rpm",
            "linux-"
        ));
        assert!(!name_matches(
            "linux-esx-6.12.109-3.ph5.aarch64.rpm",
            "linux-"
        ));
        assert!(name_matches(
            "linux-esx-6.12.109-3.ph5.aarch64.rpm",
            "linux-esx-"
        ));
        // and a non-rpm file with the right prefix is not a package
        assert!(!name_matches(
            "linux-6.12.109-3.ph5.aarch64.rpm.sha256",
            "linux-"
        ));
    }

    /// Every chroot command runs under `env -i` with LC_ALL=C. A leaked locale
    /// makes `olddefconfig` order differently, which turns the fixed-point
    /// check into a spurious failure - or, worse, passes and ships a config
    /// that is not what the next build would produce.
    #[test]
    fn chroot_commands_run_with_a_scrubbed_c_locale_environment() {
        let argv = chroot_argv("/br", &["/usr/bin/make", "olddefconfig"]);
        assert_eq!(argv[0], "/br");
        assert_eq!(argv[1], "/usr/bin/env");
        assert_eq!(argv[2], "-i", "the host environment must not leak in");
        assert!(argv.contains(&"LC_ALL=C"), "{argv:?}");
        assert!(argv.contains(&"LANG=C"), "{argv:?}");
        assert_eq!(argv[argv.len() - 2], "/usr/bin/make");
        assert_eq!(argv[argv.len() - 1], "olddefconfig");
    }
}
