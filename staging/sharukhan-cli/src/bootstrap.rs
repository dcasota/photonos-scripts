//! A spec whose build environment needs one of its own subpackages, declared
//! as `%define ExtraBuildRequires <pkg>` (systemd.spec: rpm-build requires
//! systemd-rpm-macros, which systemd.spec makes), cannot be built in a stage
//! that holds no RPM of that subpackage at all - a stage seeded for a new
//! systemd release, where only the port's own Version-Release is trusted.
//! The spec names Photon's answer: consume the published RPM. This module is
//! that, verified: the highest NEVR the release's repositories publish, its
//! signature checked, recorded in the stage, and retired as soon as the
//! tree's own build of the package is there, before any media is composed.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The stage's record of the published RPMs it was given: file, sha256, url.
pub const LEDGER: &str = ".sharukhan-bootstrap.tsv";

/// The repositories a release publishes to, as the host's tdnf names them.
const REPOS: &[&str] = &["--disablerepo=*", "--enablerepo=photon-updates", "--enablerepo=photon-release", "--enablerepo=photon"];

/// The package names of a spec's `ExtraBuildRequires` define. Version
/// constraints (`pkg >= 1.2`, `pkg = 1.2-3`) are dropped with their operand.
pub fn extra_build_requires(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for l in text.lines() {
        let mut w = l.split_whitespace();
        let (Some(kw), Some(name)) = (w.next(), w.next()) else { continue };
        if !(kw == "%define" || kw == "%global") || name != "ExtraBuildRequires" {
            continue;
        }
        let toks: Vec<&str> = w.flat_map(|t| t.split(',')).filter(|t| !t.is_empty()).collect();
        let mut skip = false;
        for t in toks {
            if skip {
                skip = false;
                continue;
            }
            if matches!(t, "=" | ">=" | "<=" | ">" | "<") {
                skip = true;
                continue;
            }
            if t.chars().next().is_some_and(|c| c.is_ascii_alphanumeric()) && !t.contains('%') {
                out.push(t.to_string());
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

/// Every (spec, package) where a spec of `tree` at `sub` needs one of its own
/// subpackages to be built.
pub fn self_needs(tree: &Path, sub: Option<u32>) -> Vec<(String, String)> {
    let mut out = Vec::new();
    for (_, text) in crate::baseline::spec_texts(tree, sub) {
        let Some(f) = crate::buildexec::spec_families_text(&text) else { continue };
        for p in extra_build_requires(&text) {
            if f.families.contains(&p) {
                out.push((f.name.clone(), p));
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

/// The RPM files of `pkg` in `stage/RPMS/<arch>/`.
fn rpms_of(stage: &Path, pkg: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(rd) = fs::read_dir(stage.join("RPMS")) else { return out };
    for a in rd.flatten() {
        let Ok(files) = fs::read_dir(a.path()) else { continue };
        for f in files.flatten() {
            let n = f.file_name().to_string_lossy().into_owned();
            if crate::buildexec::parse_rpm_name(&n).is_some_and(|(p, _, _)| p == pkg) {
                out.push(f.path());
            }
        }
    }
    out.sort();
    out
}

/// The highest published NEVR of `pkg` among `urls` (tdnf's `--location`
/// lines). Only files named exactly `<pkg>-<v>-<r>.<arch>.rpm` count.
pub fn pick_latest(urls: &str, pkg: &str) -> Option<String> {
    let mut best: Option<(String, String, String)> = None;
    for u in urls.lines().map(str::trim).filter(|l| l.starts_with("https://")) {
        let file = u.rsplit('/').next().unwrap_or("");
        let Some((p, v, r)) = crate::buildexec::parse_rpm_name(file) else { continue };
        if p != pkg {
            continue;
        }
        let newer = match &best {
            None => true,
            Some((_, bv, br)) => crate::buildexec::vercmp(&v, bv).then_with(|| crate::buildexec::vercmp(&r, br)).is_gt(),
        };
        if newer {
            best = Some((u.to_string(), v, r));
        }
    }
    best.map(|(u, _, _)| u)
}

fn out(prog: &str, args: &[&str]) -> Result<String, String> {
    let o = Command::new(prog).args(args).output().map_err(|e| format!("running {prog}: {e}"))?;
    if o.status.success() {
        Ok(String::from_utf8_lossy(&o.stdout).into_owned())
    } else {
        Err(format!("{prog} {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()))
    }
}

/// Give `stage` the published RPM of every package a spec of `tree` needs
/// for its own build and the stage holds no RPM of. Returns what was added.
pub fn provide(tree: &Path, stage: &Path, log: &mut dyn FnMut(&str)) -> Result<Vec<String>, String> {
    let sub = crate::specresolve::tree_subrelease(tree);
    let cfg: serde_json::Value = serde_json::from_str(&fs::read_to_string(tree.join("build-config.json")).map_err(|e| format!("{}: {e}", tree.display()))?)
        .map_err(|e| format!("{}/build-config.json: {e}", tree.display()))?;
    let releasever = cfg["photon-build-param"]["photon-release-version"].as_str().ok_or_else(|| format!("{}/build-config.json: no photon-release-version", tree.display()))?.to_string();
    let mut added = Vec::new();
    for (spec, pkg) in self_needs(tree, sub) {
        if !rpms_of(stage, &pkg).is_empty() {
            continue;
        }
        let mut a: Vec<&str> = vec!["--releasever", &releasever];
        a.extend(REPOS);
        a.extend(["repoquery", "--location", pkg.as_str()]);
        let urls = out("tdnf", &a)?;
        let url = pick_latest(&urls, &pkg).ok_or_else(|| format!("{spec} builds with {pkg}, the stage has none, and the {releasever} repositories publish none"))?;
        if !url.starts_with("https://") {
            return Err(format!("{url}: not https"));
        }
        let file = url.rsplit('/').next().unwrap_or("").to_string();
        let tmp = stage.join(format!(".bootstrap.{}", std::process::id()));
        fs::create_dir_all(&tmp).map_err(|e| format!("{}: {e}", tmp.display()))?;
        let dl = tmp.join(&file);
        let r = (|| -> Result<String, String> {
            out("curl", &["-fsS", "--proto", "=https", "--retry", "3", "-o", &dl.to_string_lossy(), &url])?;
            let k = out("rpm", &["-K", &dl.to_string_lossy()])?;
            if !k.trim_end().ends_with("digests signatures OK") {
                return Err(format!("{file}: no valid signature ({})", k.trim()));
            }
            let q = out("rpm", &["-qp", "--qf", "%{NAME} %{ARCH}", &dl.to_string_lossy()])?;
            let (n, arch) = q.trim().split_once(' ').ok_or_else(|| format!("{file}: rpm -qp said {q:?}"))?;
            if n != pkg {
                return Err(format!("{file} is {n}, not {pkg}"));
            }
            let dir = stage.join("RPMS").join(arch);
            fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
            let sum = crate::sha256::bytes(&fs::read(&dl).map_err(|e| format!("{}: {e}", dl.display()))?);
            fs::rename(&dl, dir.join(&file)).map_err(|e| format!("{}: {e}", dir.display()))?;
            let mut led = fs::read_to_string(stage.join(LEDGER)).unwrap_or_default();
            led.push_str(&format!("{arch}/{file}\t{sum}\t{url}\n"));
            fs::write(stage.join(LEDGER), led).map_err(|e| format!("{}: {e}", stage.join(LEDGER).display()))?;
            Ok(sum)
        })();
        let _ = fs::remove_dir_all(&tmp);
        let sum = r?;
        log(&format!("  bootstrap: {spec} builds with {pkg}, which the stage lacks: the published {file} (signature OK, sha256 {}), retired once {spec} is built", &sum[..16]));
        added.push(file);
    }
    Ok(added)
}

/// Remove every recorded bootstrap RPM whose package the stage now also has
/// from another file (the tree's own build). Returns the files still in
/// place: a bootstrap RPM that would reach the media.
pub fn retire(stage: &Path, log: &mut dyn FnMut(&str)) -> Result<Vec<String>, String> {
    let led_path = stage.join(LEDGER);
    let Ok(text) = fs::read_to_string(&led_path) else { return Ok(vec![]) };
    let mut keep = String::new();
    let mut left = Vec::new();
    for line in text.lines().filter(|l| !l.trim().is_empty()) {
        let rel = line.split('\t').next().unwrap_or("");
        let path = stage.join("RPMS").join(rel);
        let file = rel.rsplit('/').next().unwrap_or("");
        let Some((pkg, _, _)) = crate::buildexec::parse_rpm_name(file) else { continue };
        if !path.exists() {
            continue;
        }
        let others: Vec<PathBuf> = rpms_of(stage, &pkg).into_iter().filter(|p| p != &path).collect();
        if others.is_empty() {
            keep.push_str(line);
            keep.push('\n');
            left.push(file.to_string());
            continue;
        }
        fs::remove_file(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        log(&format!("  bootstrap {file} retired: the stage has {} of its own", others.iter().filter_map(|p| p.file_name()).map(|n| n.to_string_lossy().into_owned()).collect::<Vec<_>>().join(", ")));
    }
    if keep.is_empty() {
        let _ = fs::remove_file(&led_path);
    } else {
        fs::write(&led_path, keep).map_err(|e| format!("{}: {e}", led_path.display()))?;
    }
    Ok(left)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extra_build_requires_reads_names_not_constraints() {
        let t = "Name: systemd\n%define ExtraBuildRequires systemd-rpm-macros\n%global ExtraBuildRequires foo >= 1.2, bar = 3-4 baz\n%define Other x\n";
        assert_eq!(extra_build_requires(t), vec!["bar", "baz", "foo", "systemd-rpm-macros"]);
        assert!(extra_build_requires("%define ExtraBuildRequiresSansSnapshot x\n").is_empty());
    }

    #[test]
    fn the_highest_published_nevr_is_picked_by_rpm_order() {
        let urls = "https://h/p/noarch/systemd-rpm-macros-257.13-9.ph5.noarch.rpm\n\
                    https://h/p/noarch/systemd-rpm-macros-257.13-10.ph5.noarch.rpm\n\
                    https://h/p/noarch/systemd-rpm-macros-extra-300-1.ph5.noarch.rpm\n\
                    http://h/p/noarch/systemd-rpm-macros-999-1.ph5.noarch.rpm\n";
        assert_eq!(pick_latest(urls, "systemd-rpm-macros").as_deref(), Some("https://h/p/noarch/systemd-rpm-macros-257.13-10.ph5.noarch.rpm"));
        assert_eq!(pick_latest(urls, "absent"), None);
    }

    #[test]
    fn a_bootstrap_rpm_is_retired_only_once_the_stage_has_its_own() {
        let d = crate::safepath::test_base().join(format!("shk-bootstrap-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let noarch = d.join("RPMS/noarch");
        fs::create_dir_all(&noarch).unwrap();
        let boot = "systemd-rpm-macros-257.13-6.ph5.noarch.rpm";
        fs::write(noarch.join(boot), "x").unwrap();
        fs::write(d.join(LEDGER), format!("noarch/{boot}\tabc\thttps://h/{boot}\n")).unwrap();
        let mut seen = Vec::new();
        assert_eq!(retire(&d, &mut |l| seen.push(l.to_string())).unwrap(), vec![boot.to_string()]);
        assert!(noarch.join(boot).exists() && d.join(LEDGER).exists());
        let own = "systemd-rpm-macros-262.2-1.ph5.noarch.rpm";
        fs::write(noarch.join(own), "y").unwrap();
        assert!(retire(&d, &mut |l| seen.push(l.to_string())).unwrap().is_empty());
        assert!(!noarch.join(boot).exists() && noarch.join(own).exists() && !d.join(LEDGER).exists());
        assert!(seen.iter().any(|l| l.contains("retired") && l.contains(own)), "{seen:?}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn a_spec_that_needs_its_own_subpackage_is_found() {
        let d = crate::safepath::test_base().join(format!("shk-selfneed-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("SPECS/systemd")).unwrap();
        fs::create_dir_all(d.join("SPECS/other")).unwrap();
        fs::write(d.join("build-config.json"), r#"{"photon-build-param": {"photon-subrelease": "92"}}"#).unwrap();
        fs::write(d.join("SPECS/systemd/systemd.spec"), "Name: systemd\nVersion: 262.2\nRelease: 1%{?dist}\n%define ExtraBuildRequires systemd-rpm-macros\n%package rpm-macros\nSummary: m\n%description rpm-macros\nm\n").unwrap();
        fs::write(d.join("SPECS/other/other.spec"), "Name: other\nVersion: 1\nRelease: 1%{?dist}\n%define ExtraBuildRequires systemd-rpm-macros\n").unwrap();
        assert_eq!(self_needs(&d, Some(92)), vec![("systemd".to_string(), "systemd-rpm-macros".to_string())]);
        let _ = fs::remove_dir_all(&d);
    }
}
