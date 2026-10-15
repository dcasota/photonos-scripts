//! A build pinned to a subrelease must not see the stage RPMs that only another
//! subrelease builds.
//!
//! The release tree carries one spec per subrelease line for many packages
//! (SPECS/gcc builds 12.5.0 from 92 on, SPECS/91/gcc builds 12.2.0 at 91), and
//! every build of that tree fills the same stage/RPMS. The sandbox installs a
//! BuildRequires by name and takes the newest candidate, so a subrelease 91
//! build of linux resolved `gcc >= 12.2.0-6` to the mainline gcc-12.5.0 and
//! failed its config check on the compiler version: a spec that is correct
//! looked broken, purely because of what an earlier build left in the stage.
//!
//! So before make, every stage RPM is moved to `stage/subrelease-aside` when
//!   - no spec the pinned subrelease builds produces that package at all, but a
//!     spec of another subrelease does, or
//!   - a spec the pinned subrelease builds produces it at a LOWER version-release
//!     (the stage copy would shadow it).
//! Moved, never deleted, and moved back after the build: those RPMs are the
//! mainline build's output and cost hours to reproduce.
//!
//! A package no spec in the tree produces is left alone (nothing says which
//! subrelease it belongs to), and so is one whose spec cannot be decided
//! (an arch-only build_if, or a Release that needs rpm to expand).

use crate::buildexec::{parse_rpm_name, spec_families_text, vercmp};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

pub const ASIDE: &str = "subrelease-aside";
const MANIFEST: &str = "manifest.tsv";

/// Does a spec build at subrelease `sub`? Decided from its `build_if` line:
/// Some(true/false) when it is a conjunction of photon_subrelease comparisons,
/// None when it depends on something else (the arch), Err when it is a form
/// this does not know - never a guess. No build_if: every subrelease builds it.
pub fn build_if(spec_text: &str, sub: u32) -> Result<Option<bool>, String> {
    for l in spec_text.lines() {
        let t: Vec<&str> = l.split_whitespace().collect();
        if t.len() < 3 || !(t[0] == "%global" || t[0] == "%define") || t[1] != "build_if" {
            continue;
        }
        let expr = t[2..].join(" ");
        if expr.contains("%{_arch}") {
            return Ok(None);
        }
        let mut holds = true;
        for clause in expr.split("&&") {
            let p: Vec<&str> = clause.split_whitespace().collect();
            if p.len() != 3 || !matches!(p[0], "%{photon_subrelease}" | "0%{?photon_subrelease}") {
                return Err(format!("unsupported build_if: {expr}"));
            }
            let n: u32 = p[2]
                .parse()
                .map_err(|_| format!("unsupported build_if: {expr}"))?;
            holds &= match p[1] {
                "==" => sub == n,
                "!=" => sub != n,
                ">=" => sub >= n,
                "<=" => sub <= n,
                ">" => sub > n,
                "<" => sub < n,
                _ => return Err(format!("unsupported build_if operator in: {expr}")),
            };
        }
        return Ok(Some(holds));
    }
    Ok(Some(true))
}

/// What the tree builds at the pinned subrelease, per package name.
#[derive(Debug, Default)]
pub struct Plan {
    /// package -> (version, release) a spec built at this subrelease produces
    pub active: HashMap<String, (String, String)>,
    /// packages only specs of other subreleases produce
    pub foreign: HashSet<String>,
    /// packages of specs that could not be decided: never moved
    pub undecided: HashSet<String>,
}

