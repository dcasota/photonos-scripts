//! The per-package evidence record and the file it lives in.
//!
//! `results/<perm>/pkglife-<stamp>.jsonl`, one object per package, written
//! line by line as each package finishes so a crash loses at most the package
//! in flight; `pkglife-latest.jsonl` points at the newest. The stamp is the
//! stamp of the checks file the same run wrote, which is how `ingest` ties the
//! two to one permutation row.
//!
//! Every string that came from the guest is bounded ([`clip`]) - a package
//! whose version probe prints a megabyte must not produce a megabyte record -
//! and scrubbed of the guest password on the way in, as the harvest is.

use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

pub const PASS: &str = "pass";
pub const FAIL: &str = "fail";
pub const SKIP: &str = "skip";
pub const INFO: &str = "info";
pub const NOT_REACHED: &str = "not-reached";

/// Longest value kept in a record field.
pub const FIELD_LIMIT: usize = 2000;

pub fn clip(s: &str) -> String {
    let t = s.trim_end();
    if t.len() <= FIELD_LIMIT {
        return t.to_string();
    }
    let mut end = FIELD_LIMIT;
    while !t.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}... [{} bytes total]", &t[..end], t.len())
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct Step {
    pub name: String,
    pub status: String,
    pub detail: String,
    pub ms: u64,
}

