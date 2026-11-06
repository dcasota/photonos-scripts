//! `--baseline`: the media of the release as upstream has it, without any PR.
//!
//! A package PR is needed only while the defect it fixes shows on the
//! release without it. That is a package-lifecycle run on media built from
//! pristine 5.0 and pristine common, compared with the run on the gated
//! media. Building that baseline in the gate's stage would be wrong: the
//! stage holds the PR builds, at higher Releases than the pristine specs
//! declare (they would win on version and ship) and at NEVRs the release
//! later reached with other content (the content ledger knows those).
//!
//! So the baseline builds in a root of its own, whose stage is seeded with
//! hard links to exactly the gate-stage RPMs a pristine spec produces: the
//! one spec that builds at the subrelease declares that package at that
//! Version-Release, and the gate's content ledger records no other content
//! for it. Everything else the build makes itself. The gate's stage is
//! never written. The variant patches are empty files: every variant is the
//! tree as it is, and every expectation (the installer on the media, the
//! kernel) is derived from the pristine tree as it is for a gated build.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use crate::config::Config;

/// The configuration a `--baseline` build or test runs under.
pub fn effective_cfg(cfg: &Config) -> Config {
    if cfg.baseline.is_some() {
        return cfg.clone();
    }
    let mut b = cfg.clone();
    b.baseline = Some(cfg.photon_tree.join("stage"));
    let root = cfg.work.join("baseline-root");
    b.build_root = root.clone();
    b.photon_tree = root.join(&cfg.release);
    b.variant_patches = cfg.variant_patches.join("baseline");
    b.iso_cache = cfg.iso_cache.join("baseline");
    b
}

/// The variant patches of the baseline: one empty `poi-<variant>.patch` per
/// variant and an empty `common-fixes.patch`. Written fresh, so nothing a
/// gated run made can be left in them.
pub fn write_patches(b: &Config, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let vs = crate::variants::load_file(&b.variants_file)?;
    fs::create_dir_all(&b.variant_patches).map_err(|e| format!("{}: {e}", b.variant_patches.display()))?;
    let mut names: Vec<String> = vs.variants.iter().map(|v| format!("poi-{}.patch", v.name)).collect();
    names.push("common-fixes.patch".into());
    for n in &names {
        let p = b.variant_patches.join(n);
        fs::write(&p, "").map_err(|e| format!("{}: {e}", p.display()))?;
    }
    log(&format!("baseline variant patches: {} empty file(s) in {}", names.len(), b.variant_patches.display()));
    Ok(())
}

/// What a spec of the pristine tree produces at the subrelease: each binary
/// package's name -> (Version, Release without dist, spec name, spec dir).
type Produced = BTreeMap<String, (String, String, String, PathBuf)>;

/// Every spec under `<tree>/SPECS` that builds at `sub`, read as that
/// subrelease sees it. A spec that cannot be read without rpm (a Release
/// behind a macro, a missing Name) contributes nothing: its RPMs are not
/// trusted and the build makes them. A package two specs claim at this
/// subrelease is dropped for the same reason.
pub fn produced(tree: &Path, sub: Option<u32>) -> Produced {
    let specs = tree.join("SPECS");
    let children = |d: &Path| -> Vec<PathBuf> {
        fs::read_dir(d).map(|rd| rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect()).unwrap_or_default()
    };
    let mut dirs = children(&specs);
    let subdirs: Vec<PathBuf> = dirs
        .iter()
        .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit())))
        .cloned()
        .collect();
    for s in &subdirs {
        dirs.extend(children(s));
    }
    let mut out: Produced = BTreeMap::new();
    let mut doubled = std::collections::BTreeSet::new();
    for dir in dirs.iter().filter(|d| !subdirs.contains(d)) {
        let Ok(rd) = fs::read_dir(dir) else { continue };
        for e in rd.flatten() {
            let file = e.file_name().to_string_lossy().into_owned();
            if !file.ends_with(".spec") {
                continue;
            }
            let Some(text) = crate::specresolve::resolve(&crate::specresolve::dir_reader(dir), &file, sub) else { continue };
            if !crate::buildexec::builds_at(&text, sub) {
                continue;
            }
            let Some(fams) = crate::buildexec::spec_families_text(&text) else { continue };
            let rel = text
                .lines()
                .find(|l| l.starts_with("Release:"))
                .and_then(|l| l.split_whitespace().nth(1))
                .map(|v| v.split('%').next().unwrap_or("").to_string())
                .unwrap_or_default();
            if rel.is_empty() || !rel.chars().all(|c| c.is_ascii_digit() || c == '.') {
                continue;
            }
            for pkg in &fams.families {
                if out.insert(pkg.clone(), (fams.version.clone(), rel.clone(), fams.name.clone(), dir.clone())).is_some() {
                    doubled.insert(pkg.clone());
                }
            }
        }
    }
    for d in doubled {
        out.remove(&d);
    }
    out
}

