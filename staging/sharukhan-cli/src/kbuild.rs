//! ISO builds with a kernel from a wrapper profile (`--kernel 7.3-rc4`).
//!
//! A derived wrapper (`sharukhan wrapper derive`) turns Photon 5.0 into a tree
//! for another kernel: its pin script rewrites the kernel specs, enables the
//! rebased patch sets and, for a canister build, the FIPS series its profile
//! names. The cascade runs that same pin script as one injection instead of
//! the wrapper's own driver, so a kernel build gets everything the cascade
//! does (purge between phases, verified sources, retries) and nothing is
//! re-implemented.
//!
//! Such a build never touches the trees of other builds: it runs in its own
//! root (`$MC_WORK/kbuild/<kernel>`), with its own ISO cache and variant
//! patch directories. `/root/common` and `/root/experimental/*` belong to
//! whoever else builds on this host.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::config::Config;
use crate::wrapper::base::Base;
use crate::wrapper::derive;
use crate::wrapper::profile::Profile;

/// Everything a kernel-profile build needs, resolved from the profile.
#[derive(Debug, Clone)]
pub struct KernelBuild {
    /// The profile's release, e.g. `7.3-rc4`.
    pub name: String,
    pub profile_path: PathBuf,
    pub profile: Profile,
    /// The release branch the profile's patches live on.
    pub branch: String,
    /// The NEVR `linux` builds to - and the canister it builds carries.
    pub nevr: String,
    /// The derived wrapper's pin script (its EMBEDPIN heredoc).
    pub pins: String,
    /// Packages the derived wrapper builds before `make image`.
    pub prebuild: Vec<String>,
    /// The Photon release whose userland the build keeps (e.g. `5.0`): where
    /// a published canister would be.
    pub userland: String,
}

/// sharukhan-cli's own directory: profiles and the base wrapper live beside it.
fn cli_dir() -> PathBuf {
    std::env::var_os("SHARUKHAN_CLI_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")))
}

/// The heredoc body between `cat > "$PINOUT" << 'EMBEDPIN'` and `EMBEDPIN`.
pub fn pin_script(wrapper: &str) -> Result<String, String> {
    const OPEN: &str = "cat > \"$PINOUT\" << 'EMBEDPIN'\n";
    const CLOSE: &str = "\nEMBEDPIN\n";
    let start = wrapper
        .find(OPEN)
        .ok_or("the derived wrapper has no EMBEDPIN pin script")?
        + OPEN.len();
    let len = wrapper[start..]
        .find(CLOSE)
        .ok_or("the derived wrapper's pin script is never closed")?;
    if wrapper[start + len + CLOSE.len()..].contains(OPEN) {
        return Err("the derived wrapper has two pin scripts".into());
    }
    let body = &wrapper[start..start + len + 1];
    if !body.contains("\nworktree_now\n") {
        return Err("the pin script does not run worktree_now".into());
    }
    Ok(body.to_string())
}

/// The `pkgs="..."` list of the wrapper's pre-build, in its order.
pub fn prebuild_packages(wrapper: &str) -> Result<Vec<String>, String> {
    derive::pkgs_list(wrapper).map_err(|e| format!("the wrapper's pre-build list: {e}"))
}

pub fn load(name: &str) -> Result<KernelBuild, String> {
    let dir = cli_dir();
    let profile_path = std::env::var_os("SHARUKHAN_WRAPPER_PROFILES")
        .map(PathBuf::from)
        .unwrap_or_else(|| dir.join("profiles/kernel"))
        .join(format!("{name}.json"));
    let profile = Profile::load(&profile_path).map_err(|e| e.to_string())?;
    let target = profile.release().map_err(|e| e.to_string())?;
    if target.ksrc() != name {
        return Err(format!(
            "{} is the profile of {}, not {name}",
            profile_path.display(),
            target.ksrc()
        ));
    }
    let base_path = dir.join("..").join(&profile.base.script);
    let base_text =
        fs::read_to_string(&base_path).map_err(|e| format!("{}: {e}", base_path.display()))?;
    let base = Base::parse(&base_text).map_err(|e| e.to_string())?;
    let derived = derive::derive_text(&base_text, &profile).map_err(|e| e.to_string())?;
    let pins = pin_script(&derived.script)?;
    let prebuild = prebuild_packages(&derived.script)?;
    let nevr = format!(
        "{}-{}{}",
        target.rpm_version(),
        target.rpm_release(profile.rpm_release_iteration),
        base.userland.dist()
    );
    Ok(KernelBuild {
        name: name.to_string(),
        profile_path,
        branch: target.branch(),
        profile,
        nevr,
        pins,
        prebuild,
        userland: base.userland.full(),
    })
}

