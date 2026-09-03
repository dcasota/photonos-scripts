//! Build mode: one parameterised cascade in place of five drifting scripts.
//!
//! `runPh4.sh`, `runPh5_normal.sh`, `runPh5_pinned90.sh`, `runPh5_pinned91.sh`
//! and `runPh6.sh` are the same build with different accretions. Their fixups
//! diverge in a way that is not a decision:
//!
//! | fixup | Ph4 | Ph5n | Ph5p90 | Ph5p91 | Ph6 |
//! |---|---|---|---|---|---|
//! | openjdk / python3 / sssd | y | y | y | y | y |
//! | libcap stale-RPM | - | y | y | y | y |
//! | rpm 6.x removal | - | y | y | y | - |
//! | run-in-chroot fd 255 | - | y | y | - | - |
//! | createrepo_c repair | - | y | - | - | y |
//!
//! Every one of those is a property of the HOST or the TREE, not of the
//! release: `run-in-chroot.sh` closing fd 255 breaks a 4.0 build exactly as it
//! breaks a 5.0 one. The table is a record of which file someone was editing
//! that day.
//!
//! So a phase here never asks "which release is this". It asks "is the thing I
//! fix present on this host, in this tree" - and says so when the answer is no.
//! That is the property that stops the table above from growing back.
//!
//! The axes that genuinely vary are two: release (4.0|5.0|6.0) and subrelease
//! (mainline|90|91). `pinned90` and `pinned91` already differ only in a
//! variable.

use std::fmt;
use std::path::PathBuf;

/// Which tree a modification applies to.
///
/// The distinction is the whole reason this module exists. Photon keeps
/// per-release SPECS on `5.0`/`4.0`/`6.0` and shared build tooling on `common`,
/// and those histories never meet - `common` has no `SPECS/`, `5.0` has no
/// `support/package-builder/`. The variant-patch mechanism diffs
/// `origin/<release>..branch` and applies to `SPECS`, so it cannot carry a
/// change to the package builder at all. That is why the sans-snapshot fix
/// reaches a build only as a file that happens to be on disk.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tree {
    Release,
    Common,
}

impl Tree {
    pub fn as_str(&self) -> &'static str {
        match self {
            Tree::Release => "release",
            Tree::Common => "common",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Subrelease {
    Mainline,
    Pinned(u32),
}

impl fmt::Display for Subrelease {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Subrelease::Mainline => write!(f, "mainline"),
            Subrelease::Pinned(n) => write!(f, "{n}"),
        }
    }
}

/// `make image IMG_NAME=<this>`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImgType {
    Iso,
    MinimalIso,
    BasicIso,
    RtIso,
}

impl ImgType {
    pub fn parse(s: &str) -> Result<Self, String> {
        Ok(match s {
            "iso" => ImgType::Iso,
            "minimal-iso" => ImgType::MinimalIso,
            "basic-iso" => ImgType::BasicIso,
            "rt-iso" => ImgType::RtIso,
            other => {
                return Err(format!(
                    "unsupported image type '{other}'; valid: iso (full), \
                     minimal-iso, basic-iso, rt-iso"
                ))
            }
        })
    }
    pub fn as_str(&self) -> &'static str {
        match self {
            ImgType::Iso => "iso",
            ImgType::MinimalIso => "minimal-iso",
            ImgType::BasicIso => "basic-iso",
            ImgType::RtIso => "rt-iso",
        }
    }
}

/// The canister modes runPh5 accepts. `equivalent-a`/`-b` are the two phases of
/// a locally built canister and both require the NEVR it will carry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CanisterMode {
    Prebuilt,
    Build,
    Acvp,
    Kat,
    EquivalentA,
    EquivalentB,
}

