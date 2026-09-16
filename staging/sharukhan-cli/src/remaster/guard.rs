//! The disk guard: a multi-hour build must not die of a full filesystem.
//!
//! It PAUSES, it never kills. The kernel build tree is tens of gigabytes of
//! work that took hours to produce, so the response to "300 MB left" is
//! SIGSTOP to the build's process group and SIGCONT once space comes back -
//! not SIGKILL, which throws the work away to solve a problem that is usually
//! transient (another build's sandbox, a log, a downloaded tarball).
//!
//! The decision is a pure function of the measured free space, so the
//! hysteresis can be tested without filling a disk. That matters: a guard with
//! one threshold instead of two oscillates - pause at 1 GB, resume at 1 GB,
//! pause again - and spends the build stopping and starting.

use std::path::Path;

/// Free space on every filesystem the build depends on, in KiB.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Free {
    /// The host root, where docker images and the build root live.
    pub root: u64,
    /// The work directory - usually the same filesystem, sometimes not.
    pub work: u64,
    /// The output volume the finished ISO is written to.
    pub out: u64,
    /// MemAvailable + SwapFree. A swap-backed tmpfs build tree runs out of
    /// MEMORY rather than disk, and the symptom is identical.
    pub mem: u64,
}

/// The thresholds, in KiB. Two of them per resource on purpose: see the module
/// comment on oscillation.
#[derive(Debug, Clone, Copy)]
pub struct Thresholds {
    pub root_low: u64,
    pub root_resume: u64,
    pub work_low: u64,
    pub work_resume: u64,
    pub out_low: u64,
    pub out_resume: u64,
    pub mem_low: u64,
    pub mem_resume: u64,
}

