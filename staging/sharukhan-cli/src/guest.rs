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

use std::path::{Path, PathBuf};
use std::process::Command;

pub struct Guest {
    pub user: String,
    pub ip: String,
    pub key: PathBuf,
    pub connect_timeout: u64,
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
