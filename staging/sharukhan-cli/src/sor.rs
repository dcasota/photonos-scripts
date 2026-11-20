//! The source-of-record profile (`sharukhan --sor <command>`, or
//! `SHARUKHAN_PROFILE=sor`; ADR-0015, U4).
//!
//! A run under this profile must be reproducible and auditable from its
//! recorded inputs alone. So the profile refuses, before anything acts, every
//! input the record would not show:
//!
//! - **override**: a setting that replaces a built-in data file or template
//!   (`SHARUKHAN_MATRIX`, `MC_VMX_TEMPLATE`, ...). The built-in copy is part of
//!   the binary whose sha256 a record names; a file beside it is not.
//! - **escalation**: the model escalation (ADR-0010). Its output is not
//!   reproducible. Under the profile it is off whatever `MC_ESCALATE` says, and
//!   an explicit `MC_ESCALATE=auto` is refused rather than silently ignored.
//! - **image**: a container image named by a tag. A tag can move, so only an
//!   immutable ID (`sha256:<64 hex>` or `<name>@sha256:<64 hex>`) is accepted.
//!   The builder's own base image is accepted by ID already (builder.rs).
//! - **network**: a repository or source URL that is not `file://`. A record
//!   run sees only its mirror. The commands that reach GitHub, kernel.org or
//!   a model by design (sync, watch, escalate, ...) are refused as a whole.
//!
//! Each refusal names the setting, the value measured and what was expected,
//! and sharukhan stops with exit 78 (EX_CONFIG). `doctor` lists the findings
//! instead of stopping, so a host can be brought into line.

/// The setting that selects the profile.
pub const SETTING: &str = "SHARUKHAN_PROFILE";

/// Settings that replace something built into the binary.
pub const OVERRIDES: &[&str] = &[
    "SHARUKHAN_MATRIX",
    "SHARUKHAN_VARIANTS",
    "SHARUKHAN_CHECK_PRS",
    "SHARUKHAN_PR_DEFECTS",
    "MC_VMX_TEMPLATE",
    "SHARUKHAN_WRAPPERS",
    "SHARUKHAN_WRAPPER_PROFILES",
    "SHARUKHAN_SYSTEMD_PROFILES",
];

/// Commands whose purpose is to reach a remote (GitHub, kernel.org, a model's
/// API, a package repository's network): never part of a record run.
pub const NETWORK_COMMANDS: &[&str] = &[
    "sync",
    "watch",
    "events",
    "escalate",
    "mcp",
    "wrapper",
    "systemd",
    "pr-eligibility",
];

/// Commands that report on the profile rather than act under it.
const EXEMPT: &[&str] = &["doctor", "help", "settings"];

/// One refused input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    pub rule: &'static str,
    pub setting: String,
    pub value: String,
    pub expected: String,
}

impl std::fmt::Display for Finding {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}: {}={}: expected {}",
            self.rule, self.setting, self.value, self.expected
        )
    }
}

/// `SHARUKHAN_PROFILE`: unset, empty or `default` is off; `sor` is on;
/// anything else is an error, never off (a typo must not drop the profile).
pub fn parse(v: Option<&str>) -> Result<bool, String> {
    match v.map(str::trim) {
        None | Some("") | Some("default") => Ok(false),
        Some("sor") => Ok(true),
        Some(v) => Err(format!("{SETTING}={v}: valid are default and sor")),
    }
}

/// Whether this process runs under the profile. A malformed setting stops
/// sharukhan with a configuration error (EX_CONFIG).
pub fn active() -> bool {
    match parse(std::env::var(SETTING).ok().as_deref()) {
        Ok(on) => on,
        Err(e) => {
            eprintln!("sharukhan: configuration error: {e}");
            std::process::exit(78)
        }
    }
}

/// Whether `r` names an image by its immutable ID.
pub fn by_id(r: &str) -> bool {
    let digest = |d: &str| {
        d.len() == 64
            && d.bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    };
    if let Some(d) = r.strip_prefix("sha256:") {
        return digest(d);
    }
    match r.split_once("@sha256:") {
        Some((name, d)) => !name.is_empty() && !name.chars().any(char::is_whitespace) && digest(d),
        None => false,
    }
}

