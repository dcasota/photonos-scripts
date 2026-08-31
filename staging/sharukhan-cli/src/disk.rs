//! Disk admission control.
//!
//! Running out of space part-way through leaves a half-written VM and a verdict
//! that means nothing, so capacity is checked BEFORE work starts rather than
//! discovered during it.

use std::process::Command;

#[derive(Debug, Clone, Copy)]
pub struct Space {
    pub avail_gb: u64,
    pub use_pct: u64,
}

pub fn space(path: &str) -> Option<Space> {
    let out = Command::new("df").args(["-BG", path]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let line = text.lines().nth(1)?;
    let f: Vec<&str> = line.split_whitespace().collect();
    if f.len() < 5 {
        return None;
    }
    let avail = f[3].trim_end_matches('G').parse().ok()?;
    let pct = f[4].trim_end_matches('%').parse().ok()?;
    Some(Space { avail_gb: avail, use_pct: pct })
}

/// What a unit of work needs, in GB, on each filesystem.
pub struct Need {
    pub root_gb: u64,
    pub vmstore_gb: u64,
    pub what: &'static str,
}

pub const VM_RUN: Need = Need { root_gb: 5, vmstore_gb: 20, what: "install one VM" };
pub const ISO_BUILD: Need = Need { root_gb: 25, vmstore_gb: 5, what: "build an ISO" };

pub enum Verdict {
    Admit,
    Refuse(String),
}

pub fn admit(need: &Need, root: &str, vmstore: &str) -> Verdict {
    let r = space(root);
    let v = space(vmstore);
    let (Some(r), Some(v)) = (r, v) else {
        return Verdict::Refuse(format!("cannot read free space on {root} or {vmstore}"));
    };
    if r.avail_gb < need.root_gb {
        return Verdict::Refuse(format!(
            "not enough space to {}: {} has {}G free, needs {}G",
            need.what, root, r.avail_gb, need.root_gb
        ));
    }
    if v.avail_gb < need.vmstore_gb {
        return Verdict::Refuse(format!(
            "not enough space to {}: {} has {}G free, needs {}G",
            need.what, vmstore, v.avail_gb, need.vmstore_gb
        ));
    }
    Verdict::Admit
}

/// How many VMs may run at once. Default is CPUs/4 rounded down, floored at 1,
/// then capped by how many VMs the VM store can actually hold - parallelism
/// that fills the disk is worse than none.
pub fn max_parallel(vmstore: &str, requested: Option<u64>) -> (u64, String) {
    let cpus = std::thread::available_parallelism().map(|n| n.get() as u64).unwrap_or(4);
    let by_cpu = std::cmp::max(1, cpus / 4);
    let want = requested.unwrap_or(by_cpu);
    let by_disk = space(vmstore)
        .map(|s| std::cmp::max(1, s.avail_gb / VM_RUN.vmstore_gb))
        .unwrap_or(1);
    let n = std::cmp::min(want, by_disk);
    let why = if n < want {
        format!("{n} (requested {want}, but {vmstore} only has room for {by_disk})")
    } else {
        format!("{n} (cpus={cpus} -> {by_cpu}{})", if requested.is_some() { ", requested" } else { "" })
    };
    (n, why)
}
