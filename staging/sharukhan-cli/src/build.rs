//! Resolving a build-axis tuple to an ISO, and assembling the installer
//! variant patches. Ported from mc-build-iso.sh and mc-make-variant-patches.sh.
//!
//! The build-time axes are ISO type, installer version and canister, and
//! nothing else. Everything the matrix varies at install time (STIG,
//! filesystem, kickstart vs UI) is injected per VM, so 34 permutations need
//! only 4 ISOs.
//!
//! `make`, `build.py` and `git` stay external: the Photon build system is the
//! system under test, and reimplementing any of it would mean testing a
//! different builder than the one that ships.

use crate::config::Config;
use crate::{job, sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub struct IsoRequest {
    pub iso_type: String,
    pub poi: String,
    pub canister: String,
}

impl IsoRequest {
    /// runPh5's IMG_NAME. `minimal` is the matrix's word, `minimal-iso` is the
    /// build target's.
    pub fn img(&self) -> Result<&'static str, String> {
        match self.iso_type.as_str() {
            "minimal" => Ok("minimal-iso"),
            "full" => Ok("iso"),
            other => Err(format!("unknown iso type '{other}' (expected minimal or full)")),
        }
    }
    pub fn key(&self) -> String {
        format!("{}-poi{}-{}", self.iso_type, self.poi, self.canister)
    }
}

