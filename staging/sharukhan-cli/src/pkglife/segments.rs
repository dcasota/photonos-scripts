//! Every package of a row, even when one of them takes the guest down.
//!
//! A lifecycle run stops when a package leaves the guest away from its
//! baseline or unreachable - by design: verdicts on a guest that is not
//! known-good are unattributable. In a 1,932-package baseline that stopped
//! k09 after 3 packages (Linux-PAM) and c01 after 1,375 (python3-hyperlink),
//! so most of the media was never tested.
//!
//! This keeps the design and finishes the row: after a stop the remaining
//! packages run on a FRESHLY INSTALLED guest (create-vm --recreate, install),
//! one segment at a time. The package that broke the guest keeps its fail;
//! every segment must reach at least one package more than the last, or the
//! run ends with an error instead of looping. The segments' records are
//! appended to one file, so the last record of a package - its real
//! verdict - wins wherever a file is read (pkg-compare, ingest).

use super::record::{self, PkgRecord, NOT_REACHED};
use super::Opts;
use crate::config::Config;
use std::io::Write;
use std::path::{Path, PathBuf};

/// A run's records that never got a verdict.
pub fn unreached(recs: &[PkgRecord]) -> Vec<String> {
    let mut v: Vec<String> = recs
        .iter()
        .filter(|r| r.verdict == NOT_REACHED)
        .map(|r| r.package.clone())
        .collect();
    v.sort();
    v.dedup();
    v
}

/// Packages whose final record says the guest was lost while they were
/// tested. A host-side outage (WSL and VMware networking stalling together,
/// measured 2026-10-04: three guests lost within ten minutes) is recorded
/// against whatever package was in flight; each of these is tested once
/// more, alone, on a fresh guest, and that verdict stands.
pub fn guest_lost(recs: &[PkgRecord]) -> Vec<String> {
    let mut last: std::collections::BTreeMap<&str, &PkgRecord> = Default::default();
    for r in recs {
        last.insert(r.package.as_str(), r);
    }
    last.into_iter()
        .filter(|(_, r)| {
            r.steps
                .iter()
                .any(|s| s.name == "guest-state" && s.status == record::FAIL)
        })
        .map(|(p, _)| p.to_string())
        .collect()
}

/// Whether a segment advanced: fewer packages remain than before it.
pub fn progressed(before: Option<usize>, after: usize) -> bool {
    match before {
        None => true,
        Some(b) => after < b,
    }
}

fn latest(results: &Path, id: &str) -> Option<PathBuf> {
    std::fs::canonicalize(results.join(id).join("pkglife-latest.jsonl")).ok()
}

pub struct Outcome {
    pub merged: PathBuf,
    pub segments: usize,
    pub unreached: Vec<String>,
}

