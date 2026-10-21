//! Parse a SPECS tree the way Photon's package builder does, before a build.
//!
//! Gate 49 lost every ISO build to one line a fix branch added,
//! `Requires: /usr/bin/tar`: the package builder's SpecData resolves each
//! requirement by package name or by a `Provides:` some spec declares, and no
//! spec declares that path, so `make` stopped at
//! "ERROR: What package provides /usr/bin/tar ? Used in 'dovecot' spec."
//! rpm itself would have been happy, and so was every check of the day.
//!
//! The only faithful check is the builder's own code. This runs SpecData
//! (common/support/package-builder) over the common SPECS and the given
//! release SPECS, configured from the release's build-config.json exactly as
//! build.py's initialize_constants configures it for the spec side: the two
//! spec paths, the dist tag, the release and subrelease, the branch. Building
//! `SPECS.getData()` parses every spec and resolves every requirement; any
//! exception it raises is the build's own error, returned verbatim.

use std::path::{Path, PathBuf};
use std::process::Command;

/// The driver, run with the package builder's directory on `sys.path`.
const DRIVER: &str = r#"
import json, os, sys
pb, common_specs, release_specs, cfg, logdir, changed = sys.argv[1:7]
sys.path.insert(0, pb)
from constants import constants
c = json.load(open(cfg))
p = c["photon-build-param"]
constants.addSpecPath(common_specs)
constants.addSpecPath(release_specs)
os.makedirs(logdir, exist_ok=True)
constants.setLogPath(logdir)
constants.setLogLevel("error")
constants.setDist(p["photon-dist-tag"])
constants.setReleaseVersion(p["photon-release-version"])
constants.setSubreleaseVersion(p["photon-subrelease"])
constants.setPhotonBranch(c["photon-branch"])
constants.initialize()
from SpecData import SPECS
d = SPECS.getData()
print("SPECDATA-OK %d" % len(d.mapSpecFileNameToSpecObj))
# build.py's CheckTools.check_spec_files: check_specs over the changed specs
files = [l.strip() for l in open(changed) if l.strip()]
if files:
    sys.path.insert(0, os.path.join(os.path.dirname(pb), "spec-checker"))
    from check_spec import check_specs
    if check_specs(files, p["photon-subrelease"], p.get("photon-mainline")):
        print("SPECCHECK-FAILED")
        sys.exit(3)
print("SPECCHECK-OK %d" % len(files))
"#;

/// The runtime-dependency driver. The package builder skips a requested
/// package whose RPMs are already in the stage before it looks at that
/// package's `Requires:`, so a dependency whose spec moved to a new NEVR since
/// is never built: `minimal` stays built, `docker` 29.8.0-3 never is, and
/// photon-iso-builder's tdnf then fails on the older docker's requirements.
/// This walks the install requirements from the image's package lists with
/// SpecData's own resolution, descending only through packages whose RPMs are
/// all present (an unbuilt one is the builder's to build, with its
/// dependencies), and names every spec reached that way whose RPMs are not.
const DEPS_DRIVER: &str = r#"
import json, os, sys
pb, common_specs, release_specs, cfg, logdir, rpmdir, roots_file = sys.argv[1:8]
lists = sys.argv[8:]
sys.path.insert(0, pb)
from constants import constants
c = json.load(open(cfg))
p = c["photon-build-param"]
constants.addSpecPath(common_specs)
constants.addSpecPath(release_specs)
os.makedirs(logdir, exist_ok=True)
constants.setLogPath(logdir)
constants.setLogLevel("error")
constants.setDist(p["photon-dist-tag"])
constants.setReleaseVersion(p["photon-release-version"])
constants.setSubreleaseVersion(p["photon-subrelease"])
constants.setPhotonBranch(c["photon-branch"])
constants.setRpmPath(rpmdir)
constants.initialize()
from SpecData import SPECS
d = SPECS.getData()
arch = constants.buildArch
names = [l.strip() for l in open(roots_file) if l.strip()]
for f in lists:
    j = json.load(open(f))
    names += j["packages"] + j.get("packages_" + arch, [])
