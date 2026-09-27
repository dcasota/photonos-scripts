//! A kernel.org release, and everything a wrapper derives from it.
//!
//! Nothing here is a table of known kernels. A release string is parsed by a
//! strict grammar - `MAJOR.MINOR` (mainline), `MAJOR.MINOR-rcN` (mainline
//! release candidate) or `MAJOR.MINOR.PATCH` (stable or longterm) - and every
//! derived name follows from it by rule:
//!
//! | derived            | 7.3-rc4                                     | 7.2.7                    |
//! |--------------------|---------------------------------------------|--------------------------|
//! | tarball directory  | `linux-7.3-rc4`                             | `linux-7.2.7`            |
//! | RPM `Version:`     | `7.3.0` (RPM versions cannot contain `-`)   | `7.2.7`                  |
//! | RPM `Release:`     | `0.rc4.<n>` (sorts below the final `<n>`)   | `<n>`                    |
//! | spec `%setup` dir  | `%{kernel_src}` (differs from the version)  | `%{version}`             |
//! | wrapper tag        | `runPh7-3-RC4`                              | `runPh7-2-7`             |
//! | identity token     | `73rc4`                                     | `727`                    |
//! | source             | git.kernel.org snapshot, `.tar.gz`          | cdn.kernel.org, `.tar.xz`|
//!
//! Anything else - `linux-next`, `-mm`, a `.0` stable, a leading zero - is
//! rejected rather than guessed at.

use super::error::{Result, WrapperError};

/// Which kind of kernel.org release this is. It decides the source host, the
/// archive format and the RPM version scheme.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// `X.Y-rcN`: a git.kernel.org snapshot of Linus's tag.
    MainlineRc { rc: u32 },
    /// `X.Y`: a mainline release, published on cdn.kernel.org.
    MainlineFinal,
    /// `X.Y.Z`: a stable or longterm release, published on cdn.kernel.org.
    Stable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KernelRelease {
    pub major: u32,
    pub minor: u32,
    pub patch: Option<u32>,
    pub kind: Kind,
}

/// A decimal component: no sign, no leading zero, bounded.
fn component(s: &str, what: &str, input: &str, max: u32) -> Result<u32> {
    let bad = |why: String| WrapperError::KernelRelease {
        input: input.to_string(),
        why,
    };
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return Err(bad(format!("{what} '{s}' is not a decimal number")));
    }
    if s.len() > 1 && s.starts_with('0') {
        return Err(bad(format!("{what} '{s}' has a leading zero")));
    }
    let v: u32 = s
        .parse()
        .map_err(|_| bad(format!("{what} '{s}' is out of range")))?;
    if v > max {
        return Err(bad(format!("{what} {v} is above {max}")));
    }
    Ok(v)
}

impl KernelRelease {
    pub fn parse(input: &str) -> Result<KernelRelease> {
        let bad = |why: &str| WrapperError::KernelRelease {
            input: input.to_string(),
            why: why.to_string(),
        };
        if input != input.trim() || input.is_empty() {
            return Err(bad("empty, or surrounded by whitespace"));
        }
        let (ver, rc) = match input.split_once("-rc") {
            Some((v, n)) => (v, Some(component(n, "release candidate", input, 99)?)),
            None => (input, None),
        };
        if rc == Some(0) {
            return Err(bad("there is no -rc0"));
        }
        let parts: Vec<&str> = ver.split('.').collect();
        let (major, minor, patch) = match parts.as_slice() {
            [a, b] => (
                component(a, "major", input, 99)?,
                component(b, "minor", input, 999)?,
                None,
            ),
            [a, b, c] => (
                component(a, "major", input, 99)?,
                component(b, "minor", input, 999)?,
                Some(component(c, "patch level", input, 9999)?),
            ),
            _ => {
                return Err(bad(
                    "expected MAJOR.MINOR, MAJOR.MINOR-rcN or MAJOR.MINOR.PATCH",
                ))
            }
        };
        if major == 0 {
            return Err(bad("major version 0 is not a kernel.org release"));
        }
        let kind = match (patch, rc) {
            (Some(_), Some(_)) => return Err(bad("a stable release has no release candidates")),
            (Some(0), None) => {
                return Err(bad(
                    "kernel.org publishes X.Y, never X.Y.0; name the mainline release X.Y",
                ))
            }
            (Some(_), None) => Kind::Stable,
            (None, Some(n)) => Kind::MainlineRc { rc: n },
            (None, None) => Kind::MainlineFinal,
        };
        Ok(KernelRelease {
            major,
            minor,
            patch,
            kind,
        })
    }

