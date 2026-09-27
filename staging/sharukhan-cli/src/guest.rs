//! Running a command in the guest.
//!
//! `ssh` stays an exec'd external binary, deliberately. The s02 defect in this
//! project - FIPS-constrained crypto refusing the algorithms sshd itself
//! advertised - was found through OpenSSH's own error text:
//!
//!   ssh_dispatch_run_fatal: ... invalid argument [preauth]
//!
//! A Rust SSH library would negotiate differently, produce different
//! diagnostics, and could mask exactly the class of defect this harness exists
//! to find. ssh is not an implementation detail here; it is the instrument.
//!
//! Which is also why stderr is CAPTURED rather than discarded. The bash sent
//! it to /dev/null and the s02 message had to be recovered by hand afterwards.
//!
//! sshpass is gone. The kickstart injects `public_key`, so authentication is
//! key-only and the guest password never reaches a command line - where it
//! would be visible to every other process on the host through /proc.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub struct Guest {
    pub user: String,
    pub ip: String,
    pub key: PathBuf,
    pub connect_timeout: u64,
    /// An OpenSSH ControlMaster socket for [`Guest::run_bounded`]. A package
    /// lifecycle run issues thousands of short commands; a fresh handshake for
    /// each costs more than the command. None keeps every call independent,
    /// which is what the oracle wants.
    pub control: Option<PathBuf>,
}

/// What [`Guest::run_bounded`] measured. Unlike [`Output`] it keeps the exit
/// code: "the version probe exited 2" and "ssh could not connect" (255) are
/// different findings, and a timeout is a third.
#[derive(Clone, Debug, Default)]
pub struct Bounded {
    pub stdout: String,
    pub stderr: String,
    /// None when the process was killed or could not be started.
    pub code: Option<i32>,
    pub timed_out: bool,
    pub elapsed_ms: u64,
    /// Output beyond [`CAPTURE_LIMIT`] was drained and discarded.
    pub truncated: bool,
}

impl Bounded {
    pub fn ok(&self) -> bool {
        self.code == Some(0) && !self.timed_out
    }
}

/// Per-stream capture ceiling. A runaway command must not exhaust the host's
/// memory; the excess is still read so the remote side never blocks on a full
/// pipe.
pub const CAPTURE_LIMIT: usize = 8 * 1024 * 1024;

fn drain<R: Read + Send + 'static>(mut r: R) -> std::thread::JoinHandle<(Vec<u8>, bool)> {
    std::thread::spawn(move || {
        let mut kept = Vec::new();
        let mut buf = [0u8; 65536];
        let mut truncated = false;
        loop {
            match r.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    let room = CAPTURE_LIMIT.saturating_sub(kept.len());
                    if room < n {
                        truncated = true;
                    }
                    kept.extend_from_slice(&buf[..n.min(room)]);
                }
            }
        }
        (kept, truncated)
    })
}

/// Run a prepared command with a wall-clock bound, optional stdin, and both
/// streams captured. The child is killed at the deadline; the caller is
/// expected to have bounded the REMOTE side too (`timeout` in the guest),
/// because killing the local ssh client does not signal a remote command that
/// has no terminal.
pub fn run_command_bounded(mut cmd: Command, stdin: Option<&[u8]>, limit: Duration) -> Bounded {
    let started = Instant::now();
    cmd.stdin(if stdin.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    })
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            return Bounded {
                stderr: format!("could not execute {:?}: {e}", cmd.get_program()),
                ..Default::default()
            }
        }
    };
    let writer = match (stdin, child.stdin.take()) {
        (Some(data), Some(mut pipe)) => {
            let data = data.to_vec();
            Some(std::thread::spawn(move || {
                let _ = pipe.write_all(&data);
            }))
        }
        _ => None,
    };
    let out = child.stdout.take().map(drain);
    let err = child.stderr.take().map(drain);
    let mut timed_out = false;
    let code = loop {
        match child.try_wait() {
            Ok(Some(st)) => break st.code(),
            Ok(None) if started.elapsed() >= limit => {
                timed_out = true;
                let _ = child.kill();
                let _ = child.wait();
                break None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(10)),
            Err(_) => break None,
        }
    };
    if let Some(w) = writer {
        let _ = w.join();
    }
    let (o, ot) = out
        .and_then(|h| h.join().ok())
        .unwrap_or((Vec::new(), false));
    let (e, et) = err
        .and_then(|h| h.join().ok())
        .unwrap_or((Vec::new(), false));
    Bounded {
        stdout: String::from_utf8_lossy(&o).to_string(),
        stderr: String::from_utf8_lossy(&e).to_string(),
        code,
        timed_out,
        elapsed_ms: started.elapsed().as_millis() as u64,
        truncated: ot || et,
    }
}