impl CanisterMode {
    pub fn parse(s: &str) -> Result<Self, String> {
        Ok(match s {
            "prebuilt" => CanisterMode::Prebuilt,
            "build" => CanisterMode::Build,
            "acvp" => CanisterMode::Acvp,
            "kat" => CanisterMode::Kat,
            "equivalent-a" => CanisterMode::EquivalentA,
            "equivalent-b" => CanisterMode::EquivalentB,
            other => {
                return Err(format!(
                    "unsupported canister mode '{other}'; valid: prebuilt \
                     (default), build, acvp, kat, equivalent-a, equivalent-b"
                ))
            }
        })
    }
    pub fn as_str(&self) -> &'static str {
        match self {
            CanisterMode::Prebuilt => "prebuilt",
            CanisterMode::Build => "build",
            CanisterMode::Acvp => "acvp",
            CanisterMode::Kat => "kat",
            CanisterMode::EquivalentA => "equivalent-a",
            CanisterMode::EquivalentB => "equivalent-b",
        }
    }
    /// Phase A creates a canister and phase B links it; both have to be told
    /// which NEVR, because neither can derive it from a tree that has not been
    /// patched yet.
    pub fn needs_nevr(&self) -> bool {
        matches!(self, CanisterMode::EquivalentA | CanisterMode::EquivalentB)
    }
    /// `make linux` for phase A - one package, not an image. Phase A exists to
    /// produce `linux-fips-canister-<nevr>`, and building 700 packages to get
    /// it would be hours wasted.
    pub fn make_target(&self) -> &'static str {
        match self {
            CanisterMode::EquivalentA => "linux",
            _ => "image",
        }
    }
}

/// A modification sharukhan OWNS, compiled into the binary.
///
/// These are test-only: they have no destination in vmware/photon and are not
/// waiting on anyone's review. `canister_equivalent` exists so a kernel with no
/// published canister can be covered at all; upstream has no reason to carry a
/// switch whose only consumer is this harness. Keeping them here rather than on
/// a branch is what makes the tool monolithic - a fresh clone of
/// photonos-scripts can build an equivalent-canister ISO with no other
/// repository checked out at any particular revision.
///
/// They apply AFTER the variant patch, because they build on what the
/// upstream-bound PRs change. The variant patches carry only work that is
/// genuinely destined upstream; nothing test-only leaks into a PR.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Embedded {
    /// linux/linux-esx: make the linked canister version selectable, so a
    /// build can link one built from the kernel under test.
    CanisterEquivalent,
    /// package-builder: let a sans-snapshot BuildRequires resolve against the
    /// local repo, without which phase B cannot find the canister phase A just
    /// built.
    SansSnapshotLocalCanister,
}

impl Embedded {
    pub fn as_str(&self) -> &'static str {
        match self {
            Embedded::CanisterEquivalent => "canister-equivalent",
            Embedded::SansSnapshotLocalCanister => "sans-snapshot-local-canister",
        }
    }
    pub fn tree(&self) -> Tree {
        match self {
            Embedded::CanisterEquivalent => Tree::Release,
            Embedded::SansSnapshotLocalCanister => Tree::Common,
        }
    }
    /// The patch text, compiled in. No file to go missing, no branch to be on
    /// the wrong revision.
    pub fn patch(&self) -> &'static str {
        match self {
            Embedded::CanisterEquivalent => include_str!("embedded/canister-equivalent.patch"),
            Embedded::SansSnapshotLocalCanister => {
                include_str!("embedded/sans-snapshot-local-canister.patch")
            }
        }
    }
    /// Which canister modes need it. `prebuilt` links the published canister
    /// and needs neither, so a normal build is untouched by any of this.
    pub fn needed_for(mode: CanisterMode) -> Vec<Embedded> {
        match mode {
            CanisterMode::EquivalentA | CanisterMode::EquivalentB => {
                vec![Embedded::CanisterEquivalent, Embedded::SansSnapshotLocalCanister]
            }
            _ => vec![],
        }
    }
}

/// A tree modification applied before `make`, as data rather than as another
/// branch in a shell script.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Injection {
    /// Apply a patch to one of the two trees. `Tree::Common` is the case the
    /// old mechanism could not express at all.
    TreePatch { tree: Tree, patch: PathBuf },
    /// A modification compiled into sharukhan itself.
    Embed(Embedded),
    /// Pin `photon-subrelease` in the build config - the pinned90/91 behaviour,
    /// which was a whole separate script per value.
    PinSubrelease(u32),
    /// Canister macros into `pkg-build-options`.
    PkgBuildOptions { mode: CanisterMode, nevr: Option<String> },
    /// One of the host workarounds. Each carries its own precondition.
    SpecFixup(Fixup),
}

