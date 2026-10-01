//! Two lifecycle runs of the same row, package by package: did the change
//! under test make any package worse?
//!
//! Zero failures is not a usable bar - lifecycle runs on untouched media
//! already carry failures that no PR caused - so a gate is judged against a
//! baseline run of the same row on the media without the change. What fails
//! the comparison:
//!
//! - regression   a package that passed (or was skipped) now fails
//! - new failure  a package only the new media carries, and it fails
//! - missing      a package the baseline tested is no longer on the media
//! - incomplete   a package was not reached on either side, so nothing can
//!                be said about it
//!
//! A failure present in both runs is "unchanged" and does not fail the
//! comparison; its reasons are shown when they differ. A failure that now
//! passes is an improvement.

use super::record::{PkgRecord, FAIL, PASS, SKIP};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Change {
    Regression,
    NewFailure,
    Missing,
    Incomplete,
    UnchangedFailure,
    Improvement,
    Added,
    Same,
}

impl Change {
    pub fn as_str(&self) -> &'static str {
        match self {
            Change::Regression => "regression",
            Change::NewFailure => "new-failure",
            Change::Missing => "missing",
            Change::Incomplete => "incomplete",
            Change::UnchangedFailure => "unchanged-failure",
            Change::Improvement => "improvement",
            Change::Added => "added",
            Change::Same => "same",
        }
    }

    /// Whether this change fails the comparison.
    pub fn blocks(&self) -> bool {
        matches!(
            self,
            Change::Regression | Change::NewFailure | Change::Missing | Change::Incomplete
        )
    }
}

#[derive(Debug, Clone)]
pub struct Row {
    pub package: String,
    pub base: Option<(String, String, String)>, // verdict, evr, reason
    pub new: Option<(String, String, String)>,
    pub change: Change,
}

fn key(r: &PkgRecord) -> String {
    if r.arch.is_empty() {
        r.package.clone()
    } else {
        format!("{}.{}", r.package, r.arch)
    }
}

/// The last record per package wins, as in the file a resumed run leaves.
fn index(recs: &[PkgRecord]) -> BTreeMap<String, &PkgRecord> {
    let mut m = BTreeMap::new();
    for r in recs {
        m.insert(key(r), r);
    }
    m
}

pub fn classify(base: Option<&str>, new: Option<&str>) -> Change {
    match (base, new) {
        (None, None) => Change::Same,
        (Some(_), None) => Change::Missing,
        (None, Some(n)) if n == FAIL => Change::NewFailure,
        (None, Some(n)) if n != PASS && n != SKIP => Change::Incomplete,
        (None, Some(_)) => Change::Added,
        (Some(b), Some(n)) => {
            let reached = |v: &str| v == PASS || v == FAIL || v == SKIP;
            if !reached(b) || !reached(n) {
                Change::Incomplete
            } else if n == FAIL && b == FAIL {
                Change::UnchangedFailure
            } else if n == FAIL {
                Change::Regression
            } else if b == FAIL {
                Change::Improvement
            } else {
                Change::Same
            }
        }
    }
}

pub fn compare(base: &[PkgRecord], new: &[PkgRecord]) -> Vec<Row> {
    let (b, n) = (index(base), index(new));
    let mut names: Vec<&String> = b.keys().chain(n.keys()).collect();
    names.sort();
    names.dedup();
    names
        .into_iter()
        .map(|k| {
            let bb = b.get(k).map(|r| (r.verdict.clone(), r.evr.clone(), r.reason.clone()));
            let nn = n.get(k).map(|r| (r.verdict.clone(), r.evr.clone(), r.reason.clone()));
            let change = classify(bb.as_ref().map(|x| x.0.as_str()), nn.as_ref().map(|x| x.0.as_str()));
            Row { package: k.clone(), base: bb, new: nn, change }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(p: &str, v: &str) -> PkgRecord {
        PkgRecord { package: p.into(), arch: "x86_64".into(), verdict: v.into(), ..Default::default() }
    }

    #[test]
    fn every_transition_is_classified() {
        assert_eq!(classify(Some(PASS), Some(FAIL)), Change::Regression);
        assert_eq!(classify(Some(SKIP), Some(FAIL)), Change::Regression);
        assert_eq!(classify(Some(FAIL), Some(FAIL)), Change::UnchangedFailure);
        assert_eq!(classify(Some(FAIL), Some(PASS)), Change::Improvement);
        assert_eq!(classify(Some(PASS), Some(PASS)), Change::Same);
        assert_eq!(classify(Some(PASS), Some(SKIP)), Change::Same);
        assert_eq!(classify(Some(PASS), None), Change::Missing);
        assert_eq!(classify(None, Some(FAIL)), Change::NewFailure);
        assert_eq!(classify(None, Some(PASS)), Change::Added);
        assert_eq!(classify(Some(PASS), Some("not-reached")), Change::Incomplete);
        assert_eq!(classify(Some("not-reached"), Some(PASS)), Change::Incomplete);
    }

    #[test]
    fn only_regressions_new_failures_missing_and_incomplete_block() {
        for c in [Change::Regression, Change::NewFailure, Change::Missing, Change::Incomplete] {
            assert!(c.blocks(), "{c:?}");
        }
        for c in [Change::UnchangedFailure, Change::Improvement, Change::Added, Change::Same] {
            assert!(!c.blocks(), "{c:?}");
        }
    }

    #[test]
    fn packages_are_matched_by_name_and_arch_and_the_last_record_wins() {
        let base = vec![rec("a", PASS), rec("b", FAIL), rec("c", PASS)];
        let new = vec![rec("a", FAIL), rec("a", PASS), rec("b", FAIL), rec("d", FAIL)];
        let rows = compare(&base, &new);
        let get = |p: &str| rows.iter().find(|r| r.package == format!("{p}.x86_64")).unwrap().change.clone();
        assert_eq!(get("a"), Change::Same, "the later record of a replaced the earlier one");
        assert_eq!(get("b"), Change::UnchangedFailure);
        assert_eq!(get("c"), Change::Missing);
        assert_eq!(get("d"), Change::NewFailure);
    }
}
