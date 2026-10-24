//! `sharukhan sync analyze | rebase | verify`: the deterministic part of a 5.0
//! sync, which the iteration of 2026-10-21 did with scratch scripts.
//!
//! * analyze: every open PR of the fork against the moved bases - is the local
//!   head the one on GitHub, does it merge onto the new base and change
//!   anything, which of its files did upstream touch too.
//! * rebase: replay one PR onto the new base. Spec files are merged three-way
//!   with every `Release:` value and the `%changelog` body masked; the result
//!   gets the base's Release with its last component plus one and exactly one
//!   changelog entry on top (the PR's own line, dated today, renumbered). A
//!   path the base renamed is followed. Anything else that conflicts is
//!   refused with the file named: that is a decision, not a rule.
//! * verify: merge each ref onto the base and check every spec it changes at
//!   every subrelease its build_if admits: rpmspec on x86_64 and aarch64,
//!   check_spec, and the one-changelog-entry rule.
//!
//! Spec tools run through `builder` (the pinned container in the gate).

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const AUTHOR: &str = "Daniel Casota <dcasota@gmail.com>";

fn git_in(dir: &Path, args: &[&str]) -> Result<String, String> {
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

fn show(dir: &Path, rev: &str, path: &str) -> Option<String> {
    git_in(dir, &["show", &format!("{rev}:{path}")]).ok()
}

// --- analyze ----------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct Pr {
    pub number: u64,
    pub base: String,
    pub head_ref: String,
    pub gh_head: String,
}

pub fn open_prs(fork: &str) -> Result<Vec<Pr>, String> {
    let out = Command::new("gh")
        .args(["pr", "list", "-R", fork, "--state", "open", "--limit", "300"])
        .args(["--json", "number,baseRefName,headRefName,headRefOid"])
        .args(["--jq", ".[] | [.number, .baseRefName, .headRefName, .headRefOid] | @tsv"])
        .output()
        .map_err(|e| format!("running gh: {e}"))?;
    if !out.status.success() {
        return Err(format!("gh pr list -R {fork}: {}", String::from_utf8_lossy(&out.stderr).trim()));
    }
    let mut v: Vec<Pr> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            (f.len() == 4).then(|| Pr {
                number: f[0].parse().unwrap_or(0),
                base: f[1].into(),
                head_ref: f[2].into(),
                gh_head: f[3].into(),
            })
        })
        .collect();
    v.sort_by_key(|p| p.number);
    Ok(v)
}

/// The branch a stacked PR finally merges into: follow PR bases until one of
/// `roots` (e.g. 5.0, common). None for a chain that never reaches one.
pub fn root_base(pr: &Pr, all: &[Pr], roots: &[&str]) -> Option<(String, Option<String>)> {
    let mut base = pr.base.clone();
    let mut parent = None;
    for _ in 0..30 {
        if roots.contains(&base.as_str()) {
            return Some((base, parent));
        }
        let up = all.iter().find(|p| p.head_ref == base)?;
        if parent.is_none() {
            parent = Some(up.head_ref.clone());
        }
        base = up.base.clone();
    }
    None
}

#[derive(Debug, Clone)]
pub struct Analysis {
    pub number: u64,
    pub head_ref: String,
    pub root: String,
    pub local_head: String,
    pub in_sync: bool,
    pub merge: Result<bool, Vec<String>>, // Ok(has_effect) | Err(conflicting files)
    pub own_commits: usize,
    pub equivalent: usize,
    pub touched: Vec<String>,
}

/// `old..new` per root, e.g. 5.0 = (a18c26c1f, refs/remotes/dcasota/5.0).
pub fn analyze(
    repo: &Path,
    fork: &str,
    bases: &BTreeMap<String, (String, String)>,
    log: &mut dyn FnMut(&str),
) -> Result<Vec<Analysis>, String> {
    let prs = open_prs(fork)?;
    let roots: Vec<&str> = bases.keys().map(String::as_str).collect();
    let mut out = Vec::new();
    for pr in &prs {
        let Some((root, parent)) = root_base(pr, &prs, &roots) else {
            log(&format!("  #{}: its base chain reaches none of {}", pr.number, roots.join(", ")));
            continue;
        };
        let (old, new) = &bases[&root];
        let local = git_in(repo, &["rev-parse", "--verify", "-q", &format!("refs/heads/{}", pr.head_ref)])
            .map(|s| s.trim().to_string());
        let head = match local {
            Ok(h) if !h.is_empty() => h,
            _ => {
                git_in(
                    repo,
                    &["fetch", "-q", &format!("https://github.com/{fork}.git"), &format!("+refs/heads/{0}:refs/sync/pr/{0}", pr.head_ref)],
                )?;
                git_in(repo, &["rev-parse", &format!("refs/sync/pr/{}", pr.head_ref)])?.trim().to_string()
            }
        };
        let own_base = match &parent {
            None => git_in(repo, &["merge-base", &head, old])?.trim().to_string(),
            Some(p) => {
                let ph = git_in(repo, &["rev-parse", "--verify", "-q", &format!("refs/heads/{p}")])
                    .or_else(|_| git_in(repo, &["rev-parse", &format!("refs/sync/pr/{p}")]))?;
                git_in(repo, &["merge-base", &head, ph.trim()])?.trim().to_string()
            }
        };
        let new_tree = git_in(repo, &["rev-parse", &format!("{new}^{{tree}}")])?.trim().to_string();
        let merge = match Command::new("git")
            .arg("-C")
            .arg(repo)
            .args(["merge-tree", "--write-tree", "--name-only", new, &head])
            .output()
        {
            Ok(o) if o.status.success() => {
                let tree = String::from_utf8_lossy(&o.stdout).lines().next().unwrap_or("").to_string();
                Ok(tree != new_tree)
            }
            Ok(o) => Err(String::from_utf8_lossy(&o.stdout)
                .lines()
                .skip(1)
                .take_while(|l| !l.is_empty())
                .map(str::to_string)
                .collect()),
            Err(e) => return Err(format!("git merge-tree: {e}")),
        };
        let pr_files: Vec<String> = git_in(repo, &["diff", "--name-only", &own_base, &head])?.lines().map(str::to_string).collect();
        let up_files: Vec<String> = git_in(repo, &["diff", "--name-only", old, new])?.lines().map(str::to_string).collect();
        let moved = base_renames(repo, old, new)?;
        let mut touched: Vec<String> = pr_files.iter().filter(|f| up_files.contains(f) && !moved.contains_key(*f)).cloned().collect();
        let moved_n = pr_files.iter().filter(|f| moved.contains_key(*f)).count();
        if moved_n > 0 {
            touched.push(format!("{moved_n} file(s) moved by upstream, e.g. {}", pr_files.iter().find(|f| moved.contains_key(*f)).map(|f| format!("{f} -> {}", moved[f])).unwrap_or_default()));
        }
        let own: Vec<String> = git_in(repo, &["rev-list", &format!("{own_base}..{head}")])?.lines().map(str::to_string).collect();
        let equivalent = git_in(repo, &["cherry", new, &head, &own_base])?.lines().filter(|l| l.starts_with('-')).count();
        out.push(Analysis {
            number: pr.number,
            head_ref: pr.head_ref.clone(),
            root,
            in_sync: head == pr.gh_head,
            local_head: head,
            merge,
            own_commits: own.len(),
            equivalent,
            touched,
        });
    }
    Ok(out)
}

