//! `run`, `stop`, `watch` - the orchestration that eight bash drivers each
//! reimplemented.
//!
//! `run` decides and serialises; it builds nothing and installs nothing itself.
//! Every expensive step is still `mission-control`'s: mc-run.sh drives the ISO
//! resolution, VM creation, install and verification. What lives here is the
//! part the drivers got wrong often enough to be worth writing once - the
//! gates in front of that call, and the record that makes the work findable
//! afterwards.

use crate::config::Config;
use crate::matrix::Permutation;
use crate::{disk, job, matrix, media, proc, vmware};
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// What the bash drivers waited on: a build or an install already in flight.
/// runPh5_normal.sh is included because an ISO build is reachable without
/// mc-build-iso.sh in the argv when someone runs the build script directly.
const FOREIGN: &[&str] = &["bin/mc-run.sh", "bin/mc-build-iso.sh", "runPh5_normal"];

pub struct RunOpts {
    pub only: Option<String>,
    pub all: bool,
    pub dry_run: bool,
    pub keep: bool,
    pub settle: u64,
    pub wait_idle: u64,
    pub log: Option<String>,
}

// ---------------------------------------------------------------- run ------

/// One ISO's worth of rows, with the verdict of the gates in front of it.
struct Group {
    key: String,
    iso: PathBuf,
    rows: Vec<Permutation>,
    /// None while the group is still admissible; Some(reason) once refused.
    refused: Option<String>,
    /// The media observation, made exactly once. A later phase never re-derives
    /// it: evidence observed in one phase is authoritative.
    gate: Option<media::Gate>,
    age: u64,
}

