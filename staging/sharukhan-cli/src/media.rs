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

    // Release may legitimately be absent from the diff: `latest` bumps Version
    // to 2.9 and keeps Release 2, and once upstream's 2.8 also sat at Release 2
    // the line was identical on both sides and dropped out of the patch
    // (2026-09-26, both latest groups refused although the media carried
    // 2.9-2). Taking it from pristine is sound only when this patch bumps
    // Version: the NEVR is then distinct from upstream's own installer. A patch
    // that sets neither would let upstream's installer pass the gate.
    if rel.is_empty() && !ver.is_empty() {
        rel = pristine_field(photon_tree, "Release:").ok_or_else(|| {
            format!(
                "{} bumps the installer Version: but keeps its Release:, and origin/5.0 could \
                 not be read from {} to supply it - refusing to guess",
                variant_patch.display(),
                photon_tree.display()
            )
        })?;
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
    pristine_field(photon_tree, "Version:")
}

/// A preamble field of the pristine installer spec, reduced as [`field`] does.
fn pristine_field(photon_tree: &Path, key: &str) -> Option<String> {
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
        .find_map(|l| field(&format!("+{l}"), &format!("+{key}")))
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

/// `release_bump`: Release increments applied after the variant patch - a
/// kernel profile's pins append installer patches, each bumping Release once.
pub fn gate(iso: &Path, variant_patch: &Path, photon_tree: &Path, release_bump: u32) -> Result<Gate, String> {
    let expected = bump_release(&expected_installer(variant_patch, photon_tree)?, release_bump)?;
    let actual = installer_on_media(iso)?;
    let ok = actual.starts_with(&expected);
    Ok(Gate {
        expected,
        actual,
        ok,
    })
}

/// `photon-os-installer-2.9-2` + 2 -> `photon-os-installer-2.9-4`.
pub fn bump_release(nevr: &str, by: u32) -> Result<String, String> {
    if by == 0 {
        return Ok(nevr.to_string());
    }
    let (head, rel) = nevr
        .rsplit_once('-')
        .ok_or_else(|| format!("'{nevr}' has no Release to bump"))?;
    let n: u32 = rel
        .parse()
        .map_err(|_| format!("'{nevr}': Release '{rel}' is not a number"))?;
    Ok(format!("{head}-{}", n + by))
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
/// The finding's own mitigation is a settle delay, so a caller may wait out
/// `Unsettled::Young` - announcing the measured age and the remaining seconds,
/// never pausing silently. `Growing` and `Unreadable` are not waited on:
/// something is writing the file, or it cannot be read at all.
pub fn settled(iso: &Path, min_age_secs: u64) -> Result<u64, Unsettled> {
    let meta = std::fs::metadata(iso)
        .map_err(|e| Unsettled::Unreadable(format!("{}: {e}", iso.display())))?;
    let mtime = meta
        .modified()
        .map_err(|e| Unsettled::Unreadable(format!("{}: no mtime: {e}", iso.display())))?;
    let age = std::time::SystemTime::now()
        .duration_since(mtime)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if let Some(remaining) = remaining_settle(age, min_age_secs) {
        return Err(Unsettled::Young {
            path: iso.display().to_string(),
            age,
            remaining,
        });
    }
    let first = meta.len();
    std::thread::sleep(std::time::Duration::from_secs(1));
    let second = std::fs::metadata(iso).map(|m| m.len()).unwrap_or(first);
    if first != second {
        return Err(Unsettled::Growing {
            path: iso.display().to_string(),
            from: first,
            to: second,
        });
    }
    Ok(age)
}

/// Why an ISO is not yet safe to hand to VMware (finding #29).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Unsettled {
    /// Written less than the minimum age ago; `remaining` seconds to go.
    Young {
        path: String,
        age: u64,
        remaining: u64,
    },
    /// Its size changed across a one-second sample: something is writing it.
    Growing { path: String, from: u64, to: u64 },
    /// Its metadata could not be read.
    Unreadable(String),
}

impl std::fmt::Display for Unsettled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Unsettled::Young { path, age, remaining } => write!(
                f,
                "{path} was written {age}s ago; VMware cannot reliably open an ISO that is still \
                 settling (finding #29). Wait {remaining}s or pass --settle 0 if you know the file is quiet."
            ),
            Unsettled::Growing { path, from, to } => write!(
                f,
                "{path} is still growing ({from} -> {to} bytes in one second) - something is \
                 writing it now"
            ),
            Unsettled::Unreadable(why) => write!(f, "{why}"),
        }
    }
}