/// What analyze concludes for one PR.
pub fn verdict(a: &Analysis) -> &'static str {
    match &a.merge {
        Err(_) => "conflict: rebase",
        Ok(false) => "no effect on the new base: candidate to close (check twice)",
        Ok(true) if a.own_commits > 0 && a.equivalent == a.own_commits => {
            "every commit already upstream: candidate to close (check twice)"
        }
        Ok(true) if !a.touched.is_empty() => "merges, but upstream touched its files: rebase and re-verify",
        Ok(true) => "merges cleanly: keep",
    }
}

// --- rebase -----------------------------------------------------------------

/// `Release:` lines; the value may be dotted (17.2.3).
fn release_value(spec: &str) -> Option<String> {
    spec.lines().find_map(|l| {
        let r = l.strip_prefix("Release:")?.trim();
        let v: String = r.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
        (!v.is_empty()).then_some(v)
    })
}

/// The next release after `r`: the last component plus one, so a dotted
/// release stays dotted (17.2.2 -> 17.2.3) and an integer one stays integer.
pub fn next_release(r: &str) -> Option<String> {
    let mut parts: Vec<String> = r.split('.').map(str::to_string).collect();
    let last = parts.last_mut()?;
    *last = (last.parse::<u64>().ok()? + 1).to_string();
    Some(parts.join("."))
}

const REL_MASK: &str = "@SHARUKHAN-RELEASE@";

/// Release values masked and everything after `%changelog` dropped, so a
/// three-way merge sees neither.
pub fn mask(spec: &str) -> String {
    let mut out = String::new();
    for l in spec.split_inclusive('\n') {
        if let Some(rest) = l.strip_prefix("Release:") {
            let ws: String = rest.chars().take_while(|c| *c == ' ' || *c == '\t').collect();
            let after = &rest[ws.len()..];
            let num: String = after.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
            out.push_str(&format!("Release:{ws}{REL_MASK}{}", &after[num.len()..]));
        } else {
            out.push_str(l);
        }
        if l.trim_end() == "%changelog" {
            break;
        }
    }
    out
}

fn changelog_body(spec: &str) -> &str {
    match spec.find("\n%changelog\n") {
        Some(i) => &spec[i + "\n%changelog\n".len()..],
        None => "",
    }
}

fn merge3(base: &str, ours: &str, theirs: &str) -> Result<String, ()> {
    // one directory per call: two merges within the same second must not share files
    static SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let seq = SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let d = std::env::temp_dir().join(format!("shk-merge3-{}-{}-{seq}", std::process::id(), crate::job::stamp()));
    let _ = fs::create_dir_all(&d);
    let (o, b, t) = (d.join("o"), d.join("b"), d.join("t"));
    let r = (|| {
        fs::write(&o, ours).map_err(|_| ())?;
        fs::write(&b, base).map_err(|_| ())?;
        fs::write(&t, theirs).map_err(|_| ())?;
        let out = Command::new("git").args(["merge-file", "-p"]).arg(&o).arg(&b).arg(&t).output().map_err(|_| ())?;
        if out.status.success() {
            Ok(String::from_utf8_lossy(&out.stdout).to_string())
        } else {
            Err(())
        }
    })();
    let _ = fs::remove_dir_all(&d);
    r
}