pub fn cmd_run(cfg: &Config, o: &RunOpts) -> Result<(), String> {
    if !o.all && o.only.is_none() {
        return Err("run needs --only <ids> or --all; it will not guess a selection".into());
    }
    let all_rows = matrix::load(&cfg.matrix_tsv)?;
    let sel = matrix::select(&all_rows, o.only.as_deref())?;

    // --- what this host and this harness can actually drive ----------------
    let mut runnable: Vec<Permutation> = Vec::new();
    println!("selection: {} row(s)", sel.len());
    for p in &sel {
        if p.is_unrunnable_here() {
            println!(
                "  refused {:<5} canister={} needs aarch64, this host is {}",
                p.id,
                p.canister,
                std::env::consts::ARCH
            );
        } else if p.needs_operator() {
            println!(
                "  refused {:<5} mode=ui needs a human at the console: {}/mc-operator-card.sh --id {}",
                p.id,
                cfg.mc_bin.display(),
                p.id
            );
        } else {
            runnable.push(p.clone());
        }
    }
    if runnable.is_empty() {
        return Err("nothing in the selection can be run autonomously on this host".into());
    }
    println!("  {} row(s) can run autonomously", runnable.len());

    // --- serialisation -----------------------------------------------------
    // Chained on a recorded job, not on a generic idle poll. Two drivers
    // polling the same idle condition both wake when it clears, and both start
    // work; a row in the database is a completion marker one of them owns.
    let conn = job::open_rw(&cfg.memory_db)?;
    println!("\nserialisation");
    let mut stale = Vec::new();
    let mut live = Vec::new();
    for j in job::list(&conn, true)? {
        if j.is_live() {
            live.push(j);
        } else {
            stale.push(j);
        }
    }
    for j in &stale {
        println!(
            "  note    job {} claims 'running' but {} - it did not finish cleanly; \
             `sharukhan stop --job {}` will close it",
            j.id,
            j.liveness(),
            j.id
        );
    }
    if let Some(j) = live.first() {
        return Err(format!(
            "job {} ({} {}) is still running as pid {}; refusing to start a second one. \
             Watch it with `sharukhan watch --job {}` or end it with `sharukhan stop --job {}`",
            j.id,
            j.kind,
            j.label,
            j.pid.unwrap_or(0),
            j.id,
            j.id
        ));
    }
    println!("  ok      no sharukhan job is running");
    wait_for_idle(o.wait_idle)?;

    // --- disk, before anything starts --------------------------------------
    let vmstore = cfg.vm_root.to_str().unwrap_or("/");
    println!("\ndisk");
    match disk::admit(&disk::VM_RUN, "/", vmstore) {
        disk::Verdict::Admit => {
            let r = disk::space("/").map(|s| s.avail_gb).unwrap_or(0);
            let v = disk::space(vmstore).map(|s| s.avail_gb).unwrap_or(0);
            println!("  ok      / {r}G free, VM store {v}G free");
        }
        disk::Verdict::Refuse(why) => return Err(why),
    }

    // --- media, once per ISO -----------------------------------------------
    let mut groups = group_rows(cfg, &runnable);
    println!("\nmedia");
    for g in &mut groups {
        if !g.iso.exists() {
            g.refused = Some(format!(
                "no ISO at {} - build it with `{}/mc-build-iso.sh --iso-type {} --poi {} --canister {}` \
                 (hours, not minutes)",
                g.iso.display(),
                cfg.mc_bin.display(),
                g.rows[0].iso_type,
                g.rows[0].poi,
                g.rows[0].canister
            ));
            println!("  REFUSED {:<24} {}", g.key, g.refused.as_ref().unwrap());
            continue;
        }
        match media::settled(&g.iso, o.settle) {
            Ok(age) => g.age = age,
            Err(why) => {
                g.refused = Some(why);
                println!("  REFUSED {:<24} {}", g.key, g.refused.as_ref().unwrap());
                continue;
            }
        }
        let patch = cfg.variant_patches.join(format!("poi-{}.patch", g.rows[0].poi));
        match media::gate(&g.iso, &patch, &cfg.photon_tree) {
            Ok(gate) => {
                println!(
                    "  {} {:<24} media has {} (expected {}*), written {}s ago",
                    if gate.ok { "ok     " } else { "REFUSED" },
                    g.key,
                    gate.actual,
                    gate.expected,
                    g.age
                );
                if !gate.ok {
                    g.refused = Some(format!(
                        "media carries {} but this variant asks for {}* - verdicts would be meaningless",
                        gate.actual, gate.expected
                    ));
                }
                g.gate = Some(gate);
            }
            Err(why) => {
                g.refused = Some(why);
                println!("  REFUSED {:<24} {}", g.key, g.refused.as_ref().unwrap());
            }
        }
    }

    let admissible: usize = groups.iter().filter(|g| g.refused.is_none()).map(|g| g.rows.len()).sum();
    if admissible == 0 {
        return Err("every ISO group was refused; nothing would be run".into());
    }

    if o.dry_run {
        println!("\nwould run {admissible} row(s), sequentially:");
        for g in &groups {
            if g.refused.is_some() {
                continue;
            }
            for p in &g.rows {
                println!(
                    "  {:<5} {:<24} {}/mc-run.sh --only {}{}",
                    p.id,
                    g.key,
                    cfg.mc_bin.display(),
                    p.id,
                    if o.keep { " --keep" } else { "" }
                );
            }
        }
        println!("\ndry run: no job recorded, nothing executed");
        return Ok(());
    }

    // --- execute -----------------------------------------------------------
    let stamp = stamp();
    let log_path = match &o.log {
        Some(p) => PathBuf::from(p),
        None => cfg.run_log_dir.join(format!("run-{stamp}.log")),
    };
    if let Some(dir) = log_path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    }
    File::create(&log_path).map_err(|e| format!("{}: {e}", log_path.display()))?;

    let label = runnable.iter().map(|p| p.id.as_str()).collect::<Vec<_>>().join(",");
    let pid = std::process::id() as i32;
    let job_id = job::start(&conn, "run", &label, pid, &log_path.to_string_lossy())?;
    println!("\njob {job_id} (pid {pid}) -> {}", log_path.display());
    println!("  sharukhan watch --job {job_id}");
    println!("  sharukhan stop  --job {job_id}");

    let mut logf = OpenOptions::new()
        .append(true)
        .open(&log_path)
        .map_err(|e| format!("{}: {e}", log_path.display()))?;
    say(&mut logf, &format!("job {job_id} pid {pid} selection {label}"));
    for g in &groups {
        match (&g.refused, &g.gate) {
            (Some(why), _) => say(&mut logf, &format!("group {} REFUSED: {why}", g.key)),
            (None, Some(gate)) => say(
                &mut logf,
                &format!(
                    "group {} admitted: media {} matches {}*, ISO {}s old",
                    g.key, gate.actual, gate.expected, g.age
                ),
            ),
            (None, None) => say(&mut logf, &format!("group {} admitted", g.key)),
        }
    }

    let mut attempted = 0usize;
    let mut halted: Option<String> = None;
    'outer: for g in &groups {
        if g.refused.is_some() {
            continue;
        }
        for p in &g.rows {
            // Re-check before EVERY row, and stop rather than skip: one row
            // short of space means the next one is too.
            if let disk::Verdict::Refuse(why) = disk::admit(&disk::VM_RUN, "/", vmstore) {
                halted = Some(format!("stopped before {}: {why}", p.id));
                say(&mut logf, halted.as_ref().unwrap());
                println!("  {}", halted.as_ref().unwrap());
                break 'outer;
            }
            attempted += 1;
            say(&mut logf, &format!("--- {} ---", p.id));
            println!("  running {} ({})", p.id, g.key);
            let (rc, verdict) = run_one(cfg, &p.id, o.keep, &log_path, &mut logf);
            let line = match verdict {
                Some(v) => format!("{}: {v}", p.id),
                // mc-run.sh ends with mc_report_to_file, so its exit code
                // reflects the last tee, not the verdict. Report the rc as the
                // only thing observed, and do not call it a result.
                None => format!(
                    "{}: no summary line in the log (mc-run.sh exited {rc}, which is not a verdict)",
                    p.id
                ),
            };
            say(&mut logf, &line);
            println!("  {line}");
        }
    }

    let state = if halted.is_some() { job::FAILED } else { job::DONE };
    say(&mut logf, &format!("job {job_id} {state}: {attempted} row(s) attempted"));
    job::finish(&conn, job_id, state)?;
    println!("\njob {job_id} {state}: {attempted} of {admissible} admissible row(s) attempted");
    println!("evidence: {}", log_path.display());
    println!("results:  sharukhan report --only {label}");
    if let Some(h) = halted {
        return Err(h);
    }
    Ok(())
}