/// Seconds still to wait before an ISO of `age` reaches `min_age`, or `None`
/// once it has.
pub fn remaining_settle(age: u64, min_age: u64) -> Option<u64> {
    (age < min_age).then(|| min_age - age)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A git tree whose origin/5.0 carries an installer spec at `ver`-`rel`.
    fn pristine_tree(tag: &str, ver: &str, rel: &str) -> std::path::PathBuf {
        let t = std::env::temp_dir().join(format!("sharukhan-media-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&t);
        let d = t.join("SPECS/photon-os-installer");
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(
            d.join("photon-os-installer.spec"),
            format!("Name: photon-os-installer\nVersion:       {ver}\nRelease:       {rel}%{{?dist}}\n"),
        )
        .unwrap();
        let g = |a: &[&str]| {
            assert!(Command::new("git").arg("-C").arg(&t).args(a).status().unwrap().success());
        };
        g(&["init", "-q"]);
        g(&["add", "-A"]);
        g(&["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]);
        g(&["update-ref", "refs/remotes/origin/5.0", "HEAD"]);
        t
    }

    fn installer_patch(dir: &std::path::Path, body: &str) -> std::path::PathBuf {
        let p = dir.join("variant.patch");
        std::fs::write(
            &p,
            format!(
                "diff --git a/SPECS/photon-os-installer/photon-os-installer.spec b/SPECS/photon-os-installer/photon-os-installer.spec\n\
                 --- a/SPECS/photon-os-installer/photon-os-installer.spec\n\
                 +++ b/SPECS/photon-os-installer/photon-os-installer.spec\n{body}\
                 diff --git a/SPECS/other/other.spec b/SPECS/other/other.spec\n\
                 +++ b/SPECS/other/other.spec\n+Release:       9%{{?dist}}\n"
            ),
        )
        .unwrap();
        p
    }

    /// 2026-09-26: latest bumped Version to 2.9 and kept Release 2, upstream
    /// 2.8 sat at Release 2 too, the Release line dropped out of the diff and
    /// both latest groups were refused while their media carried 2.9-2.
    #[test]
    fn a_version_bump_takes_an_unchanged_release_from_pristine() {
        let t = pristine_tree("verbump", "2.8", "2");
        let p = installer_patch(&t, "-Version:       2.8\n+Version:       2.9\n");
        assert_eq!(expected_installer(&p, &t).unwrap(), "photon-os-installer-2.9-2");
        assert_eq!(bump_release("photon-os-installer-2.9-2", 2).unwrap(), "photon-os-installer-2.9-4");
        assert_eq!(bump_release("photon-os-installer-2.9-2", 0).unwrap(), "photon-os-installer-2.9-2");
        assert!(bump_release("photon-os-installer-2.9-x", 1).is_err());
        let _ = std::fs::remove_dir_all(&t);
    }

    /// Negative control: a patch that sets neither field would let upstream's
    /// own installer pass the gate, so it is still refused - and another
    /// spec's +Release: further down is not mistaken for the installer's.
    #[test]
    fn a_patch_that_sets_neither_field_is_still_refused() {
        let t = pristine_tree("neither", "2.8", "2");
        let p = installer_patch(&t, " Summary: unchanged\n");
        assert!(expected_installer(&p, &t).unwrap_err().contains("does not set Release"));
        let _ = std::fs::remove_dir_all(&t);
    }

    #[test]
    fn a_release_bump_takes_version_from_pristine_as_before() {
        let t = pristine_tree("relbump", "2.8", "2");
        let p = installer_patch(&t, "-Release:       2%{?dist}\n+Release:       4%{?dist}\n");
        assert_eq!(expected_installer(&p, &t).unwrap(), "photon-os-installer-2.8-4");
        let _ = std::fs::remove_dir_all(&t);
    }

    #[test]
    fn a_young_iso_reports_exactly_the_seconds_left() {
        assert_eq!(remaining_settle(10, 300), Some(290));
        assert_eq!(remaining_settle(0, 320), Some(320));
    }

    #[test]
    fn an_iso_at_or_past_the_minimum_age_needs_no_wait() {
        // negative control: without it a gate that always waits passes the test above
        assert_eq!(remaining_settle(300, 300), None);
        assert_eq!(remaining_settle(4000, 300), None);
        assert_eq!(remaining_settle(5, 0), None);
    }

    #[test]
    fn a_freshly_written_file_is_young_and_says_why() {
        let d = std::env::temp_dir().join(format!("sk-media-young-{}", std::process::id()));
        std::fs::write(&d, b"iso").unwrap();
        let got = settled(&d, 300);
        let _ = std::fs::remove_file(&d);
        match got {
            Err(Unsettled::Young { age, remaining, .. }) => {
                assert!(age < 60, "age {age}");
                assert_eq!(age + remaining, 300);
            }
            other => panic!("expected Young, got {other:?}"),
        }
    }

    #[test]
    fn the_young_message_keeps_its_wording() {
        let m = Unsettled::Young {
            path: "/x/photon.iso".into(),
            age: 48,
            remaining: 272,
        }
        .to_string();
        assert_eq!(
            m,
            "/x/photon.iso was written 48s ago; VMware cannot reliably open an ISO that is still \
             settling (finding #29). Wait 272s or pass --settle 0 if you know the file is quiet."
        );
    }

    #[test]
    fn a_missing_iso_is_unreadable_not_young() {
        let got = settled(Path::new("/nonexistent/sharukhan/photon.iso"), 300);
        assert!(matches!(got, Err(Unsettled::Unreadable(_))), "{got:?}");
    }
}
