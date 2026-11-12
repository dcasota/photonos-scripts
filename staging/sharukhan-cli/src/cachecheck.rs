//! Before a cached ISO is reused: are its RPMs still what the stage's
//! records say they are?
//!
//! The input record (`inputs.txt`) names the trees, patches and composer an
//! ISO was built FROM. It cannot see a build that composed the right inputs
//! from a stale stage: on 2026-11-07 the systemd 262.2 port was amended at the
//! same NEVR, the stage kept the RPM built before the amend (the ledger did not
//! cover the port's own specs then), and the cached ISOs carried it under an
//! input record that matched. Two rules close that:
//!
//! 1. An RPM on the ISO whose file the stage still holds must be that file,
//!    byte for byte. One the stage no longer holds is not judged: a later build
//!    may legitimately have replaced it (phase B of a canister build swaps the
//!    kernels at another NEVR).
//! 2. On a port build (`--systemd`), every RPM of a spec the port branch
//!    changes needs a ledger record equal to the hash of that spec directory as
//!    committed. No record means nothing proves the port's content was built.

use std::fs;
use std::path::Path;
use std::process::Command;

use crate::config::Config;

/// The cache directory's record of the ISO's RPMs: first line `iso <sha256>`,
/// then `<arch>/<file>\t<sha256>` per RPM.
pub const MANIFEST: &str = "rpms.sha256";

/// The RPMs on `iso` with their sha256, read back from the ISO itself.
fn read_iso_rpms(iso: &Path, scratch: &Path) -> Result<Vec<(String, String)>, String> {
    let tmp = scratch.join(format!(".isorpms.{}", std::process::id()));
    let _ = fs::remove_dir_all(&tmp);
    fs::create_dir_all(&tmp).map_err(|e| format!("{}: {e}", tmp.display()))?;
    let out = Command::new("xorriso")
        .args(["-osirrox", "on", "-indev"])
        .arg(iso)
        .args(["-extract", "/RPMS"])
        .arg(tmp.join("RPMS"))
        .output()
        .map_err(|e| format!("running xorriso: {e}"));
    let r = (|| {
        let out = out?;
        if !out.status.success() {
            return Err(format!("xorriso could not read /RPMS from {}: {}", iso.display(), String::from_utf8_lossy(&out.stderr).trim()));
        }
        let mut v = Vec::new();
        for f in crate::build::find_files_rec(&tmp.join("RPMS"), "", ".rpm") {
            let rel = f.strip_prefix(tmp.join("RPMS")).map_err(|e| e.to_string())?.to_string_lossy().into_owned();
            v.push((rel, crate::sha256::file(&f).map_err(|e| format!("{}: {e}", f.display()))?));
        }
        v.sort();
        if v.is_empty() {
            return Err(format!("{} carries no RPM under /RPMS", iso.display()));
        }
        Ok(v)
    })();
    let _ = fs::remove_dir_all(&tmp);
    r
}

fn parse_manifest(text: &str, iso_sha: &str) -> Option<Vec<(String, String)>> {
    let mut lines = text.lines();
    if lines.next()? != format!("iso {iso_sha}") {
        return None;
    }
    let v: Vec<(String, String)> = lines.filter_map(|l| l.split_once('\t')).map(|(a, b)| (a.to_string(), b.to_string())).collect();
    (!v.is_empty()).then_some(v)
}

