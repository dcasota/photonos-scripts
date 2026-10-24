//! Structured results. Ported from lib/common.sh's mc_result_init / mc_check /
//! mc_expect / mc_result_summary.
//!
//! Every assertion lands in one JSONL file as one object per line, and names
//! the PR it proves - so a failure reads as "PR #22 regressed" rather than
//! "something broke". That naming is the whole purpose of the harness.
//!
//! Every run gets its own timestamped file. An earlier version truncated a
//! fixed checks.jsonl, so re-running a permutation destroyed the evidence of
//! the run before it - exactly when comparing two runs is what would explain a
//! regression. checks-latest.jsonl is a convenience pointer, never storage.
//!
//! The format is frozen by the 21 rows of evidence already under
//! /root/photon-mc/results/: field names, field order, and the flat all-string
//! values are what `report` and every stored file agree on.

use serde::Serialize;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Pass,
    Fail,
    Skip,
    Info,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Status::Pass => "pass",
            Status::Fail => "fail",
            Status::Skip => "skip",
            Status::Info => "info",
        }
    }
}

#[derive(Serialize)]
struct Record<'a> {
    perm: &'a str,
    check: &'a str,
    pr: &'a str,
    status: &'a str,
    expected: &'a str,
    actual: &'a str,
    detail: &'a str,
}

pub struct Checks {
    pub perm: String,
    pub path: PathBuf,
    file: File,
    pub pass: usize,
    pub fail: usize,
    pub skip: usize,
    pub info: usize,
    pub failed: Vec<String>,
    pub prs: Vec<String>,
    /// check id -> the PR it proves (config/check-prs.tsv). A check without an
    /// entry is attributed to no PR ("-").
    pub attribution: std::collections::BTreeMap<String, String>,
    /// Whether each record is also printed as it is written. A run driving many
    /// rows wants the lines; a caller collecting a summary does not.
    pub echo: bool,
}

/// The check -> PR attribution file: `check-id<TAB>PR#n` lines, `#` comment lines.
/// A malformed line, a label that is not PR#n/POI#n or a check listed twice is
/// an error: attribution is what a failed check reports as implicated.
pub fn load_attribution(path: &Path) -> Result<std::collections::BTreeMap<String, String>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e} (SHARUKHAN_CHECK_PRS)", path.display()))?;
    let mut out = std::collections::BTreeMap::new();
    for (i, l) in text.lines().enumerate() {
        // full-line comments only: the labels themselves carry '#'
        let l = l.trim();
        if l.is_empty() || l.starts_with('#') {
            continue;
        }
        let f: Vec<&str> = l.split_whitespace().collect();
        let ok_label = |x: &str| {
            ["PR#", "POI#"].iter().any(|p| x.strip_prefix(p).is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())))
        };
        if f.len() != 2 || !ok_label(f[1]) {
            return Err(format!("{}:{}: expected 'check-id PR#n|POI#n', got '{l}'", path.display(), i + 1));
        }
        if out.insert(f[0].to_string(), f[1].to_string()).is_some() {
            return Err(format!("{}:{}: {} attributed twice", path.display(), i + 1, f[0]));
        }
    }
    Ok(out)
}

