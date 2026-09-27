//! Version probes for the executables a package ships.
//!
//! The safety policy, in the order it is applied:
//!
//! 1. **Never a bare invocation.** Every probe carries an argument
//!    (`--version`, `-V`, ...); the policy loader refuses an empty one.
//! 2. **Denylist by name** (`cli.never_execute`): power-state, partitioning,
//!    filesystem-creation and process-signalling tools are not executed at
//!    all, each entry with its reason. Reviewed per-binary exceptions for
//!    tools that have no version query live in `cli.no_version_query`.
//! 3. **A sandbox for everything that does run.** The probe is a transient
//!    systemd service: a dynamic unprivileged user, no capabilities, no
//!    network (loopback only), no devices, a read-only root, a private /tmp
//!    as the working directory, no set-uid elevation, `@reboot @swap @mount
//!    @module @raw-io @clock` system calls refused, a runtime ceiling, task,
//!    memory and file-size limits, stdin at end-of-file. A tool that
//!    misreads `version` as an operand can at most write into a private
//!    /tmp that vanishes with it.
//!
//! A probe PASSES when it exits 0, prints something, the output carries a
//! version token (the package's own version, or a dotted number), and stderr
//! is free of the error markers in the policy. The first passing probe ends
//! the search; every attempt is recorded either way.

use crate::pkglife::policy::{first_match, Policy};
use crate::pkglife::record::{clip, CliResult, ProbeAttempt, FAIL, PASS, SKIP};
use crate::pkglife::remote::{argv, Remote};

/// The transient unit's sandbox. Each property is one hardening measure; see
/// systemd.exec(5).
pub const SANDBOX: [&str; 32] = [
    // A fixed unprivileged account, not DynamicUser: Photon resolves users
    // from files only (no nss-systemd), and a dynamic uid absent from
    // /etc/passwd made cronie's crontab refuse "your UID isn't in the passwd
    // file" before printing anything (measured on k09).
    "User=nobody",
    "PrivateNetwork=yes",
    "PrivateDevices=yes",
    "PrivateTmp=yes",
    "PrivateIPC=yes",
    "ProtectSystem=strict",
    "ProtectHome=yes",
    "ProtectKernelTunables=yes",
    "ProtectKernelModules=yes",
    "ProtectKernelLogs=yes",
    "ProtectControlGroups=yes",
    "ProtectClock=yes",
    "ProtectHostname=yes",
    "NoNewPrivileges=yes",
    "RestrictSUIDSGID=yes",
    "RestrictRealtime=yes",
    "LockPersonality=yes",
    "CapabilityBoundingSet=",
    "AmbientCapabilities=",
    "SystemCallFilter=~@reboot",
    "SystemCallFilter=~@swap",
    "SystemCallFilter=~@mount",
    "SystemCallFilter=~@module",
    "SystemCallFilter=~@raw-io",
    "SystemCallFilter=~@clock",
    "SystemCallFilter=~@cpu-emulation",
    "TasksMax=64",
    "MemoryMax=512M",
    "LimitFSIZE=4M",
    "LimitCORE=0",
    "WorkingDirectory=/tmp",
    "UMask=0077",
];

/// The command line that runs `exe args...` inside the sandbox as the
/// transient unit `unit`, bounded to `secs` by systemd itself.
pub fn sandboxed(unit: &str, secs: u64, exe: &str, args: &[&str]) -> Result<String, String> {
    let runtime = format!("RuntimeMaxSec={secs}");
    let unit_arg = format!("--unit={unit}");
    let mut v: Vec<&str> = vec![
        "systemd-run",
        "--quiet",
        "--wait",
        "--pipe",
        "--collect",
        "--service-type=exec",
        &unit_arg,
        "-p",
        &runtime,
    ];
    for p in SANDBOX.iter() {
        v.push("-p");
        v.push(p);
    }
    v.push("--");
    v.push(exe);
    v.extend_from_slice(args);
    Ok(format!("{} </dev/null", argv(&v)?))
}

