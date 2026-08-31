//! The permutation matrix.
//!
//! permutations.tsv is whitespace-aligned, not tab-separated, despite the name.
//! Splitting on '\t' silently yields zero rows, so split on whitespace.

use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Permutation {
    pub id: String,
    pub iso_type: String,
    pub poi: String,
    pub stig: String,
    pub fs: String,
    pub mode: String,
    pub variant: String,
    pub doc: String,
}

impl Permutation {
    /// True when this row needs a human at the installer console.
    pub fn needs_operator(&self) -> bool {
        self.mode == "ui"
    }
    /// Build-time axes decide which ISO serves the row.
    pub fn iso_key(&self) -> String {
        format!("{}/{}", self.iso_type, self.poi)
    }
}

pub fn load(path: &Path) -> Result<Vec<Permutation>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut out = Vec::new();
    for line in text.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let f: Vec<&str> = t.split_whitespace().collect();
        if f.len() < 8 {
            continue;
        }
        out.push(Permutation {
            id: f[0].into(),
            iso_type: f[1].into(),
            poi: f[2].into(),
            stig: f[3].into(),
            fs: f[4].into(),
            mode: f[5].into(),
            variant: f[6].into(),
            doc: f[7].into(),
        });
    }
    if out.is_empty() {
        return Err(format!("no permutations parsed from {}", path.display()));
    }
    Ok(out)
}

/// Filter by a comma-separated id list. Unknown ids are an error rather than a
/// silent no-op: asking for a row that does not exist should never look like a
/// clean run.
pub fn select(all: &[Permutation], only: Option<&str>) -> Result<Vec<Permutation>, String> {
    let Some(spec) = only else {
        return Ok(all.to_vec());
    };
    let want: Vec<&str> = spec.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect();
    let mut out = Vec::new();
    let mut missing = Vec::new();
    for id in &want {
        match all.iter().find(|p| p.id == *id) {
            Some(p) => out.push(p.clone()),
            None => missing.push(id.to_string()),
        }
    }
    if !missing.is_empty() {
        return Err(format!("unknown permutation id(s): {}", missing.join(", ")));
    }
    Ok(out)
}
