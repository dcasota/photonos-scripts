//! PR descriptions across a sync: carry the written description to the
//! rebased head and check it still describes that head.
//!
//! A sync does not change what a PR is for, so Problem and Change keep their
//! words. What a rebase can make wrong is mechanical: a path the base moved
//! (`SPECS/linux` -> `SPECS/92/linux`) and a Release the PR introduces that had
//! to move past a new upstream bump (6.12.113-2 -> 6.12.113-3). `rewrite`
//! changes exactly those, from evidence (the base's renames, the specs at the
//! old and new heads); `lint` then refuses a body that still names a path
//! neither the head nor its base has, a Release the PR no longer introduces,
//! a missing section, a stale Dependencies line, run-internal numbers or a
//! session link. A body that fails the lint is not published automatically:
//! it is escalation material.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::process::Command;

pub const FOOTER: &str = "🤖 Generated with [Claude Code](https://claude.com/claude-code)";

/// Everything the rewrite and the lint know about one PR, gathered from git.
#[derive(Debug, Default, Clone)]
pub struct Facts {
    /// old path -> new path, files and whole directories the base moved
    pub paths: BTreeMap<String, String>,
    /// Version-Release the PR introduced at its old head -> at its new head
    pub releases: BTreeMap<String, String>,
    /// Version-Release of the same specs on the old base -> on the new base
    pub base_releases: BTreeMap<String, String>,
    /// every file and directory of the new head and of the new base
    pub tree: BTreeSet<String>,
    /// the same of the old head and the old base: a path only these have is
    /// one the sync made stale; a path neither has (another branch's tree,
    /// upstream's) was never the sync's to judge
    pub old_tree: BTreeSet<String>,
    /// the PR number this one is stacked on
    pub parent: Option<u64>,
}

fn path_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | '-' | '+')
}

/// Path-like tokens under SPECS/ with their byte ranges; globs and brace
/// lists are not paths and are skipped.
fn spec_paths(text: &str) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let b = text.as_bytes();
    let mut i = 0;
    while let Some(off) = text[i..].find("SPECS") {
        let s = i + off;
        let boundary = s == 0 || !path_char(text[..s].chars().next_back().unwrap_or(' '));
        let mut e = s;
        while e < b.len() && path_char(b[e] as char) {
            e += 1;
        }
        // a sentence's full stop is not part of the path
        while e > s && matches!(b[e - 1], b'.' | b'-' | b'/') {
            e -= 1;
        }
        let glob = e < b.len() && matches!(b[e], b'*' | b'{' | b'?' | b'[');
        let tok = &text[s..e];
        if boundary && !glob && (tok == "SPECS" || tok.starts_with("SPECS/")) {
            out.push((s, e));
        }
        i = e.max(s + 5);
    }
    out
}

fn release_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '.' || c == '-'
}

/// Replace whole tokens only: `6.12.113-2` must not match inside `6.12.113-21`.
fn replace_token(text: &str, from: &str, to: &str, tok_char: fn(char) -> bool) -> String {
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while let Some(off) = text[i..].find(from) {
        let s = i + off;
        let e = s + from.len();
        let before = text[..s].chars().next_back().map_or(false, tok_char);
        // a trailing full stop ends a sentence, not the token
        let after = text[e..].chars().next().map_or(false, |c| tok_char(c) && !(c == '.' && !text[e + 1..].starts_with(|d: char| d.is_ascii_alphanumeric())));
        out.push_str(&text[i..s]);
        out.push_str(if before || after { from } else { to });
        i = e;
    }
    out.push_str(&text[i..]);
    out
}

/// Map one path through the moves: an exact file rename, else the deepest
/// moved directory that contains it.
pub fn moved(path: &str, moves: &BTreeMap<String, String>) -> Option<String> {
    if let Some(n) = moves.get(path) {
        return Some(n.clone());
    }
    moves
        .iter()
        .filter(|(old, _)| path.starts_with(&format!("{old}/")))
        .max_by_key(|(old, _)| old.len())
        .map(|(old, new)| format!("{new}{}", &path[old.len()..]))
}