def built(spec, ver):
    for r in d.getRPMPackages(spec, ver):
        a = d.getBuildArch(r, ver)
        if not os.path.isfile(os.path.join(rpmdir, a, f"{r}-{ver}.{a}.rpm")):
            return False
    return True
def requires(pkg, ver):
    for obj in d.getSpecObjects(pkg):
        if obj.version == ver:
            for dep in obj.installRequiresPackages.get(pkg, []):
                v = d._getProperVersion(dep)
                if not v:
                    raise Exception(f"Could not find proper version for {dep.package}")
                yield dep.package, v
            return
    raise Exception(f"Invalid package: {pkg}-{ver}")
seen, todo = set(), []
for n in names:
    if not d.isRPMPackage(n):
        raise Exception(f"{n} is listed for the image but no spec builds it")
    for v in d.getVersions(n):
        todo.append((n, v))
cache, reported = {}, set()
while todo:
    pkg, ver = todo.pop()
    if (pkg, ver) in seen:
        continue
    seen.add((pkg, ver))
    spec = d.getSpecNameForVersion(pkg, ver)
    if (spec, ver) not in cache:
        cache[(spec, ver)] = built(spec, ver)
    if not cache[(spec, ver)]:
        continue
    for dp, dv in requires(pkg, ver):
        ds = d.getSpecNameForVersion(dp, dv)
        if (ds, dv) not in cache:
            cache[(ds, dv)] = built(ds, dv)
        if cache[(ds, dv)]:
            todo.append((dp, dv))
        elif (ds, dv) not in reported:
            reported.add((ds, dv))
            print(f"UNBUILT {ds} {dv} {pkg}-{ver}")
print("DEPS-OK %d" % len(seen))
"#;

/// A spec an already-built package needs at runtime whose RPMs are missing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Unbuilt {
    /// The spec's name, which is also its `make` target.
    pub spec: String,
    /// version-release.dist, as SpecData names it
    pub version: String,
    /// The first already-built package found requiring it, with its version.
    pub needed_by: String,
}

/// Parse the dependency driver's output.
pub fn parse_unbuilt(stdout: &str) -> Option<Vec<Unbuilt>> {
    stdout.lines().find(|l| l.starts_with("DEPS-OK "))?;
    Some(
        stdout
            .lines()
            .filter_map(|l| {
                let mut f = l.strip_prefix("UNBUILT ")?.split_whitespace();
                let (spec, version, needed_by) = (f.next()?, f.next()?, f.next()?);
                f.next().is_none().then(|| Unbuilt {
                    spec: spec.into(),
                    version: version.into(),
                    needed_by: needed_by.into(),
                })
            })
            .collect(),
    )
}

