//! Patch the Photon OS installer inside the unpacked installer initrd.
//!
//! Two unrelated things live here, and they stay unrelated on purpose:
//!
//! 1. A CRASH in photon-os-installer's kickstart loading. `isoInstaller.py`
//!    evaluates `'live' not in install_config`, but the platform loader returns
//!    `None` when the platform provides no kickstart - which is every
//!    non-VMware platform, Azure included - and `'live' not in None` raises
//!    `TypeError: argument of type 'NoneType' is not a container or iterable`.
//!    The VMware path reaches the same end by falling off `_load_ks_config_vmware`
//!    without a `return` when guestinfo carries neither `data` nor `url`.
//!
//!    Returning `{}` is necessary but NOT sufficient. The caller then stamps
//!    `install_config['live'] = True`, which turns `{}` into a TRUTHY config,
//!    and `installer.configure()` decides whether to run the UI configurator
//!    with `if not install_config and ui_config`. A truthy config skips the UI
//!    and `_check_install_config()` fails with "No disk configured" - a
//!    different failure, not a fix. So the stamp is guarded too.
//!
//! 2. The KERNEL COMMAND LINE of the installed system. POI 2.x has no
//!    kickstart key for kernel parameters, and Azure exposes the VM console as
//!    ttyAMA0 on Arm64, ttyS0 on x86. Without it the installed system boots
//!    with no console that Azure boot diagnostics or the serial console can
//!    read. This is not a bug fix: it is a property of the target, and nothing
//!    upstream will ever supply it.
//!
//! Neither is gated on a VERSION NUMBER. The egg-info in the 5.0 aarch64
//! initrd reads 2.2 while the design note recorded 2.7, so a version gate
//! would be deciding on evidence that disagrees with itself. The SOURCE TEXT
//! decides: the anchor is present (patch it), the patched form is already
//! present (nothing to do), or neither is (a typed error naming the file).
//! That way a medium whose POI already carries the upstream fix is left alone
//! without this code having to know which release that was.

use super::{Arch, Ctx};
use std::fs;
use std::path::{Path, PathBuf};

/// `isoInstaller.py`: stamp `live` only on a real kickstart, so an interactive
/// install keeps a falsy config and still reaches the UI configurator.
const LIVE_ANCHOR: &str = "        # 'live' should be True for iso installs\n        if 'live' not in install_config:";
const LIVE_FIXED: &str = "        # 'live' should be True for iso installs. Only stamp it on an actual\n        # (non-empty) kickstart config. For an interactive install the config\n        # is empty here and must stay falsy, otherwise installer.configure()\n        # ('if not install_config and ui_config') skips the UI configurator\n        # and _check_install_config() fails with \"No disk configured\".\n        if install_config and 'live' not in install_config:";

/// `isoInstaller.py`: a non-VMware platform has no kickstart, which is an
/// interactive install, not `None`.
const PLATFORM_ANCHOR: &str = "        if CommandUtils.is_vmware_virtualization():\n            return self._load_ks_config_vmware(verify=verify)\n        else:\n            return None";
const PLATFORM_FIXED: &str = "        if CommandUtils.is_vmware_virtualization():\n            return self._load_ks_config_vmware(verify=verify)\n        else:\n            # No platform-provided kickstart: fall back to an interactive\n            # install with an empty config. Returning None here makes the\n            # caller crash at \"if 'live' not in install_config\".\n            return {}";

/// `isoInstaller.py`: the VMware path must not fall off the end either.
const VMWARE_ANCHOR: &str = "            print(\n                f\"Failed to run vmtoolsd, do you have open-vm-tools installed? Error: {e}\"\n            )";
const VMWARE_FIXED: &str = "            print(\n                f\"Failed to run vmtoolsd, do you have open-vm-tools installed? Error: {e}\"\n            )\n        # No guestinfo kickstart (data/url both absent) or vmtoolsd missing:\n        # fall back to an interactive install with an empty config instead of\n        # returning None, which would crash at \"if 'live' not in install_config\".\n        return {}";

