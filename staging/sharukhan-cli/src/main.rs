//! sharukhan - permutation-matrix harness for Photon OS ISO/PR verification.
//!
//! Every subcommand here reports only what it actually observed. Where a fact
//! cannot be established it says so rather than guessing, because a harness
//! that reports a confident wrong answer is worse than one that reports none.

mod config;
mod disk;
mod matrix;
mod memory;
mod report;
mod vmware;

use std::process::ExitCode;

const USAGE: &str = "\
sharukhan - Photon OS permutation-matrix harness

USAGE:
    sharukhan <COMMAND> [OPTIONS]

COMMANDS:
    doctor              check the environment before anything is built or run
    plan                show which permutations would run, and which ISOs they need
    status              running VMs, disk headroom, and the parallelism that allows
    findings            findings recorded in the memory database
    report              per-permutation results from the last run of each

OPTIONS:
    --only <ids>        comma-separated permutation ids (plan, report)
    --severity <level>  filter findings by severity
    --jobs <n>          proposed parallel VM count (status); default is cpus/4
    -h, --help          this text
";

struct Args {
    cmd: String,
    only: Option<String>,
    severity: Option<String>,
    jobs: Option<u64>,
}

fn parse() -> Result<Args, String> {
    let mut a = std::env::args().skip(1);
    let cmd = a.next().unwrap_or_else(|| "help".into());
    let mut out = Args { cmd, only: None, severity: None, jobs: None };
    while let Some(f) = a.next() {
        match f.as_str() {
            "--only" => out.only = Some(a.next().ok_or("--only needs a value")?),
            "--severity" => out.severity = Some(a.next().ok_or("--severity needs a value")?),
            "--jobs" => {
                let v = a.next().ok_or("--jobs needs a value")?;
                out.jobs = Some(v.parse().map_err(|_| format!("--jobs: not a number: {v}"))?);
            }
            "-h" | "--help" => out.cmd = "help".into(),
            other => return Err(format!("unknown option: {other}")),
        }
    }
    Ok(out)
}

// Rust ignores SIGPIPE, so `sharukhan findings | head` panics with "failed
// printing to stdout: Broken pipe" instead of exiting quietly. Restore the
// default disposition: piping into head or less is normal use of a CLI.
fn restore_sigpipe() {
    const SIGPIPE: i32 = 13;
    const SIG_DFL: usize = 0;
    extern "C" {
        fn signal(signum: i32, handler: usize) -> usize;
    }
    unsafe {
        signal(SIGPIPE, SIG_DFL);
    }
}

fn main() -> ExitCode {
    restore_sigpipe();
    let args = match parse() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("sharukhan: {e}");
            return ExitCode::from(64);
        }
    };
    let cfg = config::Config::load();
    let r = match args.cmd.as_str() {
        "doctor" => cmd_doctor(&cfg),
        "plan" => cmd_plan(&cfg, args.only.as_deref()),
        "status" => cmd_status(&cfg, args.jobs),
        "findings" => cmd_findings(&cfg, args.severity.as_deref()),
        "report" => cmd_report(&cfg, args.only.as_deref()),
        "help" => {
            print!("{USAGE}");
            Ok(())
        }
        other => Err(format!("unknown command: {other}\n\n{USAGE}")),
    };
    match r {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("sharukhan: {e}");
            ExitCode::FAILURE
        }
    }
}

fn mark(ok: bool) -> &'static str {
    if ok { "ok  " } else { "FAIL" }
}

fn cmd_doctor(cfg: &config::Config) -> Result<(), String> {
    let mut bad = 0;
    let mut check = |label: &str, ok: bool, detail: String| {
        if !ok {
            bad += 1;
        }
        println!("  [{}] {:<22} {}", mark(ok), label, detail);
    };

    println!("environment");
    let t = cfg.photon_tree.exists();
    check("photon tree", t, cfg.photon_tree.display().to_string());
    let m = cfg.matrix_tsv.exists();
    check("matrix", m, cfg.matrix_tsv.display().to_string());
    let v = cfg.vmrun.exists();
    check("vmrun", v, cfg.vmrun.display().to_string());

    println!("capacity");
    for (label, path, need) in [
        ("/ (build stage)", "/", disk::ISO_BUILD.root_gb),
        ("VM store", cfg.vm_root.to_str().unwrap_or("/"), disk::VM_RUN.vmstore_gb),
    ] {
        match disk::space(path) {
            Some(s) => check(
                label,
                s.avail_gb >= need,
                format!("{}G free ({}% used), needs {}G", s.avail_gb, s.use_pct, need),
            ),
            None => check(label, false, format!("cannot read free space on {path}")),
        }
    }

    println!("inputs");
    let vp = cfg.variant_patches.join("poi-2.8.patch").exists();
    check("variant patches", vp, cfg.variant_patches.display().to_string());
    let isos: Vec<String> = std::fs::read_dir(&cfg.iso_cache)
        .map(|d| d.flatten().filter_map(|e| e.file_name().into_string().ok()).collect())
        .unwrap_or_default();
    check(
        "iso cache",
        !isos.is_empty(),
        if isos.is_empty() { "empty - an ISO must be built first".into() } else { isos.join(", ") },
    );

    println!("memory");
    match memory::open(&cfg.memory_db) {
        Ok(c) => check("database", true, format!("{} finding(s)", memory::count(&c, "finding"))),
        Err(e) => check("database", false, e),
    }

    if bad > 0 {
        return Err(format!("{bad} check(s) failed"));
    }
    println!("\nall checks passed");
    Ok(())
}