/// The specs whose RPMs are missing from `rpm_dir` although an already-built
/// package reachable from `roots` or the package lists `lists` requires them
/// at runtime, resolved by the package builder's SpecData over the common
/// SPECS and `release_specs`. The builder itself never builds these (see
/// DEPS_DRIVER).
pub fn unbuilt_runtime_deps(
    inputs: &Inputs,
    release_specs: &Path,
    rpm_dir: &Path,
    roots: &[String],
    lists: &[PathBuf],
    log_dir: &Path,
) -> Result<Vec<Unbuilt>, String> {
    if let Some(m) = inputs.missing() {
        return Err(format!("cannot run the package builder's spec parser: {m}"));
    }
    for p in lists {
        if !p.is_file() {
            return Err(format!("package list {} does not exist", p.display()));
        }
    }
    std::fs::create_dir_all(log_dir).map_err(|e| format!("{}: {e}", log_dir.display()))?;
    let roots_file = log_dir.join("runtime-roots.txt");
    let text: String = roots.iter().map(|r| format!("{r}\n")).collect();
    std::fs::write(&roots_file, text).map_err(|e| format!("{}: {e}", roots_file.display()))?;
    let out = Command::new("python3")
        .arg("-c")
        .arg(DEPS_DRIVER)
        .arg(&inputs.package_builder)
        .arg(&inputs.common_specs)
        .arg(release_specs)
        .arg(&inputs.build_config)
        .arg(log_dir)
        .arg(rpm_dir)
        .arg(&roots_file)
        .args(lists)
        .current_dir(&inputs.package_builder)
        .output()
        .map_err(|e| format!("running python3: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    match (out.status.success(), parse_unbuilt(&stdout)) {
        (true, Some(u)) => Ok(u),
        _ => Err(builder_error(&stdout, &stderr)),
    }
}

/// Where the pieces of a build root are.
pub struct Inputs {
    /// common/support/package-builder
    pub package_builder: PathBuf,
    /// common/SPECS
    pub common_specs: PathBuf,
    /// <release>/build-config.json
    pub build_config: PathBuf,
}

impl Inputs {
    pub fn from_build_root(build_root: &Path, common: &str, release: &str) -> Inputs {
        let c = build_root.join(common);
        Inputs {
            package_builder: c.join("support/package-builder"),
            common_specs: c.join("SPECS"),
            build_config: build_root.join(release).join("build-config.json"),
        }
    }

    /// The package builder and common SPECS of `common` (a checked-out common
    /// tree), with the release's `build_config`.
    pub fn from_trees(common: &Path, build_config: PathBuf) -> Inputs {
        Inputs {
            package_builder: common.join("support/package-builder"),
            common_specs: common.join("SPECS"),
            build_config,
        }
    }

    /// What is missing to run the check, if anything.
    pub fn missing(&self) -> Option<String> {
        for p in [
            self.package_builder.join("SpecData.py"),
            self.common_specs.clone(),
            self.build_config.clone(),
        ] {
            if !p.exists() {
                return Some(format!("{} does not exist", p.display()));
            }
        }
        None
    }
}

/// Parse `release_specs` with the package builder's SpecData, then run the
/// spec checker over `changed` (absolute spec paths) exactly as build.py's
/// check_spec_files does before every build. Ok with the number of specs
/// parsed; Err with the builder's or the checker's own words.
pub fn check(
    inputs: &Inputs,
    release_specs: &Path,
    changed: &[PathBuf],
    log_dir: &Path,
) -> Result<usize, String> {
    if let Some(m) = inputs.missing() {
        return Err(format!("cannot run the package builder's spec parser: {m}"));
    }
    if !release_specs.is_dir() {
        return Err(format!("{} is not a directory", release_specs.display()));
    }
    std::fs::create_dir_all(log_dir).map_err(|e| format!("{}: {e}", log_dir.display()))?;
    let list = log_dir.join("changed-specs.txt");
    let text: String = changed
        .iter()
        .map(|p| format!("{}\n", p.display()))
        .collect();
    std::fs::write(&list, text).map_err(|e| format!("{}: {e}", list.display()))?;
    let out = Command::new("python3")
        .arg("-c")
        .arg(DRIVER)
        .arg(&inputs.package_builder)
        .arg(&inputs.common_specs)
        .arg(release_specs)
        .arg(&inputs.build_config)
        .arg(log_dir)
        .arg(&list)
        // SpecData resolves some paths relative to its own directory
        .current_dir(&inputs.package_builder)
        .output()
        .map_err(|e| format!("running python3: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if stdout.contains("SPECCHECK-FAILED") {
        return Err(checker_errors(&format!("{stdout}\n{stderr}")));
    }
    if out.status.success() && stdout.contains("SPECCHECK-OK") {
        if let Some(n) = stdout
            .lines()
            .find_map(|l| l.strip_prefix("SPECDATA-OK "))
            .and_then(|n| n.trim().parse::<usize>().ok())
        {
            return Ok(n);
        }
    }
    Err(builder_error(&stdout, &stderr))
}

/// The spec checker's own error lines ("ERROR in <spec>: ...").
pub fn checker_errors(stdout: &str) -> String {
    let errs: Vec<&str> = stdout
        .lines()
        .map(str::trim)
        .filter(|l| l.starts_with("ERROR in ") || l.starts_with("--- List of errors"))
        .collect();
    if errs.is_empty() {
        "the spec checker failed (build.py's check_spec_files would stop the build)".into()
    } else {
        format!("the spec checker refuses it: {}", errs.join(" | "))
    }
}

/// The line that says what went wrong: the exception message at the end of
/// the traceback, or the last non-empty line when there is none.
pub fn builder_error(stdout: &str, stderr: &str) -> String {
    let all: Vec<&str> = stderr
        .lines()
        .chain(stdout.lines())
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();
    all.iter()
        .rev()
        .find(|l| l.starts_with("Exception:") || l.contains("Error:") || l.contains("ERROR"))
        .or(all.last())
        .map(|l| l.to_string())
        .unwrap_or_else(|| "the spec parser failed without a message".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_builders_exception_is_what_is_reported() {
        let stderr = "Traceback (most recent call last):\n  File \"x\", line 1\n    raise Exception(...)\nException: ERROR: What package provides /usr/bin/tar ? Used in 'dovecot' spec.\n";
        assert_eq!(
            builder_error("", stderr),
            "Exception: ERROR: What package provides /usr/bin/tar ? Used in 'dovecot' spec."
        );
        assert_eq!(builder_error("", ""), "the spec parser failed without a message");
    }

    #[test]
    fn a_build_root_without_the_package_builder_is_an_error_not_a_pass() {
        let t = std::env::temp_dir().join(format!("shk-specdata-{}", std::process::id()));
        let _ = std::fs::create_dir_all(t.join("SPECS"));
        let i = Inputs::from_build_root(&t, "common", "5.0");
        let r = check(&i, &t.join("SPECS"), &[], &t.join("logs"));
        assert!(r.unwrap_err().contains("cannot run the package builder's spec parser"));
        let _ = std::fs::remove_dir_all(&t);
    }

    #[test]
    fn the_dependency_drivers_lines_are_read_only_after_it_finished() {
        let out = "UNBUILT docker 29.8.0-3.ph5 minimal-5.0-9.ph5\nDEPS-OK 12\n";
        assert_eq!(
            parse_unbuilt(out).unwrap(),
            vec![Unbuilt {
                spec: "docker".into(),
                version: "29.8.0-3.ph5".into(),
                needed_by: "minimal-5.0-9.ph5".into(),
            }]
        );
        assert!(parse_unbuilt("UNBUILT docker 29.8.0-3.ph5 minimal-5.0-9.ph5\n").is_none());
        assert!(parse_unbuilt("UNBUILT a b c d\nDEPS-OK 1\n").unwrap().is_empty());
    }

    /// Against the real gate build root and 5.0: with only minimal's RPMs in
    /// the stage, the requirements of the already-built minimal are named
    /// (docker among them, the gate-70 failure); with no RPM at all minimal
    /// is the builder's to build and nothing is named.
    #[test]
    fn an_already_built_packages_unbuilt_requirement_is_named() {
        let root = Path::new("/root/photon-mc/gate/build-root");
        let repo = Path::new("/root/photon-mc/gate/photon.git");
        let i = Inputs::from_build_root(root, "common", "5.0");
        if i.missing().is_some() || !repo.is_dir() {
            return;
        }
        let t = std::env::temp_dir().join(format!("shk-specdeps-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&t);
        std::fs::create_dir_all(&t).unwrap();
        let ok = Command::new("sh")
            .arg("-c")
            .arg(format!(
                "git --git-dir={} archive 5.0 SPECS | tar -x -C {} --exclude='*.patch' --exclude='*.tar.*' --exclude='*.tgz' --exclude='*.zip'",
                repo.display(),
                t.display()
            ))
            .status()
            .unwrap();
        assert!(ok.success());
        let spec = std::fs::read_to_string(t.join("SPECS/minimal/minimal.spec")).unwrap();
        let v = crate::specresolve::field(&spec, "Version:").unwrap();
        let r = crate::specresolve::field(&spec, "Release:").unwrap();
        let r = r.trim_end_matches("%{?dist}");
        let cfg: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&i.build_config).unwrap()).unwrap();
        let dist = cfg["photon-build-param"]["photon-dist-tag"].as_str().unwrap();
        let arch = std::env::consts::ARCH;
        let rpms = t.join("RPMS");
        std::fs::create_dir_all(rpms.join(arch)).unwrap();
        let roots = vec!["minimal".to_string()];
        let logs = t.join("logs");
        let none = unbuilt_runtime_deps(&i, &t.join("SPECS"), &rpms, &roots, &[], &logs).unwrap();
        assert!(none.is_empty(), "{none:?}");
        std::fs::write(rpms.join(arch).join(format!("minimal-{v}-{r}{dist}.{arch}.rpm")), "").unwrap();
        let some = unbuilt_runtime_deps(&i, &t.join("SPECS"), &rpms, &roots, &[], &logs).unwrap();
        let docker = some.iter().find(|u| u.spec == "docker").unwrap_or_else(|| panic!("{some:?}"));
        assert_eq!(docker.needed_by, format!("minimal-{v}-{r}{dist}"));
        let bad = unbuilt_runtime_deps(&i, &t.join("SPECS"), &rpms, &["zz-no-such".into()], &[], &logs)
            .unwrap_err();
        assert!(bad.contains("zz-no-such is listed for the image but no spec builds it"), "{bad}");
        let _ = std::fs::remove_dir_all(&t);
    }

    /// Against the real gate build root and the gate repository's 5.0, when
    /// this host has them: the 5.0 specs plus a probe parse, and the probe
    /// requiring a path no spec provides fails with the builder's own words -
    /// the gate-49 failure, reproduced.
    #[test]
    fn the_real_parser_refuses_a_requirement_no_spec_provides() {
        let root = Path::new("/root/photon-mc/gate/build-root");
        let repo = Path::new("/root/photon-mc/gate/photon.git");
        let i = Inputs::from_build_root(root, "common", "5.0");
        if i.missing().is_some() || !repo.is_dir() {
            return;
        }
        let t = std::env::temp_dir().join(format!("shk-specdata-real-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&t);
        std::fs::create_dir_all(&t).unwrap();
        // the spec side of 5.0: everything but patches and archives
        let ok = Command::new("sh")
            .arg("-c")
            .arg(format!(
                "git --git-dir={} archive 5.0 SPECS | tar -x -C {} --exclude='*.patch' --exclude='*.tar.*' --exclude='*.tgz' --exclude='*.zip'",
                repo.display(),
                t.display()
            ))
            .status()
            .unwrap();
        assert!(ok.success());
        let specs = t.join("SPECS/zz-probe");
        std::fs::create_dir_all(&specs).unwrap();
        let spec = |req: &str| {
            format!(
                "Summary: probe\nName: zz-probe\nVersion: 1\nRelease: 1%{{?dist}}\nLicense: MIT\nGroup: x\nVendor: x\nDistribution: x\nURL: http://x\n{req}\n%description\nprobe\n%files\n%changelog\n* Sat Oct 03 2026 x <x@x> 1-1\n- probe\n"
            )
        };
        let logs = t.join("logs");
        std::fs::write(specs.join("zz-probe.spec"), spec("Requires: (tar or toybox)")).unwrap();
        let ok = check(&i, &t.join("SPECS"), &[], &logs);
        assert!(ok.is_ok(), "{ok:?}");
        std::fs::write(
            specs.join("zz-probe.spec"),
            spec("Requires: /usr/bin/zz-no-such-file"),
        )
        .unwrap();
        let bad = check(&i, &t.join("SPECS"), &[], &logs).unwrap_err();
        assert!(
            bad.contains("What package provides /usr/bin/zz-no-such-file"),
            "{bad}"
        );
        // the checker: a real 5.0 spec passes it; one whose license the
        // checker cannot validate stops the build exactly as build.py would
        std::fs::write(specs.join("zz-probe.spec"), spec("Requires: bash")).unwrap();
        let bash = t.join("SPECS/bash/bash.spec");
        let ok = check(&i, &t.join("SPECS"), &[bash], &logs);
        assert!(ok.is_ok(), "{ok:?}");
        let lic = t.join("SPECS/bash/license.txt");
        let text = std::fs::read_to_string(&lic).unwrap_or_default();
        let bad_lic = if text.contains("License:") {
            std::fs::write(&lic, "License: ZZ-Not-A-License-Key\n").unwrap();
            true
        } else {
            false
        };
        if bad_lic {
            let bad = check(&i, &t.join("SPECS"), &[t.join("SPECS/bash/bash.spec")], &logs)
                .unwrap_err();
            assert!(bad.contains("ZZ-Not-A-License-Key"), "{bad}");
        }
        let _ = std::fs::remove_dir_all(&t);
    }
}
