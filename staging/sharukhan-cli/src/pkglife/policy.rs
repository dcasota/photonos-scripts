//! The reviewed safety and override policy.
//!
//! The policy is data, not code: `schema/package-lifecycle-policy.json`,
//! embedded at build time so a verdict can always name the exact policy that
//! produced it (the sha256 goes into the evidence). An operator can test a
//! change with `--pkg-policy <file>`; the same validation applies.
//!
//! Validation is strict: unknown fields are refused, every rule needs a reason
//! a reader can act on, and a version probe that could run a binary with no
//! argument at all is refused outright.

use serde::Deserialize;

pub const EMBEDDED: &str = include_str!("../../schema/package-lifecycle-policy.json");

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    pub pattern: String,
    pub reason: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PathRule {
    pub path: String,
    pub reason: String,
}

/// A reviewed alternative version query for tools that have no `--version`
/// style option. It is still a probe: it must exit 0 and print a version.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VersionQuery {
    pub pattern: String,
    pub args: Vec<String>,
    /// The exit status that answers the query. 0 unless the tool is
    /// documented to exit otherwise after printing its version (GNU `false`).
    #[serde(default)]
    pub exit: i32,
    pub reason: String,
}

/// Output that only a broken installation produces: the dynamic loader, an
/// interpreter or a language runtime saying that something the program needs
/// is not there. Every string in `all` must appear on ONE line.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Signature {
    pub name: String,
    pub all: Vec<String>,
    pub reason: String,
}

/// A reviewed tool that cannot answer a version query on the bench, and the
/// exact words it says why. The probe still runs; only those words, with no
/// defect signature anywhere, make it a skip.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Precondition {
    pub pattern: String,
    pub marker: String,
    pub reason: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Limits {
    pub query_secs: u64,
    pub install_secs: u64,
    pub remove_secs: u64,
    pub unit_start_secs: u64,
    pub unit_stop_secs: u64,
    pub stability_secs: u64,
    pub deadman_secs: u64,
    pub probe_secs: u64,
    pub max_probes_per_package: usize,
    pub reconnect_secs: u64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Packages {
    pub never_install: Vec<Rule>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CliPrecondition {
    pub pattern: String,
    /// The tool's own words, quoted from a measured probe.
    #[serde(default)]
    pub marker: Option<String>,
    /// A tool that answers every probe with one of these statuses and no
    /// output.
    #[serde(default)]
    pub exit: Option<Vec<i32>>,
    /// A tool that waits for something the sandbox does not provide and is
    /// ended by the runtime limit on every probe.
    #[serde(default)]
    pub hangs: bool,
    /// A tool whose whole answer to every probe is exactly this text (a
    /// number, a prompt): too short to be a marker, exact enough as output.
    #[serde(default)]
    pub output: Option<String>,
    pub reason: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Cli {
    pub probes: Vec<Vec<String>>,
    pub stderr_error_markers: Vec<String>,
    pub never_execute: Vec<Rule>,
    pub version_query: Vec<VersionQuery>,
    pub no_version_query: Vec<PathRule>,
    /// Checked first, on every probe: a match fails the CLI whatever else
    /// the probes showed.
    pub defect_signatures: Vec<Signature>,
    /// The tool's own option parser refusing a probe argument: the program
    /// ran and has no such option.
    pub option_rejection_markers: Vec<String>,
    /// The tool refusing to run as an unprivileged user, in its own words.
    pub privilege_refusal_markers: Vec<String>,
    pub preconditions: Vec<CliPrecondition>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Units {
    pub network_ordering: Vec<String>,
    pub protected: Vec<Rule>,
    pub never_start: Vec<Rule>,
    pub network_affecting: Vec<Rule>,
    pub requires_config: Vec<Rule>,
    /// Reviewed err-priority lines that are not a defect of the package on
    /// this bench: the unit or syslog identifier (glob) and the exact words.
    pub expected_errors: Vec<Precondition>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Policy {
    pub schema: u32,
    pub reviewed: String,
    /// Prose for the human reading the JSON; parsed so an unknown-field
    /// check can stay strict, never used by the code.
    #[allow(dead_code)]
    pub about: String,
    pub limits: Limits,
    pub boot_paths: Vec<String>,
    pub packages: Packages,
    pub cli: Cli,
    pub units: Units,
    /// sha256 of the text it was parsed from; filled by [`Policy::parse`].
    #[serde(skip)]
    pub sha256: String,
}

/// `*` matches any run of characters, `?` exactly one. Nothing else is
/// special: a policy pattern is a name, not a regular expression.
pub fn glob(pattern: &str, text: &str) -> bool {
    let p: Vec<char> = pattern.chars().collect();
    let t: Vec<char> = text.chars().collect();
    let (mut pi, mut ti) = (0usize, 0usize);
    let (mut star, mut mark) = (None::<usize>, 0usize);
    while ti < t.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star = Some(pi);
            mark = ti;
            pi += 1;
        } else if let Some(s) = star {
            pi = s + 1;
            mark += 1;
            ti = mark;
        } else {
            return false;
        }
    }
    while pi < p.len() && p[pi] == '*' {
        pi += 1;
    }
    pi == p.len()
}

/// The first rule whose pattern matches, if any.
pub fn first_match<'a>(rules: &'a [Rule], name: &str) -> Option<&'a Rule> {
    rules.iter().find(|r| glob(&r.pattern, name))
}

fn check_rules(section: &str, rules: &[Rule]) -> Result<(), String> {
    for (i, r) in rules.iter().enumerate() {
        let ok_pattern = !r.pattern.is_empty()
            && r.pattern.len() <= 200
            && r.pattern
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "._@*?+-:\\".contains(c));
        if !ok_pattern {
            return Err(format!(
                "{section}[{i}]: pattern {:?} is not a name glob",
                r.pattern
            ));
        }
        if r.reason.trim().len() < 10 {
            return Err(format!(
                "{section}[{i}] ({}): a rule needs a reason a reader can act on",
                r.pattern
            ));
        }
    }
    Ok(())
}

