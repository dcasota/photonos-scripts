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
    /// Whether each record is also printed as it is written. A run driving many
    /// rows wants the lines; a caller collecting a summary does not.
    pub echo: bool,
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
        let _ = std::os::unix::fs::symlink(
            path.file_name().unwrap_or_default(),
            &link,
        );
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
            echo: true,
        })
    }

    /// One assertion. `actual` is always the MEASURED value, never a bare
    /// OK/FAIL: "tool missing" and "tool present but unreadable by this user"
    /// need different fixes and look identical in a boolean.
    pub fn check(
        &mut self,
        id: &str,
        pr: &str,
        status: Status,
        expected: &str,
        actual: &str,
        detail: &str,
    ) {
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
    pub fn expect(&mut self, id: &str, pr: &str, expected: &str, actual: &str, detail: &str) {
        let st = if expected == actual { Status::Pass } else { Status::Fail };
        self.check(id, pr, st, expected, actual, detail);
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
            "-",
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
        a.check("x", "-", Status::Pass, "1", "1", "");
        let mut b = Checks::init(&d, "k02", "20260901T010000Z").unwrap();
        b.echo = false;
        b.check("y", "-", Status::Pass, "1", "1", "");
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
            "-",
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
        c.expect("guest.no_render_group", "PR#22", "0", "3", "");
        c.expect("guest.failed_units", "PR#9", "0", "0", "");
        c.expect("guest.no_journal_group", "PR#22", "0", "1", "");
        assert_eq!((c.pass, c.fail), (1, 2));
        assert_eq!(c.prs, vec!["PR#22".to_string()]);
        assert_eq!(c.failed.len(), 2);
        assert!(c.summary().contains("3 checks, 1 pass, 2 fail"));
        fs::remove_dir_all(&d).ok();
    }
}
