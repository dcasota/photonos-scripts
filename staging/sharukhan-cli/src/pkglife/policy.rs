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
pub struct Cli {
    pub probes: Vec<Vec<String>>,
    pub stderr_error_markers: Vec<String>,
    pub never_execute: Vec<Rule>,
    pub version_query: Vec<VersionQuery>,
    pub no_version_query: Vec<PathRule>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Units {
    pub network_ordering: Vec<String>,
    pub protected: Vec<Rule>,
    pub never_start: Vec<Rule>,
    pub network_affecting: Vec<Rule>,
    pub requires_config: Vec<Rule>,
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