/// Every input of this invocation the profile refuses. `get` reads a setting,
/// `argv` is the command line without the program name.
pub fn check(get: &dyn Fn(&str) -> Option<String>, argv: &[String]) -> Vec<Finding> {
    let set = |k: &str| get(k).filter(|v| !v.trim().is_empty());
    let mut out = Vec::new();
    let mut refuse = |rule: &'static str, setting: &str, value: &str, expected: &str| {
        out.push(Finding {
            rule,
            setting: setting.to_string(),
            value: value.to_string(),
            expected: expected.to_string(),
        })
    };

    if let Some(cmd) = argv
        .first()
        .map(String::as_str)
        .filter(|c| NETWORK_COMMANDS.contains(c))
    {
        refuse(
            "network",
            "command",
            cmd,
            "a command that reaches no remote (the profile builds and tests from the mirror)",
        );
    }

    for k in OVERRIDES {
        if let Some(v) = set(k) {
            refuse("override", k, &v, "unset: the copy built into sharukhan");
        }
    }

    if let Some(v) = set("MC_ESCALATE").filter(|v| v.trim() != "off") {
        refuse(
            "escalation",
            "MC_ESCALATE",
            &v,
            "off or unset: escalation is disabled under the profile",
        );
    }

    let poi = set("MC_POI_BASE_IMAGE").unwrap_or_else(|| crate::poiimage::DEFAULT_BASE.to_string());
    if !by_id(&poi) {
        refuse(
            "image",
            "MC_POI_BASE_IMAGE",
            &poi,
            "an image by ID (<name>@sha256:<64 hex>)",
        );
    }
    let mut a = argv.iter();
    while let Some(x) = a.next() {
        if x == "--builder-image" {
            if let Some(v) = a.next().filter(|v| !by_id(v)) {
                refuse(
                    "image",
                    "--builder-image",
                    v,
                    "an image by ID (<name>@sha256:<64 hex>)",
                );
            }
        }
    }

    let remote =
        set("MC_PHOTON_REMOTE").unwrap_or_else(|| crate::config::DEFAULT_PHOTON_REMOTE.to_string());
    if !remote.starts_with("file://") {
        refuse(
            "network",
            "MC_PHOTON_REMOTE",
            &remote,
            "a file:// URL of the mirror",
        );
    }
    let mirror = crate::buildexec::sources_mirror_from(get);
    if !mirror.starts_with("file://") {
        refuse(
            "network",
            "MC_SOURCES_MIRROR",
            &mirror,
            "a file:// URL of the mirror",
        );
    }
    out
}