    /// The release as kernel.org names it, and as the tarball directory does.
    pub fn ksrc(&self) -> String {
        match (self.patch, self.kind) {
            (Some(p), _) => format!("{}.{}.{}", self.major, self.minor, p),
            (None, Kind::MainlineRc { rc }) => format!("{}.{}-rc{}", self.major, self.minor, rc),
            (None, _) => format!("{}.{}", self.major, self.minor),
        }
    }

    /// RPM `Version:`. A release candidate and a mainline release both name
    /// themselves X.Y.0 in `uname -r` once EXTRAVERSION is blanked.
    pub fn rpm_version(&self) -> String {
        match self.patch {
            Some(p) => format!("{}.{}.{}", self.major, self.minor, p),
            None => format!("{}.{}.0", self.major, self.minor),
        }
    }

    /// RPM `Release:` for build iteration `n`. A release candidate sorts below
    /// the final release (`0.rcN.n` < `n`), so an rc RPM can never shadow it.
    pub fn rpm_release(&self, iteration: u32) -> String {
        match self.kind {
            Kind::MainlineRc { rc } => format!("0.rc{rc}.{iteration}"),
            _ => iteration.to_string(),
        }
    }

    /// Whether the tarball directory differs from the RPM version, so the
    /// spec needs `%define kernel_src` and `%setup -n linux-%{kernel_src}`.
    pub fn needs_kernel_src(&self) -> bool {
        self.ksrc() != self.rpm_version()
    }