pub fn run(
    cfg: &Config,
    id: &str,
    iso: &Path,
    base: &Opts,
    max_segments: usize,
    log: &mut dyn FnMut(&str),
) -> Result<Outcome, String> {
    if !iso.is_file() {
        return Err(format!("{}: not a file", iso.display()));
    }
    let stamp = crate::job::stamp();
    let merged = cfg
        .results_dir
        .join(id)
        .join(format!("pkglife-segmented-{stamp}.jsonl"));
    std::fs::create_dir_all(merged.parent().unwrap())
        .map_err(|e| format!("{}: {e}", merged.display()))?;
    let mut out = std::fs::File::create(&merged).map_err(|e| format!("{}: {e}", merged.display()))?;
    let iso_s = iso.to_string_lossy().to_string();
    let mut remaining: Option<Vec<String>> = base.packages.clone();
    let mut before: Option<usize> = None;
    let mut segments = 0;
    let mut left: Vec<String> = Vec::new();

    let mut seg = 0;
    let mut interop_waits = 0;
    let mut network_retries = 0;
    while seg < max_segments {
        seg += 1;
        segments = seg;
        log(&format!(
            "segment {seg}: fresh guest for {id}, {} package(s)",
            remaining.as_ref().map(|r| r.len().to_string()).unwrap_or_else(|| "all".into())
        ));
        let prev = latest(&cfg.results_dir, id);
        if let Err(e) = fresh_guest(cfg, id, &iso_s) {
            // A guest that cannot be created or installed while WSL interop
            // is down says nothing about the packages: wait for interop and
            // retry the same segment (bounded), otherwise stop as before.
            if interop_waits < MAX_INTEROP_WAITS && !crate::vmware::interop_alive(&cfg.vmrun) {
                interop_waits += 1;
                log(&format!("segment {seg}: {e}"));
                if crate::vmware::wait_for_interop(&cfg.vmrun, INTEROP_WAIT, log) {
                    seg -= 1;
                    continue;
                }
            }
            return Err(format!("segment {seg}: no guest, no package verdicts: {e}"));
        }
        let mut o = base.clone();
        o.packages = remaining.clone();
        o.resume = false;
        // A failing package fails verify's checks; the records are the result.
        if let Err(e) = crate::phases::cmd_verify(cfg, id, None, Some(&o), Some(&iso_s)) {
            log(&format!("segment {seg}: verify reported: {e}"));
        }
        let file = latest(&cfg.results_dir, id);
        let _ = crate::phases::cmd_teardown(cfg, id, true);
        let file = match file {
            Some(f) if Some(&f) != prev.as_ref() => f,
            _ => {
                // verify refused the guest. When the only thing wrong with it
                // is the bench network being late at first boot (wait-online
                // failed, every other check - the network ones included -
                // passed), the guest says nothing about the packages: try a
                // fresh one, a bounded number of times.
                if network_retries < MAX_NETWORK_RETRIES {
                    if let Some(why) = bench_network_only_latest(&cfg.results_dir, id) {
                        network_retries += 1;
                        log(&format!(
                            "segment {seg}: {why}; fresh guest again ({network_retries}/{MAX_NETWORK_RETRIES})"
                        ));
                        seg -= 1;
                        continue;
                    }
                }
                return Err(format!("segment {seg}: verify wrote no new lifecycle file for {id}"));
            }
        };
        let recs = record::read(&file)?;
        for r in &recs {
            let line = serde_json::to_string(r).map_err(|e| e.to_string())?;
            writeln!(out, "{line}").map_err(|e| format!("{}: {e}", merged.display()))?;
        }
        left = unreached(&recs);
        log(&format!(
            "segment {seg}: {} record(s) from {}, {} not reached",
            recs.len(),
            file.display(),
            left.len()
        ));
        if left.is_empty() {
            break;
        }
        if !progressed(before, left.len()) {
            return Err(format!(
                "segment {seg} reached no package the previous one had not: stopping with {} unreached (merged so far: {})",
                left.len(),
                merged.display()
            ));
        }
        before = Some(left.len());
        remaining = Some(left.clone());
    }
    // Each package recorded as losing the guest is tested once more, alone,
    // on a fresh guest; its last record - this one - is its verdict.
    let all = record::read(&merged)?;
    for p in guest_lost(&all) {
        log(&format!("retest of {p}, alone on a fresh guest (it was in flight when the guest was lost)"));
        let mut attempts = 0;
        let file = loop {
            attempts += 1;
            let prev = latest(&cfg.results_dir, id);
            if let Err(e) = fresh_guest(cfg, id, &iso_s) {
                if attempts <= MAX_INTEROP_WAITS && !crate::vmware::interop_alive(&cfg.vmrun)
                    && crate::vmware::wait_for_interop(&cfg.vmrun, INTEROP_WAIT, log)
                {
                    continue;
                }
                log(&format!("retest of {p}: no guest ({e}); its first record stands"));
                break None;
            }
            let mut o = base.clone();
            o.packages = Some(vec![p.clone()]);
            o.resume = false;
            if let Err(e) = crate::phases::cmd_verify(cfg, id, None, Some(&o), Some(&iso_s)) {
                log(&format!("retest of {p}: verify reported: {e}"));
            }
            let f = latest(&cfg.results_dir, id);
            let _ = crate::phases::cmd_teardown(cfg, id, true);
            break f.filter(|f| Some(f) != prev.as_ref());
        };
        if let Some(f) = file {
            for r in record::read(&f)?.iter().filter(|r| r.package == p) {
                let line = serde_json::to_string(r).map_err(|e| e.to_string())?;
                writeln!(out, "{line}").map_err(|e| format!("{}: {e}", merged.display()))?;
                log(&format!("retest of {p}: {}", r.verdict));
            }
        }
    }
    Ok(Outcome { merged, segments, unreached: left })
}

/// How often a segment retries a guest whose only fault is the bench network
/// at first boot.
const MAX_NETWORK_RETRIES: usize = 3;

/// Checks that failed in a verify run's checks file.
pub fn failed_checks(checks: &str) -> Vec<String> {
    checks
        .lines()
        .filter_map(|l| serde_json::from_str::<serde_json::Value>(l).ok())
        .filter(|v| v.get("status").and_then(|s| s.as_str()) == Some("fail"))
        .filter_map(|v| v.get("check").and_then(|c| c.as_str()).map(str::to_string))
        .collect()
}

/// Units `systemctl --failed` lists as loaded and failed.
pub fn failed_unit_names(text: &str) -> Vec<String> {
    text.lines()
        .filter_map(|l| {
            let t: Vec<&str> = l.trim_start_matches(|c: char| c == '\u{25cf}' || c.is_whitespace())
                .split_whitespace()
                .collect();
            (t.len() >= 3 && t[1] == "loaded" && t[2] == "failed").then(|| t[0].to_string())
        })
        .collect()
}

/// The unit that fails when the bench's DHCP answers after its timeout.
const BENCH_NETWORK_UNIT: &str = "systemd-networkd-wait-online.service";