/// How the seeding went.
#[derive(Debug, Default, PartialEq)]
pub struct Seeded {
    pub linked: usize,
    pub present: usize,
    /// RPMs no pristine spec produces at that Version-Release (PR builds,
    /// other subreleases, stale ones).
    pub not_produced: usize,
    /// RPMs at a pristine NEVR the gate's ledger records other content for.
    pub other_content: Vec<String>,
    pub sources: usize,
}

/// Link into `dest` (a stage) the RPMs of `gate` (the gate's stage) that the
/// pristine tree produces, and every source tarball. Never writes `gate`.
pub fn seed(gate: &Path, tree: &Path, sub: Option<u32>, dest: &Path) -> Result<Seeded, String> {
    let made = produced(tree, sub);
    let dist = crate::specresolve::dist_tag_of(tree).ok_or_else(|| format!("{}: no photon-dist-tag", tree.display()))?;
    let ledger = crate::buildexec::parse_ledger(&fs::read_to_string(gate.join(crate::buildexec::BUILT_FROM_LEDGER)).unwrap_or_default());
    let mut hashes: BTreeMap<PathBuf, Option<String>> = BTreeMap::new();
    let mut s = Seeded::default();
    let link = |from: &Path, to: &Path| -> Result<bool, String> {
        if to.exists() {
            return Ok(false);
        }
        fs::hard_link(from, to).map_err(|e| format!("linking {} -> {}: {e}", from.display(), to.display()))?;
        Ok(true)
    };
    let rpms = gate.join("RPMS");
    for arch in fs::read_dir(&rpms).map_err(|e| format!("{}: {e}", rpms.display()))?.flatten() {
        let adir = arch.path();
        if !adir.is_dir() {
            continue;
        }
        let to_dir = dest.join("RPMS").join(arch.file_name());
        fs::create_dir_all(&to_dir).map_err(|e| format!("{}: {e}", to_dir.display()))?;
        for f in fs::read_dir(&adir).map_err(|e| format!("{}: {e}", adir.display()))?.flatten() {
            let name = f.file_name().to_string_lossy().into_owned();
            let Some((pkg, ver, rel)) = crate::buildexec::parse_rpm_name(&name) else { continue };
            let Some((v, r, spec, dir)) = made.get(&pkg) else {
                s.not_produced += 1;
                continue;
            };
            if &ver != v || rel.strip_suffix(dist.as_str()) != Some(r.as_str()) {
                s.not_produced += 1;
                continue;
            }
            let key = format!("{spec}-{v}-{r}");
            if let Some(was) = ledger.get(&key) {
                let now = hashes.entry(dir.clone()).or_insert_with(|| crate::buildexec::spec_dir_hash(dir)).clone();
                if now.as_deref() != Some(was.as_str()) {
                    s.other_content.push(name);
                    continue;
                }
            }
            if link(&f.path(), &to_dir.join(&name))? {
                s.linked += 1;
            } else {
                s.present += 1;
            }
        }
    }
    let src = gate.join("SOURCES");
    if let Ok(rd) = fs::read_dir(&src) {
        let to = dest.join("SOURCES");
        fs::create_dir_all(&to).map_err(|e| format!("{}: {e}", to.display()))?;
        for f in rd.flatten() {
            if f.path().is_file() && link(&f.path(), &to.join(f.file_name()))? {
                s.sources += 1;
            }
        }
    }
    s.other_content.sort();
    Ok(s)
}

