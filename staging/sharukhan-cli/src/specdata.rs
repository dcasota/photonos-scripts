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
pb, common_specs, release_specs, cfg, logdir = sys.argv[1:6]
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
"#;

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

/// Parse `release_specs` with the package builder's SpecData. Ok with the
/// number of specs parsed; Err with the builder's own error line.
pub fn check(inputs: &Inputs, release_specs: &Path, log_dir: &Path) -> Result<usize, String> {
    if let Some(m) = inputs.missing() {
        return Err(format!("cannot run the package builder's spec parser: {m}"));
    }
    if !release_specs.is_dir() {
        return Err(format!("{} is not a directory", release_specs.display()));
    }
    let out = Command::new("python3")
        .arg("-c")
        .arg(DRIVER)
        .arg(&inputs.package_builder)
        .arg(&inputs.common_specs)
        .arg(release_specs)
        .arg(&inputs.build_config)
        .arg(log_dir)
        // SpecData resolves some paths relative to its own directory
        .current_dir(&inputs.package_builder)
        .output()
        .map_err(|e| format!("running python3: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if out.status.success() {
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
        let r = check(&i, &t.join("SPECS"), &t.join("logs"));
        assert!(r.unwrap_err().contains("cannot run the package builder's spec parser"));
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
        let ok = check(&i, &t.join("SPECS"), &logs);
        assert!(ok.is_ok(), "{ok:?}");
        std::fs::write(
            specs.join("zz-probe.spec"),
            spec("Requires: /usr/bin/zz-no-such-file"),
        )
        .unwrap();
        let bad = check(&i, &t.join("SPECS"), &logs).unwrap_err();
        assert!(
            bad.contains("What package provides /usr/bin/zz-no-such-file"),
            "{bad}"
        );
        let _ = std::fs::remove_dir_all(&t);
    }
}
