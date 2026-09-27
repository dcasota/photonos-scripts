//! Commands in the guest: quoting, bounding, and a seam for tests.
//!
//! ssh hands its command to the remote user's shell as ONE string, so an
//! argument vector has to be turned into a string the shell splits back into
//! exactly those arguments. Every value that reaches the guest from data -
//! a package name from repository metadata, a file path from an RPM header, a
//! unit name - goes through [`sq`], and nothing is ever interpolated any other
//! way. The shell snippets that remain in the callers are constants.
//!
//! Every command is also bounded twice: by `timeout` inside the guest, because
//! killing a local ssh client does not signal a remote process that has no
//! terminal, and by a host-side deadline a little beyond it, because a guest
//! that stops answering must not hang the run.

use crate::guest::{Bounded, Guest};
use std::time::Duration;

/// POSIX single-quoting. The only character that needs care inside single
/// quotes is the quote itself, which is closed, escaped and reopened.
///
/// A NUL byte cannot be part of any argument, so a value carrying one is
/// refused rather than silently truncated by the remote exec.
pub fn sq(s: &str) -> Result<String, String> {
    if s.contains('\0') {
        return Err(format!("refusing to pass a value containing NUL: {s:?}"));
    }
    Ok(format!("'{}'", s.replace('\'', "'\\''")))
}

/// An argument vector as one shell-safe command line.
pub fn argv(args: &[&str]) -> Result<String, String> {
    if args.is_empty() {
        return Err("empty argument vector".into());
    }
    Ok(args
        .iter()
        .map(|a| sq(a))
        .collect::<Result<Vec<_>, _>>()?
        .join(" "))
}

/// An RPM package name as it may appear on a command line. RPM itself allows
/// more than this, but every name on the media under test fits, and a name
/// that does not is far more likely to be corrupt metadata than a package -
/// refusing it keeps an option-looking value (`-foo`) away from tdnf and rpm.
pub fn valid_package_name(n: &str) -> bool {
    !n.is_empty()
        && n.len() <= 200
        && !n.starts_with('-')
        && n.chars()
            .all(|c| c.is_ascii_alphanumeric() || "._+-".contains(c))
}

/// A systemd unit name as systemd itself defines it (unit_name_is_valid):
/// [A-Za-z0-9:_.\\-@] plus a known type suffix, at most 255 characters.
pub fn valid_unit_name(n: &str) -> bool {
    const SUFFIXES: [&str; 11] = [
        ".service",
        ".socket",
        ".timer",
        ".path",
        ".target",
        ".mount",
        ".automount",
        ".swap",
        ".slice",
        ".scope",
        ".device",
    ];
    !n.is_empty()
        && n.len() <= 255
        && !n.starts_with('-')
        && SUFFIXES.iter().any(|s| n.ends_with(s) && n.len() > s.len())
        && n.chars()
            .all(|c| c.is_ascii_alphanumeric() || ":_.\\-@".contains(c))
}

/// One command's measured outcome.
pub type Exec = Bounded;

/// Where commands run. The real one is ssh; tests script one.
pub trait Remote {
    /// Run a shell command line in the guest, bounded to `limit_secs` there
    /// and a margin beyond it here.
    fn exec(&mut self, cmd: &str, stdin: Option<&[u8]>, limit_secs: u64) -> Exec;
    /// Whether a NEW ssh connection succeeds right now.
    fn fresh_reachable(&mut self) -> bool;
}

/// Grace for the host-side deadline beyond the guest-side one: connection
/// setup plus `timeout -k`'s kill delay.
const HOST_MARGIN_SECS: u64 = 20;

/// `timeout -k 5 <n> sh -c '<cmd>'`: the guest bounds the command itself.
pub fn guest_bounded(cmd: &str, limit_secs: u64) -> Result<String, String> {
    Ok(format!(
        "timeout -k 5 {} sh -c {}",
        limit_secs.max(1),
        sq(cmd)?
    ))
}

pub struct GuestRemote<'a> {
    pub guest: &'a Guest,
}

impl Remote for GuestRemote<'_> {
    fn exec(&mut self, cmd: &str, stdin: Option<&[u8]>, limit_secs: u64) -> Exec {
        let wrapped = match guest_bounded(cmd, limit_secs) {
            Ok(w) => w,
            Err(e) => {
                return Exec {
                    stderr: e,
                    ..Default::default()
                }
            }
        };
        self.guest.run_bounded(
            &wrapped,
            stdin,
            Duration::from_secs(limit_secs + HOST_MARGIN_SECS),
            true,
        )
    }

    fn fresh_reachable(&mut self) -> bool {
        self.guest
            .run_bounded("true", None, Duration::from_secs(20), false)
            .ok()
    }
}