/// The workarounds the five scripts accumulated. Named after what they fix, so
/// a skipped one says something useful.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fixup {
    /// openjdk needs `--build` under WSL2 or configure misdetects the host.
    OpenJdkWsl2,
    /// python3 PGO training runs test_generators, which hangs on WSL2.
    Python3PgoTestGenerators,
    /// sssd's parallel %make_install races with itself.
    SssdSerialMakeInstall,
    /// run-in-chroot.sh closes fd 255, which is bash's own terminal fd.
    RunInChrootFd255,
    /// Consecutive blank lines make Photon's spec checker fail.
    SpecBlankLines,
}

impl Fixup {
    pub fn as_str(&self) -> &'static str {
        match self {
            Fixup::OpenJdkWsl2 => "openjdk-wsl2-build-flag",
            Fixup::Python3PgoTestGenerators => "python3-pgo-test-generators",
            Fixup::SssdSerialMakeInstall => "sssd-serial-make-install",
            Fixup::RunInChrootFd255 => "run-in-chroot-fd-255",
            Fixup::SpecBlankLines => "spec-consecutive-blank-lines",
        }
    }
    /// Which tree it edits. `RunInChrootFd255` is in the package builder, so it
    /// is a `common` edit - the same class as the sans-snapshot fix, and
    /// another thing the release-tree patch mechanism could never have carried.
    pub fn tree(&self) -> Tree {
        match self {
            Fixup::RunInChrootFd255 => Tree::Common,
            _ => Tree::Release,
        }
    }
}

/// Everything a build needs, resolved once, before anything is touched.
#[derive(Debug, Clone)]
pub struct BuildSpec {
    pub base_dir: PathBuf,
    pub common_branch: String,
    pub release: String,
    pub subrelease: Subrelease,
    pub output_dir: PathBuf,
    pub img: ImgType,
    pub canister: CanisterMode,
    pub canister_nevr: Option<String>,
    pub injections: Vec<Injection>,
}

impl BuildSpec {
    /// The positional contract the scripts share:
    /// `<base> <common> <release> <out> <img> <canister>`. Kept identical so a
    /// cascade invocation and a script invocation can be compared field by
    /// field during the parity stage.
    pub fn from_args(
        base_dir: &str,
        common_branch: &str,
        release: &str,
        output_dir: &str,
        img: &str,
        canister: &str,
        nevr: Option<String>,
    ) -> Result<Self, String> {
        let canister = CanisterMode::parse(canister)?;
        if canister.needs_nevr() && nevr.as_deref().unwrap_or("").is_empty() {
            return Err(format!(
                "{} needs MC_CANISTER_NEVR (the NEVR the locally built canister carries)",
                canister.as_str()
            ));
        }
        Ok(BuildSpec {
            base_dir: PathBuf::from(base_dir),
            common_branch: common_branch.to_string(),
            release: release.to_string(),
            subrelease: Subrelease::Mainline,
            output_dir: PathBuf::from(output_dir),
            img: ImgType::parse(img)?,
            canister,
            canister_nevr: nevr,
            injections: Vec::new(),
        })
    }

    pub fn tree(&self, t: Tree) -> PathBuf {
        match t {
            Tree::Release => self.base_dir.join(&self.release),
            Tree::Common => self.base_dir.join(&self.common_branch),
        }
    }

    /// The cascade this spec implies, in execution order.
    ///
    /// Built from the spec rather than hardcoded per release: that is the
    /// difference between one implementation and five that drift.
    pub fn cascade(&self) -> Vec<Stage> {
        let mut v = vec![Stage::Resolve, Stage::Sync, Stage::Reset];
        let _ = &v;
        for inj in &self.injections {
            v.push(Stage::Inject(inj.clone()));
        }
        v.push(Stage::Sources);
        v.push(Stage::Preflight);
        v.push(Stage::Purge);
        v.push(Stage::Make);
        v.push(Stage::Post);
        v
    }
}

/// One step of the cascade.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Stage {
    Resolve,
    Sync,
    Reset,
    Inject(Injection),
    /// Verify every declared source archive, fetching what is missing. After
    /// the injections, because a patch can add a source.
    Sources,
    Preflight,
    Purge,
    Make,
    Post,
}

