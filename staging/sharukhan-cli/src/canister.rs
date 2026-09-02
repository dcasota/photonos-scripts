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
    /// The published repo could not be reached, so which state applies is
    /// unknown. Deliberately NOT folded into Equivalent: "build one locally"
    /// and "we could not look" are different claims, and only the first is a
    /// reason to spend hours building a canister.
    Unknown { kernel: String, reason: String },
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
            State::Unknown { .. } => "unknown",
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
///
/// Only the tests read it now - production reads the pin through the variant
/// patch instead, which is the kernel a build actually produces. Kept because
/// it is what the tests use to assert the pin in the shipped spec.
#[cfg(test)]
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

/// The newest `linux-fips-canister-*` published for this release, as a NEVR
/// fragment like `6.12.60-18.ph5`.
///
/// This — not the spec's `%define` — is what decides whether a canister has to
/// be built. The spec pin answers "what does this spec ask for", which is a
/// different question and can be unsatisfiable: on 2026-09-02 both specs pinned
/// `6.12.60-18.2.ph5` while the repo published only `6.12.60-18.ph5`, so a
/// build that actually had to recompile the kernel could not resolve its
/// BuildRequires at all.
///
/// Returns Ok(None) when the repo is reachable and simply has no canister.
pub fn published(release: &str) -> Result<Option<String>, String> {
    let url = format!(
        "https://packages.broadcom.com/artifactory/photon/{release}/\
photon_updates_{release}_x86_64/x86_64/"
    );
    let out = Command::new("curl")
        .args(["-s", "-f", "--max-time", "60", &url])
        .output()
        .map_err(|e| format!("running curl: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "{url}: curl exited {}",
            out.status.code().unwrap_or(-1)
        ));
    }
    let body = String::from_utf8_lossy(&out.stdout);
    let mut found: Vec<String> = body
        .split(|c| c == '"' || c == '<' || c == '>' || c == ' ')
        .filter_map(parse_canister_rpm)
        .collect();
    found.sort();
    found.dedup();
    Ok(found.pop())
}

/// `linux-fips-canister-6.12.60-18.ph5.x86_64.rpm` -> `6.12.60-18.ph5`.
///
/// Anchored on the full package name so `linux-fips-canister-debuginfo-...`
/// does not read as a canister; the arch and extension are stripped rather
/// than assumed, so a noarch build would still parse.
fn parse_canister_rpm(name: &str) -> Option<String> {
    let rest = name.trim().strip_prefix("linux-fips-canister-")?;
    if !rest.ends_with(".rpm") || !rest.starts_with(|c: char| c.is_ascii_digit()) {
        return None;
    }
    let rest = rest.trim_end_matches(".rpm");
    let rest = rest
        .strip_suffix(".x86_64")
        .or_else(|| rest.strip_suffix(".noarch"))
        .or_else(|| rest.strip_suffix(".aarch64"))
        .unwrap_or(rest);
    if rest.is_empty() {
        None
    } else {
        Some(rest.to_string())
    }
}

pub struct Specs {
    pub linux: PathBuf,
    /// Read by P4 (consume), which rebuilds this flavour against the canister
    /// linux produced. Detection only needs linux.spec: linux-esx never builds
    /// a canister, it only links one.
    #[allow(dead_code)]
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

/// Where a kernel version came from, so a mismatch can be named.
pub struct Provenance {
    /// What the build will actually compile: the tree with the variant patch
    /// applied. This is the version every canister decision must be about.
    pub effective: String,
    /// linux.spec on the operator's fork branch (origin/<release>).
    pub fork: Option<String>,
    /// linux.spec on the reference branch (vmware/<release>).
    pub upstream: Option<String>,
    /// Refs that could not be read, so a missing value is never mistaken for
    /// agreement.
    pub unread: Vec<String>,
}

impl Provenance {
    /// The fork has moved relative to the reference. Not an error - carrying
    /// patches is the point of a fork - but it means "the kernel under test" is
    /// downstream of upstream, and a canister decision taken here does not
    /// necessarily hold there.
    pub fn fork_differs(&self) -> bool {
        matches!((&self.fork, &self.upstream), (Some(f), Some(u)) if f != u)
    }
}

fn nevr_at(tree: &Path, git_ref: &str) -> Option<String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(tree)
        .args(["show", &format!("{git_ref}:SPECS/linux/linux.spec")])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    spec_nevr(&String::from_utf8_lossy(&out.stdout))
}