/// Return the ISO for this tuple, building it only when the caller has said it
/// may.
///
/// The refusal is a POLICY, not a missing capability: an ISO build takes hours
/// and shares $PHOTON_TREE/stage with anything else building, so starting one
/// as a side effect of asking for a test run is never what the operator meant.
/// `--allow-build` is the explicit consent.
pub fn resolve(
    cfg: &Config,
    req: &IsoRequest,
    force: bool,
    allow_build: bool,
    log: &mut dyn FnMut(&str),
) -> Result<PathBuf, String> {
    let img = req.img()?;
    let dest = cfg.iso_dir(&req.iso_type, &req.poi, &req.canister);
    let iso = dest.join("photon.iso");

    // Nothing is created before the decision to build: an empty cache
    // directory looks exactly like an ISO that failed to copy.
    if !force && iso.exists() {
        log(&format!("cache hit: {} -> {}", req.key(), iso.display()));
        return Ok(iso);
    }
    if !allow_build {
        return Err(format!(
            "no ISO at {} and building is off by default. An ISO build takes hours and shares \
             {}/stage with every other build on this host, so it is never started implicitly. \
             Run `sharukhan build-iso --iso-type {} --poi {} --canister {} --allow-build` when \
             you mean it.",
            iso.display(),
            cfg.photon_tree.display(),
            req.iso_type,
            req.poi,
            req.canister
        ));
    }

    fs::create_dir_all(&dest).map_err(|e| format!("{}: {e}", dest.display()))?;
    fs::create_dir_all(&cfg.build_log_dir)
        .map_err(|e| format!("{}: {e}", cfg.build_log_dir.display()))?;

    // --- the stale-RPM landmine ------------------------------------------
    // tdnf picks the highest release it can see, so a months-old
    // photon-os-installer left in stage/RPMS silently wins and lands on the
    // ISO. A test run that exercises a stale installer is worse than no test
    // run: it reports a verdict for code nobody is shipping.
    let stage = cfg.photon_tree.join("stage/RPMS");
    if stage.is_dir() {
        let mut n = 0;
        for p in find_files(&stage, "photon-os-installer-", ".rpm") {
            if fs::remove_file(&p).is_ok() {
                n += 1;
            }
        }
        if n > 0 {
            log(&format!(
                "purged {n} cached photon-os-installer RPM(s) so the build cannot pick a stale one"
            ));
        }
    }

    // --- installer version, without merging anything ---------------------
    // The point of this harness is to test PRs BEFORE they merge, so requiring
    // a merge to reach the poi=latest rows would invert that. Each variant
    // gets its own patch instead, generated from the PR branches and verified
    // to apply to a pristine 5.0 before use.
    //
    // runPh5_normal.sh resolves its patch relative to its OWN directory, so
    // the variant is selected by staging a script directory rather than by
    // editing the build script. SCRIPT_DIR is used for nothing else.
    let patch = cfg.variant_patches.join(format!("poi-{}.patch", req.poi));
    if !patch.is_file() {
        return Err(format!(
            "no variant patch at {} - run `sharukhan variant-patches`",
            patch.display()
        ));
    }
    let stage_dir = cfg.work.join("scriptdir").join(req.key());
    fs::create_dir_all(stage_dir.join("photonos-patches"))
        .map_err(|e| format!("{}: {e}", stage_dir.display()))?;
    let driver = cfg.photon_scripts.join("runPh5_normal.sh");
    fs::copy(&driver, stage_dir.join("runPh5_normal.sh"))
        .map_err(|e| format!("{}: {e}", driver.display()))?;
    fs::copy(&patch, stage_dir.join("photonos-patches/downstream-fixes.patch"))
        .map_err(|e| format!("{}: {e}", patch.display()))?;
    log(&format!(
        "staged build dir {} with poi-{}.patch ({} files)",
        stage_dir.display(),
        req.poi,
        patched_files(&patch)
    ));

    // Each variant patch must land on a PRISTINE SPECS tree. runPh5 applies it
    // on top of whatever is already there, so one variant's files survive into
    // the next: after a poi-2.8 build, 0003/0004/0005 were still on disk while
    // the poi-latest spec no longer referenced them, and Photon's own spec
    // check failed the build with "List of unused files". Everything removed
    // here is reproduced by the variant patch, so the reset is idempotent.
    let _ = git(&cfg.photon_tree, &["checkout", "--", "SPECS"]);
    let _ = git(&cfg.photon_tree, &["clean", "-fdq", "SPECS"]);
    log(&format!("SPECS reset to pristine {} before applying poi-{}.patch", cfg.release, req.poi));

    let build_log = cfg
        .build_log_dir
        .join(format!("{}-{}.log", req.key(), job::stamp()));
    log(&format!("building {img} (canister={}) -> {}", req.canister, build_log.display()));
    log("this takes hours");
    let logf = fs::File::create(&build_log).map_err(|e| format!("{}: {e}", build_log.display()))?;
    let err = logf.try_clone().map_err(|e| format!("{e}"))?;
    let rc = Command::new("sh")
        .arg(stage_dir.join("runPh5_normal.sh"))
        .arg(&cfg.build_root)
        .arg(&cfg.build_common)
        .arg(&cfg.release)
        .arg(&dest)
        .arg(img)
        .arg(&req.canister)
        .stdout(Stdio::from(logf))
        .stderr(Stdio::from(err))
        .status()
        .map_err(|e| format!("running runPh5_normal.sh: {e}"))?;
    if !rc.success() {
        return Err(format!(
            "build failed (rc={}), see {}",
            rc.code().unwrap_or(-1),
            build_log.display()
        ));
    }

    // The NEWEST ISO, not `find -newer $BUILD_LOG`. The build log is still
    // being appended to when the ISO lands, so its mtime is later than the
    // artefact's and `-newer` matches nothing; the bash then fell back to
    // `head -1`, which can pick a stale ISO left in the same cache directory
    // by an earlier build. mtime order answers the question that was meant.
    let produced = find_files(&dest, "", ".iso")
        .into_iter()
        .filter(|p| p.file_name().map(|n| n != "photon.iso").unwrap_or(false))
        .max_by_key(|p| fs::metadata(p).and_then(|m| m.modified()).ok())
        .ok_or_else(|| format!("build reported success but produced no ISO in {}", dest.display()))?;
    if produced != iso {
        let _ = fs::remove_file(&iso);
        let name = produced.file_name().unwrap_or_default();
        std::os::unix::fs::symlink(name, &iso).map_err(|e| format!("{}: {e}", iso.display()))?;
    }

    // --- assert what actually shipped ------------------------------------
    let on_media = crate::media::installer_on_media(&produced).unwrap_or_else(|_| "ABSENT".into());
    log(&format!("installer on the produced media: {on_media}"));
    let _ = fs::write(dest.join("poi-nevr.txt"), format!("{on_media}\n"));
    if let Ok(h) = sha256::file(&produced) {
        let _ = fs::write(dest.join("photon.iso.sha256"), format!("{h}\n"));
    }
    log(&format!("cached: {}", iso.display()));
    Ok(iso)
}