/// The configuration a kernel build runs under: its own build root, release
/// tree, ISO cache and variant patches. Nothing else changes.
pub fn effective_cfg(cfg: &Config, kb: &KernelBuild) -> Config {
    let mut k = cfg.clone();
    let root = cfg.work.join("kbuild").join(&kb.name);
    k.build_root = root.clone();
    k.release = kb.branch.clone();
    k.photon_tree = root.join(&kb.branch);
    k.variant_patches = cfg.variant_patches.join(format!("k{}", kb.name));
    k.iso_cache = cfg.iso_cache.join(format!("k{}", kb.name));
    k
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .args(args)
        .current_dir(dir)
        .output()
        .map_err(|e| format!("git {}: {e}", args.join(" ")))?;
    if !out.status.success() {
        return Err(format!(
            "git {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

/// Clone (or fetch) the isolated release tree and verify its branch carries
/// what the profile names - the tarball manifest, every patch file and, for
/// a FIPS profile, every file of the series manifest. Refused before hours
/// are spent, not discovered in %prep.
pub fn prepare_release_tree(
    kc: &Config,
    kb: &KernelBuild,
    log: &mut dyn FnMut(&str),
) -> Result<(), String> {
    // The isolated common tree too: the build's input record names its
    // commit before the cascade runs.
    let common = kc.build_root.join(&kc.build_common);
    if !common.join(".git").exists() {
        fs::create_dir_all(&kc.build_root).map_err(|e| format!("{}: {e}", kc.build_root.display()))?;
        log(&format!("cloning {} ({}) -> {}", kc.photon_remote, kc.build_common, common.display()));
        let ok = Command::new("git")
            .args(["clone", "--quiet", "-b", &kc.build_common, &kc.photon_remote])
            .arg(&common)
            .status()
            .map_err(|e| format!("git clone: {e}"))?;
        if !ok.success() {
            return Err(format!("cloning {} failed", kc.build_common));
        }
    } else {
        git(&common, &["fetch", "-q", "origin", &kc.build_common])?;
    }
    let tree = &kc.photon_tree;
    let parent = tree.parent().ok_or("release tree has no parent")?;
    fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    if !tree.join(".git").exists() {
        log(&format!("cloning {} ({}) -> {}", kc.photon_remote, kb.branch, tree.display()));
        let ok = Command::new("git")
            .args(["clone", "--quiet", "-b", &kb.branch, &kc.photon_remote])
            .arg(tree)
            .status()
            .map_err(|e| format!("git clone: {e}"))?;
        if !ok.success() {
            return Err(format!("cloning {} failed", kb.branch));
        }
    } else {
        git(tree, &["fetch", "-q", "origin", &kb.branch])?;
    }
    let report = crate::wrapper::branch::verify(tree, &kb.profile).map_err(|e| e.to_string())?;
    log(&format!(
        "branch {} at {} carries the profile ({} checks)",
        kb.branch,
        &report.commit[..12.min(report.commit.len())],
        report.checked.len()
    ));
    for c in &report.checked {
        log(&format!("  {c}"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_committed_profile_yields_its_pin_script_and_nevr() {
        let kb = load("7.3-rc4").unwrap();
        assert_eq!(kb.branch, "experimental/linux-7.3-rc4");
        assert_eq!(kb.nevr, "7.3.0-0.rc4.1.ph5");
        assert!(kb.pins.contains("pin_73rc4 SPECS/linux/linux.spec"));
        assert!(kb.pins.contains("enable_fips_73rc4 SPECS/linux/linux-esx.spec"));
        assert!(kb.pins.trim_end().ends_with("worktree_now"));
        assert!(kb.prebuild.contains(&"photon-os-installer".to_string()), "{:?}", kb.prebuild);
    }

    #[test]
    fn a_wrapper_without_or_with_two_pin_scripts_is_refused() {
        assert!(pin_script("#!/bin/sh\necho hi\n").is_err());
        let one = "cat > \"$PINOUT\" << 'EMBEDPIN'\nx\nworktree_now\nEMBEDPIN\n";
        assert_eq!(pin_script(one).unwrap(), "x\nworktree_now\n");
        assert!(pin_script(&format!("{one}{one}")).is_err());
        assert!(pin_script("cat > \"$PINOUT\" << 'EMBEDPIN'\nx\n").is_err());
    }

    #[test]
    fn the_prebuild_list_is_parsed_and_validated() {
        let w = "x sudo make -j8 pkgs=\"audit,rsyslog\" THREADS=8";
        assert_eq!(prebuild_packages(w).unwrap(), vec!["audit", "rsyslog"]);
        let split = "'sudo make -j8 pkgs=\"audit,rsyslog,'\n            'aide,sudo\" THREADS=8'";
        assert_eq!(prebuild_packages(split).unwrap(), vec!["audit", "rsyslog", "aide", "sudo"]);
        assert!(prebuild_packages("x sudo make -j8 pkgs=\"a;rm\" y").is_err());
        assert!(prebuild_packages("nothing").unwrap().is_empty());
    }

    #[test]
    fn a_kernel_build_runs_in_its_own_root() {
        let kb = load("7.3-rc4").unwrap();
        let cfg = Config::load();
        let k = effective_cfg(&cfg, &kb);
        assert!(k.build_root.ends_with("kbuild/7.3-rc4"));
        assert_eq!(k.photon_tree, k.build_root.join("experimental/linux-7.3-rc4"));
        assert_eq!(k.release, "experimental/linux-7.3-rc4");
        assert_ne!(k.iso_cache, cfg.iso_cache);
        assert_ne!(k.variant_patches, cfg.variant_patches);
        assert!(!k.build_root.starts_with("/root/common") && k.build_root != PathBuf::from("/root"));
    }
}