/// `installer.py`: the installed system's kernel command line.
const CMDLINE_ANCHOR: &str = "        self.poi_kernel_cmdline = \"\"";

/// The replacement for the command line, which depends on the target's console.
///
/// Built from explicit lines rather than a continued literal: this text becomes
/// PYTHON, where the indentation is syntax, and a continued literal carries
/// whatever leading whitespace the Rust source happened to have.
fn cmdline_fixed(arch: Arch) -> String {
    let dev = arch.console();
    [
        format!("        # Azure exposes the VM console as {dev}: boot diagnostics and the"),
        "        # serial console read it, and systemd starts a getty on whatever the".to_string(),
        "        # kernel console is. POI 2.x has no kickstart key for kernel".to_string(),
        "        # parameters, so the installed system would otherwise boot with no".to_string(),
        format!("        # reachable console. The device follows the arch: {dev} here."),
        format!("        self.poi_kernel_cmdline = \"console={dev},115200n8\""),
    ]
    .join("\n")
}

/// What one anchored edit did.
#[derive(Debug, PartialEq, Eq)]
pub enum Edit {
    /// The anchor was found and replaced.
    Applied,
    /// The patched form was already there. A medium whose POI carries the
    /// upstream fix lands here, and that is a success, not a skip.
    AlreadyPresent,
}

/// Apply one anchored edit to a file's text.
///
/// The patched form is checked FIRST, so re-running on an already-patched tree
/// is a no-op rather than an error, and the anchor must then occur EXACTLY
/// once: a second occurrence means the file is not the one this anchor was
/// written against, and replacing "the first one" would be a guess.
pub fn apply(text: &str, anchor: &str, fixed: &str) -> Result<(String, Edit), String> {
    if text.contains(fixed) {
        return Ok((text.to_string(), Edit::AlreadyPresent));
    }
    match text.matches(anchor).count() {
        1 => Ok((text.replacen(anchor, fixed, 1), Edit::Applied)),
        0 => Err(format!(
            "neither the expected code nor the fix is present. The file this \
             anchor was written against has changed:\n---\n{anchor}\n---"
        )),
        n => Err(format!(
            "the anchor occurs {n} times, so replacing one of them would be a \
             guess:\n---\n{anchor}\n---"
        )),
    }
}

/// Locate the installer's `site-packages` inside an unpacked initrd root.
///
/// The python minor version is NOT hard-coded: a 5.0 aarch64 initrd carries
/// python3.14, a different medium carries something else, and a wrong guess
/// presents as "the installer was not patched" only at boot. More than one
/// match is an error rather than a choice.
pub fn site_packages(root: &Path) -> Result<PathBuf, String> {
    let mut found: Vec<PathBuf> = Vec::new();
    for lib in ["usr/lib", "usr/lib64", "lib", "lib64"] {
        let base = root.join(lib);
        let Ok(rd) = fs::read_dir(&base) else { continue };
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if !name.starts_with("python3") {
                continue;
            }
            let sp = e.path().join("site-packages");
            if sp.join("photon_installer").is_dir() && !found.contains(&sp) {
                found.push(sp);
            }
        }
    }
    found.sort();
    match found.len() {
        1 => Ok(found.remove(0)),
        0 => Err(format!(
            "no photon_installer package under {}/usr/lib/python3*/site-packages; \
             this is not the installer initrd",
            root.display()
        )),
        _ => Err(format!(
            "photon_installer appears in {} python trees ({}); patching one of \
             them would leave the other live",
            found.len(),
            found.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")
        )),
    }
}

