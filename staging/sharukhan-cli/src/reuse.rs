//! A passed row's evidence, reused instead of installing the row again - only
//! when everything that decides the row's result is the same.
//!
//! The sync's fast loop installs rows (k03, c03) on ISOs the gate then serves
//! from the cache, and the gate installed them a second time on the very same
//! bytes. A row's result is decided by the medium, the row's axes, the
//! kickstart the guest is given and the harness that judges it; when all four
//! are identical, a second install measures nothing new.
//!
//! The record is written only for a row that passed, next to its checks file,
//! and carries the fingerprint of those four inputs. A later run reuses it only
//! when it was written at or after a given time (the sync run's own fast loop)
//! and the fingerprint computed NOW, from the files as they are, is equal.
//! Anything unreadable means no reuse.

use crate::config::Config;
use crate::matrix::Permutation;
use std::fs;
use std::path::{Path, PathBuf};

const PREFIX: &str = "reuse-";

/// The fingerprint of what decides `p`'s result on `iso`: the ISO's sha256,
/// the row as the matrix defines it, the kickstart evidence copy (no secret)
/// and the sha256 of the running sharukhan binary.
pub fn fingerprint(cfg: &Config, p: &Permutation, iso: &Path) -> Result<String, String> {
    let iso_sum = crate::sha256::file(iso)?;
    let ks = if p.mode == "ks" {
        crate::phases::kickstart_evidence(cfg, p)?
    } else {
        String::new()
    };
    let exe = std::env::current_exe().map_err(|e| format!("own binary: {e}"))?;
    let exe_sum = crate::sha256::file(&exe)?;
    let text = format!("iso\t{iso_sum}\nrow\t{p:?}\nkickstart\t{}\nsharukhan\t{exe_sum}\n", crate::sha256::bytes(ks.as_bytes()));
    Ok(crate::sha256::bytes(text.as_bytes()))
}

fn record_path(cfg: &Config, id: &str, stamp: &str) -> PathBuf {
    cfg.results_dir.join(id).join(format!("{PREFIX}{stamp}.json"))
}

/// Record that `p` passed on `iso`, with the checks file `checks`, at `stamp`.
pub fn record(cfg: &Config, p: &Permutation, iso: &Path, stamp: &str, checks: &Path) -> Result<PathBuf, String> {
    let fp = fingerprint(cfg, p, iso)?;
    let name = checks.file_name().and_then(|n| n.to_str()).ok_or_else(|| format!("{}: no file name", checks.display()))?;
    let v = serde_json::json!({ "stamp": stamp, "fingerprint": fp, "checks": name, "iso": iso.display().to_string() });
    let path = record_path(cfg, &p.id, stamp);
    fs::write(&path, format!("{v}\n")).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(path)
}

/// A reusable passed result of `p` on `iso`: the newest record written at or
/// after `since` (a `YYYYMMDDTHHMMSSZ` stamp) whose fingerprint equals the one
/// computed now and whose checks file is still there with no failure.
/// Returns the checks file and a sentence saying why it holds.
pub fn find(cfg: &Config, p: &Permutation, iso: &Path, since: &str) -> Option<(PathBuf, String)> {
    let dir = cfg.results_dir.join(&p.id);
    let mut recs: Vec<(String, PathBuf)> = fs::read_dir(&dir)
        .ok()?
        .flatten()
        .filter_map(|e| {
            let n = e.file_name().to_str()?.to_string();
            let stamp = n.strip_prefix(PREFIX)?.strip_suffix(".json")?.to_string();
            (valid_stamp(&stamp) && stamp.as_str() >= since).then(|| (stamp, e.path()))
        })
        .collect();
    recs.sort();
    let (stamp, path) = recs.pop()?;
    let v: serde_json::Value = serde_json::from_str(&fs::read_to_string(&path).ok()?).ok()?;
    if v["stamp"].as_str()? != stamp {
        return None;
    }
    let checks = dir.join(v["checks"].as_str()?);
    if checks.parent()? != dir || !passed(&checks)? {
        return None;
    }
    let now = fingerprint(cfg, p, iso).ok()?;
    (v["fingerprint"].as_str()? == now).then(|| {
        (
            checks.clone(),
            format!(
                "reused {} from {stamp}: the same ISO (sha256), row, kickstart and sharukhan binary, and it passed",
                checks.display()
            ),
        )
    })
}

/// Point checks-latest.jsonl and logs-latest at a reused result, so the report
/// of this run shows the evidence it relies on.
pub fn point_latest(checks: &Path) -> Result<(), String> {
    let dir = checks.parent().ok_or("checks file has no directory")?;
    let name = checks.file_name().and_then(|n| n.to_str()).ok_or("checks file has no name")?;
    let stamp = name.strip_prefix("checks-").and_then(|s| s.strip_suffix(".jsonl")).ok_or("not a checks-<stamp>.jsonl file")?;
    for (link, target) in [("checks-latest.jsonl", name.to_string()), ("logs-latest", format!("logs-{stamp}"))] {
        let l = dir.join(link);
        let _ = fs::remove_file(&l);
        std::os::unix::fs::symlink(&target, &l).map_err(|e| format!("{}: {e}", l.display()))?;
    }
    Ok(())
}

