//! The installer variants and the `common` branches, read from data.
//!
//! Which PR branches make up a variant is project state, not code: it changes
//! whenever a PR opens, merges or is stacked anew, and the reasons a branch is
//! in a variant (a range rule, an alternative) belong next to it. They live in
//! `config/variants.conf` (SHARUKHAN_VARIANTS):
//!
//! ```text
//! # comment
//! [variant 2.8]
//! fix/some-branch      # why it is here
//! [common]
//! fix/a-common-branch
//! [excluded]
//! fix/an-alternative   # the reason is required
//! ```
//!
//! The first `[variant ...]` section is the default variant: what `--poi`
//! means when it is not given, and what the fast loop builds.
//!
//! A missing or malformed file is an error, never an empty list: a variant
//! patch built from nothing would prove nothing. `check` compares the file
//! with the fork's open PRs, so a branch that merged or closed is reported
//! instead of silently fetched from a stale ref.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, PartialEq)]
pub struct Variant {
    pub name: String,
    pub branches: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Variants {
    pub variants: Vec<Variant>,
    pub common: Vec<String>,
    /// Open PRs deliberately in no variant, each with its reason (the
    /// comment on its line is required).
    pub excluded: Vec<(String, String)>,
}

/// The installer branch of a variant: `fix/poi-*` or
/// `upstream/photon-os-installer-*`; nothing else in a variant names "poi".
pub fn installer_branch(v: &Variant) -> Option<&str> {
    v.branches.iter().find(|b| is_installer(b)).map(String::as_str)
}

fn is_installer(b: &str) -> bool {
    b.contains("/poi-") || b.contains("photon-os-installer")
}

/// A branch name git accepts as a ref component, without the forms that
/// would change what a range or a refspec means.
fn valid_branch(b: &str) -> bool {
    !b.is_empty()
        && b.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '/' | '-'))
        && !b.contains("..")
        && !b.starts_with(['/', '-', '.'])
        && !b.ends_with(['/', '.'])
        && !b.ends_with(".lock")
}

pub fn parse(text: &str) -> Result<Variants, String> {
    enum Sec {
        None,
        Variant(usize),
        Common,
        Excluded,
    }
    let mut out = Variants { variants: Vec::new(), common: Vec::new(), excluded: Vec::new() };
    let mut sec = Sec::None;
    let mut seen_common = false;
    for (i, raw) in text.lines().enumerate() {
        let n = i + 1;
        let line = match raw.find('#') {
            Some(p) => &raw[..p],
            None => raw,
        }
        .trim();
        if line.is_empty() {
            continue;
        }
        if let Some(h) = line.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
            let h = h.trim();
            if h == "excluded" {
                sec = Sec::Excluded;
            } else if h == "common" {
                if seen_common {
                    return Err(format!("line {n}: a second [common] section"));
                }
                seen_common = true;
                sec = Sec::Common;
            } else if let Some(name) = h.strip_prefix("variant ").map(str::trim) {
                if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-')) {
                    return Err(format!("line {n}: variant name '{name}' is not a plain name"));
                }
                if out.variants.iter().any(|v| v.name == name) {
                    return Err(format!("line {n}: variant {name} defined twice"));
                }
                out.variants.push(Variant { name: name.to_string(), branches: Vec::new() });
                sec = Sec::Variant(out.variants.len() - 1);
            } else {
                return Err(format!("line {n}: unknown section [{h}]"));
            }
            continue;
        }
        if line.split_whitespace().count() != 1 || !valid_branch(line) {
            return Err(format!("line {n}: '{line}' is not one branch name"));
        }
        let list = match sec {
            Sec::None => return Err(format!("line {n}: branch {line} outside a section")),
            Sec::Variant(k) => &mut out.variants[k].branches,
            Sec::Common => &mut out.common,
            Sec::Excluded => {
                let why = raw.find('#').map(|p| raw[p + 1..].trim()).unwrap_or("");
                if why.is_empty() {
                    return Err(format!("line {n}: excluded {line} needs its reason as a comment"));
                }
                if out.excluded.iter().any(|(b, _)| b == line) {
                    return Err(format!("line {n}: {line} excluded twice"));
                }
                out.excluded.push((line.to_string(), why.to_string()));
                continue;
            }
        };
        if list.iter().any(|b| b == line) {
            return Err(format!("line {n}: {line} listed twice in the same section"));
        }
        list.push(line.to_string());
    }
    if out.variants.is_empty() {
        return Err("no [variant ...] section".into());
    }
    if !seen_common {
        return Err("no [common] section (it may be empty, but it must be there)".into());
    }
    for v in &out.variants {
        let hits = v.branches.iter().filter(|b| is_installer(b)).count();
        if hits != 1 {
            return Err(format!("variant {} carries {hits} installer branches; exactly one is required", v.name));
        }
    }
    Ok(out)
}

pub fn load(path: &Path) -> Result<Variants, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e} (SHARUKHAN_VARIANTS)", path.display()))?;
    parse(&text).map_err(|e| format!("{}: {e}", path.display()))
}

impl Variants {
    /// The default variant: the first section of the file.
    pub fn default_variant(&self) -> &Variant {
        &self.variants[0]
    }

    /// Every branch of every variant, in first-seen order, without repeats.
    pub fn all_variant_branches(&self) -> Vec<&str> {
        let mut out: Vec<&str> = Vec::new();
        for v in &self.variants {
            for b in &v.branches {
                if !out.contains(&b.as_str()) {
                    out.push(b);
                }
            }
        }
        out
    }
}

/// What the file says against what the fork has open: branches no open PR
/// heads (merged, closed or renamed), and open PRs on the release or common
/// line that no section lists.
pub struct Drift {
    pub not_open: Vec<String>,
    pub unlisted: Vec<(u64, String, String)>,
}

