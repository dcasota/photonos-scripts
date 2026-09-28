//! A kernel profile: the data a derived wrapper needs that cannot be computed
//! from the release string.
//!
//! Names, versions, URLs and tokens are NOT here - `identity` derives them.
//! What is here is what a person decided or observed: which base wrapper
//! version the profile was reviewed against, the derived wrapper's own version
//! and banner, the pinned tarball digest and how it was verified, dated
//! changelog entries, and the patches the release branch carries.
//!
//! Loading is strict. Unknown fields are refused (a typo must not silently
//! drop a setting), every field is validated by its grammar, and free text may
//! not name a kernel release other than the profile's own - the signature of a
//! profile copied from another kernel and only half updated.

use serde::Deserialize;
use std::collections::BTreeSet;
use std::path::Path;

use super::error::{io, profile as perr, Result};
use super::escape;
use super::identity::KernelRelease;

pub const SCHEMA: u32 = 1;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    pub schema: u32,
    /// The kernel.org release this profile derives a wrapper for.
    pub kernel: String,
    pub base: BaseRef,
    /// The derived wrapper's own version, shown in its header and banner.
    pub wrapper_version: u32,
    /// The derived banner's summary of what the wrapper carries.
    pub summary: String,
    /// The RPM build iteration: Release 0.rcN.<this> or <this>.
    pub rpm_release_iteration: u32,
    pub source: Source,
    pub changelog: Changelog,
    #[serde(default)]
    pub drop_kernel_params: Vec<DropParam>,
    #[serde(default)]
    pub kernel_patches: Vec<KernelPatch>,
    #[serde(default)]
    pub installer_patches: Option<InstallerPatches>,
    /// Packages built before `make image` in addition to the base's set.
    #[serde(default)]
    pub prebuild_extra: Vec<String>,
    /// The FIPS canister series ported to this kernel, if any.
    #[serde(default)]
    pub fips: Option<Fips>,
}

/// A FIPS canister series ported to the target kernel and carried on its
/// release branch. What each spec number becomes lives in the branch's own
/// manifest (written by the port's export and verified by a %prep replay);
/// the profile only says where it is and which LKCM series it is.
///
/// The wrapper enables it only for a canister build: CANISTER_MODE build,
/// equivalent-a or equivalent-b. `none` keeps the kernel FIPS-off.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Fips {
    /// Release-tree path of the manifest, under `SPECS/linux/`.
    pub manifest: String,
    /// The LKCM series stamped into the canister (`FIPS_CANISTER_VERSION`):
    /// the target's `<major>.<minor>`.
    pub lkcm_version: String,
    pub comment: Vec<String>,
}

/// The base wrapper this profile was reviewed against.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BaseRef {
    pub script: String,
    pub kernel: String,
    pub wrapper_version: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Source {
    pub sha512: String,
    pub verified: Verified,
}