    /// The spec macro naming the tarball directory in `%setup -n linux-...`.
    pub fn setup_macro(&self) -> &'static str {
        if self.needs_kernel_src() {
            "kernel_src"
        } else {
            "version"
        }
    }

    /// Wrapper script tag and log prefix: `runPh7-3-RC4`, `runPh7-2-7`.
    pub fn tag(&self) -> String {
        format!(
            "runPh{}",
            self.ksrc().replace('.', "-").replace("-rc", "-RC")
        )
    }

    /// Lower-case alphanumeric identity token: `73rc4`, `727`. Used in shell
    /// function and variable names, which admit no `.` or `-`.
    pub fn token(&self) -> String {
        self.ksrc()
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .map(|c| c.to_ascii_lowercase())
            .collect()
    }

    /// The ISO marker stem the wrapper rewrites `.runph5-iso-marker` to.
    pub fn marker(&self) -> String {
        format!("runph{}", self.token())
    }

    /// Shell variable holding the tarball's sha512.
    pub fn sha_var(&self) -> String {
        format!("K{}_SHA", self.token().to_ascii_uppercase())
    }

    pub fn pin_fn(&self) -> String {
        format!("pin_{}", self.token())
    }

    pub fn script_file(&self) -> String {
        format!("{}.sh", self.tag())
    }

    /// The experimental release branch on github.com/dcasota/photon.
    pub fn branch(&self) -> String {
        format!("experimental/linux-{}", self.ksrc())
    }

    /// The git tag kernel.org cut for this release.
    pub fn git_tag(&self) -> String {
        format!("v{}", self.ksrc())
    }

    pub fn tarball(&self) -> String {
        match self.kind {
            Kind::MainlineRc { .. } => format!("linux-{}.tar.gz", self.ksrc()),
            _ => format!("linux-{}.tar.xz", self.ksrc()),
        }
    }

    /// Where kernel.org publishes the tarball. Release candidates exist only
    /// as git.kernel.org snapshots; releases are on cdn.kernel.org.
    pub fn source_url(&self) -> String {
        match self.kind {
            Kind::MainlineRc { .. } => {
                format!("https://git.kernel.org/torvalds/t/{}", self.tarball())
            }
            _ => format!(
                "https://cdn.kernel.org/pub/linux/kernel/v{}.x/{}",
                self.major,
                self.tarball()
            ),
        }
    }

    /// The same URL with the release directory replaced by the spec macro,
    /// as the spec's `Source0:` carries it.
    pub fn source0(&self) -> String {
        let url = self.source_url();
        let tarball = self.tarball();
        let dir = format!("linux-{}", self.ksrc());
        let spec_dir = format!("linux-%{{{}}}", self.setup_macro());
        let base = &url[..url.len() - tarball.len()];
        format!("{base}{}", tarball.replacen(&dir, &spec_dir, 1))
    }

    /// kernel.org's detached signature over the uncompressed tar, where one
    /// exists. Snapshots have none.
    pub fn signature_url(&self) -> Option<String> {
        match self.kind {
            Kind::MainlineRc { .. } => None,
            _ => Some(format!(
                "https://cdn.kernel.org/pub/linux/kernel/v{}.x/linux-{}.tar.sign",
                self.major,
                self.ksrc()
            )),
        }
    }

    pub fn source_host(&self) -> &'static str {
        match self.kind {
            Kind::MainlineRc { .. } => "git.kernel.org",
            _ => "cdn.kernel.org",
        }
    }

    /// "mainline release candidate", "mainline release", "stable release".
    pub fn kind_long(&self) -> &'static str {
        match self.kind {
            Kind::MainlineRc { .. } => "mainline release candidate",
            Kind::MainlineFinal => "mainline release",
            Kind::Stable => "stable release",
        }
    }

    /// Header suffix after the release: " (mainline RC)", " (mainline)", "".
    pub fn kind_suffix(&self) -> &'static str {
        match self.kind {
            Kind::MainlineRc { .. } => " (mainline RC)",
            Kind::MainlineFinal => " (mainline)",
            Kind::Stable => "",
        }
    }

    /// The Makefile EXTRAVERSION a release candidate carries (`-rc4`).
    pub fn extraversion(&self) -> Option<String> {
        match self.kind {
            Kind::MainlineRc { rc } => Some(format!("-rc{rc}")),
            _ => None,
        }
    }

    /// Every string the wrapper derived from this identity carries, most
    /// specific first. Used for the leftover assertion and for the collision
    /// pre-check.
    pub fn identity_strings(&self) -> Vec<String> {
        let mut v = vec![
            self.tag(),
            self.marker(),
            self.sha_var(),
            self.pin_fn(),
            self.ksrc(),
            self.token(),
        ];
        v.dedup();
        v
    }
}

/// A Photon userland release as the base wrapper declares it (`5.0`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Userland {
    pub major: u32,
    pub minor: u32,
}