/// The new content of a spec the PR changed: merged with Release and changelog
/// masked, Release = base + 1, the PR's top entry redated and renumbered on
/// top of the base's changelog.
pub fn rebase_spec(prev: &str, cur: &str, pr: &str, pr_head: &str, base: &str, date: &str, stacked: bool) -> Result<(String, String), String> {
    let merged = merge3(&mask(prev), &mask(cur), &mask(pr)).map_err(|_| "conflict beyond Release and %changelog".to_string())?;
    let base_rel = release_value(base).ok_or("no Release in the base")?;
    // A stacked PR amends its parent's entry: same Release, its line replaces
    // the parent's, so the stack still adds exactly one entry.
    let parent_entry = stacked && changelog_body(base).lines().next().is_some_and(|l| l.starts_with("* ") && l.contains(AUTHOR));
    let next = if parent_entry {
        base_rel.clone()
    } else {
        next_release(&base_rel).ok_or_else(|| format!("cannot increment Release {base_rel}"))?
    };
    let version = merged
        .lines()
        .find_map(|l| l.strip_prefix("Version:").map(|v| v.trim().to_string()))
        .ok_or("no Version")?;
    let entry: Vec<&str> = changelog_body(pr_head).lines().take(2).collect();
    if entry.len() < 2 || !entry[0].starts_with("* ") || !entry[0].contains(AUTHOR) {
        return Err(format!("the top changelog entry of the PR is not its own: {}", entry.first().unwrap_or(&"")));
    }
    let rest: String = if parent_entry {
        // drop the parent's entry: its header and its lines up to the next entry
        let body = changelog_body(base);
        let mut lines = body.lines();
        lines.next();
        let tail: Vec<&str> = lines.skip_while(|l| !l.starts_with("* ")).collect();
        if tail.is_empty() { String::new() } else { tail.join("\n") + "\n" }
    } else {
        changelog_body(base).to_string()
    };
    let out = format!("{}* {date} {AUTHOR} {version}-{next}\n{}\n{}", merged.replace(REL_MASK, &next), entry[1], rest);
    Ok((out, format!("{version}-{next}")))
}

/// Renames the base made between `old` and `new`: old path -> new path.
pub fn base_renames(repo: &Path, old: &str, new: &str) -> Result<BTreeMap<String, String>, String> {
    let out = git_in(repo, &["diff", "--name-status", "-M", "--diff-filter=R", old, new])?;
    Ok(out
        .lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split('\t').collect();
            (f.len() == 3).then(|| (f[1].to_string(), f[2].to_string()))
        })
        .collect())
}

/// Directories the base moved as a whole: every file it renamed out of `a/`
/// went to the same `b/`. A file a PR adds in `a/` belongs in `b/`.
pub fn dir_moves(renames: &BTreeMap<String, String>) -> BTreeMap<String, String> {
    let mut seen: BTreeMap<String, Option<String>> = BTreeMap::new();
    for (old, new) in renames {
        let (Some(od), Some(nd)) = (Path::new(old).parent(), Path::new(new).parent()) else { continue };
        if Path::new(old).file_name() != Path::new(new).file_name() || od == nd {
            continue;
        }
        let (od, nd) = (od.to_string_lossy().to_string(), nd.to_string_lossy().to_string());
        let e = seen.entry(od).or_insert_with(|| Some(nd.clone()));
        if e.as_deref() != Some(nd.as_str()) {
            *e = None; // split across targets: not a directory move
        }
    }
    seen.into_iter().filter_map(|(k, v)| v.map(|v| (k, v))).collect()
}

/// Where a PR path lands on the new base: its own rename, else the move of its
/// directory (deepest first), else unchanged.
pub fn map_path(path: &str, renames: &BTreeMap<String, String>, dirs: &BTreeMap<String, String>) -> String {
    if let Some(n) = renames.get(path) {
        return n.clone();
    }
    let mut d = Path::new(path).parent();
    while let Some(dir) = d {
        let key = dir.to_string_lossy().to_string();
        if let Some(to) = dirs.get(&key) {
            return format!("{to}{}", &path[key.len()..]);
        }
        d = dir.parent();
    }
    path.to_string()
}

/// Equal once what a sync itself rewrites is set aside: a spec's Release
/// values and `%changelog`, the entry header lines of a changelog .inc.
pub fn same_beyond_bookkeeping(path: &str, a: &str, b: &str) -> bool {
    let name = path.rsplit('/').next().unwrap_or(path);
    if path.ends_with(".spec") {
        mask(a) == mask(b)
    } else if name.contains("changelog") && name.ends_with(".inc") {
        let body = |t: &str| t.lines().filter(|l| !l.starts_with("* ")).map(str::to_string).collect::<Vec<_>>();
        body(a) == body(b)
    } else {
        a == b
    }
}

pub struct RebaseResult {
    pub head: String,
    pub commits: Vec<String>,
    pub dropped: Vec<String>,
    pub releases: BTreeMap<String, String>,
}

/// Replay the PR's own commits (`own_base..src`) onto `new_base` in a scratch
/// worktree; return the new head. Nothing outside the worktree changes.
pub fn rebase(
    repo: &Path,
    src: &str,
    own_base: &str,
    old_base: &str,
    new_base: &str,
    date: &str,
    work: &Path,
    stacked: bool,
) -> Result<RebaseResult, String> {
    let renames = base_renames(repo, old_base, new_base)?;
    let _ = git_in(repo, &["worktree", "remove", "--force", &work.to_string_lossy()]);
    git_in(repo, &["worktree", "add", "--detach", &work.to_string_lossy(), new_base])?;
    let r = replay(repo, work, src, own_base, new_base, date, &renames, stacked);
    let _ = git_in(repo, &["worktree", "remove", "--force", &work.to_string_lossy()]);
    r
}