impl Checks {
    /// results/<perm>/checks-<stamp>.jsonl, with checks-latest.jsonl pointed
    /// at it.
    pub fn init(results_dir: &Path, perm: &str, stamp: &str) -> Result<Checks, String> {
        let dir = results_dir.join(perm);
        fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let path = dir.join(format!("checks-{stamp}.jsonl"));
        let file = File::create(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        let link = dir.join("checks-latest.jsonl");
        let _ = fs::remove_file(&link);
        let _ = std::os::unix::fs::symlink(path.file_name().unwrap_or_default(), &link);
        Ok(Checks {
            perm: perm.to_string(),
            path,
            file,
            pass: 0,
            fail: 0,
            skip: 0,
            info: 0,
            failed: Vec::new(),
            prs: Vec::new(),
            attribution: std::collections::BTreeMap::new(),
            echo: true,
        })
    }

    /// One assertion. `actual` is always the MEASURED value, never a bare
    /// OK/FAIL: "tool missing" and "tool present but unreadable by this user"
    /// need different fixes and look identical in a boolean.
    pub fn check(
        &mut self,
        id: &str,
        status: Status,
        expected: &str,
        actual: &str,
        detail: &str,
    ) {
        let pr = self.attribution.get(id).map(String::as_str).unwrap_or("-").to_string();
        let pr = pr.as_str();
        let rec = Record {
            perm: &self.perm,
            check: id,
            pr,
            status: status.as_str(),
            expected,
            actual,
            detail,
        };
        match serde_json::to_string(&rec) {
            Ok(line) => {
                let _ = writeln!(self.file, "{line}");
                let _ = self.file.flush();
            }
            Err(e) => eprintln!("sharukhan: could not record check {id}: {e}"),
        }
        match status {
            Status::Pass => {
                self.pass += 1;
                if self.echo {
                    println!("  PASS  {id:<34} {pr:<10} {actual}");
                }
            }
            Status::Fail => {
                self.fail += 1;
                self.failed.push(id.to_string());
                if pr != "-" && !pr.is_empty() && !self.prs.iter().any(|p| p == pr) {
                    self.prs.push(pr.to_string());
                }
                if self.echo {
                    println!("  FAIL  {id:<34} {pr:<10} expected={expected} actual={actual}");
                }
            }
            Status::Skip => {
                self.skip += 1;
                if self.echo {
                    println!("  skip  {id:<34} {pr:<10} {detail}");
                }
            }
            Status::Info => {
                self.info += 1;
                if self.echo {
                    println!("  info  {id:<34} {pr:<10} {actual}");
                }
            }
        }
    }

    /// Pass when measured equals expected, fail otherwise.
    pub fn expect(&mut self, id: &str, expected: &str, actual: &str, detail: &str) {
        let st = if expected == actual {
            Status::Pass
        } else {
            Status::Fail
        };
        self.check(id, st, expected, actual, detail);
    }

    pub fn total(&self) -> usize {
        self.pass + self.fail + self.skip + self.info
    }

    pub fn summary(&self) -> String {
        let mut s = format!(
            "  {}: {} checks, {} pass, {} fail",
            self.perm,
            self.total(),
            self.pass,
            self.fail
        );
        if !self.prs.is_empty() {
            s.push_str(&format!("\n  PRs implicated: {}", self.prs.join(", ")));
        }
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("sharukhan-ev-{}-{tag}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    /// The stored evidence under results/ is the format; a change here would
    /// make 21 existing runs unreadable.
    #[test]
    fn the_line_format_matches_the_stored_evidence() {
        let d = tmpdir("fmt");
        let mut c = Checks::init(&d, "k01", "20260901T000000Z").unwrap();
        c.echo = false;
        c.check(
            "meta.doc_verdict",
            Status::Info,
            "",
            "works",
            "what ISO-PERMUTATION-MATRIX.md records",
        );
        let text = fs::read_to_string(&c.path).unwrap();
        assert_eq!(
            text.trim(),
            "{\"perm\":\"k01\",\"check\":\"meta.doc_verdict\",\"pr\":\"-\",\"status\":\"info\",\
             \"expected\":\"\",\"actual\":\"works\",\"detail\":\"what ISO-PERMUTATION-MATRIX.md records\"}"
        );
        fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn latest_points_at_this_run_not_at_the_previous_one() {
        let d = tmpdir("latest");
        let mut a = Checks::init(&d, "k02", "20260901T000000Z").unwrap();
        a.echo = false;
        a.check("x", Status::Pass, "1", "1", "");
        let mut b = Checks::init(&d, "k02", "20260901T010000Z").unwrap();
        b.echo = false;
        b.check("y", Status::Pass, "1", "1", "");
        // The earlier file still exists: a re-run must never destroy the
        // evidence of the run before it.
        assert!(d.join("k02/checks-20260901T000000Z.jsonl").exists());
        let link = fs::read_link(d.join("k02/checks-latest.jsonl")).unwrap();
        assert_eq!(link.to_string_lossy(), "checks-20260901T010000Z.jsonl");
        fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn quotes_and_newlines_in_a_measured_value_stay_on_one_line() {
        let d = tmpdir("esc");
        let mut c = Checks::init(&d, "s02", "20260901T000000Z").unwrap();
        c.echo = false;
        c.check(
            "guest.ssh",
            Status::Fail,
            "reachable",
            "ssh_dispatch_run_fatal: invalid \"argument\"\n[preauth]",
            "",
        );
        let text = fs::read_to_string(&c.path).unwrap();
        assert_eq!(text.lines().count(), 1);
        assert!(text.contains("\\n[preauth]"));
        assert!(text.contains("invalid \\\"argument\\\""));
        fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn failures_collect_the_prs_they_implicate() {
        let d = tmpdir("prs");
        let mut c = Checks::init(&d, "k11", "20260901T000000Z").unwrap();
        c.echo = false;
        // the attribution is data (config/check-prs.tsv); two checks of one PR
        let attr = d.join("check-prs.tsv");
        fs::write(&attr, "# test\nguest.no_render_group\tPR#22\nguest.no_journal_group PR#22\nguest.failed_units\tPR#9\n").unwrap();
        c.attribution = load_attribution(&attr).unwrap();
        c.expect("guest.no_render_group", "0", "3", "");
        c.expect("guest.failed_units", "0", "0", "");
        c.expect("guest.no_journal_group", "0", "1", "");
        assert_eq!((c.pass, c.fail), (1, 2));
        assert_eq!(c.prs, vec!["PR#22".to_string()]);
        assert_eq!(c.failed.len(), 2);
        assert!(c.summary().contains("3 checks, 1 pass, 2 fail"));
        fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn a_malformed_attribution_is_refused() {
        let d = tmpdir("attr");
        for (bad, why) in [("x PR#\n", "expected"), ("x 22\n", "expected"), ("x PR#1 extra\n", "expected"), ("x PR#1\nx POI#2\n", "twice")] {
            let p = d.join("a.tsv");
            fs::write(&p, bad).unwrap();
            assert!(load_attribution(&p).unwrap_err().contains(why), "{bad:?}");
        }
        fs::remove_dir_all(&d).ok();
    }

    /// The shipped attribution file must load.
    #[test]
    fn the_shipped_attribution_loads() {
        let p = Path::new(env!("CARGO_MANIFEST_DIR")).join("../mission-control/config/check-prs.tsv");
        let a = load_attribution(&p).unwrap();
        assert_eq!(a.get("guest.selinux").map(String::as_str), Some("PR#9"));
    }
}