/// A probe argument: an option or a bare word, nothing a shell or the tool
/// could read as a path, an assignment or a second command.
fn probe_arg_ok(a: &str) -> bool {
    let body = a.trim_start_matches('-');
    a.len() <= 32
        && a.len() - body.len() <= 2
        && !body.is_empty()
        && body.chars().all(|c| c.is_ascii_alphanumeric())
}

impl Policy {
    pub fn parse(text: &str) -> Result<Policy, String> {
        let mut p: Policy =
            serde_json::from_str(text).map_err(|e| format!("package-lifecycle policy: {e}"))?;
        p.sha256 = crate::sha256::bytes(text.as_bytes());
        p.validate()?;
        Ok(p)
    }

    pub fn embedded() -> Result<Policy, String> {
        Policy::parse(EMBEDDED)
    }

    pub fn load(path: Option<&std::path::Path>) -> Result<Policy, String> {
        match path {
            None => Policy::embedded(),
            Some(p) => {
                let t = std::fs::read_to_string(p).map_err(|e| format!("{}: {e}", p.display()))?;
                Policy::parse(&t).map_err(|e| format!("{}: {e}", p.display()))
            }
        }
    }

    fn validate(&self) -> Result<(), String> {
        if self.schema != 1 {
            return Err(format!(
                "unsupported policy schema {} (this build reads 1)",
                self.schema
            ));
        }
        let l = &self.limits;
        for (name, v, lo, hi) in [
            ("query_secs", l.query_secs, 5, 3600),
            ("install_secs", l.install_secs, 30, 7200),
            ("remove_secs", l.remove_secs, 30, 7200),
            ("unit_start_secs", l.unit_start_secs, 5, 900),
            ("unit_stop_secs", l.unit_stop_secs, 5, 900),
            ("stability_secs", l.stability_secs, 1, 120),
            ("deadman_secs", l.deadman_secs, 10, 600),
            ("probe_secs", l.probe_secs, 1, 120),
            ("reconnect_secs", l.reconnect_secs, 30, 1800),
        ] {
            if !(lo..=hi).contains(&v) {
                return Err(format!("limits.{name} = {v} is outside {lo}..={hi}"));
            }
        }
        if l.max_probes_per_package == 0 {
            return Err("limits.max_probes_per_package must be at least 1".into());
        }
        if self.boot_paths.is_empty()
            || self
                .boot_paths
                .iter()
                .any(|b| !b.starts_with('/') || !b.ends_with('/'))
        {
            return Err(
                "boot_paths must be non-empty absolute directory prefixes ending in '/'".into(),
            );
        }
        if self.cli.probes.is_empty() {
            return Err("cli.probes is empty: no CLI could ever be tested".into());
        }
        for (i, probe) in self.cli.probes.iter().enumerate() {
            // Never run a binary with no argument: that is the one invocation
            // most likely to DO something rather than describe itself.
            if probe.is_empty() {
                return Err(format!(
                    "cli.probes[{i}] has no argument; a bare invocation is never allowed"
                ));
            }
            if let Some(a) = probe.iter().find(|a| !probe_arg_ok(a)) {
                return Err(format!(
                    "cli.probes[{i}]: argument {a:?} is not a plain option or word"
                ));
            }
        }
        if self
            .cli
            .stderr_error_markers
            .iter()
            .any(|m| m.trim().is_empty())
        {
            return Err(
                "cli.stderr_error_markers contains an empty marker, which would match everything"
                    .into(),
            );
        }
        check_rules("packages.never_install", &self.packages.never_install)?;
        check_rules("cli.never_execute", &self.cli.never_execute)?;
        let as_rules: Vec<Rule> = self
            .cli
            .version_query
            .iter()
            .map(|v| Rule {
                pattern: v.pattern.clone(),
                reason: v.reason.clone(),
            })
            .collect();
        check_rules("cli.version_query", &as_rules)?;
        for (i, v) in self.cli.version_query.iter().enumerate() {
            if v.args.is_empty() {
                return Err(format!(
                    "cli.version_query[{i}] has no argument; a bare invocation is never allowed"
                ));
            }
            if let Some(a) = v.args.iter().find(|a| !probe_arg_ok(a)) {
                return Err(format!(
                    "cli.version_query[{i}]: argument {a:?} is not a plain option or word"
                ));
            }
        }
        for (i, v) in self.cli.version_query.iter().enumerate() {
            if !(0..=255).contains(&v.exit) {
                return Err(format!(
                    "cli.version_query[{i}]: exit {} is not an exit status",
                    v.exit
                ));
            }
        }
        if self.cli.defect_signatures.is_empty() {
            return Err(
                "cli.defect_signatures is empty: a broken installation would read as a tool without a version query"
                    .into(),
            );
        }
        for (i, sig) in self.cli.defect_signatures.iter().enumerate() {
            if sig.name.trim().is_empty()
                || sig.all.is_empty()
                || sig.all.iter().any(|m| m.trim().len() < 3)
                || sig.reason.trim().len() < 10
            {
                return Err(format!(
                    "cli.defect_signatures[{i}] ({:?}): needs a name, markers of at least 3 characters and a reason",
                    sig.name
                ));
            }
        }
        for (name, list) in [
            (
                "cli.option_rejection_markers",
                &self.cli.option_rejection_markers,
            ),
            (
                "cli.privilege_refusal_markers",
                &self.cli.privilege_refusal_markers,
            ),
        ] {
            if list.iter().any(|m| m.trim().len() < 4) {
                return Err(format!(
                    "{name} contains a marker shorter than 4 characters, which would match almost anything"
                ));
            }
        }
        let as_rules: Vec<Rule> = self
            .cli
            .preconditions
            .iter()
            .map(|v| Rule {
                pattern: v.pattern.clone(),
                reason: v.reason.clone(),
            })
            .collect();
        check_rules("cli.preconditions", &as_rules)?;
        for (i, c) in self.cli.preconditions.iter().enumerate() {
            let kinds = c.marker.is_some() as u8
                + c.exit.is_some() as u8
                + c.hangs as u8
                + c.output.is_some() as u8;
            if kinds != 1 {
                return Err(format!(
                    "cli.preconditions[{i}] ({}): exactly one of marker, exit, hangs, output",
                    c.pattern
                ));
            }
            if c.marker.as_deref().map(|m| m.trim().len() < 6).unwrap_or(false) {
                return Err(format!(
                    "cli.preconditions[{i}] ({}): the marker must quote the tool, at least 6 characters",
                    c.pattern
                ));
            }
            if let Some(e) = &c.exit {
                if e.is_empty() || e.iter().any(|x| !(1..=255).contains(x)) {
                    return Err(format!(
                        "cli.preconditions[{i}] ({}): exit must list failing statuses 1..=255",
                        c.pattern
                    ));
                }
            }
        }
        for (i, r) in self.cli.no_version_query.iter().enumerate() {
            if !r.path.starts_with('/') || r.reason.trim().len() < 10 {
                return Err(format!(
                    "cli.no_version_query[{i}]: needs an absolute path and a reason"
                ));
            }
        }
        check_rules("units.protected", &self.units.protected)?;
        check_rules("units.never_start", &self.units.never_start)?;
        check_rules("units.network_affecting", &self.units.network_affecting)?;
        check_rules("units.requires_config", &self.units.requires_config)?;
        let as_rules: Vec<Rule> = self
            .units
            .expected_errors
            .iter()
            .map(|v| Rule {
                pattern: v.pattern.clone(),
                reason: v.reason.clone(),
            })
            .collect();
        check_rules("units.expected_errors", &as_rules)?;
        for (i, c) in self.units.expected_errors.iter().enumerate() {
            if c.marker.trim().len() < 10 {
                return Err(format!(
                    "units.expected_errors[{i}] ({}): the marker must quote the line, at least 10 characters",
                    c.pattern
                ));
            }
        }
        if self.units.network_ordering.is_empty() {
            return Err(
                "units.network_ordering is empty: firewalls would not be recognised".into(),
            );
        }
        Ok(())
    }