/// Every line of a checks file parses and none failed.
fn passed(checks: &Path) -> Option<bool> {
    let text = fs::read_to_string(checks).ok()?;
    let mut n = 0;
    for l in text.lines().filter(|l| !l.trim().is_empty()) {
        let v: serde_json::Value = serde_json::from_str(l).ok()?;
        if v["status"].as_str()? == "fail" {
            return Some(false);
        }
        n += 1;
    }
    Some(n > 0)
}

/// `YYYYMMDDTHHMMSSZ`, the stamp `job::stamp` writes.
pub fn valid_stamp(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 16 && b[8] == b'T' && b[15] == b'Z' && b[..8].iter().chain(&b[9..15]).all(u8::is_ascii_digit)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row() -> Permutation {
        use std::str::FromStr;
        Permutation {
            id: "k03".into(),
            iso_type: "minimal".into(),
            poi: "2.8".into(),
            stig: "yes".into(),
            fs: "ext4".into(),
            mode: "interactive".into(),
            variant: "none".into(),
            doc: "untested".into(),
            expect: "pass".into(),
            canister: "prebuilt".into(),
            net: crate::net::NetSpec::from_str("v4-dhcp-untag").unwrap(),
            firmware: "efi".into(),
        }
    }

    /// Reused only for the same medium, the same row, a record at or after
    /// the bound, and a checks file that still passes.
    #[test]
    fn a_result_is_reused_only_when_its_inputs_are_identical() {
        let d = std::env::temp_dir().join(format!("shk-reuse-e2e-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let mut cfg = Config::defaults();
        cfg.results_dir = d.join("results");
        let p = row();
        fs::create_dir_all(cfg.results_dir.join("k03")).unwrap();
        let iso = d.join("photon.iso");
        fs::write(&iso, b"medium one").unwrap();
        let checks = cfg.results_dir.join("k03/checks-20261105T080743Z.jsonl");
        fs::write(&checks, "{\"status\":\"pass\"}\n").unwrap();
        record(&cfg, &p, &iso, "20261105T080743Z", &checks).unwrap();

        let (got, why) = find(&cfg, &p, &iso, "20261105T072023Z").expect("identical inputs");
        assert_eq!(got, checks);
        assert!(why.contains("same ISO (sha256)"), "{why}");
        assert!(find(&cfg, &p, &iso, "20261105T080744Z").is_none(), "older than this run's fast loop");

        let mut other = row();
        other.fs = "btrfs".into();
        assert!(find(&cfg, &other, &iso, "20261105T072023Z").is_none(), "another row definition");

        fs::write(&iso, b"medium two").unwrap();
        assert!(find(&cfg, &p, &iso, "20261105T072023Z").is_none(), "another medium");
        fs::write(&iso, b"medium one").unwrap();

        fs::write(&checks, "{\"status\":\"fail\"}\n").unwrap();
        assert!(find(&cfg, &p, &iso, "20261105T072023Z").is_none(), "the checks no longer pass");
        fs::write(&checks, "{\"status\":\"pass\"}\n").unwrap();

        // a record that names a file outside its row is not followed
        let rec = cfg.results_dir.join("k03/reuse-20261105T080743Z.json");
        let text = fs::read_to_string(&rec).unwrap().replace("checks-20261105T080743Z.jsonl", "../k04/checks-x.jsonl");
        fs::write(&rec, text).unwrap();
        assert!(find(&cfg, &p, &iso, "20261105T072023Z").is_none());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_stamp_is_the_compact_utc_form() {
        assert!(valid_stamp("20261105T080743Z"));
        for bad in ["20261105T080743", "2026-11-05T08:07", "20261105X080743Z", "2026110aT080743Z"] {
            assert!(!valid_stamp(bad), "{bad}");
        }
    }

    #[test]
    fn a_checks_file_passes_only_without_failures_and_when_readable() {
        let d = std::env::temp_dir().join(format!("shk-reuse-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        let f = d.join("checks-20261105T080743Z.jsonl");
        fs::write(&f, "{\"status\":\"pass\"}\n{\"status\":\"info\"}\n").unwrap();
        assert_eq!(passed(&f), Some(true));
        fs::write(&f, "{\"status\":\"pass\"}\n{\"status\":\"fail\"}\n").unwrap();
        assert_eq!(passed(&f), Some(false));
        fs::write(&f, "{\"status\":\"pass\"}\nnot json\n").unwrap();
        assert_eq!(passed(&f), None, "an unreadable line means no reuse");
        fs::write(&f, "").unwrap();
        assert_eq!(passed(&f), Some(false), "an empty file proves nothing");
        fs::create_dir_all(d.join("logs-20261105T080743Z")).unwrap();
        point_latest(&f).unwrap();
        assert_eq!(fs::read_link(d.join("checks-latest.jsonl")).unwrap(), PathBuf::from("checks-20261105T080743Z.jsonl"));
        assert_eq!(fs::read_link(d.join("logs-latest")).unwrap(), PathBuf::from("logs-20261105T080743Z"));
        let _ = fs::remove_dir_all(&d);
    }
}
