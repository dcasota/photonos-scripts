//! Guards for rebasing a PR branch onto a base that has moved.
//!
//! Both checks here exist because both failure modes were shipped, survived
//! review, and were only caught afterwards - each time because the check that
//! should have caught it was measuring the wrong thing rather than returning a
//! wrong answer.
//!
//! 1. A CHANGELOG ENTRY THAT DUPLICATES ONE THE TARGET ALREADY HAS.
//!    A branch numbered against yesterday's base claims a version the target
//!    branch has since published itself. The earlier verifier compared the
//!    branch to `merge-base(target, branch)` - which is the OLD base, where the
//!    version really was unused - so a duplicate looked unique and passed. The
//!    baseline has to be the target's CURRENT content, so `changelog_version_is_new`
//!    takes the target text itself and there is no merge-base to get wrong.
//!
//! 2. A RENAME WHOSE SOURCE PATH IS NEVER REMOVED.
//!    `git show --name-only` collapses a rename to the DESTINATION path alone,
//!    so a replay that iterates that list writes the new path and never learns
//!    the old one went away. A single-source kernel commit moves 400+ files;
//!    the replay kept 136 of them. The resulting tree still builds, still passes
//!    the spec checker, and still looks clean in a rename-aware diff - it is
//!    wrong only against the branch it claims to reproduce.
//!
//! Neither guard trusts a boolean. Both report the measured values - which
//! version, which paths - because "duplicate" and "136 paths missed" need
//! different fixes and are indistinguishable in a pass/fail.

use std::path::Path;
use std::process::Command;

/// Run git as an argument vector, never a shell string.
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

/// One `%changelog` entry header, as far as these guards care.
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Entry {
    /// The trailing version-release, e.g. `6.12.109-7`.
    pub version: String,
    /// `YYYYMMDD`, or `None` when the header does not parse as a date.
    pub date: Option<u32>,
}

fn month(m: &str) -> Option<u32> {
    Some(match m {
        "Jan" => 1,
        "Feb" => 2,
        "Mar" => 3,
        "Apr" => 4,
        "May" => 5,
        "Jun" => 6,
        "Jul" => 7,
        "Aug" => 8,
        "Sep" => 9,
        "Oct" => 10,
        "Nov" => 11,
        "Dec" => 12,
        _ => return None,
    })
}

/// Parse the `* Day Mon DD YYYY Name <mail> version` headers of a changelog.
///
/// A header that does not parse as a date yields `date: None` rather than a
/// fabricated key. An earlier shell implementation built the key with
/// `printf '%02d' || echo 00`, which on a rejected value emits BOTH outputs and
/// concatenates them, inventing date inversions in files that were correctly
/// ordered - so every entry failed and the check became noise.
pub fn entries(text: &str) -> Vec<Entry> {
    let mut out = Vec::new();
    let body = match text.find("%changelog") {
        Some(i) => &text[i..],
        None => text,
    };
    for line in body.lines().filter(|l| l.starts_with("* ")) {
        let f: Vec<&str> = line.split_whitespace().collect();
        let Some(version) = f.last() else { continue };
        let date = match (f.get(2), f.get(3), f.get(4)) {
            (Some(m), Some(d), Some(y)) => match (month(m), d.parse::<u32>(), y.parse::<u32>()) {
                (Some(m), Ok(d), Ok(y)) if (1..=31).contains(&d) && (1970..=9999).contains(&y) => {
                    Some(y * 10_000 + m * 100 + d)
                }
                _ => None,
            },
            _ => None,
        };
        out.push(Entry {
            version: (*version).to_string(),
            date,
        });
    }
    out
}

/// What a changelog check found. Values, not a boolean.
#[derive(Debug, PartialEq, Eq)]
pub enum Changelog {
    /// The branch adds this version and the target does not have it.
    New { version: String },
    /// The target ALREADY publishes this version: the branch must renumber.
    Duplicate {
        version: String,
        target_date: Option<u32>,
    },
    /// The branch adds no entry at all (a stacked child extending its parent).
    NoneAdded,
}

