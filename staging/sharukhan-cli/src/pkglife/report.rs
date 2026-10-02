//! What failed, per ISO: the package-lifecycle failures of one or more runs
//! as a Markdown report someone can act on.
//!
//! pkg-compare answers "did the change make anything worse"; this answers
//! "what is broken on the media at all". Each run is read the way every
//! other reader reads it - the last record of a package is its verdict - and
//! every failing part is reported from the record's own structure (failed
//! steps, units and CLIs with their detail), never re-derived from the
//! one-line reason.

use super::record::{PkgRecord, FAIL, NOT_REACHED, PASS, SKIP};
use std::collections::{BTreeMap, BTreeSet};

/// Detail kept per failing part; the full text stays in the run's file.
const DETAIL: usize = 240;

/// One failing part of a package: what kind of check, which object, why.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Part {
    pub kind: String,
    pub what: String,
    pub detail: String,
}

#[derive(Debug, Clone)]
pub struct Failure {
    pub package: String,
    pub evr: String,
    pub parts: Vec<Part>,
    /// The guest was lost with this package; its parts after the loss say
    /// nothing about the package itself.
    pub guest_lost: bool,
}

#[derive(Debug, Default)]
pub struct RunSummary {
    pub total: usize,
    pub pass: usize,
    pub fail: usize,
    pub skip: usize,
    pub not_reached: usize,
    pub failures: Vec<Failure>,
    /// Every package the run carries, with its verdict.
    pub verdicts: BTreeMap<String, String>,
}

fn short(s: &str) -> String {
    let one: String = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if one.chars().count() <= DETAIL {
        one
    } else {
        format!("{}...", one.chars().take(DETAIL).collect::<String>())
    }
}

fn key(r: &PkgRecord) -> String {
    if r.arch.is_empty() {
        r.package.clone()
    } else {
        format!("{}.{}", r.package, r.arch)
    }
}

/// The failing parts of one record, steps first, then units, then CLIs.
pub fn parts(r: &PkgRecord) -> Vec<Part> {
    let mut v: Vec<Part> = r
        .steps
        .iter()
        .filter(|s| s.status == FAIL)
        .map(|s| Part { kind: s.name.clone(), what: String::new(), detail: short(&s.detail) })
        .collect();
    v.extend(r.units.iter().filter(|u| u.status == FAIL).map(|u| Part {
        kind: "unit".into(),
        what: u.unit.clone(),
        detail: short(&u.outcome),
    }));
    v.extend(r.clis.iter().filter(|c| c.status == FAIL).map(|c| Part {
        kind: "cli".into(),
        what: c.path.clone(),
        detail: short(&c.reason),
    }));
    v
}

pub fn summarize(recs: &[PkgRecord]) -> RunSummary {
    let mut last: BTreeMap<String, &PkgRecord> = BTreeMap::new();
    for r in recs {
        last.insert(key(r), r);
    }
    let mut s = RunSummary { total: last.len(), ..Default::default() };
    for r in last.values() {
        s.verdicts.insert(key(r), r.verdict.clone());
        match r.verdict.as_str() {
            PASS => s.pass += 1,
            SKIP => s.skip += 1,
            NOT_REACHED => s.not_reached += 1,
            FAIL => {
                s.fail += 1;
                s.failures.push(Failure {
                    package: key(r),
                    evr: r.evr.clone(),
                    parts: parts(r),
                    guest_lost: r.steps.iter().any(|st| st.name == "guest-state" && st.status == FAIL),
                });
            }
            _ => s.skip += 1,
        }
    }
    s
}

/// Packages failing per kind of check: a package counts once per kind.
pub fn by_kind(s: &RunSummary) -> BTreeMap<String, usize> {
    let mut m = BTreeMap::new();
    for f in &s.failures {
        let kinds: BTreeSet<&str> = f.parts.iter().map(|p| p.kind.as_str()).collect();
        for k in kinds {
            *m.entry(k.to_string()).or_insert(0) += 1;
        }
    }
    m
}

fn esc(s: &str) -> String {
    s.replace('|', "\\|").replace('`', "'")
}

