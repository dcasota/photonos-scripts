//! sharukhan - permutation-matrix harness for Photon OS ISO/PR verification.
//!
//! Every subcommand here reports only what it actually observed. Where a fact
//! cannot be established it says so rather than guessing, because a harness
//! that reports a confident wrong answer is worse than one that reports none.

mod b64;
mod canister;
mod card;
mod build;
mod config;
mod evidence;
mod guest;
mod install;
mod oracle;
mod serial;
mod sha256;
mod verify;
mod disk;
mod identity;
mod kickstart;
mod job;
mod matrix;
mod media;
mod memory;
mod phases;
mod proc;
mod report;
mod runner;
mod vm;
mod vmware;
mod vmx;
mod winpath;

use std::process::ExitCode;

const USAGE: &str = "\
sharukhan - Photon OS permutation-matrix harness

USAGE:
    sharukhan <COMMAND> [OPTIONS]

INSPECT
    doctor              check the environment before anything is built or run
    plan                show which permutations would run, and which ISOs they need
    status              running VMs, disk headroom, and the parallelism that allows
    findings            findings recorded in the memory database
    report              per-permutation results from the last run of each
    card                what a human must enter for one interactive permutation

DRIVE
    run                 drive permutations end to end, sequentially
    stop                end a recorded job and its process tree
    watch               follow a job, or show every job, VM and free space

PHASES (the same code `run` calls, one step at a time)
    kickstart           print the kickstart JSON for one permutation
    create-vm           disk, VMX and kickstart injection for one permutation
    install             power on and wait for the guest to boot off disk
    verify              run the oracle against an installed guest, harvest logs
    teardown            return one permutation's VM to a fresh-disk state
    build-iso           resolve a build-axis tuple to an ISO (see --allow-build)
    variant-patches     rebuild the installer variant patches from the PR branches
    canister            which canister this kernel can have (--rebase-check to prove it)
    mirrors             are the SPECS copies of POI PR commits still current with the fork?

OPTIONS:
    --id <perm>         one permutation (card, kickstart, create-vm, install,
                        verify, teardown)
    --only <ids>        comma-separated permutation ids (plan, report, run)
    --all               every permutation in the matrix (run); every running job (stop)
    --allow-build       permit an ISO build; OFF by default, because a build takes
                        hours and shares $PHOTON_TREE/stage with everything else
    --iso <path>        ISO to attach (create-vm); default is the row's cached one
    --kickstart <file>  kickstart to inject (create-vm); default is generated
    --recreate          stash the VM directory's contents first (create-vm)
    --mode <m>          auto | interactive (install)
    --no-wait           leave the VM up for an operator and return (install)
    --timeout <sec>     install timeout; default MC_INSTALL_TIMEOUT_SEC
    --ip <addr>         guest address (verify), when the facts file has none
    --purge             delete old stashes as well (teardown)
    --iso-type <t>      minimal | full (build-iso)
    --poi <v>           2.8 | latest (build-iso)
    --canister <c>      prebuilt | build | acvp | kat (build-iso)
    --force             rebuild even on a cache hit (build-iso)
    --severity <level>  filter findings by severity
    --jobs <n>          proposed parallel VM count (status); default is cpus/4
    --job <id>          a job table row id (stop, watch) - NOT --jobs
    --dry-run           run every gate, change nothing (run, stop)
    --keep              do not tear the VM down after verifying (run)
    --settle <sec>      minimum ISO age before the first VM (run); default 300
    --wait-idle <sec>   wait this long for foreign builds/installs (run); default 0
    --log <path>        run log path (run)
    --interval <sec>    poll interval (watch); default 15
    --once              one snapshot instead of following (watch)
    -h, --help          this text

MC_GUEST_PASSWORD is REQUIRED for anything that installs or configures a guest.
It is the root password of every VM this harness creates, so it has no default.
";

