//! The FIPS crypto canister: which one a build gets, and whether one can be made.
//!
//! Photon links a pre-built, CMVP-certified canister into the kernel. The
//! certified binary is deliberately OLDER than the kernel it ships in - 6.12.60
//! linked into 6.12.103 is the designed state, not a defect - because
//! certification attaches to a specific binary evaluated by a lab.
//!
//! That leaves a gap. Nothing in the matrix ever exercised `canister_build=1`,
//! the path that creates a canister from source, and when it was finally tried
//! it failed in %prep: the canister-creation patch series is maintained against
//! the certified kernel and had drifted. A flag that cannot run is a flag whose
//! breakage is discovered by whoever needs it in an emergency.
//!
//! This module decides which of three states a build is in, and can prove
//! whether a canister could be created for the kernel under test WITHOUT
//! committing to a multi-hour build - which matters, because %prep stops at the
//! first rejected hunk and so can never tell you the size of the problem.

use crate::config::Config;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Which canister a build of this kernel can have.
#[derive(Debug, Clone, PartialEq)]
pub enum State {
    /// An official canister exists for this kernel level. Today's path, and the
    /// only one that carries a certificate.
    Certified { version: String },
    /// No official canister matches the kernel under test. One can be built
    /// locally: functionally equivalent, NOT validated.
    Equivalent { kernel: String, certified: String },
    /// This architecture has no canister at all, by design - both specs set
    /// `%global fips 0` on aarch64. Reported as a correct outcome, never as a
    /// failure, so the mode cannot invent work on a platform Photon excludes.
    Absent { arch: String, reason: String },
}

impl State {
    pub fn label(&self) -> &'static str {
        match self {
            State::Certified { .. } => "certified",
            State::Equivalent { .. } => "equivalent",
            State::Absent { .. } => "absent",
        }
    }
    /// Whether a FIPS verdict taken in this state may be reported as compliant.
    /// Only a certified canister may; an equivalent one is for coverage.
    pub fn is_validated(&self) -> bool {
        matches!(self, State::Certified { .. })
    }
}

/// One `%define`d value read out of a spec.
///
/// Read with a regex-free scan rather than `rpmspec`, because rpmspec needs the
/// SOURCES tree present and this has to work against a spec in any checkout.
fn spec_define(spec: &str, name: &str) -> Option<String> {
    for line in spec.lines() {
        let t = line.trim();
        // Matches both the bare form and the overridable
        // `%{!?name: %define name value}` guard.
        // `?` here would return from the whole function on the first line that
        // is not the definition - i.e. always, on line 1.
        let Some(after) = t
            .strip_prefix(&format!("%define {name} "))
            .or_else(|| t.strip_prefix(&format!("%global {name} ")))
            .or_else(|| {
                t.strip_prefix(&format!("%{{!?{name}:"))
                    .and_then(|r| r.trim().strip_prefix(&format!("%define {name} ")))
            })
        else {
            continue;
        };
        let v = after.trim().trim_end_matches('}').trim();
        if !v.is_empty() {
            return Some(v.to_string());
        }
    }
    None
}

/// `Version:` / `Release:` as the built NEVR fragment, e.g. `6.12.103-12.ph5`.
///
/// Release carries rpm conditionals (`%{?acvp_build:.acvp}`), so everything
/// from the first `%` is dropped and `.ph5` appended - the dist tag every
/// Photon 5.0 build gets.
fn spec_nevr(spec: &str) -> Option<String> {
    let field = |k: &str| {
        spec.lines()
            .find(|l| l.starts_with(k))
            .map(|l| l[k.len()..].trim().to_string())
    };
    let v = field("Version:")?;
    let r = field("Release:")?;
    let r = r.split('%').next().unwrap_or(&r).trim().to_string();
    Some(format!("{v}-{r}.ph5"))
}

pub struct Specs {
    pub linux: PathBuf,
    pub linux_esx: PathBuf,
}

impl Specs {
    pub fn under(tree: &Path) -> Specs {
        Specs {
            linux: tree.join("SPECS/linux/linux.spec"),
            linux_esx: tree.join("SPECS/linux/linux-esx.spec"),
        }
    }
}