/// The version a branch ADDS must not already exist on the target branch.
///
/// Three texts, because two are not enough and each fixes a different defect:
///
/// * `base` (the merge-base) decides WHAT THE BRANCH ADDED. Without it, "the
///   branch's top entry" is taken as its contribution - but on a file the
///   branch never touched and the target has since moved ahead on, that entry
///   is simply stale, and every such file was reported as a duplicate.
/// * `target` decides WHETHER THAT VERSION IS FREE. Comparing against the
///   merge-base instead is how a version the target had since published looked
///   unique and passed.
///
/// Using only one of them fails in one of those two directions, and both
/// failures have happened.
pub fn changelog_version_is_new(base: &str, target: &str, branch: &str) -> Changelog {
    let bse = entries(base);
    let tgt = entries(target);
    let br = entries(branch);
    let Some(top) = br
        .iter()
        .find(|e| !bse.iter().any(|x| x.version == e.version))
    else {
        return Changelog::NoneAdded;
    };
    match tgt.iter().find(|e| e.version == top.version) {
        Some(dup) => Changelog::Duplicate {
            version: top.version.clone(),
            target_date: dup.date,
        },
        None => Changelog::New {
            version: top.version.clone(),
        },
    }
}

/// The entries of a %changelog as blocks: the `* ` header line and the lines
/// under it, blank lines dropped.
pub fn entry_blocks(text: &str) -> Vec<Vec<String>> {
    let body = match text.find("%changelog") {
        Some(i) => &text[i..],
        None => text,
    };
    let mut out: Vec<Vec<String>> = Vec::new();
    // A `%` line (another file's %changelog in package_changelogs' joined
    // text) ends the entry before it.
    let mut open = false;
    for line in body.lines() {
        if line.starts_with("* ") {
            out.push(vec![line.trim_end().to_string()]);
            open = true;
        } else if line.starts_with('%') {
            open = false;
        } else if open && !line.trim().is_empty() {
            if let Some(cur) = out.last_mut() {
                cur.push(line.trim_end().to_string());
            }
        }
    }
    out
}

/// One %changelog entry per PR and spec, in one short line.
///
/// `reference` holds every changelog of the package at the merge-base (so an
/// entry that only moved between a spec and an include is not new), `before`
/// the same file at the merge-base, `branch` the file on the branch. The
/// branch may add exactly one entry, on top, by `author`, with exactly one
/// change line of at most `max_words` words. It may replace an entry only
/// when that entry is `author`'s own: a stacked PR amends its parent's entry
/// instead of appending one.
pub fn single_entry_problems(
    reference: &str,
    before: &str,
    branch: &str,
    author: &str,
    max_words: usize,
) -> Vec<String> {
    let known = entry_blocks(reference);
    let mut known_before = entry_blocks(before);
    known_before.extend(known.iter().cloned());
    let now = entry_blocks(branch);
    let added: Vec<&Vec<String>> = now.iter().filter(|e| !known_before.contains(e)).collect();
    let mut out = Vec::new();
    if added.len() > 1 {
        out.push(format!("adds {} %changelog entries; one per PR", added.len()));
    }
    for e in &added {
        if !e[0].contains(author) {
            out.push(format!("the added entry is not by {author}: {}", e[0]));
        }
        if e.len() != 2 {
            out.push(format!(
                "the added entry has {} change lines; it must have exactly one",
                e.len() - 1
            ));
        }
        for l in &e[1..] {
            let words = l.trim_start_matches(|c| c == '-' || c == ' ').split_whitespace().count();
            if words > max_words {
                out.push(format!("change line of {words} words (at most {max_words}): {}", l.trim()));
            }
        }
    }
    if let Some(first) = added.first() {
        if now.first() != Some(*first) {
            out.push("the added entry is not the top entry".into());
        }
    }
    for e in entry_blocks(before) {
        if !now.contains(&e) && !e[0].contains(author) {
            out.push(format!("changes or drops an existing entry: {}", e[0]));
        }
    }
    out
}

/// The top entry must not be older than the entry beneath it.
///
/// Only the top pair is compared. The historical tail belongs to upstream and
/// contains genuine inversions from years back; failing a branch for those
/// blames it for defects it did not introduce and cannot fix.
/// Entries of the base's changelog that the head's package no longer has in
/// any of its changelogs. A spec whose changelog moved into included files
/// keeps every entry there; only an entry of the author's own may change.
pub fn dropped_entries(before: &str, head_package: &str, author: &str) -> Vec<String> {
    let now = entry_blocks(head_package);
    entry_blocks(before)
        .into_iter()
        .filter(|e| !e[0].contains(author) && !now.contains(e))
        .map(|e| format!("changes or drops an existing entry: {}", e[0]))
        .collect()
}