pub struct Output {
    pub stdout: String,
    pub stderr: String,
    pub ok: bool,
}

impl Output {
    /// stdout with surrounding whitespace removed - what nearly every oracle
    /// wants, since the bash piped through `tr -d ' '`.
    pub fn trimmed(&self) -> String {
        self.stdout.trim().to_string()
    }
    /// The measured value, or the marker the oracle prints when a command
    /// produced nothing. "unknown" and "0" mean different things and must not
    /// collapse into each other.
    pub fn value_or(&self, fallback: &str) -> String {
        let t = self.trimmed();
        if t.is_empty() {
            fallback.to_string()
        } else {
            t
        }
    }
}

impl Guest {
    pub fn new(user: &str, ip: &str, key: &Path, connect_timeout: u64) -> Guest {
        Guest {
            user: user.to_string(),
            ip: ip.to_string(),
            key: key.to_path_buf(),
            connect_timeout,
            control: None,
        }
    }

    /// The ssh options every call shares. Kept in one place so the bounded
    /// path cannot drift from the one the oracle has proven.
    fn base_args(&self, multiplex: bool) -> Vec<String> {
        let mut a: Vec<String> = [
            "-i",
            &self.key.to_string_lossy(),
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            &format!("ConnectTimeout={}", self.connect_timeout),
            "-o",
            "LogLevel=ERROR",
            // A guest that stops answering mid-command (a firewall unit that
            // drops the session) is noticed in ~30 s rather than never.
            "-o",
            "ServerAliveInterval=10",
            "-o",
            "ServerAliveCountMax=3",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        match (&self.control, multiplex) {
            (Some(path), true) => {
                a.extend([
                    "-o".to_string(),
                    "ControlMaster=auto".to_string(),
                    "-o".to_string(),
                    format!("ControlPath={}", path.display()),
                    "-o".to_string(),
                    "ControlPersist=120".to_string(),
                ]);
            }
            _ => a.extend(["-o".to_string(), "ControlPath=none".to_string()]),
        }
        a
    }

    /// Run `cmd` in the guest with a host-side deadline and optional stdin.
    ///
    /// `multiplex` = false forces a brand-new TCP connection. That is the
    /// only honest reachability test after something may have changed the
    /// guest's firewall: an established multiplexed session survives rules
    /// that refuse every new connection.
    pub fn run_bounded(
        &self,
        cmd: &str,
        stdin: Option<&[u8]>,
        limit: Duration,
        multiplex: bool,
    ) -> Bounded {
        let mut c = Command::new("ssh");
        c.args(self.base_args(multiplex))
            .arg(format!("{}@{}", self.user, self.ip))
            .arg(cmd);
        run_command_bounded(c, stdin, limit)
    }

    /// Ask a multiplexing master to exit. Harmless when none is running.
    pub fn close_control(&self) {
        if let Some(path) = &self.control {
            let mut c = Command::new("ssh");
            c.args([
                "-o",
                &format!("ControlPath={}", path.display()),
                "-O",
                "exit",
            ])
            .arg(format!("{}@{}", self.user, self.ip));
            let _ = run_command_bounded(c, None, Duration::from_secs(10));
        }
    }

    /// StrictHostKeyChecking=no with UserKnownHostsFile=/dev/null: every
    /// permutation is a fresh machine reusing an address from a fixed pool, so
    /// a remembered host key is guaranteed to be wrong and would block the run
    /// with a warning nobody is there to answer.
    ///
    /// BatchMode=yes so a guest that will not take the key fails in seconds
    /// instead of blocking on a password prompt that has no reader.
    pub fn run(&self, cmd: &str) -> Output {
        let out = Command::new("ssh")
            .args([
                "-i",
                &self.key.to_string_lossy(),
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
                "-o",
                &format!("ConnectTimeout={}", self.connect_timeout),
                "-o",
                "LogLevel=ERROR",
                &format!("{}@{}", self.user, self.ip),
                cmd,
            ])
            .output();
        match out {
            Ok(o) => Output {
                stdout: String::from_utf8_lossy(&o.stdout).to_string(),
                stderr: String::from_utf8_lossy(&o.stderr).to_string(),
                ok: o.status.success(),
            },
            Err(e) => Output {
                stdout: String::new(),
                stderr: format!("could not execute ssh: {e}"),
                ok: false,
            },
        }
    }

    /// Whether the guest answers at all. The stderr comes back with it: on
    /// s02 that text IS the finding.
    pub fn reachable(&self) -> Output {
        self.run("true")
    }
}

/// Whether ssh failed because the guest is not accepting connections YET -
/// nothing answered on port 22 - as opposed to an sshd that answered and
/// refused.
///
/// Only the first is worth waiting out. k16 leased its address on 2026-09-13
/// and was probed 12 seconds later, before sshd listened: "Connection timed
/// out". s02 reaches sshd and is turned away - "Permission denied", or under
/// FIPS-constrained crypto "Unable to negotiate" - and that refusal IS its
/// finding, so retrying it would only delay the evidence.
pub fn transport_not_ready(stderr: &str) -> bool {
    const ANSWERED: [&str; 4] = [
        "Permission denied",
        "Unable to negotiate",
        "Host key verification failed",
        "no matching",
    ];
    const NOT_READY: [&str; 6] = [
        "Connection timed out",
        "Connection refused",
        "No route to host",
        "Network is unreachable",
        "Connection reset by peer",
        "kex_exchange_identification",
    ];
    if ANSWERED.iter().any(|a| stderr.contains(a)) {
        return false;
    }
    NOT_READY.iter().any(|n| stderr.contains(n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_bounded_command_reports_code_streams_and_stdin() {
        let mut c = Command::new("sh");
        c.args(["-c", "cat; echo err >&2; exit 3"]);
        let b = run_command_bounded(c, Some(b"hello"), Duration::from_secs(10));
        assert_eq!(b.code, Some(3));
        assert_eq!(b.stdout, "hello");
        assert_eq!(b.stderr.trim(), "err");
        assert!(!b.timed_out && !b.ok());
    }

    #[test]
    fn a_hung_command_is_killed_at_the_deadline() {
        let mut c = Command::new("sleep");
        c.arg("30");
        let b = run_command_bounded(c, None, Duration::from_millis(300));
        assert!(b.timed_out);
        assert_eq!(b.code, None);
        assert!(b.elapsed_ms < 5000, "took {} ms", b.elapsed_ms);
    }

    #[test]
    fn stdin_is_null_unless_given_so_nothing_can_block_on_it() {
        let mut c = Command::new("cat");
        c.arg("-");
        let b = run_command_bounded(c, None, Duration::from_secs(5));
        assert!(b.ok(), "{b:?}");
        assert_eq!(b.stdout, "");
    }

    #[test]
    fn a_missing_program_is_reported_not_panicked() {
        let c = Command::new("/nonexistent/sharukhan-test-binary");
        let b = run_command_bounded(c, None, Duration::from_secs(5));
        assert_eq!(b.code, None);
        assert!(b.stderr.contains("could not execute"));
    }

    #[test]
    fn output_beyond_the_limit_is_drained_and_flagged() {
        let mut c = Command::new("sh");
        c.args(["-c", "head -c 9000000 /dev/zero"]);
        let b = run_command_bounded(c, None, Duration::from_secs(20));
        assert!(b.ok());
        assert!(b.truncated);
        assert_eq!(b.stdout.len(), CAPTURE_LIMIT);
    }

    #[test]
    fn only_a_multiplexed_call_names_the_control_socket() {
        let mut g = Guest::new("root", "10.0.0.1", Path::new("/k"), 5);
        assert!(g.base_args(true).contains(&"ControlPath=none".to_string()));
        g.control = Some(PathBuf::from("/tmp/x/cm"));
        assert!(g
            .base_args(true)
            .contains(&"ControlPath=/tmp/x/cm".to_string()));
        // a fresh-connection probe must never ride on the master
        assert!(g.base_args(false).contains(&"ControlPath=none".to_string()));
        assert!(!g.base_args(false).iter().any(|a| a == "ControlMaster=auto"));
    }

    #[test]
    fn k16s_timeout_is_waited_out() {
        assert!(transport_not_ready(
            "ssh: connect to host 192.168.225.171 port 22: Connection timed out"
        ));
        assert!(transport_not_ready(
            "ssh: connect to host 10.0.0.9 port 22: Connection refused"
        ));
        assert!(transport_not_ready(
            "kex_exchange_identification: read: Connection reset by peer"
        ));
    }

    #[test]
    fn s02s_refusals_are_evidence_not_retried() {
        assert!(!transport_not_ready(
            "root@192.168.225.152: Permission denied (publickey,password,keyboard-interactive)."
        ));
        assert!(!transport_not_ready(
            "Unable to negotiate with 192.168.225.136 port 22: no matching key exchange method found."
        ));
    }

    #[test]
    fn an_unrecognised_failure_is_not_retried() {
        // negative control: a classifier that retries everything passes k16's test
        assert!(!transport_not_ready(""));
        assert!(!transport_not_ready(
            "could not execute ssh: No such file or directory"
        ));
    }
}