/// Why a refused guest is only the bench network's fault, or None: the one
/// failing check is guest.failed_units and the one failed unit is
/// wait-online.
pub fn bench_network_only(checks: &str, failed_units: &str) -> Option<String> {
    let fails = failed_checks(checks);
    let units = failed_unit_names(failed_units);
    (fails == ["guest.failed_units"] && units == [BENCH_NETWORK_UNIT]).then(|| {
        format!("the guest's only fault is {BENCH_NETWORK_UNIT} (no DHCP lease within its timeout at first boot); every other check passed")
    })
}

fn bench_network_only_latest(results: &Path, id: &str) -> Option<String> {
    let dir = results.join(id);
    let checks = std::fs::read_to_string(dir.join("checks-latest.jsonl")).ok()?;
    let units = std::fs::read_to_string(dir.join("logs-latest").join("failed-units.txt")).ok()?;
    bench_network_only(&checks, &units)
}

/// How long a segment waits for WSL interop to come back, and how often.
const INTEROP_WAIT: std::time::Duration = std::time::Duration::from_secs(12 * 3600);
const MAX_INTEROP_WAITS: usize = 3;

/// create-vm --recreate and install: a known-good guest, or why not.
fn fresh_guest(cfg: &Config, id: &str, iso: &str) -> Result<(), String> {
    crate::phases::cmd_create_vm(cfg, id, Some(iso), None, true, false)?;
    if let Err(e) = crate::phases::cmd_install(cfg, id, None, None, false) {
        let _ = crate::phases::cmd_teardown(cfg, id, true);
        return Err(format!("install failed: {e}"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(p: &str, v: &str) -> PkgRecord {
        PkgRecord { package: p.into(), verdict: v.into(), ..Default::default() }
    }

    #[test]
    fn unreached_lists_each_package_once() {
        let r = vec![rec("b", NOT_REACHED), rec("a", "pass"), rec("b", NOT_REACHED), rec("c", NOT_REACHED)];
        assert_eq!(unreached(&r), vec!["b".to_string(), "c".to_string()]);
    }

    #[test]
    fn a_package_that_lost_the_guest_is_retested_by_its_last_record_only() {
        let lost = |p: &str| {
            let mut r = rec(p, "fail");
            r.steps.push(record::Step::new("guest-state", record::FAIL, "rpm -qa: exit Some(255)", 0));
            r
        };
        let mut other = rec("b", "fail");
        other.steps.push(record::Step::new("journal-window", record::FAIL, "x", 0));
        let recs = vec![
            lost("a"),
            other,
            lost("c"),
            rec("c", "pass"), // c's retest passed: its last record wins
            rec("d", "pass"),
        ];
        // a lost the guest; b failed for another reason; c was retested; d passed
        assert_eq!(guest_lost(&recs), vec!["a".to_string()]);
    }

    const UNITS_WAIT_ONLINE: &str = "  UNIT                                 LOAD   ACTIVE SUB    DESCRIPTION\n\u{25cf} systemd-networkd-wait-online.service loaded failed failed Wait for Network to be Configured\n\nLegend: LOAD   \u{2192} Reflects whether the unit definition was properly loaded.\n";
    const CHECKS_UNITS_ONLY: &str = "{\"check\":\"net.v4_addr\",\"status\":\"pass\"}\n{\"check\":\"guest.failed_units\",\"status\":\"fail\"}\n";

    #[test]
    fn a_late_bench_network_alone_is_retried() {
        assert!(bench_network_only(CHECKS_UNITS_ONLY, UNITS_WAIT_ONLINE).is_some());
    }

    #[test]
    fn any_other_fault_is_not_retried() {
        // another failed unit next to wait-online
        let two = format!("{UNITS_WAIT_ONLINE}\u{25cf} sshd.service loaded failed failed OpenSSH\n");
        assert!(bench_network_only(CHECKS_UNITS_ONLY, &two).is_none());
        // a different unit alone
        assert!(bench_network_only(CHECKS_UNITS_ONLY, "\u{25cf} sshd.service loaded failed failed OpenSSH\n").is_none());
        // another failing check next to failed_units
        let more = format!("{CHECKS_UNITS_ONLY}{{\"check\":\"net.dns_resolves\",\"status\":\"fail\"}}\n");
        assert!(bench_network_only(&more, UNITS_WAIT_ONLINE).is_none());
        // nothing failed at all: not this case either
        assert!(bench_network_only("{\"check\":\"x\",\"status\":\"pass\"}\n", "").is_none());
    }

    #[test]
    fn failed_units_are_read_from_systemctl_output() {
        assert_eq!(failed_unit_names(UNITS_WAIT_ONLINE), vec![BENCH_NETWORK_UNIT.to_string()]);
        assert!(failed_unit_names("0 loaded units listed.\n").is_empty());
    }

    #[test]
    fn a_segment_must_reach_something_new() {
        assert!(progressed(None, 1929));
        assert!(progressed(Some(1929), 600));
        assert!(!progressed(Some(600), 600));
        assert!(!progressed(Some(600), 700));
    }
}