/// Read the kernel version from the tree, the fork and the reference.
///
/// `effective` is passed in rather than read, because the version that matters
/// is the one the variant patch produces - the pristine tree is a different
/// kernel and answering for it would decide the canister question about
/// something nobody is building.
pub fn provenance(cfg: &Config, effective: String) -> Provenance {
    let mut unread = Vec::new();
    let fork_ref = format!("origin/{}", cfg.release);
    let up_ref = format!("vmware/{}", cfg.release);
    let fork = nevr_at(&cfg.photon_tree, &fork_ref);
    if fork.is_none() {
        unread.push(fork_ref);
    }
    let upstream = nevr_at(&cfg.photon_tree, &up_ref);
    if upstream.is_none() {
        unread.push(up_ref);
    }
    Provenance { effective, fork, upstream, unread }
}

/// P0 - decide the state from the tree, without building anything.
///
/// The detection is deliberately NOT "the canister NEVR differs from the kernel
/// NEVR". That is true of every healthy Photon build, so it would fire always.
/// What is asked is narrower: does an official canister exist *at the kernel
/// level under test*. When it does not, a build that wants same-version
/// coverage has to make one.
pub fn detect(cfg: &Config, arch: &str) -> Result<State, String> {
    detect_for(cfg, arch, None)
}

/// As `detect`, for a kernel NEVR the caller already knows.
///
/// A build applies a variant patch before compiling, and that patch is what
/// sets Release - so the pristine tree answers for a kernel that is not the one
/// being built. Whoever knows the real NEVR must pass it, or the decision is
/// made about the wrong kernel.
pub fn detect_for(cfg: &Config, arch: &str, kernel: Option<&str>) -> Result<State, String> {
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

    let kernel = match kernel {
        Some(k) => k.to_string(),
        None => spec_nevr(&linux).ok_or("linux.spec has no Version:/Release:")?,
    };

    // Ask the REPO, not the spec. The spec's %define says what this spec wants
    // to link; it does not say whether such a canister exists, and the two have
    // drifted - the pin was 6.12.60-18.2.ph5 while the repo published only
    // 6.12.60-18.ph5. Phase A is needed exactly when nothing published matches
    // the kernel under test, so that is the comparison to make.
    match published(&cfg.release) {
        Ok(Some(pubv)) if pubv == kernel => Ok(State::Certified { version: pubv }),
        Ok(Some(pubv)) => Ok(State::Equivalent { kernel, certified: pubv }),
        Ok(None) => Ok(State::Equivalent {
            kernel,
            certified: "none published".into(),
        }),
        // Never guess. Falling back to the spec pin here would let a network
        // blip turn "certified" into "spend twelve hours building a canister",
        // or the reverse, with nothing in the output to say which happened.
        Err(e) => Ok(State::Unknown { kernel, reason: e }),
    }
}

/// What a build has to do to reach a canister at the kernel level under test.
///
/// Phase A is CONDITIONAL: it exists only to make a canister that is not
/// published. When one is published at the right level there is nothing to
/// build, and linking it keeps the result certified rather than merely
/// equivalent.
#[derive(Debug, Clone, PartialEq)]
pub enum Plan {
    /// Link the published canister. One build, and it stays validated.
    LinkPublished { version: String },
    /// A locally built equivalent already exists at this kernel level. Link it
    /// and skip phase A: rebuilding it would spend ~90 minutes reproducing an
    /// artifact that is already on disk, byte for byte the same inputs.
    LinkLocalEquivalent { version: String, path: String },
    /// Build a canister from this kernel, then relink both flavours against it.
    BuildThenLink { version: String },
    /// Nothing to do - this architecture has no canister by design.
    Nothing { reason: String },
    /// Refuse to plan. The state could not be determined.
    Refuse { reason: String },
}

pub fn plan(state: &State) -> Plan {
    plan_with_local(state, None)
}

/// The decision, in the order the question is actually asked:
///
///   1. Does Broadcom publish a canister for the kernel being built? Link it.
///      The build stays CMVP validated and nothing local is involved.
///   2. Not published, but is there already a locally built equivalent at that
///      exact NEVR? Link that. Phase A would spend ~90 minutes reproducing an
///      artifact that is already on disk from the same inputs.
///   3. Neither? Build one (phase A), then relink both flavours against it
///      (phase B).
///
/// Only 3 costs the extra build, and only 2 and 3 are NOT CMVP validated.
/// `local` is the canister found in the stage, if any.
pub fn plan_with_local(state: &State, local: Option<(&str, &str)>) -> Plan {
    match state {
        State::Certified { version } => Plan::LinkPublished { version: version.clone() },
        State::Equivalent { kernel, .. } => match local {
            Some((nevr, path)) if nevr == kernel => Plan::LinkLocalEquivalent {
                version: kernel.clone(),
                path: path.to_string(),
            },
            _ => Plan::BuildThenLink { version: kernel.clone() },
        },
        State::Absent { reason, .. } => Plan::Nothing { reason: reason.clone() },
        State::Unknown { reason, .. } => Plan::Refuse { reason: reason.clone() },
    }
}

