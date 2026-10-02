//! Version probes for the executables a package ships.
//!
//! The safety policy, in the order it is applied:
//!
//! 1. **Never a bare invocation.** Every probe carries an argument
//!    (`--version`, `-V`, ...); the policy loader refuses an empty one.
//! 2. **Denylist by name** (`cli.never_execute`): power-state, partitioning,
//!    filesystem-creation and process-signalling tools are not executed at
//!    all, each entry with its reason.
//! 3. **A sandbox for everything that does run.** The probe is a transient
//!    systemd service: an unprivileged user with a private, size-bounded
//!    tmpfs as /tmp, /var/tmp and $HOME, no capabilities, no network
//!    (loopback only), no devices, a read-only root, no set-uid elevation,
//!    `@reboot @swap @mount @module @raw-io @clock @cpu-emulation` system
//!    calls refused with EPERM, a runtime ceiling, task and memory limits,
//!    stdin at end-of-file. A tool that misreads `version` as an operand can
//!    at most write into a tmpfs that vanishes with it.
//!
//! What a probe run can show, judged in this order:
//!
//! - **a version**: exit 0 (or a reviewed status), output carrying a version
//!   token, no policy error marker on stderr - PASS;
//! - **a reviewed precondition** (`cli.preconditions`): the tool's own words
//!   for why it cannot answer on this bench, with no defect signature outside
//!   them - SKIP with the reason;
//! - **a defect signature** (`cli.defect_signatures`, a crash by signal, an
//!   exec failure, a missing interpreter): something the program needs is not
//!   there - FAIL, naming it;
//! - **no version query**: the program ran its own code and showed it - its
//!   option parser rejected the probe, it took the probe as an operand, it
//!   refused to run unprivileged, or it ended with status 0 - SKIP with the
//!   line that shows it;
//! - anything else - FAIL with every attempt.
//!
//! Before anything runs, the file itself is inspected: a path that does not
//! resolve fails, a file only its owner or group may execute is skipped
//! (the probe user could not run it), and a script whose interpreter is not
//! installed fails without being started.

use crate::pkglife::policy::{first_match, Policy};
use crate::pkglife::record::{clip, CliResult, ProbeAttempt, FAIL, PASS, SKIP};
use crate::pkglife::remote::{argv, sq, Remote};

/// The transient unit's sandbox. Each property is one hardening measure; see
/// systemd.exec(5).
pub const SANDBOX: [&str; 35] = [
    // A fixed unprivileged account, not DynamicUser: Photon resolves users
    // from files only (no nss-systemd), and a dynamic uid absent from
    // /etc/passwd made cronie's crontab refuse "your UID isn't in the passwd
    // file" before printing anything (measured on k09).
    "User=nobody",
    // nobody's home is /dev/null: ansible, podman, tshark and nerdctl failed
    // creating ~/.config or ~/.ansible under it before parsing an option
    // (measured on k13, 2026-10-02). An ordinary user has a writable home.
    "Environment=HOME=/tmp",
    "PrivateNetwork=yes",
    "PrivateDevices=yes",
    // /tmp and /var/tmp as private tmpfs mounts with a size bound, instead of
    // PrivateTmp (disk-backed) plus LimitFSIZE: RLIMIT_FSIZE also bounds
    // ftruncate on a memfd, and JIT runtimes that dual-map their code through
    // a memfd died of SIGXFSZ at start (erlang's beam.smp: elixir, erlc,
    // dialyzer; measured on k13). The tmpfs bound keeps writes out of the
    // guest's disk and inside MemoryMax.
    "TemporaryFileSystem=/tmp:size=64M,mode=1777",
    "TemporaryFileSystem=/var/tmp:size=64M,mode=1777",
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
    // A refused system call fails with EPERM, as it would for an ordinary
    // user, instead of killing the process with SIGSYS: podman --version died
    // of SIGSYS in the sandbox and printed its version with EPERM (k13).
    "SystemCallErrorNumber=EPERM",
    "TasksMax=64",
    // RuntimeMaxSec stops a hung probe with SIGTERM; one that ignores it
    // would otherwise live through systemd's default 90 s stop timeout and
    // outlast its package (paho_c_sub was still running after its removal on
    // k13). SIGKILL follows after 5 s.
    "TimeoutStopSec=5",
    "MemoryMax=512M",
    "LimitCORE=0",
    "WorkingDirectory=/tmp",
    "UMask=0077",
];