/// The body with moved paths and the PR's own Releases updated. Base
/// Releases change only as the left side of `old -> new` where the right side
/// is one of the PR's Releases; elsewhere an older Release is history (the
/// version a defect was observed on) and stays.
pub fn rewrite(body: &str, f: &Facts) -> String {
    let mut out = String::with_capacity(body.len());
    let mut last = 0;
    for (s, e) in spec_paths(body) {
        out.push_str(&body[last..s]);
        let tok = &body[s..e];
        match moved(tok, &f.paths) {
            Some(n) if !f.tree.contains(tok) => out.push_str(&n),
            _ => out.push_str(tok),
        }
        last = e;
    }
    out.push_str(&body[last..]);

    // Every replacement goes through a mark first, so that nothing replaced
    // is matched again: a chain a->b, b->c must not turn a into c, and a new
    // base Release may equal an old head Release.
    let mut resolved: Vec<(String, String)> = Vec::new();
    let mut mark = |to: &str| {
        let m = format!("\u{0}SHK{}\u{0}", resolved.len());
        resolved.push((m.clone(), to.to_string()));
        m
    };
    // arrows first, while the right side still holds the old Release
    for (old_base, new_base) in &f.base_releases {
        if old_base == new_base {
            continue;
        }
        for old_head in f.releases.keys() {
            for arrow in [" -> ", " → "] {
                for bold in ["", "**"] {
                    let from = format!("{old_base}{arrow}{bold}{old_head}{bold}");
                    if out.contains(&from) {
                        let to = format!("{}{arrow}{bold}{old_head}{bold}", mark(new_base));
                        out = out.replace(&from, &to);
                    }
                }
            }
        }
    }
    for (from, to) in f.releases.iter().filter(|(a, b)| a != b) {
        let m = mark(to);
        out = replace_token(&out, from, &m, release_char);
    }
    for (m, to) in resolved.iter().rev() {
        out = out.replace(m.as_str(), to);
    }
    out
}

fn headings(body: &str) -> Vec<String> {
    body.lines().filter_map(|l| l.strip_prefix("## ")).map(|h| h.trim().to_string()).collect()
}

/// Every problem the body has for the head the facts describe. Empty: fit to publish.
pub fn lint(body: &str, f: &Facts) -> Vec<String> {
    let mut p = Vec::new();
    // Problem, Change and Testing in that order; a section of its own between
    // them (a trade-off, why a backport) is the author's to add
    let h = headings(body);
    let want: Vec<&str> = if f.parent.is_some() { vec!["Problem", "Change", "Testing", "Dependencies"] } else { vec!["Problem", "Change", "Testing"] };
    let seen: Vec<&str> = h.iter().map(String::as_str).filter(|x| want.contains(x) || *x == "Dependencies").collect();
    let ordered = seen.iter().filter(|x| **x != "Dependencies").copied().collect::<Vec<_>>() == ["Problem", "Change", "Testing"];
    if !ordered || (f.parent.is_some() && !seen.contains(&"Dependencies")) {
        p.push(format!("sections are [{}], expected [{}]", h.join(", "), want.join(", ")));
    }
    if let Some(parent) = f.parent {
        let dep = body.split("\n## Dependencies").nth(1).unwrap_or("");
        let named = dep.split("## ").next().unwrap_or("");
        let first_ref = named.find('#').map(|i| named[i + 1..].chars().take_while(char::is_ascii_digit).collect::<String>());
        if first_ref.as_deref() != Some(parent.to_string().as_str()) {
            p.push(format!("Dependencies does not name #{parent} first, the PR this one is stacked on"));
        }
    }
    if body.trim_end().lines().last().map(str::trim) != Some(FOOTER) {
        p.push("the body does not end with the Generated-with line".into());
    }
    let lower = body.to_lowercase();
    for (needle, what) in [
        ("claude.ai/code/session", "a session link"),
        ("claude-session:", "a session trailer"),
        ("refs/heads/sync/", "a sync candidate ref"),
        ("/results/", "a results path"),
        ("memory.db", "the harness database"),
    ] {
        if lower.contains(needle) {
            p.push(format!("the body contains {what} ({needle})"));
        }
    }
    let words: Vec<&str> = lower.split(|c: char| !c.is_ascii_alphanumeric()).filter(|w| !w.is_empty()).collect();
    for w in words.windows(2) {
        if w[0] == "gate" && w[1].chars().all(|c| c.is_ascii_digit()) {
            p.push(format!("the body names an internal gate number (gate {})", w[1]));
        }
    }
    let mut stale = BTreeSet::new();
    for (s, e) in spec_paths(body) {
        let tok = &body[s..e];
        if !f.tree.contains(tok) && f.old_tree.contains(tok) {
            stale.insert(tok.to_string());
        }
    }
    for t in stale {
        p.push(format!("`{t}` is gone from the head and its base since the sync"));
    }
    for (old, new) in &f.releases {
        if old != new && replace_token(body, old, "\u{0}", release_char).contains('\u{0}') {
            p.push(format!("Release {old} is named, but the PR now introduces {new}"));
        }
    }
    p
}