/// The report for runs labelled by their ISO, in the order given.
pub fn markdown(runs: &[(String, String, RunSummary)]) -> String {
    let mut o = String::from("# Package lifecycle failures\n\n");
    o.push_str("The last record of a package is its verdict. A package marked *guest lost* was being tested when the guest stopped answering; its later parts say nothing about the package.\n\n");
    o.push_str("| ISO | packages | pass | fail | skip | not reached |\n|---|---:|---:|---:|---:|---:|\n");
    for (label, _, s) in runs {
        o.push_str(&format!(
            "| {} | {} | {} | {} | {} | {} |\n",
            esc(label), s.total, s.pass, s.fail, s.skip, s.not_reached
        ));
    }

    // across the ISOs: a package that fails on one ISO and passes on
    // another that carries it - a package an ISO does not carry says nothing
    if runs.len() > 1 {
        let mut failing: BTreeSet<&str> = BTreeSet::new();
        for (_, _, s) in runs {
            failing.extend(s.failures.iter().map(|f| f.package.as_str()));
        }
        let mut everywhere = 0;
        let mut split: Vec<(&str, Vec<&str>, Vec<&str>)> = Vec::new();
        for p in &failing {
            let (mut f, mut ok) = (Vec::new(), Vec::new());
            for (label, _, s) in runs {
                match s.verdicts.get(*p).map(String::as_str) {
                    Some(FAIL) => f.push(label.as_str()),
                    Some(PASS) | Some(SKIP) => ok.push(label.as_str()),
                    _ => {}
                }
            }
            if ok.is_empty() {
                everywhere += 1;
            } else {
                split.push((p, f, ok));
            }
        }
        o.push_str(&format!(
            "\n## Across the ISOs\n\n{} package(s) fail on at least one ISO: {} on every ISO that carries them, {} fail on one ISO but pass or skip on another:\n\n",
            failing.len(),
            everywhere,
            split.len()
        ));
        if !split.is_empty() {
            o.push_str("| package | fails on | passes or skips on |\n|---|---|---|\n");
            for (p, f, ok) in split {
                o.push_str(&format!("| {} | {} | {} |\n", esc(p), esc(&f.join(", ")), esc(&ok.join(", "))));
            }
        }
    }

    for (label, file, s) in runs {
        o.push_str(&format!("\n## {}\n\n`{}`\n\n", esc(label), file));
        if s.failures.is_empty() {
            o.push_str("No failing package.\n");
            continue;
        }
        o.push_str("| failing check | packages |\n|---|---:|\n");
        let mut kinds: Vec<(String, usize)> = by_kind(s).into_iter().collect();
        kinds.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        for (k, n) in kinds {
            o.push_str(&format!("| {} | {} |\n", esc(&k), n));
        }
        let lost: Vec<&Failure> = s.failures.iter().filter(|f| f.guest_lost).collect();
        if !lost.is_empty() {
            o.push_str(&format!(
                "\nGuest lost while testing: {}\n",
                lost.iter().map(|f| f.package.as_str()).collect::<Vec<_>>().join(", ")
            ));
        }
        o.push_str("\n### Packages\n\n");
        for f in &s.failures {
            o.push_str(&format!(
                "- **{}** {}{}\n",
                esc(&f.package),
                esc(&f.evr),
                if f.guest_lost { " - *guest lost*" } else { "" }
            ));
            for p in &f.parts {
                let what = if p.what.is_empty() { String::new() } else { format!(" `{}`", esc(&p.what)) };
                o.push_str(&format!("  - {}{}: {}\n", esc(&p.kind), what, esc(&p.detail)));
            }
        }
    }
    o
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pkglife::record::{CliResult, Step, UnitResult};

    fn rec(p: &str, v: &str) -> PkgRecord {
        PkgRecord { package: p.into(), arch: "x86_64".into(), evr: "1-1.ph5".into(), verdict: v.into(), ..Default::default() }
    }

    #[test]
    fn the_last_record_of_a_package_is_its_verdict() {
        let s = summarize(&[rec("a", FAIL), rec("a", PASS), rec("b", NOT_REACHED), rec("b", FAIL), rec("c", SKIP)]);
        assert_eq!((s.total, s.pass, s.fail, s.skip, s.not_reached), (3, 1, 1, 1, 0));
        assert_eq!(s.failures[0].package, "b.x86_64");
    }

    #[test]
    fn parts_come_from_the_record_structure_not_the_reason() {
        let mut r = rec("x", FAIL);
        r.reason = "misleading text".into();
        r.steps.push(Step::new("ldcache", FAIL, "libx.so.1 not in the linker cache", 0));
        r.steps.push(Step::new("install", PASS, "ok", 0));
        r.units.push(UnitResult { unit: "x.service".into(), status: FAIL.into(), outcome: "exited 1".into(), ..Default::default() });
        r.clis.push(CliResult { path: "/usr/bin/x".into(), status: FAIL.into(), reason: "no version probe succeeded".into(), ..Default::default() });
        let p = parts(&r);
        let kinds: Vec<&str> = p.iter().map(|x| x.kind.as_str()).collect();
        assert_eq!(kinds, ["ldcache", "unit", "cli"]);
        assert_eq!(p[1].what, "x.service");
        let s = summarize(&[r]);
        let k = by_kind(&s);
        assert_eq!(k.get("cli"), Some(&1));
        assert!(!k.contains_key("install"));
    }

    #[test]
    fn a_lost_guest_is_marked_and_a_package_counts_once_per_kind() {
        let mut r = rec("y", FAIL);
        r.clis.push(CliResult { path: "/a".into(), status: FAIL.into(), ..Default::default() });
        r.clis.push(CliResult { path: "/b".into(), status: FAIL.into(), ..Default::default() });
        r.steps.push(Step::new("guest-state", FAIL, "ssh lost", 0));
        let s = summarize(&[r]);
        assert!(s.failures[0].guest_lost);
        assert_eq!(by_kind(&s).get("cli"), Some(&1));
    }

    #[test]
    fn the_report_names_packages_failing_on_only_some_isos() {
        let a = summarize(&[rec("p", FAIL), rec("q", FAIL)]);
        let b = summarize(&[rec("p", FAIL), rec("q", PASS)]);
        let md = markdown(&[("k01".into(), "a.jsonl".into(), a), ("k05".into(), "b.jsonl".into(), b)]);
        assert!(md.contains("1 on every ISO that carries them, 1 fail on one ISO but pass"), "{md}");
        assert!(md.contains("| q.x86_64 | k01 | k05 |"), "{md}");
    }

    #[test]
    fn a_package_an_iso_does_not_carry_is_not_a_split() {
        let a = summarize(&[rec("p", FAIL)]);
        let b = summarize(&[rec("other", PASS)]);
        let md = markdown(&[("full".into(), "a".into(), a), ("minimal".into(), "b".into(), b)]);
        assert!(md.contains("1 on every ISO that carries them, 0 fail on one ISO"), "{md}");
    }

    #[test]
    fn long_details_are_clipped_and_pipes_escaped() {
        let mut r = rec("z", FAIL);
        r.steps.push(Step::new("files", FAIL, "a|b ".repeat(200), 0));
        let md = markdown(&[("iso".into(), "f".into(), summarize(&[r]))]);
        assert!(md.contains("a\\|b"));
        assert!(md.contains("..."));
    }
}
