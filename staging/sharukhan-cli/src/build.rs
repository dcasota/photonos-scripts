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
        for p in find_files_rec(&stage, "photon-os-installer-", ".rpm") {
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

    // The common tree gets its own patch, staged beside the release one.
    //
    // Without this, a change to the package builder reaches a build only by
    // being present in whatever /root/common happens to be checked out at -
    // which is how `--canister equivalent` came to depend on an operator's
    // working tree. A fresh clone (runPh5 clones `-b common`) does not carry
    // it, and the build dies two hours in on a sans-snapshot BuildRequires
    // that resolves against the published repo only.
    //
    // Absence is not fatal here: most builds need no tooling patch, and
    // refusing to build for a missing one would be worse than the gap. runPh5
    // says which case it is.
    let common_patch = cfg.variant_patches.join("common-fixes.patch");
    if common_patch.is_file() {
        fs::copy(&common_patch, stage_dir.join("photonos-patches/common-fixes.patch"))
            .map_err(|e| format!("{}: {e}", common_patch.display()))?;
        log(&format!(
            "staged common-fixes.patch ({} file(s)) for the {} tree",
            patched_files(&common_patch),
            cfg.build_common
        ));
    } else {
        log("no common-fixes.patch staged: the common tree is used as checked out");
    }

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
    // One invocation per phase. `equivalent` is one or two, decided HERE and
    // now - never assumed.
    //
    // Phase A exists only to make a canister that nobody has published. That is
    // true today and is not a property of the mode: the moment a canister is
    // published at the kernel level under test, building one locally would
    // throw away a certificate and spend hours doing it. So every canister run
    // re-asks, against the kernel it is actually about to build (which the
    // variant patch sets, not the pristine tree).
    let (phases, nevr): (Vec<&str>, String) = if req.canister == "equivalent" {
        let kernel = kernel_nevr(cfg, &patch)?;
        let state = crate::canister::detect_for(cfg, std::env::consts::ARCH, Some(&kernel))?;
        match crate::canister::plan(&state) {
            crate::canister::Plan::LinkPublished { version } => {
                log(&format!(
                    "canister {version} is published at this kernel level: linking it, \
no phase A. This build stays CMVP validated."
                ));
                (vec!["equivalent-b"], version)
            }
            crate::canister::Plan::BuildThenLink { version } => {
                log(&format!(
                    "no canister published for {version}: phase A builds one, phase B \
relinks both flavours against it. NOT CMVP validated."
                ));
                (vec!["equivalent-a", "equivalent-b"], version)
            }
            crate::canister::Plan::Nothing { reason } => {
                return Err(format!("no canister applies here: {reason}"));
            }
            crate::canister::Plan::Refuse { reason } => {
                return Err(format!(
                    "refusing to choose a canister plan: {reason}. Building one locally \
and failing to look are different things, and only the first is worth hours."
                ));
            }
        }
    } else {
        (vec![req.canister.as_str()], String::new())
    };

    for phase in &phases {
        if *phase == "equivalent-b" {
            // Phase A's `linux` RPM has the SAME NEVR as phase B's but is a
            // canister-CREATION kernel (canister_usage=0, links nothing).
            // build.py would see it as already built, skip it, and the ISO
            // would ship it - silently, because nothing downstream inspects
            // which mode a kernel was built in. Keep only the canister.
            // Anchored to the kernel NEVR, not to the "linux" prefix. A bare
            // prefix also matches linux-api-headers, linux-firmware and
            // linux-tools, which are separate packages at their own versions -
            // deleting them forces a needless rebuild and, for linux-firmware,
            // a large one. Matching "-<nevr>." keeps every flavour and
            // subpackage of the kernel under test (linux, linux-esx,
            // linux-devel, linux-esx-devel...) and nothing else, because only
            // the kernel carries that NEVR.
            let mut n = 0;
            for p in find_files_rec(&stage, "linux", ".rpm") {
                let name = p.file_name().and_then(|x| x.to_str()).unwrap_or("");
                if !purged_before_phase_b(name, &nevr) {
                    continue;
                }
                if fs::remove_file(&p).is_ok() {
                    n += 1;
                }
            }
            log(&format!(
                "purged {n} kernel RPM(s) from stage/RPMS, keeping only the canister, \
so phase B cannot ship the canister-creation kernel phase A built"
            ));
        }
        let logf = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&build_log)
            .map_err(|e| format!("{}: {e}", build_log.display()))?;
        let err = logf.try_clone().map_err(|e| format!("{e}"))?;
        if phases.len() > 1 {
            log(&format!("--- {phase} ---"));
        }
        let rc = Command::new("sh")
            .arg(stage_dir.join("runPh5_normal.sh"))
            .arg(&cfg.build_root)
            .arg(&cfg.build_common)
            .arg(&cfg.release)
            .arg(&dest)
            .arg(img)
            .arg(phase)
            .env("MC_CANISTER_NEVR", &nevr)
            .stdout(Stdio::from(logf))
            .stderr(Stdio::from(err))
            .status()
            .map_err(|e| format!("running runPh5_normal.sh: {e}"))?;
        if !rc.success() {
            return Err(format!(
                "build failed in {phase} (rc={}), see {}",
                rc.code().unwrap_or(-1),
                build_log.display()
            ));
        }
        if *phase == "equivalent-a" {
            // Do not take make's word for it: the canister must exist at the
            // NEVR phase B is about to require, or phase B fails hours later
            // on an unresolvable BuildRequires.
            let want = format!("linux-fips-canister-{nevr}");
            if !find_files_rec(&stage, &want, ".rpm").is_empty() {
                log(&format!("phase A produced {want}"));
            } else {
                return Err(format!(
                    "phase A reported success but {want}*.rpm is not in {}; \
phase B would fail on an unresolvable BuildRequires",
                    stage.display()
                ));
            }
        }
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

/// The one branch in a variant that sets the photon-os-installer version.
///
/// Matched by shape, and defined ONCE. There used to be two copies of an
/// allowlist of literal branch names - one here in `mirrors`, one in the test
/// that asserts exactly one installer branch per variant. Renaming the latest
/// variant's branch to fix/poi-2.9-fips-sshd-algorithms broke both, and the
/// mirrors copy would have failed at runtime with "variant latest has no
/// installer branch" rather than in the test suite.
///
/// Every installer branch is `fix/poi-*` or `upstream/photon-os-installer-*`,
/// and nothing else in either variant contains "poi".
pub fn installer_branch(v: &Variant) -> Option<&'static str> {
    v.branches
        .iter()
        .find(|b| b.contains("/poi-") || b.contains("photon-os-installer"))
        .copied()
}

