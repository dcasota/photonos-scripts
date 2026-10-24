//! The subreleases a release tree distinguishes, read from the tree.
//!
//! A check that covers "90, 91, 92 and 93" because a list says so stops
//! covering the tree the day upstream adds `SPECS/94` or a spec conditioned on
//! `%{photon_subrelease} >= 94`. The set is therefore derived:
//!
//! * `photon-subrelease` and `photon-mainline` of `build-config.json`,
//! * every `SPECS/<n>` directory,
//! * every number a spec compares `photon_subrelease` with.
//!
//! The spec checker's mainline is the highest of these: it caps its sweep at
//! the mainline, and a subrelease a spec already builds for (93 while the
//! config still says 92) must be swept too.

use std::collections::BTreeSet;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, PartialEq)]
pub struct Subreleases {
    pub all: Vec<u32>,
    /// What `check_spec.py --mainline` gets: the highest subrelease.
    pub check_mainline: u32,
}

/// Numbers compared with `photon_subrelease` in spec text: `%{photon_subrelease} >= 93`,
/// `0%{?photon_subrelease} == 91`.
fn compared(text: &str) -> BTreeSet<u32> {
    let mut out = BTreeSet::new();
    let mut rest = text;
    while let Some(i) = rest.find("photon_subrelease") {
        rest = &rest[i + "photon_subrelease".len()..];
        let after = rest.trim_start_matches(['}', ' ', '\t']);
        let op_len = ["==", ">=", "<=", "!=", ">", "<"].iter().find(|o| after.starts_with(**o)).map(|o| o.len());
        if let Some(l) = op_len {
            let num: String = after[l..].trim_start().chars().take_while(char::is_ascii_digit).collect();
            if let Ok(n) = num.parse() {
                out.insert(n);
            }
        }
    }
    out
}

/// The set from the three sources; refuses a tree that names none, and a
/// number far from the configured subrelease (a typo, not a subrelease).
pub fn derive(build_config: &str, spec_text: &str, dirs: &[String]) -> Result<Subreleases, String> {
    let cfg: serde_json::Value = serde_json::from_str(build_config).map_err(|e| format!("build-config.json: {e}"))?;
    let param = |k: &str| -> Option<u32> { cfg.get("photon-build-param")?.get(k)?.as_str()?.trim().parse().ok() };
    let sub = param("photon-subrelease").ok_or("build-config.json has no numeric photon-subrelease")?;
    let mut all: BTreeSet<u32> = BTreeSet::from([sub]);
    if let Some(m) = param("photon-mainline") {
        all.insert(m);
    }
    all.extend(dirs.iter().filter_map(|d| d.parse::<u32>().ok()));
    all.extend(compared(spec_text));
    if let Some(odd) = all.iter().find(|n| n.abs_diff(sub) > 30) {
        return Err(format!("subrelease {odd} is implausibly far from photon-subrelease {sub}"));
    }
    let all: Vec<u32> = all.into_iter().collect();
    let check_mainline = *all.last().ok_or("no subrelease")?;
    Ok(Subreleases { all, check_mainline })
}

fn run(dir: &Path, prog: &str, args: &[&str]) -> Result<String, String> {
    let o = Command::new(prog).arg("-C").arg(dir).args(args).output().map_err(|e| format!("{prog}: {e}"))?;
    // git grep exits 1 when nothing matches: no conditions is a valid answer
    if !o.status.success() && !(prog == "git" && args.first() == Some(&"grep") && o.status.code() == Some(1)) {
        return Err(format!("{prog} {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).to_string())
}

/// From a revision of a release repository.
pub fn at_rev(repo: &Path, rev: &str) -> Result<Subreleases, String> {
    let bc = run(repo, "git", &["show", &format!("{rev}:build-config.json")])?;
    let specs = run(repo, "git", &["grep", "-h", "-o", "-E", "photon_subrelease[}[:space:]]*(==|>=|<=|!=|>|<)[[:space:]]*[0-9]+", rev, "--", "SPECS"])?;
    let dirs: Vec<String> = run(repo, "git", &["ls-tree", "--name-only", rev, "SPECS/"])?
        .lines()
        .filter_map(|l| l.strip_prefix("SPECS/").map(str::to_string))
        .collect();
    derive(&bc, &specs, &dirs)
}

/// From a checked-out release tree.
pub fn in_dir(root: &Path) -> Result<Subreleases, String> {
    let bc = std::fs::read_to_string(root.join("build-config.json")).map_err(|e| format!("{}/build-config.json: {e}", root.display()))?;
    let mut text = String::new();
    let mut dirs = Vec::new();
    let specs = root.join("SPECS");
    for e in std::fs::read_dir(&specs).map_err(|e| format!("{}: {e}", specs.display()))?.flatten() {
        dirs.push(e.file_name().to_string_lossy().to_string());
    }
    let mut stack = vec![specs];
    while let Some(d) = stack.pop() {
        for e in std::fs::read_dir(&d).map_err(|e| format!("{}: {e}", d.display()))?.flatten() {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
            } else if p.extension().is_some_and(|x| x == "spec" || x == "inc") {
                if let Ok(t) = std::fs::read_to_string(&p) {
                    for l in t.lines().filter(|l| l.contains("photon_subrelease")) {
                        text.push_str(l);
                        text.push('\n');
                    }
                }
            }
        }
    }
    derive(&bc, &text, &dirs)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BC: &str = r#"{"photon-build-param": {"photon-subrelease": "92", "photon-mainline": "92"}}"#;

    #[test]
    fn the_set_is_config_dirs_and_spec_conditions() {
        let specs = "%global build_if %{photon_subrelease} >= 93\n%if 0%{?photon_subrelease} == 91\n%if %{photon_subrelease} <= 90\n";
        let s = derive(BC, specs, &["90".into(), "91".into(), "92".into(), "linux".into()]).unwrap();
        assert_eq!(s.all, vec![90, 91, 92, 93]);
        assert_eq!(s.check_mainline, 93);
    }

    #[test]
    fn a_new_subrelease_in_a_spec_joins_the_set() {
        let s = derive(BC, "%global build_if %{photon_subrelease} >= 94\n", &[]).unwrap();
        assert_eq!(s.all, vec![92, 94]);
        assert_eq!(s.check_mainline, 94);
    }

    #[test]
    fn a_broken_config_or_an_implausible_number_is_refused() {
        assert!(derive("{}", "", &[]).is_err());
        assert!(derive("not json", "", &[]).is_err());
        assert!(derive(BC, "%if %{photon_subrelease} == 920\n", &[]).unwrap_err().contains("implausibly"));
    }

    #[test]
    fn comparisons_are_read_in_every_spelling() {
        assert_eq!(compared("%{photon_subrelease}>=91 0%{?photon_subrelease} != 90 photon_subrelease < 89"), BTreeSet::from([89, 90, 91]));
        assert!(compared("%define photon_subrelease 92").is_empty());
    }
}