/// A version token: the package's own version string, else the first run of
/// digits containing a dot between digits ("4.3", "2.42.3", "1.30.4-2").
pub fn version_token(text: &str, pkg_version: &str) -> Option<String> {
    if !pkg_version.is_empty() && text.contains(pkg_version) {
        return Some(pkg_version.to_string());
    }
    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i].is_ascii_digit() {
            let start = i;
            while i < b.len() && (b[i].is_ascii_digit() || b[i] == b'.') {
                i += 1;
            }
            let tok = text[start..i].trim_end_matches('.');
            let dotted =
                tok.split('.').filter(|p| !p.is_empty()).count() >= 2 && !tok.contains("..");
            if dotted {
                return Some(tok.to_string());
            }
        } else {
            i += 1;
        }
    }
    None
}

/// The first policy error marker in `stderr`, case-insensitively.
pub fn error_marker<'a>(stderr: &str, markers: &'a [String]) -> Option<&'a str> {
    let low = stderr.to_lowercase();
    markers
        .iter()
        .find(|m| low.contains(&m.to_lowercase()))
        .map(String::as_str)
}

/// Judge one probe from what it measured. Ok carries the version token.
pub fn judge(
    code: Option<i32>,
    timed_out: bool,
    stdout: &str,
    stderr: &str,
    pkg_version: &str,
    markers: &[String],
) -> Result<String, String> {
    if timed_out {
        return Err("did not finish (killed at the deadline)".into());
    }
    match code {
        Some(0) => {}
        Some(c) => return Err(format!("exit status {c}")),
        None => return Err("no exit status (killed or not started)".into()),
    }
    if stdout.trim().is_empty() && stderr.trim().is_empty() {
        return Err("exit 0 but printed nothing".into());
    }
    if let Some(m) = error_marker(stderr, markers) {
        return Err(format!("stderr carries {m:?}: {}", clip(stderr.trim())));
    }
    let both = format!("{stdout}\n{stderr}");
    version_token(&both, pkg_version).ok_or_else(|| "exit 0 but no version in the output".into())
}

/// Probe one executable. `seq` makes each transient unit name unique.
pub fn probe(
    r: &mut dyn Remote,
    policy: &Policy,
    exe: &str,
    pkg_version: &str,
    unit_prefix: &str,
    seq: &mut u64,
) -> CliResult {
    let mut res = CliResult {
        path: exe.to_string(),
        ..Default::default()
    };
    let base = exe.rsplit('/').next().unwrap_or(exe);
    if let Some(rule) = first_match(&policy.cli.never_execute, base) {
        res.status = SKIP.into();
        res.reason = format!("never executed ({}): {}", rule.pattern, rule.reason);
        return res;
    }
    if let Some(rule) = policy.no_version_query(exe) {
        res.status = SKIP.into();
        res.reason = format!("no version query (reviewed): {}", rule.reason);
        return res;
    }
    let secs = policy.limits.probe_secs;
    // A reviewed alternative replaces the generic probes for this tool; it is
    // judged exactly like them.
    let override_probe: Vec<Vec<String>>;
    let probes = match policy.version_query(base) {
        Some(v) => {
            override_probe = vec![v.args.clone()];
            &override_probe
        }
        None => &policy.cli.probes,
    };
    for args in probes {
        *seq += 1;
        let unit = format!("{unit_prefix}-{seq}");
        let a: Vec<&str> = args.iter().map(String::as_str).collect();
        let cmd = match sandboxed(&unit, secs, exe, &a) {
            Ok(c) => c,
            Err(e) => {
                res.status = FAIL.into();
                res.reason = e;
                return res;
            }
        };
        let e = r.exec(&cmd, None, secs + 10);
        let verdict = judge(
            e.code,
            e.timed_out,
            &e.stdout,
            &e.stderr,
            pkg_version,
            &policy.cli.stderr_error_markers,
        );
        // systemd's RuntimeMaxSec ends a hung probe with a plain failure
        // status; the elapsed time is what says it hung.
        let hung = e.elapsed_ms >= secs * 1000;
        res.attempts.push(ProbeAttempt {
            args: args.clone(),
            code: e.code,
            timed_out: e.timed_out || hung,
            ms: e.elapsed_ms,
            stdout: clip(&e.stdout),
            stderr: clip(&e.stderr),
            verdict: format!(
                "{}{}",
                match &verdict {
                    Ok(v) => format!("version {v}"),
                    Err(why) if hung => format!("hung: ended at the {secs}s runtime limit ({why})"),
                    Err(why) => why.clone(),
                },
                if e.truncated {
                    " (output beyond the capture limit discarded)"
                } else {
                    ""
                }
            ),
        });
        if let Ok(v) = verdict {
            res.status = PASS.into();
            res.reason = format!("`{} {}` -> version {v}", base, args.join(" "));
            return res;
        }
    }
    res.status = FAIL.into();
    res.reason = format!(
        "no version probe succeeded ({} tried: {})",
        res.attempts.len(),
        res.attempts
            .iter()
            .map(|a| format!("{} -> {}", a.args.join(" "), a.verdict))
            .collect::<Vec<_>>()
            .join("; ")
    );
    res
}