impl Default for Thresholds {
    /// The PoC's values, which were arrived at by hitting the wall: it stopped
    /// on a full root part-way through a kernel build. `out_low` is larger than
    /// the others because the finished ISO is ~4.3 GB and is written in one go
    /// at the end, so running out there wastes the whole run.
    fn default() -> Self {
        Thresholds {
            root_low: 4_000_000,
            root_resume: 6_000_000,
            work_low: 4_000_000,
            work_resume: 6_000_000,
            out_low: 6_000_000,
            out_resume: 8_000_000,
            mem_low: 2_000_000,
            mem_resume: 3_000_000,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    /// Leave it running.
    Continue,
    /// Stop the process group; the string says which resource and how much.
    Pause(String),
    /// Resume it.
    Resume(String),
}

/// What to do, given what was measured and whether the build is already paused.
///
/// Pure, so the hysteresis is testable. Resuming requires EVERY resource to be
/// back above its resume threshold; pausing needs only one to be below its low
/// threshold. Asymmetric on purpose: one full filesystem stops the build, but
/// one recovered filesystem does not make it safe to continue.
pub fn decision(f: &Free, paused: bool, t: &Thresholds) -> Decision {
    let low: Vec<String> = [
        ("root", f.root, t.root_low),
        ("work", f.work, t.work_low),
        ("out", f.out, t.out_low),
        ("mem+swap", f.mem, t.mem_low),
    ]
    .iter()
    .filter(|(_, have, limit)| have < limit)
    .map(|(name, have, limit)| format!("{name}={}M (below {}M)", have / 1024, limit / 1024))
    .collect();

    if !paused {
        if low.is_empty() {
            return Decision::Continue;
        }
        return Decision::Pause(low.join(", "));
    }

    let still: Vec<String> = [
        ("root", f.root, t.root_resume),
        ("work", f.work, t.work_resume),
        ("out", f.out, t.out_resume),
        ("mem+swap", f.mem, t.mem_resume),
    ]
    .iter()
    .filter(|(_, have, limit)| have < limit)
    .map(|(name, have, limit)| format!("{name}={}M (needs {}M)", have / 1024, limit / 1024))
    .collect();
    if still.is_empty() {
        return Decision::Resume(format!(
            "root={}M work={}M out={}M mem+swap={}M",
            f.root / 1024,
            f.work / 1024,
            f.out / 1024,
            f.mem / 1024
        ));
    }
    Decision::Continue
}

/// Free KiB on the filesystem holding `p`, via statvfs. `None` when the path
/// cannot be stat'd - reported, never silently treated as "plenty".
pub fn avail_kb(p: &Path) -> Option<u64> {
    // statvfs rather than parsing `df`, whose output format and units differ
    // between coreutils and busybox.
    #[repr(C)]
    #[derive(Default)]
    struct StatVfs {
        f_bsize: u64,
        f_frsize: u64,
        f_blocks: u64,
        f_bfree: u64,
        f_bavail: u64,
        f_files: u64,
        f_ffree: u64,
        f_favail: u64,
        f_fsid: u64,
        f_flag: u64,
        f_namemax: u64,
        f_spare: [u64; 6],
    }
    extern "C" {
        fn statvfs(path: *const u8, buf: *mut StatVfs) -> i32;
    }
    let mut c: Vec<u8> = p.to_string_lossy().as_bytes().to_vec();
    c.push(0);
    let mut s = StatVfs::default();
    let rc = unsafe { statvfs(c.as_ptr(), &mut s) };
    if rc != 0 {
        return None;
    }
    let unit = if s.f_frsize > 0 { s.f_frsize } else { s.f_bsize };
    Some(s.f_bavail.saturating_mul(unit) / 1024)
}

/// MemAvailable + SwapFree, in KiB. A tmpfs build tree exhausts these rather
/// than a filesystem, and the failure looks exactly the same from the build.
pub fn mem_avail_kb() -> Option<u64> {
    let text = std::fs::read_to_string("/proc/meminfo").ok()?;
    let mut avail = 0u64;
    let mut swap = 0u64;
    for line in text.lines() {
        let mut it = line.split_whitespace();
        let (Some(k), Some(v)) = (it.next(), it.next()) else { continue };
        let Ok(n) = v.parse::<u64>() else { continue };
        match k {
            "MemAvailable:" => avail = n,
            "SwapFree:" => swap = n,
            _ => {}
        }
    }
    Some(avail + swap)
}

/// Measure every resource the build depends on.
pub fn measure(work: &Path, out: &Path) -> Free {
    Free {
        root: avail_kb(Path::new("/")).unwrap_or(0),
        work: avail_kb(work).unwrap_or(0),
        out: avail_kb(out).unwrap_or(0),
        mem: mem_avail_kb().unwrap_or(0),
    }
}

pub const SIGSTOP: i32 = 19;
pub const SIGCONT: i32 = 18;

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

/// Signal a whole PROCESS GROUP, which is what `kill(-pgid, sig)` means.
///
/// The group, not the pid: rpmbuild forks make, which forks compilers, and
/// stopping only the pid leaves several hundred cc1 processes running into the
/// wall the guard just detected.
pub fn signal_group(pgid: i32, sig: i32) -> bool {
    if pgid <= 1 {
        return false;
    }
    unsafe { kill(-pgid, sig) == 0 }
}

/// Whether any process in the group is still alive.
pub fn group_alive(pgid: i32) -> bool {
    if pgid <= 1 {
        return false;
    }
    // Signal 0 tests deliverability without delivering anything.
    unsafe { kill(-pgid, 0) == 0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plenty() -> Free {
        Free { root: 100_000_000, work: 100_000_000, out: 100_000_000, mem: 20_000_000 }
    }

    #[test]
    fn disk_guard_stops_below_threshold() {
        let t = Thresholds::default();
        assert_eq!(decision(&plenty(), false, &t), Decision::Continue);

        let mut f = plenty();
        f.root = 1_000_000; // 1 GB, below the 4 GB floor
        match decision(&f, false, &t) {
            Decision::Pause(why) => {
                // The reason has to name the resource AND the number: "low
                // disk" sends an operator to the wrong filesystem.
                assert!(why.contains("root"), "{why}");
                assert!(why.contains("976M"), "{why}");
            }
            other => panic!("expected a pause, got {other:?}"),
        }
    }

    /// Any ONE resource can stop the build - including memory, because a
    /// swap-backed build tree runs out of memory rather than disk and the
    /// symptom is identical.
    #[test]
    fn each_resource_can_pause_the_build_on_its_own() {
        let t = Thresholds::default();
        for (name, set) in [
            ("root", (|f: &mut Free| f.root = 1) as fn(&mut Free)),
            ("work", |f: &mut Free| f.work = 1),
            ("out", |f: &mut Free| f.out = 1),
            ("mem+swap", |f: &mut Free| f.mem = 1),
        ] {
            let mut f = plenty();
            set(&mut f);
            match decision(&f, false, &t) {
                Decision::Pause(why) => assert!(why.contains(name), "{name}: {why}"),
                other => panic!("{name} must pause the build, got {other:?}"),
            }
        }
    }

    /// The hysteresis is the whole point. At a level that is above the pause
    /// floor but below the resume floor, a paused build must STAY paused -
    /// otherwise it oscillates and spends the build stopping and starting.
    #[test]
    fn a_paused_build_resumes_only_above_the_higher_threshold() {
        let t = Thresholds::default();
        let mut f = plenty();
        f.root = 5_000_000; // above root_low (4G), below root_resume (6G)
        assert_eq!(
            decision(&f, true, &t),
            Decision::Continue,
            "still paused: 5G is past the pause floor but not past the resume floor"
        );
        // And the same level does not pause a RUNNING build, which is what
        // makes the band a band rather than a second threshold.
        assert_eq!(decision(&f, false, &t), Decision::Continue);

        f.root = 7_000_000;
        match decision(&f, true, &t) {
            Decision::Resume(detail) => assert!(detail.contains("root=6835M"), "{detail}"),
            other => panic!("expected a resume, got {other:?}"),
        }
    }

    /// Resuming needs EVERY resource back, not just the one that tripped.
    #[test]
    fn one_recovered_filesystem_does_not_resume_a_build_another_is_still_starving() {
        let t = Thresholds::default();
        let mut f = plenty();
        f.root = 7_000_000; // recovered
        f.work = 100_000; // still starving
        assert_eq!(decision(&f, true, &t), Decision::Continue);
    }

    /// The guard must measure something real, or every decision above is taken
    /// on zeros - which would pause the build permanently on a healthy host.
    #[test]
    fn free_space_and_memory_are_actually_measured_on_this_host() {
        let root = avail_kb(Path::new("/")).expect("/ must be stat-able");
        assert!(root > 0, "statvfs reported no free space on /");
        // A path that cannot exist reports None rather than zero: "I could not
        // look" and "there is no space" need different responses.
        assert_eq!(avail_kb(Path::new("/no/such/path/sharukhan-xyz")), None);
        let mem = mem_avail_kb().expect("/proc/meminfo must be readable");
        assert!(mem > 0, "MemAvailable+SwapFree came back as zero");
    }

    /// Signalling group 0 or 1 would hit this process's own group or init.
    #[test]
    fn a_nonsense_process_group_is_refused_rather_than_signalled() {
        assert!(!signal_group(0, SIGCONT), "pgid 0 means OUR group");
        assert!(!signal_group(1, SIGCONT), "pgid 1 means init");
        assert!(!signal_group(-5, SIGCONT));
        assert!(!group_alive(0));
    }
}