/// Before a baseline build: the empty variant patches, then the stage
/// seeded from the gate's (`gate_stage`).
pub fn prepare(b: &Config, gate_stage: &Path, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    write_patches(b, log)?;
    seed_stage(b, gate_stage, "baseline", log)
}

/// Seed the stage of `b`'s release tree from `gate_stage` with only what
/// that tree's specs produce, and log the counts under `label`. A build in a
/// root of its own (a baseline, a systemd port) then rebuilds what its tree
/// changes, never what it shares with the gate.
pub fn seed_stage(b: &Config, gate_stage: &Path, label: &str, log: &mut dyn FnMut(&str)) -> Result<(), String> {
    let sub = crate::specresolve::tree_subrelease(&b.photon_tree);
    let dest = b.photon_tree.join("stage");
    let s = seed(gate_stage, &b.photon_tree, sub, &dest)?;
    log(&format!(
        "{label} stage seeded from {}: {} RPM(s) linked, {} already there, {} not what the tree's specs produce, {} at the tree's NEVR built from other content, {} source(s) linked",
        gate_stage.display(),
        s.linked,
        s.present,
        s.not_produced,
        s.other_content.len(),
        s.sources
    ));
    for n in &s.other_content {
        log(&format!("  not linked, other content at the release's NEVR: {n}"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The seeding links exactly what the pristine specs produce: not a PR's
    /// higher Release, not another subrelease's spec, not a pristine NEVR the
    /// ledger records other content for; and it never writes the gate stage.
    #[test]
    fn the_baseline_stage_holds_only_what_the_pristine_specs_produce() {
        let root = std::env::temp_dir().join(format!("shk-baseline-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let tree = root.join("5.0");
        let gate = root.join("gate-stage");
        let dest = root.join("baseline-stage");
        fs::create_dir_all(gate.join("RPMS/x86_64")).unwrap();
        fs::create_dir_all(gate.join("RPMS/noarch")).unwrap();
        fs::create_dir_all(gate.join("SOURCES")).unwrap();
        fs::create_dir_all(&tree).unwrap();
        fs::write(tree.join("build-config.json"), r#"{"photon-build-param": {"photon-dist-tag": ".ph5", "photon-subrelease": "92"}}"#).unwrap();
        let spec = |dir: &str, name: &str, cond: &str, ver: &str, rel: &str, extra: &str| {
            let d = tree.join("SPECS").join(dir);
            fs::create_dir_all(&d).unwrap();
            fs::write(d.join(format!("{name}.spec")), format!("%global build_if %{{photon_subrelease}} {cond}\nName: {name}\nVersion: {ver}\nRelease: {rel}%{{?dist}}\n%package devel\nSummary: x\n{extra}")).unwrap();
        };
        spec("foo", "foo", ">= 91", "1.0", "2", "");
        spec("91/foo", "foo", "== 91", "1.0", "1", "");
        spec("bar", "bar", ">= 91", "2.0", "5", "");
        spec("baz", "baz", ">= 91", "3.0", "%{rel}", "");
        let rpm = |a: &str, n: &str| fs::write(gate.join("RPMS").join(a).join(n), n).unwrap();
        for n in [
            "foo-1.0-2.ph5.x86_64.rpm",       // pristine: linked
            "foo-devel-1.0-2.ph5.x86_64.rpm", // pristine subpackage: linked
            "foo-1.0-3.ph5.x86_64.rpm",       // a PR's higher Release: not produced
            "foo-1.0-1.ph5.x86_64.rpm",       // the 91 spec's: not produced at 92
            "bar-2.0-5.ph5.x86_64.rpm",       // pristine NEVR, ledger says other content
            "baz-3.0-1.ph5.x86_64.rpm",       // Release behind a macro: not trusted
            "qux-1-1.ph5.x86_64.rpm",         // no spec at all
        ] {
            rpm("x86_64", n);
        }
        rpm("noarch", "foo-1.0-2.ph5.noarch.rpm");
        fs::write(gate.join("SOURCES/foo-1.0.tar.gz"), "src").unwrap();
        fs::write(gate.join(crate::buildexec::BUILT_FROM_LEDGER), "bar-2.0-5\tpr-content\n").unwrap();
        let before = fs::read_to_string(gate.join(crate::buildexec::BUILT_FROM_LEDGER)).unwrap();

        let s = seed(&gate, &tree, Some(92), &dest).unwrap();
        assert_eq!(s.linked, 3, "{s:?}");
        assert_eq!(s.not_produced, 4, "{s:?}");
        assert_eq!(s.other_content, vec!["bar-2.0-5.ph5.x86_64.rpm".to_string()]);
        assert_eq!(s.sources, 1);
        let mut have: Vec<String> = fs::read_dir(dest.join("RPMS/x86_64")).unwrap().flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
        have.sort();
        assert_eq!(have, vec!["foo-1.0-2.ph5.x86_64.rpm", "foo-devel-1.0-2.ph5.x86_64.rpm"]);
        assert!(dest.join("RPMS/noarch/foo-1.0-2.ph5.noarch.rpm").exists());
        // hard links: the same file, nothing copied
        use std::os::unix::fs::MetadataExt;
        assert_eq!(fs::metadata(dest.join("RPMS/x86_64/foo-1.0-2.ph5.x86_64.rpm")).unwrap().ino(), fs::metadata(gate.join("RPMS/x86_64/foo-1.0-2.ph5.x86_64.rpm")).unwrap().ino());
        // the gate stage is untouched, and a second seeding links nothing new
        assert_eq!(fs::read_dir(gate.join("RPMS/x86_64")).unwrap().count(), 7);
        assert_eq!(fs::read_to_string(gate.join(crate::buildexec::BUILT_FROM_LEDGER)).unwrap(), before);
        let again = seed(&gate, &tree, Some(92), &dest).unwrap();
        assert_eq!((again.linked, again.present), (0, 3));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn a_baseline_runs_in_a_root_cache_and_patches_of_its_own_with_empty_patches() {
        let d = std::env::temp_dir().join(format!("shk-baseline-cfg-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let mut cfg = Config::for_test(&d);
        cfg.work = d.join("work");
        cfg.variant_patches = d.join("vp");
        cfg.release = "5.0".into();
        let b = effective_cfg(&cfg);
        assert_eq!(b.baseline, Some(cfg.photon_tree.join("stage")));
        assert_eq!(b.build_root, d.join("work/baseline-root"));
        assert_eq!(b.photon_tree, d.join("work/baseline-root/5.0"));
        assert_eq!(b.variant_patches, d.join("vp/baseline"));
        assert_eq!(b.iso_cache, cfg.iso_cache.join("baseline"));
        assert_eq!(effective_cfg(&b).build_root, b.build_root, "applied twice, derived once");
        write_patches(&b, &mut |_| {}).unwrap();
        for n in ["poi-2.8.patch", "poi-latest.patch", "common-fixes.patch"] {
            assert!(crate::build::is_empty_patch(&b.variant_patches.join(n)), "{n}");
        }
        let _ = fs::remove_dir_all(&d);
    }
}
