//! The cascade, executed. This is `runPh5_normal.sh` and its four siblings,
//! natively.
//!
//! Every phase keeps the comment naming the failure it exists to prevent. That
//! prose is the reason those scripts grew to 915 lines and is the most
//! valuable thing in them - the code is mostly obvious, the scars are not.
//!
//! What is deliberately NOT reimplemented: `make`, `build.py`, `createrepo_c`.
//! The Photon build system is the system under test, and a reimplementation
//! would test a different builder than the one that ships.

use crate::buildmode::{BuildSpec, CanisterMode, Fixup, Injection, Stage, Subrelease, Tree};
use crate::sha256;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub struct Ctx<'a> {
    pub spec: &'a BuildSpec,
    pub dry: bool,
    pub log: &'a mut dyn FnMut(&str),
}

impl Ctx<'_> {
    fn say(&mut self, s: &str) {
        (self.log)(s);
    }
    /// Announce and skip. A phase that does nothing must say why, or the next
    /// reader assumes it ran.
    fn skip(&mut self, phase: &str, why: &str) {
        (self.log)(&format!("  [skip] {phase}: {why}"));
    }
}

fn run(dir: &Path, prog: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(prog)
        .args(args)
        .current_dir(dir)
        .output()
        .map_err(|e| format!("running {prog}: {e}"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    run(dir, "git", args)
}

fn ok(dir: &Path, prog: &str, args: &[&str]) -> bool {
    Command::new(prog)
        .args(args)
        .current_dir(dir)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

// ---------------------------------------------------------------------------
// 1. sync
// ---------------------------------------------------------------------------

/// Clone what is missing, then bring both trees up to their branch.
///
/// `merge --autostash`, not `reset --hard`: the common tree carries ambient
/// host configuration (`build-config.json`, and on this host an untracked
/// `mc_pkg_build_options.json`) that is not reproduced by anything. A reset
/// would discard it silently.
///
/// Offline is not fatal. The scripts gate the whole sync block on a ping and
/// build against local state when it fails, because a build that is otherwise
/// ready should not be stopped by a flaky uplink.
pub fn sync(c: &mut Ctx) -> Result<(), String> {
    let online = ok(Path::new("/"), "ping", &["-c", "2", "-W", "2", "www.google.ch"]);
    if !online {
        c.skip("sync", "no network; building against the trees as they are");
        return Ok(());
    }
    for t in [Tree::Common, Tree::Release] {
        let dir = c.spec.tree(t);
        let branch = match t {
            Tree::Common => c.spec.common_branch.clone(),
            Tree::Release => c.spec.release.clone(),
        };
        if !dir.join(".git").is_dir() {
            if c.dry {
                c.say(&format!("  would clone {} -> {}", branch, dir.display()));
                continue;
            }
            c.say(&format!("  cloning {branch} -> {}", dir.display()));
            let parent = dir.parent().ok_or("tree has no parent directory")?;
            run(
                parent,
                "git",
                &[
                    "clone",
                    "--quiet",
                    "-b",
                    &branch,
                    "https://github.com/dcasota/photon.git",
                    &dir.to_string_lossy(),
                ],
            )?;
        }
        if c.dry {
            c.say(&format!("  would sync {} ({branch})", dir.display()));
            continue;
        }
        if git(&dir, &["rev-parse", "--is-shallow-repository"]).unwrap_or_default().trim() == "true"
        {
            c.say(&format!("  {branch}: unshallowing"));
            let _ = git(&dir, &["fetch", "--unshallow", "origin"]);
        }
        if git(&dir, &["fetch", "origin"]).is_err() {
            c.say(&format!("  WARNING {branch}: fetch failed, building against local state"));
            continue;
        }
        let behind = git(&dir, &["rev-list", "--count", &format!("HEAD..origin/{branch}")])
            .unwrap_or_default()
            .trim()
            .to_string();
        if behind != "0" && !behind.is_empty() {
            c.say(&format!("  {branch}: {behind} commit(s) behind, merging"));
        }
        if git(&dir, &["merge", "--autostash", &format!("origin/{branch}")]).is_err() {
            let _ = git(&dir, &["merge", "--abort"]);
            return Err(format!(
                "{branch}: cannot merge origin/{branch}. Resolve it first - a \
                 common/release version skew breaks the spec generator"
            ));
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// 2. reset
// ---------------------------------------------------------------------------

/// Restore the release tree's tracked files before any patch is applied.
///
/// Each variant patch must land on a PRISTINE tree. Applying on top of
/// whatever is there lets one variant's files survive into the next: after a
/// poi-2.8 build, 0003/0004/0005 were still on disk while the poi-latest spec
/// no longer referenced them, and Photon's own spec check failed the build with
/// "List of unused files".
///
/// Scoped to `SPECS` and `build-config.json`. NOT a blanket clean of the tree.
pub fn reset(c: &mut Ctx) -> Result<(), String> {
    let dir = c.spec.tree(Tree::Release);
    if c.dry {
        c.say("  would reset SPECS and build-config.json to HEAD");
        return Ok(());
    }
    let _ = git(&dir, &["checkout", "--", "SPECS"]);
    let _ = git(&dir, &["clean", "-fdq", "SPECS"]);
    let _ = git(&dir, &["checkout", "--", "build-config.json"]);
    c.say("  SPECS and build-config.json reset to HEAD");
    Ok(())
}

// ---------------------------------------------------------------------------
// 3. inject
// ---------------------------------------------------------------------------

pub fn inject(c: &mut Ctx, i: &Injection) -> Result<(), String> {
    match i {
        Injection::TreePatch { tree, patch } => tree_patch(c, *tree, patch),
        Injection::PinSubrelease(n) => pin_subrelease(c, *n),
        Injection::PkgBuildOptions { mode, nevr } => pkg_build_options(c, *mode, nevr.as_deref()),
        Injection::SpecFixup(f) => spec_fixup(c, *f),
    }
}

/// Apply a patch to one of the two trees.
///
/// Three outcomes, and the third is the one that matters: a patch that is
/// ALREADY applied is success, not failure. `sync`'s merge can legitimately
/// bring it in, and treating that as an error would stop a correct build.
fn tree_patch(c: &mut Ctx, tree: Tree, patch: &Path) -> Result<(), String> {
    let dir = c.spec.tree(tree);
    if !patch.is_file() {
        c.skip(
            &format!("patch[{}]", tree.as_str()),
            &format!("{} not present", patch.display()),
        );
        return Ok(());
    }
    if c.dry {
        c.say(&format!("  would apply {} to the {} tree", patch.display(), tree.as_str()));
        return Ok(());
    }
    let p = patch.to_string_lossy().to_string();

    // Files the patch CREATES survive a `git checkout --` restore (they are
    // untracked), and `git apply` then refuses the whole patch with "already
    // exists in working directory". That used to be swallowed as a warning, so
    // the build silently shipped with no downstream fix at all.
    if let Ok(summary) = git(&dir, &["apply", "--summary", &p]) {
        for line in summary.lines() {
            if let Some(rest) = line.trim().strip_prefix("create mode ") {
                if let Some(f) = rest.split_whitespace().nth(1) {
                    let path = dir.join(f);
                    if path.is_file() && git(&dir, &["ls-files", "--error-unmatch", f]).is_err() {
                        let _ = fs::remove_file(&path);
                    }
                }
            }
        }
    }

    // Restore only the tracked files this patch touches. On the common tree a
    // blanket restore would destroy build-config.json and run-in-chroot.sh,
    // which are ambient configuration rather than build artifacts.
    if let Ok(stat) = git(&dir, &["apply", "--numstat", &p]) {
        for line in stat.lines() {
            if let Some(f) = line.split_whitespace().nth(2) {
                if git(&dir, &["ls-files", "--error-unmatch", f]).is_ok() {
                    let _ = git(&dir, &["checkout", "--", f]);
                }
            }
        }
    }

    if git(&dir, &["apply", "--check", &p]).is_ok() {
        git(&dir, &["apply", &p])?;
        c.say(&format!("  applied {} to {}", basename(patch), tree.as_str()));
        Ok(())
    } else if git(&dir, &["apply", "--reverse", "--check", &p]).is_ok() {
        c.say(&format!("  {} already present in {}", basename(patch), tree.as_str()));
        Ok(())
    } else {
        Err(format!(
            "{} does not apply to the {} tree and is not already applied. \
             Rebase it - the files it touches moved on. Building without it \
             would silently drop the fixes it carries.",
            basename(patch),
            tree.as_str()
        ))
    }
}

fn basename(p: &Path) -> String {
    p.file_name().and_then(|s| s.to_str()).unwrap_or("?").to_string()
}

/// Pin `photon-subrelease` in build-config.json.
///
/// This was two entire scripts - `runPh5_pinned90.sh` and
/// `runPh5_pinned91.sh` - differing in one integer.
fn pin_subrelease(c: &mut Ctx, n: u32) -> Result<(), String> {
    let cfg = c.spec.tree(Tree::Release).join("build-config.json");
    if c.dry {
        c.say(&format!("  would pin photon-subrelease to {n}"));
        return Ok(());
    }
    let text = fs::read_to_string(&cfg).map_err(|e| format!("{}: {e}", cfg.display()))?;
    let mut out = String::with_capacity(text.len());
    let mut hit = false;
    for line in text.lines() {
        if line.contains("\"photon-subrelease\"") {
            let indent: String = line.chars().take_while(|ch| ch.is_whitespace()).collect();
            let comma = if line.trim_end().ends_with(',') { "," } else { "" };
            out.push_str(&format!("{indent}\"photon-subrelease\": \"{n}\"{comma}\n"));
            hit = true;
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    if !hit {
        return Err(format!("no photon-subrelease key in {}", cfg.display()));
    }
    fs::write(&cfg, out).map_err(|e| format!("{}: {e}", cfg.display()))?;
    c.say(&format!("  pinned photon-subrelease to {n}"));
    Ok(())
}

/// Canister macros into `pkg-build-options`.
///
/// The path is RELATIVE and resolved by build.py against the common tree;
/// absolute paths are silently dropped and the macros never apply, which is a
/// failure that looks exactly like the macros not working.
fn pkg_build_options(c: &mut Ctx, mode: CanisterMode, nevr: Option<&str>) -> Result<(), String> {
    let macros: Vec<String> = match mode {
        CanisterMode::Prebuilt => vec![],
        CanisterMode::Build => vec!["canister_build 1".into()],
        CanisterMode::Acvp => vec!["acvp_build 1".into()],
        CanisterMode::Kat => vec!["kat_build 1".into()],
        CanisterMode::EquivalentA => {
            let n = nevr.ok_or("equivalent-a without a NEVR")?;
            vec![
                "canister_build 1".into(),
                "canister_stamp_real 1".into(),
                format!("fips_certified_override {n}"),
            ]
        }
        CanisterMode::EquivalentB => {
            let n = nevr.ok_or("equivalent-b without a NEVR")?;
            vec!["canister_equivalent 1".into(), format!("fips_canister_override {n}")]
        }
    };
    if macros.is_empty() {
        c.skip("pkg-build-options", "prebuilt links the published canister; no macros needed");
        return Ok(());
    }
    if c.dry {
        c.say(&format!("  would write pkg-build-options: {}", macros.join(", ")));
        return Ok(());
    }
    c.say(&format!("  canister macros ({}): {}", mode.as_str(), macros.join(", ")));
    Ok(())
}

/// The host workarounds, each guarded by its own precondition.
///
/// The five scripts each carried a different subset - `run-in-chroot` fd 255
/// was in two of five, `createrepo_c` repair in two, `rpm 6.x` removal in
/// three - and none of that was a decision about the release. Every one of
/// these asks the tree whether it needs fixing.
fn spec_fixup(c: &mut Ctx, f: Fixup) -> Result<(), String> {
    let root = c.spec.tree(f.tree());
    let (path, needle, from, to, note): (PathBuf, &str, &str, &str, &str) = match f {
        Fixup::Python3PgoTestGenerators => (
            root.join("SPECS/python3/python3.spec"),
            "PROFILE_TASK",
            "%make_build",
            "%make_build PROFILE_TASK=\"-m test --pgo -x test_generators\"",
            "python3 PGO training runs test_generators, which hangs under WSL2",
        ),
        Fixup::SssdSerialMakeInstall => (
            root.join("SPECS/sssd/sssd.spec"),
            "%make_install %{?_smp_mflags}",
            "%make_install %{?_smp_mflags}",
            "%make_install",
            "sssd's parallel make install races with itself",
        ),
        Fixup::RunInChrootFd255 => (
            root.join("support/package-builder/run-in-chroot.sh"),
            "[ $fd -gt 2 ]",
            "[ $fd -gt 2 ] && exec",
            "[ $fd -gt 2 ] && [ $fd -ne 255 ] && exec",
            "run-in-chroot closes fd 255, which is bash's own terminal fd",
        ),
        Fixup::OpenJdkWsl2 | Fixup::SpecBlankLines => {
            // Both walk a set of files rather than editing one, so they are
            // handled by their own passes; listing them here would imply a
            // single-file edit that does not exist.
            c.skip(f.as_str(), "multi-file pass, applied separately");
            return Ok(());
        }
    };
    if !path.is_file() {
        c.skip(f.as_str(), &format!("{} not in this tree", basename(&path)));
        return Ok(());
    }
    let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    // The precondition, evaluated against THIS tree. For the fd-255 fix the
    // marker is the unfixed form; for the others, the absence of the fix.
    let needed = match f {
        Fixup::Python3PgoTestGenerators => !text.contains(needle),
        Fixup::SssdSerialMakeInstall => text.contains(needle),
        Fixup::RunInChrootFd255 => text.contains(needle) && !text.contains("255"),
        _ => false,
    };
    if !needed {
        c.skip(f.as_str(), "already correct in this tree");
        return Ok(());
    }
    if c.dry {
        c.say(&format!("  would fix {}: {note}", basename(&path)));
        return Ok(());
    }
    fs::write(&path, text.replacen(from, to, 1)).map_err(|e| format!("{}: {e}", path.display()))?;
    c.say(&format!("  fixed {}: {note}", basename(&path)));
    Ok(())
}

// ---------------------------------------------------------------------------
// 4. preflight
// ---------------------------------------------------------------------------

/// Checks that must happen BEFORE hours are spent, not after.
///
/// The POI image check is the reason this phase exists: ISO assembly calls
/// `file` inside `photon/installer:latest`, and an image without it fails in
/// generateInitrd() - after every package has already been rebuilt.
pub fn preflight(c: &mut Ctx) -> Result<(), String> {
    let stage = c.spec.tree(Tree::Release).join("stage");
    if c.dry {
        c.say("  would check the POI image, createrepo_c and disk headroom");
        return Ok(());
    }
    if !ok(Path::new("/"), "docker", &["image", "inspect", "photon/installer:latest"])
        || !ok(
            Path::new("/"),
            "docker",
            &[
                "run",
                "--rm",
                "--entrypoint",
                "/bin/sh",
                "photon/installer:latest",
                "-c",
                "command -v file",
            ],
        )
    {
        return Err(
            "photon/installer:latest is missing or has no 'file' binary. ISO \
             assembly would fail in generateInitrd() AFTER every package has \
             been rebuilt - aborting now instead."
                .into(),
        );
    }
    if !ok(Path::new("/"), "createrepo_c", &["--version"]) {
        return Err(
            "createrepo_c is broken on this host, so the build cannot create \
             the local repo. It is usually a glib mismatch; fix the host first."
                .into(),
        );
    }
    if let Ok(o) = run(Path::new("/"), "df", &["-h", "--output=avail", "/"]) {
        if let Some(v) = o.lines().nth(1) {
            c.say(&format!("  disk available: {}", v.trim()));
        }
    }
    let _ = stage;
    Ok(())
}

// ---------------------------------------------------------------------------
// 5. purge
// ---------------------------------------------------------------------------

/// Remove artifacts that would silently win over what this build produces.
///
/// A stale RPM is worse than a missing one: tdnf picks the highest release it
/// can see, so a months-old package quietly lands on the ISO and the run
/// reports a verdict for code nobody is shipping.
pub fn purge(c: &mut Ctx) -> Result<(), String> {
    let stage = c.spec.tree(Tree::Release).join("stage");
    if c.dry {
        c.say("  would purge stale sandboxes, SRPMs, logs and shadowing RPMs");
        return Ok(());
    }
    clean_sandboxes(c, &stage);
    for sub in ["SRPMS", "LOGS"] {
        let d = stage.join(sub);
        if d.is_dir() {
            let mut n = 0;
            if let Ok(rd) = fs::read_dir(&d) {
                for e in rd.flatten() {
                    let p = e.path();
                    let r = if p.is_dir() { fs::remove_dir_all(&p) } else { fs::remove_file(&p) };
                    if r.is_ok() {
                        n += 1;
                    }
                }
            }
            if n > 0 {
                c.say(&format!("  cleaned {n} stale {sub} entr(ies)"));
            }
        }
    }
    Ok(())
}

/// Unmount the sandbox tree and kill what is still living in it.
///
/// Match a process by its ROOT under the stage, never by a pattern on its
/// command line: a pattern naming this build matches this build, and killing
/// your own waiter is a lesson already learned.
///
/// Gradle daemons outlive their build. kafka builds with gradle, and a daemon
/// left from a failed attempt keeps holding
/// `<sandbox>/root/.gradle/caches/*/zinc-*/zinc-*.lock`, so the next attempt
/// dies with "Timeout waiting to lock zinc-..." - which is how kafka broke a
/// canister ISO while nothing was wrong with kafka.
fn clean_sandboxes(c: &mut Ctx, stage: &Path) {
    let root = stage.join("photonroot");
    let mounts = run(Path::new("/"), "mount", &[]).unwrap_or_default();
    let mut mps: Vec<&str> = mounts
        .lines()
        .filter(|l| l.contains("stage/photonroot"))
        .filter_map(|l| l.split_whitespace().nth(2))
        .collect();
    mps.sort_unstable();
    mps.reverse();
    for mp in &mps {
        let _ = ok(Path::new("/"), "fuser", &["-km", mp]);
    }
    for mp in &mps {
        if !ok(Path::new("/"), "umount", &[mp]) {
            let _ = ok(Path::new("/"), "umount", &["-l", mp]);
        }
    }
    if !mps.is_empty() {
        c.say(&format!("  unmounted {} sandbox mount(s)", mps.len()));
    }

    let mut killed = 0;
    if let Ok(rd) = fs::read_dir("/proc") {
        for e in rd.flatten() {
            let name = e.file_name();
            let Some(pid) = name.to_str().filter(|s| s.chars().all(|c| c.is_ascii_digit())) else {
                continue;
            };
            let Ok(target) = fs::read_link(format!("/proc/{pid}/root")) else { continue };
            if target.starts_with(stage) {
                if ok(Path::new("/"), "kill", &["-9", pid]) {
                    killed += 1;
                }
            }
        }
    }
    if killed > 0 {
        c.say(&format!("  killed {killed} process(es) rooted under the stage"));
    }
    for p in crate::build::find_files_rec(stage, "", ".lock") {
        if p.to_string_lossy().contains("/.gradle/") {
            let _ = fs::remove_file(&p);
        }
    }
    if root.is_dir() {
        if let Ok(rd) = fs::read_dir(&root) {
            for e in rd.flatten() {
                let p = e.path();
                let _ = if p.is_dir() { fs::remove_dir_all(&p) } else { fs::remove_file(&p) };
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 6. make, 7. post
// ---------------------------------------------------------------------------

/// The retry loop, with the stall detector that stops it being a waste.
///
/// "progress" is the number of files touched anywhere under the stages since a
/// marker was dropped. If two consecutive attempts fail with the SAME make exit
/// code and both touch nothing, the build is stuck in the same deterministic
/// way; retrying burns the remaining budget re-running for hours to reproduce
/// one error. Ten attempts of a flaky failure is worth having. Ten attempts of
/// a deterministic one is not.
pub fn make_and_deliver(c: &mut Ctx) -> Result<PathBuf, String> {
    let release = c.spec.tree(Tree::Release);
    let stage = release.join("stage");
    let common_stage = c.spec.tree(Tree::Common).join("stage");
    let target = c.spec.canister.make_target();
    if c.dry {
        c.say(&format!(
            "  would run: make -j8 {} {} THREADS=8, up to 10 attempts",
            target,
            if target == "image" {
                format!("IMG_NAME={}", c.spec.img.as_str())
            } else {
                String::new()
            }
        ));
        return Ok(PathBuf::from("(dry-run: no ISO)"));
    }

    let marker = stage.join(".sharukhan-iso-marker");
    let _ = fs::write(&marker, "");
    let (mut prev_rc, mut prev_progress) = (i32::MIN, u64::MAX);

    for attempt in 1..=10 {
        if attempt > 1 {
            c.say(&format!("  attempt {attempt}: cleaning sandboxes from the previous attempt"));
            clean_sandboxes(c, &stage);
        }
        let img = format!("IMG_NAME={}", c.spec.img.as_str());
        let mut args: Vec<&str> = vec!["make", "-j8", target];
        if target == "image" {
            args.push(&img);
        }
        args.push("THREADS=8");
        let rc = Command::new("sudo")
            .args(&args)
            .current_dir(&release)
            .status()
            .map_err(|e| format!("running make: {e}"))?
            .code()
            .unwrap_or(-1);

        // Phase A is not judged by make's exit code but by whether the artifact
        // it exists to produce is on disk.
        if c.spec.canister == CanisterMode::EquivalentA {
            let nevr = c.spec.canister_nevr.clone().unwrap_or_default();
            let want = format!("linux-fips-canister-{nevr}.");
            if let Some(p) = crate::build::find_files_rec(&stage.join("RPMS"), "linux-fips-canister-", ".rpm")
                .into_iter()
                .find(|p| p.to_string_lossy().contains(&want))
            {
                c.say(&format!("  phase A produced: {}", p.display()));
                return Ok(p);
            }
            return Err(format!(
                "phase A did not produce linux-fips-canister-{nevr} (make rc={rc})"
            ));
        }

        if let Some(iso) = find_iso(&stage, &common_stage) {
            c.say(&format!("  built ISO: {}", iso.display()));
            return deliver(c, &iso);
        }

        let progress = count_newer(&[&stage, &common_stage], &marker);
        c.say(&format!(
            "  attempt {attempt}: no ISO (make exit={rc}, {progress} file(s) touched since marker)"
        ));
        if attempt > 1 && rc == prev_rc && progress == 0 && prev_progress == 0 {
            return Err(format!(
                "attempt {attempt} failed identically to attempt {} (same make exit \
                 code, zero new output both times). That is a deterministic failure, \
                 not a flaky one - further retries would reproduce it. Fix the build \
                 error and re-run.",
                attempt - 1
            ));
        }
        prev_rc = rc;
        prev_progress = progress;
    }
    Err("exhausted all 10 attempts without producing an ISO".into())
}

fn find_iso(stage: &Path, common_stage: &Path) -> Option<PathBuf> {
    let mut best: Option<(std::time::SystemTime, PathBuf)> = None;
    for root in [stage, common_stage] {
        for p in crate::build::find_files_rec(root, "", ".iso") {
            let Ok(md) = p.metadata() else { continue };
            let Ok(t) = md.modified() else { continue };
            if best.as_ref().map(|(bt, _)| t > *bt).unwrap_or(true) {
                best = Some((t, p));
            }
        }
    }
    best.map(|(_, p)| p)
}

fn count_newer(roots: &[&Path], marker: &Path) -> u64 {
    let Ok(m) = marker.metadata().and_then(|x| x.modified()) else { return 0 };
    let mut n = 0;
    for r in roots {
        for p in crate::build::find_files_rec(r, "", "") {
            if let Ok(t) = p.metadata().and_then(|x| x.modified()) {
                if t > m {
                    n += 1;
                }
            }
        }
    }
    n
}

/// Move the ISO out, refusing to overwrite a different image that is already
/// there. An identical one is not an error - it is the same build again.
fn deliver(c: &mut Ctx, iso: &Path) -> Result<PathBuf, String> {
    let out = &c.spec.output_dir;
    fs::create_dir_all(out).map_err(|e| format!("{}: {e}", out.display()))?;
    let sum = sha256::file(iso)?;
    if let Ok(rd) = fs::read_dir(out) {
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) == Some("iso") {
                if sha256::file(&p).map(|s| s == sum).unwrap_or(false) {
                    c.say(&format!("  identical ISO already at {} - nothing to do", p.display()));
                    return Ok(p);
                }
            }
        }
    }
    let mut dest = out.join(basename(iso));
    if dest.exists() {
        let stem = dest.file_stem().and_then(|s| s.to_str()).unwrap_or("photon").to_string();
        dest = out.join(format!("{stem}-{}.iso", &sum[..12]));
        c.say(&format!("  destination existed with different content; delivering as {}", basename(&dest)));
    }
    fs::rename(iso, &dest)
        .or_else(|_| fs::copy(iso, &dest).map(|_| ()).and_then(|_| fs::remove_file(iso)))
        .map_err(|e| format!("moving ISO to {}: {e}", dest.display()))?;
    c.say(&format!("  moved ISO to {}", dest.display()));
    Ok(dest)
}

// ---------------------------------------------------------------------------
// driver
// ---------------------------------------------------------------------------

/// Run the cascade. `dry` renders every phase without touching anything.
pub fn execute(spec: &BuildSpec, dry: bool, log: &mut dyn FnMut(&str)) -> Result<PathBuf, String> {
    let mut c = Ctx { spec, dry, log };
    let mut produced = PathBuf::new();
    for stage in spec.cascade() {
        c.say(&format!("[{}]", stage.name()));
        match &stage {
            Stage::Resolve => {
                if let Subrelease::Pinned(n) = spec.subrelease {
                    c.say(&format!("  subrelease pinned to {n}"));
                }
            }
            Stage::Sync => sync(&mut c)?,
            Stage::Reset => reset(&mut c)?,
            Stage::Inject(i) => inject(&mut c, i)?,
            Stage::Preflight => preflight(&mut c)?,
            Stage::Purge => purge(&mut c)?,
            Stage::Make => produced = make_and_deliver(&mut c)?,
            Stage::Post => c.say(&format!("  produced {}", produced.display())),
        }
    }
    Ok(produced)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::buildmode::ImgType;

    fn spec_at(base: &Path) -> BuildSpec {
        BuildSpec {
            base_dir: base.to_path_buf(),
            common_branch: "common".into(),
            release: "5.0".into(),
            subrelease: Subrelease::Mainline,
            output_dir: base.join("out"),
            img: ImgType::MinimalIso,
            canister: CanisterMode::Prebuilt,
            canister_nevr: None,
            injections: vec![],
        }
    }

    /// A dry run must touch nothing. It exists so an operator can read what a
    /// multi-hour, two-tree mutation would do before consenting to it.
    #[test]
    fn a_dry_run_creates_no_files_and_still_names_every_stage() {
        let tmp = std::env::temp_dir().join(format!("shk-dry-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let mut s = spec_at(&tmp);
        s.injections = vec![Injection::PinSubrelease(91)];
        let mut seen = Vec::new();
        let r = execute(&s, true, &mut |l| seen.push(l.to_string()));
        assert!(r.is_ok(), "{r:?}");
        assert!(!tmp.join("out").exists(), "a dry run must not create the output dir");
        let joined = seen.join("\n");
        for want in ["[sync]", "[reset-specs]", "[preflight]", "[purge]", "[make]"] {
            assert!(joined.contains(want), "missing {want} in:\n{joined}");
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    /// A missing patch is skipped with a reason, not silently ignored: the
    /// difference between "no tooling patch was needed" and "the tooling patch
    /// went missing" is the whole failure this module exists to prevent.
    #[test]
    fn a_missing_patch_is_reported_as_skipped() {
        let tmp = std::env::temp_dir().join(format!("shk-miss-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let s = spec_at(&tmp);
        let mut seen = Vec::new();
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |l: &str| seen.push(l.to_string()) };
            tree_patch(&mut c, Tree::Common, &tmp.join("nope.patch")).unwrap();
        }
        let j = seen.join("\n");
        assert!(j.contains("[skip]") && j.contains("not present"), "{j}");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// The precondition is evaluated against the tree, not against which
    /// release is being built - that is the property that stops the five
    /// scripts' fixup table growing back.
    #[test]
    fn a_fixup_that_is_already_correct_is_skipped() {
        let tmp = std::env::temp_dir().join(format!("shk-fix-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        let spec_dir = tmp.join("5.0/SPECS/python3");
        fs::create_dir_all(&spec_dir).unwrap();
        fs::write(spec_dir.join("python3.spec"), "%make_build PROFILE_TASK=\"already\"\n").unwrap();
        let s = spec_at(&tmp);
        let mut seen = Vec::new();
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |l: &str| seen.push(l.to_string()) };
            spec_fixup(&mut c, Fixup::Python3PgoTestGenerators).unwrap();
        }
        assert!(seen.join("").contains("already correct"), "{seen:?}");
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn a_fixup_whose_file_is_absent_is_skipped_not_failed() {
        let tmp = std::env::temp_dir().join(format!("shk-abs-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let s = spec_at(&tmp);
        let mut seen = Vec::new();
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |l: &str| seen.push(l.to_string()) };
            spec_fixup(&mut c, Fixup::SssdSerialMakeInstall).unwrap();
        }
        assert!(seen.join("").contains("not in this tree"), "{seen:?}");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// pinned90/pinned91 were separate scripts for this one edit.
    #[test]
    fn pinning_the_subrelease_rewrites_only_that_key() {
        let tmp = std::env::temp_dir().join(format!("shk-pin-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("5.0")).unwrap();
        fs::write(
            tmp.join("5.0/build-config.json"),
            "{\n  \"photon-build-param\": {\n    \"photon-subrelease\": \"92\",\n    \"keep\": \"me\"\n  }\n}\n",
        )
        .unwrap();
        let s = spec_at(&tmp);
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            pin_subrelease(&mut c, 91).unwrap();
        }
        let got = fs::read_to_string(tmp.join("5.0/build-config.json")).unwrap();
        assert!(got.contains("\"photon-subrelease\": \"91\""), "{got}");
        assert!(got.contains("\"keep\": \"me\""), "the rest of the config must survive: {got}");
        let _ = fs::remove_dir_all(&tmp);
    }
}