fn cmd_plan(cfg: &config::Config, only: Option<&str>) -> Result<(), String> {
    let all = matrix::load(&cfg.matrix_tsv)?;
    let sel = matrix::select(&all, only)?;
    let mut isos: Vec<String> = sel.iter().map(|p| p.iso_key()).collect();
    isos.sort();
    isos.dedup();

    println!("ISOs required ({}):", isos.len());
    for k in &isos {
        let (t, p) = k.split_once('/').unwrap_or((k, ""));
        let dir = cfg.iso_cache.join(format!("{t}-poi{p}-prebuilt"));
        let have = dir.join("photon.iso").exists();
        println!("  {:<16} {}", k, if have { "cached" } else { "must be built" });
    }

    let (auto, oper): (Vec<_>, Vec<_>) = sel.iter().partition(|p| !p.needs_operator());
    println!("\npermutations: {} ({} autonomous, {} need an operator)", sel.len(), auto.len(), oper.len());
    println!("  {:<5} {:<8} {:<7} {:<5} {:<6} {:<5} {:<10} {}", "ID", "ISO", "POI", "STIG", "FS", "MODE", "VARIANT", "DOC");
    for p in &sel {
        println!(
            "  {:<5} {:<8} {:<7} {:<5} {:<6} {:<5} {:<10} {}",
            p.id, p.iso_type, p.poi, p.stig, p.fs, p.mode, p.variant, p.doc
        );
    }
    Ok(())
}

fn cmd_status(cfg: &config::Config, jobs: Option<u64>) -> Result<(), String> {
    println!("running VMs");
    match vmware::running(&cfg.vmrun) {
        Ok(v) if v.is_empty() => println!("  (none)"),
        Ok(v) => v.iter().for_each(|l| println!("  {l}")),
        Err(e) => println!("  unavailable: {e}"),
    }

    println!("\ndisk");
    for (label, path) in [("/", "/"), ("VM store", cfg.vm_root.to_str().unwrap_or("/"))] {
        match disk::space(path) {
            Some(s) => println!("  {:<10} {}G free ({}% used)", label, s.avail_gb, s.use_pct),
            None => println!("  {:<10} unreadable", label),
        }
    }

    if let Ok(all) = matrix::load(&cfg.matrix_tsv) {
        let up: Vec<&str> = all
            .iter()
            .filter(|p| vmware::is_running(&cfg.vmrun, &format!("mc-{}", p.id)))
            .map(|p| p.id.as_str())
            .collect();
        if !up.is_empty() {
            println!("\nmatrix VMs up: {}", up.join(", "));
        }
    }

    let vmstore = cfg.vm_root.to_str().unwrap_or("/");
    let (n, why) = disk::max_parallel(vmstore, jobs);
    println!("\nparallel VMs allowed: {n}");
    println!("  {why}");
    match disk::admit(&disk::ISO_BUILD, "/", vmstore) {
        disk::Verdict::Admit => println!("  an ISO build would be admitted"),
        disk::Verdict::Refuse(r) => println!("  an ISO build would be REFUSED: {r}"),
    }
    Ok(())
}

fn cmd_findings(cfg: &config::Config, severity: Option<&str>) -> Result<(), String> {
    let conn = memory::open(&cfg.memory_db)?;
    let f = memory::findings(&conn, severity)?;
    if f.is_empty() {
        println!("no findings{}", severity.map(|s| format!(" with severity {s}")).unwrap_or_default());
        return Ok(());
    }
    println!("{} finding(s)\n", f.len());
    for x in &f {
        let sev = if x.severity.is_empty() { "-".into() } else { x.severity.clone() };
        let st = if x.status.is_empty() { "-".into() } else { x.status.clone() };
        println!("  #{:<3} {:<10} {:<10} {}", x.id, sev, st, x.slug);
        if !x.summary.is_empty() {
            let s: String = x.summary.chars().take(100).collect();
            println!("        {s}");
        }
    }
    Ok(())
}

fn cmd_report(cfg: &config::Config, only: Option<&str>) -> Result<(), String> {
    let all = matrix::load(&cfg.matrix_tsv)?;
    let sel = matrix::select(&all, only)?;
    println!("  {:<5} {:<8} {:<7} {:<5} {:<6} {:<10} {:<8} {:<28} {}", "ID", "ISO", "POI", "STIG", "FS", "DOC", "RESULT", "EVIDENCE", "FAILED CHECKS");
    let (mut run, mut failing) = (0, 0);
    for p in &sel {
        match report::read(&cfg.results_dir, &p.id) {
            Some(o) => {
                run += 1;
                if o.fail > 0 {
                    failing += 1;
                }
                let verdict = if o.fail == 0 {
                    format!("{} pass", o.pass)
                } else {
                    format!("{} FAIL", o.fail)
                };
                println!(
                    "  {:<5} {:<8} {:<7} {:<5} {:<6} {:<10} {:<8} {:<28} {}",
                    p.id, p.iso_type, p.poi, p.stig, p.fs, p.doc, verdict,
                    if o.stamp.is_empty() { "-" } else { o.stamp.as_str() },
                    o.failed_checks.join(", ")
                );
            }
            None => println!(
                "  {:<5} {:<8} {:<7} {:<5} {:<6} {:<10} {:<8} {:<28} -",
                p.id, p.iso_type, p.poi, p.stig, p.fs, p.doc, "not run", "-"
            ),
        }
    }
    println!("\n{run} of {} permutation(s) have results; {failing} with failing checks", sel.len());
    Ok(())
}