/// The manifest of the cached ISO in `dir`, made from the ISO on first use.
fn manifest(dir: &Path, scratch: &Path) -> Result<Vec<(String, String)>, String> {
    let iso_sha = fs::read_to_string(dir.join("photon.iso.sha256"))
        .map_err(|e| format!("{}: {e}", dir.join("photon.iso.sha256").display()))?
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_string();
    if iso_sha.len() != 64 {
        return Err(format!("{}/photon.iso.sha256 names no sha256", dir.display()));
    }
    if let Some(v) = fs::read_to_string(dir.join(MANIFEST)).ok().and_then(|t| parse_manifest(&t, &iso_sha)) {
        return Ok(v);
    }
    let iso = fs::canonicalize(dir.join("photon.iso")).map_err(|e| format!("{}: {e}", dir.join("photon.iso").display()))?;
    let v = read_iso_rpms(&iso, scratch)?;
    let mut text = format!("iso {iso_sha}\n");
    for (f, s) in &v {
        text.push_str(&format!("{f}\t{s}\n"));
    }
    fs::write(dir.join(MANIFEST), text).map_err(|e| format!("{}: {e}", dir.join(MANIFEST).display()))?;
    Ok(v)
}

/// Rule 1: the first ISO RPM that differs from the stage's file of that name.
pub fn differs_from_stage(rpms: &[(String, String)], stage_rpms: &Path) -> Result<Option<String>, String> {
    for (rel, sha) in rpms {
        let s = stage_rpms.join(rel);
        if !s.is_file() {
            continue;
        }
        let now = crate::sha256::file(&s).map_err(|e| format!("{}: {e}", s.display()))?;
        if &now != sha {
            return Ok(Some(format!("{rel} on the ISO differs from the stage's (rebuilt at the same NEVR since)")));
        }
    }
    Ok(None)
}