struct Args {
    cmd: String,
    id: Option<String>,
    only: Option<String>,
    iso: Option<String>,
    kickstart: Option<String>,
    mode: Option<String>,
    ip: Option<String>,
    iso_type: Option<String>,
    poi: Option<String>,
    canister: Option<String>,
    timeout: Option<u64>,
    allow_build: bool,
    rebase_check: bool,
    recreate: bool,
    no_wait: bool,
    purge: bool,
    force: bool,
    severity: Option<String>,
    jobs: Option<u64>,
    all: bool,
    job: Option<i64>,
    dry_run: bool,
    keep: bool,
    once: bool,
    settle: u64,
    wait_idle: u64,
    interval: u64,
    log: Option<String>,
}

fn parse() -> Result<Args, String> {
    let mut a = std::env::args().skip(1);
    // `sharukhan --help` puts the flag where the command goes; treat it as the
    // command rather than reporting it as an unknown one.
    let cmd = match a.next() {
        Some(c) if c == "-h" || c == "--help" => "help".to_string(),
        Some(c) => c,
        None => "help".to_string(),
    };
    let mut out = Args {
        cmd,
        id: None,
        only: None,
        iso: None,
        kickstart: None,
        mode: None,
        ip: None,
        iso_type: None,
        poi: None,
        canister: None,
        timeout: None,
        allow_build: false,
        rebase_check: false,
        recreate: false,
        no_wait: false,
        purge: false,
        force: false,
        severity: None,
        jobs: None,
        all: false,
        job: None,
        dry_run: false,
        keep: false,
        once: false,
        settle: 300,
        wait_idle: 0,
        interval: 15,
        log: None,
    };
    while let Some(f) = a.next() {
        match f.as_str() {
            "--id" => out.id = Some(a.next().ok_or("--id needs a value")?),
            "--only" => out.only = Some(a.next().ok_or("--only needs a value")?),
            "--iso" => out.iso = Some(a.next().ok_or("--iso needs a value")?),
            "--kickstart" => out.kickstart = Some(a.next().ok_or("--kickstart needs a value")?),
            "--mode" => out.mode = Some(a.next().ok_or("--mode needs a value")?),
            "--ip" => out.ip = Some(a.next().ok_or("--ip needs a value")?),
            "--iso-type" => out.iso_type = Some(a.next().ok_or("--iso-type needs a value")?),
            "--poi" => out.poi = Some(a.next().ok_or("--poi needs a value")?),
            "--canister" => out.canister = Some(a.next().ok_or("--canister needs a value")?),
            "--timeout" => {
                let v = a.next().ok_or("--timeout needs a value")?;
                out.timeout = Some(v.parse().map_err(|_| format!("--timeout: not a number: {v}"))?);
            }
            "--allow-build" => out.allow_build = true,
            "--rebase-check" => out.rebase_check = true,
            "--recreate" => out.recreate = true,
            "--no-wait" => out.no_wait = true,
            "--purge" => out.purge = true,
            "--force" => out.force = true,
            "--severity" => out.severity = Some(a.next().ok_or("--severity needs a value")?),
            "--jobs" => {
                let v = a.next().ok_or("--jobs needs a value")?;
                out.jobs = Some(v.parse().map_err(|_| format!("--jobs: not a number: {v}"))?);
            }
            "--job" => {
                let v = a.next().ok_or("--job needs a value")?;
                out.job = Some(v.parse().map_err(|_| format!("--job: not a number: {v}"))?);
            }
            "--all" => out.all = true,
            "--dry-run" => out.dry_run = true,
            "--keep" => out.keep = true,
            "--once" => out.once = true,
            "--log" => out.log = Some(a.next().ok_or("--log needs a value")?),
            "--settle" => {
                let v = a.next().ok_or("--settle needs a value")?;
                out.settle = v.parse().map_err(|_| format!("--settle: not a number: {v}"))?;
            }
            "--wait-idle" => {
                let v = a.next().ok_or("--wait-idle needs a value")?;
                out.wait_idle = v.parse().map_err(|_| format!("--wait-idle: not a number: {v}"))?;
            }
            "--interval" => {
                let v = a.next().ok_or("--interval needs a value")?;
                out.interval = v.parse().map_err(|_| format!("--interval: not a number: {v}"))?;
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
        "run" => runner::cmd_run(
            &cfg,
            &runner::RunOpts {
                only: args.only.clone(),
                all: args.all,
                dry_run: args.dry_run,
                keep: args.keep,
                settle: args.settle,
                wait_idle: args.wait_idle,
                log: args.log.clone(),
                allow_build: args.allow_build,
            },
        ),
        "card" => need_id(&args).and_then(|id| phases::cmd_card(&cfg, id)),
        "kickstart" => need_id(&args).and_then(|id| phases::cmd_kickstart(&cfg, id)),
        "create-vm" => need_id(&args).and_then(|id| {
            phases::cmd_create_vm(
                &cfg,
                id,
                args.iso.as_deref(),
                args.kickstart.as_deref(),
                args.recreate,
                args.allow_build,
            )
        }),
        "install" => need_id(&args).and_then(|id| {
            phases::cmd_install(&cfg, id, args.mode.as_deref(), args.timeout, args.no_wait)
        }),
        "verify" => need_id(&args).and_then(|id| phases::cmd_verify(&cfg, id, args.ip.as_deref())),
        "teardown" => need_id(&args).and_then(|id| phases::cmd_teardown(&cfg, id, args.purge)),
        "build-iso" => phases::cmd_build_iso(
            &cfg,
            args.iso_type.as_deref().unwrap_or("minimal"),
            args.poi.as_deref().unwrap_or("2.8"),
            args.canister.as_deref().unwrap_or("prebuilt"),
            args.force,
            args.allow_build,
        ),
        "variant-patches" => phases::cmd_variant_patches(&cfg),
        "canister" => cmd_canister(&cfg, args.rebase_check),
        "mirrors" => cmd_mirrors(&cfg),
        "stop" => runner::cmd_stop(&cfg, args.job, args.all, args.dry_run),
        "watch" => runner::cmd_watch(&cfg, args.job, args.once, args.interval),
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

/// A phase command without --id must say so rather than picking a row.
fn need_id(a: &Args) -> Result<&str, String> {
    a.id
        .as_deref()
        .ok_or_else(|| format!("{} needs --id <permutation>", a.cmd))
}

fn mark(ok: bool) -> &'static str {
    if ok { "ok  " } else { "FAIL" }
}

/// doctor answers mc-preflight.sh's question: can this host run the matrix?
///
/// It prints MEASURED values, never a bare OK/FAIL. "tool missing" and "tool
/// present but not executable by this user" need different fixes and are
/// indistinguishable in a boolean.
fn cmd_doctor(cfg: &config::Config) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
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
    // Required, no default: it is the root password of every VM installed.
    match cfg.guest_password() {
        Ok(_) => check("MC_GUEST_PASSWORD", true, "set in the environment".into()),
        Err(e) => check("MC_GUEST_PASSWORD", false, e),
    }

    println!("vmware tooling");
    for tool in [&cfg.vmrun, &cfg.vdiskmanager] {
        let name = tool
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| tool.display().to_string());
        match std::fs::metadata(tool) {
            Err(_) => check(&name, false, format!("not found at {}", tool.display())),
            Ok(md) if md.permissions().mode() & 0o111 == 0 => check(
                &name,
                false,
                format!("present but not executable by this user: {}", tool.display()),
            ),
            Ok(_) => check(&name, true, "executable".into()),
        }
    }
    match vmware::running(&cfg.vmrun) {
        // Never blanket-stop VMs: other VMs on this host may be live CI
        // runners, so the count is reported and nothing is touched.
        Ok(v) => check(
            "VMs already running",
            true,
            format!("{} (this harness only ever touches its own)", v.len()),
        ),
        Err(e) => check("vmrun list", false, e),
    }

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
    for d in [&cfg.iso_cache, &cfg.results_dir] {
        let ok = std::fs::create_dir_all(d).is_ok();
        check(
            &format!("{}", d.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()),
            ok,
            d.display().to_string(),
        );
    }

    println!("iso build tree");
    let head = std::process::Command::new("git")
        .arg("-C")
        .arg(&cfg.photon_tree)
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "not a repo".into());
    check("photon tree HEAD", t, format!("{} ({head})", cfg.photon_tree.display()));
    // What a build actually applies is a PER-VARIANT patch: build_iso stages
    // variant-patches/poi-<variant>.patch into its own scriptdir as
    // photonos-patches/downstream-fixes.patch, because runPh5_normal.sh
    // resolves that name relative to its own directory.
    //
    // So checking the standing /root/photonos-patches/downstream-fixes.patch
    // validates a file no build has read since the variant mechanism landed.
    // It reported a FAIL for a stale Aug-31 copy while both live variant
    // patches applied cleanly - a false alarm on the one check whose whole job
    // is to catch a stale patch. Its companion "build resolves patch" compared
    // cfg.photon_scripts.join("photonos-patches/downstream-fixes.patch")
    // against cfg.downstream_patch, which is the same path, so it could never
    // fail. Between them they proved nothing about the patch a build would use.
    let mut variants: Vec<std::path::PathBuf> = std::fs::read_dir(&cfg.variant_patches)
        .map(|rd| {
            rd.flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.extension().is_some_and(|x| x == "patch")
                        && p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("poi-"))
                })
                .collect()
        })
        .unwrap_or_default();
    variants.sort();
    if variants.is_empty() {
        check(
            "variant patches apply",
            false,
            format!("no poi-*.patch in {}", cfg.variant_patches.display()),
        );
    } else {
        for vp in &variants {
            let name = vp.file_stem().unwrap_or_default().to_string_lossy().to_string();
            let applies = t
                && std::process::Command::new("git")
                    .arg("-C")
                    .arg(&cfg.photon_tree)
                    .args(["apply", "--check"])
                    .arg(vp)
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false);
            check(
                &format!("{name} applies"),
                applies,
                if applies {
                    format!("{} files", build::patched_files(vp))
                } else {
                    "no - regenerate with `sharukhan variant-patches`".into()
                },
            );
        }
    }

    println!("external tools");
    // python3, base64, jq and sshpass are deliberately absent from this list:
    // they were absorbed. ssh is here because it is the instrument, not an
    // implementation detail - see src/guest.rs.
    for tool in ["xorriso", "ssh", "ssh-keygen", "git"] {
        let found = std::env::var("PATH")
            .unwrap_or_default()
            .split(':')
            .map(|d| std::path::Path::new(d).join(tool))
            .find(|p| p.is_file());
        match found {
            Some(p) => check(tool, true, p.display().to_string()),
            None => check(tool, false, "not installed".into()),
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
    let key = cfg.ssh_key();
    check(
        "lab keypair",
        true,
        if key.exists() {
            key.display().to_string()
        } else {
            format!("{} absent - `run` will create it", key.display())
        },
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
        let parts: Vec<&str> = k.split('/').collect();
        let (t, p, c) = (parts[0], parts.get(1).copied().unwrap_or(""), parts.get(2).copied().unwrap_or("prebuilt"));
        let dir = cfg.iso_cache.join(format!("{t}-poi{p}-{c}"));
        let have = dir.join("photon.iso").exists();
        println!("  {:<26} {}", k, if have { "cached" } else { "must be built" });
    }

    let (auto, oper): (Vec<_>, Vec<_>) = sel.iter().partition(|p| !p.needs_operator());
    let blocked: Vec<_> = sel.iter().filter(|p| p.is_unrunnable_here()).collect();
    println!("\npermutations: {} ({} autonomous, {} need an operator)", sel.len(), auto.len(), oper.len());
    if !blocked.is_empty() {
        println!("  {} cannot run on this host ({}): {}",
                 blocked.len(), std::env::consts::ARCH,
                 blocked.iter().map(|p| p.id.as_str()).collect::<Vec<_>>().join(", "));
    }
    println!("  {:<5} {:<8} {:<7} {:<5} {:<6} {:<5} {:<10} {:<14} {}", "ID", "ISO", "POI", "STIG", "FS", "MODE", "VARIANT", "CANISTER", "DOC");
    for p in &sel {
        println!(
            "  {:<5} {:<8} {:<7} {:<5} {:<6} {:<5} {:<10} {:<14} {}",
            p.id, p.iso_type, p.poi, p.stig, p.fs, p.mode, p.variant, p.canister, p.doc
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

/// Prints the report AND keeps a copy.
///
/// mc-run.sh wrote results/reports/report-<stamp>.txt and pointed
/// report-latest.txt at it, so two runs could be diffed. The port printed to
/// stdout and kept nothing, which makes a regression between runs invisible -
/// the whole point of a matrix is comparing today against yesterday.
fn cmd_report(cfg: &config::Config, only: Option<&str>) -> Result<(), String> {
    let all = matrix::load(&cfg.matrix_tsv)?;
    let sel = matrix::select(&all, only)?;
    let mut out = String::new();
    macro_rules! line {
        ($($a:tt)*) => {{ let l = format!($($a)*); println!("{l}"); out.push_str(&l); out.push('\n'); }};
    }
    line!("  {:<5} {:<8} {:<7} {:<5} {:<6} {:<10} {:<8} {:<28} {}", "ID", "ISO", "POI", "STIG", "FS", "DOC", "RESULT", "EVIDENCE", "FAILED CHECKS");
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
                line!(
                    "  {:<5} {:<8} {:<7} {:<5} {:<6} {:<10} {:<8} {:<28} {}",
                    p.id, p.iso_type, p.poi, p.stig, p.fs, p.doc, verdict,
                    if o.stamp.is_empty() { "-" } else { o.stamp.as_str() },
                    o.failed_checks.join(", ")
                );
            }
            None => line!(
                "  {:<5} {:<8} {:<7} {:<5} {:<6} {:<10} {:<8} {:<28} -",
                p.id, p.iso_type, p.poi, p.stig, p.fs, p.doc, "not run", "-"
            ),
        }
    }
    line!("\n{run} of {} permutation(s) have results; {failing} with failing checks", sel.len());

    // Timestamped, so a report never overwrites the one it should be compared
    // against; report-latest.txt is the moving pointer.
    let dir = cfg.results_dir.join("reports");
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("sharukhan: could not create {}: {e}", dir.display());
        return Ok(());
    }
    let stamp = job::stamp();
    let file = dir.join(format!("report-{stamp}.txt"));
    match std::fs::write(&file, &out) {
        Ok(()) => {
            let latest = dir.join("report-latest.txt");
            let _ = std::fs::remove_file(&latest);
            let _ = std::fs::write(&latest, &out);
            println!("\nwritten: {}", file.display());
        }
        Err(e) => eprintln!("sharukhan: could not write {}: {e}", file.display()),
    }
    Ok(())
}

