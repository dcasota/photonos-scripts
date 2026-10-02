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

    for seg in 1..=max_segments {
        segments = seg;
        log(&format!(
            "segment {seg}: fresh guest for {id}, {} package(s)",
            remaining.as_ref().map(|r| r.len().to_string()).unwrap_or_else(|| "all".into())
        ));
        let prev = latest(&cfg.results_dir, id);
        crate::phases::cmd_create_vm(cfg, id, Some(&iso_s), None, true, false)?;
        if let Err(e) = crate::phases::cmd_install(cfg, id, None, None, false) {
            let _ = crate::phases::cmd_teardown(cfg, id, true);
            return Err(format!("segment {seg}: install failed, no package verdicts: {e}"));
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
            _ => return Err(format!("segment {seg}: verify wrote no new lifecycle file for {id}")),
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
    Ok(Outcome { merged, segments, unreached: left })
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
    fn a_segment_must_reach_something_new() {
        assert!(progressed(None, 1929));
        assert!(progressed(Some(1929), 600));
        assert!(!progressed(Some(600), 600));
        assert!(!progressed(Some(600), 700));
    }
}
