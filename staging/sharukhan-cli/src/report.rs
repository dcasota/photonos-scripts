//! Per-permutation results harvested by the run phase.
//!
//! Result files are timestamped (checks-<UTC>.jsonl) with a checks-latest.jsonl
//! symlink, so a re-run never overwrites the evidence of the previous one.

use std::fs;
use std::path::Path;

#[derive(Default)]
pub struct Outcome {
    pub pass: usize,
    pub fail: usize,
    pub info: usize,
    pub stamp: String,
    pub failed_checks: Vec<String>,
}

/// Minimal field extraction. The result files are one JSON object per line with
/// flat string values, so a tiny scanner avoids a serde dependency for what is
/// really a log format.
fn field(line: &str, key: &str) -> Option<String> {
    let pat = format!("\"{key}\"");
    let i = line.find(&pat)? + pat.len();
    let rest = &line[i..];
    let c = rest.find(':')? + 1;
    let rest = rest[c..].trim_start();
    if let Some(stripped) = rest.strip_prefix('"') {
        let end = stripped.find('"')?;
        Some(stripped[..end].to_string())
    } else {
        let end = rest.find([',', '}']).unwrap_or(rest.len());
        Some(rest[..end].trim().to_string())
    }
}

pub fn read(results_dir: &Path, id: &str) -> Option<Outcome> {
    let dir = results_dir.join(id);
    let latest = dir.join("checks-latest.jsonl");
    let path = if latest.exists() {
        latest
    } else {
        let mut cands: Vec<_> = fs::read_dir(&dir)
            .ok()?
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| n.starts_with("checks") && n.ends_with(".jsonl"))
                    .unwrap_or(false)
            })
            .collect();
        cands.sort();
        cands.pop()?
    };
    let text = fs::read_to_string(&path).ok()?;
    let mut o = Outcome {
        stamp: fs::canonicalize(&path)
            .ok()
            .and_then(|p| p.file_name().and_then(|n| n.to_str()).map(str::to_string))
            .unwrap_or_default(),
        ..Default::default()
    };
    for line in text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let status = field(line, "status").or_else(|| field(line, "result")).unwrap_or_default();
        let name = field(line, "check").or_else(|| field(line, "name")).unwrap_or_default();
        match status.as_str() {
            "pass" => o.pass += 1,
            "fail" => {
                o.fail += 1;
                o.failed_checks.push(name);
            }
            _ => o.info += 1,
        }
    }
    Some(o)
}