/// How the pinned digest was established, as `sharukhan wrapper verify`
/// measured it. Recorded so a reader knows what the pin rests on.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Verified {
    /// `pgp-signature`: the cdn.kernel.org `.tar.sign` over the decompressed
    /// tarball. `signed-tag`: a git.kernel.org snapshot (no signature of its
    /// own) whose decompressed content equals `git archive` of the commit a
    /// signed tag names.
    pub method: String,
    /// Primary key fingerprint of the signer, one of the reviewed kernel.org
    /// signers (profiles/kernel/kernel-org-signers.json).
    pub signer: String,
    /// The commit the signed tag names; `signed-tag` only.
    #[serde(default)]
    pub commit: Option<String>,
    /// When the verification ran, `YYYY-MM-DD`.
    pub on: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Changelog {
    pub date: String,
    pub author: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DropParam {
    pub param: String,
    /// Comment lines explaining why the parameter must go.
    pub reason: Vec<String>,
}

/// How a kernel patch is put into the spec.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    /// Point an existing `PatchN:` line at the rebased file.
    Replace,
    /// Drop any `PatchN:` line and add it back after `Patch1:`.
    Readd,
    /// Add `PatchN:` after `Patch1:` unless it is already there.
    Add,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Flavour {
    Linux,
    LinuxEsx,
}

impl Flavour {
    pub fn spec(&self) -> &'static str {
        match self {
            Flavour::Linux => "SPECS/linux/linux.spec",
            Flavour::LinuxEsx => "SPECS/linux/linux-esx.spec",
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KernelPatch {
    /// Short name, used in the shell function name `enable_<name>_<token>`.
    pub name: String,
    pub mode: Mode,
    pub patch: u32,
    /// The file the `replace` mode expects to find on the `PatchN:` line.
    #[serde(default)]
    pub replaces: Option<String>,
    pub file: String,
    /// `%autopatch -p1 -mN -MN` ranges to enable, the first being `patch`.
    pub autopatch: Vec<u32>,
    pub flavours: Vec<Flavour>,
    /// What the patch is, in the refusal message of the `replace` mode.
    pub label: String,
    pub comment: Vec<String>,
    /// Printed when the spec changed.
    pub applied: String,
    /// Printed when the spec already carried it.
    pub already: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InstallerPatches {
    pub comment: Vec<String>,
    pub patches: Vec<InstallerPatch>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InstallerPatch {
    pub file: String,
    pub date: String,
    /// The changelog entry, one element per line, exactly as it will read.
    pub changelog: Vec<String>,
}

impl Profile {
    pub fn load(path: &Path) -> Result<Profile> {
        let text = std::fs::read_to_string(path).map_err(|e| io(path.display().to_string(), e))?;
        let p: Profile = serde_json::from_str(&text).map_err(|e| {
            perr(
                path.display().to_string(),
                format!("not a valid profile: {e}"),
            )
        })?;
        p.validate()?;
        Ok(p)
    }

    pub fn release(&self) -> Result<KernelRelease> {
        KernelRelease::parse(&self.kernel)
    }

    pub fn base_release(&self) -> Result<KernelRelease> {
        KernelRelease::parse(&self.base.kernel)
    }

    pub fn validate(&self) -> Result<()> {
        if self.schema != SCHEMA {
            return Err(perr(
                "schema",
                format!("is {}, this sharukhan reads schema {SCHEMA}", self.schema),
            ));
        }
        let target = self.release()?;
        let base = self.base_release()?;
        if target == base {
            return Err(perr("kernel", "equals base.kernel; nothing to derive"));
        }
        if self.base.script.is_empty()
            || !self
                .base
                .script
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
            || !self.base.script.ends_with(".sh")
        {
            return Err(perr(
                "base.script",
                "must be a plain file name ending in .sh",
            ));
        }
        if self.base.script != base.script_file() {
            return Err(perr(
                "base.script",
                format!(
                    "is '{}', but a {} base is named '{}'",
                    self.base.script,
                    base.ksrc(),
                    base.script_file()
                ),
            ));
        }
        for (f, v) in [
            ("wrapper_version", self.wrapper_version),
            ("base.wrapper_version", self.base.wrapper_version),
            ("rpm_release_iteration", self.rpm_release_iteration),
        ] {
            if v == 0 || v > 9999 {
                return Err(perr(f, format!("{v} is not in 1..=9999")));
            }
        }
        escape::sh_dq_text("summary", &self.summary)?;
        escape::fstring_text("summary", &self.summary)?;
        if !crate::sha512::is_hex_digest(&self.source.sha512) {
            return Err(perr("source.sha512", "is not 128 lower-case hex digits"));
        }
        self.validate_verified()?;
        escape::changelog_date("changelog.date", &self.changelog.date)?;
        escape::author("changelog.author", &self.changelog.author)?;
        for (i, d) in self.drop_kernel_params.iter().enumerate() {
            escape::kernel_param(&format!("drop_kernel_params[{i}].param"), &d.param)?;
            if d.reason.is_empty() {
                return Err(perr(format!("drop_kernel_params[{i}].reason"), "is empty"));
            }
            for (j, l) in d.reason.iter().enumerate() {
                escape::comment_line(&format!("drop_kernel_params[{i}].reason[{j}]"), l)?;
            }
        }
        self.validate_kernel_patches()?;
        self.validate_installer_patches()?;
        self.validate_fips(&target)?;
        let mut seen = BTreeSet::new();
        for (i, p) in self.prebuild_extra.iter().enumerate() {
            escape::package_name(&format!("prebuild_extra[{i}]"), p)?;
            if !seen.insert(p) {
                return Err(perr(
                    format!("prebuild_extra[{i}]"),
                    format!("'{p}' is listed twice"),
                ));
            }
        }
        self.validate_release_mentions(&target, &base)?;
        Ok(())
    }

    fn validate_fips(&self, target: &KernelRelease) -> Result<()> {
        let Some(f) = &self.fips else { return Ok(()) };
        let comps: Vec<&str> = f.manifest.split('/').collect();
        let plain = |c: &str| {
            !c.is_empty()
                && !c.starts_with('.')
                && !c.starts_with('-')
                && c.chars().all(|x| x.is_ascii_alphanumeric() || matches!(x, '.' | '_' | '-'))
        };
        if comps.len() < 4
            || comps[0] != "SPECS"
            || comps[1] != "linux"
            || !comps.iter().all(|c| plain(c))
            || !f.manifest.ends_with(".json")
        {
            return Err(perr(
                "fips.manifest",
                "must be a plain relative path SPECS/linux/<dir>/<name>.json",
            ));
        }
        let series = target.series();
        if f.lkcm_version != series {
            return Err(perr(
                "fips.lkcm_version",
                format!("is '{}', the target's series is '{series}'", f.lkcm_version),
            ));
        }
        if f.comment.is_empty() {
            return Err(perr("fips.comment", "is empty"));
        }
        for (j, l) in f.comment.iter().enumerate() {
            escape::comment_line(&format!("fips.comment[{j}]"), l)?;
        }
        Ok(())
    }

    fn validate_verified(&self) -> Result<()> {
        let v = &self.source.verified;
        let target = self.release()?;
        let expected = if target.signature_url().is_some() {
            "pgp-signature"
        } else {
            "signed-tag"
        };
        if v.method != expected {
            return Err(perr(
                "source.verified.method",
                format!(
                    "'{}': {} is verified by {expected} ({})",
                    v.method,
                    target.ksrc(),
                    if expected == "signed-tag" {
                        "a git.kernel.org snapshot carries no signature of its own"
                    } else {
                        "cdn.kernel.org publishes a .tar.sign for it"
                    }
                ),
            ));
        }
        if !is_fingerprint(&v.signer) {
            return Err(perr(
                "source.verified.signer",
                "must be a 40-digit uppercase hex primary key fingerprint",
            ));
        }
        match (expected, &v.commit) {
            ("signed-tag", Some(c)) if is_commit(c) => {}
            ("signed-tag", _) => {
                return Err(perr(
                    "source.verified.commit",
                    "a signed-tag verification records the 40-hex commit the tag names",
                ))
            }
            (_, Some(_)) => {
                return Err(perr(
                    "source.verified.commit",
                    "only a signed-tag verification names a commit",
                ))
            }
            _ => {}
        }
        let ok = v.on.len() == 10
            && v.on.as_bytes()[4] == b'-'
            && v.on.as_bytes()[7] == b'-'
            && v.on
                .bytes()
                .enumerate()
                .all(|(i, b)| i == 4 || i == 7 || b.is_ascii_digit());
        if !ok {
            return Err(perr("source.verified.on", "must be YYYY-MM-DD"));
        }
        Ok(())
    }

    fn validate_kernel_patches(&self) -> Result<()> {
        let mut names = BTreeSet::new();
        let mut numbers = BTreeSet::new();
        for (i, k) in self.kernel_patches.iter().enumerate() {
            let f = |s: &str| format!("kernel_patches[{i}].{s}");
            escape::ident(&f("name"), &k.name)?;
            if !names.insert(k.name.clone()) {
                return Err(perr(f("name"), format!("'{}' is used twice", k.name)));
            }
            if k.patch < 2 || k.patch > 99_999 {
                return Err(perr(
                    f("patch"),
                    format!(
                        "{} is not in 2..=99999 (Patch0 and Patch1 are the base's)",
                        k.patch
                    ),
                ));
            }
            if !numbers.insert(k.patch) {
                return Err(perr(f("patch"), format!("Patch{} is used twice", k.patch)));
            }
            escape::patch_file(&f("file"), &k.file)?;
            match (k.mode, &k.replaces) {
                (Mode::Replace, Some(r)) => {
                    escape::patch_file(&f("replaces"), r)?;
                    if r == &k.file {
                        return Err(perr(f("replaces"), "equals file; nothing would change"));
                    }
                }
                (Mode::Replace, None) => {
                    return Err(perr(
                        f("replaces"),
                        "the replace mode needs the file it replaces",
                    ))
                }
                (_, Some(_)) => {
                    return Err(perr(
                        f("replaces"),
                        "only the replace mode takes 'replaces'",
                    ))
                }
                (_, None) => {}
            }
            if k.autopatch.first() != Some(&k.patch) {
                return Err(perr(
                    f("autopatch"),
                    format!("must start with the patch's own number {}", k.patch),
                ));
            }
            let mut ranges = BTreeSet::new();
            for r in &k.autopatch {
                if *r < 2 || !ranges.insert(*r) {
                    return Err(perr(
                        f("autopatch"),
                        format!("{r} is below 2 or listed twice"),
                    ));
                }
            }
            if k.flavours.is_empty() {
                return Err(perr(f("flavours"), "is empty"));
            }
            let mut fl = k.flavours.clone();
            fl.sort();
            fl.dedup();
            if fl.len() != k.flavours.len() || fl != k.flavours {
                return Err(perr(
                    f("flavours"),
                    "must be unique and in the order linux, linux-esx",
                ));
            }
            escape::fstring_text(&f("label"), &k.label)?;
            escape::fstring_text(&f("applied"), &k.applied)?;
            escape::fstring_text(&f("already"), &k.already)?;
            if k.comment.is_empty() {
                return Err(perr(f("comment"), "is empty; say what the patch is for"));
            }
            for (j, l) in k.comment.iter().enumerate() {
                escape::comment_line(&format!("kernel_patches[{i}].comment[{j}]"), l)?;
            }
        }
        Ok(())
    }

    fn validate_installer_patches(&self) -> Result<()> {
        let Some(ip) = &self.installer_patches else {
            return Ok(());
        };
        if ip.patches.is_empty() {
            return Err(perr(
                "installer_patches.patches",
                "is empty; omit the section instead",
            ));
        }
        for (j, l) in ip.comment.iter().enumerate() {
            escape::comment_line(&format!("installer_patches.comment[{j}]"), l)?;
        }
        let mut files = BTreeSet::new();
        for (i, p) in ip.patches.iter().enumerate() {
            let f = |s: &str| format!("installer_patches.patches[{i}].{s}");
            escape::patch_file(&f("file"), &p.file)?;
            if !files.insert(p.file.clone()) {
                return Err(perr(f("file"), format!("'{}' is listed twice", p.file)));
            }
            escape::changelog_date(&f("date"), &p.date)?;
            if p.changelog.is_empty() {
                return Err(perr(f("changelog"), "is empty"));
            }
            for (j, l) in p.changelog.iter().enumerate() {
                escape::py_text(&format!("installer_patches.patches[{i}].changelog[{j}]"), l)?;
            }
            if !p.changelog[0].starts_with("- ") {
                return Err(perr(f("changelog"), "the first line must start with '- '"));
            }
        }
        Ok(())
    }

    /// Every text a person wrote into the profile.
    fn texts(&self) -> Vec<(String, &str)> {
        let mut v: Vec<(String, &str)> = vec![("summary".into(), self.summary.as_str())];
        for (i, d) in self.drop_kernel_params.iter().enumerate() {
            for (j, l) in d.reason.iter().enumerate() {
                v.push((format!("drop_kernel_params[{i}].reason[{j}]"), l));
            }
        }
        for (i, k) in self.kernel_patches.iter().enumerate() {
            for (s, t) in [
                ("label", &k.label),
                ("applied", &k.applied),
                ("already", &k.already),
            ] {
                v.push((format!("kernel_patches[{i}].{s}"), t));
            }
            for (j, l) in k.comment.iter().enumerate() {
                v.push((format!("kernel_patches[{i}].comment[{j}]"), l));
            }
        }
        if let Some(ip) = &self.installer_patches {
            for (j, l) in ip.comment.iter().enumerate() {
                v.push((format!("installer_patches.comment[{j}]"), l));
            }
        }
        if let Some(f) = &self.fips {
            for (j, l) in f.comment.iter().enumerate() {
                v.push((format!("fips.comment[{j}]"), l));
            }
        }
        v
    }

    /// No text may name a full kernel release other than the target's, as
    /// release or as RPM version. `6.12-era` or `7.3's` (major.minor only)
    /// are fine; `7.2.7` in a 7.3-rc4 profile is a leftover.
    fn validate_release_mentions(
        &self,
        target: &KernelRelease,
        base: &KernelRelease,
    ) -> Result<()> {
        let allowed = [target.ksrc(), target.rpm_version()];
        for (field, text) in self.texts() {
            for found in release_mentions(text) {
                if !allowed.contains(&found) {
                    let hint = if found == base.ksrc() {
                        " (the base's kernel; this text was not updated for the target)"
                    } else {
                        ""
                    };
                    return Err(perr(
                        field,
                        format!(
                            "names the kernel release '{found}', not the profile's '{}'{hint}",
                            target.ksrc()
                        ),
                    ));
                }
            }
        }
        Ok(())
    }
}

/// Full kernel releases named in `text`: `X.Y.Z`, `X.Y-rcN`. A bare `X.Y`
/// is a series, not a release, and is not reported.
pub fn is_fingerprint(s: &str) -> bool {
    s.len() == 40
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'A'..=b'F').contains(&b))
}

pub fn is_commit(s: &str) -> bool {
    s.len() == 40
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub fn release_mentions(text: &str) -> Vec<String> {
    let b = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let starts = b[i].is_ascii_digit()
            && (i == 0 || !(b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'.'));
        if !starts {
            i += 1;
            continue;
        }
        let mut j = i;
        while j < b.len() && (b[j].is_ascii_digit() || b[j] == b'.') {
            j += 1;
        }
        let mut cand = text[i..j].trim_end_matches('.').to_string();
        let dots = cand.matches('.').count();
        let mut end = i + cand.len();
        if dots == 1 && text[end..].starts_with("-rc") {
            let mut k = end + 3;
            while k < b.len() && b[k].is_ascii_digit() {
                k += 1;
            }
            if k > end + 3 {
                cand = text[i..k].to_string();
                end = k;
            }
        }
        if (dots == 2 || cand.contains("-rc")) && KernelRelease::parse(&cand).is_ok() {
            out.push(cand);
        }
        i = end.max(i + 1);
    }
    out
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// A complete, valid 7.3-rc4 profile for unit tests.
    pub fn sample() -> String {
        r#"{
  "schema": 1,
  "kernel": "7.3-rc4",
  "base": {"script": "runPh7-2-7.sh", "kernel": "7.2.7", "wrapper_version": 13},
  "wrapper_version": 8,
  "summary": "RAP/KCFI on, rdrand-rng",
  "rpm_release_iteration": 1,
  "source": {"sha512": "7a4b9599c2c593131e150ae22030f643813b0fb3de2b479281ebb9a413e7928903adc748eb522e03fd39e9ca4991c12e4d0331718fff59a53fc6676b390c7945",
             "verified": {"method": "signed-tag", "signer": "ABAF11C65A2970B130ABE3C479BE3E4300411886",
                          "commit": "93f51579e7df248780214094418f205253383cc5", "on": "2026-09-27"}},
  "changelog": {"date": "Fri Sep 25 2026", "author": "Daniel Casota <dcasota@gmail.com>"},
  "drop_kernel_params": [{"param": "noreplace-smp", "reason": ["gone in the 7.3 cycle"]}],
  "kernel_patches": [
    {"name": "rap", "mode": "replace", "patch": 61, "replaces": "0001-gcc-rap-plugin-with-kcfi.patch",
     "file": "0001-gcc-rap-plugin-with-kcfi-7.3.patch", "autopatch": [61, 63], "flavours": ["linux"],
     "label": "RAP", "comment": ["RAP for linux"], "applied": "RAP enabled (7.3-rc4 rebase)", "already": "RAP already enabled"}
  ],
  "installer_patches": {"comment": ["installer fixes"], "patches": [
    {"file": "0008-x.patch", "date": "Sat Sep 26 2026", "changelog": ["- x: fix", "  more"]}]},
  "prebuild_extra": ["cloud-init"]
}"#
        .to_string()
    }

    fn parse(s: &str) -> Result<Profile> {
        let p: Profile = serde_json::from_str(s).map_err(|e| perr("json", e.to_string()))?;
        p.validate()?;
        Ok(p)
    }

    #[test]
    fn the_sample_profile_is_valid() {
        let p = parse(&sample()).unwrap();
        assert_eq!(p.release().unwrap().ksrc(), "7.3-rc4");
        assert_eq!(p.kernel_patches[0].mode, Mode::Replace);
    }

    #[test]
    fn an_unknown_field_is_refused_not_ignored() {
        let s = sample().replacen("\"schema\": 1,", "\"schema\": 1, \"summry\": \"typo\",", 1);
        let e = serde_json::from_str::<Profile>(&s).unwrap_err().to_string();
        assert!(e.contains("unknown field"), "{e}");
    }

    #[test]
    fn each_invalid_field_is_named() {
        for (from, to, field) in [
            ("\"schema\": 1", "\"schema\": 2", "schema"),
            ("\"kernel\": \"7.3-rc4\"", "\"kernel\": \"7.2.7\"", "kernel"),
            ("\"runPh7-2-7.sh\"", "\"runPh7-2-8.sh\"", "base.script"),
            (
                "\"wrapper_version\": 8",
                "\"wrapper_version\": 0",
                "wrapper_version",
            ),
            ("7a4b9599c2", "7A4B9599C2", "source.sha512"),
            (
                "\"signed-tag\"",
                "\"pgp-signature\"",
                "source.verified.method",
            ),
            ("\"ABAF11C6", "\"abaf11c6", "source.verified.signer"),
            (
                "\"commit\": \"93f5",
                "\"commit\": \"93F5",
                "source.verified.commit",
            ),
            ("\"2026-09-27\"", "\"27.09.2026\"", "source.verified.on"),
            ("Fri Sep 25 2026", "Thu Sep 25 2026", "changelog.date"),
            (
                "Daniel Casota <dcasota@gmail.com>",
                "dcasota",
                "changelog.author",
            ),
            (
                "\"noreplace-smp\"",
                "\"no replace\"",
                "drop_kernel_params[0].param",
            ),
            (
                "\"name\": \"rap\"",
                "\"name\": \"Rap\"",
                "kernel_patches[0].name",
            ),
            ("\"patch\": 61", "\"patch\": 1", "kernel_patches[0].patch"),
            ("[61, 63]", "[63, 61]", "kernel_patches[0].autopatch"),
            (
                "\"flavours\": [\"linux\"]",
                "\"flavours\": []",
                "kernel_patches[0].flavours",
            ),
            (
                "RAP already enabled",
                "RAP {already}",
                "kernel_patches[0].already",
            ),
            (
                "\"0008-x.patch\"",
                "\"0008-x.diff\"",
                "installer_patches.patches[0].file",
            ),
            (
                "\"- x: fix\"",
                "\"x: fix\"",
                "installer_patches.patches[0].changelog",
            ),
            (
                "[\"cloud-init\"]",
                "[\"cloud-init\", \"cloud-init\"]",
                "prebuild_extra[1]",
            ),
            ("RAP/KCFI on, rdrand-rng", "cost $5", "summary"),
        ] {
            let s = sample().replacen(from, to, 1);
            assert_ne!(s, sample(), "fixture did not change for {field}");
            let e = parse(&s).unwrap_err().to_string();
            assert!(e.contains(&format!("'{field}'")), "{field}: {e}");
        }
    }

    #[test]
    fn a_text_naming_another_kernel_release_is_a_leftover() {
        let s = sample().replacen(
            "RAP enabled (7.3-rc4 rebase)",
            "RAP enabled (7.2.7 rebase)",
            1,
        );
        let e = parse(&s).unwrap_err().to_string();
        assert!(
            e.contains("names the kernel release '7.2.7'") && e.contains("base's kernel"),
            "{e}"
        );
        // the target's own release and RPM version, and a bare series, are fine
        assert!(
            parse(&sample().replacen("RAP for linux", "RAP 7.3.0 on 7.3, 6.12-era", 1)).is_ok()
        );
    }

    #[test]
    fn release_mentions_find_releases_and_ignore_series() {
        assert_eq!(
            release_mentions("from 7.2.7 to 7.3-rc4."),
            vec!["7.2.7", "7.3-rc4"]
        );
        assert!(release_mentions("6.12-era, 7.3's DRM, Patch2-Patch49, v13").is_empty());
        assert!(release_mentions("sha 1a7.2.7b").is_empty());
    }
    fn with_fips(fips: &str) -> std::result::Result<Profile, String> {
        let t = sample();
        let t = format!("{},\n  \"fips\": {fips}\n}}", t.trim_end().trim_end_matches('}').trim_end());
        let p: Profile = serde_json::from_str(&t).map_err(|e| e.to_string())?;
        p.validate().map_err(|e| e.to_string())?;
        Ok(p)
    }

    #[test]
    fn a_fips_section_is_validated() {
        let ok = r#"{"manifest": "SPECS/linux/fips-7.3/manifest.json", "lkcm_version": "7.3", "comment": ["x"]}"#;
        assert!(with_fips(ok).is_ok(), "{:?}", with_fips(ok).err());
        for (bad, why) in [
            (r#"{"manifest": "SPECS/linux/../x.json", "lkcm_version": "7.3", "comment": ["x"]}"#, "fips.manifest"),
            (r#"{"manifest": "SPECS/foo/fips/m.json", "lkcm_version": "7.3", "comment": ["x"]}"#, "fips.manifest"),
            (r#"{"manifest": "/SPECS/linux/fips/m.json", "lkcm_version": "7.3", "comment": ["x"]}"#, "fips.manifest"),
            (r#"{"manifest": "SPECS/linux/fips/m.json", "lkcm_version": "7.2", "comment": ["x"]}"#, "fips.lkcm_version"),
            (r#"{"manifest": "SPECS/linux/fips/m.json", "lkcm_version": "7.3", "comment": []}"#, "fips.comment"),
            (r#"{"manifest": "SPECS/linux/fips/m.json", "lkcm_version": "7.3", "comment": ["the 7.2.7 base"]}"#, "fips.comment[0]"),
            (r#"{"manifest": "SPECS/linux/fips/m.json", "lkcm_version": "7.3", "comment": ["x"], "extra": 1}"#, "unknown field"),
        ] {
            let e = with_fips(bad).expect_err(bad);
            assert!(e.contains(why), "{bad}: {e}");
        }
    }
}