fn replay(
    repo: &Path,
    w: &Path,
    src: &str,
    own_base: &str,
    new_base: &str,
    date: &str,
    renames: &BTreeMap<String, String>,
    stacked: bool,
) -> Result<RebaseResult, String> {
    let commits: Vec<String> = git_in(repo, &["rev-list", "--reverse", &format!("{own_base}..{src}")])?
        .lines()
        .map(str::to_string)
        .collect();
    let dirs = dir_moves(renames);
    let mut res = RebaseResult { head: String::new(), commits: vec![], dropped: vec![], releases: BTreeMap::new() };
    for c in &commits {
        let changes = git_in(repo, &["diff-tree", "--no-commit-id", "-r", "--name-status", "--no-renames", &format!("{c}^"), c])?;
        for st in changes.lines() {
            let f: Vec<&str> = st.split('\t').collect();
            if f.len() != 2 {
                continue;
            }
            let (kind, path) = (f[0], f[1]);
            let target = map_path(path, renames, &dirs);
            let abs = w.join(&target);
            let prev = show(repo, &format!("{c}^"), path);
            let pr = show(repo, c, path);
            let cur = fs::read_to_string(&abs).ok();
            match kind {
                "D" => {
                    // a parent's rebase renumbers and re-dates its own entries;
                    // only a change beyond that is upstream's
                    let differs = match (&cur, &prev) {
                        (Some(c), Some(p)) => !same_beyond_bookkeeping(&target, c, p),
                        (c, p) => c.is_some() != p.is_some(),
                    };
                    if cur.is_some() && differs {
                        return Err(format!("{target}: deleted by the PR but changed upstream"));
                    }
                    if cur.is_some() {
                        git_in(w, &["rm", "-q", &target])?;
                    }
                }
                "A" => {
                    let pr = pr.ok_or_else(|| format!("{path}: added but unreadable"))?;
                    if cur.is_some() && cur.as_deref() != Some(pr.as_str()) {
                        return Err(format!("{target}: added by the PR and differently upstream"));
                    }
                    if let Some(d) = abs.parent() {
                        fs::create_dir_all(d).map_err(|e| format!("{}: {e}", d.display()))?;
                    }
                    fs::write(&abs, &pr).map_err(|e| format!("{target}: {e}"))?;
                    git_in(w, &["add", &target])?;
                }
                _ => {
                    let (prev, pr) = (prev.unwrap_or_default(), pr.unwrap_or_default());
                    let cur = cur.ok_or_else(|| format!("{target}: changed by the PR but gone upstream"))?;
                    let out = if target.ends_with(".spec") {
                        let base_spec = show(repo, new_base, &target).ok_or_else(|| format!("{target}: not in the base"))?;
                        let pr_head = show(repo, src, path).unwrap_or_else(|| pr.clone());
                        let (text, vr) = rebase_spec(&prev, &cur, &pr, &pr_head, &base_spec, date, stacked)
                            .map_err(|e| format!("{target}: {e}"))?;
                        res.releases.insert(target.clone(), vr);
                        text
                    } else if target.ends_with(".inc") && target.contains("changelog") {
                        return Err(format!("{target}: a changelog include needs a person (its entries are not a spec's %changelog)"));
                    } else {
                        merge3(&prev, &cur, &pr).map_err(|_| format!("{target}: conflict"))?
                    };
                    fs::write(&abs, &out).map_err(|e| format!("{target}: {e}"))?;
                    git_in(w, &["add", &target])?;
                }
            }
        }
        let staged = git_in(w, &["diff", "--cached", "--name-only"])?;
        let subject = git_in(repo, &["log", "-1", "--format=%s", c])?.trim().to_string();
        if staged.trim().is_empty() {
            res.dropped.push(format!("{} {subject}", &c[..9]));
            continue;
        }
        let msg = git_in(repo, &["log", "-1", "--format=%B", c])?;
        let who = |f: &str| git_in(repo, &["log", "-1", &format!("--format={f}"), c]).map(|s| s.trim().to_string());
        let out = Command::new("git")
            .arg("-C")
            .arg(w)
            .args(["commit", "-q", "-F", "-"])
            .env("GIT_AUTHOR_NAME", who("%an")?)
            .env("GIT_AUTHOR_EMAIL", who("%ae")?)
            .env("GIT_AUTHOR_DATE", who("%aD")?)
            .env("GIT_COMMITTER_NAME", "Daniel Casota")
            .env("GIT_COMMITTER_EMAIL", "dcasota@gmail.com")
            .stdin(std::process::Stdio::piped())
            .spawn()
            .and_then(|mut ch| {
                use std::io::Write;
                ch.stdin.take().map(|mut s| s.write_all(msg.as_bytes()));
                ch.wait_with_output()
            })
            .map_err(|e| format!("git commit: {e}"))?;
        if !out.status.success() {
            return Err(format!("git commit failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
        }
        res.commits.push(format!("{} {subject}", git_in(w, &["rev-parse", "--short=9", "HEAD"])?.trim()));
    }
    res.head = git_in(w, &["rev-parse", "HEAD"])?.trim().to_string();
    Ok(res)
}

// --- verify -----------------------------------------------------------------

/// Evaluate a build_if expression with the subrelease substituted: integers,
/// comparisons, `!`, `&&`, `||`, parentheses. None when it is not that.
pub fn eval_build_if(expr: &str, sub: u32) -> Option<bool> {
    let e = expr
        .replace("0%{?photon_subrelease}", &sub.to_string())
        .replace("%{?photon_subrelease}", &sub.to_string())
        .replace("%{photon_subrelease}", &sub.to_string());
    let toks = tokenize(&e)?;
    let mut p = 0;
    let v = or_expr(&toks, &mut p)?;
    (p == toks.len()).then_some(v != 0)
}

fn tokenize(s: &str) -> Option<Vec<String>> {
    let mut out = Vec::new();
    let c: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < c.len() {
        if c[i].is_whitespace() {
            i += 1;
        } else if c[i].is_ascii_digit() {
            let st = i;
            while i < c.len() && c[i].is_ascii_digit() {
                i += 1;
            }
            out.push(c[st..i].iter().collect());
        } else {
            let two: String = c[i..(i + 2).min(c.len())].iter().collect();
            if ["&&", "||", "==", "!=", ">=", "<="].contains(&two.as_str()) {
                out.push(two);
                i += 2;
            } else if "()<>!".contains(c[i]) {
                out.push(c[i].to_string());
                i += 1;
            } else {
                return None;
            }
        }
    }
    Some(out)
}

fn or_expr(t: &[String], p: &mut usize) -> Option<i64> {
    let mut v = and_expr(t, p)?;
    while t.get(*p).map(String::as_str) == Some("||") {
        *p += 1;
        let r = and_expr(t, p)?;
        v = ((v != 0) || (r != 0)) as i64;
    }
    Some(v)
}

fn and_expr(t: &[String], p: &mut usize) -> Option<i64> {
    let mut v = cmp_expr(t, p)?;
    while t.get(*p).map(String::as_str) == Some("&&") {
        *p += 1;
        let r = cmp_expr(t, p)?;
        v = ((v != 0) && (r != 0)) as i64;
    }
    Some(v)
}

fn cmp_expr(t: &[String], p: &mut usize) -> Option<i64> {
    let l = unary(t, p)?;
    let op = t.get(*p).map(String::as_str);
    let f: fn(i64, i64) -> bool = match op {
        Some("==") => |a, b| a == b,
        Some("!=") => |a, b| a != b,
        Some(">=") => |a, b| a >= b,
        Some("<=") => |a, b| a <= b,
        Some(">") => |a, b| a > b,
        Some("<") => |a, b| a < b,
        _ => return Some(l),
    };
    *p += 1;
    let r = unary(t, p)?;
    Some(f(l, r) as i64)
}

fn unary(t: &[String], p: &mut usize) -> Option<i64> {
    match t.get(*p).map(String::as_str)? {
        "!" => {
            *p += 1;
            Some((unary(t, p)? == 0) as i64)
        }
        "(" => {
            *p += 1;
            let v = or_expr(t, p)?;
            (t.get(*p).map(String::as_str) == Some(")")).then(|| *p += 1)?;
            Some(v)
        }
        n => {
            let v = n.parse().ok()?;
            *p += 1;
            Some(v)
        }
    }
}

/// The subreleases a spec builds for, from its `%global build_if`.
pub fn subreleases_for(spec: &str, candidates: &[u32]) -> Vec<u32> {
    let cond = spec.lines().find_map(|l| l.trim().strip_prefix("%global build_if").map(|r| r.trim().to_string()));
    candidates
        .iter()
        .copied()
        .filter(|s| cond.as_deref().map(|c| eval_build_if(c, *s).unwrap_or(true)).unwrap_or(true))
        .collect()
}

#[derive(Debug)]
pub struct Check {
    pub spec: String,
    pub subrelease: u32,
    pub what: String,
    pub ok: bool,
    pub detail: String,
}

/// Merge `r` onto `base`, extract the merged SPECS and check every changed spec.
pub fn verify(
    repo: &Path,
    base: &str,
    r: &str,
    common: &Path,
    work: &Path,
    subs: &[u32],
    log: &mut dyn FnMut(&str),
) -> Result<Vec<Check>, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["merge-tree", "--write-tree", base, r])
        .output()
        .map_err(|e| format!("git merge-tree: {e}"))?;
    if !out.status.success() {
        return Err(format!("{r} does not merge onto {base}"));
    }
    let tree = String::from_utf8_lossy(&out.stdout).lines().next().unwrap_or("").to_string();
    let _ = fs::remove_dir_all(work);
    fs::create_dir_all(work).map_err(|e| format!("{}: {e}", work.display()))?;
    let tar = Command::new("sh")
        .arg("-c")
        .arg("git -C \"$1\" archive \"$2\" SPECS data 2>/dev/null | tar -x -C \"$3\" || git -C \"$1\" archive \"$2\" SPECS | tar -x -C \"$3\"")
        .args(["sh", &repo.to_string_lossy(), &tree, &work.to_string_lossy()])
        .status()
        .map_err(|e| format!("git archive: {e}"))?;
    if !tar.success() {
        return Err("extracting the merged SPECS failed".into());
    }
    let changed: Vec<String> = git_in(repo, &["diff", "--name-only", base, &tree, "--", "*.spec"])?
        .lines()
        .map(str::to_string)
        .filter(|f| work.join(f).is_file())
        .collect();
    let checker = common.join("support/spec-checker/check_spec.py");
    let mut checks = Vec::new();
    let incs: Vec<String> = git_in(repo, &["diff", "--name-only", base, &tree, "--", "*changelog*.inc"])?
        .lines()
        .map(str::to_string)
        .filter(|f| work.join(f).is_file())
        .collect();
    for g in &incs {
        let mine = fs::read_to_string(work.join(g)).map_err(|e| format!("{g}: {e}"))?;
        let reference = crate::branchguard::package_changelogs(repo, base, g);
        let before = crate::branchguard::file_at(repo, base, g);
        let problems = crate::branchguard::single_entry_problems(&reference, &before, &mine, AUTHOR, 10);
        checks.push(Check { spec: g.clone(), subrelease: 0, what: "changelog".into(), ok: problems.is_empty(), detail: problems.join(" | ") });
    }
    for f in &changed {
        let abs = work.join(f);
        let text = fs::read_to_string(&abs).map_err(|e| format!("{f}: {e}"))?;
        let dir = abs.parent().unwrap_or(work).to_path_buf();
        for sub in subreleases_for(&text, subs) {
            for arch in ["x86_64", "aarch64"] {
                let args: Vec<OsString> = vec![
                    "-P".into(),
                    "--target".into(),
                    arch.into(),
                    "--define".into(),
                    format!("photon_subrelease {sub}").into(),
                    "--define".into(),
                    "dist .ph5".into(),
                    "--define".into(),
                    format!("_sourcedir {}", dir.display()).into(),
                    abs.clone().into(),
                ];
                let o = crate::builder::tool_command("rpmspec", &dir, &args, log)?
                    .output()
                    .map_err(|e| format!("rpmspec: {e}"))?;
                let err = String::from_utf8_lossy(&o.stderr);
                checks.push(Check {
                    spec: f.clone(),
                    subrelease: sub,
                    what: format!("rpmspec {arch}"),
                    ok: o.status.success(),
                    detail: err.lines().find(|l| l.contains("error")).unwrap_or("").to_string(),
                });
            }
            let args: Vec<OsString> = vec![
                checker.clone().into(),
                "--mainline".into(),
                "93".into(),
                "--subrelease".into(),
                sub.to_string().into(),
                abs.clone().into(),
            ];
            let o = crate::builder::python_command(common, &args, log)?
                .output()
                .map_err(|e| format!("check_spec: {e}"))?;
            let all = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
            checks.push(Check {
                spec: f.clone(),
                subrelease: sub,
                what: "check_spec".into(),
                ok: o.status.success(),
                detail: all.lines().filter(|l| l.contains("ERROR") || l.contains("Error")).take(2).collect::<Vec<_>>().join(" | "),
            });
        }
        // one changelog entry, one short line, against the base; a spec whose
        // changelog lives in included files is checked per file below, and
        // here only for the base's entries it must still carry somewhere
        let reference = crate::branchguard::package_changelogs(repo, base, f);
        let before = crate::branchguard::file_at(repo, base, f);
        let problems = if text.contains("%changelog") {
            crate::branchguard::single_entry_problems(&reference, &before, &text, AUTHOR, 10)
        } else {
            crate::branchguard::dropped_entries(&before, &crate::branchguard::package_changelogs(repo, &tree, f), AUTHOR)
        };
        checks.push(Check {
            spec: f.clone(),
            subrelease: 0,
            what: "changelog".into(),
            ok: problems.is_empty(),
            detail: problems.join(" | "),
        });
    }
    Ok(checks)
}