/// One spec's contribution: its resolved text (subrelease conditionals decided,
/// includes inlined) and whether it builds at this subrelease.
pub fn add_spec(plan: &mut Plan, resolved: &str, builds: Option<bool>) {
    let Some(f) = spec_families_text(resolved) else {
        return;
    };
    let rel = resolved
        .lines()
        .find(|l| l.starts_with("Release:"))
        .and_then(|l| l.split_whitespace().nth(1))
        .map(|v| v.split('%').next().unwrap_or("").to_string())
        .unwrap_or_default();
    let decidable = !rel.is_empty() && rel.chars().all(|c| c.is_ascii_digit() || c == '.');
    match (builds, decidable) {
        (Some(true), true) => {
            for fam in f.families {
                let newer = match plan.active.get(&fam) {
                    Some((v, r)) => newer_than((&f.version, &rel), (v, r)),
                    None => true,
                };
                if newer {
                    plan.active.insert(fam, (f.version.clone(), rel.clone()));
                }
            }
        }
        (Some(false), _) => plan.foreign.extend(f.families),
        _ => plan.undecided.extend(f.families),
    }
}

fn newer_than(a: (&str, &str), b: (&str, &str)) -> bool {
    vercmp(a.0, b.0).then_with(|| vercmp(a.1, b.1)) == std::cmp::Ordering::Greater
}

/// Why an RPM file must not be visible to this build, or None.
pub fn hide_reason(plan: &Plan, file: &str, sub: u32) -> Option<String> {
    let (pkg, ver, rel) = parse_rpm_name(file)?;
    if plan.undecided.contains(&pkg) {
        return None;
    }
    let rel = rel.split(".ph").next().unwrap_or(&rel).to_string();
    if let Some((v, r)) = plan.active.get(&pkg) {
        return newer_than((&ver, &rel), (v, r))
            .then(|| format!("{ver}-{rel} shadows {v}-{r}, which subrelease {sub} builds"));
    }
    plan.foreign
        .contains(&pkg)
        .then(|| format!("no spec built at subrelease {sub} produces {pkg}"))
}

/// The plan for `release_tree` at `sub`, from every spec under SPECS.
pub fn plan_tree(release_tree: &Path, sub: u32) -> Result<Plan, String> {
    let mut plan = Plan::default();
    for spec in crate::build::find_files_rec(&release_tree.join("SPECS"), "", ".spec") {
        let raw = fs::read_to_string(&spec).map_err(|e| format!("{}: {e}", spec.display()))?;
        let builds = build_if(&raw, sub).map_err(|e| format!("{}: {e}", spec.display()))?;
        let (Some(dir), Some(name)) = (spec.parent(), spec.file_name()) else {
            continue;
        };
        let Some(text) = crate::specresolve::resolve(
            &crate::specresolve::dir_reader(dir),
            &name.to_string_lossy(),
            Some(sub),
        ) else {
            continue;
        };
        add_spec(&mut plan, &text, builds);
    }
    Ok(plan)
}

/// Move what `plan` hides out of `stage/RPMS`, recording each move. Returns how
/// many files moved. Anything already aside from an interrupted run is put
/// back first, so the decision is always made against the whole stage.
pub fn vault(stage: &Path, plan: &Plan, sub: u32, say: &mut dyn FnMut(&str)) -> Result<usize, String> {
    restore(stage, say);
    let rpms = stage.join("RPMS");
    let aside = stage.join(ASIDE);
    let mut manifest = String::new();
    let mut n = 0;
    for p in crate::build::find_files_rec(&rpms, "", ".rpm") {
        let file = p.file_name().unwrap_or_default().to_string_lossy().to_string();
        let Some(why) = hide_reason(plan, &file, sub) else {
            continue;
        };
        let rel = p.strip_prefix(&rpms).map_err(|e| e.to_string())?.to_path_buf();
        let dst = aside.join(&rel);
        if let Some(d) = dst.parent() {
            fs::create_dir_all(d).map_err(|e| format!("{}: {e}", d.display()))?;
        }
        fs::rename(&p, &dst).map_err(|e| format!("moving {} aside: {e}", p.display()))?;
        manifest.push_str(&format!("{}\t{why}\n", rel.display()));
        say(&format!("  aside {file}: {why}"));
        n += 1;
    }
    if n > 0 {
        let m = aside.join(MANIFEST);
        let mut all = fs::read_to_string(&m).unwrap_or_default();
        all.push_str(&manifest);
        fs::write(&m, all).map_err(|e| format!("{}: {e}", m.display()))?;
    }
    Ok(n)
}