/// `Version:`/`Release:` pairs of a spec in file order, as `V-R`. A value made
/// of macros is not a Release a reader can name and is left out.
pub fn version_releases(spec: &str) -> Vec<String> {
    let field = |l: &str, k: &str| -> Option<String> {
        let v = l.strip_prefix(k)?.trim();
        let lit: String = v.chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '.' || *c == '_' || *c == '+').collect();
        Some(lit)
    };
    let mut vs = Vec::new();
    let mut rs = Vec::new();
    for l in spec.lines() {
        if let Some(v) = field(l, "Version:") {
            vs.push(v);
        } else if let Some(r) = field(l, "Release:") {
            rs.push(r.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect::<String>());
        }
    }
    if vs.len() != rs.len() {
        return Vec::new();
    }
    vs.into_iter().zip(rs).filter(|(v, r)| !v.is_empty() && !r.is_empty()).map(|(v, r)| format!("{v}-{r}")).collect()
}

/// Pair the Releases of a spec at two revisions; positions that differ in
/// count give nothing, so nothing is rewritten on a guess.
pub fn pair_releases(old: &str, new: &str, into: &mut BTreeMap<String, String>, ambiguous: &mut BTreeSet<String>) {
    let (a, b) = (version_releases(old), version_releases(new));
    if a.len() != b.len() {
        return;
    }
    for (x, y) in a.into_iter().zip(b) {
        match into.get(&x) {
            Some(prev) if prev != &y => {
                ambiguous.insert(x);
            }
            _ => {
                into.insert(x, y);
            }
        }
    }
}