// --- CLI --------------------------------------------------------------------

fn opt<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).map(String::as_str)
}

fn opts<'a>(args: &'a [String], name: &str) -> Vec<&'a str> {
    args.iter()
        .enumerate()
        .filter(|(_, a)| *a == name)
        .filter_map(|(i, _)| args.get(i + 1).map(String::as_str))
        .collect()
}

fn today() -> String {
    Command::new("date")
        .args(["-u", "+%a %b %d %Y"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

const USAGE: &str = "usage:
  sharukhan sync analyze --repo <git dir> --fork <owner/repo> --base <name>=<old>..<new> [--base ...]
  sharukhan sync rebase  --repo <git dir> --src <ref> --own-base <rev> --old-base <rev> --new-base <rev> --branch <name> [--stacked] [--date 'Wed Oct 21 2026']
  sharukhan sync verify  --repo <git dir> --base <rev> --common <common tree> <ref>...";

pub fn cli(args: &[String]) -> u8 {
    let mut log = |l: &str| println!("{l}");
    let r = (|| -> Result<bool, String> {
        let sub = args.first().map(String::as_str).ok_or(USAGE)?;
        let rest = &args[1..];
        let repo = PathBuf::from(opt(rest, "--repo").ok_or(USAGE)?);
        match sub {
            "analyze" => {
                let fork = opt(rest, "--fork").ok_or(USAGE)?;
                let mut bases = BTreeMap::new();
                for b in opts(rest, "--base") {
                    let (name, range) = b.split_once('=').ok_or(USAGE)?;
                    let (old, new) = range.split_once("..").ok_or(USAGE)?;
                    bases.insert(name.to_string(), (old.to_string(), new.to_string()));
                }
                if bases.is_empty() {
                    return Err(USAGE.into());
                }
                let res = analyze(&repo, fork, &bases, &mut log)?;
                for a in &res {
                    let m = match &a.merge {
                        Ok(true) => "clean".to_string(),
                        Ok(false) => "clean, no effect".to_string(),
                        Err(f) => format!("CONFLICT {}", f.join(" ")),
                    };
                    println!(
                        "#{:<4} {:<45} {:<6} {} {} own={} upstream={} touched={} -> {}",
                        a.number,
                        a.head_ref,
                        a.root,
                        &a.local_head[..9],
                        if a.in_sync { "gh=local" } else { "gh!=local" },
                        a.own_commits,
                        a.equivalent,
                        if a.touched.is_empty() { "none".to_string() } else { a.touched.join(",") },
                        verdict(a)
                    );
                    let _ = m;
                }
                let conflicts = res.iter().filter(|a| a.merge.is_err()).count();
                println!("PRs: {}, conflicts: {conflicts}", res.len());
                Ok(true)
            }
            "rebase" => {
                let need = |n: &str| opt(rest, n).ok_or_else(|| format!("{n} missing\n{USAGE}"));
                let branch = need("--branch")?;
                let work = repo.join(format!(".sharukhan-sync-{}", branch.replace('/', "-")));
                let date = opt(rest, "--date").map(str::to_string).unwrap_or_else(today);
                let stacked = rest.iter().any(|a| a == "--stacked");
                let r = rebase(&repo, need("--src")?, need("--own-base")?, need("--old-base")?, need("--new-base")?, &date, &work, stacked);
                match r {
                    Ok(res) => {
                        git_in(&repo, &["update-ref", &format!("refs/heads/{branch}"), &res.head])?;
                        for c in &res.commits {
                            println!("commit {c}");
                        }
                        for d in &res.dropped {
                            println!("EMPTY after rebase, dropped: {d}");
                        }
                        for (f, vr) in &res.releases {
                            println!("  {f} {vr}");
                        }
                        println!("{branch} = {}", &res.head[..12]);
                        Ok(true)
                    }
                    Err(e) => {
                        println!("REFUSED: {e}");
                        Ok(false)
                    }
                }
            }
            "verify" => {
                let base = opt(rest, "--base").ok_or(USAGE)?;
                let common = PathBuf::from(opt(rest, "--common").ok_or(USAGE)?);
                let skip = ["--repo", "--base", "--common"];
                let refs: Vec<&String> = rest
                    .iter()
                    .enumerate()
                    .filter(|(i, a)| !a.starts_with("--") && !(i > &0 && skip.contains(&rest[i - 1].as_str())))
                    .map(|(_, a)| a)
                    .collect();
                let root = crate::builder::shared_root();
                let mut all_ok = true;
                for r in refs {
                    let work = root.join("work").join(format!("sync-verify-{}", r.replace('/', "-")));
                    match verify(&repo, base, r, &common, &work, &[90, 91, 92, 93], &mut log) {
                        Ok(checks) => {
                            let bad: Vec<&Check> = checks.iter().filter(|c| !c.ok).collect();
                            println!("{r}: {} check(s), {} failed", checks.len(), bad.len());
                            for c in bad {
                                println!("  FAIL {} sr{} {}: {}", c.spec, c.subrelease, c.what, c.detail);
                                all_ok = false;
                            }
                        }
                        Err(e) => {
                            println!("{r}: {e}");
                            all_ok = false;
                        }
                    }
                    let _ = fs::remove_dir_all(&work);
                }
                Ok(all_ok)
            }
            _ => Err(USAGE.into()),
        }
    })();
    match r {
        Ok(true) => 0,
        Ok(false) => 2,
        Err(e) => {
            eprintln!("sharukhan sync: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bookkeeping_is_not_an_upstream_change() {
        let a = "Release: 2%{?dist}\nBuildRequires: x\n%changelog\n* Mon Oct 19 2026 D <d> 1-2\n- y\n";
        let b = "Release: 3%{?dist}\nBuildRequires: x\n%changelog\n* Fri Oct 23 2026 D <d> 1-3\n- y\n";
        assert!(same_beyond_bookkeeping("SPECS/90/linux/linux.spec", a, b));
        assert!(!same_beyond_bookkeeping("SPECS/90/linux/linux.spec", a, &b.replace("x", "z")));
        assert!(same_beyond_bookkeeping("SPECS/linux/linux-esx-6.12-changelog.inc", "* Mon a 1\n- y\n", "* Fri b 2\n- y\n"));
        assert!(!same_beyond_bookkeeping("SPECS/linux/x.patch", "a\n", "b\n"));
    }

    #[test]
    fn a_release_increments_its_last_component_and_keeps_its_shape() {
        assert_eq!(next_release("5").as_deref(), Some("6"));
        assert_eq!(next_release("17.2.2").as_deref(), Some("17.2.3"));
        assert_eq!(next_release("5.1.9").as_deref(), Some("5.1.10"));
        assert_eq!(next_release("x"), None);
    }

    #[test]
    fn build_if_is_evaluated_per_subrelease() {
        assert_eq!(eval_build_if("%{photon_subrelease} >= 92", 91), Some(false));
        assert_eq!(eval_build_if("0%{?photon_subrelease} == 91 || 0%{?photon_subrelease} >= 93", 93), Some(true));
        assert_eq!(eval_build_if("!(%{photon_subrelease} < 92) && %{photon_subrelease} != 93", 92), Some(true));
        assert_eq!(eval_build_if("%{with_foo}", 92), None);
        let spec = "Name: x\n%global build_if %{photon_subrelease} <= 90\n";
        assert_eq!(subreleases_for(spec, &[90, 91, 92]), vec![90]);
        assert_eq!(subreleases_for("Name: x\n", &[90, 91]), vec![90, 91]);
    }

    #[test]
    fn a_spec_is_rebased_to_one_entry_on_top_of_the_new_base() {
        let head = |rel: &str, ver: &str, extra: &str, cl: &str| {
            format!("Name: p\nVersion: {ver}\nRelease: {rel}%{{?dist}}\n{extra}\n%changelog\n{cl}")
        };
        let prev = head("3", "1.0", "", "* Mon Oct 19 2026 X Y <x@y> 1.0-3\n- Old\n");
        let pr = head(
            "4",
            "1.0",
            "Patch9: fix.patch",
            "* Tue Oct 20 2026 Daniel Casota <dcasota@gmail.com> 1.0-4\n- Fix the thing\n* Mon Oct 19 2026 X Y <x@y> 1.0-3\n- Old\n",
        );
        // upstream moved to 1.1-1 meanwhile
        let base = head("1", "1.1", "", "* Thu Oct 22 2026 X Y <x@y> 1.1-1\n- Update to 1.1\n* Mon Oct 19 2026 X Y <x@y> 1.0-3\n- Old\n");
        let (out, vr) = rebase_spec(&prev, &base, &pr, &pr, &base, "Fri Oct 23 2026", false).unwrap();
        assert_eq!(vr, "1.1-2");
        assert!(out.contains("Version: 1.1\nRelease: 2%{?dist}\nPatch9: fix.patch\n"), "{out}");
        assert!(out.contains("%changelog\n* Fri Oct 23 2026 Daniel Casota <dcasota@gmail.com> 1.1-2\n- Fix the thing\n* Thu Oct 22 2026 X Y <x@y> 1.1-1\n"), "{out}");
        assert_eq!(out.matches("Daniel Casota").count(), 1);
        // a PR whose top entry is not its own is refused
        let foreign = head("4", "1.0", "Patch9: fix.patch", "* Tue Oct 20 2026 X Y <x@y> 1.0-4\n- Not mine\n");
        assert!(rebase_spec(&prev, &base, &foreign, &foreign, &base, "Fri Oct 23 2026", false).unwrap_err().contains("not its own"));
        // a real conflict is refused, not resolved
        let other = head("1", "1.1", "Patch9: other.patch", "");
        assert!(rebase_spec(&prev, &other, &pr, &pr, &base, "Fri Oct 23 2026", false).unwrap_err().contains("conflict"));
    }

    #[test]
    fn a_stacked_pr_amends_its_parents_entry_instead_of_adding_one() {
        let spec = |rel: &str, extra: &str, cl: &str| format!("Name: p\nVersion: 2.0\nRelease: {rel}%{{?dist}}\n{extra}\n%changelog\n{cl}");
        let up = "* Thu Oct 22 2026 X Y <x@y> 2.0-1\n- Update\n";
        // the rebased parent: one entry of ours on top of upstream
        let parent = spec("2", "Patch1: a.patch", &format!("* Fri Oct 23 2026 Daniel Casota <dcasota@gmail.com> 2.0-2\n- Do A\n{up}"));
        // the child before the rebase: on the old parent, its line replaced the parent's
        let prev = spec("2", "Patch1: a.patch", "* Mon Oct 19 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Do A\n");
        let pr = spec("2", "Patch1: a.patch\nPatch2: b.patch", "* Tue Oct 20 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Do A and B\n");
        let (out, vr) = rebase_spec(&prev, &parent, &pr, &pr, &parent, "Fri Oct 23 2026", true).unwrap();
        assert_eq!(vr, "2.0-2", "the stack keeps the parent's Release");
        assert_eq!(out.matches("Daniel Casota").count(), 1, "{out}");
        assert!(out.contains("2.0-2\n- Do A and B\n* Thu Oct 22 2026 X Y <x@y> 2.0-1"), "{out}");
        // a root PR on a base whose top entry happens to be ours still adds one
        let (_, vr2) = rebase_spec(&prev, &parent, &pr, &pr, &parent, "Fri Oct 23 2026", false).unwrap();
        assert_eq!(vr2, "2.0-3");
    }

    #[test]
    fn files_added_in_a_moved_directory_follow_the_move() {
        let mut r = BTreeMap::new();
        r.insert("SPECS/linux/linux.spec".to_string(), "SPECS/92/linux/linux.spec".to_string());
        r.insert("SPECS/linux/patches/a.patch".to_string(), "SPECS/92/linux/patches/a.patch".to_string());
        r.insert("SPECS/x/one".to_string(), "SPECS/y/one".to_string());
        r.insert("SPECS/x/two".to_string(), "SPECS/z/two".to_string());
        let d = dir_moves(&r);
        assert_eq!(map_path("SPECS/linux/canister_config.inc", &r, &d), "SPECS/92/linux/canister_config.inc");
        assert_eq!(map_path("SPECS/linux/patches/new.patch", &r, &d), "SPECS/92/linux/patches/new.patch");
        assert_eq!(map_path("SPECS/linux/linux.spec", &r, &d), "SPECS/92/linux/linux.spec");
        assert_eq!(map_path("SPECS/x/three", &r, &d), "SPECS/x/three", "a split directory is not a move");
        assert_eq!(map_path("SPECS/other/f", &r, &d), "SPECS/other/f");
    }

    #[test]
    fn a_stacked_pr_finds_its_root_and_parent() {
        let p = |n: u64, base: &str, head: &str| Pr { number: n, base: base.into(), head_ref: head.into(), gh_head: String::new() };
        let all = vec![p(24, "5.0", "a"), p(29, "a", "b"), p(36, "b", "c"), p(9, "nowhere", "z")];
        assert_eq!(root_base(&all[2], &all, &["5.0", "common"]), Some(("5.0".into(), Some("b".into()))));
        assert_eq!(root_base(&all[0], &all, &["5.0"]), Some(("5.0".into(), None)));
        assert_eq!(root_base(&all[3], &all, &["5.0"]), None);
    }
}