/// Put everything back. A file the build has since produced under the same
/// name stays where the build put it, and the older copy stays aside - and is
/// reported, because it is the one case that needs a person to look.
pub fn restore(stage: &Path, say: &mut dyn FnMut(&str)) -> usize {
    let aside = stage.join(ASIDE);
    let rpms = stage.join("RPMS");
    let mut back = 0;
    let mut kept: Vec<PathBuf> = Vec::new();
    for p in crate::build::find_files_rec(&aside, "", ".rpm") {
        let Ok(rel) = p.strip_prefix(&aside) else {
            continue;
        };
        let dst = rpms.join(rel);
        if dst.exists() {
            kept.push(p.clone());
            continue;
        }
        if let Some(d) = dst.parent() {
            let _ = fs::create_dir_all(d);
        }
        if fs::rename(&p, &dst).is_ok() {
            back += 1;
        } else {
            kept.push(p.clone());
        }
    }
    for k in &kept {
        say(&format!(
            "  kept aside {}: the stage has a file of that name again",
            k.display()
        ));
    }
    if kept.is_empty() {
        let _ = fs::remove_file(aside.join(MANIFEST));
    }
    if back > 0 {
        say(&format!("  restored {back} RPM(s) from {}", aside.display()));
    }
    back
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(name: &str, ver: &str, rel: &str, extra: &str) -> String {
        format!("Name: {name}\nVersion: {ver}\nRelease: {rel}%{{?dist}}\n{extra}")
    }

    #[test]
    fn build_if_decides_every_form_the_tree_uses() {
        let b = |e: &str, s| build_if(&format!("%global build_if {e}\n"), s);
        assert_eq!(b("%{photon_subrelease} <= 90", 91).unwrap(), Some(false));
        assert_eq!(b("%{photon_subrelease} >= 91", 91).unwrap(), Some(true));
        assert_eq!(b("%{photon_subrelease} == 91", 92).unwrap(), Some(false));
        assert_eq!(b("%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92", 92).unwrap(), Some(true));
        assert_eq!(b("%{photon_subrelease} >= 91 && %{photon_subrelease} <= 92", 93).unwrap(), Some(false));
        assert_eq!(b("\"%{_arch}\" == \"aarch64\"", 91).unwrap(), None);
        assert!(b("%{photon_subrelease} ~ 91", 91).is_err());
        assert!(b("%{dist} == 91", 91).is_err());
        assert_eq!(build_if("Name: x\n", 91).unwrap(), Some(true));
    }

    fn gcc_plan() -> Plan {
        let mut p = Plan::default();
        let pkg = "%package -n libgcc\nSummary: x\n";
        add_spec(&mut p, &spec("gcc", "12.5.0", "2", pkg), Some(false));
        add_spec(&mut p, &spec("gcc", "12.2.0", "16.2", pkg), Some(true));
        add_spec(&mut p, &spec("rpm6", "6.0.1", "1", ""), Some(false));
        add_spec(&mut p, &spec("armonly", "1.0", "1", ""), None);
        p
    }

    #[test]
    fn the_mainline_compiler_is_hidden_from_a_subrelease_91_build() {
        let p = gcc_plan();
        let why = hide_reason(&p, "gcc-12.5.0-2.ph5.x86_64.rpm", 91).unwrap();
        assert!(why.contains("shadows 12.2.0-16.2"), "{why}");
        assert!(hide_reason(&p, "libgcc-12.5.0-2.ph5.x86_64.rpm", 91).is_some());
        assert!(hide_reason(&p, "gcc-12.2.0-16.2.ph5.x86_64.rpm", 91).is_none());
        // an OLDER copy cannot shadow, so it stays
        assert!(hide_reason(&p, "gcc-12.2.0-16.1.ph5.x86_64.rpm", 91).is_none());
    }

    #[test]
    fn a_package_only_another_subrelease_builds_is_hidden_and_an_unknown_one_is_not() {
        let p = gcc_plan();
        assert!(hide_reason(&p, "rpm6-6.0.1-1.ph5.x86_64.rpm", 91).unwrap().contains("no spec built"));
        assert!(hide_reason(&p, "armonly-1.0-1.ph5.x86_64.rpm", 91).is_none());
        assert!(hide_reason(&p, "unrelated-1.0-1.ph5.x86_64.rpm", 91).is_none());
    }

    #[test]
    fn a_release_rpm_cannot_expand_is_never_acted_on() {
        let mut p = Plan::default();
        add_spec(&mut p, "Name: k\nVersion: 1\nRelease: %{krel}%{?dist}\n", Some(true));
        assert!(hide_reason(&p, "k-2-1.ph5.x86_64.rpm", 91).is_none());
    }

    #[test]
    fn vault_moves_aside_and_restore_puts_back() {
        let root = std::env::temp_dir().join(format!("shk-subvault-{}", std::process::id()));
        let x = root.join("RPMS/x86_64");
        fs::create_dir_all(&x).unwrap();
        for f in ["gcc-12.5.0-2.ph5.x86_64.rpm", "gcc-12.2.0-16.2.ph5.x86_64.rpm", "zlib-1.3-1.ph5.x86_64.rpm"] {
            fs::write(x.join(f), f).unwrap();
        }
        let mut lines = Vec::new();
        let n = vault(&root, &gcc_plan(), 91, &mut |l| lines.push(l.to_string())).unwrap();
        assert_eq!(n, 1);
        assert!(!x.join("gcc-12.5.0-2.ph5.x86_64.rpm").exists());
        assert!(root.join(ASIDE).join("x86_64/gcc-12.5.0-2.ph5.x86_64.rpm").exists());
        assert!(fs::read_to_string(root.join(ASIDE).join(MANIFEST)).unwrap().contains("gcc-12.5.0-2"));
        assert!(x.join("gcc-12.2.0-16.2.ph5.x86_64.rpm").exists() && x.join("zlib-1.3-1.ph5.x86_64.rpm").exists());
        // an interrupted run's leftovers are put back before deciding again
        let again = vault(&root, &gcc_plan(), 91, &mut |_| {}).unwrap();
        assert_eq!(again, 1);
        assert_eq!(restore(&root, &mut |_| {}), 1);
        assert_eq!(fs::read(x.join("gcc-12.5.0-2.ph5.x86_64.rpm")).unwrap(), b"gcc-12.5.0-2.ph5.x86_64.rpm");
        assert!(!root.join(ASIDE).join(MANIFEST).exists());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_file_the_build_recreated_is_not_overwritten_on_restore() {
        let root = std::env::temp_dir().join(format!("shk-subvault-keep-{}", std::process::id()));
        let x = root.join("RPMS/x86_64");
        fs::create_dir_all(&x).unwrap();
        fs::write(x.join("gcc-12.5.0-2.ph5.x86_64.rpm"), b"old").unwrap();
        vault(&root, &gcc_plan(), 91, &mut |_| {}).unwrap();
        fs::write(x.join("gcc-12.5.0-2.ph5.x86_64.rpm"), b"new").unwrap();
        let mut lines = Vec::new();
        assert_eq!(restore(&root, &mut |l| lines.push(l.to_string())), 0);
        assert_eq!(fs::read(x.join("gcc-12.5.0-2.ph5.x86_64.rpm")).unwrap(), b"new");
        assert!(lines.iter().any(|l| l.contains("kept aside")), "{lines:?}");
        assert!(root.join(ASIDE).join(MANIFEST).exists());
        fs::remove_dir_all(&root).ok();
    }
}