pub fn top_entry_is_not_older(text: &str) -> Result<(), String> {
    let e = entries(text);
    match (e.first(), e.get(1)) {
        (Some(a), Some(b)) => match (a.date, b.date) {
            (Some(x), Some(y)) if x < y => Err(format!(
                "the top entry {} is dated {x}, older than {} beneath it at {y}; \
                 rpm requires descending dates",
                a.version, b.version
            )),
            _ => Ok(()),
        },
        _ => Ok(()),
    }
}

/// Every path a commit touches, INCLUDING the source side of a rename.
///
/// `--no-renames` is required, not a preference: without it git reports a
/// rename as a single destination path and a replay that follows that list
/// never removes the source, silently keeping files the commit deleted.
pub fn touched_paths(dir: &Path, rev: &str) -> Result<Vec<String>, String> {
    let out = git(
        dir,
        &["show", "--name-only", "--no-renames", "--format=", rev],
    )?;
    Ok(out
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect())
}

/// The paths a rename-collapsing enumeration would have missed.
///
/// Reported rather than merely counted: an operator who sees "136 missed" still
/// has to know WHICH files were left behind to judge the damage.
pub fn renames_would_be_missed(dir: &Path, rev: &str) -> Result<Vec<String>, String> {
    let naive = git(dir, &["show", "--name-only", "--format=", rev])?;
    let naive: Vec<&str> = naive
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();
    let full = touched_paths(dir, rev)?;
    Ok(full
        .into_iter()
        .filter(|p| !naive.contains(&p.as_str()))
        .collect())
}

/// A replayed tree must carry the same executable bits as the original.
///
/// Writing files with a plain create gives 0644 and silently drops `+x` from
/// the build scripts the chain carries. No content diff reveals it.
pub fn executable_paths(dir: &Path, rev: &str) -> Result<Vec<String>, String> {
    let out = git(dir, &["ls-tree", "-r", rev])?;
    let mut v: Vec<String> = out
        .lines()
        .filter(|l| l.starts_with("100755"))
        .filter_map(|l| l.split('\t').nth(1).map(str::to_string))
        .collect();
    v.sort();
    Ok(v)
}

/// The spec and include files a branch changes, relative to `from`.
///
/// `from` must be the MERGE-BASE, not the target: `git diff target branch`
/// lists files differing in either direction, so a spec the branch never
/// touched and the target has moved ahead on would be inspected as though the
/// branch had changed it.
///
/// Both `.spec` and `.inc`: a single-source spec moves its %changelog into an
/// include, and a verifier that globbed only `*.spec` inspected ZERO files for
/// such a branch and reported a vacuous pass.
pub fn changed_spec_files(dir: &Path, target: &str, branch: &str) -> Result<Vec<String>, String> {
    let out = git(
        dir,
        &[
            "diff",
            "--no-renames",
            "--name-only",
            target,
            branch,
            "--",
            "*.spec",
            "*.inc",
        ],
    )?;
    Ok(out
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect())
}

/// The base's, target's and branch's text for one path.
///
/// A ref that lacks the file yields an empty string rather than skipping the
/// path: a file the branch ADDS has no target text, and treating that as
/// "cannot check" would silently exempt exactly the new files.
pub fn three_texts(
    dir: &Path,
    base: &str,
    target: &str,
    branch: &str,
    path: &str,
) -> (String, String, String) {
    let at = |r: &str| match git(dir, &["show", &format!("{r}:{path}")]) {
        Ok(t) => t,
        // The file does not exist there: a changelog that moved into a new
        // file (an include, or another subrelease's directory) still belongs
        // to the same package, so compare against all of its changelogs.
        Err(_) => package_changelogs(dir, r, path),
    };
    (at(base), at(target), at(branch))
}

/// Every changelog of the package `path` belongs to, at `rev`: the .spec and
/// *changelog*.inc files in any SPECS/<pkg>/ or SPECS/<subrelease>/<pkg>/
/// directory with the same package directory name (Photon's layout).
/// `path` at `rev`, or empty when it does not exist there.
pub fn file_at(dir: &Path, rev: &str, path: &str) -> String {
    git(dir, &["show", &format!("{rev}:{path}")]).unwrap_or_default()
}