impl Step {
    pub fn new(name: &str, status: &str, detail: impl Into<String>, ms: u64) -> Step {
        Step {
            name: name.to_string(),
            status: status.to_string(),
            detail: clip(&detail.into()),
            ms,
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct UnitResult {
    pub unit: String,
    pub kind: String,
    /// What the policy decided before anything ran: cycle, cycle-deadman,
    /// observe, skip: <reason>.
    pub plan: String,
    pub status: String,
    pub outcome: String,
    pub steps: Vec<Step>,
    pub journal_errors: Vec<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct ProbeAttempt {
    pub args: Vec<String>,
    pub code: Option<i32>,
    pub timed_out: bool,
    pub ms: u64,
    pub stdout: String,
    pub stderr: String,
    pub verdict: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct CliResult {
    pub path: String,
    pub status: String,
    pub reason: String,
    pub attempts: Vec<ProbeAttempt>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct PkgRecord {
    pub perm: String,
    pub stamp: String,
    pub machine_id: String,
    pub policy_sha256: String,
    pub package: String,
    pub evr: String,
    pub arch: String,
    /// fresh = installed by this run and removed again; preinstalled =
    /// tested in place and never removed.
    pub origin: String,
    pub classes: Vec<String>,
    pub verdict: String,
    pub reason: String,
    pub duration_ms: u64,
    /// The packages the install transaction added (the package and its
    /// dependencies), as name-evr.arch.
    pub installed: Vec<String>,
    pub steps: Vec<Step>,
    pub units: Vec<UnitResult>,
    pub clis: Vec<CliResult>,
    pub journal_errors: Vec<String>,
    /// Set when this record was taken over from an earlier run on the same
    /// guest by --pkg-resume; names that run's stamp.
    #[serde(default)]
    pub carried_from: Option<String>,
}

impl PkgRecord {
    /// The verdict follows from the parts, never the other way round: any
    /// failed step, unit or CLI fails the package; a package where nothing
    /// could be tested at all is a skip with the reason.
    pub fn settle(&mut self) {
        let failed: Vec<String> = self
            .steps
            .iter()
            .filter(|s| s.status == FAIL)
            .map(|s| s.name.clone())
            .chain(
                self.units
                    .iter()
                    .filter(|u| u.status == FAIL)
                    .map(|u| format!("unit {}", u.unit)),
            )
            .chain(
                self.clis
                    .iter()
                    .filter(|c| c.status == FAIL)
                    .map(|c| format!("cli {}", c.path)),
            )
            .collect();
        if !failed.is_empty() {
            self.verdict = FAIL.into();
            let mut r = failed.join(", ");
            if !self.reason.is_empty() {
                r = format!("{}; {r}", self.reason);
            }
            self.reason = clip(&r);
            return;
        }
        let tested = self.steps.iter().any(|s| s.status == PASS)
            || self.units.iter().any(|u| u.status == PASS)
            || self.clis.iter().any(|c| c.status == PASS);
        if tested {
            self.verdict = PASS.into();
        } else if self.verdict.is_empty() {
            self.verdict = SKIP.into();
            if self.reason.is_empty() {
                self.reason = "nothing testable".into();
            }
        }
    }

    /// One line for the checks file: the measured summary, not a bare word.
    pub fn summary(&self) -> String {
        let fails = self.steps.iter().filter(|s| s.status == FAIL).count()
            + self.units.iter().filter(|u| u.status == FAIL).count()
            + self.clis.iter().filter(|c| c.status == FAIL).count();
        format!(
            "{} {} [{}] {} unit(s), {} cli(s), {} failing part(s), {} ms",
            self.origin,
            self.evr,
            self.classes.join(","),
            self.units.len(),
            self.clis.len(),
            fails,
            self.duration_ms
        )
    }
}

pub struct Writer {
    pub path: PathBuf,
    file: File,
}

impl Writer {
    pub fn create(results_dir: &Path, perm: &str, stamp: &str) -> Result<Writer, String> {
        let dir = results_dir.join(perm);
        fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let path = dir.join(format!("pkglife-{stamp}.jsonl"));
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .map_err(|e| format!("{}: {e}", path.display()))?;
        let link = dir.join("pkglife-latest.jsonl");
        let _ = fs::remove_file(&link);
        let _ = std::os::unix::fs::symlink(format!("pkglife-{stamp}.jsonl"), &link);
        Ok(Writer { path, file })
    }

    pub fn write(&mut self, r: &PkgRecord) -> Result<(), String> {
        let line = serde_json::to_string(r).map_err(|e| format!("record {}: {e}", r.package))?;
        writeln!(self.file, "{line}").map_err(|e| format!("{}: {e}", self.path.display()))?;
        self.file
            .flush()
            .map_err(|e| format!("{}: {e}", self.path.display()))
    }
}

/// Records of a previous lifecycle file, for --pkg-resume. Malformed lines are
/// reported, not skipped: a resume that silently forgot half its input would
/// re-test packages or, worse, claim they were never reached.
pub fn read(path: &Path) -> Result<Vec<PkgRecord>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .enumerate()
        .map(|(i, l)| {
            serde_json::from_str(l).map_err(|e| format!("{}:{}: {e}", path.display(), i + 1))
        })
        .collect()
}

/// The records a resume may keep: same guest (machine-id), same policy, and
/// a final verdict. A package that was not reached, or whose record came from
/// another guest or another policy, is tested again.
pub fn carry(previous: Vec<PkgRecord>, machine_id: &str, policy_sha: &str) -> Vec<PkgRecord> {
    previous
        .into_iter()
        .filter(|r| {
            r.machine_id == machine_id
                && r.policy_sha256 == policy_sha
                && [PASS, FAIL, SKIP].contains(&r.verdict.as_str())
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(verdict: &str) -> PkgRecord {
        PkgRecord {
            package: "x".into(),
            machine_id: "m".into(),
            policy_sha256: "p".into(),
            verdict: verdict.into(),
            ..Default::default()
        }
    }

    #[test]
    fn the_verdict_follows_from_the_parts() {
        let mut r = rec("");
        r.steps.push(Step::new("rpm-verify", PASS, "clean", 1));
        r.settle();
        assert_eq!(r.verdict, PASS);

        let mut r = rec("");
        r.steps.push(Step::new("rpm-verify", PASS, "", 1));
        r.units.push(UnitResult {
            unit: "a.service".into(),
            status: FAIL.into(),
            ..Default::default()
        });
        r.clis.push(CliResult {
            path: "/usr/bin/a".into(),
            status: FAIL.into(),
            ..Default::default()
        });
        r.settle();
        assert_eq!(r.verdict, FAIL);
        assert_eq!(r.reason, "unit a.service, cli /usr/bin/a");

        // negative control: skips alone never make a pass
        let mut r = rec("");
        r.steps.push(Step::new("install", SKIP, "conflict", 1));
        r.settle();
        assert_eq!(r.verdict, SKIP);
        assert_eq!(r.reason, "nothing testable");

        let mut r = rec(SKIP);
        r.reason = "boot-affecting".into();
        r.settle();
        assert_eq!(
            (r.verdict.as_str(), r.reason.as_str()),
            (SKIP, "boot-affecting")
        );
    }

    #[test]
    fn a_pre_existing_reason_is_kept_ahead_of_the_failures() {
        let mut r = rec("");
        r.reason = "installed set differs".into();
        r.steps.push(Step::new("install", FAIL, "", 1));
        r.settle();
        assert_eq!(r.reason, "installed set differs; install");
    }

    #[test]
    fn fields_are_bounded_on_a_char_boundary() {
        let long = "é".repeat(FIELD_LIMIT);
        let c = clip(&long);
        assert!(c.len() < long.len());
        assert!(c.ends_with(&format!("[{} bytes total]", long.len())));
        assert_eq!(clip("short\n"), "short");
        assert!(Step::new("a", PASS, "x".repeat(5000), 0).detail.len() < 2100);
    }

    #[test]
    fn records_round_trip_and_resume_keeps_only_final_verdicts_from_this_guest() {
        let d = std::env::temp_dir().join(format!("sharukhan-rec-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let mut w = Writer::create(&d, "k09", "20260927T000000Z").unwrap();
        let mut a = rec(PASS);
        a.package = "a".into();
        let mut b = rec(NOT_REACHED);
        b.package = "b".into();
        let mut c = rec(FAIL);
        c.package = "c".into();
        c.machine_id = "other-guest".into();
        let mut e = rec(SKIP);
        e.package = "e".into();
        e.policy_sha256 = "older-policy".into();
        for r in [&a, &b, &c, &e] {
            w.write(r).unwrap();
        }
        let link = fs::read_link(d.join("k09/pkglife-latest.jsonl")).unwrap();
        assert_eq!(link.to_string_lossy(), "pkglife-20260927T000000Z.jsonl");
        let back = read(&w.path).unwrap();
        assert_eq!(back.len(), 4);
        let kept = carry(back, "m", "p");
        assert_eq!(
            kept.iter().map(|r| r.package.as_str()).collect::<Vec<_>>(),
            vec!["a"]
        );
        // a corrupt line is an error, not a shorter list
        fs::write(&w.path, "{\"package\":1}\n").unwrap();
        assert!(read(&w.path).is_err());
        assert!(read(&d.join("none.jsonl")).is_err());
        fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn the_summary_is_measured() {
        let mut r = rec(PASS);
        r.origin = "fresh".into();
        r.evr = "4.3-3.ph5".into();
        r.classes = vec!["daemon".into(), "cli".into()];
        r.duration_ms = 1234;
        assert_eq!(
            r.summary(),
            "fresh 4.3-3.ph5 [daemon,cli] 0 unit(s), 0 cli(s), 0 failing part(s), 1234 ms"
        );
    }
}