/// Group rows by the ISO that serves them, keeping matrix order so the cheap
/// rows of a cached ISO run before anything that needs another one.
fn group_rows(cfg: &Config, rows: &[Permutation]) -> Vec<Group> {
    let mut out: Vec<Group> = Vec::new();
    for p in rows {
        let key = p.iso_key();
        if let Some(g) = out.iter_mut().find(|g| g.key == key) {
            g.rows.push(p.clone());
            continue;
        }
        let dir = format!("{}-poi{}-{}", p.iso_type, p.poi, p.canister);
        out.push(Group {
            key,
            iso: cfg.iso_cache.join(dir).join("photon.iso"),
            rows: vec![p.clone()],
            refused: None,
            gate: None,
            age: 0,
        });
    }
    out
}

/// Wait for foreign build/install work, bounded. The bash form waited forever,
/// which is only safe when a human is watching.
fn wait_for_idle(max_secs: u64) -> Result<(), String> {
    let mut waited = 0;
    loop {
        let busy = proc::matching(FOREIGN);
        if busy.is_empty() {
            println!("  ok      no mc-run / mc-build-iso / runPh5 in flight");
            return Ok(());
        }
        if waited >= max_secs {
            let who: Vec<String> = busy
                .iter()
                .map(|p| format!("pid {} {}", p.pid, first_words(&p.cmdline, 6)))
                .collect();
            return Err(format!(
                "foreign work is in flight: {}. ISO builds share $PHOTON_TREE/stage and the VM \
                 store cannot hold two installs, so this would corrupt both. Wait, or pass \
                 --wait-idle <sec>",
                who.join("; ")
            ));
        }
        println!("  wait    {} process(es) in flight, waited {waited}s of {max_secs}s", busy.len());
        std::thread::sleep(std::time::Duration::from_secs(15));
        waited += 15;
    }
}