/// The newest locally built canister in the stage, as (NEVR, path).
///
/// Deliberately anchored: `linux-fips-canister-debuginfo-...` is a different
/// package and must not be mistaken for the canister itself.
pub fn local_canister(stage: &std::path::Path, kernel: &str) -> Option<(String, String)> {
    let want = format!("linux-fips-canister-{kernel}.");
    crate::build::find_files_rec(stage, "linux-fips-canister-", ".rpm")
        .into_iter()
        .find(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with(&want))
                .unwrap_or(false)
        })
        .map(|p| (kernel.to_string(), p.display().to_string()))
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

    /// The repo listing is HTML, and it contains names that merely start the
    /// same way. A canister is the exact package, at a version, for an arch.
    #[test]
    fn only_a_real_canister_rpm_parses_as_one() {
        assert_eq!(
            parse_canister_rpm("linux-fips-canister-6.12.60-18.ph5.x86_64.rpm").as_deref(),
            Some("6.12.60-18.ph5")
        );
        assert_eq!(
            parse_canister_rpm("linux-fips-canister-6.12.103-13.ph5.noarch.rpm").as_deref(),
            Some("6.12.103-13.ph5")
        );
        // Not canisters.
        assert!(parse_canister_rpm("linux-fips-canister-debuginfo-6.12.60-18.ph5.x86_64.rpm").is_none());
        assert!(parse_canister_rpm("linux-6.12.103-13.ph5.x86_64.rpm").is_none());
        assert!(parse_canister_rpm("linux-fips-canister-6.12.60-18.ph5.x86_64.srpm").is_none());
        assert!(parse_canister_rpm("").is_none());
    }

    /// Phase A is conditional. This is the whole point: a canister published at
    /// the kernel level under test must be LINKED, not rebuilt - rebuilding it
    /// would throw away the certificate and spend hours doing it.
    #[test]
    fn a_published_canister_at_the_kernel_level_means_no_phase_a() {
        let st = State::Certified { version: "6.12.103-13.ph5".into() };
        assert_eq!(
            plan(&st),
            Plan::LinkPublished { version: "6.12.103-13.ph5".into() }
        );
        assert!(st.is_validated());
    }

    #[test]
    fn a_mismatched_publication_means_build_then_link() {
        let st = State::Equivalent {
            kernel: "6.12.103-13.ph5".into(),
            certified: "6.12.60-18.ph5".into(),
        };
        assert_eq!(
            plan(&st),
            Plan::BuildThenLink { version: "6.12.103-13.ph5".into() }
        );
        assert!(!st.is_validated());
    }

    /// The decision has to be about the kernel BEING BUILT. A variant patch
    /// sets Release, so the pristine tree answers for a different kernel - and
    /// the whole question is whether a canister exists at this one's level.
    #[test]
    fn the_comparison_uses_the_kernel_it_was_given() {
        // Same published canister, two different kernels under test: the
        // verdict must differ.
        let published = "6.12.60-18.ph5";
        let same = State::Certified { version: published.into() };
        assert!(same.is_validated());

        let differs = State::Equivalent {
            kernel: "6.12.103-14.ph5".into(),
            certified: published.into(),
        };
        assert!(!differs.is_validated());
        assert_eq!(
            plan(&differs),
            Plan::BuildThenLink { version: "6.12.103-14.ph5".into() }
        );
    }

    /// A fork that has moved relative to the reference must be reported. Not
    /// as an error - carrying patches is what a fork is for - but a verdict
    /// taken on the fork's kernel does not automatically hold upstream.
    #[test]
    fn a_fork_ahead_of_the_reference_is_flagged() {
        let same = Provenance {
            effective: "6.12.103-14.ph5".into(),
            fork: Some("6.12.103-11.ph5".into()),
            upstream: Some("6.12.103-11.ph5".into()),
            unread: vec![],
        };
        assert!(!same.fork_differs());

        let moved = Provenance {
            effective: "6.12.103-14.ph5".into(),
            fork: Some("6.12.103-12.ph5".into()),
            upstream: Some("6.12.103-11.ph5".into()),
            unread: vec![],
        };
        assert!(moved.fork_differs());
    }

    /// An unreadable ref must never read as agreement: "we could not compare"
    /// and "they match" are different answers.
    #[test]
    fn an_unreadable_ref_is_not_agreement() {
        let p = Provenance {
            effective: "6.12.103-14.ph5".into(),
            fork: Some("6.12.103-11.ph5".into()),
            upstream: None,
            unread: vec!["vmware/5.0".into()],
        };
        assert!(!p.fork_differs(), "unknown must not be reported as a difference");
        assert!(!p.unread.is_empty(), "but it must be reported as unread");
    }

    /// If a canister is later published at the kernel level under test, the
    /// SAME mode must stop building one. Phase A is a consequence of the repo,
    /// not a property of asking for --canister equivalent.
    #[test]
    fn publishing_a_matching_canister_removes_phase_a() {
        let before = State::Equivalent {
            kernel: "6.12.103-14.ph5".into(),
            certified: "6.12.60-18.ph5".into(),
        };
        let after = State::Certified { version: "6.12.103-14.ph5".into() };
        assert!(matches!(plan(&before), Plan::BuildThenLink { .. }));
        assert!(matches!(plan(&after), Plan::LinkPublished { .. }));
        assert!(!before.is_validated() && after.is_validated());
    }

    /// A network failure must not be readable as "build one". They are
    /// different claims and only one of them costs twelve hours.
    #[test]
    fn an_unreadable_repo_refuses_rather_than_guessing() {
        let st = State::Unknown {
            kernel: "6.12.103-13.ph5".into(),
            reason: "curl exited 6".into(),
        };
        assert!(matches!(plan(&st), Plan::Refuse { .. }));
        assert!(!st.is_validated());
        assert_eq!(st.label(), "unknown");
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

#[cfg(test)]
mod plan_tests {
    use super::*;

    /// The question, in the order it is actually asked. Only the third case
    /// costs a build, and getting case 2 wrong costs ~90 minutes reproducing
    /// an artifact that is already on disk.
    #[test]
    fn a_published_canister_wins_over_anything_local() {
        let st = State::Certified { version: "6.12.60-18.ph5".into() };
        // Even with a local equivalent present, a published canister is linked:
        // it is the one that keeps the build CMVP validated.
        match plan_with_local(&st, Some(("6.12.60-18.ph5", "/stage/x.rpm"))) {
            Plan::LinkPublished { version } => assert_eq!(version, "6.12.60-18.ph5"),
            other => panic!("published must win: {other:?}"),
        }
    }

    #[test]
    fn an_existing_local_equivalent_is_linked_instead_of_rebuilt() {
        let st = State::Equivalent {
            kernel: "6.12.103-14.ph5".into(),
            certified: "6.12.60-18.ph5".into(),
        };
        match plan_with_local(&st, Some(("6.12.103-14.ph5", "/stage/RPMS/x86_64/c.rpm"))) {
            Plan::LinkLocalEquivalent { version, path } => {
                assert_eq!(version, "6.12.103-14.ph5");
                assert!(path.ends_with("c.rpm"));
            }
            other => panic!("an existing local equivalent must be linked, not rebuilt: {other:?}"),
        }
    }

    /// A canister built from a DIFFERENT kernel is not a substitute. The whole
    /// claim of the equivalent mode is that the canister comes from the kernel
    /// under test, so a near-miss must still build.
    #[test]
    fn a_local_canister_from_another_kernel_does_not_count() {
        let st = State::Equivalent {
            kernel: "6.12.103-14.ph5".into(),
            certified: "6.12.60-18.ph5".into(),
        };
        for other in ["6.12.103-13.ph5", "6.12.60-18.ph5"] {
            match plan_with_local(&st, Some((other, "/stage/x.rpm"))) {
                Plan::BuildThenLink { version } => assert_eq!(version, "6.12.103-14.ph5"),
                p => panic!("{other} must not satisfy 6.12.103-14: {p:?}"),
            }
        }
    }

    #[test]
    fn nothing_published_and_nothing_local_means_build_it() {
        let st = State::Equivalent {
            kernel: "6.12.103-14.ph5".into(),
            certified: "6.12.60-18.ph5".into(),
        };
        match plan_with_local(&st, None) {
            Plan::BuildThenLink { version } => assert_eq!(version, "6.12.103-14.ph5"),
            other => panic!("{other:?}"),
        }
    }

    /// An unreadable published list is refused, never guessed. "Could not look"
    /// and "nothing is published" lead to opposite decisions, and one of them
    /// costs twelve hours.
    #[test]
    fn an_unreadable_published_list_is_refused_even_with_a_local_canister() {
        let st = State::Unknown { kernel: "6.12.103-14.ph5".into(), reason: "http 503".into() };
        assert!(matches!(
            plan_with_local(&st, Some(("6.12.103-14.ph5", "/stage/x.rpm"))),
            Plan::Refuse { .. }
        ));
    }
}