/// What `main` does before any command runs: off, or a command that only
/// reports, passes; otherwise every finding is printed and the run stops.
pub fn enforce(argv: &[String]) -> Result<(), Vec<Finding>> {
    if !active() || argv.first().is_some_and(|c| EXEMPT.contains(&c.as_str())) {
        return Ok(());
    }
    let f = check(&|k: &str| std::env::var(k).ok(), argv);
    if f.is_empty() {
        Ok(())
    } else {
        Err(f)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn compliant(k: &str) -> Option<String> {
        match k {
            "MC_POI_BASE_IMAGE" => Some(format!("photon/installer@sha256:{ID}")),
            "MC_PHOTON_REMOTE" => Some("file:///srv/mirror/photon.git".into()),
            "MC_SOURCES_MIRROR" => Some("file:///srv/mirror/photon_sources/1.0".into()),
            _ => None,
        }
    }

    fn argv(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    fn rules(f: &[Finding]) -> Vec<(&'static str, String)> {
        f.iter().map(|f| (f.rule, f.setting.clone())).collect()
    }

    #[test]
    fn the_profile_is_off_unless_named_and_a_typo_is_an_error() {
        assert_eq!(parse(None), Ok(false));
        assert_eq!(parse(Some("")), Ok(false));
        assert_eq!(parse(Some("default")), Ok(false));
        assert_eq!(parse(Some(" sor ")), Ok(true));
        assert!(parse(Some("SOR")).is_err());
        assert!(parse(Some("record")).is_err());
    }

    #[test]
    fn an_image_counts_only_by_its_id() {
        assert!(by_id(&format!("sha256:{ID}")));
        assert!(by_id(&format!("photon/installer@sha256:{ID}")));
        for bad in [
            "photon/installer:latest".to_string(),
            "photon:5.0".to_string(),
            format!("photon@sha256:{}", &ID[1..]),
            format!("photon@sha256:{}", ID.to_uppercase()),
            format!("@sha256:{ID}"),
            format!("pho ton@sha256:{ID}"),
            format!("sha256:{ID}x"),
        ] {
            assert!(!by_id(&bad), "{bad}");
        }
    }

    // the positive control: a compliant host and a build command pass
    #[test]
    fn a_compliant_configuration_passes() {
        assert_eq!(
            check(&compliant, &argv(&["build", "--iso-type", "minimal"])),
            vec![]
        );
        assert_eq!(check(&compliant, &argv(&["run", "--only", "k03"])), vec![]);
        // MC_ESCALATE=off agrees with the profile
        let off = |k: &str| {
            if k == "MC_ESCALATE" {
                Some("off".into())
            } else {
                compliant(k)
            }
        };
        assert_eq!(check(&off, &argv(&["run"])), vec![]);
        let pinned = argv(&["build", "--builder-image", &format!("sha256:{ID}")]);
        assert_eq!(check(&compliant, &pinned), vec![]);
    }

    // one violation at a time: each rule refuses exactly the input it names
    #[test]
    fn each_rule_refuses_a_single_violation() {
        for k in OVERRIDES {
            let g = |s: &str| {
                if s == *k {
                    Some("/srv/other".into())
                } else {
                    compliant(s)
                }
            };
            assert_eq!(
                rules(&check(&g, &argv(&["run"]))),
                vec![("override", k.to_string())],
                "{k}"
            );
        }

        let esc = |k: &str| {
            if k == "MC_ESCALATE" {
                Some("auto".into())
            } else {
                compliant(k)
            }
        };
        assert_eq!(
            rules(&check(&esc, &argv(&["run"]))),
            vec![("escalation", "MC_ESCALATE".into())]
        );

        let tag = |k: &str| {
            if k == "MC_POI_BASE_IMAGE" {
                Some("photon/installer:latest".into())
            } else {
                compliant(k)
            }
        };
        let f = check(&tag, &argv(&["build"]));
        assert_eq!(rules(&f), vec![("image", "MC_POI_BASE_IMAGE".into())]);
        assert_eq!(
            f[0].value, "photon/installer:latest",
            "the measured value is reported"
        );
        let unset = |k: &str| {
            if k == "MC_POI_BASE_IMAGE" {
                None
            } else {
                compliant(k)
            }
        };
        assert_eq!(
            rules(&check(&unset, &argv(&["build"]))),
            vec![("image", "MC_POI_BASE_IMAGE".into())],
            "the default is a tag"
        );
        let flag = argv(&["build", "--builder-image", "sharukhan-builder:latest"]);
        assert_eq!(
            rules(&check(&compliant, &flag)),
            vec![("image", "--builder-image".into())]
        );

        let https = |k: &str| {
            if k == "MC_PHOTON_REMOTE" {
                Some("https://github.com/dcasota/photon.git".into())
            } else {
                compliant(k)
            }
        };
        assert_eq!(
            rules(&check(&https, &argv(&["run"]))),
            vec![("network", "MC_PHOTON_REMOTE".into())]
        );
        let unset = |k: &str| {
            if k == "MC_SOURCES_MIRROR" {
                None
            } else {
                compliant(k)
            }
        };
        assert_eq!(
            rules(&check(&unset, &argv(&["build"]))),
            vec![("network", "MC_SOURCES_MIRROR".into())],
            "the default mirror is https"
        );

        for cmd in NETWORK_COMMANDS {
            assert_eq!(
                rules(&check(&compliant, &argv(&[cmd]))),
                vec![("network", "command".into())],
                "{cmd}"
            );
        }
    }

    #[test]
    fn a_finding_names_the_setting_the_value_and_what_was_expected() {
        let tag = |k: &str| {
            if k == "MC_POI_BASE_IMAGE" {
                Some("photon/installer:latest".into())
            } else {
                compliant(k)
            }
        };
        let s = check(&tag, &argv(&["build"]))[0].to_string();
        assert!(
            s.contains("MC_POI_BASE_IMAGE=photon/installer:latest"),
            "{s}"
        );
        assert!(s.contains("expected an image by ID"), "{s}");
    }
}