fn git(dir: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").args(args).current_dir(dir).output().map_err(|e| format!("running git: {e}"))?;
    if o.status.success() {
        Ok(String::from_utf8_lossy(&o.stdout).into_owned())
    } else {
        Err(format!("git {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()))
    }
}

/// The spec directories `tip` changes against `base`, minus those `variant`
/// (a variant patch's text) also changes: their built content is the patched
/// one, which the input record's patch hash already pins.
pub fn port_spec_dirs(tree: &Path, base: &str, tip: &str, variant: &str) -> Result<Vec<String>, String> {
    let mb = git(tree, &["merge-base", base, tip])?;
    let names = git(tree, &["diff", "--name-only", mb.trim(), tip, "--", "SPECS"])?;
    let patched: Vec<String> = variant
        .lines()
        .filter_map(|l| l.strip_prefix("+++ b/").or_else(|| l.strip_prefix("--- a/")))
        .filter_map(|p| p.split_whitespace().next())
        .filter_map(|p| p.rsplit_once('/').map(|(d, _)| d.to_string()))
        .collect();
    let mut dirs: Vec<String> = names
        .lines()
        .filter_map(|p| p.trim().rsplit_once('/').map(|(d, _)| d.to_string()))
        .filter(|d| d != "SPECS" && !patched.contains(d))
        .collect();
    dirs.sort();
    dirs.dedup();
    Ok(dirs)
}

/// Rule 2 for one port spec directory, `dir` holding its committed content:
/// the first ISO RPM of a spec there whose NEVR the ledger does not record as
/// built from exactly this content.
pub fn port_rpm_unrecorded(
    dir: &Path,
    rel_dir: &str,
    sub: Option<u32>,
    rpms: &[(String, String)],
    ledger: &std::collections::BTreeMap<String, String>,
) -> Option<String> {
    let now = crate::buildexec::spec_dir_hash(dir)?;
    let mut specs: Vec<String> = fs::read_dir(dir)
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.ends_with(".spec"))
        .collect();
    specs.sort();
    for spec in specs {
        let Some(text) = crate::specresolve::resolve(&crate::specresolve::dir_reader(dir), &spec, sub) else { continue };
        let Some(fams) = crate::buildexec::spec_families_text(&text) else { continue };
        let rel = text
            .lines()
            .find(|l| l.starts_with("Release:"))
            .and_then(|l| l.split_whitespace().nth(1))
            .map(|v| v.split('%').next().unwrap_or("").to_string())
            .unwrap_or_default();
        let key = format!("{}-{}-{}", fams.name, fams.version, rel);
        let on_iso = rpms.iter().find(|(f, _)| {
            let file = f.rsplit('/').next().unwrap_or("");
            crate::buildexec::parse_rpm_name(file).is_some_and(|(p, v, r)| fams.families.contains(&p) && v == fams.version && r.split(".ph").next() == Some(rel.as_str()))
        });
        let Some((f, _)) = on_iso else { continue };
        match ledger.get(&key) {
            Some(h) if *h == now => {}
            Some(_) => return Some(format!("{f} on the ISO: the stage's ledger records {key} as built from other content than {rel_dir} has now")),
            None => return Some(format!("{f} on the ISO: the stage's ledger has no record that {key} was built from {rel_dir} as committed")),
        }
    }
    None
}

/// Both rules for the cached ISO in `dir`. None: it may be reused.
pub fn cached_rpms_differ(cfg: &Config, variant_patch: &Path, dir: &Path) -> Option<String> {
    let rpms = match manifest(dir, &cfg.work) {
        Ok(v) => v,
        Err(e) => return Some(format!("its RPMs cannot be read back ({e})")),
    };
    let stage = cfg.photon_tree.join("stage");
    match differs_from_stage(&rpms, &stage.join("RPMS")) {
        Ok(Some(why)) => return Some(why),
        Ok(None) => {}
        Err(e) => return Some(format!("the stage cannot be compared ({e})")),
    }
    let Some(s) = &cfg.systemd else { return None };
    let variant = fs::read_to_string(variant_patch).unwrap_or_default();
    let tip = format!("origin/{}", cfg.release);
    let dirs = match port_spec_dirs(&cfg.photon_tree, &format!("origin/{}", s.base_release), &tip, &variant) {
        Ok(d) => d,
        Err(e) => return Some(format!("the port's own specs cannot be listed ({e})")),
    };
    let ledger = crate::buildexec::parse_ledger(&fs::read_to_string(stage.join(crate::buildexec::BUILT_FROM_LEDGER)).unwrap_or_default());
    let sub = crate::specresolve::tree_subrelease(&cfg.photon_tree);
    for d in dirs {
        let tmp = cfg.work.join(format!(".portspec.{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        if let Err(e) = fs::create_dir_all(&tmp) {
            return Some(format!("{}: {e}", tmp.display()));
        }
        let r = (|| -> Result<Option<String>, String> {
            let ar = Command::new("git")
                .args(["archive", "--format=tar", &tip, "--", &d])
                .current_dir(&cfg.photon_tree)
                .output()
                .map_err(|e| format!("running git archive: {e}"))?;
            if !ar.status.success() {
                return Err(format!("git archive {tip} {d}: {}", String::from_utf8_lossy(&ar.stderr).trim()));
            }
            let mut tar = Command::new("tar")
                .args(["-x", "-C"])
                .arg(&tmp)
                .stdin(std::process::Stdio::piped())
                .spawn()
                .map_err(|e| format!("running tar: {e}"))?;
            {
                use std::io::Write;
                tar.stdin.take().ok_or("tar has no stdin")?.write_all(&ar.stdout).map_err(|e| e.to_string())?;
            }
            if !tar.wait().map_err(|e| e.to_string())?.success() {
                return Err(format!("extracting {d} from {tip} failed"));
            }
            Ok(port_rpm_unrecorded(&tmp.join(&d), &d, sub, &rpms, &ledger))
        })();
        let _ = fs::remove_dir_all(&tmp);
        match r {
            Ok(Some(why)) => return Some(why),
            Ok(None) => {}
            Err(e) => return Some(format!("the port's content of {d} cannot be read ({e})")),
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_manifest_belongs_to_one_iso() {
        let t = "iso aaa\nx86_64/a-1-1.ph5.x86_64.rpm\th1\n";
        assert_eq!(parse_manifest(t, "aaa").unwrap(), vec![("x86_64/a-1-1.ph5.x86_64.rpm".to_string(), "h1".to_string())]);
        assert!(parse_manifest(t, "bbb").is_none(), "another ISO's manifest is never reused");
    }

    #[test]
    fn an_iso_rpm_must_be_the_stages_file_where_the_stage_still_has_it() {
        let d = crate::safepath::test_base().join(format!("shk-cachechk-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("x86_64")).unwrap();
        fs::write(d.join("x86_64/systemd-262.2-1.ph5.x86_64.rpm"), "new").unwrap();
        let old = crate::sha256::bytes(b"old");
        let new = crate::sha256::bytes(b"new");
        let rpms = |s: &str| vec![("x86_64/systemd-262.2-1.ph5.x86_64.rpm".to_string(), s.to_string()), ("x86_64/linux-6.12.115-2.ph5.x86_64.rpm".to_string(), "k".to_string())];
        assert!(differs_from_stage(&rpms(&old), &d).unwrap().unwrap().contains("systemd-262.2-1"));
        assert_eq!(differs_from_stage(&rpms(&new), &d).unwrap(), None, "a kernel the stage replaced is not judged");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_port_rpm_needs_a_record_of_the_committed_content() {
        let d = crate::safepath::test_base().join(format!("shk-portrec-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("SPECS/systemd")).unwrap();
        fs::write(d.join("build-config.json"), r#"{"photon-build-param": {"photon-subrelease": "92"}}"#).unwrap();
        let dir = d.join("SPECS/systemd");
        fs::write(dir.join("systemd.spec"), "Name: systemd\nVersion: 262.2\nRelease: 1%{?dist}\n%package udev\nSummary: u\n%description udev\nu\n").unwrap();
        let rpms = vec![("x86_64/systemd-udev-262.2-1.ph5.x86_64.rpm".to_string(), "h".to_string())];
        let mut ledger = std::collections::BTreeMap::new();
        assert!(port_rpm_unrecorded(&dir, "SPECS/systemd", Some(92), &rpms, &ledger).unwrap().contains("no record"));
        ledger.insert("systemd-262.2-1".to_string(), "other".to_string());
        assert!(port_rpm_unrecorded(&dir, "SPECS/systemd", Some(92), &rpms, &ledger).unwrap().contains("other content"));
        ledger.insert("systemd-262.2-1".to_string(), crate::buildexec::spec_dir_hash(&dir).unwrap());
        assert_eq!(port_rpm_unrecorded(&dir, "SPECS/systemd", Some(92), &rpms, &ledger), None);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_spec_the_variant_patch_changes_is_not_a_port_spec_here() {
        let d = crate::safepath::test_base().join(format!("shk-portdirs-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("SPECS/systemd")).unwrap();
        fs::create_dir_all(d.join("SPECS/rsyslog")).unwrap();
        let g = |a: &[&str]| assert!(Command::new("git").args(["-c", "user.name=t", "-c", "user.email=t@t"]).args(a).current_dir(&d).status().unwrap().success());
        g(&["init", "-q", "-b", "5.0"]);
        fs::write(d.join("SPECS/systemd/systemd.spec"), "a\n").unwrap();
        fs::write(d.join("SPECS/rsyslog/rsyslog.spec"), "a\n").unwrap();
        g(&["add", "-A"]);
        g(&["commit", "-qm", "b"]);
        g(&["checkout", "-qb", "port"]);
        fs::write(d.join("SPECS/systemd/systemd.spec"), "b\n").unwrap();
        fs::write(d.join("SPECS/rsyslog/rsyslog.spec"), "b\n").unwrap();
        g(&["commit", "-qam", "p"]);
        let variant = "--- a/SPECS/rsyslog/rsyslog.spec\n+++ b/SPECS/rsyslog/rsyslog.spec\n";
        assert_eq!(port_spec_dirs(&d, "5.0", "port", variant).unwrap(), vec!["SPECS/systemd".to_string()]);
        let _ = fs::remove_dir_all(&d);
    }
}
