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

/// The top entry must not be older than the entry beneath it.
///
/// Only the top pair is compared. The historical tail belongs to upstream and
/// contains genuine inversions from years back; failing a branch for those
/// blames it for defects it did not introduce and cannot fix.
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
    let at = |r: &str| git(dir, &["show", &format!("{r}:{path}")]).unwrap_or_default();
    (at(base), at(target), at(branch))
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
}