/// Whether a failed exec is ssh failing rather than the command: 255 is what
/// ssh exits with on a transport error, and the stderr says which.
pub fn transport_lost(e: &Exec) -> bool {
    e.code == Some(255) && crate::guest::transport_not_ready(&e.stderr)
        || e.code.is_none() && e.timed_out
}

#[cfg(test)]
pub mod fake {
    //! A scripted guest. Each rule is (substring of the command, response);
    //! the first rule that matches answers. Unmatched commands fail loudly
    //! with code 127 so a test cannot pass by accident on a command nobody
    //! scripted.
    use super::*;
    use std::cell::RefCell;

    pub struct Rule {
        pub needle: String,
        pub out: Exec,
        /// Answer only this many times, then fall through to later rules.
        pub times: Option<usize>,
    }

    #[derive(Default)]
    pub struct Fake {
        pub rules: Vec<Rule>,
        pub log: RefCell<Vec<String>>,
        pub reachable: bool,
        /// When set, the fake keeps a journal: `logger` and the harness's
        /// control unit append to it, and `journalctl --after-cursor` returns
        /// it. That is what lets a whole run, controls included, be driven
        /// with the random nonces the controls use.
        pub journal: Option<Vec<String>>,
    }

    /// The single-quoted argument that follows `after` in a command line.
    fn quoted_after<'c>(cmd: &'c str, after: &str) -> Option<&'c str> {
        let i = cmd.find(after)? + after.len();
        let rest = cmd[i..].strip_prefix(" '")?;
        rest.split('\'').next()
    }

    pub fn ok(stdout: &str) -> Exec {
        Exec {
            stdout: stdout.to_string(),
            code: Some(0),
            ..Default::default()
        }
    }

    pub fn rc(code: i32, stdout: &str, stderr: &str) -> Exec {
        Exec {
            stdout: stdout.to_string(),
            stderr: stderr.to_string(),
            code: Some(code),
            ..Default::default()
        }
    }

    impl Fake {
        pub fn new() -> Fake {
            Fake {
                reachable: true,
                ..Default::default()
            }
        }
        pub fn on(&mut self, needle: &str, out: Exec) -> &mut Self {
            self.rules.push(Rule {
                needle: needle.to_string(),
                out,
                times: None,
            });
            self
        }
        pub fn once(&mut self, needle: &str, out: Exec) -> &mut Self {
            self.rules.push(Rule {
                needle: needle.to_string(),
                out,
                times: Some(1),
            });
            self
        }
        pub fn ran(&self, needle: &str) -> usize {
            self.log
                .borrow()
                .iter()
                .filter(|c| c.contains(needle))
                .count()
        }
    }

    impl Remote for Fake {
        fn exec(&mut self, cmd: &str, _stdin: Option<&[u8]>, _limit: u64) -> Exec {
            self.log.borrow_mut().push(cmd.to_string());
            if let Some(j) = self.journal.as_mut() {
                if cmd.contains("'logger'") {
                    if let Some(msg) = quoted_after(cmd, "'--'") {
                        j.push(format!(
                            r#"{{"SYSLOG_IDENTIFIER":"sharukhan-control","PRIORITY":"3","MESSAGE":"{msg}"}}"#
                        ));
                        return ok("");
                    }
                }
                if cmd.contains("'systemd-run'") && cmd.contains("unit control ") {
                    let unit = cmd
                        .split("'--unit=")
                        .nth(1)
                        .and_then(|r| r.split('\'').next())
                        .unwrap_or("");
                    let nonce = cmd
                        .split("unit control ")
                        .nth(1)
                        .and_then(|r| r.split('"').next())
                        .unwrap_or("");
                    j.push(format!(
                        r#"{{"_SYSTEMD_UNIT":"{unit}","PRIORITY":"3","MESSAGE":"unit control {nonce}"}}"#
                    ));
                    return rc(3, "", "");
                }
                if cmd.contains("journalctl") && cmd.contains("--after-cursor") {
                    let unit = cmd
                        .split("'--unit=")
                        .nth(1)
                        .and_then(|r| r.split('\'').next());
                    let lines: Vec<&String> = j
                        .iter()
                        .filter(|l| unit.is_none_or(|u| l.contains(u)))
                        .collect();
                    return ok(&lines.iter().map(|l| format!("{l}\n")).collect::<String>());
                }
            }
            for r in self.rules.iter_mut() {
                if cmd.contains(&r.needle) {
                    match r.times {
                        Some(0) => continue,
                        Some(n) => r.times = Some(n - 1),
                        None => {}
                    }
                    return r.out.clone();
                }
            }
            rc(127, "", &format!("fake: no rule for {cmd}"))
        }
        fn fresh_reachable(&mut self) -> bool {
            self.reachable
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The quoting is proven against a real shell, not against itself.
    #[test]
    fn quoted_arguments_survive_a_real_shell_unchanged() {
        let nasty = [
            "plain",
            "it's",
            "$(touch /tmp/sharukhan-pwned)",
            "`id`",
            "a b\tc\nd",
            "'';\"\\",
            "-rf",
            "",
        ];
        for n in nasty {
            let line = format!("printf '%s' {}", sq(n).unwrap());
            let out = std::process::Command::new("sh")
                .args(["-c", &line])
                .output()
                .unwrap();
            assert_eq!(String::from_utf8_lossy(&out.stdout), n, "for {n:?}");
        }
        assert!(!std::path::Path::new("/tmp/sharukhan-pwned").exists());
    }

    #[test]
    fn nul_is_refused_not_truncated() {
        assert!(sq("a\0b").is_err());
        assert!(argv(&["rpm", "a\0b"]).is_err());
        assert!(argv(&[]).is_err());
        assert_eq!(argv(&["rpm", "-q", "x y"]).unwrap(), "'rpm' '-q' 'x y'");
    }

    #[test]
    fn the_guest_side_bound_wraps_the_whole_line() {
        let w = guest_bounded("a | b; c", 30).unwrap();
        assert_eq!(w, "timeout -k 5 30 sh -c 'a | b; c'");
        assert!(guest_bounded("x", 0)
            .unwrap()
            .starts_with("timeout -k 5 1 "));
    }

    #[test]
    fn package_names_from_the_media_pass_and_option_lookalikes_do_not() {
        for ok in [
            "chrony",
            "Linux-PAM-devel",
            "libstdc++",
            "python3.14-pip",
            "gdk-pixbuf2",
        ] {
            assert!(valid_package_name(ok), "{ok}");
        }
        for bad in ["", "-y", "a b", "a;b", "$(x)", "a/b", "é"] {
            assert!(!valid_package_name(bad), "{bad}");
        }
    }

    #[test]
    fn unit_names_follow_systemds_own_grammar() {
        for ok in [
            "chronyd.service",
            "getty@.service",
            "dev-sda1.device",
            "a\\x2db.mount",
        ] {
            assert!(valid_unit_name(ok), "{ok}");
        }
        for bad in [
            "",
            ".service",
            "chronyd",
            "-x.service",
            "a b.service",
            "x.conf",
            "a;b.socket",
        ] {
            assert!(!valid_unit_name(bad), "{bad}");
        }
    }

    #[test]
    fn only_ssh_transport_failures_count_as_a_lost_session() {
        let lost = Exec {
            code: Some(255),
            stderr: "ssh: connect to host 1.2.3.4 port 22: Connection timed out".into(),
            ..Default::default()
        };
        assert!(transport_lost(&lost));
        let hung = Exec {
            timed_out: true,
            ..Default::default()
        };
        assert!(transport_lost(&hung));
        // negative controls: a command's own failure is not a lost session
        let cmd_failed = Exec {
            code: Some(255),
            stderr: "some tool: fatal".into(),
            ..Default::default()
        };
        assert!(!transport_lost(&cmd_failed));
        assert!(!transport_lost(&fake::rc(1, "", "")));
    }

    #[test]
    fn the_fake_refuses_unscripted_commands() {
        let mut f = fake::Fake::new();
        f.once("a", fake::ok("1")).on("a", fake::ok("2"));
        assert_eq!(f.exec("a", None, 1).stdout, "1");
        assert_eq!(f.exec("a", None, 1).stdout, "2");
        assert_eq!(f.exec("zzz", None, 1).code, Some(127));
        assert_eq!(f.ran("a"), 2);
        assert!(f.fresh_reachable());
    }
}