    pub fn is_boot_path(&self, path: &str) -> bool {
        self.boot_paths.iter().any(|b| path.starts_with(b.as_str()))
    }

    /// The reviewed alternative query for an executable's base name, if any.
    pub fn version_query(&self, base: &str) -> Option<&VersionQuery> {
        self.cli
            .version_query
            .iter()
            .find(|v| glob(&v.pattern, base))
    }

    /// The reviewed entry that explains an err-priority journal line, if any:
    /// its unit or syslog identifier matches the pattern and its message
    /// carries the marker.
    pub fn expected_error(
        &self,
        unit: &str,
        identifier: &str,
        message: &str,
    ) -> Option<&Precondition> {
        self.units.expected_errors.iter().find(|c| {
            (glob(&c.pattern, unit) || glob(&c.pattern, identifier))
                && message.contains(c.marker.as_str())
        })
    }

    /// The reviewed preconditions for an executable's base name.
    pub fn preconditions(&self, base: &str) -> Vec<&CliPrecondition> {
        self.cli
            .preconditions
            .iter()
            .filter(|c| glob(&c.pattern, base))
            .collect()
    }

    pub fn no_version_query(&self, path: &str) -> Option<&PathRule> {
        self.cli.no_version_query.iter().find(|r| r.path == path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_embedded_policy_is_valid_and_fingerprinted() {
        let p = Policy::embedded().unwrap();
        assert_eq!(p.sha256.len(), 64);
        assert!(p.cli.probes.iter().all(|a| !a.is_empty()));
        assert!(first_match(&p.cli.never_execute, "mkfs.ext4").is_some());
        assert!(first_match(&p.cli.never_execute, "shutdown").is_some());
        assert!(first_match(&p.cli.never_execute, "chronyc").is_none());
        assert!(first_match(&p.units.protected, "sshd.service").is_some());
        assert!(first_match(&p.units.never_start, "google-guest-agent.service").is_some());
        assert!(p.is_boot_path("/boot/vmlinuz-6.12"));
        assert!(!p.is_boot_path("/usr/bin/boot"));
    }

    #[test]
    fn globs_are_names_not_regexes() {
        assert!(glob("mkfs.*", "mkfs.xfs"));
        assert!(!glob("mkfs.*", "mkfs"));
        assert!(glob("mkfs", "mkfs"));
        assert!(glob("a*b*c", "aXXbYYc"));
        assert!(!glob("a*b*c", "aXXbYY"));
        assert!(glob("?d", "dd"));
        assert!(!glob("dd", "ddx"));
        assert!(glob("*", ""));
        assert!(!glob("", "x"));
        assert!(glob(
            "tdnf-automatic*.timer",
            "tdnf-automatic-install.timer"
        ));
        // '.' is literal
        assert!(!glob("a.b", "axb"));
    }

    fn with(edit: impl Fn(&mut serde_json::Value)) -> Result<Policy, String> {
        let mut v: serde_json::Value = serde_json::from_str(EMBEDDED).unwrap();
        edit(&mut v);
        Policy::parse(&v.to_string())
    }

    #[test]
    fn a_bare_invocation_can_never_be_configured() {
        let e = with(|v| v["cli"]["probes"] = serde_json::json!([["--version"], []])).unwrap_err();
        assert!(e.contains("bare invocation"), "{e}");
        let e = with(|v| v["cli"]["probes"] = serde_json::json!([])).unwrap_err();
        assert!(e.contains("empty"), "{e}");
    }

    #[test]
    fn probe_arguments_are_plain_options() {
        for bad in [
            "--version;reboot",
            "/etc/passwd",
            "---x",
            "-",
            "a=b",
            "$(id)",
            "",
        ] {
            let e = with(|v| v["cli"]["probes"] = serde_json::json!([[bad]]));
            assert!(e.is_err(), "{bad:?} accepted");
        }
        for ok in ["--version", "-V", "version", "-version", "--help"] {
            assert!(probe_arg_ok(ok), "{ok}");
        }
    }

    #[test]
    fn a_version_query_override_is_held_to_the_probe_rules() {
        let e = with(|v| {
            v["cli"]["version_query"] =
                serde_json::json!([{"pattern":"x","args":[],"reason":"a long enough reason"}])
        })
        .unwrap_err();
        assert!(e.contains("bare invocation"), "{e}");
        assert!(with(|v| {
            v["cli"]["version_query"] =
                serde_json::json!([{"pattern":"x","args":["a;b"],"reason":"a long enough reason"}])
        })
        .is_err());
        let p = with(|v| {
            v["cli"]["version_query"] =
                serde_json::json!([{"pattern":"7z*","args":["i"],"reason":"a long enough reason"}])
        })
        .unwrap();
        assert_eq!(p.version_query("7zz").unwrap().args, vec!["i"]);
        assert!(p.version_query("tar").is_none());
    }

    #[test]
    fn every_rule_needs_a_reason_and_a_sane_pattern() {
        let e = with(|v| {
            v["units"]["never_start"] = serde_json::json!([{"pattern":"x.service","reason":"no"}])
        })
        .unwrap_err();
        assert!(e.contains("reason"), "{e}");
        let e = with(|v| {
            v["cli"]["never_execute"] =
                serde_json::json!([{"pattern":"a b","reason":"a long enough reason"}])
        })
        .unwrap_err();
        assert!(e.contains("not a name glob"), "{e}");
    }

    #[test]
    fn unknown_fields_and_out_of_range_limits_are_refused() {
        assert!(with(|v| v["surprise"] = serde_json::json!(1)).is_err());
        assert!(with(|v| v["limits"]["probe_secs"] = serde_json::json!(0)).is_err());
        assert!(with(|v| v["limits"]["max_probes_per_package"] = serde_json::json!(0)).is_err());
        assert!(with(|v| v["schema"] = serde_json::json!(2)).is_err());
        assert!(with(|v| v["boot_paths"] = serde_json::json!(["boot"])).is_err());
        assert!(with(|v| v["units"]["network_ordering"] = serde_json::json!([])).is_err());
        assert!(with(|v| v["cli"]["stderr_error_markers"] = serde_json::json!([" "])).is_err());
        assert!(with(|v| {
            v["cli"]["no_version_query"] =
                serde_json::json!([{"path":"rel","reason":"a long enough reason"}])
        })
        .is_err());
        assert!(Policy::parse("{").is_err());
    }

    #[test]
    fn a_policy_file_is_loaded_and_errors_name_it() {
        let d = std::env::temp_dir().join(format!("sharukhan-pol-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("p.json");
        std::fs::write(&f, EMBEDDED).unwrap();
        let p = Policy::load(Some(&f)).unwrap();
        assert_eq!(p.sha256, Policy::embedded().unwrap().sha256);
        std::fs::write(&f, "{}").unwrap();
        assert!(Policy::load(Some(&f)).unwrap_err().contains("p.json"));
        assert!(Policy::load(Some(&d.join("missing.json"))).is_err());
        std::fs::remove_dir_all(&d).ok();
    }
}
