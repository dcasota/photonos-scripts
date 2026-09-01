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
    let skip = self_and_ancestors();
    let mine = own_argv0();
    let mut out = Vec::new();
    for pid in pids() {
        if skip.contains(&pid) {
            continue;
        }
        let Some(cmd) = cmdline(pid) else { continue };
        let argv: Vec<&str> = cmd.split_whitespace().collect();
        let argv0 = argv
            .first()
            .and_then(|a| a.rsplit('/').next())
            .unwrap_or("");
        if !mine.is_empty() && argv0 == mine {
            continue;
        }
        let head = &argv[..argv.len().min(2)];
        if needles.iter().any(|n| head.iter().any(|a| a.contains(n))) {
            out.push(Proc { pid, cmdline: cmd });
        }
    }
    out.sort_by_key(|p| p.pid);
    out
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
    let Some(cmd) = cmdline(pid) else { return false };
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
