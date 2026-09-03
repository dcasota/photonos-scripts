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

use crate::buildmode::{BuildSpec, CanisterMode, Embedded, Fixup, Injection, Stage, Subrelease, Tree};
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
        // `.git` is a FILE in a linked worktree, not a directory, so testing
        // is_dir() there reports "not a repository" and the clone below then
        // fails on a non-empty destination. Ask git instead of guessing from
        // the layout.
        let is_repo = dir.is_dir() && ok(&dir, "git", &["rev-parse", "--is-inside-work-tree"]);
        if !is_repo {
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
        let head_before = git(&dir, &["rev-parse", "--short", "HEAD"]).unwrap_or_default();
        if git(&dir, &["merge", "--autostash", &format!("origin/{branch}")]).is_err() {
            let _ = git(&dir, &["merge", "--abort"]);
            return Err(format!(
                "{branch}: cannot merge origin/{branch}. Resolve it first - a \
                 common/release version skew breaks the spec generator"
            ));
        }
        // `merge --autostash` exits 0 when the MERGE succeeded even if popping
        // the stash afterwards conflicted, so the exit code alone says nothing.
        // That happened on the 6.12.103 -> 6.12.107 sync: HEAD advanced, the
        // stashed SPECS edits collided with the rewritten kernel specs, and the
        // tree was left with UU paths. `git checkout -- SPECS` cannot restore an
        // unmerged path, so reset silently left them and the variant patch then
        // "did not apply" - a message that points at the patch when the fault is
        // a half-finished merge.
        let unmerged = git(&dir, &["ls-files", "-u"]).unwrap_or_default().lines().count();
        if unmerged > 0 {
            return Err(format!(
                "{branch}: the merge left {unmerged} unmerged path entr(ies) in {} - \
                 autostash could not be reapplied. Resolve or discard them \
                 (git reset HEAD -- SPECS && git checkout -- SPECS) before building; \
                 a stash entry is probably still listed.",
                dir.display()
            ));
        }
        let head = git(&dir, &["rev-parse", "--short", "HEAD"]).unwrap_or_default();
        let dirty = git(&dir, &["status", "--porcelain"]).unwrap_or_default().lines().count();
        c.say(&format!(
            "  {branch}: {} -> {} ({dirty} uncommitted path(s)) at {}",
            head_before.trim(),
            head.trim(),
            dir.display()
        ));
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
    let before = git(&dir, &["status", "--porcelain", "SPECS", "build-config.json"])
        .unwrap_or_default()
        .lines()
        .count();
    // Unstage first. A path left in the index - staged, or unmerged after a
    // failed autostash pop - cannot be restored by `checkout --`, and the reset
    // then reports success while leaving the tree modified.
    let _ = git(&dir, &["reset", "-q", "HEAD", "--", "SPECS", "build-config.json"]);
    let _ = git(&dir, &["checkout", "--", "SPECS"]);
    let _ = git(&dir, &["clean", "-fdq", "SPECS"]);
    let _ = git(&dir, &["checkout", "--", "build-config.json"]);
    let after = git(&dir, &["status", "--porcelain", "SPECS", "build-config.json"])
        .unwrap_or_default()
        .lines()
        .count();
    c.say(&format!(
        "  {} restored {before} dirty path(s) under SPECS + build-config.json; {after} remain",
        dir.display()
    ));
    // Anything left means the next phase applies a patch to a tree that is not
    // pristine, and the failure surfaces as "patch does not apply" - blaming
    // the patch for the tree's state.
    if after > 0 {
        return Err(format!(
            "{after} path(s) under SPECS are still modified after the reset; a variant \
             patch must land on a pristine tree. Inspect with `git -C {} status --porcelain SPECS`",
            dir.display()
        ));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// 3. inject
// ---------------------------------------------------------------------------

pub fn inject(c: &mut Ctx, i: &Injection) -> Result<(), String> {
    match i {
        Injection::TreePatch { tree, patch } => tree_patch(c, *tree, patch),
        Injection::Embed(e) => embedded_patch(c, *e),
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

    let files = git(&dir, &["apply", "--numstat", &p]).unwrap_or_default().lines().count();
    let bytes = fs::metadata(patch).map(|m| m.len()).unwrap_or(0);
    if git(&dir, &["apply", "--check", &p]).is_ok() {
        git(&dir, &["apply", &p])?;
        c.say(&format!(
            "  applied {} to {} ({files} file(s), {bytes} bytes) in {}",
            basename(patch),
            tree.as_str(),
            dir.display()
        ));
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

/// Apply a patch that is compiled into this binary.
///
/// Written to a temp file rather than piped to `git apply` on stdin, so a
/// failure names a path the operator can inspect. The patch itself cannot go
/// missing - that is the point of embedding it - but it CAN stop applying when
/// the tree moves, and then the message has to be actionable.
fn embedded_patch(c: &mut Ctx, e: Embedded) -> Result<(), String> {
    let dir = c.spec.tree(e.tree());
    if c.dry {
        c.say(&format!("  would apply embedded {} to the {} tree", e.as_str(), e.tree().as_str()));
        return Ok(());
    }
    let tmp = std::env::temp_dir().join(format!("sharukhan-{}-{}.patch", e.as_str(), std::process::id()));
    fs::write(&tmp, e.patch()).map_err(|x| format!("{}: {x}", tmp.display()))?;
    let p = tmp.to_string_lossy().to_string();

    if let Ok(stat) = git(&dir, &["apply", "--numstat", &p]) {
        for line in stat.lines() {
            if let Some(f) = line.split_whitespace().nth(2) {
                if git(&dir, &["ls-files", "--error-unmatch", f]).is_ok()
                    && git(&dir, &["apply", "--reverse", "--check", &p]).is_ok()
                {
                    // Already applied and tracked: restoring would undo the
                    // variant patch underneath it, so leave the tree alone.
                    c.say(&format!("  embedded {} already present in {}", e.as_str(), e.tree().as_str()));
                    let _ = fs::remove_file(&tmp);
                    return Ok(());
                }
            }
        }
    }
    let r = if git(&dir, &["apply", "--check", &p]).is_ok() {
        git(&dir, &["apply", &p]).map(|_| ()).map_err(|x| x)
    } else if git(&dir, &["apply", "--reverse", "--check", &p]).is_ok() {
        c.say(&format!("  embedded {} already present in {}", e.as_str(), e.tree().as_str()));
        let _ = fs::remove_file(&tmp);
        return Ok(());
    } else {
        Err(format!(
            "embedded patch {} no longer applies to the {} tree. It layers on top of \
             the variant patch, so either that changed or the tree moved under both. \
             The patch is at {} for inspection.",
            e.as_str(),
            e.tree().as_str(),
            tmp.display()
        ))
    };
    match r {
        Ok(()) => {
            c.say(&format!("  applied embedded {} to {}", e.as_str(), e.tree().as_str()));
            let _ = fs::remove_file(&tmp);
            Ok(())
        }
        Err(x) => Err(x),
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
/// an absolute path is silently dropped and the macros never apply, which is a
/// failure that looks exactly like the macros not working.
///
/// ALWAYS written, including for `prebuilt`, where it writes an EMPTY macro
/// list. Skipping the write there would leave whatever the previous run put in
/// the file, so a prebuilt build following an equivalent one would silently
/// inherit `canister_equivalent 1` and link a canister it was never asked to.
///
/// `equivalent-a` writes `linux` ONLY. linux-esx hardcodes `canister_build 0`
/// and cannot create a canister, so giving it these macros would be a lie
/// about what that package does.
fn pkg_build_options(c: &mut Ctx, mode: CanisterMode, nevr: Option<&str>) -> Result<(), String> {
    let dir = c.spec.tree(Tree::Common).join("common/data");
    let out = dir.join("mc_pkg_build_options.json");
    if !dir.is_dir() {
        return Err(format!(
            "{} does not exist; build.py resolves pkg-build-options there",
            dir.display()
        ));
    }

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
    let pkgs: &[&str] =
        if mode == CanisterMode::EquivalentA { &["linux"] } else { &["linux", "linux-esx"] };

    let body = pkgs
        .iter()
        .map(|p| {
            let m = macros
                .iter()
                .map(|x| format!("                \"{x}\""))
                .collect::<Vec<_>>()
                .join(",\n");
            let m = if m.is_empty() { String::new() } else { format!("\n{m}\n            ") };
            format!(
                "        \"{p}\": {{\n            \"pullsources\": [],\n            \"macros\": [{m}]\n        }}"
            )
        })
        .collect::<Vec<_>>()
        .join(",\n");
    let json = format!("{{\n{body}\n}}\n");

    c.say(&format!("  target: {}", out.display()));
    c.say(&format!("  mode {}: {} package(s), {} macro(s)", mode.as_str(), pkgs.len(), macros.len()));
    for p in pkgs {
        c.say(&format!("    {p}: [{}]", macros.join(", ")));
    }
    if c.dry {
        c.say("  (dry run: not written)");
        return Ok(());
    }
    fs::write(&out, &json).map_err(|e| format!("{}: {e}", out.display()))?;
    // Read it back. A macro file that silently failed to land is the failure
    // mode this phase exists to prevent, and it is invisible until the build
    // links the wrong canister hours later.
    let back = fs::read_to_string(&out).map_err(|e| format!("{}: {e}", out.display()))?;
    if back != json {
        return Err(format!("{} did not read back as written", out.display()));
    }
    c.say(&format!("  wrote and verified {} bytes", json.len()));
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
        Fixup::OpenJdkWsl2 => return openjdk_wsl2(c),
        Fixup::SpecBlankLines => return spec_blank_lines(c),
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

/// OpenJDK's configure detects "x86_64-pc-wsl" inside a WSL2 chroot and fails
/// with "Incorrect wsl1 installation"; `--build=` overrides the auto-detected
/// triplet.
///
/// Gated on the host actually being WSL2. On any other host the flag would be
/// a gratuitous spec edit, and the five scripts all carried this guard.
fn openjdk_wsl2(c: &mut Ctx) -> Result<(), String> {
    let wsl = fs::read_to_string("/proc/version")
        .map(|v| {
            let v = v.to_ascii_lowercase();
            v.contains("microsoft") || v.contains("wsl")
        })
        .unwrap_or(false);
    if !wsl {
        c.skip("openjdk-wsl2-build-flag", "not a WSL host; the triplet is detected correctly");
        return Ok(());
    }
    let mut done = 0;
    for root in [c.spec.tree(Tree::Release), c.spec.tree(Tree::Common)] {
        let dir = root.join("SPECS/openjdk");
        let Ok(rd) = fs::read_dir(&dir) else { continue };
        for e in rd.flatten() {
            let path = e.path();
            let name = path.file_name().and_then(|x| x.to_str()).unwrap_or("");
            if !(name.starts_with("openjdk") && name.ends_with(".spec")) {
                continue;
            }
            let Ok(text) = fs::read_to_string(&path) else { continue };
            if !text.contains("sh ./configure")
                || text.contains("build=x86_64-unknown-linux-gnu")
            {
                continue;
            }
            if c.dry {
                c.say(&format!("  would add --build to {name}"));
                done += 1;
                continue;
            }
            let out = text.replace(
                "--disable-warnings-as-errors\n",
                "--disable-warnings-as-errors \\\n    --build=x86_64-unknown-linux-gnu\n",
            );
            if out != text {
                fs::write(&path, out).map_err(|x| format!("{}: {x}", path.display()))?;
                c.say(&format!("  fixed {name}: added --build for WSL2"));
                done += 1;
            }
        }
    }
    if done == 0 {
        c.skip("openjdk-wsl2-build-flag", "already correct in every openjdk spec");
    }
    Ok(())
}

/// Photon's spec checker rejects consecutive blank lines as a formatting error,
/// and a formatting error fails the whole build long before anything compiles.
fn spec_blank_lines(c: &mut Ctx) -> Result<(), String> {
    let path = c
        .spec
        .tree(Tree::Release)
        .join("SPECS/91/python3-setuptools/python3-setuptools.spec");
    if !path.is_file() {
        c.skip("spec-consecutive-blank-lines", "python3-setuptools spec not in this tree");
        return Ok(());
    }
    let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let has_double = text.lines().collect::<Vec<_>>().windows(2).any(|w| {
        w[0].trim().is_empty() && w[1].trim().is_empty()
    });
    if !has_double {
        c.skip("spec-consecutive-blank-lines", "no consecutive blank lines");
        return Ok(());
    }
    if c.dry {
        c.say("  would collapse consecutive blank lines in python3-setuptools.spec");
        return Ok(());
    }
    let mut out = String::with_capacity(text.len());
    let mut prev_blank = false;
    for line in text.lines() {
        let blank = line.trim().is_empty();
        if !(blank && prev_blank) {
            out.push_str(line);
            out.push('\n');
        }
        prev_blank = blank;
    }
    fs::write(&path, out).map_err(|e| format!("{}: {e}", path.display()))?;
    c.say("  collapsed consecutive blank lines in python3-setuptools.spec");
    Ok(())
}

/// Make sure every declared source archive is present and matches its checksum.
///
/// Three failure modes, all seen:
///
///  - a spec's url points at `invisible-island.net/.../current/`, which 404s
///    the moment a dated snapshot is superseded (ncurses-6.5-20250816.tgz).
///    The Broadcom photon_sources mirror keeps every historical archive, so it
///    is always tried as a second candidate.
///  - `wget -O target` TRUNCATES the target before the request, so a 404 leaves
///    a zero-byte file that poisons the SOURCES cache for every later build.
///    Downloads go to a temp file and are moved only once validated.
///  - a cached archive whose checksum no longer matches is often still correct
///    in the common tree's cache, so that is checked before re-downloading.
pub fn sources(c: &mut Ctx) -> Result<(), String> {
    let dest = c.spec.tree(Tree::Release).join("stage/SOURCES");
    let backup = c.spec.tree(Tree::Common).join("stage/SOURCES");
    let specs = c.spec.tree(Tree::Release).join("SPECS");
    if !specs.is_dir() {
        c.skip("sources", "no SPECS tree yet");
        return Ok(());
    }
    if c.dry {
        c.say("  would verify every declared source archive and fetch what is missing");
        return Ok(());
    }
    fs::create_dir_all(&dest).map_err(|e| format!("{}: {e}", dest.display()))?;

    let (mut checked, mut restored, mut fetched, mut failed) = (0u32, 0u32, 0u32, 0u32);
    for cfg in crate::build::find_files_rec(&specs, "config", ".yaml") {
        for (archive, url, sha) in declared_sources(&cfg) {
            checked += 1;
            let target = dest.join(&archive);
            if target.is_file() {
                if sha.is_empty() {
                    continue; // cached, nothing to validate against
                }
                if sha512(&target).as_deref() == Some(sha.as_str()) {
                    continue;
                }
                c.say(&format!("  sha512 mismatch for {archive}"));
                let b = backup.join(&archive);
                if b.is_file() && sha512(&b).as_deref() == Some(sha.as_str()) {
                    if fs::copy(&b, &target).is_ok() {
                        c.say(&format!("  restored {archive} from the common cache"));
                        restored += 1;
                        continue;
                    }
                }
                let _ = fs::remove_file(&target);
            }
            let mirror =
                format!("https://packages.broadcom.com/photon/photon_sources/1.0/{archive}");
            let mut got = false;
            for src in [url.as_str(), mirror.as_str()] {
                if src.is_empty() {
                    continue;
                }
                let tmp = dest.join(format!("{archive}.tmp"));
                let _ = fs::remove_file(&tmp);
                if !ok(&dest, "wget", &["-q", src, "-O", &tmp.to_string_lossy()]) {
                    let _ = fs::remove_file(&tmp);
                    continue;
                }
                if tmp.metadata().map(|m| m.len() == 0).unwrap_or(true) {
                    let _ = fs::remove_file(&tmp);
                    continue;
                }
                if !sha.is_empty() && sha512(&tmp).as_deref() != Some(sha.as_str()) {
                    c.say(&format!("  checksum mismatch for fetched {archive}, discarding"));
                    let _ = fs::remove_file(&tmp);
                    continue;
                }
                if fs::rename(&tmp, &target).is_ok() {
                    c.say(&format!("  fetched {archive}"));
                    fetched += 1;
                    got = true;
                    break;
                }
            }
            if !got {
                c.say(&format!("  WARNING: could not obtain {archive} from any source"));
                failed += 1;
            }
        }
    }
    c.say(&format!(
        "  sources: {checked} declared, {restored} restored, {fetched} fetched, {failed} unresolved"
    ));
    Ok(())
}

/// `(archive, url, sha512)` for every source declared in a `config.yaml`.
///
/// The keys are `archive`, `url` and `archive_sha512sum` - verified against the
/// real files, not assumed. An earlier version of this parser looked for
/// `file:`/`sha512:` and returned NOTHING from every config.yaml in the tree,
/// which would have made the whole sources phase a silent no-op whose only
/// symptom is a 404 hours later.
///
/// Parsed directly rather than through python+pyyaml: the shape is a flat list
/// under `sources:` and three string fields, and the entries are `- archive:`
/// with the rest indented beneath.
fn declared_sources(cfg: &Path) -> Vec<(String, String, String)> {
    let Ok(text) = fs::read_to_string(cfg) else { return Vec::new() };
    let mut out: Vec<(String, String, String)> = Vec::new();
    let mut cur: Option<(String, String, String)> = None;
    let mut in_sources = false;
    // Which field is waiting for its value on the following line, if any.
    let mut pending: Option<u8> = None;
    // Indentation of a real source item. Nested lists inside an entry -
    // license_manual_review carries one - also begin with "- ", and treating
    // those as new sources splits an entry in two: the archive lands on the
    // first half and the url on a second that has no archive and is dropped.
    // A real item sits at exactly one indent level, and its fields two deeper.
    let mut item_indent: Option<usize> = None;

    for line in text.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let indented = line.starts_with(' ') || line.starts_with('-');
        if !indented {
            // A new top-level key ends the sources block.
            if let Some(c) = cur.take() {
                out.push(c);
            }
            in_sources = t.starts_with("sources:");
            item_indent = None;
            pending = None;
            continue;
        }
        if !in_sources {
            continue;
        }
        // `- archive: x` starts a new entry; the rest of its fields follow
        // indented beneath it.
        let indent = line.len() - line.trim_start().len();
        let is_item = t.starts_with("- ") && item_indent.map(|i| indent == i).unwrap_or(true);
        if is_item {
            item_indent.get_or_insert(indent);
        }
        // Fields belong to the item directly, not to anything nested deeper.
        let field_indent = item_indent.map(|i| i + 2);
        let at_field_level = is_item || field_indent.map(|f| indent == f).unwrap_or(false);
        let kv = t.trim_start_matches("- ").trim();
        if is_item {
            if let Some(c) = cur.take() {
                out.push(c);
            }
            cur = Some((String::new(), String::new(), String::new()));
            pending = None;
        }
        // A continuation value sits DEEPER than field level - the key is at
        // field level and its scalar on the next, more-indented line. So this
        // is checked before the field-level gate, or glibc's sha512 and
        // cri-tools' url are both discarded as "nested".
        if let (Some(field), Some(fi)) = (pending, field_indent) {
            if indent > fi && cur.is_some() && (!kv.contains(':') || kv.starts_with("http")) {
                let e = cur.as_mut().unwrap();
                let v = kv.trim().trim_matches('"').trim_matches('\'').to_string();
                match field {
                    0 => e.0 = v,
                    1 => e.1 = v,
                    _ => e.2 = v,
                }
                pending = None;
                continue;
            }
        }
        if !at_field_level {
            pending = None;
            continue;
        }
        let Some(e) = cur.as_mut() else {
            pending = None;
            continue;
        };
        let val = |v: &str| v.trim().trim_matches('"').trim_matches('\'').to_string();

        // A key whose value is empty carries it on the NEXT, more-indented
        // line - plain YAML, and used in this tree: glibc puts its
        // archive_sha512sum there, cri-tools its url. Reading only the key line
        // silently loses both, and a lost sha512 means an archive that is never
        // validated.
        // archive_sha512sum before archive: the longer key is a prefix match of
        // the shorter one otherwise.
        let (field, v) = if let Some(v) = kv.strip_prefix("archive_sha512sum:") {
            (2u8, v)
        } else if let Some(v) = kv.strip_prefix("archive:") {
            (0u8, v)
        } else if let Some(v) = kv.strip_prefix("url:") {
            (1u8, v)
        } else {
            continue;
        };
        if v.trim().is_empty() {
            pending = Some(field);
        } else {
            match field {
                0 => e.0 = val(v),
                1 => e.1 = val(v),
                _ => e.2 = val(v),
            }
        }
    }
    if let Some(c) = cur.take() {
        out.push(c);
    }
    // An entry with no archive name is not a source.
    out.retain(|(a, _, _)| !a.is_empty());
    out
}

fn sha512(p: &Path) -> Option<String> {
    run(Path::new("/"), "sha512sum", &[&p.to_string_lossy()])
        .ok()
        .and_then(|o| o.split_whitespace().next().map(|s| s.to_string()))
}

/// Report the subrelease the tree will actually build at.
///
/// Not decorative: `photon-subrelease` selects which SPECS/<n>/ overlay wins,
/// and `photon-mainline` decides whether snapshots are used at all. A build
/// that silently runs at a different subrelease than the operator believes
/// produces packages from a different overlay - which is how a SELinux
/// expectation was once written against the wrong one.
fn report_subrelease(c: &mut Ctx) -> Result<(), String> {
    let cfg = c.spec.tree(Tree::Release).join("build-config.json");
    let Ok(text) = fs::read_to_string(&cfg) else {
        c.skip("subrelease", "no build-config.json yet");
        return Ok(());
    };
    let field = |k: &str| -> Option<String> {
        let pat = format!("\"{k}\"");
        text.lines().find(|l| l.contains(&pat)).and_then(|l| {
            l.split(':').nth(1).map(|v| {
                v.trim().trim_end_matches(',').trim().trim_matches('"').to_string()
            })
        })
    };
    let sub = field("photon-subrelease").unwrap_or_else(|| "?".into());
    let main = field("photon-mainline").unwrap_or_else(|| sub.clone());
    c.say(&format!("  upstream photon-subrelease: {sub} (mainline: {main})"));
    // In a dry run the pin was deliberately not written, so reading the
    // unpinned value is the correct observation rather than a fault.
    if let Subrelease::Pinned(n) = c.spec.subrelease {
        if !c.dry && sub != n.to_string() {
            return Err(format!(
                "asked for subrelease {n} but build-config.json says {sub} - the pin \
                 did not take, and the build would use the wrong SPECS overlay"
            ));
        }
    }
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
    c.say("  checking photon/installer:latest carries a `file` binary");
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
    c.say("  POI image ok");
    c.say("  checking createrepo_c");
    if !ok(Path::new("/"), "createrepo_c", &["--version"]) {
        return Err(
            "createrepo_c is broken on this host, so the build cannot create \
             the local repo. It is usually a glib mismatch; fix the host first."
                .into(),
        );
    }
    c.say("  createrepo_c ok");
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
        // Name the phase-A kernels explicitly. A dry run that says only
        // "would purge stale RPMs" hides the single most destructive thing
        // this phase does, and the operator cannot check it before it runs.
        if let (CanisterMode::EquivalentB, Some(nevr)) =
            (c.spec.canister, c.spec.canister_nevr.as_deref())
        {
            let doomed: Vec<String> =
                crate::build::find_files_rec(&stage.join("RPMS"), "linux", ".rpm")
                    .iter()
                    .map(|p| basename(p))
                    .filter(|n| crate::build::purged_before_phase_b(n, nevr))
                    .collect();
            c.say(&format!(
                "  would remove {} phase-A kernel RPM(s), keeping linux-fips-canister-{nevr}",
                doomed.len()
            ));
            for n in &doomed {
                c.say(&format!("    - {n}"));
            }
        }
        c.say("  would purge stale sandboxes, SRPMs, logs and shadowing RPMs");
        return Ok(());
    }
    c.say(&format!("  stage: {}", stage.display()));
    purge_phase_a_kernels(c, &stage);
    purge_toolchain_blockers(c, &stage);
    purge_shadowing_rpms(c, &stage);
    let n = purge_corrupt_rpms(c, &stage);
    c.say(&format!("  corrupted RPMs removed: {n}"));
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

/// The kernel RPMs phase A left behind, which phase B must never ship.
///
/// Phase A builds `linux` with `canister_build 1`: that kernel PRODUCES the
/// canister object, it does not link against it. Phase B builds the same NEVR
/// with `canister_usage 1`, and the two are indistinguishable by name. So if
/// phase A's output is still in `stage/RPMS`, build.py sees the NEVR already
/// built, skips it, and the ISO ships a kernel that never consumed the
/// canister at all - passing every build check and failing only at runtime
/// attestation, if anyone thinks to look.
///
/// The canister RPM itself is the one thing that MUST survive: it is phase A's
/// deliverable and phase B's input.
///
/// The legacy script path carried this rule (`build::purged_before_phase_b`);
/// the cascade did not, and a dry run on 2026-09-03 found phase A's eight
/// kernel RPMs sitting in the stage with nothing scheduled to remove them.
fn purge_phase_a_kernels(c: &mut Ctx, stage: &Path) {
    let CanisterMode::EquivalentB = c.spec.canister else { return };
    let Some(nevr) = c.spec.canister_nevr.as_deref() else { return };
    let mut n = 0;
    for p in crate::build::find_files_rec(&stage.join("RPMS"), "linux", ".rpm") {
        let name = basename(&p);
        let doomed = crate::build::purged_before_phase_b(&name, nevr)
            || kernel_flavour_nevrs(c)
                .iter()
                .any(|(prefix, frag)| stale_flavour_rpm(&name, prefix, frag));
        if doomed && fs::remove_file(&p).is_ok() {
            c.say(&format!("  removed phase-A kernel {name}"));
            n += 1;
        }
    }
    c.say(&format!(
        "  phase-A kernel RPMs removed: {n}, keeping linux-fips-canister-{nevr}"
    ));
}

/// The two kernel flavours do NOT share a Release, so one NEVR cannot purge
/// both.
///
/// The canister-equivalent patch bumps `linux` 3 -> 4 and `linux-esx` 2 -> 3.
/// The purge above is anchored to the canister's NEVR, which is `linux`'s, so
/// it can never match `linux-esx-6.12.107-3`. That is the same defect it was
/// written to fix, one flavour over - and on the flavour that matters more,
/// because `linux-esx` is the kernel the ISO actually boots. A stale
/// `linux-esx` at its own Release, built before the canister macros existed,
/// would survive the purge, be counted as already built, and ship a boot
/// kernel with no canister linkage at all.
///
/// So read each flavour's Release from its own spec rather than assuming the
/// canister's applies to both.
fn kernel_flavour_nevrs(c: &mut Ctx) -> Vec<(String, String)> {
    let specs = c.spec.tree(Tree::Release).join("SPECS/linux");
    let mut out = Vec::new();
    for flavour in ["linux", "linux-esx"] {
        let Ok(text) = fs::read_to_string(specs.join(format!("{flavour}.spec"))) else {
            continue;
        };
        let field = |k: &str| -> Option<String> {
            text.lines()
                .find(|l| l.starts_with(k))
                .and_then(|l| l.split_whitespace().nth(1))
                // "4%{?acvp_build:.acvp}%{?kat_build:.kat}%{?dist}" -> "4"
                .map(|v| v.split('%').next().unwrap_or("").to_string())
        };
        let (Some(ver), Some(rel)) = (field("Version:"), field("Release:")) else { continue };
        // An unexpanded macro means the spec cannot be read without rpm. Do not
        // guess, and above all do not delete on a guess.
        if ver.is_empty() || rel.is_empty() || !rel.chars().all(|x| x.is_ascii_digit()) {
            continue;
        }
        out.push((format!("{flavour}-"), format!("-{ver}-{rel}.")));
    }
    out
}

/// Does this RPM belong to `prefix` at exactly `frag`, and is it not the
/// canister?
///
/// `linux-` is a prefix of `linux-esx-`, so the flavour test alone would let
/// `linux` purge the esx tree. The NEVR fragment separates them in practice -
/// the two flavours are at different Releases - but relying on that would make
/// the rule correct only by coincidence, so exclude esx from linux explicitly.
fn stale_flavour_rpm(name: &str, prefix: &str, frag: &str) -> bool {
    if name.starts_with("linux-fips-canister-") {
        return false;
    }
    if prefix == "linux-" && name.starts_with("linux-esx-") {
        return false;
    }
    name.starts_with(prefix) && name.contains(frag)
}

/// Two package families that block the toolchain bootstrap if left behind.
///
/// rpm 6.x: the bootstrap requires rpm 4.x, and a 6.x build left in the stage
/// wins on version and breaks it. libcap 2.66: the tree has moved to 2.77 and
/// the old one shadows the rebuild. Both also invalidate sandboxBase, which is
/// why it goes with them - a sandbox built against the removed RPM is a
/// sandbox that reintroduces it.
fn purge_toolchain_blockers(c: &mut Ctx, stage: &Path) {
    let rpms = stage.join("RPMS/x86_64");
    let Ok(rd) = fs::read_dir(&rpms) else { return };
    let names: Vec<String> = rd
        .flatten()
        .filter_map(|e| e.file_name().to_str().map(|s| s.to_string()))
        .collect();
    let rpm6: Vec<&String> = names.iter().filter(|n| is_rpm6(n)).collect();
    let libcap: Vec<&String> =
        names.iter().filter(|n| n.starts_with("libcap-2.66") || n.starts_with("libcap-debuginfo-2.66")).collect();

    for (label, set, why) in [
        ("rpm 6.x", &rpm6, "the toolchain bootstrap requires rpm 4.x"),
        ("libcap 2.66", &libcap, "it shadows the rebuild to 2.77"),
    ] {
        if set.is_empty() {
            continue;
        }
        let mut n = 0;
        for f in set {
            if fs::remove_file(rpms.join(f)).is_ok() {
                n += 1;
            }
        }
        if n > 0 {
            c.say(&format!("  removed {n} {label} RPM(s): {why}"));
            let _ = fs::remove_dir_all(stage.join("images/sandboxBase"));
        }
    }
}

/// Is this filename one of the rpm 6.x packages the bootstrap cannot tolerate?
///
/// Matched against an explicit name list with the version glued on, NOT by
/// looking for "-6." anywhere: `rpm-4.18.0-6.ph5.x86_64.rpm` contains "-6." in
/// its RELEASE field, and deleting that removes the very rpm 4.x the toolchain
/// bootstrap requires. The bash used explicit `rpm-6.*` globs for this reason.
fn is_rpm6(name: &str) -> bool {
    if !name.ends_with(".rpm") {
        return false;
    }
    if name.starts_with("rpm-sequoia-") {
        return true;
    }
    const FAMILIES: [&str; 9] = [
        "rpm", "rpm-build", "rpm-build-libs", "rpm-libs", "rpm-devel", "rpm-lang",
        "rpm-sign-libs", "rpm-debuginfo", "rpm-plugin-systemd-inhibit",
    ];
    FAMILIES.iter().any(|f| name.starts_with(&format!("{f}-6.")))
}

/// A previously built RPM whose Release is HIGHER than the patched spec's.
///
/// tdnf picks the highest release it can see, so such a package silently wins
/// over the one this build is about to produce and lands on the ISO. The run
/// then reports a verdict for code nobody is shipping - which is exactly how a
/// 2.9-3 installer reached an ISO built for 2.8.
fn purge_shadowing_rpms(c: &mut Ctx, stage: &Path) {
    let release_tree = c.spec.tree(Tree::Release);
    for pkg in ["photon-os-installer", "stig-hardening", "linux"] {
        let spec = release_tree.join(format!("SPECS/{pkg}/{pkg}.spec"));
        let Ok(text) = fs::read_to_string(&spec) else { continue };
        let field = |k: &str| -> Option<String> {
            text.lines()
                .find(|l| l.starts_with(k))
                .and_then(|l| l.split_whitespace().nth(1))
                .map(|v| v.split('%').next().unwrap_or("").to_string())
        };
        let (Some(ver), Some(rel)) = (field("Version:"), field("Release:")) else { continue };
        // An unexpanded macro means the spec cannot be read without rpm; do not
        // guess, and above all do not delete on a guess.
        if ver.is_empty() || rel.is_empty() || !rel.chars().all(|x| x.is_ascii_digit()) {
            continue;
        }
        let Ok(want) = rel.parse::<u32>() else { continue };
        for p in crate::build::find_files_rec(&stage.join("RPMS"), &format!("{pkg}-{ver}-"), ".rpm")
        {
            let Ok(out) = run(Path::new("/"), "rpm", &["-qp", "--qf", "%{RELEASE}", &p.to_string_lossy()])
            else {
                continue;
            };
            let got = out.trim().split(".ph").next().unwrap_or("").to_string();
            if !got.is_empty() && got.chars().all(|x| x.is_ascii_digit()) {
                if let Ok(g) = got.parse::<u32>() {
                    if g > want && fs::remove_file(&p).is_ok() {
                        c.say(&format!(
                            "  removed stale {}: release {g} shadows the patched {want}",
                            basename(&p)
                        ));
                    }
                }
            }
        }
    }
}

/// An RPM that fails its own signature/digest check.
///
/// A truncated package from an interrupted build is not detected by anything
/// downstream; it simply fails at install time, deep inside the ISO build,
/// with an error that names the package but not the reason.
fn purge_corrupt_rpms(c: &mut Ctx, stage: &Path) -> u32 {
    let dir = stage.join("RPMS/x86_64");
    if !dir.is_dir() {
        return 0;
    }
    let mut n = 0;
    for p in crate::build::find_files_rec(&dir, "", ".rpm") {
        if !ok(Path::new("/"), "rpm", &["-K", &p.to_string_lossy()]) {
            if fs::remove_file(&p).is_ok() {
                c.say(&format!("  removed corrupted RPM: {}", basename(&p)));
                n += 1;
            }
        }
    }
    n
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
        c.say(&format!("  attempt {attempt}/10: sudo {} (cwd {})", args.join(" "), release.display()));
        let t0 = std::time::SystemTime::now();
        let rc = Command::new("sudo")
            .args(&args)
            .current_dir(&release)
            .status()
            .map_err(|e| format!("running make: {e}"))?
            .code()
            .unwrap_or(-1);
        let secs = t0.elapsed().map(|d| d.as_secs()).unwrap_or(0);
        c.say(&format!("  attempt {attempt}: make exited {rc} after {}m{:02}s", secs / 60, secs % 60));

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
    let size = fs::metadata(&dest).map(|m| m.len()).unwrap_or(0);
    c.say(&format!(
        "  delivered {} ({:.2} GB, sha256 {})",
        dest.display(),
        size as f64 / 1_073_741_824.0,
        &sum[..16]
    ));
    Ok(dest)
}

/// Prove the canister phase did what it claims, before anyone boots the ISO.
///
/// Until now `post` printed a filename and asserted nothing, while the oracle's
/// own comment said "the canister linkage is proved at build time only". Both
/// cannot be true: nothing was checking at build time.
///
/// What is checkable here, cheaply and without booting:
///
/// - phase A must have produced the canister RPM. It is the entire deliverable
///   of a 140-minute build; if it is absent the build should not be reported as
///   a success.
/// - phase B must have REBUILT the kernel. `purge` deletes every kernel RPM at
///   this NEVR precisely so build.py cannot skip it, so their presence again at
///   post is proof the rebuild ran - the same-name/same-version trap that
///   shipped a canister-creating kernel is exactly what this catches if the
///   purge ever regresses.
///
/// The stronger claim - that the kernel binary really links the canister object
/// - is settled at runtime by a fips=1 row reading the canister stamp, because
/// only the FIPS self-test prints it. See `oracle::based_on_check`.
fn post_assert(c: &mut Ctx) -> Result<(), String> {
    if c.dry {
        return Ok(());
    }
    let Some(nevr) = c.spec.canister_nevr.as_deref() else { return Ok(()) };
    let rpms = c.spec.tree(Tree::Release).join("stage/RPMS");
    // The canister is itself a "linux-" RPM at this NEVR, so a naive prefix
    // test would let the canister alone satisfy phase B - the exact skip this
    // assertion exists to catch. `purged_before_phase_b` already draws that
    // line; reuse it rather than restate it.
    let kernel_rebuilt = || -> bool {
        crate::build::find_files_rec(&rpms, "linux", ".rpm")
            .iter()
            .any(|p| crate::build::purged_before_phase_b(&basename(p), nevr))
    };
    let canister_present = || -> bool {
        crate::build::find_files_rec(&rpms, "linux-fips-canister-", ".rpm")
            .iter()
            .any(|p| basename(p).contains(&format!("-{nevr}.")))
    };
    match c.spec.canister {
        CanisterMode::EquivalentA => {
            if !canister_present() {
                return Err(format!(
                    "phase A reported success but produced no \
linux-fips-canister-{nevr}: the canister is the whole point of the phase"
                ));
            }
            c.say(&format!("  asserted: linux-fips-canister-{nevr} exists"));
        }
        CanisterMode::EquivalentB => {
            if !kernel_rebuilt() {
                return Err(format!(
                    "phase B produced no kernel RPM at {nevr}. purge removed them \
so build.py could not skip the rebuild; their absence now means the rebuild \
never ran and the ISO cannot contain a canister-consuming kernel"
                ));
            }
            c.say(&format!(
                "  asserted: kernel RPMs at {nevr} were rebuilt after the phase-A purge"
            ));
            // linux-esx is the kernel the ISO boots, it is in packages_minimal
            // alongside linux, and equivalent-b writes canister macros for it
            // too - so "the kernel was rebuilt" is not settled by `linux` alone.
            // It sits at its OWN Release (the patch bumps linux 3->4 and
            // linux-esx 2->3), which is why this cannot reuse the canister NEVR.
            for (prefix, frag) in kernel_flavour_nevrs(c) {
                let seen = crate::build::find_files_rec(&rpms, "linux", ".rpm")
                    .iter()
                    .any(|p| stale_flavour_rpm(&basename(p), &prefix, &frag));
                if !seen {
                    return Err(format!(
                        "phase B rebuilt no {prefix}* RPM at {frag} - purge removed \
that flavour, so its absence means build.py never rebuilt it and the ISO would \
carry no canister-consuming {}",
                        prefix.trim_end_matches('-')
                    ));
                }
                c.say(&format!("  asserted: {prefix}* rebuilt at {frag}"));
            }
        }
        _ => {}
    }
    Ok(())
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
            Stage::Sources => {
                report_subrelease(&mut c)?;
                sources(&mut c)?
            }
            Stage::Preflight => preflight(&mut c)?,
            Stage::Purge => purge(&mut c)?,
            Stage::Make => produced = make_and_deliver(&mut c)?,
            Stage::Post => {
                c.say(&format!("  produced {}", produced.display()));
                post_assert(&mut c)?;
            }
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
    /// The regression this exists to stop. A "-6." substring match also hits
    /// `rpm-4.18.0-6.ph5`, whose RELEASE is 6 - and deleting that removes the
    /// rpm 4.x the toolchain bootstrap requires, turning a cleanup into a
    /// broken build.
    /// Parsed against the real shape Photon uses. A parser that silently
    /// returns nothing would make the whole sources phase a no-op, and the
    /// failure would only appear as a 404 hours later.
    #[test]
    fn declared_sources_reads_the_shape_photon_actually_uses() {
        // Verbatim shape from /root/5.0/SPECS/*/config.yaml.
        let tmp = std::env::temp_dir().join(format!("shk-yaml-{}.yaml", std::process::id()));
        fs::write(
            &tmp,
            "sources:\n- archive: fuse-overlayfs-snapshotter-2.1.7.tar.gz\n  \
             archive_sha512sum: c6027cdf\n  archive_type: upstream\n  \
             skip_validation: false\n- archive: second.tar.xz\n  url: https://x/second.tar.xz\n  \
             archive_sha512sum: def456\nspdx:\n  package:\n    home_page: http://x.org/\n",
        )
        .unwrap();
        let got = declared_sources(&tmp);
        assert_eq!(got.len(), 2, "both sources must be seen: {got:?}");
        assert_eq!(got[0].0, "fuse-overlayfs-snapshotter-2.1.7.tar.gz");
        assert_eq!(got[0].2, "c6027cdf", "archive_sha512sum, not sha512");
        assert_eq!(got[0].1, "", "no url declared for this one");
        assert_eq!(got[1].0, "second.tar.xz");
        assert_eq!(got[1].1, "https://x/second.tar.xz");
        assert_eq!(got[1].2, "def456");
        let _ = fs::remove_file(&tmp);
    }

    #[test]
    fn the_rpm6_purge_matches_the_version_not_the_release() {
        for keep in [
            "rpm-4.18.0-6.ph5.x86_64.rpm",
            "rpm-libs-4.18.0-6.ph5.x86_64.rpm",
            "rpm-build-4.18.0-16.ph5.x86_64.rpm",
            "librpm-6.0.0-1.ph5.x86_64.rpm",
            "rpm-6.1.0-1.ph5.x86_64.notrpm",
        ] {
            assert!(!is_rpm6(keep), "{keep} must be KEPT");
        }
        for drop in [
            "rpm-6.1.0-1.ph5.x86_64.rpm",
            "rpm-build-6.1.0-1.ph5.x86_64.rpm",
            "rpm-libs-6.1.0-1.ph5.x86_64.rpm",
            "rpm-plugin-systemd-inhibit-6.1.0-1.ph5.x86_64.rpm",
            "rpm-sequoia-1.10.0-1.ph5.x86_64.rpm",
        ] {
            assert!(is_rpm6(drop), "{drop} must be REMOVED");
        }
    }

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

#[cfg(test)]
mod parity_tests {
    use super::*;

    /// Parity against the real tree, not a fixture.
    ///
    /// The fixture test passes even when the KEYS are wrong, because the
    /// fixture is written to match whatever the parser expects. This one reads
    /// the actual SPECS tree, so a parser looking for the wrong key names
    /// returns zero and fails here. That is exactly the bug this replaced:
    /// `file:`/`sha512:` instead of `archive:`/`archive_sha512sum:`.
    ///
    /// Skipped, not failed, where no tree is checked out - a unit test suite
    /// must not depend on this host.
    #[test]
    fn the_parser_agrees_with_the_real_specs_tree() {
        let specs = Path::new("/root/5.0/SPECS");
        if !specs.is_dir() {
            eprintln!("no SPECS tree here; skipping the parity check");
            return;
        }
        let mut files = 0;
        let mut archives = 0;
        let mut with_sha = 0;
        for cfg in crate::build::find_files_rec(specs, "config", ".yaml") {
            files += 1;
            for (a, _u, h) in declared_sources(&cfg) {
                assert!(!a.contains(' '), "archive name must be a single token: {a:?}");
                archives += 1;
                if !h.is_empty() {
                    with_sha += 1;
                }
            }
            if files >= 200 {
                break;
            }
        }
        assert!(files > 0, "found no config.yaml at all");
        assert!(
            archives > 0,
            "parsed {files} config.yaml files and found NO archives - the key names are wrong"
        );
        assert!(
            with_sha * 2 > archives,
            "most archives should carry archive_sha512sum; got {with_sha}/{archives}"
        );
        eprintln!("parity: {archives} archives ({with_sha} with sha512) across {files} files");
    }
}

#[cfg(test)]
mod parity_exact {
    use super::*;
    /// Exact per-file agreement with pyyaml, written to a file the reference
    /// implementation can be diffed against. Counts that merely look similar
    /// are not agreement.
    #[test]
    fn dump_for_reference_diff() {
        // Regenerate with:
        //   cargo test --release dump_for_reference
        //   diff <(sort /tmp/py-sources.txt) <(sort /tmp/rust-sources.txt)
        // Last run: 0 differences over 1968 entries in 1745 files.
        let specs = Path::new("/root/5.0/SPECS");
        if !specs.is_dir() {
            return;
        }
        let mut lines: Vec<String> = Vec::new();
        let mut files: Vec<PathBuf> = crate::build::find_files_rec(specs, "config", ".yaml");
        files.sort();
        for cfg in files.iter() {
            for (a, u, h) in declared_sources(cfg) {
                lines.push(format!("{}|{a}|{u}|{h}", cfg.display()));
            }
        }
        let _ = fs::write("/tmp/rust-sources.txt", lines.join("\n") + "\n");
    }
}

#[cfg(test)]
mod worktree_tests {
    use super::*;

    /// A linked git worktree has `.git` as a FILE. Testing `.git/` with
    /// is_dir() calls it "not a repository", and the cascade then tries to
    /// clone over a populated directory:
    ///   fatal: destination path '...' already exists and is not an empty directory
    /// Found by running the cascade for real against worktrees, not by review.
    #[test]
    fn a_linked_worktree_is_recognised_as_a_repository() {
        let base = Path::new("/root/photon-mc/work/parity/5.0");
        if !base.is_dir() {
            eprintln!("no parity worktree here; skipping");
            return;
        }
        assert!(base.join(".git").exists(), "a worktree has a .git entry");
        assert!(!base.join(".git").is_dir(), "and in a worktree it is a FILE, not a directory");
        assert!(
            ok(base, "git", &["rev-parse", "--is-inside-work-tree"]),
            "git must still recognise it as a work tree"
        );
    }
}

#[cfg(test)]
mod pkgopts_tests {
    use super::*;

    /// The file is written for EVERY mode, including prebuilt.
    ///
    /// Skipping the write on prebuilt leaves whatever the previous run put
    /// there, so a prebuilt build following an equivalent one silently
    /// inherits `canister_equivalent 1` and links a canister nobody asked for.
    /// An empty macro list is the instruction "no canister macros", and it has
    /// to be written to mean anything.
    #[test]
    fn prebuilt_writes_an_empty_macro_list_rather_than_skipping() {
        let tmp = std::env::temp_dir().join(format!("shk-opts-{}", std::process::id()));
        let dir = tmp.join("common/common/data");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&dir).unwrap();
        let out = dir.join("mc_pkg_build_options.json");
        fs::write(&out, "{\"stale\": \"canister_equivalent 1\"}").unwrap();

        let mut s = BuildSpec::from_args(
            &tmp.to_string_lossy(), "common", "5.0", "/out", "minimal-iso", "prebuilt", None,
        )
        .unwrap();
        s.subrelease = Subrelease::Mainline;
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            pkg_build_options(&mut c, CanisterMode::Prebuilt, None).unwrap();
        }
        let got = fs::read_to_string(&out).unwrap();
        assert!(!got.contains("stale"), "the stale file must be overwritten: {got}");
        assert!(got.contains("\"linux\""), "{got}");
        assert!(got.contains("\"linux-esx\""), "{got}");
        assert!(!got.contains("canister_equivalent"), "prebuilt must carry no macros: {got}");
        let _ = fs::remove_dir_all(&tmp);
    }

    /// A rebuilt `linux` does not prove a rebuilt `linux-esx`.
    ///
    /// packages_minimal ships both, equivalent-b writes canister macros for
    /// both, and linux-esx is the one that boots - so post must fail when only
    /// the non-booting flavour came back.
    #[test]
    fn post_is_not_satisfied_by_linux_when_linux_esx_is_missing() {
        let tmp = std::env::temp_dir().join(format!("shk-postesx-{}", std::process::id()));
        let rpms = tmp.join("release/5.0/stage/RPMS/x86_64");
        let specs = tmp.join("release/5.0/SPECS/linux");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&rpms).unwrap();
        fs::create_dir_all(&specs).unwrap();
        fs::write(specs.join("linux.spec"),
            "Version:        6.12.107\nRelease:        4%{?dist}\n").unwrap();
        fs::write(specs.join("linux-esx.spec"),
            "Version:        6.12.107\nRelease:        3%{?dist}\n").unwrap();

        let mut sp = BuildSpec::from_args(
            &tmp.join("release").to_string_lossy(), "common", "5.0", "/out",
            "minimal-iso", "equivalent-b", Some("6.12.107-4.ph5".to_string()),
        )
        .unwrap();
        sp.subrelease = Subrelease::Mainline;

        // only the non-booting flavour came back
        fs::write(rpms.join("linux-6.12.107-4.ph5.x86_64.rpm"), b"x").unwrap();
        let e = {
            let mut c = Ctx { spec: &sp, dry: false, log: &mut |_: &str| {} };
            post_assert(&mut c).unwrap_err()
        };
        assert!(e.contains("linux-esx-"), "post must name the missing flavour: {e}");

        // with the boot kernel present it passes
        fs::write(rpms.join("linux-esx-6.12.107-3.ph5.x86_64.rpm"), b"x").unwrap();
        {
            let mut c = Ctx { spec: &sp, dry: false, log: &mut |_: &str| {} };
            post_assert(&mut c).unwrap();
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    /// linux is at Release 4 and linux-esx at Release 3, by the same patch.
    ///
    /// So the canister's NEVR purges one flavour and silently misses the
    /// other - the one the ISO boots. A stale linux-esx built before the
    /// canister macros existed would be counted as already built and shipped
    /// with no canister linkage.
    #[test]
    fn the_purge_covers_both_flavours_at_their_own_releases() {
        let tmp = std::env::temp_dir().join(format!("shk-esx-{}", std::process::id()));
        let rpms = tmp.join("release/5.0/stage/RPMS/x86_64");
        let specs = tmp.join("release/5.0/SPECS/linux");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&rpms).unwrap();
        fs::create_dir_all(&specs).unwrap();
        fs::write(
            specs.join("linux.spec"),
            "Version:        6.12.107\nRelease:        4%{?dist}\n",
        )
        .unwrap();
        fs::write(
            specs.join("linux-esx.spec"),
            "Version:        6.12.107\nRelease:        3%{?dist}\n",
        )
        .unwrap();

        let doomed = [
            "linux-6.12.107-4.ph5.x86_64.rpm",
            "linux-devel-6.12.107-4.ph5.x86_64.rpm",
            // the boot kernel, at ITS release - missed by the canister NEVR
            "linux-esx-6.12.107-3.ph5.x86_64.rpm",
            "linux-esx-devel-6.12.107-3.ph5.x86_64.rpm",
        ];
        let spared = [
            "linux-fips-canister-6.12.107-4.ph5.x86_64.rpm",
            // driver packages encode the kernel in their Release, not as a
            // kernel NEVR, so they must not be swept up
            "linux-esx-drivers-intel-i40e-2.30.18-2.0612107003.ph5.x86_64.rpm",
            "linux-api-headers-6.12.107-1.ph5.noarch.rpm",
            "linux-firmware-20250101-1.ph5.noarch.rpm",
        ];
        for f in doomed.iter().chain(spared.iter()) {
            fs::write(rpms.join(f), b"x").unwrap();
        }

        let mut sp = BuildSpec::from_args(
            &tmp.join("release").to_string_lossy(), "common", "5.0", "/out",
            "minimal-iso", "equivalent-b", Some("6.12.107-4.ph5".to_string()),
        )
        .unwrap();
        sp.subrelease = Subrelease::Mainline;
        {
            let mut c = Ctx { spec: &sp, dry: false, log: &mut |_: &str| {} };
            purge_phase_a_kernels(&mut c, &tmp.join("release/5.0/stage"));
        }
        for f in doomed {
            assert!(!rpms.join(f).exists(), "{f} must be purged");
        }
        for f in spared {
            assert!(rpms.join(f).exists(), "{f} must survive");
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    /// linux- is a prefix of linux-esx-, so the flavour scoping must be
    /// explicit rather than rely on the two Releases happening to differ.
    #[test]
    fn linux_does_not_purge_the_esx_tree() {
        assert!(!stale_flavour_rpm(
            "linux-esx-6.12.107-4.ph5.x86_64.rpm", "linux-", "-6.12.107-4."
        ));
        assert!(stale_flavour_rpm(
            "linux-esx-6.12.107-4.ph5.x86_64.rpm", "linux-esx-", "-6.12.107-4."
        ));
        assert!(!stale_flavour_rpm(
            "linux-fips-canister-6.12.107-4.ph5.x86_64.rpm", "linux-", "-6.12.107-4."
        ));
    }

    /// post used to print a filename and assert nothing.
    ///
    /// The oracle says the canister linkage "is proved at build time only".
    /// Nothing was proving it. These pin the two claims post can actually
    /// settle without booting anything.
    #[test]
    fn post_rejects_a_phase_a_that_produced_no_canister() {
        let tmp = std::env::temp_dir().join(format!("shk-posta-{}", std::process::id()));
        // tree(Release) is base_dir.join(release), so the stage lives one
        // level deeper than the base_dir handed to from_args.
        let rpms = tmp.join("release/5.0/stage/RPMS/x86_64");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&rpms).unwrap();
        let nevr = "6.12.107-4.ph5";
        let mk = |mode: &str| {
            let mut s = BuildSpec::from_args(
                &tmp.join("release").to_string_lossy(), "common", "5.0", "/out",
                "minimal-iso", mode, Some(nevr.to_string()),
            )
            .unwrap();
            s.subrelease = Subrelease::Mainline;
            s
        };

        // phase A with an empty stage: the deliverable is missing
        let s = mk("equivalent-a");
        let e = {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            post_assert(&mut c).unwrap_err()
        };
        assert!(e.contains("no linux-fips-canister"), "{e}");

        // with the canister present it passes
        fs::write(rpms.join(format!("linux-fips-canister-{nevr}.x86_64.rpm")), b"x").unwrap();
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            post_assert(&mut c).unwrap();
        }

        // phase B, with ONLY the canister in the stage. The canister is itself
        // a "linux-" RPM at this NEVR, so a prefix test would pass here - and
        // that is precisely the skipped-rebuild case post exists to catch.
        let s = mk("equivalent-b");
        let e = {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            post_assert(&mut c).unwrap_err()
        };
        assert!(e.contains("no kernel RPM"), "the canister must not satisfy phase B: {e}");

        // a real rebuilt kernel does satisfy it
        fs::write(rpms.join(format!("linux-{nevr}.x86_64.rpm")), b"x").unwrap();
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            post_assert(&mut c).unwrap();
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    /// The predicate was tested; the CALL was not, and the cascade never made it.
    ///
    /// `build::purged_before_phase_b` has had unit tests since it was written,
    /// and they all passed while the cascade's purge phase - the only caller
    /// that matters now that `build` replaces the scripts - did not invoke it.
    /// A phase B run would have found phase A's `linux-6.12.107-4.ph5` already
    /// in the stage, skipped the rebuild, and shipped the canister-CREATING
    /// kernel on the ISO. So this test exercises the phase, not the predicate.
    #[test]
    fn cascade_purge_removes_phase_a_kernels_but_keeps_the_canister() {
        let tmp = std::env::temp_dir().join(format!("shk-purgeb-{}", std::process::id()));
        let rpms = tmp.join("release/stage/RPMS/x86_64");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&rpms).unwrap();
        let nevr = "6.12.107-4.ph5";
        let doomed = [
            "linux-6.12.107-4.ph5.x86_64.rpm",
            "linux-devel-6.12.107-4.ph5.x86_64.rpm",
            "linux-esx-6.12.107-4.ph5.x86_64.rpm",
            "linux-debuginfo-6.12.107-4.ph5.x86_64.rpm",
        ];
        let spared = [
            // phase A's deliverable and phase B's input
            "linux-fips-canister-6.12.107-4.ph5.x86_64.rpm",
            // a different NEVR is not phase A's output
            "linux-6.12.103-14.ph5.x86_64.rpm",
            // packages whose names merely start with "linux"
            "linux-api-headers-6.12.107-1.ph5.noarch.rpm",
            "linux-firmware-20250101-1.ph5.noarch.rpm",
        ];
        for f in doomed.iter().chain(spared.iter()) {
            fs::write(rpms.join(f), b"x").unwrap();
        }

        let mut s = BuildSpec::from_args(
            &tmp.join("release").to_string_lossy(), "common", "5.0", "/out",
            "minimal-iso", "equivalent-b", Some(nevr.to_string()),
        )
        .unwrap();
        s.subrelease = Subrelease::Mainline;
        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            purge_phase_a_kernels(&mut c, &tmp.join("release/stage"));
        }
        for f in doomed {
            assert!(!rpms.join(f).exists(), "{f} is phase-A output and must be purged");
        }
        for f in spared {
            assert!(rpms.join(f).exists(), "{f} must survive the phase-B purge");
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    /// Phase A must not purge its own inputs, and prebuilt has no phase at all.
    #[test]
    fn only_phase_b_purges_kernels() {
        let tmp = std::env::temp_dir().join(format!("shk-purgea-{}", std::process::id()));
        let rpms = tmp.join("release/stage/RPMS/x86_64");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&rpms).unwrap();
        let f = "linux-6.12.107-4.ph5.x86_64.rpm";
        for mode in ["equivalent-a", "prebuilt"] {
            fs::write(rpms.join(f), b"x").unwrap();
            let nevr = if mode == "prebuilt" { None } else { Some("6.12.107-4.ph5".to_string()) };
            let mut s = BuildSpec::from_args(
                &tmp.join("release").to_string_lossy(), "common", "5.0", "/out",
                "minimal-iso", mode, nevr,
            )
            .unwrap();
            s.subrelease = Subrelease::Mainline;
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            purge_phase_a_kernels(&mut c, &tmp.join("release/stage"));
            assert!(rpms.join(f).exists(), "{mode} must not purge kernels");
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    /// linux-esx hardcodes `canister_build 0` and cannot create a canister, so
    /// handing it phase A's macros would be a lie about what it does.
    #[test]
    fn phase_a_targets_linux_only_and_phase_b_targets_both() {
        let tmp = std::env::temp_dir().join(format!("shk-opts2-{}", std::process::id()));
        let dir = tmp.join("common/common/data");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&dir).unwrap();
        let out = dir.join("mc_pkg_build_options.json");
        let s = BuildSpec::from_args(
            &tmp.to_string_lossy(), "common", "5.0", "/out", "minimal-iso", "prebuilt", None,
        )
        .unwrap();

        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            pkg_build_options(&mut c, CanisterMode::EquivalentA, Some("6.12.103-14.ph5")).unwrap();
        }
        let a = fs::read_to_string(&out).unwrap();
        assert!(a.contains("\"linux\""), "{a}");
        assert!(!a.contains("linux-esx"), "phase A must NOT name linux-esx: {a}");
        assert!(a.contains("canister_build 1") && a.contains("canister_stamp_real 1"), "{a}");
        assert!(a.contains("fips_certified_override 6.12.103-14.ph5"), "{a}");

        {
            let mut c = Ctx { spec: &s, dry: false, log: &mut |_: &str| {} };
            pkg_build_options(&mut c, CanisterMode::EquivalentB, Some("6.12.103-14.ph5")).unwrap();
        }
        let b = fs::read_to_string(&out).unwrap();
        assert!(b.contains("\"linux-esx\""), "phase B relinks BOTH flavours: {b}");
        assert!(b.contains("canister_equivalent 1"), "{b}");
        assert!(b.contains("fips_canister_override 6.12.103-14.ph5"), "{b}");
        assert!(!b.contains("canister_build 1"), "phase B must not create a canister: {b}");
        let _ = fs::remove_dir_all(&tmp);
    }
}