/// Proof that the sandbox is in force on this guest: the unit's user is not
/// root, it sees only loopback, and the root filesystem is read-only to it.
/// Returns the measured values on success; the reason on failure.
pub const SANDBOX_CONTROL_SCRIPT: &str = "id -u; ls /sys/class/net | tr '\\n' ' '; echo; \
     if touch /usr/.sharukhan-sandbox-probe 2>/dev/null; then echo writable; else echo read-only; fi";

pub fn judge_sandbox(stdout: &str) -> Result<String, String> {
    let lines: Vec<&str> = stdout.lines().map(str::trim).collect();
    let (Some(uid), Some(net), Some(fs)) = (lines.first(), lines.get(1), lines.get(2)) else {
        return Err(format!("unexpected sandbox control output: {stdout:?}"));
    };
    let uid_ok = uid.parse::<u32>().map(|u| u != 0).unwrap_or(false);
    if !uid_ok {
        return Err(format!(
            "probes would run as uid {uid:?}, not an unprivileged user"
        ));
    }
    if *net != "lo" {
        return Err(format!(
            "probes would see network interfaces {net:?}, not only lo"
        ));
    }
    if *fs != "read-only" {
        return Err(format!("the root filesystem is {fs} inside the sandbox"));
    }
    Ok(format!("uid {uid}, interfaces [{net}], root {fs}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pkglife::remote::fake::{self, Fake};

    fn markers() -> Vec<String> {
        Policy::embedded().unwrap().cli.stderr_error_markers
    }

    #[test]
    fn version_tokens() {
        assert_eq!(version_token("RPM version 6.1.0", ""), Some("6.1.0".into()));
        assert_eq!(
            version_token("chronyc (chrony) version 4.3 (+READLINE)", "4.3"),
            Some("4.3".into())
        );
        assert_eq!(
            version_token("nginx version: nginx/1.30.4", ""),
            Some("1.30.4".into())
        );
        assert_eq!(version_token("tool 7", "7"), Some("7".into()));
        assert_eq!(version_token("v2.", ""), None);
        assert_eq!(version_token("no digits here", "1.0"), None);
        assert_eq!(version_token("1..2", ""), None);
        assert_eq!(version_token("build 20260927", ""), None);
    }

    #[test]
    fn a_probe_passes_only_with_status_zero_output_and_a_version() {
        let m = markers();
        assert_eq!(
            judge(Some(0), false, "RPM version 6.1.0\n", "", "", &m).unwrap(),
            "6.1.0"
        );
        // java prints its version on stderr; that is not an error
        assert!(judge(
            Some(0),
            false,
            "",
            "openjdk version \"17.0.9\" 2023-10-17",
            "",
            &m
        )
        .is_ok());
        // GNU false prints its version and exits 1: the negative control
        assert_eq!(
            judge(Some(1), false, "false (GNU coreutils) 9.1", "", "", &m).unwrap_err(),
            "exit status 1"
        );
        assert!(judge(Some(0), false, "", "", "", &m)
            .unwrap_err()
            .contains("nothing"));
        assert!(judge(Some(0), false, "usage", "", "", &m)
            .unwrap_err()
            .contains("no version"));
        assert!(judge(Some(0), false, "x 1.2", "Error: bad", "", &m)
            .unwrap_err()
            .contains("error"));
        assert!(judge(Some(0), false, "x 1.2", "unrecognized option '-V'", "", &m).is_err());
        assert!(judge(None, true, "", "", "", &m)
            .unwrap_err()
            .contains("deadline"));
        assert!(judge(None, false, "", "", "", &m).is_err());
    }

    #[test]
    fn the_sandbox_line_is_an_argument_vector_with_every_measure() {
        let c = sandboxed("sharukhan-probe-1", 10, "/usr/bin/x", &["--version"]).unwrap();
        assert!(c.starts_with("'systemd-run' '--quiet' '--wait' '--pipe' '--collect'"));
        assert!(c.contains("'--unit=sharukhan-probe-1'"));
        assert!(c.contains("'RuntimeMaxSec=10'"));
        for p in SANDBOX {
            assert!(c.contains(&format!("'-p' '{p}'")), "{p} missing");
        }
        assert!(c.ends_with("'--' '/usr/bin/x' '--version' </dev/null"));
        // a hostile path stays one argument
        let c = sandboxed("u", 1, "/usr/bin/a'; reboot; '", &["-V"]).unwrap();
        assert!(c.contains("'/usr/bin/a'\\''; reboot; '\\'''"));
    }

    #[test]
    fn denylisted_binaries_are_never_sent_to_the_guest() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        let mut seq = 0;
        for exe in [
            "/usr/sbin/shutdown",
            "/usr/sbin/mkfs.xfs",
            "/usr/bin/dd",
            "/sbin/fdisk",
        ] {
            let r = probe(&mut f, &p, exe, "1.0", "sharukhan-probe", &mut seq);
            assert_eq!(r.status, SKIP, "{exe}");
            assert!(r.reason.starts_with("never executed"), "{}", r.reason);
        }
        assert!(f.log.borrow().is_empty(), "something reached the guest");
    }

    #[test]
    fn probes_stop_at_the_first_success_and_record_every_attempt() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        f.on(
            "'--version'",
            fake::rc(1, "", "tool: unrecognized option '--version'"),
        )
        .on("'-V'", fake::ok("tool 2.4.1\n"));
        let mut seq = 0;
        let r = probe(
            &mut f,
            &p,
            "/usr/bin/tool",
            "2.4.1",
            "sharukhan-probe-t",
            &mut seq,
        );
        assert_eq!(r.status, PASS, "{r:?}");
        assert_eq!(r.attempts.len(), 2);
        assert_eq!(r.attempts[0].verdict, "exit status 1");
        assert!(r.reason.contains("tool -V"));
        assert_eq!(seq, 2);
        assert_eq!(f.ran("sharukhan-probe-t-1"), 1);
        assert_eq!(f.ran("sharukhan-probe-t-2"), 1);
    }

    #[test]
    fn a_binary_without_any_version_query_fails_with_every_attempt_named() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        f.on("systemd-run", fake::rc(2, "", "usage: tool FILE"));
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/bin/tool", "1", "u", &mut seq);
        assert_eq!(r.status, FAIL);
        assert_eq!(r.attempts.len(), p.cli.probes.len());
        assert!(
            r.reason.contains("--version -> exit status 2"),
            "{}",
            r.reason
        );
    }

    #[test]
    fn a_hung_probe_is_named_as_hung() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        let mut slow = fake::rc(1, "", "");
        slow.elapsed_ms = p.limits.probe_secs * 1000 + 50;
        f.on("systemd-run", slow);
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/bin/cat", "1", "u", &mut seq);
        assert_eq!(r.status, FAIL);
        assert!(r
            .attempts
            .iter()
            .all(|a| a.timed_out && a.verdict.starts_with("hung")));
    }

    #[test]
    fn the_sandbox_control_needs_all_three_properties() {
        assert!(judge_sandbox("61234\nlo \nread-only\n").is_ok());
        assert!(judge_sandbox("0\nlo \nread-only\n")
            .unwrap_err()
            .contains("uid"));
        assert!(judge_sandbox("61234\neth0 lo \nread-only\n")
            .unwrap_err()
            .contains("interfaces"));
        assert!(judge_sandbox("61234\nlo \nwritable\n")
            .unwrap_err()
            .contains("writable"));
        assert!(judge_sandbox("").is_err());
        assert!(judge_sandbox("x\nlo\nread-only").is_err());
    }
}