pub fn package_changelogs(dir: &Path, rev: &str, path: &str) -> String {
    let Some(pkg) = Path::new(path).parent().and_then(|p| p.file_name()).and_then(|n| n.to_str()) else {
        return String::new();
    };
    let Ok(list) = git(dir, &["ls-tree", "-r", "--name-only", rev, "--", "SPECS"]) else {
        return String::new();
    };
    let mut out = String::new();
    for f in list.lines() {
        let p = Path::new(f);
        let in_pkg = p.parent().and_then(|d| d.file_name()).and_then(|n| n.to_str()) == Some(pkg);
        let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
        let depth = f.matches('/').count();
        if in_pkg && (2..=3).contains(&depth) && (name.ends_with(".spec") || (name.contains("changelog") && name.ends_with(".inc"))) {
            if let Ok(t) = git(dir, &["show", &format!("{rev}:{f}")]) {
                if let Some(i) = t.find("%changelog") {
                    out.push_str(&t[i..]);
                    out.push('\n');
                }
            }
        }
    }
    out
}

/// The merge-base of two refs.
pub fn merge_base(dir: &Path, a: &str, b: &str) -> Result<String, String> {
    Ok(git(dir, &["merge-base", a, b])?.trim().to_string())
}

/// The commits a branch adds on top of its target.
pub fn commits_between(dir: &Path, target: &str, branch: &str) -> Result<Vec<String>, String> {
    let out = git(
        dir,
        &["rev-list", "--reverse", &format!("{target}..{branch}")],
    )?;
    Ok(out
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The merge-base: what both sides had before either moved.
    const BASE: &str = "\
%changelog
* Thu Sep 17 2026 srinidhira0 <srinidhi.rao@broadcom.com> 6.12.109-5
- Fixes CVE-2026-43464
";

    const TARGET: &str = "\
%changelog
* Fri Sep 18 2026 Guruswamy Basavaiah <guruswamy.basavaiah@broadcom.com> 6.12.109-6
- Fixes CVE-2026-68337, CVE-2026-68441
* Thu Sep 17 2026 srinidhira0 <srinidhi.rao@broadcom.com> 6.12.109-5
- Fixes CVE-2026-43464
";

    /// THE INCIDENT. The branch was numbered 6.12.109-6 against a base where
    /// that version was free; the target then published its own -6. Measured
    /// against the old merge-base this looked unique and passed.
    #[test]
    fn a_version_the_target_already_publishes_is_a_duplicate_not_a_new_entry() {
        let branch = "\
%changelog
* Thu Sep 17 2026 Daniel Casota <dcasota@gmail.com> 6.12.109-6
- Share canister/.config handling via canister_config.inc
* Thu Sep 17 2026 srinidhira0 <srinidhi.rao@broadcom.com> 6.12.109-5
- Fixes CVE-2026-43464
";
        assert_eq!(
            changelog_version_is_new(BASE, TARGET, branch),
            Changelog::Duplicate {
                version: "6.12.109-6".to_string(),
                target_date: Some(20260918),
            }
        );
    }

    /// NEGATIVE CONTROL: the repaired branch must pass, or the guard is just a
    /// check that always fails - as useless as one that always passes.
    #[test]
    fn the_renumbered_entry_is_accepted() {
        let branch = "\
%changelog
* Sat Sep 19 2026 Daniel Casota <dcasota@gmail.com> 6.12.109-7
- Share canister/.config handling via canister_config.inc
* Fri Sep 18 2026 Guruswamy Basavaiah <guruswamy.basavaiah@broadcom.com> 6.12.109-6
- Fixes CVE-2026-68337, CVE-2026-68441
";
        assert_eq!(
            changelog_version_is_new(BASE, TARGET, branch),
            Changelog::New {
                version: "6.12.109-7".to_string()
            }
        );
        assert!(top_entry_is_not_older(branch).is_ok());
    }

    /// A stacked child extends its parent's entry instead of adding one, which
    /// is correct and must not be reported as a missing bump.
    #[test]
    fn a_branch_that_adds_no_entry_is_not_a_duplicate() {
        assert_eq!(
            changelog_version_is_new(BASE, TARGET, BASE),
            Changelog::NoneAdded
        );
        assert_eq!(
            changelog_version_is_new(BASE, TARGET, "%changelog\n"),
            Changelog::NoneAdded
        );
    }

    /// THE SECOND INCIDENT, found by running the guard on a real repository.
    /// The branch never touched this spec; the target moved ahead on it. With
    /// only two texts the branch's stale top entry read as a duplicate, and six
    /// untouched specs (apache-tomcat, bpftrace, libarchive, perl) were all
    /// reported as defects.
    #[test]
    fn a_file_the_branch_never_touched_is_not_its_duplicate() {
        // target has advanced to -6; the branch still carries the base's -5
        assert_eq!(
            changelog_version_is_new(BASE, TARGET, BASE),
            Changelog::NoneAdded
        );
    }

    /// Placing a new entry above one with a later date is what a rebase breaks,
    /// and rpm rejects it.
    #[test]
    fn an_entry_older_than_the_one_beneath_it_is_refused() {
        let inverted = "\
%changelog
* Thu Sep 17 2026 Daniel Casota <dcasota@gmail.com> 6.12.109-7
- late
* Fri Sep 18 2026 Guruswamy Basavaiah <g@broadcom.com> 6.12.109-6
- earlier in the file, later in time
";
        let e = match top_entry_is_not_older(inverted) {
            Err(e) => e,
            Ok(()) => panic!("an inverted pair must be refused"),
        };
        assert!(e.contains("6.12.109-7"), "{e}");
        assert!(
            e.contains("20260917"),
            "the error states the measured date: {e}"
        );
    }

    /// Only the top pair is judged: upstream's historical tail carries real
    /// inversions this branch neither introduced nor can fix.
    #[test]
    fn a_historical_inversion_further_down_is_not_this_branchs_defect() {
        let old_mess = "\
%changelog
* Sat Sep 19 2026 Daniel Casota <dcasota@gmail.com> 6.12.109-7
- fine
* Fri Sep 18 2026 Someone <s@example.com> 6.12.109-6
- fine
* Wed Feb 03 2016 Ancient <a@example.com> 4.2.0-2
- out of order below
* Thu Feb 11 2016 Ancient <a@example.com> 4.2.0-1
- and here
";
        assert!(top_entry_is_not_older(old_mess).is_ok());
    }

    /// A header with a malformed date yields None rather than a fabricated key.
    #[test]
    fn an_unparseable_header_date_is_none_not_a_made_up_number() {
        let e = entries("%changelog\n* Notaday Xxx ?? notayear Someone <s@e.com> 1.0-1\n- x\n");
        assert_eq!(e.len(), 1);
        assert_eq!(e[0].version, "1.0-1");
        assert_eq!(e[0].date, None);
        // and a pair where one side is unparseable is not called inverted
        assert!(top_entry_is_not_older(
            "%changelog\n* Bad date here Someone <s@e.com> 1.0-2\n- x\n\
             * Fri Sep 18 2026 Someone <s@e.com> 1.0-1\n- y\n"
        )
        .is_ok());
    }

    /// Dates are parsed without printf, so a zero-padded day cannot be read as
    /// an invalid octal number - the bug that made the shell version emit an
    /// error per entry.
    #[test]
    fn a_zero_padded_day_parses_as_decimal() {
        let e = entries("%changelog\n* Mon Sep 08 2026 Someone <s@e.com> 1.0-1\n- x\n");
        assert_eq!(e[0].date, Some(20260908));
    }
    /// A changelog moved into a file the target does not have (an include)
    /// still collides with the package's own versions on the target.
    #[test]
    fn a_changelog_moved_into_an_include_is_checked_against_the_package() {
        use std::process::Command;
        let d = std::env::temp_dir().join(format!("shk-bg-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("SPECS/linux")).unwrap();
        let g = |a: &[&str]| {
            let o = Command::new("git").arg("-C").arg(&d).args(a).output().unwrap();
            assert!(o.status.success(), "{:?}", String::from_utf8_lossy(&o.stderr));
        };
        g(&["init", "-q", "-b", "5.0"]);
        g(&["config", "user.email", "t@t"]);
        g(&["config", "user.name", "t"]);
        let spec = |top: &str| format!("Name: linux\n%changelog\n{top}* Wed Sep 23 2026 A <a@a> 6.12.111-1\n- base\n");
        std::fs::write(d.join("SPECS/linux/linux.spec"), spec("")).unwrap();
        g(&["add", "."]);
        g(&["commit", "-qm", "base"]);
        g(&["checkout", "-qb", "pr"]);
        std::fs::write(d.join("SPECS/linux/linux.spec"), "Name: linux\n%include %{SOURCE1}\n").unwrap();
        std::fs::write(
            d.join("SPECS/linux/linux-changelog.inc"),
            "%changelog\n* Thu Sep 24 2026 B <b@b> 6.12.111-2\n- pr\n* Wed Sep 23 2026 A <a@a> 6.12.111-1\n- base\n",
        )
        .unwrap();
        g(&["add", "."]);
        g(&["commit", "-qm", "pr"]);
        g(&["checkout", "-q", "5.0"]);
        std::fs::write(d.join("SPECS/linux/linux.spec"), spec("* Mon Sep 28 2026 C <c@c> 6.12.111-2\n- up\n")).unwrap();
        g(&["commit", "-qam", "upstream"]);
        let (b, t, br) = three_texts(&d, "5.0~1", "5.0", "pr", "SPECS/linux/linux-changelog.inc");
        match changelog_version_is_new(&b, &t, &br) {
            Changelog::Duplicate { version, .. } => assert_eq!(version, "6.12.111-2"),
            other => panic!("expected a duplicate, got {other:?}"),
        }
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn one_short_entry_passes_and_every_breach_is_named() {
        let a = "Daniel Casota <dcasota@gmail.com>";
        let base = "%changelog\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update\n";
        let ok = "%changelog\n* Wed Oct 21 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Fix the thing\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update\n";
        assert!(single_entry_problems(base, base, ok, a, 10).is_empty());
        let two = "%changelog\n* Thu Oct 22 2026 Daniel Casota <dcasota@gmail.com> 1.0-3\n- More\n* Wed Oct 21 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Fix\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update\n";
        assert!(single_entry_problems(base, base, two, a, 10).iter().any(|p| p.contains("adds 2")));
        let long = "%changelog\n* Wed Oct 21 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- one two three four five six seven eight nine ten eleven\n- second\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update\n";
        let p = single_entry_problems(base, base, long, a, 10);
        assert!(p.iter().any(|p| p.contains("2 change lines")), "{p:?}");
        assert!(p.iter().any(|p| p.contains("11 words")), "{p:?}");
        let altered = "%changelog\n* Wed Oct 21 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Fix\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update, reworded\n";
        assert!(single_entry_problems(base, base, altered, a, 10).iter().any(|p| p.contains("changes or drops")));
    }

    #[test]
    fn a_stacked_pr_may_amend_its_parents_entry_and_a_moved_entry_is_not_new() {
        let a = "Daniel Casota <dcasota@gmail.com>";
        let parent = "%changelog\n* Wed Oct 21 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Fix A\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update\n";
        let child = "%changelog\n* Wed Oct 21 2026 Daniel Casota <dcasota@gmail.com> 1.0-2\n- Fix A and B\n* Mon Oct 19 2026 X Y <x@y> 1.0-1\n- Update\n";
        assert!(single_entry_problems(parent, parent, child, a, 10).is_empty());
        // the whole history moved from the spec into an include
        assert!(single_entry_problems(parent, "", parent, a, 10).is_empty());
        // several files joined, as package_changelogs returns them: the last
        // entry of one does not swallow the next file's %changelog line
        let joined = format!("{parent}\n%changelog\n* Mon Oct 19 2026 X Y <x@y> 2.0-1\n- Other\n");
        assert!(single_entry_problems(&joined, "", parent, a, 10).is_empty());
        // a changelog moved into includes keeps the base's entries there
        let base_spec = "%changelog\n* Fri Oct 23 2026 V W <v@w> 1-5\n- Fix\n* Mon Oct 19 2026 V W <v@w> 1-4\n- Up\n";
        let incs = "%changelog\n* Sat Oct 24 2026 Daniel Casota <dcasota@gmail.com> 1-6\n- Mine\n* Fri Oct 23 2026 V W <v@w> 1-5\n- Fix\n* Mon Oct 19 2026 V W <v@w> 1-4\n- Up\n";
        assert!(dropped_entries(base_spec, incs, a).is_empty());
        let lost = incs.replace("- Fix\n", "- Fixed\n");
        assert_eq!(dropped_entries(base_spec, &lost, a).len(), 1);
    }
}