/// Does this RPM have to go before phase B runs?
///
/// Anchored to the kernel NEVR, not to the "linux" prefix. A bare prefix also
/// matches linux-api-headers, linux-firmware and linux-tools, which are
/// separate packages at their own versions - deleting them forces a needless
/// rebuild and, for linux-firmware, a large one. Matching "-<nevr>." keeps
/// every flavour and subpackage of the kernel under test (linux, linux-esx,
/// linux-devel, linux-esx-devel...) and nothing else, because only the kernel
/// carries that NEVR.
///
/// The canister is the one thing at that NEVR that must survive: it is what
/// phase B links against.
fn purged_before_phase_b(name: &str, nevr: &str) -> bool {
    !name.starts_with("linux-fips-canister-") && name.contains(&format!("-{nevr}."))
}

/// Recursive variant, for `stage/RPMS`.
///
/// rpmbuild files its output under an arch subdirectory - `x86_64/`, `noarch/` -
/// so a single `read_dir` of `stage/RPMS` matches nothing at all. The purge
/// above was therefore a silent no-op for its whole life, and on 2026-09-01 it
/// let a 2.9-3 installer land on an ISO built for the 2.8 variant: exactly the
/// "verdict for code nobody is shipping" its own comment warns about. Walk the
/// tree instead. `find_files` stays flat because its other caller looks for the
/// ISO in one directory and must not reach into the build scratch dirs below it.
/// The NEVR `linux` will build to once the variant patch is applied.
///
/// It has to be known BEFORE phase A runs, because phase A stamps it into the
/// canister, and the variant patch is what sets Release - so reading the
/// pristine tree would give the wrong answer whenever a PR bumps the kernel.
/// Prefer the patch, fall back to the tree when the patch does not touch
/// linux.spec.
pub fn kernel_nevr(cfg: &Config, patch: &Path) -> Result<String, String> {
    let mut version: Option<String> = None;
    let mut release: Option<String> = None;

    if let Ok(text) = fs::read_to_string(patch) {
        let mut in_linux_spec = false;
        for line in text.lines() {
            if line.starts_with("+++ b/") {
                in_linux_spec = line.ends_with("SPECS/linux/linux.spec");
                continue;
            }
            if !in_linux_spec {
                continue;
            }
            // Context lines count too: a patch that bumps Release but leaves
            // Version alone still tells us the Version, on a ' ' line.
            let body = match line.chars().next() {
                Some('+') | Some(' ') => &line[1..],
                _ => continue,
            };
            if let Some(v) = body.strip_prefix("Version:") {
                version.get_or_insert(v.trim().to_string());
            } else if let Some(r) = body.strip_prefix("Release:") {
                release.get_or_insert(r.trim().to_string());
            }
        }
    }

    if version.is_none() || release.is_none() {
        let spec = cfg.photon_tree.join("SPECS/linux/linux.spec");
        let text = fs::read_to_string(&spec).map_err(|e| format!("{}: {e}", spec.display()))?;
        for line in text.lines() {
            if let Some(v) = line.strip_prefix("Version:") {
                version.get_or_insert(v.trim().to_string());
            } else if let Some(r) = line.strip_prefix("Release:") {
                release.get_or_insert(r.trim().to_string());
            }
        }
    }

    let v = version.ok_or("no Version: for linux")?;
    let r = release.ok_or("no Release: for linux")?;
    // Release carries rpm conditionals and the dist tag: 13%{?acvp_build:.acvp}%{?dist}
    let r = r.split('%').next().unwrap_or(&r).trim().to_string();
    Ok(format!("{v}-{r}.ph5"))
}