/// `sharukhan canister [--rebase-check]`
///
/// Reports which of the three canister states this kernel is in, and with
/// --rebase-check proves whether a canister could actually be created for it.
///
/// The proof matters because rpm cannot give it: %prep applies at --fuzz=0 and
/// stops at the first rejected hunk, so a build reports "a patch broke" and
/// nothing about how far the series has diverged. Running the whole series and
/// forcing through failures is the difference between an afternoon and a
/// project - and it costs seconds against a build's hours.
fn cmd_canister(cfg: &config::Config, rebase_check: bool) -> Result<(), String> {
    let arch = std::env::consts::ARCH;
    let state = canister::detect(cfg, arch)?;
    println!("state: {}", state.label());
    match &state {
        canister::State::Certified { version } => {
            println!("  an official canister matches this kernel: {version}");
            println!("  this is the only state that carries a CMVP certificate");
        }
        canister::State::Equivalent { kernel, certified } => {
            println!("  kernel under test        {kernel}");
            println!("  certified canister pin   {certified}");
            println!("  no official canister exists at this kernel level, so same-version");
            println!("  coverage needs one built locally: functionally equivalent, NOT validated");
        }
        canister::State::Absent { arch, reason } => {
            println!("  arch {arch}: {reason}");
            println!("  this is a correct outcome, not a failure");
        }
    }
    if !state.is_validated() {
        println!("\nany FIPS verdict taken in this state must be recorded as NOT CMVP validated");
    }
    if !rebase_check {
        if matches!(state, canister::State::Equivalent { .. }) {
            println!("\nrun with --rebase-check to prove the canister series still applies");
        }
        return Ok(());
    }

    // Work on a throwaway copy: the series must be applied cumulatively for
    // later patches to see earlier ones, and that must never touch the tree a
    // build is using.
    let work = std::env::temp_dir().join(format!("sharukhan-rebase-{}", job::stamp()));
    println!("\nrebase-check needs an unpacked kernel tree at {}", work.display());
    println!("(not yet wired to unpack the source tarball - point PHOTON_KERNEL_TREE at one)");
    let tree = match std::env::var("PHOTON_KERNEL_TREE") {
        Ok(t) => std::path::PathBuf::from(t),
        Err(_) => return Err("set PHOTON_KERNEL_TREE to a prepared kernel tree".into()),
    };
    let applied = canister::rebase_check(cfg, &tree)?;
    let (mut ok, mut bad) = (0, 0);
    for a in &applied {
        if a.ok {
            ok += 1;
        } else {
            bad += 1;
            println!("  FAILED  {}", a.name);
            for r in &a.rejects {
                println!("            {r}");
            }
        }
    }
    println!("\n{ok} of {} applied clean at --fuzz=0, {bad} failed", applied.len());
    if bad > 0 {
        println!("rejects are listed above; %prep would have shown you only the first");
    }
    Ok(())
}