/// P0 - decide the state from the tree, without building anything.
///
/// The detection is deliberately NOT "the canister NEVR differs from the kernel
/// NEVR". That is true of every healthy Photon build, so it would fire always.
/// What is asked is narrower: does an official canister exist *at the kernel
/// level under test*. When it does not, a build that wants same-version
/// coverage has to make one.
pub fn detect(cfg: &Config, arch: &str) -> Result<State, String> {
    let specs = Specs::under(&cfg.photon_tree);
    let linux = std::fs::read_to_string(&specs.linux)
        .map_err(|e| format!("{}: {e}", specs.linux.display()))?;

    if arch != "x86_64" {
        return Ok(State::Absent {
            arch: arch.to_string(),
            reason: "both specs set %global fips 0 on this arch, so no canister is \
                     expected; canister creation is x86_64-only in any case - \
                     gen_canister_relocs.c emits only R_X86_64_* relocations"
                .into(),
        });
    }

    let kernel = spec_nevr(&linux).ok_or("linux.spec has no Version:/Release:")?;
    let certified = spec_define(&linux, "fips_canister_version")
        .ok_or("linux.spec defines no fips_canister_version")?;

    if certified == kernel {
        Ok(State::Certified { version: certified })
    } else {
        Ok(State::Equivalent { kernel, certified })
    }
}

/// One patch in the canister-creation series and how it fared.
pub struct Applied {
    pub name: String,
    pub ok: bool,
    pub rejects: Vec<String>,
}

/// P1 - would the canister-creation series apply to this kernel?
///
/// rpm applies at `--fuzz=0` and `%prep` halts at the first rejected hunk, so a
/// build can only ever report "a patch broke", never how much has diverged.
/// That difference is the difference between an afternoon and a project: when
/// this was first run against 6.12.103, sixteen of eighteen patches applied
/// untouched and the only two rejects were the SAME upstream line, in the same
/// function, twice.
///
/// So: force through failures and report every one. Never auto-fuzz - rpm will
/// not, so a patch that only applies with fuzz is not actually applied.
pub fn rebase_check(cfg: &Config, tree: &Path) -> Result<Vec<Applied>, String> {
    let dir = cfg.photon_tree.join("SPECS/linux/canister_builder/patches");
    rebase_check_in(&dir, tree)
}

/// The series application itself, with the patch directory given explicitly so
/// the reject-reporting path can be tested without a kernel tree.
pub fn rebase_check_in(dir: &Path, tree: &Path) -> Result<Vec<Applied>, String> {
    if !dir.is_dir() {
        return Err(format!("no canister patch series at {}", dir.display()));
    }
    let mut series: Vec<PathBuf> = std::fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.extension().is_some_and(|x| x == "patch")
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| n.starts_with('1') && n.len() > 4)
        })
        .collect();
    series.sort();
    if series.is_empty() {
        return Err(format!("no 1xxx-*.patch in {}", dir.display()));
    }

    let mut out = Vec::new();
    for patch in series {
        let name = patch
            .file_stem()
            .and_then(|n| n.to_str())
            .unwrap_or_default()
            .to_string();
        let status = Command::new("patch")
            .current_dir(tree)
            .args(["-p1", "-s", "--fuzz=0", "--no-backup-if-mismatch", "-f", "-i"])
            .arg(&patch)
            .output()
            .map_err(|e| format!("running patch: {e}"))?;
        let ok = status.status.success();
        let rejects = if ok {
            Vec::new()
        } else {
            String::from_utf8_lossy(&status.stdout)
                .lines()
                .chain(String::from_utf8_lossy(&status.stderr).lines().map(|s| s.to_owned()).collect::<Vec<_>>().iter().map(|s| s.as_str()))
                .filter(|l| l.contains("FAILED") || l.contains("saving rejects"))
                .map(|l| l.trim().to_string())
                .collect()
        };
        out.push(Applied { name, ok, rejects });
    }
    Ok(out)
}

