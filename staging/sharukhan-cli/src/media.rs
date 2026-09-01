//! Proving an ISO carries the packages under test.
//!
//! A verdict from media that does not carry the PRs is worse than no verdict:
//! it reports on code nobody is shipping. This module answers two questions -
//! what SHOULD be on the media, and what IS - and never conflates them.
//!
//! The expected NEVR is derived, never written down. A driver that hardcoded
//! `2.9-2` rejected a perfectly good ISO once the spec moved to `2.9-3`, and
//! could not be corrected in place because bash re-reads a running script.

use std::path::Path;
use std::process::Command;

pub struct Gate {
    pub expected: String,
    pub actual: String,
    pub ok: bool,
}

/// The installer NEVR prefix this variant's patch asks for.
///
/// The variant patch touches ~28 spec files, so grepping the whole patch for
/// `+Release:` picks up whichever spec happens to come last rather than the
/// installer's. Isolate the photon-os-installer.spec hunk first.
///
/// `Version:` is only bumped by the `latest` variant; for `2.8` it comes from
/// the PRISTINE tree via `git show origin/5.0:`, never from the working tree,
/// which holds whatever the previous build left patched.
pub fn expected_installer(variant_patch: &Path, photon_tree: &Path) -> Result<String, String> {
    let text = std::fs::read_to_string(variant_patch)
        .map_err(|e| format!("{}: {e}", variant_patch.display()))?;

    let mut in_hunk = false;
    let (mut ver, mut rel) = (String::new(), String::new());
    for line in text.lines() {
        if line.starts_with("+++ b/SPECS/photon-os-installer/photon-os-installer.spec") {
            in_hunk = true;
            continue;
        }
        if line.starts_with("+++ b/") {
            in_hunk = false;
            continue;
        }
        if !in_hunk {
            continue;
        }
        if let Some(v) = field(line, "+Version:") {
            if ver.is_empty() {
                ver = v;
            }
        }
        if let Some(v) = field(line, "+Release:") {
            if rel.is_empty() {
                rel = v;
            }
        }
    }

    if ver.is_empty() {
        ver = pristine_version(photon_tree).ok_or_else(|| {
            format!(
                "{} does not set Version: for the installer, and origin/5.0 could not be read \
                 from {} to supply it - refusing to guess",
                variant_patch.display(),
                photon_tree.display()
            )
        })?;
    }
    if rel.is_empty() {
        return Err(format!(
            "{} does not set Release: for the installer - the expected NEVR cannot be derived",
            variant_patch.display()
        ));
    }
    Ok(format!("photon-os-installer-{ver}-{rel}"))
}

/// `+Version:       2.9` -> `2.9`; `+Release:  3%{?dist}` -> `3`.
fn field(line: &str, key: &str) -> Option<String> {
    let rest = line.strip_prefix(key)?.trim();
    let v: String = rest
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    if v.is_empty() {
        None
    } else {
        Some(v)
    }
}

fn pristine_version(photon_tree: &Path) -> Option<String> {
    let out = Command::new("git")
        .args([
            "-C",
            photon_tree.to_str()?,
            "show",
            "origin/5.0:SPECS/photon-os-installer/photon-os-installer.spec",
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .find_map(|l| l.strip_prefix("Version:"))
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// What is actually on the media.
///
/// Reads the ISO itself rather than any file written beside it: a sidecar
/// records what a build believed it produced, and the whole point of this gate
/// is that that belief is what needs checking.
pub fn installer_on_media(iso: &Path) -> Result<String, String> {
    let out = Command::new("xorriso")
        .args(["-osirrox", "on", "-indev"])
        .arg(iso)
        .args(["-find", "/RPMS", "-name", "photon-os-installer-*.rpm"])
        .output()
        .map_err(|e| format!("running xorriso: {e}"))?;
    // xorriso writes its banner and progress to stderr and exits 0 for an
    // empty result, so the exit code says nothing; parse stdout.
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines() {
        if let Some(i) = line.find("photon-os-installer-") {
            let name: String = line[i..]
                .chars()
                .take_while(|c| !c.is_whitespace() && *c != '\'' && *c != '"')
                .collect();
            if name.ends_with(".rpm") {
                return Ok(name);
            }
        }
    }
    Err(format!(
        "no photon-os-installer RPM found under /RPMS on {}",
        iso.display()
    ))
}

pub fn gate(iso: &Path, variant_patch: &Path, photon_tree: &Path) -> Result<Gate, String> {
    let expected = expected_installer(variant_patch, photon_tree)?;
    let actual = installer_on_media(iso)?;
    let ok = actual.starts_with(&expected);
    Ok(Gate { expected, actual, ok })
}

/// Age of the ISO in seconds, refusing while it is younger than `min_age` or
/// while its size is still changing.
///
/// Finding #29: k09/k10 were started the same second a 3.9G ISO was moved into
/// the cache. vmrun exited non-zero, three vmware-vmx.exe processes stalled at
/// ~23MB and no VM powered on. Eight minutes later the identical file opened in
/// zero seconds. NTFS over drvfs is still settling; VMware cannot open the file
/// and reports it as a start failure.
///
/// This refuses rather than sleeping, so the operator sees the reason instead
/// of an unexplained pause.
pub fn settled(iso: &Path, min_age_secs: u64) -> Result<u64, String> {
    let meta = std::fs::metadata(iso).map_err(|e| format!("{}: {e}", iso.display()))?;
    let mtime = meta
        .modified()
        .map_err(|e| format!("{}: no mtime: {e}", iso.display()))?;
    let age = std::time::SystemTime::now()
        .duration_since(mtime)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if age < min_age_secs {
        return Err(format!(
            "{} was written {age}s ago; VMware cannot reliably open an ISO that is still \
             settling (finding #29). Wait {}s or pass --settle 0 if you know the file is quiet.",
            iso.display(),
            min_age_secs - age
        ));
    }
    let first = meta.len();
    std::thread::sleep(std::time::Duration::from_secs(1));
    let second = std::fs::metadata(iso).map(|m| m.len()).unwrap_or(first);
    if first != second {
        return Err(format!(
            "{} is still growing ({first} -> {second} bytes in one second) - something is \
             writing it now",
            iso.display()
        ));
    }
    Ok(age)
}