/// Invoke mc-run.sh for one row, appending its output to the run log, and
/// scrape the summary line it prints. Returns (exit code, verdict).
fn run_one(
    cfg: &Config,
    id: &str,
    keep: bool,
    log_path: &Path,
    logf: &mut File,
) -> (i32, Option<String>) {
    let before = logf.metadata().map(|m| m.len()).unwrap_or(0);
    let script = cfg.mc_bin.join("mc-run.sh");
    let (out, err) = match (
        OpenOptions::new().append(true).open(log_path),
        OpenOptions::new().append(true).open(log_path),
    ) {
        (Ok(a), Ok(b)) => (a, b),
        _ => return (-1, None),
    };
    let mut cmd = Command::new("bash");
    cmd.arg(&script).args(["--only", id]);
    if keep {
        cmd.arg("--keep");
    }
    let rc = cmd
        .stdout(Stdio::from(out))
        .stderr(Stdio::from(err))
        .status()
        .map(|s| s.code().unwrap_or(-1))
        .unwrap_or(-1);
    (rc, scrape(log_path, before, id))
}

/// mc_result_summary prints "  <id>: N checks, N pass, N fail". That line is
/// the evidence; the exit code is not.
fn scrape(log_path: &Path, from: u64, id: &str) -> Option<String> {
    let mut f = File::open(log_path).ok()?;
    f.seek(SeekFrom::Start(from)).ok()?;
    let mut text = String::new();
    f.read_to_string(&mut text).ok()?;
    let want = format!("{id}:");
    text.lines()
        .map(str::trim)
        .filter(|l| l.starts_with(&want) && l.contains("checks,"))
        .next_back()
        .map(|l| l[want.len()..].trim().to_string())
}

fn say(f: &mut File, msg: &str) {
    let _ = writeln!(f, "[sharukhan {}] {msg}", job::now());
    let _ = f.flush();
}