fn find_files(dir: &Path, prefix: &str, suffix: &str) -> Vec<PathBuf> {
    fs::read_dir(dir)
        .map(|d| {
            d.flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.starts_with(prefix) && n.ends_with(suffix))
                        .unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default()
}

/// How many files a patch touches - the same `grep -c '^+++ '` the bash
/// printed, and the number `doctor` compares between two copies of the
/// downstream patch.
pub fn patched_files(patch: &Path) -> usize {
    fs::read_to_string(patch)
        .map(|t| t.lines().filter(|l| l.starts_with("+++ ")).count())
        .unwrap_or(0)
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .map_err(|e| format!("running git {}: {e}", args.join(" ")))?;
    if !out.status.success() {
        return Err(format!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

// ---- variant patches -----------------------------------------------------

/// One installer variant: a name and the PR branches that make it.
///
///   poi-2.8     5.0 + #9 #19 #21 #22 #23 #24 #28  (installer stays 2.8)
///   poi-latest  5.0 + #9 #21 #22 #23 #24 #26   (#26 bumps it to v2.9)
///
/// #19 and #26 are alternatives - #19 adds patches to 2.8, #26 moves to 2.9
/// where three of them are already upstream - so exactly one appears in each.
///
/// The 2.8 installer branch is fix/poi-fips-sshd-algorithms (#28), which is a
/// SUPERSET of fix/photon-os-installer-2.8-5-interactive-osrelease: it carries
/// that branch's two commits plus the FIPS sshd fix, taking the installer to
/// 2.8-7. It replaces rather than joins it - two installer branches in one
/// variant would put two Release values in the same patch.
pub struct Variant {
    pub name: &'static str,
    pub branches: &'static [&'static str],
}

pub const VARIANTS: [Variant; 2] = [
    Variant {
        name: "2.8",
        branches: &[
            "fix/poi-fips-sshd-algorithms",
            "fix/aide-libgcrypt-versioned-requires",
            "fix-selinux-relabel",
            "fix/systemd-groups-and-stig-variant",
            "fix/stig-harden-reachable",
            "fix/kernel-shared-canister-config",
        ],
    },
    Variant {
        name: "latest",
        branches: &[
            "fix/poi-2.9-bump",
            "fix/aide-libgcrypt-versioned-requires",
            "fix-selinux-relabel",
            "fix/systemd-groups-and-stig-variant",
            "fix/stig-harden-reachable",
            "fix/kernel-shared-canister-config",
        ],
    },
];

/// Build one patch per installer variant, from the PR branches, WITHOUT
/// merging any of them.
///
/// The whole point of the harness is to test PRs before they land, so a
/// variant that required a merge first would be untestable by definition.
/// Each variant is assembled by cherry-picking the PR branches onto a pristine
/// 5.0 in a throwaway clone and diffing the result.
pub fn make_variant_patches(cfg: &Config, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let clone = cfg.work.join("photon-variants");
    fs::create_dir_all(&cfg.work).map_err(|e| format!("{}: {e}", cfg.work.display()))?;
    fs::create_dir_all(&cfg.variant_patches)
        .map_err(|e| format!("{}: {e}", cfg.variant_patches.display()))?;
    if !clone.join(".git").is_dir() {
        log(&format!("cloning {} (blobless) -> {}", cfg.photon_remote, clone.display()));
        let ok = Command::new("git")
            .args(["clone", "--quiet", "--filter=blob:none", "--no-checkout"])
            .arg(&cfg.photon_remote)
            .arg(&clone)
            .status()
            .map_err(|e| format!("running git clone: {e}"))?;
        if !ok.success() {
            return Err("clone failed".into());
        }
    }

    let mut fetch: Vec<&str> = vec!["fetch", "-q", "origin", "5.0"];
    let mut branches: Vec<&str> = Vec::new();
    for v in &VARIANTS {
        for b in v.branches {
            if !branches.contains(b) {
                branches.push(b);
            }
        }
    }
    fetch.extend(branches.iter().copied());
    git(&clone, &fetch)?;

    let mut failed = Vec::new();
    for v in &VARIANTS {
        log(&format!("variant poi-{}", v.name));
        match build_variant(cfg, &clone, v, log) {
            Ok(()) => {}
            Err(e) => {
                log(&format!("  poi-{}: {e}", v.name));
                failed.push(v.name);
            }
        }
    }
    if failed.is_empty() {
        Ok(())
    } else {
        Err(format!("variant(s) {} could not be built", failed.join(", ")))
    }
}

fn build_variant(
    cfg: &Config,
    clone: &Path,
    v: &Variant,
    log: &mut dyn FnMut(&str),
) -> Result<(), String> {
    let branch = format!("variant-{}", v.name);
    git(clone, &["checkout", "-q", "-B", &branch, "origin/5.0"])?;
    for b in v.branches {
        // The RANGE, not the tip. A PR branch grows commits over time (PR#9
        // gained the selinux-relabel ordering fix on top of its original
        // commit); cherry-picking only the tip applies a change without the
        // commit it builds on, which conflicts or silently produces a PARTIAL
        // variant patch. A partial patch here nearly reintroduced a resolved
        // release-number collision.
        let range = format!("origin/5.0..origin/{b}");
        if git(clone, &["cherry-pick", "-x", &range]).is_err() {
            let _ = git(clone, &["cherry-pick", "--abort"]);
            return Err(format!("CONFLICT applying {b}"));
        }
    }
    let out = cfg.variant_patches.join(format!("poi-{}.patch", v.name));
    let diff = git(clone, &["diff", "origin/5.0", &branch, "--", "SPECS/"])?;
    fs::write(&out, &diff).map_err(|e| format!("{}: {e}", out.display()))?;
    log(&format!(
        "  poi-{}: {} files, {} lines",
        v.name,
        patched_files(&out),
        diff.lines().count()
    ));

    // Prove it applies to a pristine tree before anything relies on it. A
    // detached worktree is the cheapest pristine 5.0 there is, and keeps this
    // to git rather than adding tar and patch(1) to the tool surface.
    let tmp = cfg.work.join(format!("apply-check-{}", v.name));
    let _ = fs::remove_dir_all(&tmp);
    let _ = git(clone, &["worktree", "prune"]);
    git(clone, &["worktree", "add", "--detach", "-q", &tmp.to_string_lossy(), "origin/5.0"])?;
    let applies = git(&tmp, &["apply", "--check", &out.to_string_lossy()]).is_ok();
    let _ = git(clone, &["worktree", "remove", "--force", &tmp.to_string_lossy()]);
    if applies {
        log(&format!("  poi-{}: applies to pristine {}", v.name, cfg.release));
        Ok(())
    } else {
        Err(format!("DOES NOT APPLY to pristine {}", cfg.release))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_matrix_word_and_the_build_target_are_not_the_same_word() {
        let r = |t: &str| IsoRequest {
            iso_type: t.into(),
            poi: "2.8".into(),
            canister: "prebuilt".into(),
        };
        assert_eq!(r("minimal").img().unwrap(), "minimal-iso");
        assert_eq!(r("full").img().unwrap(), "iso");
        assert!(r("tiny").img().is_err());
    }

    /// The canister is a build-time axis, so it is part of the cache key.
    /// Rows that need a locally built canister must not silently reuse the
    /// prebuilt ISO - that is how an axis ends up never exercised.
    #[test]
    fn the_cache_key_carries_every_build_axis() {
        let a = IsoRequest { iso_type: "full".into(), poi: "2.8".into(), canister: "prebuilt".into() };
        let b = IsoRequest { iso_type: "full".into(), poi: "2.8".into(), canister: "build".into() };
        assert_eq!(a.key(), "full-poi2.8-prebuilt");
        assert_ne!(a.key(), b.key());
    }

    /// #19 and #26 are alternatives: exactly one installer PR per variant, or
    /// the patch carries two installer versions at once.
    #[test]
    fn each_variant_carries_exactly_one_installer_branch() {
        for v in &VARIANTS {
            let n = v
                .branches
                .iter()
                .filter(|b| b.contains("photon-os-installer") || b.contains("poi-2.9-bump") || b.contains("poi-fips-sshd"))
                .count();
            assert_eq!(n, 1, "variant {} has {n} installer branches", v.name);
        }
    }
}