/// A PR is covered when a section lists it, when a listed branch is stacked
/// on it (the range rule: the child is listed and carries its parent's
/// commits), or when it is excluded with a reason.
pub fn drift(v: &Variants, open: &[(u64, String, String)], release: &str, common: &str) -> Drift {
    let listed: BTreeSet<&str> = v.all_variant_branches().into_iter().chain(v.common.iter().map(String::as_str)).collect();
    let excluded: BTreeSet<&str> = v.excluded.iter().map(|(b, _)| b.as_str()).collect();
    let heads: BTreeSet<&str> = open.iter().map(|(_, h, _)| h.as_str()).collect();
    let base_of = |h: &str| open.iter().find(|(_, x, _)| x == h).map(|(_, _, b)| b.as_str());
    let mut covered: BTreeSet<&str> = BTreeSet::new();
    for b in &listed {
        let mut cur = *b;
        for _ in 0..30 {
            covered.insert(cur);
            match base_of(cur) {
                Some(p) if heads.contains(p) => cur = p,
                _ => break,
            }
        }
    }
    // the root an open PR stacks down to: only the release and common lines count
    let root_of = |h: &str| {
        let mut cur = h;
        for _ in 0..30 {
            match base_of(cur) {
                Some(p) if heads.contains(p) => cur = p,
                Some(p) => return p.to_string(),
                None => break,
            }
        }
        String::new()
    };
    Drift {
        not_open: listed.iter().chain(excluded.iter()).filter(|b| !heads.contains(**b)).map(|b| b.to_string()).collect(),
        unlisted: open
            .iter()
            .filter(|(_, h, _)| !covered.contains(h.as_str()) && !excluded.contains(h.as_str()))
            .filter(|(_, h, _)| {
                let r = root_of(h);
                r == release || r == common
            })
            .cloned()
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OK: &str = "# head\n[variant 2.8]\nfix/poi-a  # installer\nfix/b\n\n[variant latest]\nfix/poi-c\nfix/b\n[common]\nfix/common-x\n";

    #[test]
    fn a_well_formed_file_parses_with_comments() {
        let v = parse(OK).unwrap();
        assert_eq!(v.variants.len(), 2);
        assert_eq!(v.variants[0].branches, vec!["fix/poi-a", "fix/b"]);
        assert_eq!(installer_branch(&v.variants[1]), Some("fix/poi-c"));
        assert_eq!(v.common, vec!["fix/common-x"]);
        assert_eq!(v.all_variant_branches(), vec!["fix/poi-a", "fix/b", "fix/poi-c"]);
    }

    #[test]
    fn malformed_files_are_refused() {
        for (bad, why) in [
            ("[variant 2.8]\nfix/poi-a\n", "no [common]"),
            ("[common]\n", "no [variant"),
            ("fix/x\n[variant a]\nfix/poi-a\n[common]\n", "outside a section"),
            ("[variant a]\nfix/poi-a\nfix/poi-b\n[common]\n", "2 installer branches"),
            ("[variant a]\nfix/b\n[common]\n", "0 installer branches"),
            ("[variant a]\nfix/poi-a\nfix/poi-a\n[common]\n", "listed twice"),
            ("[variant a]\nfix/poi-a\n[variant a]\nfix/poi-b\n[common]\n", "defined twice"),
            ("[variant a]\nfix/poi-a two\n[common]\n", "not one branch"),
            ("[variant a]\nfix/poi-a\norigin/5.0..x\n[common]\n", "not one branch"),
            ("[variant a]\nfix/poi-a\n[extra]\n[common]\n", "unknown section"),
            ("[variant a]\nfix/poi-a\n[common]\n[excluded]\nfix/x\n", "needs its reason"),
        ] {
            let e = parse(bad).unwrap_err();
            assert!(e.contains(why), "{bad:?}: {e}");
        }
    }

    #[test]
    fn drift_names_stale_and_unlisted_branches() {
        let v = parse(OK).unwrap();
        let open = vec![
            (1, "fix/poi-a".to_string(), "5.0".to_string()),
            (2, "fix/b".to_string(), "5.0".to_string()),
            (3, "fix/poi-c".to_string(), "5.0".to_string()),
            (4, "fix/new".to_string(), "5.0".to_string()),
            (5, "fix/stacked".to_string(), "fix/b".to_string()),
        ];
        let d = drift(&v, &open, "5.0", "common");
        assert_eq!(d.not_open, vec!["fix/common-x"]);
        assert_eq!(d.unlisted.iter().map(|x| x.0).collect::<Vec<_>>(), vec![4, 5]);
        // a listed child covers its parent; an excluded PR needs no section
        let with = format!("{OK}fix/stacked\n[excluded]\nfix/new  # an alternative of fix/b\n").replace("[common]\nfix/common-x\nfix/stacked", "[common]\nfix/common-x");
        let mut v2 = parse(&with).unwrap();
        v2.variants[0].branches.push("fix/stacked".into());
        let open2: Vec<_> = open.iter().cloned().map(|(n, h, b)| if n == 2 { (n, h, "fix/poi-a".to_string()) } else { (n, h, b) }).collect();
        let d2 = drift(&v2, &open2, "5.0", "common");
        assert!(d2.unlisted.is_empty(), "{:?}", d2.unlisted);
    }

    /// The shipped file must parse: a broken edit fails here, not two hours
    /// into a build.
    #[test]
    fn the_shipped_file_parses() {
        let p = Path::new(env!("CARGO_MANIFEST_DIR")).join("../mission-control/config/variants.conf");
        let v = load(&p).unwrap();
        assert!(v.variants.iter().any(|x| x.name == "2.8"));
    }
}