/// `sharukhan mirrors`
///
/// Several SPECS/photon-os-installer patches are COPIES of commits on
/// photon-os-installer PR branches. A copy goes stale silently: a reviewer's
/// change lands on the POI branch, the spec keeps the old text, and the matrix
/// then proves the old text - which is indistinguishable from proving the new
/// one. This compares each copy against what the PUBLISHED branch produces.
///
/// Everything comes from remote-tracking refs after a fetch, deliberately: the
/// point is to prove that what is on the fork is what gets built, not whatever
/// a local working tree happens to hold.
fn cmd_mirrors(cfg: &config::Config) -> Result<(), String> {
    let mut stale = 0;
    for variant in build::VARIANTS.iter() {
        let branch = variant
            .branches
            .iter()
            .find(|b| b.contains("photon-os-installer") || b.contains("poi-2.9-bump") || b.contains("poi-fips-sshd"))
            .ok_or_else(|| format!("variant {} has no installer branch", variant.name))?;
        println!("variant {} (installer branch {branch})", variant.name);
        for m in build::verify_mirrors(cfg, branch)? {
            let mark = if m.current { "ok  " } else { "STALE" };
            if !m.current {
                stale += 1;
            }
            println!("  [{mark}] {:<62} {}", m.spec_patch, m.detail);
        }
    }
    if stale > 0 {
        println!("\n{stale} spec patch copy(ies) are behind the fork.");
        println!("Regenerate them before building: a row built from a stale copy proves the old change.");
        return Err("stale mirrors".into());
    }
    println!("\nevery spec copy matches its published photon-os-installer branch");
    Ok(())
}