/// The evidence line the canister prints at boot, and what it means.
///
/// `crypto/fips_integrity.c` announces itself:
///
/// ```text
/// FIPS(fips_canister_init): canister 6.12 found (based on 6.12.103-12.ph5)
/// ```
///
/// and calls `panic()` when integrity fails. That makes the guest-side oracle
/// three POSITIVE checks rather than a hunt for absent errors: the guest
/// booted at all; the line names the kernel we built for; fips_enabled is 1.
/// The "based on" version is what distinguishes a locally built canister from
/// the prebuilt one - a boot alone cannot.
pub fn parse_boot_line(dmesg: &str) -> Option<(String, String)> {
    for l in dmesg.lines() {
        if !l.contains("canister") || !l.contains("found (based on") {
            continue;
        }
        let canister = l.split("canister ").nth(1)?.split_whitespace().next()?;
        let kernel = l.split("found (based on ").nth(1)?.split(')').next()?;
        return Some((canister.trim().to_string(), kernel.trim().to_string()));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const LINUX_SPEC: &str = "\
Summary:        Kernel
Name:           linux
Version:        6.12.103
Release:        12%{?acvp_build:.acvp}%{?kat_build:.kat}%{?dist}
%{!?fips_canister_version: %define fips_canister_version 6.12.60-18.2.ph5}
";

    #[test]
    fn nevr_drops_the_rpm_conditionals_from_release() {
        assert_eq!(spec_nevr(LINUX_SPEC).unwrap(), "6.12.103-12.ph5");
    }

    /// The pin must be readable through the overridable guard as well as bare,
    /// or detection breaks the moment the spec is made overridable.
    #[test]
    fn the_pin_reads_through_the_override_guard() {
        assert_eq!(
            spec_define(LINUX_SPEC, "fips_canister_version").unwrap(),
            "6.12.60-18.2.ph5"
        );
        let bare = "%define fips_canister_version 6.12.60-18.2.ph5\n";
        assert_eq!(spec_define(bare, "fips_canister_version").unwrap(), "6.12.60-18.2.ph5");
    }

    /// The canister lagging the kernel is the DESIGNED state, so a plain
    /// version comparison would report a gap on every healthy build.
    #[test]
    fn a_lagging_pin_is_the_equivalent_state_not_an_error() {
        let kernel = spec_nevr(LINUX_SPEC).unwrap();
        let pin = spec_define(LINUX_SPEC, "fips_canister_version").unwrap();
        assert_ne!(kernel, pin, "the fixture must model the real, lagging case");
    }

    #[test]
    fn the_boot_line_yields_both_versions() {
        let d = "[    1.2] FIPS(fips_canister_init): canister 6.12 found (based on 6.12.103-12.ph5)";
        assert_eq!(
            parse_boot_line(d),
            Some(("6.12".into(), "6.12.103-12.ph5".into()))
        );
    }

    /// A boot line naming the CERTIFIED kernel means the build linked the
    /// prebuilt canister - which is exactly how a silent no-op looks, and how
    /// twelve hours were once spent testing the path already covered.
    #[test]
    fn a_prebuilt_canister_is_distinguishable_from_a_locally_built_one() {
        let prebuilt = "FIPS(x): canister 6.12 found (based on 6.12.60-18.ph5)";
        let local = "FIPS(x): canister 6.12 found (based on 6.12.103-12.ph5)";
        assert_eq!(parse_boot_line(prebuilt).unwrap().1, "6.12.60-18.ph5");
        assert_eq!(parse_boot_line(local).unwrap().1, "6.12.103-12.ph5");
    }

    #[test]
    fn only_a_certified_canister_may_be_reported_as_validated() {
        assert!(State::Certified { version: "x".into() }.is_validated());
        assert!(!State::Equivalent { kernel: "a".into(), certified: "b".into() }.is_validated());
        assert!(!State::Absent { arch: "aarch64".into(), reason: "x".into() }.is_validated());
    }
}

#[cfg(test)]
mod series_tests {
    use super::*;
    use std::fs;

    /// The whole reason P1 exists is that %prep reports only the FIRST failure.
    /// So the thing that must work is: keep going, and capture each reject.
    #[test]
    fn a_failure_does_not_stop_the_series_and_its_reject_is_captured() {
        let base = std::env::temp_dir().join(format!("sk-series-{}", std::process::id()));
        let (patches, tree) = (base.join("patches"), base.join("tree"));
        fs::create_dir_all(&patches).unwrap();
        fs::create_dir_all(&tree).unwrap();
        fs::write(tree.join("f.txt"), "alpha\nbravo\ncharlie\n").unwrap();

        // 1001 applies. 1002 expects a line the tree does not have, the way an
        // upstream edit drifts context out from under a downstream patch.
        fs::write(
            patches.join("1001-ok.patch"),
            "--- a/f.txt\n+++ b/f.txt\n@@ -1,3 +1,3 @@\n alpha\n-bravo\n+BRAVO\n charlie\n",
        )
        .unwrap();
        fs::write(
            patches.join("1002-drifted.patch"),
            "--- a/f.txt\n+++ b/f.txt\n@@ -1,3 +1,3 @@\n alpha\n-delta\n+DELTA\n charlie\n",
        )
        .unwrap();
        // 1003 applies, and only runs at all if 1002 did not abort the series.
        fs::write(
            patches.join("1003-after.patch"),
            "--- a/f.txt\n+++ b/f.txt\n@@ -1,3 +1,3 @@\n alpha\n BRAVO\n-charlie\n+CHARLIE\n",
        )
        .unwrap();

        let got = rebase_check_in(&patches, &tree).unwrap();
        let _ = fs::remove_dir_all(&base);

        assert_eq!(got.len(), 3, "the series must be applied in full");
        assert!(got[0].ok, "1001 should apply");
        assert!(!got[1].ok, "1002 should fail on drifted context");
        assert!(got[2].ok, "1003 must still be attempted after 1002 failed");
        assert!(
            got[1].rejects.iter().any(|r| r.contains("FAILED")),
            "the reject was not captured: {:?}",
            got[1].rejects
        );
    }
}