/// The command line that runs `exe args...` inside the sandbox as the
/// transient unit `unit`, bounded to `secs` by systemd itself. systemd-run
/// is not `--quiet`: its own first and last lines on stderr say how the unit
/// ended ([`split_run`]).
pub fn sandboxed(unit: &str, secs: u64, exe: &str, args: &[&str]) -> Result<String, String> {
    let runtime = format!("RuntimeMaxSec={secs}");
    let unit_arg = format!("--unit={unit}");
    let mut v: Vec<&str> = vec![
        "systemd-run",
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

/// How systemd says the probe unit ended.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Ending {
    /// `Finished with result:` - success, exit-code, signal, core-dump,
    /// timeout, oom-kill, ...
    pub result: String,
    /// `Main processes terminated with:` - `code=exited, status=1/FAILURE`,
    /// `code=dumped, status=11/SEGV`, ...
    pub ended: String,
}

impl Ending {
    /// The signal that ended the main process, when it did not exit.
    pub fn signal(&self) -> Option<&str> {
        if !(self.ended.starts_with("code=killed") || self.ended.starts_with("code=dumped")) {
            return None;
        }
        self.ended.rsplit('/').next().filter(|s| !s.is_empty())
    }

    /// systemd could not execute the file at all (EXIT_EXEC).
    pub fn exec_failed(&self) -> bool {
        self.ended.starts_with("code=exited") && self.ended.contains("status=203/")
    }
}

const TRAILER: [&str; 10] = [
    "Finished with result: ",
    "Main processes terminated with: ",
    "Service runtime: ",
    "CPU time consumed: ",
    "Memory peak: ",
    "Memory swap peak: ",
    "IP traffic received: ",
    "IP traffic sent: ",
    "IO bytes read: ",
    "IO bytes written: ",
];

/// Separate systemd-run's own lines from the tool's stderr: the first line
/// names the unit (`Running as unit: <unit>.service[; invocation ID: ..]`),
/// the trailing block says how it ended. Lines are only taken when they are
/// exactly where systemd-run writes them and the trailer carries its
/// `Finished with result:` line, so a tool printing similar text cannot
/// forge an ending.
pub fn split_run(unit: &str, stderr: &str) -> (String, Ending) {
    let mut lines: Vec<&str> = stderr.lines().collect();
    let head = format!("Running as unit: {unit}.service");
    if lines
        .first()
        .map(|l| *l == head || l.starts_with(&format!("{head};")))
        .unwrap_or(false)
    {
        lines.remove(0);
    }
    let mut end = lines.len();
    while end > 0 && TRAILER.iter().any(|p| lines[end - 1].starts_with(p)) {
        end -= 1;
    }
    let tail = &lines[end..];
    let mut ending = Ending::default();
    for l in tail {
        if let Some(v) = l.strip_prefix(TRAILER[0]) {
            ending.result = v.trim().to_string();
        } else if let Some(v) = l.strip_prefix(TRAILER[1]) {
            ending.ended = v.trim().to_string();
        }
    }
    if ending.result.is_empty() {
        return (lines.join("\n"), Ending::default());
    }
    (lines[..end].join("\n"), ending)
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
/// `expect` is the exit status that answers the query (0, or a reviewed one).
pub fn judge(
    code: Option<i32>,
    timed_out: bool,
    stdout: &str,
    stderr: &str,
    pkg_version: &str,
    markers: &[String],
    expect: i32,
) -> Result<String, String> {
    if timed_out {
        return Err("did not finish (killed at the deadline)".into());
    }
    match code {
        Some(c) if c == expect => {}
        Some(c) => return Err(format!("exit status {c}")),
        None => return Err("no exit status (killed or not started)".into()),
    }
    if stdout.trim().is_empty() && stderr.trim().is_empty() {
        return Err(format!("exit {expect} but printed nothing"));
    }
    if let Some(m) = error_marker(stderr, markers) {
        return Err(format!("stderr carries {m:?}: {}", clip(stderr.trim())));
    }
    let both = format!("{stdout}\n{stderr}");
    version_token(&both, pkg_version)
        .ok_or_else(|| format!("exit {expect} but no version in the output"))
}

fn lines_of(a: &ProbeAttempt) -> impl Iterator<Item = &str> {
    a.stdout.lines().chain(a.stderr.lines())
}

fn quote_line(l: &str) -> String {
    let t = l.trim();
    let mut end = t.len().min(200);
    while !t.is_char_boundary(end) {
        end -= 1;
    }
    t[..end].to_string()
}

/// The first defect an attempt shows, skipping lines that contain `except`
/// (a reviewed precondition's own words): a crash by signal, an exec
/// failure, or a policy defect signature.
pub fn defect_in(policy: &Policy, a: &ProbeAttempt, except: Option<&str>) -> Option<String> {
    let ending = Ending {
        result: a.result.clone(),
        ended: a.ended.clone(),
    };
    // A probe ended at the runtime limit is killed by systemd, not crashed.
    if a.result != "timeout" && a.result != "oom-kill" {
        if let Some(sig) = ending.signal() {
            return Some(format!("ended by signal {sig} ({})", a.ended));
        }
    }
    if ending.exec_failed() {
        return Some(format!("systemd could not execute it ({})", a.ended));
    }
    for l in lines_of(a) {
        if except.map(|m| l.contains(m)).unwrap_or(false) {
            continue;
        }
        for sig in &policy.cli.defect_signatures {
            if sig.all.iter().all(|m| l.contains(m.as_str())) {
                return Some(format!("{}: {}", sig.name, quote_line(l)));
            }
        }
    }
    None
}

/// Evidence that the program ran its own code although no probe printed a
/// version: the line that shows it, and what it shows.
pub fn ran_without_version(policy: &Policy, a: &ProbeAttempt) -> Option<String> {
    let args = a.args.join(" ");
    if a.code == Some(0)
        && !a.timed_out
        && (a.result.is_empty() || a.result == "success")
        && a.stdout.trim().is_empty()
        && a.stderr.trim().is_empty()
    {
        return Some(format!("`{args}` exited 0 and printed nothing"));
    }
    for l in lines_of(a) {
        let low = l.to_lowercase();
        if let Some(m) = policy
            .cli
            .option_rejection_markers
            .iter()
            .find(|m| low.contains(&m.to_lowercase()))
        {
            return Some(format!(
                "its option handling answered `{args}` ({m:?}): {}",
                quote_line(l)
            ));
        }
        if let Some(m) = policy
            .cli
            .privilege_refusal_markers
            .iter()
            .find(|m| low.contains(&m.to_lowercase()))
        {
            return Some(format!(
                "refuses to run as an unprivileged user ({m:?}): {}",
                quote_line(l)
            ));
        }
        // Echoing the probe back is the program reading it as an operand. Only
        // the long spellings: `version` and `-V` are words many outputs carry.
        if let Some(arg) = a.args.first() {
            if arg.len() >= 5 && arg.starts_with('-') && l.contains(arg.as_str()) {
                return Some(format!("took `{arg}` as an operand: {}", quote_line(l)));
            }
        }
    }
    None
}

/// A probe the tool accepted - exit status as expected, not ended by the
/// runtime limit, no policy error marker on stderr - that printed output.
pub fn answered_without_version(policy: &Policy, a: &ProbeAttempt, expect: i32) -> bool {
    a.code == Some(expect)
        && !a.timed_out
        && (a.result.is_empty() || a.result == "success")
        && !(a.stdout.trim().is_empty() && a.stderr.trim().is_empty())
        && error_marker(&a.stderr, &policy.cli.stderr_error_markers).is_none()
}

/// What a file in a bin directory is, read in the guest before anything runs.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Inspect {
    pub exists: bool,
    /// Octal permission bits of the resolved file, e.g. "755".
    pub mode: String,
    pub owner: String,
    pub group: String,
    /// The `#!` line of a script, if it is one.
    pub shebang: Option<String>,
}

impl Inspect {
    /// Whether a user who is neither owner nor in the group may execute it.
    pub fn others_may_run(&self) -> bool {
        u32::from_str_radix(&self.mode, 8)
            .map(|m| m & 0o001 != 0)
            .unwrap_or(false)
    }

    /// The interpreter a `#!` line asks for: (`/usr/bin/env`'s argument or
    /// the absolute path, whether it is a name to look up in PATH).
    pub fn interpreter(&self) -> Option<(String, bool)> {
        let sb = self.shebang.as_ref()?;
        let rest = sb.strip_prefix("#!")?.trim();
        let mut words = rest.split_whitespace();
        let first = words.next()?;
        if first.ends_with("/env") {
            // `env -S prog args` and `env VAR=x prog` both name prog later.
            let prog = words.find(|w| !w.starts_with('-') && !w.contains('='))?;
            return Some((prog.to_string(), true));
        }
        Some((first.to_string(), false))
    }
}

/// The guest command for [`inspect`]: whether the path resolves, the mode and
/// owner of what it resolves to, and its first line if it starts with `#!`.
pub fn inspect_cmd(exe: &str) -> Result<String, String> {
    let f = sq(exe)?;
    Ok(format!(
        "if [ ! -e {f} ]; then echo missing; exit 0; fi; \
         stat -L -c 'mode %a %U %G' -- {f}; \
         if [ \"$(head -c 2 -- {f})\" = '#!' ]; then \
         printf 'shebang '; head -n 1 -- {f} | head -c 256 | LC_ALL=C tr -c '[:print:]\\n' '?'; echo; fi"
    ))
}

pub fn parse_inspect(out: &str) -> Inspect {
    let mut i = Inspect::default();
    for l in out.lines() {
        if l.trim() == "missing" {
            return Inspect::default();
        }
        if let Some(rest) = l.strip_prefix("mode ") {
            let w: Vec<&str> = rest.split_whitespace().collect();
            if w.len() == 3 {
                i.exists = true;
                i.mode = w[0].to_string();
                i.owner = w[1].to_string();
                i.group = w[2].to_string();
            }
        } else if let Some(rest) = l.strip_prefix("shebang ") {
            if rest.starts_with("#!") {
                i.shebang = Some(rest.trim_end().to_string());
            }
        }
    }
    i
}

/// Whether the interpreter a script names is installed: an absolute path
/// must be executable, an `env` name must resolve in the default PATH.
pub fn interpreter_cmd(interp: &str, lookup: bool) -> Result<String, String> {
    if lookup {
        Ok(format!(
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin command -v {}",
            sq(interp)?
        ))
    } else {
        Ok(format!("test -x {} && echo {}", sq(interp)?, sq(interp)?))
    }
}

fn reviewed_precondition(
    policy: &Policy,
    base: &str,
    texts: &[String],
    attempts: &[ProbeAttempt],
) -> Option<(String, String)> {
    for c in policy.preconditions(base) {
        let in_text = texts.iter().find(|t| t.contains(c.marker.as_str()));
        let in_attempt = attempts
            .iter()
            .flat_map(|a| lines_of(a))
            .find(|l| l.contains(c.marker.as_str()))
            .map(|l| l.to_string());
        let Some(line) = in_text.cloned().or(in_attempt) else {
            continue;
        };
        // The reviewed words explain the failure; anything else that looks
        // like a broken installation still fails it.
        if attempts
            .iter()
            .any(|a| defect_in(policy, a, Some(c.marker.as_str())).is_some())
        {
            continue;
        }
        return Some((c.reason.clone(), quote_line(&line)));
    }
    None
}

/// Probe one executable. `seq` makes each transient unit name unique.
/// `generic` ignores every per-tool policy entry and every derived "ran
/// without a version" basis: it is how the controls judge a known-bad binary.
pub fn probe(
    r: &mut dyn Remote,
    policy: &Policy,
    exe: &str,
    pkg_version: &str,
    unit_prefix: &str,
    seq: &mut u64,
    generic: bool,
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
    if !generic {
        if let Some(rule) = policy.no_version_query(exe) {
            res.status = SKIP.into();
            res.reason = format!("no version query (reviewed): {}", rule.reason);
            return res;
        }
    }

    // ---- the file, before anything runs ----------------------------------
    let q = policy.limits.query_secs;
    let ins = match inspect_cmd(exe) {
        Ok(c) => parse_inspect(&r.exec(&c, None, q).stdout),
        Err(e) => {
            res.status = FAIL.into();
            res.reason = e;
            return res;
        }
    };
    if !ins.exists {
        res.status = FAIL.into();
        res.reason =
            "shipped in a bin directory but does not resolve to a file (dangling link?)".into();
        return res;
    }
    if !ins.others_may_run() {
        res.status = SKIP.into();
        res.reason = format!(
            "only its owner or group may run it (mode {} {}:{}); probes run as an unprivileged user",
            ins.mode, ins.owner, ins.group
        );
        return res;
    }
    let mut static_findings: Vec<String> = Vec::new();
    if let Some((interp, lookup)) = ins.interpreter() {
        let found = interpreter_cmd(&interp, lookup)
            .map(|c| r.exec(&c, None, q))
            .map(|e| e.ok() && !e.stdout.trim().is_empty())
            .unwrap_or(false);
        if !found {
            static_findings.push(format!(
                "missing interpreter: {interp} is not installed (`{}`)",
                ins.shebang.clone().unwrap_or_default()
            ));
        }
    }
    if !static_findings.is_empty() {
        if !generic {
            if let Some((why, line)) = reviewed_precondition(policy, base, &static_findings, &[]) {
                res.status = SKIP.into();
                res.reason = format!(
                    "precondition not met on this bench (reviewed): {why}; measured: {line}"
                );
                return res;
            }
        }
        res.status = FAIL.into();
        res.reason = static_findings.join("; ");
        return res;
    }

    // ---- the probes --------------------------------------------------------
    let secs = policy.limits.probe_secs;
    // A reviewed alternative replaces the generic probes for this tool; it is
    // judged exactly like them, against its reviewed exit status.
    let override_probe: Vec<Vec<String>>;
    let (probes, expect) = match policy.version_query(base).filter(|_| !generic) {
        Some(v) => {
            override_probe = vec![v.args.clone()];
            (&override_probe, v.exit)
        }
        None => (&policy.cli.probes, 0),
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
        let (stderr, ending) = split_run(&unit, &e.stderr);
        let verdict = judge(
            e.code,
            e.timed_out,
            &e.stdout,
            &stderr,
            pkg_version,
            &policy.cli.stderr_error_markers,
            expect,
        );
        // systemd's RuntimeMaxSec ends a hung probe; its result says so, and
        // the elapsed time says so where the result was not read.
        let hung = ending.result == "timeout" || e.elapsed_ms >= secs * 1000;
        res.attempts.push(ProbeAttempt {
            args: args.clone(),
            code: e.code,
            timed_out: e.timed_out || hung,
            ms: e.elapsed_ms,
            stdout: clip(&e.stdout),
            stderr: clip(&stderr),
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
            result: ending.result.clone(),
            ended: ending.ended.clone(),
        });
        if let Ok(v) = verdict {
            res.status = PASS.into();
            res.reason = format!("`{} {}` -> version {v}", base, args.join(" "));
            return res;
        }
    }

    let tried = format!(
        "{} tried: {}",
        res.attempts.len(),
        res.attempts
            .iter()
            .map(|a| format!("{} -> {}", a.args.join(" "), a.verdict))
            .collect::<Vec<_>>()
            .join("; ")
    );
    if !generic {
        if let Some((why, line)) = reviewed_precondition(policy, base, &[], &res.attempts) {
            res.status = SKIP.into();
            res.reason =
                format!("precondition not met on this bench (reviewed): {why}; measured: {line}");
            return res;
        }
    }
    if let Some((a, d)) = res
        .attempts
        .iter()
        .find_map(|a| defect_in(policy, a, None).map(|d| (a, d)))
    {
        res.status = FAIL.into();
        res.reason = format!("`{} {}`: {d}", base, a.args.join(" "));
        return res;
    }
    if !generic {
        // A probe the tool accepted - the reviewed status, a clean stderr -
        // that printed something but no version is a version query answered
        // wrongly ("ps from procps-ng UNKNOWN", "jq-"), or a tool that does
        // something else for any argument. Neither is evidence of a tool
        // without a version query; it stays a failure until reviewed.
        if let Some(a) = res
            .attempts
            .iter()
            .find(|a| answered_without_version(policy, a, expect))
        {
            let first = lines_of(a).find(|l| !l.trim().is_empty()).unwrap_or("");
            res.status = FAIL.into();
            res.reason = format!(
                "`{} {}` was accepted (status {expect}) but printed no version: {}",
                base,
                a.args.join(" "),
                quote_line(first)
            );
            return res;
        }
        if let Some(why) = res
            .attempts
            .iter()
            .find_map(|a| ran_without_version(policy, a))
        {
            res.status = SKIP.into();
            res.reason = format!("no version query: {why}");
            return res;
        }
    }
    res.status = FAIL.into();
    res.reason = format!("no version probe succeeded ({tried})");
    res
}

/// Proof that the sandbox is in force on this guest: the unit's user is not
/// root, it sees only loopback, the root filesystem is read-only to it, /tmp
/// is a private tmpfs, and its home is writable. Returns the measured values
/// on success; the reason on failure.
pub const SANDBOX_CONTROL_SCRIPT: &str = "id -u; ls /sys/class/net | tr '\\n' ' '; echo; \
     if touch /usr/.sharukhan-sandbox-probe 2>/dev/null; then echo writable; else echo read-only; fi; \
     stat -f -c %T /tmp; \
     if touch \"$HOME/.sharukhan-home-probe\" 2>/dev/null; then echo home-writable; else echo home-read-only; fi";

pub fn judge_sandbox(stdout: &str) -> Result<String, String> {
    let lines: Vec<&str> = stdout.lines().map(str::trim).collect();
    let (Some(uid), Some(net), Some(fs), Some(tmp), Some(home)) = (
        lines.first(),
        lines.get(1),
        lines.get(2),
        lines.get(3),
        lines.get(4),
    ) else {
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
    if *tmp != "tmpfs" {
        return Err(format!(
            "/tmp is {tmp} inside the sandbox, not the private size-bounded tmpfs"
        ));
    }
    if *home != "home-writable" {
        return Err(format!("$HOME is not writable inside the sandbox ({home})"));
    }
    Ok(format!(
        "uid {uid}, interfaces [{net}], root {fs}, /tmp {tmp}, home writable"
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pkglife::remote::fake::{self, Fake};
    use crate::pkglife::remote::Exec;

    fn markers() -> Vec<String> {
        Policy::embedded().unwrap().cli.stderr_error_markers
    }

    /// The inspection of a world-executable ELF file.
    fn elf() -> Exec {
        fake::ok("mode 755 root root\n")
    }

    /// A probe unit's output as systemd-run prints it around the tool's.
    fn unit_out(stdout: &str, result: &str, ended: &str, code: i32) -> Exec {
        fake::rc(
            code,
            stdout,
            &format!(
                "Finished with result: {result}\nMain processes terminated with: {ended}\nService runtime: 5ms\nCPU time consumed: 4ms\nMemory peak: 1.7M (swap: 0B)\n"
            ),
        )
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
    fn a_probe_passes_only_with_the_expected_status_output_and_a_version() {
        let m = markers();
        assert_eq!(
            judge(Some(0), false, "RPM version 6.1.0\n", "", "", &m, 0).unwrap(),
            "6.1.0"
        );
        // java prints its version on stderr; that is not an error
        assert!(judge(
            Some(0),
            false,
            "",
            "openjdk version \"17.0.9\" 2023-10-17",
            "",
            &m,
            0
        )
        .is_ok());
        // GNU false prints its version and exits 1: the negative control
        assert_eq!(
            judge(Some(1), false, "false (GNU coreutils) 9.1", "", "", &m, 0).unwrap_err(),
            "exit status 1"
        );
        // ... and passes only where a reviewed entry expects exactly 1
        assert!(judge(Some(1), false, "false (GNU coreutils) 9.1", "", "", &m, 1).is_ok());
        assert!(judge(Some(0), false, "false (GNU coreutils) 9.1", "", "", &m, 1).is_err());
        assert!(judge(Some(0), false, "", "", "", &m, 0)
            .unwrap_err()
            .contains("nothing"));
        assert!(judge(Some(0), false, "usage", "", "", &m, 0)
            .unwrap_err()
            .contains("no version"));
        assert!(judge(Some(0), false, "x 1.2", "Error: bad", "", &m, 0)
            .unwrap_err()
            .contains("error"));
        assert!(judge(
            Some(0),
            false,
            "x 1.2",
            "unrecognized option '-V'",
            "",
            &m,
            0
        )
        .is_err());
        assert!(judge(None, true, "", "", "", &m, 0)
            .unwrap_err()
            .contains("deadline"));
        assert!(judge(None, false, "", "", "", &m, 0).is_err());
    }

    #[test]
    fn systemd_runs_own_lines_are_separated_from_the_tools_stderr() {
        let err = "Running as unit: sharukhan-probe-x-1.service; invocation ID: 0123\n\
                   tool: bad\n\
                   Finished with result: core-dump\n\
                   Main processes terminated with: code=dumped, status=11/SEGV\n\
                   Service runtime: 89ms\nCPU time consumed: 54ms\nMemory peak: 20.1M (swap: 0B)\n";
        let (tool, end) = split_run("sharukhan-probe-x-1", err);
        assert_eq!(tool, "tool: bad");
        assert_eq!(end.result, "core-dump");
        assert_eq!(end.signal(), Some("SEGV"));
        let (tool, end) = split_run(
            "u",
            "Running as unit: u.service\nFinished with result: timeout\nMain processes terminated with: code=killed, status=15/TERM\n",
        );
        assert_eq!(tool, "");
        assert_eq!(end.result, "timeout");
        assert_eq!(end.signal(), Some("TERM"));
        let (_, end) = split_run(
            "u",
            "Finished with result: exit-code\nMain processes terminated with: code=exited, status=203/EXEC\n",
        );
        assert!(end.exec_failed());
        assert_eq!(end.signal(), None);
        // another unit's header is the tool's text, and a "trailer" without
        // its Finished line is no ending at all
        let (tool, end) = split_run("u", "Running as unit: other.service\nService runtime: 1s\n");
        assert_eq!(tool, "Running as unit: other.service\nService runtime: 1s");
        assert_eq!(end, Ending::default());
    }

    #[test]
    fn the_inspection_reads_mode_owner_and_shebang() {
        let i = parse_inspect("mode 755 root root\nshebang #!/usr/bin/env python3 -s\n");
        assert!(i.exists && i.others_may_run());
        assert_eq!(i.interpreter(), Some(("python3".into(), true)));
        let i = parse_inspect("mode 750 root root\n");
        assert!(!i.others_may_run());
        assert_eq!(i.interpreter(), None);
        let i = parse_inspect("mode 4110 root stapusr\n");
        assert!(!i.others_may_run());
        assert!(!parse_inspect("missing\n").exists);
        let i = parse_inspect("mode 755 root root\nshebang #!/usr/bin/perl -w\n");
        assert_eq!(i.interpreter(), Some(("/usr/bin/perl".into(), false)));
        let i = parse_inspect("mode 755 root root\nshebang #!/usr/bin/env -S VAR=1 ruby\n");
        assert_eq!(i.interpreter(), Some(("ruby".into(), true)));
        // a quoted path survives the shell
        assert!(inspect_cmd("/usr/bin/a'b")
            .unwrap()
            .contains(r"'/usr/bin/a'\''b'"));
    }

    #[test]
    fn the_sandbox_line_is_an_argument_vector_with_every_measure() {
        let c = sandboxed("sharukhan-probe-1", 10, "/usr/bin/x", &["--version"]).unwrap();
        assert!(c.starts_with("'systemd-run' '--wait' '--pipe' '--collect'"));
        assert!(
            !c.contains("--quiet"),
            "systemd-run's own lines carry the ending"
        );
        assert!(c.contains("'--unit=sharukhan-probe-1'"));
        assert!(c.contains("'RuntimeMaxSec=10'"));
        for p in SANDBOX {
            assert!(c.contains(&format!("'-p' '{p}'")), "{p} missing");
        }
        assert!(!c.contains("LimitFSIZE"), "RLIMIT_FSIZE kills JIT runtimes");
        assert!(c.ends_with("'--' '/usr/bin/x' '--version' </dev/null"));
        // a hostile path stays one argument
        let c = sandboxed("u", 1, "/usr/bin/a'; reboot; '", &["-V"]).unwrap();
        assert!(c.contains(r"'/usr/bin/a'\''; reboot; '\'''"));
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
            let r = probe(&mut f, &p, exe, "1.0", "sharukhan-probe", &mut seq, false);
            assert_eq!(r.status, SKIP, "{exe}");
            assert!(r.reason.starts_with("never executed"), "{}", r.reason);
        }
        assert!(f.log.borrow().is_empty(), "something reached the guest");
    }

    #[test]
    fn probes_stop_at_the_first_success_and_record_every_attempt() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        f.on("stat -L", elf())
            .on(
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
            false,
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
    fn a_tool_whose_parser_rejects_every_probe_has_no_version_query() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        f.on("stat -L", elf()).on(
            "systemd-run",
            fake::rc(
                1,
                "",
                "/usr/sbin/faillock: Unknown option: --version\nUsage: /usr/sbin/faillock [--dir /path]",
            ),
        );
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/sbin/faillock", "1", "u", &mut seq, false);
        assert_eq!(r.status, SKIP, "{r:?}");
        assert!(r.reason.starts_with("no version query"), "{}", r.reason);
        assert!(r.reason.contains("Unknown option"), "{}", r.reason);
        assert_eq!(
            r.attempts.len(),
            p.cli.probes.len(),
            "every probe was tried first"
        );
        // the generic judgement (the controls') never grants that
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/sbin/faillock", "1", "u", &mut seq, true);
        assert_eq!(r.status, FAIL);
    }

    #[test]
    fn a_broken_installation_fails_even_where_the_parser_answered() {
        let p = Policy::embedded().unwrap();
        for (err, what) in [
            (
                "tool: error while loading shared libraries: libfoo.so.1: cannot open shared object file",
                "unresolved",
            ),
            (
                "Traceback (most recent call last):\n  File \"/usr/bin/t\", line 3\nModuleNotFoundError: No module named 'six'",
                "python",
            ),
            (
                "Can't locate JSON.pm in @INC (you may need to install the JSON module)",
                "perl",
            ),
            ("/usr/bin/t: line 7: exec: perl: not found", "command"),
            ("/usr/bin/t: line 40: diff: command not found", "command"),
            ("Error: Could not find or load main class org.x.Main", "java"),
            (
                "==33==ASan runtime does not come first in initial library list",
                "sanitizer",
            ),
        ] {
            let mut f = Fake::new();
            f.on("stat -L", elf())
                .on("systemd-run", fake::rc(2, "", &format!("usage: t [-h]\n{err}")));
            let mut seq = 0;
            let r = probe(&mut f, &p, "/usr/bin/t", "1", "u", &mut seq, false);
            assert_eq!(r.status, FAIL, "{what}: {r:?}");
            assert!(
                !r.reason.starts_with("no version probe"),
                "{what}: {}",
                r.reason
            );
        }
    }

    #[test]
    fn a_crash_by_signal_fails_and_a_timeout_is_not_called_one() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        f.on("stat -L", elf()).on(
            "systemd-run",
            unit_out("", "core-dump", "code=dumped, status=11/SEGV", 1),
        );
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/bin/dtagnames", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL, "{r:?}");
        assert!(r.reason.contains("signal SEGV"), "{}", r.reason);
        assert_eq!(r.attempts[0].result, "core-dump");
        // ended at the runtime limit: a hang, no crash claimed and no basis
        // derived from it
        let mut g = Fake::new();
        g.on("stat -L", elf()).on(
            "systemd-run",
            unit_out("", "timeout", "code=killed, status=15/TERM", 1),
        );
        let mut seq = 0;
        let r = probe(&mut g, &p, "/usr/bin/sendmail", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL, "{r:?}");
        assert!(
            r.reason.starts_with("no version probe succeeded"),
            "{}",
            r.reason
        );
        assert!(r
            .attempts
            .iter()
            .all(|a| a.timed_out && a.verdict.starts_with("hung")));
    }

    #[test]
    fn a_hung_probe_is_named_as_hung() {
        let p = Policy::embedded().unwrap();
        let mut f = Fake::new();
        let mut slow = fake::rc(1, "", "");
        slow.elapsed_ms = p.limits.probe_secs * 1000 + 50;
        f.on("stat -L", elf()).on("systemd-run", slow);
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/bin/cat", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL);
        assert!(r
            .attempts
            .iter()
            .all(|a| a.timed_out && a.verdict.starts_with("hung")));
    }

    #[test]
    fn exit_zero_operand_echo_and_privilege_refusal_show_the_program_ran() {
        let p = Policy::embedded().unwrap();
        for (out, want) in [
            (fake::ok(""), "printed nothing"),
            (
                fake::rc(
                    1,
                    "",
                    "e2label: No such file or directory while trying to open --version",
                ),
                "operand",
            ),
            (
                fake::rc(4, "", "You must be root to run this program."),
                "unprivileged",
            ),
        ] {
            let mut f = Fake::new();
            f.on("stat -L", elf()).on("systemd-run", out);
            let mut seq = 0;
            let r = probe(&mut f, &p, "/usr/bin/t", "1", "u", &mut seq, false);
            assert_eq!(r.status, SKIP, "{want}: {r:?}");
            assert!(r.reason.contains(want), "{want}: {}", r.reason);
        }
        // a silent failure shows nothing of the kind
        let mut f = Fake::new();
        f.on("stat -L", elf())
            .on("systemd-run", fake::rc(1, "", ""));
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/bin/t", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL);
    }

    #[test]
    fn a_version_query_answered_without_a_version_is_a_failure_not_a_skip() {
        let p = Policy::embedded().unwrap();
        // procps-ng built without .tarball-version: every tool says UNKNOWN,
        // and `-v` is rejected by its parser - which must not excuse it
        let mut f = Fake::new();
        f.on("stat -L", elf())
            .on("'--version'", fake::ok("ps from procps-ng UNKNOWN\n"))
            .on("'-V'", fake::ok("ps from procps-ng UNKNOWN\n"))
            .on(
                "systemd-run",
                fake::rc(1, "", "error: unsupported option (BSD syntax)\nUsage: ps [options]"),
            );
        let mut seq = 0;
        let r = probe(&mut f, &p, "/usr/bin/ps", "4.0.6", "u", &mut seq, false);
        assert_eq!(r.status, FAIL, "{r:?}");
        assert!(
            r.reason.contains("printed no version: ps from procps-ng UNKNOWN"),
            "{}",
            r.reason
        );
        // a tool that does its job for any argument is not excused either
        let mut f = Fake::new();
        f.on("stat -L", elf()).on("systemd-run", fake::ok("Disabled\n"));
        let r = probe(&mut f, &p, "/usr/sbin/getenforce", "3.5", "u", &mut seq, false);
        assert_eq!(r.status, FAIL, "{r:?}");
    }

    #[test]
    fn the_file_is_inspected_before_anything_runs() {
        let p = Policy::embedded().unwrap();
        let mut seq = 0;
        // dangling
        let mut f = Fake::new();
        f.on("stat -L", fake::ok("missing\n"));
        let r = probe(&mut f, &p, "/usr/bin/t", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL);
        assert!(r.reason.contains("does not resolve"));
        assert_eq!(f.ran("systemd-run"), 0);
        // root-only
        let mut f = Fake::new();
        f.on("stat -L", fake::ok("mode 700 root root\n"));
        let r = probe(&mut f, &p, "/usr/sbin/cupsd", "1", "u", &mut seq, false);
        assert_eq!(r.status, SKIP);
        assert!(r.reason.contains("mode 700"), "{}", r.reason);
        assert_eq!(f.ran("systemd-run"), 0);
        // a script whose interpreter is absent fails without being started
        let mut f = Fake::new();
        f.on(
            "stat -L",
            fake::ok("mode 755 root root\nshebang #!/usr/bin/perl -w\n"),
        )
        .on("test -x", fake::rc(1, "", ""));
        let r = probe(
            &mut f,
            &p,
            "/usr/bin/make-cert.pl",
            "1",
            "u",
            &mut seq,
            false,
        );
        assert_eq!(r.status, FAIL, "{r:?}");
        assert!(
            r.reason.contains("missing interpreter: /usr/bin/perl"),
            "{}",
            r.reason
        );
        assert_eq!(f.ran("systemd-run"), 0);
        // ... and runs when it is there
        let mut f = Fake::new();
        f.on(
            "stat -L",
            fake::ok("mode 755 root root\nshebang #!/usr/bin/env python3\n"),
        )
        .on("command -v", fake::ok("/usr/bin/python3\n"))
        .on("systemd-run", fake::ok("t 1.2\n"));
        let r = probe(&mut f, &p, "/usr/bin/t", "1", "u", &mut seq, false);
        assert_eq!(r.status, PASS, "{r:?}");
    }

    #[test]
    fn a_reviewed_precondition_needs_its_words_and_no_other_defect() {
        let mut v: serde_json::Value =
            serde_json::from_str(crate::pkglife::policy::EMBEDDED).unwrap();
        v["cli"]["preconditions"] = serde_json::json!([{
            "pattern": "aplaymidi",
            "marker": "Cannot open sequencer",
            "reason": "needs /dev/snd/seq; the bench has no sound hardware"
        }]);
        let p = Policy::parse(&v.to_string()).unwrap();
        let mut seq = 0;
        let mut f = Fake::new();
        f.on("stat -L", elf()).on(
            "systemd-run",
            fake::rc(1, "", "Cannot open sequencer - No such file or directory"),
        );
        let r = probe(&mut f, &p, "/usr/bin/aplaymidi", "1", "u", &mut seq, false);
        assert_eq!(r.status, SKIP, "{r:?}");
        assert!(r.reason.contains("reviewed"), "{}", r.reason);
        // the same words next to a loader error: the installation is broken
        let mut f = Fake::new();
        f.on("stat -L", elf()).on(
            "systemd-run",
            fake::rc(
                1,
                "",
                "aplaymidi: error while loading shared libraries: libasound.so.2\nCannot open sequencer",
            ),
        );
        let r = probe(&mut f, &p, "/usr/bin/aplaymidi", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL, "{r:?}");
        // another tool with the same words is not covered
        let mut f = Fake::new();
        f.on("stat -L", elf())
            .on("systemd-run", fake::rc(1, "", "Cannot open sequencer"));
        let r = probe(&mut f, &p, "/usr/bin/aseqdump", "1", "u", &mut seq, false);
        assert_eq!(r.status, FAIL, "{r:?}");
    }

    #[test]
    fn the_sandbox_control_needs_every_property() {
        assert!(judge_sandbox("61234\nlo \nread-only\ntmpfs\nhome-writable\n").is_ok());
        assert!(judge_sandbox("0\nlo \nread-only\ntmpfs\nhome-writable\n")
            .unwrap_err()
            .contains("uid"));
        assert!(
            judge_sandbox("61234\neth0 lo \nread-only\ntmpfs\nhome-writable\n")
                .unwrap_err()
                .contains("interfaces")
        );
        assert!(
            judge_sandbox("61234\nlo \nwritable\ntmpfs\nhome-writable\n")
                .unwrap_err()
                .contains("writable")
        );
        assert!(
            judge_sandbox("61234\nlo \nread-only\next2/ext3\nhome-writable\n")
                .unwrap_err()
                .contains("tmpfs")
        );
        assert!(
            judge_sandbox("61234\nlo \nread-only\ntmpfs\nhome-read-only\n")
                .unwrap_err()
                .contains("HOME")
        );
        assert!(judge_sandbox("").is_err());
        assert!(judge_sandbox("x\nlo\nread-only").is_err());
    }
}