impl Stage {
    pub fn name(&self) -> String {
        match self {
            Stage::Resolve => "resolve".into(),
            Stage::Sync => "sync".into(),
            Stage::Reset => "reset-specs".into(),
            Stage::Sources => "sources".into(),
            Stage::Preflight => "preflight".into(),
            Stage::Purge => "purge".into(),
            Stage::Make => "make".into(),
            Stage::Post => "post".into(),
            Stage::Inject(i) => match i {
                Injection::TreePatch { tree, patch } => format!(
                    "inject:patch[{}]:{}",
                    tree.as_str(),
                    patch.file_name().and_then(|s| s.to_str()).unwrap_or("?")
                ),
                Injection::Embed(e) => {
                    format!("inject:embedded[{}]:{}", e.tree().as_str(), e.as_str())
                }
                Injection::PinSubrelease(n) => format!("inject:subrelease[{n}]"),
                Injection::PkgBuildOptions { mode, .. } => {
                    format!("inject:pkg-build-options[{}]", mode.as_str())
                }
                Injection::SpecFixup(f) => {
                    format!("inject:fixup[{}]:{}", f.tree().as_str(), f.as_str())
                }
            },
        }
    }
}

/// Render the cascade without touching anything.
///
/// A build takes hours and mutates two shared trees, so being able to read what
/// it WOULD do is not a convenience. The scripts had no equivalent: the only
/// way to learn the order was to run one.
pub fn render(spec: &BuildSpec) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "build {} / subrelease {} / img {} / canister {}\n",
        spec.release,
        spec.subrelease,
        spec.img.as_str(),
        spec.canister.as_str()
    ));
    if let Some(n) = &spec.canister_nevr {
        out.push_str(&format!("  canister NEVR {n}\n"));
    }
    out.push_str(&format!("  release tree {}\n", spec.tree(Tree::Release).display()));
    out.push_str(&format!("  common tree  {}\n", spec.tree(Tree::Common).display()));
    out.push_str(&format!("  make target  {}\n\n", spec.canister.make_target()));
    for (i, st) in spec.cascade().iter().enumerate() {
        out.push_str(&format!("  {:>2}. {}\n", i + 1, st.name()));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> BuildSpec {
        BuildSpec::from_args("/root", "common", "5.0", "/out", "minimal-iso", "prebuilt", None)
            .unwrap()
    }

    #[test]
    fn an_unknown_image_type_is_refused_by_name() {
        let e = BuildSpec::from_args("/root", "common", "5.0", "/out", "dvd", "prebuilt", None)
            .unwrap_err();
        assert!(e.contains("dvd"), "the error must name what was rejected: {e}");
        assert!(e.contains("minimal-iso"), "and list the valid ones: {e}");
    }

    #[test]
    fn an_unknown_canister_mode_is_refused_by_name() {
        let e = BuildSpec::from_args("/root", "common", "5.0", "/out", "iso", "sideways", None)
            .unwrap_err();
        assert!(e.contains("sideways"), "{e}");
    }

    /// Phase A and B cannot derive the NEVR from a tree that has not been
    /// patched yet, so it has to be supplied. Failing at resolve is the whole
    /// point: the alternative is discovering it hours in.
    #[test]
    fn an_equivalent_phase_without_a_nevr_fails_at_resolve() {
        for m in ["equivalent-a", "equivalent-b"] {
            let e = BuildSpec::from_args("/root", "common", "5.0", "/out", "iso", m, None)
                .unwrap_err();
            assert!(e.contains("MC_CANISTER_NEVR"), "{m}: {e}");
            assert!(
                BuildSpec::from_args("/root", "common", "5.0", "/out", "iso", m, Some("6.12.103-14.ph5".into()))
                    .is_ok(),
                "{m} must resolve once the NEVR is supplied"
            );
        }
        // An empty string is not a NEVR. It arrives that way from an unset
        // environment variable, which is exactly the case being guarded.
        assert!(BuildSpec::from_args(
            "/root", "common", "5.0", "/out", "iso", "equivalent-a", Some(String::new())
        )
        .is_err());
    }

    /// Phase A builds one package. The scripts express this as MC_MAKE_TARGET;
    /// getting it wrong means 700 packages to produce one canister.
    #[test]
    fn only_phase_a_narrows_the_make_target() {
        assert_eq!(CanisterMode::EquivalentA.make_target(), "linux");
        for m in [
            CanisterMode::Prebuilt,
            CanisterMode::Build,
            CanisterMode::Acvp,
            CanisterMode::Kat,
            CanisterMode::EquivalentB,
        ] {
            assert_eq!(m.make_target(), "image", "{} must build an image", m.as_str());
        }
    }

    /// The two trees are separate repositories' branch lines. A fixup that
    /// edits the package builder is a `common` edit no matter which release is
    /// being built, and the release-tree patch mechanism cannot carry it.
    #[test]
    fn a_package_builder_fixup_targets_the_common_tree() {
        assert_eq!(Fixup::RunInChrootFd255.tree(), Tree::Common);
        for f in [
            Fixup::OpenJdkWsl2,
            Fixup::Python3PgoTestGenerators,
            Fixup::SssdSerialMakeInstall,
            Fixup::SpecBlankLines,
        ] {
            assert_eq!(f.tree(), Tree::Release, "{} edits SPECS", f.as_str());
        }
    }

    #[test]
    fn the_two_trees_resolve_to_different_directories() {
        let s = spec();
        assert!(s.tree(Tree::Release).ends_with("5.0"));
        assert!(s.tree(Tree::Common).ends_with("common"));
        assert_ne!(s.tree(Tree::Release), s.tree(Tree::Common));
    }

    /// Injections run after the tree is reset and before make - that ordering
    /// is the reason the mode exists. A patch applied after `make` has started
    /// changes nothing about the ISO.
    #[test]
    fn injections_land_between_reset_and_make() {
        let mut s = spec();
        s.injections = vec![
            Injection::TreePatch { tree: Tree::Release, patch: "poi-2.8.patch".into() },
            Injection::TreePatch { tree: Tree::Common, patch: "common-fixes.patch".into() },
        ];
        let c = s.cascade();
        let pos = |st: &Stage| c.iter().position(|x| x == st).unwrap();
        let reset = pos(&Stage::Reset);
        let make = pos(&Stage::Make);
        let injects: Vec<usize> = c
            .iter()
            .enumerate()
            .filter(|(_, s)| matches!(s, Stage::Inject(_)))
            .map(|(i, _)| i)
            .collect();
        assert_eq!(injects.len(), 2);
        assert!(injects.iter().all(|&i| i > reset && i < make), "cascade: {c:?}");
    }

    /// The common-tree patch is the case the old mechanism could not express.
    /// If this stops appearing in the cascade, `--canister equivalent` silently
    /// goes back to depending on whatever is on disk.
    #[test]
    fn a_common_tree_patch_is_expressible_at_all() {
        let mut s = spec();
        s.injections = vec![Injection::TreePatch {
            tree: Tree::Common,
            patch: "common-fixes.patch".into(),
        }];
        let names: Vec<String> = s.cascade().iter().map(|x| x.name()).collect();
        assert!(
            names.iter().any(|n| n.contains("patch[common]")),
            "the common tree must be a patch target: {names:?}"
        );
    }

    #[test]
    fn the_rendered_cascade_states_what_it_would_do() {
        let mut s = spec();
        s.subrelease = Subrelease::Pinned(91);
        s.injections = vec![Injection::PinSubrelease(91)];
        let r = render(&s);
        assert!(r.contains("subrelease 91"), "{r}");
        assert!(r.contains("inject:subrelease[91]"), "{r}");
        assert!(r.contains("make target  image"), "{r}");
    }

    /// pinned90 and pinned91 were two scripts differing in one integer.
    #[test]
    fn the_pinned_variants_differ_only_in_a_number() {
        let mut a = spec();
        a.subrelease = Subrelease::Pinned(90);
        a.injections = vec![Injection::PinSubrelease(90)];
        let mut b = spec();
        b.subrelease = Subrelease::Pinned(91);
        b.injections = vec![Injection::PinSubrelease(91)];
        let na: Vec<String> = a.cascade().iter().map(|s| s.name()).collect();
        let nb: Vec<String> = b.cascade().iter().map(|s| s.name()).collect();
        assert_eq!(na.len(), nb.len());
        let diff: Vec<_> = na.iter().zip(&nb).filter(|(x, y)| x != y).collect();
        assert_eq!(diff.len(), 1, "exactly one stage may differ: {diff:?}");
    }
}