/// The installer version, read off the egg-info/dist-info directory name.
///
/// REPORTED, never branched on - see the module note. `None` is not an error.
pub fn version(site_packages: &Path) -> Option<String> {
    let rd = fs::read_dir(site_packages).ok()?;
    for e in rd.flatten() {
        let n = e.file_name().to_string_lossy().to_string();
        if !n.starts_with("photon_installer-") {
            continue;
        }
        let rest = n.trim_start_matches("photon_installer-");
        let v = rest.split(&['-', '.'][..]).next().unwrap_or("");
        let ver: String = rest
            .split('-')
            .next()
            .unwrap_or(v)
            .trim_end_matches(".dist")
            .trim_end_matches(".egg")
            .to_string();
        if !ver.is_empty() {
            return Some(ver);
        }
    }
    None
}

/// Patch the installer in an unpacked initrd root. Returns the files changed.
pub fn patch(c: &mut Ctx, root: &Path, arch: Arch) -> Result<usize, String> {
    let sp = site_packages(root)?;
    let pkg = sp.join("photon_installer");
    match version(&sp) {
        Some(v) => c.say(&format!("  installer: photon-installer {v} at {}", pkg.display())),
        None => c.say(&format!("  installer: photon-installer (version unreadable) at {}", pkg.display())),
    }

    let mut changed = 0;

    // The crash: three edits in one file, all or nothing.
    let iso_installer = pkg.join("isoInstaller.py");
    let text = fs::read_to_string(&iso_installer)
        .map_err(|e| format!("{}: {e}", iso_installer.display()))?;
    let mut out = text.clone();
    let mut applied = 0;
    for (what, anchor, fixed) in [
        ("the interactive-install guard on the 'live' stamp", LIVE_ANCHOR, LIVE_FIXED),
        ("the non-VMware platform fallback", PLATFORM_ANCHOR, PLATFORM_FIXED),
        ("the vmtoolsd/guestinfo fallback", VMWARE_ANCHOR, VMWARE_FIXED),
    ] {
        let (next, edit) = apply(&out, anchor, fixed)
            .map_err(|e| format!("{}: {what}: {e}", iso_installer.display()))?;
        out = next;
        if edit == Edit::Applied {
            applied += 1;
        }
    }
    if out != text {
        fs::write(&iso_installer, &out).map_err(|e| format!("{}: {e}", iso_installer.display()))?;
        changed += 1;
        c.say(&format!("  installer: applied {applied} kickstart-loading fix(es) to isoInstaller.py"));
    } else {
        c.say("  installer: isoInstaller.py already handles a missing kickstart");
    }

    // The console: not a bug fix, a property of the target.
    let installer = pkg.join("installer.py");
    let text = fs::read_to_string(&installer).map_err(|e| format!("{}: {e}", installer.display()))?;
    let (out, edit) = apply(&text, CMDLINE_ANCHOR, &cmdline_fixed(arch))
        .map_err(|e| format!("{}: the installed system's kernel command line: {e}", installer.display()))?;
    if edit == Edit::Applied {
        fs::write(&installer, &out).map_err(|e| format!("{}: {e}", installer.display()))?;
        changed += 1;
        c.say(&format!(
            "  installer: the installed system gets console={},115200n8",
            arch.console()
        ));
    } else {
        c.say("  installer: the kernel command line is already set");
    }

    Ok(changed)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A tree shaped like the real initrd, with the UPSTREAM (unpatched) text.
    fn fake_poi(root: &Path, pyver: &str, poi_version: &str) -> PathBuf {
        let sp = root.join(format!("usr/lib/{pyver}/site-packages"));
        let pkg = sp.join("photon_installer");
        fs::create_dir_all(&pkg).unwrap();
        fs::create_dir_all(sp.join(format!("photon_installer-{poi_version}-py3.14.egg-info")))
            .unwrap();
        fs::write(
            pkg.join("isoInstaller.py"),
            format!("import os\n\n{LIVE_ANCHOR}\n            install_config['live'] = True\n\n    def _load_ks_config_platform(self, verify=True):\n{PLATFORM_ANCHOR}\n\n    def _load_ks_config_vmware(self, verify=True):\n        try:\n            pass\n        except Exception as e:\n{VMWARE_ANCHOR}\n"),
        )
        .unwrap();
        fs::write(
            pkg.join("installer.py"),
            format!("class Installer:\n    def __init__(self):\n{CMDLINE_ANCHOR}\n        self.other = 1\n"),
        )
        .unwrap();
        sp
    }

    fn ctx_for<'a>(
        spec: &'a crate::remaster::RemasterSpec,
        log: &'a mut dyn FnMut(&str),
    ) -> Ctx<'a> {
        Ctx { spec, log, old_uname: String::new(), new_uname: String::new() }
    }

    /// The whole point of the guard: an interactive install must keep a FALSY
    /// config. Returning `{}` alone would be stamped into `{'live': True}`,
    /// which is truthy, and the UI configurator would be skipped - trading the
    /// crash for "No disk configured".
    #[test]
    fn the_live_stamp_is_guarded_so_an_empty_config_stays_falsy() {
        assert!(
            LIVE_FIXED.contains("if install_config and 'live' not in install_config:"),
            "the fix must guard on install_config, not merely reorder the test"
        );
        assert!(LIVE_ANCHOR.contains("if 'live' not in install_config:"));
        assert!(!LIVE_ANCHOR.contains("install_config and"));
    }

    /// Both loader paths must return a container. Either one returning None is
    /// the reported TypeError.
    #[test]
    fn both_kickstart_loader_paths_return_a_container_not_none() {
        assert!(PLATFORM_ANCHOR.contains("return None"));
        assert!(!PLATFORM_FIXED.contains("return None"));
        assert!(PLATFORM_FIXED.contains("return {}"));
        // The vmware path has no `return` at all upstream: it falls off the end.
        assert!(!VMWARE_ANCHOR.contains("return"));
        assert!(VMWARE_FIXED.contains("return {}"));
    }

    /// The console device is a property of the architecture. Hard-coding
    /// ttyAMA0 would leave an x86 install with no reachable console.
    #[test]
    fn the_console_argument_follows_the_arch() {
        assert_eq!(Arch::Aarch64.console(), "ttyAMA0");
        assert_eq!(Arch::X86_64.console(), "ttyS0");
        assert!(cmdline_fixed(Arch::Aarch64).contains("console=ttyAMA0,115200n8"));
        assert!(cmdline_fixed(Arch::X86_64).contains("console=ttyS0,115200n8"));
        assert!(!cmdline_fixed(Arch::X86_64).contains("ttyAMA0"));
    }

    /// Patching twice must not double-apply, because a resumed run re-enters
    /// the initrd stage on a tree an earlier run already touched.
    #[test]
    fn patching_an_already_patched_tree_changes_nothing() {
        let d = std::env::temp_dir().join(format!("shk-poi-idem-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fake_poi(&d, "python3.14", "2.2");
        let spec = crate::remaster::tests_support::spec();

        let mut seen: Vec<String> = Vec::new();
        let mut log = |l: &str| seen.push(l.to_string());
        let n = patch(&mut ctx_for(&spec, &mut log), &d, Arch::Aarch64).unwrap();
        assert_eq!(n, 2, "both files change on the first run");

        let sp = d.join("usr/lib/python3.14/site-packages/photon_installer");
        let after_first = fs::read_to_string(sp.join("isoInstaller.py")).unwrap();

        let mut seen2: Vec<String> = Vec::new();
        let mut log2 = |l: &str| seen2.push(l.to_string());
        let n2 = patch(&mut ctx_for(&spec, &mut log2), &d, Arch::Aarch64).unwrap();
        assert_eq!(n2, 0, "the second run is a no-op");
        assert_eq!(after_first, fs::read_to_string(sp.join("isoInstaller.py")).unwrap());
        // exactly one guard, not two stacked ones
        assert_eq!(after_first.matches("if install_config and 'live'").count(), 1);
        assert_eq!(after_first.matches("return {}").count(), 2);
        let _ = fs::remove_dir_all(&d);
    }

    /// NEGATIVE CONTROL. If upstream rewrote the code, silently doing nothing
    /// would ship an ISO that crashes exactly as before. It must be an error
    /// that names the file and shows what was looked for.
    #[test]
    fn a_file_with_neither_the_anchor_nor_the_fix_is_an_error() {
        let e = apply("def main():\n    pass\n", LIVE_ANCHOR, LIVE_FIXED).unwrap_err();
        assert!(e.contains("neither the expected code nor the fix"), "{e}");

        let d = std::env::temp_dir().join(format!("shk-poi-neg-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let sp = fake_poi(&d, "python3.14", "2.2");
        fs::write(sp.join("photon_installer/isoInstaller.py"), "# rewritten upstream\n").unwrap();
        let spec = crate::remaster::tests_support::spec();
        let mut seen: Vec<String> = Vec::new();
        let mut log = |l: &str| seen.push(l.to_string());
        let e = patch(&mut ctx_for(&spec, &mut log), &d, Arch::Aarch64).unwrap_err();
        assert!(e.contains("isoInstaller.py"), "the error names the file: {e}");
        let _ = fs::remove_dir_all(&d);
    }

    /// An anchor that matches twice means this is not the file the anchor was
    /// written against; picking one would be a guess.
    #[test]
    fn an_anchor_that_occurs_twice_is_refused_rather_than_guessed() {
        let doubled = format!("{LIVE_ANCHOR}\n\n{LIVE_ANCHOR}\n");
        let e = apply(&doubled, LIVE_ANCHOR, LIVE_FIXED).unwrap_err();
        assert!(e.contains("occurs 2 times"), "{e}");
    }

    /// The python minor version is discovered, not assumed: a hard-coded
    /// python3.11 would silently patch nothing on a python3.14 medium.
    #[test]
    fn the_python_tree_is_discovered_and_ambiguity_is_refused() {
        let d = std::env::temp_dir().join(format!("shk-poi-sp-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fake_poi(&d, "python3.14", "2.2");
        assert_eq!(
            site_packages(&d).unwrap(),
            d.join("usr/lib/python3.14/site-packages")
        );
        // A second python tree carrying the package: refuse, do not choose.
        fake_poi(&d, "python3.11", "2.2");
        let e = site_packages(&d).unwrap_err();
        assert!(e.contains("2 python trees"), "{e}");

        // No installer at all is also an error, with a reason.
        let empty = d.join("empty");
        fs::create_dir_all(&empty).unwrap();
        assert!(site_packages(&empty).unwrap_err().contains("not the installer initrd"));
        let _ = fs::remove_dir_all(&d);
    }

    /// The version is read for the LOG only. It is recorded here because the
    /// medium says 2.2 while the design note said 2.7 - which is exactly why
    /// nothing branches on it.
    #[test]
    fn the_version_is_read_from_the_egg_info_and_only_reported() {
        let d = std::env::temp_dir().join(format!("shk-poi-ver-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let sp = fake_poi(&d, "python3.14", "2.2");
        assert_eq!(version(&sp).as_deref(), Some("2.2"));

        // An unreadable version must not stop the patch.
        let d2 = std::env::temp_dir().join(format!("shk-poi-ver2-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d2);
        let sp2 = fake_poi(&d2, "python3.14", "2.2");
        fs::remove_dir_all(sp2.join("photon_installer-2.2-py3.14.egg-info")).unwrap();
        assert_eq!(version(&sp2), None);
        let spec = crate::remaster::tests_support::spec();
        let mut seen: Vec<String> = Vec::new();
        let mut log = |l: &str| seen.push(l.to_string());
        assert_eq!(patch(&mut ctx_for(&spec, &mut log), &d2, Arch::Aarch64).unwrap(), 2);
        let _ = fs::remove_dir_all(&d);
        let _ = fs::remove_dir_all(&d2);
    }
}