fn stamp() -> String {
    Command::new("date")
        .args(["-u", "+%Y%m%dT%H%M%SZ"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unstamped".into())
}

fn first_words(s: &str, n: usize) -> String {
    s.split_whitespace().take(n).collect::<Vec<_>>().join(" ")
}

// --------------------------------------------------------------- stop ------

pub fn cmd_stop(cfg: &Config, target: Option<i64>, all: bool, dry: bool) -> Result<(), String> {
    let conn = job::open_rw(&cfg.memory_db)?;
    let jobs = match (target, all) {
        (Some(id), _) => vec![job::get(&conn, id)?.ok_or_else(|| format!("no job {id}"))?],
        (None, true) => job::list(&conn, true)?,
        (None, false) => return Err("stop needs --job <id> or --all".into()),
    };
    if jobs.is_empty() {
        println!("no job is running");
        return Ok(());
    }

    for j in &jobs {
        println!("job {} {} {} (state {}, {})", j.id, j.kind, j.label, j.state, j.liveness());
        if j.state != job::RUNNING {
            println!("  already {} at {}; nothing to signal", j.state, j.finished_at);
            continue;
        }
        if !j.is_live() {
            // The crashed-driver case. The row is stale, not true.
            if dry {
                println!("  would close the row: {}", j.liveness());
                continue;
            }
            job::finish(&conn, j.id, job::STOPPED)?;
            println!("  {} - closed the row, no process to signal", j.liveness());
            continue;
        }

        let pid = j.pid.unwrap_or(0) as i32;
        let kids = proc::descendants(pid);
        println!("  pid {pid} plus {} descendant(s)", kids.len());
        for k in &kids {
            println!("    {} {}", k.pid, first_words(&k.cmdline, 8));
        }
        if dry {
            println!("  dry run: nothing signalled");
            continue;
        }

        // The parent first, so it cannot start another row while its children
        // are being ended.
        proc::signal(pid, proc::SIGTERM);
        for k in &kids {
            proc::signal(k.pid, proc::SIGTERM);
        }
        let mut left = survivors(pid, &kids);
        let mut waited = 0;
        while !left.is_empty() && waited < 10 {
            std::thread::sleep(std::time::Duration::from_secs(1));
            waited += 1;
            left = survivors(pid, &kids);
        }
        if !left.is_empty() {
            println!("  {} process(es) ignored SIGTERM after {waited}s; sending SIGKILL", left.len());
            for p in &left {
                proc::signal(*p, proc::SIGKILL);
            }
            std::thread::sleep(std::time::Duration::from_secs(1));
            left = survivors(pid, &kids);
        }
        job::finish(&conn, j.id, job::STOPPED)?;
        if left.is_empty() {
            println!("  stopped after {waited}s; job {} closed", j.id);
        } else {
            // Never claim a kill that did not happen.
            println!(
                "  job {} closed, but {} process(es) are STILL ALIVE: {}",
                j.id,
                left.len(),
                left.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(", ")
            );
        }
    }

    // A VM outlives the driver that started it. Powering one off is
    // mc-teardown.sh's job - it has stash-not-delete and UEFI NVRAM semantics
    // that must not be duplicated - and this host also runs VMs that are not
    // ours. So: report, never act.
    report_vms(cfg, "still powered on");
    Ok(())
}

fn survivors(root: i32, kids: &[proc::Proc]) -> Vec<i32> {
    let mut out = Vec::new();
    if proc::alive(root) {
        out.push(root);
    }
    for k in kids {
        if proc::alive(k.pid) {
            out.push(k.pid);
        }
    }
    out
}

/// Which VMs are up, split into ours and everything else. The inventory is the
/// authority; no exit code is consulted.
fn report_vms(cfg: &Config, when: &str) {
    let Ok(all) = matrix::load(&cfg.matrix_tsv) else { return };
    match vmware::running(&cfg.vmrun) {
        Ok(list) => {
            let mine: Vec<&str> = all
                .iter()
                .filter(|p| {
                    let vm = format!("mc-{}.vmx", p.id).to_lowercase();
                    list.iter().any(|l| l.to_lowercase().contains(&vm))
                })
                .map(|p| p.id.as_str())
                .collect();
            let others = list.len() - mine.len();
            if mine.is_empty() {
                println!("\nno matrix VM is {when} ({others} other VM(s) on this host, untouched)");
            } else {
                println!(
                    "\nmatrix VMs {when}: {} - not powered off; use `{}/mc-teardown.sh --id <id>`",
                    mine.join(", "),
                    cfg.mc_bin.display()
                );
                println!("{others} other VM(s) on this host, untouched");
            }
        }
        Err(e) => println!("\nVM inventory unavailable: {e}"),
    }
}

// -------------------------------------------------------------- watch ------

pub fn cmd_watch(cfg: &Config, target: Option<i64>, once: bool, interval: u64) -> Result<(), String> {
    let conn = job::open_rw(&cfg.memory_db)?;
    match target {
        None => {
            snapshot(cfg, &conn)?;
            Ok(())
        }
        Some(id) => follow(cfg, &conn, id, once, interval),
    }
}

fn snapshot(cfg: &Config, conn: &rusqlite::Connection) -> Result<(), String> {
    let jobs = job::list(conn, false)?;
    if jobs.is_empty() {
        println!("no jobs recorded");
    } else {
        println!("  {:<4} {:<8} {:<9} {:<26} {:<20} {}", "JOB", "KIND", "STATE", "LIVENESS", "STARTED", "LABEL");
        for j in &jobs {
            let liveness = if j.state == job::RUNNING {
                j.liveness().to_string()
            } else {
                format!("pid {}", j.pid.unwrap_or(0))
            };
            println!(
                "  {:<4} {:<8} {:<9} {:<26} {:<20} {}",
                j.id, j.kind, j.state, liveness, j.started_at, j.label
            );
        }
        let confused: Vec<i64> = jobs
            .iter()
            .filter(|j| j.state == job::RUNNING && !j.is_live())
            .map(|j| j.id)
            .collect();
        if !confused.is_empty() {
            println!(
                "\njob(s) {} claim 'running' but their process is gone - they did not finish \
                 cleanly. `sharukhan stop --job <id>` closes the row.",
                confused.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(", ")
            );
        }
    }
    report_vms(cfg, "up");
    let vmstore = cfg.vm_root.to_str().unwrap_or("/");
    for (label, path) in [("/", "/"), ("VM store", vmstore)] {
        match disk::space(path) {
            Some(s) => println!("{:<10} {}G free ({}% used)", label, s.avail_gb, s.use_pct),
            None => println!("{label:<10} unreadable"),
        }
    }
    Ok(())
}

fn follow(
    cfg: &Config,
    conn: &rusqlite::Connection,
    id: i64,
    once: bool,
    interval: u64,
) -> Result<(), String> {
    let j = job::get(conn, id)?.ok_or_else(|| format!("no job {id}"))?;
    println!(
        "job {} {} {} - state {}, {}, started {}",
        j.id, j.kind, j.label, j.state, j.liveness(), j.started_at
    );
    println!("log {}", j.log_path);
    let log = PathBuf::from(&j.log_path);

    if once {
        tail(&log, 20);
        return finished_verdict(&j);
    }

    // Start from the end of the log so following an in-flight job does not
    // replay hours of output, but show the last few lines for context.
    tail(&log, 10);
    let mut offset = std::fs::metadata(&log).map(|m| m.len()).unwrap_or(0);
    loop {
        let cur = job::get(conn, id)?.ok_or_else(|| format!("job {id} disappeared"))?;
        offset = drain(&log, offset);
        if cur.state != job::RUNNING {
            println!("\njob {id} finished: {} at {}", cur.state, cur.finished_at);
            report_vms(cfg, "up");
            return finished_verdict(&cur);
        }
        if !cur.is_live() {
            // The failure that made a bash waiter loop forever: waiting on
            // something that is already gone. Say so and stop.
            println!(
                "\njob {id} still says 'running' but {} - it did not finish cleanly. \
                 `sharukhan stop --job {id}` closes the row.",
                cur.liveness()
            );
            return Err(format!("job {id} died without finishing"));
        }
        std::thread::sleep(std::time::Duration::from_secs(interval.max(1)));
    }
}

fn finished_verdict(j: &job::Job) -> Result<(), String> {
    match j.state.as_str() {
        job::DONE => Ok(()),
        job::RUNNING => Ok(()),
        other => Err(format!("job {} ended {other}", j.id)),
    }
}

fn tail(log: &Path, lines: usize) {
    let Ok(text) = std::fs::read_to_string(log) else {
        println!("(log not readable yet: {})", log.display());
        return;
    };
    let all: Vec<&str> = text.lines().collect();
    for l in all.iter().skip(all.len().saturating_sub(lines)) {
        println!("  {l}");
    }
}

/// Print whatever was appended since `from` and return the new offset. A log
/// that shrank (rotated or recreated) restarts from zero rather than seeking
/// past the end and printing nothing forever.
fn drain(log: &Path, from: u64) -> u64 {
    let len = std::fs::metadata(log).map(|m| m.len()).unwrap_or(0);
    let start = if len < from { 0 } else { from };
    let Ok(mut f) = File::open(log) else { return start };
    if f.seek(SeekFrom::Start(start)).is_err() {
        return start;
    }
    let mut buf = String::new();
    if f.read_to_string(&mut buf).is_err() {
        return start;
    }
    for l in buf.lines() {
        println!("  {l}");
    }
    start + buf.len() as u64
}