impl Userland {
    pub fn parse(s: &str) -> Result<Userland> {
        let bad = |why: &str| WrapperError::Declaration {
            why: format!("userland '{s}': {why}"),
        };
        let (a, b) = s
            .split_once('.')
            .ok_or_else(|| bad("expected MAJOR.MINOR"))?;
        let major = component(a, "major", s, 99).map_err(|_| bad("bad major"))?;
        let minor = component(b, "minor", s, 99).map_err(|_| bad("bad minor"))?;
        Ok(Userland { major, minor })
    }
    /// "5.0"
    pub fn full(&self) -> String {
        format!("{}.{}", self.major, self.minor)
    }
    /// ".ph5"
    pub fn dist(&self) -> String {
        format!(".ph{}", self.major)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn k(s: &str) -> KernelRelease {
        KernelRelease::parse(s).unwrap()
    }

    #[test]
    fn a_release_candidate_derives_the_names_the_73rc4_wrapper_uses() {
        let r = k("7.3-rc4");
        assert_eq!(r.kind, Kind::MainlineRc { rc: 4 });
        assert_eq!(r.ksrc(), "7.3-rc4");
        assert_eq!(r.rpm_version(), "7.3.0");
        assert_eq!(r.rpm_release(1), "0.rc4.1");
        assert!(r.needs_kernel_src());
        assert_eq!(r.setup_macro(), "kernel_src");
        assert_eq!(r.tag(), "runPh7-3-RC4");
        assert_eq!(r.token(), "73rc4");
        assert_eq!(r.marker(), "runph73rc4");
        assert_eq!(r.sha_var(), "K73RC4_SHA");
        assert_eq!(r.pin_fn(), "pin_73rc4");
        assert_eq!(r.branch(), "experimental/linux-7.3-rc4");
        assert_eq!(r.tarball(), "linux-7.3-rc4.tar.gz");
        assert_eq!(
            r.source_url(),
            "https://git.kernel.org/torvalds/t/linux-7.3-rc4.tar.gz"
        );
        assert_eq!(
            r.source0(),
            "https://git.kernel.org/torvalds/t/linux-%{kernel_src}.tar.gz"
        );
        assert_eq!(r.signature_url(), None);
        assert_eq!(r.extraversion().as_deref(), Some("-rc4"));
        assert_eq!(r.git_tag(), "v7.3-rc4");
    }

    #[test]
    fn a_stable_release_derives_the_names_the_727_wrapper_uses() {
        let r = k("7.2.7");
        assert_eq!(r.kind, Kind::Stable);
        assert_eq!(r.rpm_version(), "7.2.7");
        assert_eq!(r.rpm_release(3), "3");
        assert!(!r.needs_kernel_src());
        assert_eq!(r.setup_macro(), "version");
        assert_eq!(r.tag(), "runPh7-2-7");
        assert_eq!(r.token(), "727");
        assert_eq!(r.marker(), "runph727");
        assert_eq!(r.sha_var(), "K727_SHA");
        assert_eq!(
            r.source_url(),
            "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.7.tar.xz"
        );
        assert_eq!(
            r.source0(),
            "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-%{version}.tar.xz"
        );
        assert_eq!(
            r.signature_url().as_deref(),
            Some("https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.7.tar.sign")
        );
    }

    #[test]
    fn a_mainline_release_is_x_y_and_versions_as_x_y_0() {
        let r = k("7.3");
        assert_eq!(r.kind, Kind::MainlineFinal);
        assert_eq!(r.rpm_version(), "7.3.0");
        assert_eq!(r.rpm_release(1), "1");
        assert!(r.needs_kernel_src());
        assert_eq!(r.tag(), "runPh7-3");
        assert_eq!(r.tarball(), "linux-7.3.tar.xz");
        // an rc sorts below the final release of the same version
        assert!(k("7.3-rc4").rpm_release(9) < k("7.3").rpm_release(1));
    }

    #[test]
    fn anything_outside_the_grammar_is_rejected_with_the_reason() {
        for (bad, why) in [
            ("", "empty"),
            (" 7.3", "whitespace"),
            ("7", "expected"),
            ("7.3.1.2", "expected"),
            ("7.3-rc0", "no -rc0"),
            ("7.3.1-rc2", "no release candidates"),
            ("7.3.0", "never X.Y.0"),
            ("07.3", "leading zero"),
            ("7.03", "leading zero"),
            ("0.9", "major version 0"),
            ("7.3-rc", "not a decimal"),
            ("7.x", "not a decimal"),
            ("next-20260927", "expected"),
            ("7.3-rc4-mm1", "not a decimal"),
            ("100.1", "above"),
        ] {
            let e = KernelRelease::parse(bad).unwrap_err().to_string();
            assert!(e.contains(why), "{bad:?}: {e}");
        }
    }

    #[test]
    fn identity_strings_list_every_derived_name_once() {
        let v = k("7.2.7").identity_strings();
        for s in [
            "runPh7-2-7",
            "runph727",
            "K727_SHA",
            "pin_727",
            "7.2.7",
            "727",
        ] {
            assert!(v.iter().any(|x| x == s), "{s}");
        }
    }

    #[test]
    fn the_userland_declaration_parses_and_rejects() {
        let u = Userland::parse("5.0").unwrap();
        assert_eq!(
            (u.full(), u.dist()),
            ("5.0".to_string(), ".ph5".to_string())
        );
        assert!(Userland::parse("5").is_err());
        assert!(Userland::parse("5.x").is_err());
    }
}