fn git(repo: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").arg("-C").arg(repo).args(args).output().map_err(|e| format!("git: {e}"))?;
    if !o.status.success() {
        return Err(format!("git {} failed: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).to_string())
}

fn show(repo: &Path, rev: &str, path: &str) -> String {
    git(repo, &["show", &format!("{rev}:{path}")]).unwrap_or_default()
}

/// The facts of one PR moved from `old_head` on `old_base` to `new_head` on
/// `new_base`. For a stacked PR the bases are its root's: a Release the stack
/// introduced is the PR's to name, whichever member wrote the entry.
pub fn gather(repo: &Path, old_base: &str, new_base: &str, old_head: &str, new_head: &str, parent: Option<u64>) -> Result<Facts, String> {
    let renames = crate::sync::base_renames(repo, old_base, new_base)?;
    let mut f = Facts { parent, ..Facts::default() };
    f.paths.extend(crate::sync::dir_moves(&renames));
    f.paths.extend(renames);
    f.tree.insert("SPECS".into());
    for rev in [new_head, new_base] {
        f.tree.extend(git(repo, &["ls-tree", "-r", "-t", "--name-only", rev])?.lines().map(str::to_string));
    }
    for rev in [old_head, old_base] {
        f.old_tree.extend(git(repo, &["ls-tree", "-r", "-t", "--name-only", rev])?.lines().map(str::to_string));
    }
    let back: BTreeMap<String, String> = f.paths.iter().map(|(o, n)| (n.clone(), o.clone())).collect();
    let mut amb = BTreeSet::new();
    let mut base_amb = BTreeSet::new();
    for p in git(repo, &["diff", "--name-only", new_base, new_head, "--", "*.spec"])?.lines() {
        let old = moved(p, &back).unwrap_or_else(|| p.to_string());
        let (ob, nb) = (show(repo, old_base, &old), show(repo, new_base, p));
        let (oh, nh) = (show(repo, old_head, &old), show(repo, new_head, p));
        let at_base: BTreeSet<String> = version_releases(&ob).into_iter().collect();
        let mut own = BTreeMap::new();
        pair_releases(&oh, &nh, &mut own, &mut amb);
        for (a, b) in own {
            if !at_base.contains(&a) {
                if f.releases.get(&a).map_or(false, |prev| prev != &b) {
                    amb.insert(a.clone());
                }
                f.releases.insert(a, b);
            }
        }
        pair_releases(&ob, &nb, &mut f.base_releases, &mut base_amb);
    }
    for a in amb {
        f.releases.remove(&a);
    }
    for a in base_amb {
        f.base_releases.remove(&a);
    }
    Ok(f)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts() -> Facts {
        let mut f = Facts::default();
        f.paths.insert("SPECS/linux".into(), "SPECS/92/linux".into());
        f.releases.insert("6.12.113-2".into(), "6.12.113-3".into());
        f.base_releases.insert("6.12.113-1".into(), "6.12.113-2".into());
        for t in ["SPECS", "SPECS/92", "SPECS/92/linux", "SPECS/92/linux/linux.spec", "SPECS/92/linux/linux-esx.spec", "SPECS/91/linux"] {
            f.tree.insert(t.into());
        }
        for t in ["SPECS", "SPECS/linux", "SPECS/linux/linux.spec", "SPECS/linux/linux-esx.spec", "SPECS/91/linux"] {
            f.old_tree.insert(t.into());
        }
        f
    }

    #[test]
    fn moved_paths_and_the_prs_releases_are_rewritten() {
        let body = "In `SPECS/linux/linux-esx.spec` and SPECS/linux. Release: `SPECS/linux` 6.12.113-1 -> **6.12.113-2**, see 6.12.113-21.";
        let out = rewrite(body, &facts());
        assert_eq!(
            out,
            "In `SPECS/92/linux/linux-esx.spec` and SPECS/92/linux. Release: `SPECS/92/linux` 6.12.113-2 -> **6.12.113-3**, see 6.12.113-21."
        );
    }

    #[test]
    fn base_releases_outside_an_arrow_are_history_and_stay() {
        let body = "`rpm -V linux-esx` fails on linux-esx 6.12.113-1.";
        assert_eq!(rewrite(body, &facts()), body);
    }

    #[test]
    fn a_release_chain_is_not_applied_twice() {
        let mut f = Facts::default();
        f.releases.insert("1.0-2".into(), "1.0-3".into());
        f.releases.insert("1.0-3".into(), "1.0-4".into());
        assert_eq!(rewrite("1.0-2 and 1.0-3", &f), "1.0-3 and 1.0-4");
    }

    #[test]
    fn existing_paths_and_globs_are_left_alone() {
        let mut f = facts();
        f.tree.insert("SPECS/linux".into());
        assert_eq!(rewrite("`SPECS/linux` and SPECS/*/linux", &f), "`SPECS/linux` and SPECS/*/linux");
    }

    fn good(stacked: bool) -> String {
        let dep = if stacked { "## Dependencies\nStacked on #36 (and through it #29 and #24).\n\n" } else { "" };
        format!("## Problem\nx in `SPECS/92/linux/linux.spec`.\n\n## Change\n6.12.113-3.\n\n## Testing\nok.\n\n{dep}{FOOTER}\n")
    }

    #[test]
    fn a_clean_body_passes() {
        assert!(lint(&good(false), &facts()).is_empty(), "{:?}", lint(&good(false), &facts()));
        let mut f = facts();
        f.parent = Some(36);
        assert!(lint(&good(true), &f).is_empty(), "{:?}", lint(&good(true), &f));
    }

    #[test]
    fn the_lint_names_every_problem() {
        let mut f = facts();
        f.parent = Some(29);
        let body = good(true).replace("6.12.113-3", "6.12.113-2 in gate 70").replace("SPECS/92/linux/linux.spec", "SPECS/linux/linux.spec")
            + "https://claude.ai/code/session_x\n";
        let p = lint(&body, &f);
        let all = p.join("\n");
        assert!(all.contains("Dependencies does not name #29"), "{all}");
        assert!(all.contains("does not end with the Generated-with line"), "{all}");
        assert!(all.contains("session link"), "{all}");
        assert!(all.contains("internal gate number"), "{all}");
        assert!(all.contains("`SPECS/linux/linux.spec` is gone"), "{all}");
        assert!(all.contains("Release 6.12.113-2 is named"), "{all}");
        assert_eq!(p.len(), 6, "{all}");
    }

    #[test]
    fn missing_sections_are_refused_and_own_sections_allowed() {
        let body = format!("## Problem\nx\n\n## Testing\ny\n\n{FOOTER}\n");
        assert!(lint(&body, &facts())[0].contains("expected [Problem, Change, Testing]"));
        let mut f = facts();
        f.parent = Some(36);
        assert!(lint(&good(false), &f).iter().any(|l| l.contains("Dependencies")));
        let own = format!("## Problem\nx\n\n## Change\ny\n\n## Trade-off\nz\n\n## Testing\nt\n\n## Dependencies\n#21 helps.\n\n{FOOTER}\n");
        assert!(lint(&own, &facts()).is_empty(), "{:?}", lint(&own, &facts()));
    }

    #[test]
    fn paths_of_other_trees_are_not_judged() {
        let body = format!("## Problem\n`SPECS/openssh` on 6.0, see SPECS/90/systemd/.\n\n## Change\nx\n\n## Testing\nt\n\n{FOOTER}\n");
        assert!(lint(&body, &facts()).is_empty(), "{:?}", lint(&body, &facts()));
        assert_eq!(spec_paths("in SPECS/90/systemd/."), vec![(3, 19)]);
    }

    #[test]
    fn releases_pair_by_position_and_skip_macros() {
        let old = "Version: 6.12.113\nRelease: 2%{?kat_build:.kat}%{?dist}\n";
        let new = "Version: 6.12.113\nRelease: 3%{?kat_build:.kat}%{?dist}\n";
        let mut m = BTreeMap::new();
        let mut amb = BTreeSet::new();
        pair_releases(old, new, &mut m, &mut amb);
        assert_eq!(m.get("6.12.113-2").map(String::as_str), Some("6.12.113-3"));
        assert_eq!(version_releases("Version: %{kver}\nRelease: 1\n"), Vec::<String>::new());
        assert_eq!(version_releases("Version: 253.19\nRelease: 17.2.3%{?dist}\n"), vec!["253.19-17.2.3"]);
        pair_releases("Version: 1\nRelease: 1\n", "Version: 1\nRelease: 2\nVersion: 2\nRelease: 1\n", &mut m, &mut amb);
        assert!(!m.contains_key("1-1"));
    }

    #[test]
    fn moves_map_files_and_directories() {
        let mut m = BTreeMap::new();
        m.insert("SPECS/linux".to_string(), "SPECS/92/linux".to_string());
        m.insert("SPECS/linux/odd.patch".to_string(), "SPECS/x/odd.patch".to_string());
        assert_eq!(moved("SPECS/linux/linux.spec", &m).as_deref(), Some("SPECS/92/linux/linux.spec"));
        assert_eq!(moved("SPECS/linux/odd.patch", &m).as_deref(), Some("SPECS/x/odd.patch"));
        assert_eq!(moved("SPECS/linuxptp/x.spec", &m), None);
    }
}