pub fn find_files_rec(dir: &Path, prefix: &str, suffix: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir(dir) else { return out };
    for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
            out.extend(find_files_rec(&p, prefix, suffix));
        } else if p
            .file_name()
            .and_then(|n| n.to_str())
            .map(|n| n.starts_with(prefix) && n.ends_with(suffix))
            .unwrap_or(false)
        {
            out.push(p);
        }
    }
    out
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
            // Carries fix/kernel-shared-canister-config as its parent, so it
            // is listed INSTEAD of it, not after it: cherry-picking is by
            // range (origin/5.0..branch), and naming both would replay the
            // shared commit twice and conflict.
            //
            // Needed because the include-refactor bumps linux to -12 but
            // leaves the canister patch series unrebased: a canister=build row
            // then applies 1004 against a 6.12.103 that no longer wraps
            // !digest_size in WARN_ON(), and %prep dies at --fuzz=0 with
            // "1 out of 2 hunks FAILED". Inert for the prebuilt rows - the
            // patches it corrects are read only under %if 0%{?canister_build}.
            // Stacked on fix/canister-build-against-current-kernel, which is
            // itself stacked on fix/kernel-shared-canister-config. Only the
            // tip is listed: cherry-picking is by range, so naming any base
            // replays its commits twice and conflicts.
            "fix/canister-equivalent-mode",
        ],
    },
    Variant {
        name: "latest",
        branches: &[
            // Stacked on fix/poi-2.9-bump, so it is listed INSTEAD of it - the
            // same range rule as the canister branch below.
            //
            // The 2.8 variant carried fix/poi-fips-sshd-algorithms and this one
            // carried nothing, so FIPS on the NEWER installer still made a
            // system unreachable over ssh. Verified against upstream: neither
            // master nor v2.8 sets PubkeyAcceptedAlgorithms/KexAlgorithms;
            // _setup_security only appends openssl-fips-provider. A
            // photon-os-installer change has to ride both variants, or the
            // untested one is the one that reaches a user.
            "fix/poi-2.9-fips-sshd-algorithms",
            "fix/aide-libgcrypt-versioned-requires",
            "fix-selinux-relabel",
            "fix/systemd-groups-and-stig-variant",
            "fix/stig-harden-reachable",
            // Carries fix/kernel-shared-canister-config as its parent, so it
            // is listed INSTEAD of it, not after it: cherry-picking is by
            // range (origin/5.0..branch), and naming both would replay the
            // shared commit twice and conflict.
            //
            // Needed because the include-refactor bumps linux to -12 but
            // leaves the canister patch series unrebased: a canister=build row
            // then applies 1004 against a 6.12.103 that no longer wraps
            // !digest_size in WARN_ON(), and %prep dies at --fuzz=0 with
            // "1 out of 2 hunks FAILED". Inert for the prebuilt rows - the
            // patches it corrects are read only under %if 0%{?canister_build}.
            // Stacked on fix/canister-build-against-current-kernel, which is
            // itself stacked on fix/kernel-shared-canister-config. Only the
            // tip is listed: cherry-picking is by range, so naming any base
            // replays its commits twice and conflicts.
            "fix/canister-equivalent-mode",
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

    let mut branches: Vec<&str> = vec!["5.0"];
    for v in &VARIANTS {
        for b in v.branches {
            if !branches.contains(b) {
                branches.push(b);
            }
        }
    }
    // One ref per fetch, not all of them in one request. A single fetch naming
    // eight refs started failing against GitHub with
    //     error: RPC failed; HTTP 400 ... fatal: expected flush after ref listing
    // while the same refs fetched individually succeed. Fetching one at a time
    // also localises the failure: the error names the ref that could not be
    // fetched instead of the whole list.
    for b in &branches {
        git(&clone, &["fetch", "-q", "origin", b])
            .map_err(|e| format!("fetching {b}: {e}"))?;
    }

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
    log("common tree");
    if let Err(e) = build_common_patch(cfg, &clone, log) {
        log(&format!("  common: {e}"));
        failed.push("common");
    }
    if failed.is_empty() {
        Ok(())
    } else {
        Err(format!("variant(s) {} could not be built", failed.join(", ")))
    }
}

/// Branches whose changes live on the `common` branch line rather than a
/// release one.
///
/// Photon keeps per-release SPECS on 5.0/4.0/6.0 and the shared build tooling
/// on `common`, and those histories never meet: `common` has no `SPECS/`, `5.0`
/// has no `support/package-builder/`. So the variant patches - which diff
/// `origin/5.0..branch` and are applied to `SPECS` - can never carry a change
/// to the package builder.
///
/// That gap is not theoretical. `--canister equivalent` cannot work without
/// ToolChainUtils resolving a sans-snapshot BuildRequires against the local
/// repo, and until this patch existed that fix reached a build only because the
/// operator's /root/common happened to sit on the right branch and sync_repo's
/// `merge --autostash` happened to preserve it. A fresh clone (`-b common`)
/// does not contain it, and the build fails two hours in with
/// `linux-fips-canister-<nevr> package not found or not installed`.
pub const COMMON_BRANCHES: &[&str] = &["fix/sans-snapshot-resolves-locally-built-canister"];

/// The same assembly as a variant patch, against the `common` branch line.
///
/// Deliberately NOT limited by pathspec the way the variant diff is limited to
/// `SPECS/`: on this branch line every path is build tooling, and a filter here
/// would silently drop a fix that lands outside `support/`.
fn build_common_patch(cfg: &Config, clone: &Path, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let out = cfg.variant_patches.join("common-fixes.patch");
    git(clone, &["fetch", "-q", "origin", "common"]).map_err(|e| format!("fetching common: {e}"))?;
    for b in COMMON_BRANCHES {
        git(clone, &["fetch", "-q", "origin", b]).map_err(|e| format!("fetching {b}: {e}"))?;
    }

    let branch = "variant-common";
    git(clone, &["checkout", "-q", "-B", branch, "origin/common"])?;
    for b in COMMON_BRANCHES {
        let range = format!("origin/common..origin/{b}");
        if git(clone, &["cherry-pick", "-x", &range]).is_err() {
            let _ = git(clone, &["cherry-pick", "--abort"]);
            return Err(format!("CONFLICT applying {b}"));
        }
    }
    let diff = git(clone, &["diff", "origin/common", branch])?;
    if diff.trim().is_empty() {
        return Err("produced an EMPTY patch - the branches add nothing to origin/common".into());
    }
    fs::write(&out, &diff).map_err(|e| format!("{}: {e}", out.display()))?;
    log(&format!("  common: {} files, {} lines", patched_files(&out), diff.lines().count()));

    let tmp = cfg.work.join("apply-check-common");
    let _ = fs::remove_dir_all(&tmp);
    let _ = git(clone, &["worktree", "prune"]);
    git(clone, &["worktree", "add", "--detach", "-q", &tmp.to_string_lossy(), "origin/common"])?;
    let applies = git(&tmp, &["apply", "--check", &out.to_string_lossy()]).is_ok();
    let _ = git(clone, &["worktree", "remove", "--force", &tmp.to_string_lossy()]);
    if applies {
        log("  common: applies to pristine common");
        Ok(())
    } else {
        Err("DOES NOT APPLY to pristine common".into())
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

    /// The NEVR must come from the PATCH, not the tree: the patch is what sets
    /// Release, and phase A stamps that value into the canister. Reading the
    /// pristine tree would stamp the wrong kernel whenever a PR bumps it.
    #[test]
    fn the_kernel_nevr_is_read_from_the_variant_patch() {
        let tmp = std::env::temp_dir().join(format!("shk-nevr-{}", std::process::id()));
        fs::create_dir_all(&tmp).unwrap();
        let patch = tmp.join("poi-2.8.patch");
        // Built line by line on purpose: a Rust \-continuation swallows the
        // leading whitespace of the next line, which would strip the single
        // space that makes " Version:" a diff CONTEXT line - and context is
        // exactly what this function has to read.
        let lines = [
            "diff --git a/SPECS/linux/linux.spec b/SPECS/linux/linux.spec",
            "--- a/SPECS/linux/linux.spec",
            "+++ b/SPECS/linux/linux.spec",
            " Version:        6.12.103",
            "-Release:        11%{?acvp_build:.acvp}%{?dist}",
            "+Release:        14%{?acvp_build:.acvp}%{?dist}",
        ];
        fs::write(&patch, lines.join("\n") + "\n").unwrap();
        let cfg = Config::for_test(&tmp);
        assert_eq!(kernel_nevr(&cfg, &patch).unwrap(), "6.12.103-14.ph5");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// A patch that does not touch linux.spec must not silently yield a wrong
    /// answer - it falls back to the tree.
    #[test]
    fn a_patch_without_linux_spec_falls_back_to_the_tree() {
        let tmp = std::env::temp_dir().join(format!("shk-nevr2-{}", std::process::id()));
        fs::create_dir_all(tmp.join("SPECS/linux")).unwrap();
        fs::write(
            tmp.join("SPECS/linux/linux.spec"),
            "Name:           linux\nVersion:        6.12.103\nRelease:        9%{?dist}\n",
        )
        .unwrap();
        let patch = tmp.join("other.patch");
        fs::write(&patch, "+++ b/SPECS/aide/aide.spec\n+Release:        3%{?dist}\n").unwrap();
        let cfg = Config::for_test(&tmp);
        assert_eq!(kernel_nevr(&cfg, &patch).unwrap(), "6.12.103-9.ph5");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// The purge that keeps a stale installer off the ISO has to look where
    /// rpmbuild actually files its output: `stage/RPMS/<arch>/`, not
    /// `stage/RPMS/`. A flat read_dir there matched nothing and the purge did
    /// nothing, which is how a 2.9-3 installer reached an ISO built for 2.8.
    #[test]
    fn the_installer_purge_reaches_into_the_arch_subdirectory() {
        let tmp = std::env::temp_dir().join(format!("shk-purge-{}", std::process::id()));
        let arch = tmp.join("x86_64");
        fs::create_dir_all(&arch).unwrap();
        fs::write(arch.join("photon-os-installer-2.8-7.ph5.x86_64.rpm"), "").unwrap();
        fs::write(arch.join("photon-os-installer-2.9-3.ph5.x86_64.rpm"), "").unwrap();
        fs::write(arch.join("linux-6.12.103-1.ph5.x86_64.rpm"), "").unwrap();
        fs::write(tmp.join("photon-os-installer-1.0-1.ph5.noarch.rpm"), "").unwrap();

        assert!(find_files(&tmp, "photon-os-installer-", ".rpm").len() == 1);
        let mut hit = find_files_rec(&tmp, "photon-os-installer-", ".rpm");
        hit.sort();
        assert_eq!(hit.len(), 3, "arch subdirectory must be walked");
        assert!(hit.iter().all(|p| p.to_string_lossy().contains("photon-os-installer-")));

        let _ = fs::remove_dir_all(&tmp);
    }

    /// The inter-phase purge deletes the canister-creation kernel so phase B
    /// cannot ship it. It used to match on the "linux" prefix alone, which
    /// also swept up linux-api-headers, linux-firmware and linux-tools -
    /// unrelated packages at their own versions, rebuilt for nothing. Only the
    /// kernel under test carries the NEVR, so that is what the purge keys on.
    #[test]
    fn the_phase_b_purge_takes_the_kernel_and_spares_its_namesakes() {
        let nevr = "6.12.103-14.ph5";

        // Every flavour and subpackage of the kernel under test must go.
        for n in [
            "linux-6.12.103-14.ph5.x86_64.rpm",
            "linux-esx-6.12.103-14.ph5.x86_64.rpm",
            "linux-devel-6.12.103-14.ph5.x86_64.rpm",
            "linux-esx-devel-6.12.103-14.ph5.x86_64.rpm",
        ] {
            assert!(purged_before_phase_b(n, nevr), "{n} must be purged");
        }

        // The canister is what phase B links against: it stays even though it
        // carries the very same NEVR.
        assert!(
            !purged_before_phase_b("linux-fips-canister-6.12.103-14.ph5.x86_64.rpm", nevr),
            "the canister must survive the purge that precedes phase B"
        );

        // Separate packages that merely start with "linux". This is the
        // regression: linux-api-headers was observed being rebuilt after the
        // prefix-only purge deleted it.
        for n in [
            "linux-api-headers-6.1.79-6.ph5.noarch.rpm",
            "linux-firmware-20250211-1.ph5.noarch.rpm",
            "linux-tools-6.12.103-13.ph5.x86_64.rpm",
        ] {
            assert!(!purged_before_phase_b(n, nevr), "{n} must be spared");
        }
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
    ///
    /// Matched by shape rather than by an allowlist of exact branch names. The
    /// allowlist listed poi-2.9-bump and poi-fips-sshd literally, so when the
    /// latest variant moved to fix/poi-2.9-fips-sshd-algorithms - a branch
    /// stacked on the bump, listed instead of it - the count went to 0 and the
    /// test failed for a rename rather than for a real fault. Every installer
    /// branch is either fix/poi-* or upstream/photon-os-installer-*, and no
    /// other branch in either variant contains "poi".
    #[test]
    fn each_variant_carries_exactly_one_installer_branch() {
        for v in &VARIANTS {
            let hits: Vec<_> = v
                .branches
                .iter()
                .filter(|b| b.contains("/poi-") || b.contains("photon-os-installer"))
                .collect();
            assert_eq!(
                hits.len(),
                1,
                "variant {} carries {} installer branches: {hits:?}",
                v.name,
                hits.len()
            );
            // The shipped helper must agree with the test's own filter -
            // `mirrors` fails at runtime, not here, when it does not.
            assert_eq!(installer_branch(v).as_ref(), hits.first().map(|b| **b).as_ref());
        }
    }
}

#[cfg(test)]
mod mirror_tests {
    use super::*;

    /// A regenerated patch must compare equal to the stored copy even though
    /// git stamps a fresh sha, date and version footer on every run. Without
    /// this the check would cry stale on every invocation and be turned off.
    #[test]
    fn regeneration_noise_does_not_read_as_staleness() {
        let stored = "From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001\n\
                      From: A <a@b>\n\
                      Date: Mon, 31 Aug 2026 00:00:00 +0000\n\
                      Subject: [PATCH] thing\n\
                      \n\
                      body\n";
        let fresh = "From 9a49a18dc221ef6ba448cb482e530c8fda4ba85c Mon Sep 17 00:00:00 2001\n\
                     From: A <a@b>\n\
                     Date: Tue, 1 Sep 2026 21:04:11 +0200\n\
                     Subject: [PATCH] thing\n\
                     \n\
                     body\n-- \n2.43.0\n";
        assert_eq!(stable_header(stored), stable_header(fresh));
    }

    /// ...but a real content change MUST read as stale. This is the case that
    /// actually happened: the reviewed import form sat on the fork while the
    /// spec still carried the pre-review one.
    #[test]
    fn a_real_content_change_reads_as_stale() {
        let old = "From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001\n\
                   Subject: [PATCH] thing\n\n+from stigenable import KS_STIG_PACKAGES\n";
        let new = "From 1111111111111111111111111111111111111111 Mon Sep 17 00:00:00 2001\n\
                   Subject: [PATCH] thing\n\n+import stigenable\n";
        assert_ne!(stable_header(old), stable_header(new));
    }

    /// Every mirror must name a patch the spec directory actually uses.
    #[test]
    fn every_mirror_targets_a_real_spec_patch() {
        for m in &MIRRORS {
            assert!(m.spec_patch.ends_with(".patch"), "{}", m.spec_patch);
            assert!(m.poi_remote_branch.starts_with("dcasota/"), "{}", m.poi_remote_branch);
        }
    }
}

// ------------------------------------------------------- published mirror ---

/// A SPECS patch that is a COPY of a commit on a photon-os-installer PR branch.
///
/// The copy is the thing that goes stale. A reviewer's change lands on the POI
/// branch, the spec patch keeps the old text, and the matrix then proves the
/// old text - which looks exactly like proving the new one. That is not
/// hypothetical: the isoBuilder review fix sat on the POI branch for a whole
/// ISO build while all three photon branches still carried the pre-review form.
pub struct Mirror {
    pub spec_patch: &'static str,
    pub poi_remote_branch: &'static str,
}

pub const MIRRORS: [Mirror; 3] = [
    Mirror {
        spec_patch: "0006-stig-drop-redundant-packages.patch",
        poi_remote_branch: "dcasota/fix/stig-drop-redundant-packages",
    },
    Mirror {
        spec_patch: "0007-installer-seed-locale.conf-before-package-install.patch",
        poi_remote_branch: "dcasota/fix/seed-locale-conf-before-pkg-install",
    },
    Mirror {
        spec_patch: "0008-isoBuilder-put-installer-requestable-packages-on-media.patch",
        poi_remote_branch: "dcasota/fix/isobuilder-installer-pkgs-on-media",
    },
];

/// Normalise a `git format-patch` header to the shape the spec patches use, so
/// regenerating one does not churn the spec on every run.
fn stable_header(patch: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    for (i, line) in patch.lines().enumerate() {
        if i == 0 && line.starts_with("From ") {
            out.push("From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001".into());
        } else if i < 6 && line.starts_with("Date: ") {
            out.push("Date: Mon, 31 Aug 2026 00:00:00 +0000".into());
        } else {
            out.push(line.to_string());
        }
    }
    let joined = out.join("\n");
    let body = joined.split("\n-- \n").next().unwrap_or(&joined).trim_end();
    format!("{body}\n")
}

pub struct MirrorState {
    pub spec_patch: String,
    pub branch: String,
    pub current: bool,
    pub detail: String,
}

/// Verify each spec patch still equals what the PUBLISHED POI branch produces.
///
/// Everything is taken from remote-tracking refs after a fetch: the whole point
/// is to prove that what is on the fork is what gets built, not whatever a local
/// working tree happens to hold.
pub fn verify_mirrors(cfg: &Config, photon_branch: &str) -> Result<Vec<MirrorState>, String> {
    let poi = &cfg.poi_tree;
    git(poi, &["fetch", "-q", "dcasota"])?;
    git(&cfg.photon_tree, &["fetch", "-q", "origin", photon_branch])?;

    let mut out = Vec::new();
    for m in &MIRRORS {
        let spec_rel = format!("SPECS/photon-os-installer/{}", m.spec_patch);
        let in_spec = git(
            &cfg.photon_tree,
            &["show", &format!("origin/{photon_branch}:{spec_rel}")],
        );
        let Ok(in_spec) = in_spec else {
            out.push(MirrorState {
                spec_patch: m.spec_patch.into(),
                branch: m.poi_remote_branch.into(),
                current: true,
                detail: "not carried by this variant".into(),
            });
            continue;
        };
        let range = format!("{}~1..{}", m.poi_remote_branch, m.poi_remote_branch);
        let generated = match git(poi, &["format-patch", "--stdout", &range]) {
            Ok(g) => stable_header(&g),
            Err(e) => {
                out.push(MirrorState {
                    spec_patch: m.spec_patch.into(),
                    branch: m.poi_remote_branch.into(),
                    current: false,
                    detail: format!("cannot read the published branch: {e}"),
                });
                continue;
            }
        };
        let same = stable_header(&in_spec) == generated;
        out.push(MirrorState {
            spec_patch: m.spec_patch.into(),
            branch: m.poi_remote_branch.into(),
            current: same,
            detail: if same {
                "matches the published branch".into()
            } else {
                "STALE - the spec carries an older copy than the fork".into()
            },
        });
    }
    Ok(out)
}
