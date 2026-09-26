//! Process lookup that cannot match itself.
//!
//! `pgrep -f 'mc-run\.sh'` matches the pgrep that is running it, because the
//! pattern is on pgrep's own command line. In bash that made a waiter loop
//! forever - it was waiting for itself - and the `pkill -f` form of the same
//! mistake killed the shell that issued it. Twice.
//!
//! So: scan /proc directly, and exclude our own pid, every ancestor up the
//! PPid chain, and any process whose argv[0] basename is ours. A second
//! sharukhan carrying the same needle in its argv is exactly the self-match
//! case again, reached by a different route.

use std::fs;

pub struct Proc {
    pub pid: i32,
    pub cmdline: String,
}

/// /proc/<pid>/cmdline is NUL-separated, not space-separated. Joining with a
/// space is only for display and matching; nothing here re-executes it.
fn cmdline(pid: i32) -> Option<String> {
    let raw = fs::read(format!("/proc/{pid}/cmdline")).ok()?;
    let s: String = String::from_utf8_lossy(&raw)
        .split('\0')
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

fn ppid(pid: i32) -> Option<i32> {
    let status = fs::read_to_string(format!("/proc/{pid}/status")).ok()?;
    for line in status.lines() {
        if let Some(v) = line.strip_prefix("PPid:") {
            return v.trim().parse().ok();
        }
    }
    None
}

fn own_pid() -> i32 {
    fs::read_to_string("/proc/self/stat")
        .ok()
        .and_then(|s| s.split_whitespace().next().and_then(|p| p.parse().ok()))
        .unwrap_or(0)
}

/// Our own argv[0], reduced to a basename: "sharukhan".
fn own_argv0() -> String {
    std::env::args()
        .next()
        .and_then(|a| a.rsplit('/').next().map(str::to_string))
        .unwrap_or_default()
}

/// Us, and everything that spawned us. A driver started from a shell script
/// would otherwise see that script and consider itself blocked by its own
/// parent.
fn self_and_ancestors() -> Vec<i32> {
    let mut out = Vec::new();
    let mut p = own_pid();
    // Bounded, because a corrupt PPid chain must not spin.
    for _ in 0..64 {
        if p <= 0 || out.contains(&p) {
            break;
        }
        out.push(p);
        match ppid(p) {
            Some(next) => p = next,
            None => break,
        }
    }
    out
}

fn pids() -> Vec<i32> {
    fs::read_dir("/proc")
        .map(|d| {
            d.flatten()
                .filter_map(|e| e.file_name().to_str().and_then(|n| n.parse::<i32>().ok()))
                .collect()
        })
        .unwrap_or_default()
}

/// Processes RUNNING one of the named scripts, excluding this process, its
/// ancestors, and any other sharukhan.
///
/// The needle is matched against argv[0] and argv[1] only - the interpreter and
/// the script it was handed - never the whole command line. `pgrep -f` matches
/// anywhere, so any shell whose command line merely mentions "mc-run.sh"
/// (writing it, grepping it, editing it) is reported as running it. That was
/// observed here: a shell that had just written a file of that name was
/// counted as a build in flight.
pub fn matching(needles: &[&str]) -> Vec<Proc> {
    matching_by(|cmd| head_matches(cmd, needles))
}

/// [`matching`] with an arbitrary test on the command line; this process and
/// its ancestors are still never reported.
pub fn matching_by(pred: impl Fn(&str) -> bool) -> Vec<Proc> {
    let skip = self_and_ancestors();
    let mine = own_argv0();
    let mut out = Vec::new();
    for pid in pids() {
        if skip.contains(&pid) {
            continue;
        }
        let Some(cmd) = cmdline(pid) else { continue };
        let argv0 = cmd
            .split_whitespace()
            .next()
            .and_then(|a| a.rsplit('/').next())
            .unwrap_or("");
        if !mine.is_empty() && argv0 == mine {
            continue;
        }
        if pred(&cmd) {
            out.push(Proc { pid, cmdline: cmd });
        }
    }
    out.sort_by_key(|p| p.pid);
    out
}

/// Whether a needle occurs in the first two words of `cmd` - the program, or
/// the script an interpreter runs. Deeper arguments are not looked at, so a
/// process that merely mentions a path (an editor, a grep) is not work.
pub fn head_matches(cmd: &str, needles: &[&str]) -> bool {
    cmd.split_whitespace()
        .take(2)
        .any(|a| needles.iter().any(|n| a.contains(n)))
}

/// Whether `cmd` is a Python interpreter running a script named `script`
/// (`python3 build.py ...`, also behind `sudo` or `env`). A bare name would
/// match `vim build.py` or `grep ... build.py`, which run nothing.
pub fn runs_python_script(cmd: &str, script: &str) -> bool {
    let words: Vec<&str> = cmd.split_whitespace().take(4).collect();
    let base = |w: &str| w.rsplit('/').next().unwrap_or("").to_string();
    words.windows(2).any(|w| base(w[0]).starts_with("python") && base(w[1]) == script)
}

/// Every descendant of `root`, deepest last. Used to end a job's whole tree:
/// killing only the recorded pid leaves mc-run.sh and its children orphaned
/// and still installing.
pub fn descendants(root: i32) -> Vec<Proc> {
    let all = pids();
    let mut parent = Vec::new();
    for &pid in &all {
        parent.push((pid, ppid(pid).unwrap_or(0)));
    }
    let mut found = vec![root];
    // Bounded by the number of processes: each pass can only add children of
    // something already found, so at most one pass per process.
    for _ in 0..all.len().max(1) {
        let before = found.len();
        for &(pid, par) in &parent {
            if found.contains(&par) && !found.contains(&pid) {
                found.push(pid);
            }
        }
        if found.len() == before {
            break;
        }
    }
    found
        .into_iter()
        .skip(1) // the root itself is the caller's business
        .filter_map(|pid| cmdline(pid).map(|c| Proc { pid, cmdline: c }))
        .collect()
}

pub fn alive(pid: i32) -> bool {
    pid > 0 && std::path::Path::new(&format!("/proc/{pid}")).exists()
}

/// Whether a live pid is still the sharukhan that recorded it. The kernel
/// recycles pids, and a job row outlives the process it names, so signalling a
/// recorded pid without this check can signal an unrelated program. It is a
/// strong guard, not a proof - see ADR-0001 "Limits".
pub fn looks_like_sharukhan(pid: i32) -> bool {
    let Some(cmd) = cmdline(pid) else {
        return false;
    };
    cmd.split_whitespace()
        .next()
        .and_then(|a| a.rsplit('/').next())
        .map(|b| b == "sharukhan")
        .unwrap_or(false)
}

pub const SIGTERM: i32 = 15;
pub const SIGKILL: i32 = 9;

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

/// Returns whether the signal was accepted. A false here means the process was
/// already gone or is not ours to signal; both are reported, never assumed.
pub fn signal(pid: i32, sig: i32) -> bool {
    if pid <= 0 {
        return false;
    }
    unsafe { kill(pid, sig) == 0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn head_matches_looks_at_program_and_script_only() {
        // The wrapper that ran beside a sharukhan build on 2026-09-26.
        assert!(head_matches("/bin/sh /tmp/runPh7-3-RC4.5vU5M2.sh /root common", &["runPh"]));
        assert!(head_matches("sh /root/photon-mc/work/scriptdir/x/runPh5_normal.sh /root", &["runPh"]));
        // A deeper argument is not the process being run.
        assert!(!head_matches("tail -f /root/runPh7-3-RC4.run10.log", &["runPh"]));
    }

    #[test]
    fn photon_builder_is_recognised_behind_any_wrapper() {
        for cmd in [
            "python3 build.py -c build-config.json -t image",
            "/usr/bin/python3 /root/common/build.py -c build-config.json",
            "sudo python3 build.py -c build-config.json -t image",
            "env python3.11 build.py -t packages",
        ] {
            assert!(runs_python_script(cmd, "build.py"), "{cmd}");
        }
    }

    #[test]
    fn mentioning_build_py_is_not_running_it() {
        for cmd in [
            "vim build.py",
            "grep -n check_docker build.py",
            "git diff -- build.py",
            "python3 other.py build.py",
            "python3 -c import build",
        ] {
            assert!(!runs_python_script(cmd, "build.py"), "{cmd}");
        }
    }
}
