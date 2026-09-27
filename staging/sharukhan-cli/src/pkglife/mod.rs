//! Package lifecycle: for every package the row's own media offers, install
//! it, test it by what it is, remove it, and prove the guest is back where it
//! started. Opt-in (`verify|run --package-lifecycle`); design in ADR-0008,
//! contract in FRD-002.
//!
//! Order of a run:
//!
//! 1. policy (embedded, fingerprinted), guest identity (machine-id)
//! 2. media: VMX names this ISO -> device connected -> guest mounts the
//!    medium carrying the ISO's volume id -> tdnf lists exactly the ISO's RPMs
//! 3. baseline: the guest's package set, failed and active units, the ssh
//!    listener's unit, this boot's journal errors; a baseline file per
//!    machine-id makes a re-run on the same guest reconcile instead of guess
//! 4. controls, each of which disables what it protects when it fails: a
//!    logged error must be found by the journal query; a deliberately failing
//!    unit must be judged failed with its error found; the probe sandbox must
//!    be unprivileged, offline and read-only; a known-good binary must pass
//!    and GNU false (exit 1 even for --version) must fail
//! 5. per package, sorted by name: fresh (install -> verify -> classify ->
//!    libraries, CLIs, units -> journal window -> remove -> residue) or
//!    preinstalled (tested in place, never removed)
//! 6. the guest must end at its baseline; the medium is detached
//!
//! The run is bounded (`--pkg-budget`), resumable on the same guest
//! (`--pkg-resume`), and stops - saying why - the moment the guest can no
//! longer be proven to be at its baseline.

pub mod classify;
pub mod media;
pub mod parse;
pub mod policy;
pub mod probe;
pub mod record;
pub mod remote;
pub mod units;

use crate::config::Config;
use crate::evidence::{Checks, Status};
use crate::guest::Guest;
use crate::matrix::Permutation;
use parse::{FileEntry, JEntry, Pkg, Verify};
use policy::Policy;
use record::{clip, PkgRecord, Step, FAIL, INFO, NOT_REACHED, PASS, SKIP};
use remote::{argv, sq, transport_lost, Remote};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::time::Instant;

pub const MOUNT_POINT: &str = "/run/sharukhan-media";
pub const REPO_ID: &str = "sharukhan-media";
/// Units and journal identifiers the harness itself creates. They are
/// excluded from "what did the package do" comparisons - and only they.
pub const HARNESS_PREFIX: &str = "sharukhan-";

#[derive(Clone, Debug, Default)]
pub struct Opts {
    pub packages: Option<Vec<String>>,
    pub limit: Option<usize>,
    pub budget_secs: u64,
    pub resume: bool,
    pub policy: Option<PathBuf>,
    pub force_unverified: bool,
}

pub const DEFAULT_BUDGET_SECS: u64 = 4 * 3600;

impl Opts {
    /// `--packages a,b,c`: names validated before anything connects.
    pub fn parse_packages(list: &str) -> Result<Vec<String>, String> {
        let v: Vec<String> = list
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .collect();
        if v.is_empty() {
            return Err("--packages needs at least one package name".into());
        }
        if let Some(bad) = v.iter().find(|n| !remote::valid_package_name(n)) {
            return Err(format!("--packages: {bad:?} is not a package name"));
        }
        Ok(v)
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Summary {
    pub pass: usize,
    pub fail: usize,
    pub skip: usize,
    pub not_reached: usize,
    pub carried: usize,
    pub aborted: Option<String>,
}

// ------------------------------------------------------------ pure rules --

/// rpm -V judged: (failures, informational). The rule: a MISSING file, or a
/// size / digest / link-target change (S, 5, L) of a file that is neither
/// %config nor %ghost and lies outside the runtime-state trees, fails. Mode,
/// owner, group and mtime changes, %config changes and anything under
/// /var /run /proc /sys /dev /tmp are recorded, not failed - on a live system
/// those are expected (measured: 210 such lines on a vanilla k09 guest, none
/// of them a defect). Any line that is not a file line (unsatisfied
/// dependencies, %verifyscript output) fails.
pub fn judge_verify(lines: &[Verify]) -> (Vec<String>, Vec<String>) {
    const RUNTIME: [&str; 6] = ["/var/", "/run/", "/proc", "/sys", "/dev/", "/tmp/"];
    let mut fails = Vec::new();
    let mut infos = Vec::new();
    for l in lines {
        match l {
            Verify::Other(s) => fails.push(s.trim().to_string()),
            Verify::File {
                attrs,
                marker,
                path,
            } => {
                let text = format!("{attrs} {marker} {path}");
                if *marker == 'g' {
                    continue;
                }
                let runtime = RUNTIME.iter().any(|r| path.starts_with(r));
                let content = attrs == "missing" || attrs.contains(['S', '5', 'L']);
                if *marker != 'c' && !runtime && content {
                    fails.push(text);
                } else {
                    infos.push(text);
                }
            }
        }
    }
    (fails, infos)
}

/// Journal entries of the window that are errors and not the harness's own.
pub fn window_errors(entries: &[JEntry]) -> Vec<String> {
    entries
        .iter()
        .filter(|e| e.priority <= 3)
        .filter(|e| {
            !e.unit.starts_with(HARNESS_PREFIX) && !e.identifier.starts_with(HARNESS_PREFIX)
        })
        .map(|e| clip(&e.line()))
        .collect()
}

/// Units that the harness's own ssh logins create and remove. They come and
/// go with the ControlMaster connection, so they are not the package's doing.
pub fn session_noise(unit: &str) -> bool {
    unit.starts_with("user@")
        || unit.starts_with("user-runtime-dir@")
        || unit.starts_with("session-")
        || unit.starts_with(HARNESS_PREFIX)
}

/// Processes still running a file from the given set (a removed binary shows
/// as "<path> (deleted)").
pub fn leftover_processes(procs: &[(u32, String)], files: &BTreeSet<String>) -> Vec<String> {
    procs
        .iter()
        .filter(|(_, exe)| files.contains(exe.trim_end_matches(" (deleted)")))
        .map(|(pid, exe)| format!("pid {pid} {exe}"))
        .collect()
}

/// How plain `rpm -qa` prints a package: name-version-release.arch, where a
/// package without an architecture (the gpg-pubkey pseudo-packages) has no
/// `.arch` at all, and the epoch is never shown.
pub fn rpm_qa_default(p: &Pkg) -> String {
    let vr = p.evr.split_once(':').map(|x| x.1).unwrap_or(&p.evr);
    if p.arch == "(none)" || p.arch.is_empty() {
        format!("{}-{vr}", p.name)
    } else {
        format!("{}-{vr}.{}", p.name, p.arch)
    }
}

/// Does verify's harvested `rpm -qa | sort` describe the same package set?
/// The error names the differences, a few from each side.
pub fn harvest_matches(harvest: &str, now: &BTreeMap<String, Pkg>) -> Result<(), String> {
    let hv: BTreeSet<&str> = harvest
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect();
    let ours: BTreeSet<String> = now.values().map(rpm_qa_default).collect();
    let ours: BTreeSet<&str> = ours.iter().map(String::as_str).collect();
    if hv == ours {
        return Ok(());
    }
    let only_h: Vec<&&str> = hv.difference(&ours).take(5).collect();
    let only_now: Vec<&&str> = ours.difference(&hv).take(5).collect();
    Err(format!(
        "harvest {} packages, now {}; only in the harvest: {only_h:?}; only now: {only_now:?}",
        hv.len(),
        ours.len()
    ))
}

/// Which libraries of a package must be in the linker cache: every
/// conventional soname; if the package has none, at least one of its shared
/// objects. Returns (missing, found).
pub fn judge_ldcache(
    c: &classify::Classified,
    cache: &BTreeSet<String>,
) -> (Vec<String>, Vec<String>) {
    let sonames = c.soname_paths();
    let all: Vec<&str> = c.libraries.iter().map(|l| l.path.as_str()).collect();
    let found: Vec<String> = all
        .iter()
        .filter(|p| cache.contains(**p))
        .map(|p| p.to_string())
        .collect();
    let missing: Vec<String> = if sonames.is_empty() {
        if found.is_empty() {
            all.iter().map(|p| p.to_string()).collect()
        } else {
            Vec::new()
        }
    } else {
        sonames
            .iter()
            .filter(|p| !cache.contains(**p))
            .map(|p| p.to_string())
            .collect()
    };
    (missing, found)
}

/// The candidates of this run: every distinct package name on the media,
/// sorted, narrowed by --packages (every name must exist on the media) and
/// --pkg-limit, minus what a resume carries over.
pub fn candidates(
    avail: &[Pkg],
    only: Option<&[String]>,
    limit: Option<usize>,
    done: &BTreeSet<String>,
) -> Result<Vec<Pkg>, String> {
    let mut by_name: BTreeMap<String, Pkg> = BTreeMap::new();
    for p in avail {
        // Several builds of one name: tdnf installs the best, so test that one.
        by_name
            .entry(p.name.clone())
            .and_modify(|cur| {
                if rpm_newer(&p.evr, &cur.evr) {
                    *cur = p.clone();
                }
            })
            .or_insert_with(|| p.clone());
    }
    if let Some(only) = only {
        let missing: Vec<&String> = only.iter().filter(|n| !by_name.contains_key(*n)).collect();
        if !missing.is_empty() {
            return Err(format!(
                "not on the media: {}",
                missing
                    .iter()
                    .map(|s| s.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
        by_name.retain(|k, _| only.contains(k));
    }
    let mut v: Vec<Pkg> = by_name
        .into_values()
        .filter(|p| !done.contains(&p.name))
        .collect();
    if let Some(n) = limit {
        v.truncate(n);
    }
    Ok(v)
}

/// rpmvercmp-style comparison of two EVRs, enough to pick the newest build.
pub fn rpm_newer(a: &str, b: &str) -> bool {
    fn epoch(s: &str) -> (u64, &str) {
        match s.split_once(':') {
            Some((e, r)) if e.chars().all(|c| c.is_ascii_digit()) => (e.parse().unwrap_or(0), r),
            _ => (0, s),
        }
    }
    fn segs(s: &str) -> Vec<String> {
        let mut out = Vec::new();
        let mut cur = String::new();
        let mut digit = None;
        for ch in s.chars() {
            if !ch.is_ascii_alphanumeric() {
                if !cur.is_empty() {
                    out.push(std::mem::take(&mut cur));
                }
                digit = None;
                continue;
            }
            let d = ch.is_ascii_digit();
            if digit.is_some_and(|x| x != d) && !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
            digit = Some(d);
            cur.push(ch);
        }
        if !cur.is_empty() {
            out.push(cur);
        }
        out
    }
    /// rpmvercmp for one field (version, or release).
    fn cmp(a: &str, b: &str) -> std::cmp::Ordering {
        let (sa, sb) = (segs(a), segs(b));
        for (x, y) in sa.iter().zip(sb.iter()) {
            let xd = x.chars().all(|c| c.is_ascii_digit());
            let yd = y.chars().all(|c| c.is_ascii_digit());
            let ord = match (xd, yd) {
                (true, true) => {
                    let (x, y) = (x.trim_start_matches('0'), y.trim_start_matches('0'));
                    x.len().cmp(&y.len()).then(x.cmp(y))
                }
                (true, false) => std::cmp::Ordering::Greater,
                (false, true) => std::cmp::Ordering::Less,
                (false, false) => x.cmp(y),
            };
            if ord != std::cmp::Ordering::Equal {
                return ord;
            }
        }
        sa.len().cmp(&sb.len())
    }
    let ((ea, ra), (eb, rb)) = (epoch(a), epoch(b));
    if ea != eb {
        return ea > eb;
    }
    // Version first, then release: "1.0a-1" is newer than "1.0-2".
    let split = |s: &'_ str| -> (String, String) {
        match s.rsplit_once('-') {
            Some((v, r)) => (v.to_string(), r.to_string()),
            None => (s.to_string(), String::new()),
        }
    };
    let ((va, rla), (vb, rlb)) = (split(ra), split(rb));
    cmp(&va, &vb).then_with(|| cmp(&rla, &rlb)) == std::cmp::Ordering::Greater
}

pub fn nonce() -> String {
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{:x}{:x}", t & 0xffff_ffff_ffff, std::process::id())
}

// ------------------------------------------------------------- session ----

/// What stays constant for one run on one guest.
pub struct Session<'a> {
    pub r: &'a mut dyn Remote,
    pub policy: &'a Policy,
    pub nonce: String,
    pub seq: u64,
    pub baseline: BTreeMap<String, Pkg>,
    pub failed_baseline: BTreeSet<String>,
    pub active_baseline: BTreeSet<String>,
    pub protected_active: BTreeSet<String>,
    pub boot_errors: Vec<JEntry>,
    /// Some(reason) disables CLI probes: their controls did not pass.
    pub cli_disabled: Option<String>,
    /// Set when a unit test lost the ssh session (a firewall that cut it).
    pub lost: Option<String>,
    /// Units named in Conflicts= of the units started for the current
    /// package: stopping them was declared, so restoring them is expected.
    pub declared_conflicts: BTreeSet<String>,
}

const PROC_EXES: &str = "for p in /proc/[0-9]*; do e=$(readlink \"$p/exe\" 2>/dev/null) && \
                         printf '%s %s\\n' \"${p#/proc/}\" \"$e\"; done; true";
const EXISTING: &str = "while IFS= read -r f; do if [ -e \"$f\" ] || [ -L \"$f\" ]; then \
                        printf '%s\\n' \"$f\"; fi; done";

pub enum Flow {
    Continue,
    /// The guest can no longer be proven to be at its baseline, or cannot be
    /// reached: every later verdict would be unattributable.
    Abort(String),
}

impl Session<'_> {
    pub fn tdnf(&self, rest: &[&str]) -> Result<String, String> {
        let repo = format!("--repofrompath={REPO_ID},file://{MOUNT_POINT}/RPMS");
        let enable = format!("--enablerepo={REPO_ID}");
        let mut v = vec![
            "tdnf",
            "-j",
            "--disablerepo=*",
            repo.as_str(),
            enable.as_str(),
            "--nogpgcheck",
            "--noplugins",
        ];
        v.extend_from_slice(rest);
        argv(&v)
    }

    pub fn installed(&mut self) -> Result<BTreeMap<String, Pkg>, String> {
        // rpm expands the \t and \n escapes in a query format itself.
        let cmd = argv(&["rpm", "-qa", "--qf", parse::RPM_QA_QF])?;
        let e = self.r.exec(&cmd, None, self.policy.limits.query_secs);
        if !e.ok() {
            return Err(format!("rpm -qa: exit {:?}: {}", e.code, clip(&e.stderr)));
        }
        parse::rpm_qa(&e.stdout)
    }

    fn unit_set(&mut self, args: &[&str]) -> Result<BTreeSet<String>, String> {
        let mut v = vec!["systemctl", "list-units", "--no-pager", "-o", "json"];
        v.extend_from_slice(args);
        let e = self.r.exec(&argv(&v)?, None, self.policy.limits.query_secs);
        if !e.ok() {
            return Err(format!(
                "systemctl list-units: exit {:?}: {}",
                e.code,
                clip(&e.stderr)
            ));
        }
        Ok(parse::unit_list_json(&e.stdout)?
            .into_iter()
            .filter(|u| !session_noise(u))
            .collect())
    }

    pub fn failed_units(&mut self) -> Result<BTreeSet<String>, String> {
        self.unit_set(&["--failed", "--all"])
    }

    /// Unit files that are enabled: the units the guest means to keep running.
    pub fn enabled_unit_files(&mut self) -> Result<BTreeSet<String>, String> {
        let cmd = argv(&[
            "systemctl",
            "list-unit-files",
            "--state=enabled,enabled-runtime",
            "--no-pager",
            "-o",
            "json",
        ])?;
        let e = self.r.exec(&cmd, None, self.policy.limits.query_secs);
        if !e.ok() {
            return Err(format!(
                "systemctl list-unit-files: exit {:?}: {}",
                e.code,
                clip(&e.stderr)
            ));
        }
        parse::unit_files_json(&e.stdout)
    }

    pub fn active_units(&mut self) -> Result<BTreeSet<String>, String> {
        self.unit_set(&["--state=active", "--type=service,socket,timer,path"])
    }

    fn files_of(&mut self, names: &[&str], from_file: bool) -> Result<Vec<FileEntry>, String> {
        let mut v = vec!["rpm", "-q"];
        if from_file {
            v = vec!["rpm", "-qp", "--nosignature", "--nodigest"];
        }
        v.extend(["--qf", parse::RPM_FILES_QF, "--"]);
        v.extend_from_slice(names);
        let e = self.r.exec(&argv(&v)?, None, self.policy.limits.query_secs);
        if !e.ok() {
            return Err(format!(
                "rpm file list: exit {:?}: {}",
                e.code,
                clip(&e.stderr)
            ));
        }
        parse::rpm_files(&e.stdout)
    }

    fn cursor(&mut self) -> Result<String, String> {
        units::journal_cursor(self.r, self.policy.limits.query_secs)
    }

    // ---- controls -------------------------------------------------------

    /// A line logged at err must come back from the query every journal
    /// verdict relies on.
    pub fn control_journal(&mut self) -> Result<String, String> {
        let cur = self.cursor()?;
        let tag = format!("{HARNESS_PREFIX}control");
        let msg = format!("journal control {}", self.nonce);
        let e = self.r.exec(
            &argv(&["logger", "-p", "user.err", "-t", &tag, "--", &msg])?,
            None,
            self.policy.limits.query_secs,
        );
        if !e.ok() {
            return Err(format!("logger: exit {:?}: {}", e.code, clip(&e.stderr)));
        }
        let t = Instant::now();
        // journald is asynchronous; poll briefly and measure, never assume.
        loop {
            let got =
                units::journal_since(self.r, &cur, None, true, self.policy.limits.query_secs)?;
            if got
                .iter()
                .any(|j| j.identifier == tag && j.message.contains(&msg))
            {
                return Ok(format!(
                    "err-priority line found after the cursor in {} ms",
                    t.elapsed().as_millis()
                ));
            }
            if t.elapsed().as_secs() >= 10 {
                return Err(format!(
                    "logged {msg:?} at err but the query after the cursor did not return it ({} entries)",
                    got.len()
                ));
            }
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
    }

    /// A unit that fails and logs at err must be judged failed and its line
    /// found by the unit-scoped query.
    pub fn control_unit(&mut self) -> Result<String, String> {
        let unit = format!("{HARNESS_PREFIX}control-{}.service", self.nonce);
        let cur = self.cursor()?;
        let script = format!("echo \"<3>unit control {}\"; exit 3", self.nonce);
        let unit_arg = format!("--unit={unit}");
        let cmd = argv(&[
            "systemd-run",
            "--quiet",
            "--wait",
            &unit_arg,
            "-p",
            "Type=oneshot",
            "/bin/sh",
            "-c",
            &script,
        ])?;
        let e = self.r.exec(&cmd, None, self.policy.limits.unit_start_secs);
        let props = units::show(self.r, &unit, self.policy.limits.query_secs)?;
        let verdict = units::judge_start("service", Some(0), e.timed_out, &props);
        let t = Instant::now();
        let mut found = Vec::new();
        while t.elapsed().as_secs() < 10 {
            let entries = units::journal_since(
                self.r,
                &cur,
                Some(&unit),
                false,
                self.policy.limits.query_secs,
            )?;
            found = units::errors(&entries);
            if found.iter().any(|l| l.contains(&self.nonce)) {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
        let _ = self.r.exec(
            &argv(&["systemctl", "reset-failed", "--", &unit])?,
            None,
            self.policy.limits.query_secs,
        );
        match verdict {
            units::Start::Failed(why) if found.iter().any(|l| l.contains(&self.nonce)) => {
                Ok(format!("judged failed ({why}); its err line was found"))
            }
            units::Start::Failed(_) => {
                Err("judged failed, but its err line was not found by the unit query".into())
            }
            other => Err(format!("a unit that exits 3 was judged {other:?}")),
        }
    }

    /// The probe sandbox, then a known-good and a known-bad binary.
    pub fn control_cli(&mut self) -> Result<String, String> {
        self.seq += 1;
        let unit = format!("{HARNESS_PREFIX}probe-{}-{}", self.nonce, self.seq);
        let cmd = probe::sandboxed(
            &unit,
            self.policy.limits.probe_secs,
            "/bin/sh",
            &["-c", probe::SANDBOX_CONTROL_SCRIPT],
        )?;
        let e = self.r.exec(&cmd, None, self.policy.limits.probe_secs + 10);
        let sandbox = probe::judge_sandbox(&e.stdout).map_err(|w| {
            format!(
                "sandbox not in force: {w} (stderr: {})",
                clip(e.stderr.trim())
            )
        })?;
        let prefix = format!("{HARNESS_PREFIX}probe-{}", self.nonce);
        let good = probe::probe(
            self.r,
            self.policy,
            "/usr/bin/rpm",
            "",
            &prefix,
            &mut self.seq,
        );
        if good.status != PASS {
            return Err(format!(
                "known-good /usr/bin/rpm did not pass: {}",
                good.reason
            ));
        }
        let bad = probe::probe(
            self.r,
            self.policy,
            "/usr/bin/false",
            "",
            &prefix,
            &mut self.seq,
        );
        if bad.status != FAIL {
            return Err(format!(
                "known-bad /usr/bin/false (exits 1 even for --version) was judged {}: {}",
                bad.status, bad.reason
            ));
        }
        Ok(format!(
            "{sandbox}; rpm passes ({}), false fails",
            good.reason
        ))
    }

    // ---- one package ----------------------------------------------------

    fn libraries(&mut self, c: &classify::Classified, rec: &mut PkgRecord) {
        if c.libraries.is_empty() {
            return;
        }
        let t = Instant::now();
        let e = self
            .r
            .exec("ldconfig -p", None, self.policy.limits.query_secs);
        if !e.ok() {
            rec.steps.push(Step::new(
                "ldcache",
                FAIL,
                format!("ldconfig -p: exit {:?}", e.code),
                ms(t),
            ));
            return;
        }
        let cache = parse::ldconfig_paths(&e.stdout);
        let (missing, found) = judge_ldcache(c, &cache);
        if missing.is_empty() {
            rec.steps.push(Step::new(
                "ldcache",
                PASS,
                format!(
                    "{} of {} shared object(s) in the linker cache: {}",
                    found.len(),
                    c.libraries.len(),
                    found.join(" ")
                ),
                ms(t),
            ));
        } else {
            rec.steps.push(Step::new(
                "ldcache",
                FAIL,
                format!("not in the linker cache: {}", missing.join(" ")),
                ms(t),
            ));
        }
    }

    fn verify_rpm(&mut self, name: &str, rec: &mut PkgRecord) {
        let t = Instant::now();
        let e = match argv(&["rpm", "-V", "--", name]) {
            Ok(c) => self.r.exec(&c, None, self.policy.limits.query_secs),
            Err(e) => {
                rec.steps.push(Step::new("rpm-verify", FAIL, e, 0));
                return;
            }
        };
        if e.timed_out || e.code.is_none() {
            rec.steps.push(Step::new(
                "rpm-verify",
                FAIL,
                "rpm -V did not finish",
                ms(t),
            ));
            return;
        }
        // rpm -V exits 1 whenever it reports anything; the lines decide.
        let (fails, infos) = judge_verify(&parse::rpm_verify(&format!("{}{}", e.stdout, e.stderr)));
        if fails.is_empty() {
            rec.steps.push(Step::new(
                "rpm-verify",
                PASS,
                if infos.is_empty() {
                    "every file matches the package".to_string()
                } else {
                    format!(
                        "{} expected difference(s): {}",
                        infos.len(),
                        infos.join(" | ")
                    )
                },
                ms(t),
            ));
        } else {
            rec.steps
                .push(Step::new("rpm-verify", FAIL, fails.join(" | "), ms(t)));
        }
    }

    fn clis(&mut self, c: &classify::Classified, version: &str, rec: &mut PkgRecord) {
        if c.executables.is_empty() {
            return;
        }
        if let Some(why) = &self.cli_disabled {
            rec.steps.push(Step::new(
                "cli",
                SKIP,
                format!("CLI probes disabled: {why}"),
                0,
            ));
            return;
        }
        let prefix = format!("{HARNESS_PREFIX}probe-{}", self.nonce);
        for (i, exe) in c.executables.iter().enumerate() {
            if i >= self.policy.limits.max_probes_per_package {
                rec.steps.push(Step::new(
                    "cli",
                    INFO,
                    format!(
                        "{} further executable(s) not probed (limits.max_probes_per_package={})",
                        c.executables.len() - i,
                        self.policy.limits.max_probes_per_package
                    ),
                    0,
                ));
                break;
            }
            // A symlink whose target does not exist is its own finding.
            let exists = argv(&["test", "-x", exe])
                .map(|cmd| self.r.exec(&cmd, None, self.policy.limits.query_secs).ok())
                .unwrap_or(false);
            if !exists {
                rec.clis.push(record::CliResult {
                    path: exe.clone(),
                    status: FAIL.into(),
                    reason: "shipped in a bin directory but not executable (dangling link?)".into(),
                    attempts: Vec::new(),
                });
                continue;
            }
            let r = probe::probe(self.r, self.policy, exe, version, &prefix, &mut self.seq);
            rec.clis.push(r);
        }
    }

    /// A preinstalled package: tested in place, never removed.
    pub fn preinstalled(&mut self, name: &str, rec: &mut PkgRecord) -> Flow {
        rec.origin = "preinstalled".into();
        let cursor = self.cursor().ok();
        self.verify_rpm(name, rec);
        let files = match self.files_of(&[name], false) {
            Ok(f) => f,
            Err(e) => {
                rec.steps.push(Step::new("files", FAIL, e, 0));
                return Flow::Continue;
            }
        };
        let c = classify::classify(&files, |p| self.policy.is_boot_path(p));
        rec.classes = c.classes().iter().map(|s| s.to_string()).collect();
        self.libraries(&c, rec);
        let version = rec.evr.split('-').next().unwrap_or("").to_string();
        self.clis(&c, &version, rec);
        for u in c.units.iter().filter(|u| !u.alias) {
            let res = units::observe(
                self.r,
                &u.name,
                self.policy,
                &self.failed_baseline,
                &self.boot_errors,
            );
            rec.units.push(res);
        }
        if let Some(cur) = cursor {
            self.journal_window(&cur, rec);
        }
        Flow::Continue
    }

    fn journal_window(&mut self, cursor: &str, rec: &mut PkgRecord) {
        let t = Instant::now();
        match units::journal_since(self.r, cursor, None, true, self.policy.limits.query_secs) {
            Ok(entries) => {
                rec.journal_errors = window_errors(&entries);
                if rec.journal_errors.is_empty() {
                    rec.steps.push(Step::new(
                        "journal-window",
                        PASS,
                        "no err-or-worse entry anywhere while this package was tested",
                        ms(t),
                    ));
                } else {
                    rec.steps.push(Step::new(
                        "journal-window",
                        FAIL,
                        format!(
                            "{} err-or-worse entr(ies) while this package was tested: {}",
                            rec.journal_errors.len(),
                            rec.journal_errors.join(" | ")
                        ),
                        ms(t),
                    ));
                }
            }
            Err(e) => rec.steps.push(Step::new("journal-window", FAIL, e, ms(t))),
        }
    }

    /// A package the guest does not have: install, test, remove, prove.
    pub fn fresh(&mut self, pkg: &Pkg, rec: &mut PkgRecord) -> Flow {
        rec.origin = "fresh".into();
        self.declared_conflicts.clear();
        let file = format!(
            "{MOUNT_POINT}/RPMS/{}/{}",
            pkg.arch,
            media::rpm_file_name(&pkg.name, &pkg.evr, &pkg.arch)
        );

        // --- before install: what the package would put where ------------
        let t = Instant::now();
        let header = match self.files_of(&[file.as_str()], true) {
            Ok(f) => f,
            Err(e) => {
                rec.steps
                    .push(Step::new("header", FAIL, format!("{file}: {e}"), ms(t)));
                return Flow::Continue;
            }
        };
        let pre = classify::classify(&header, |p| self.policy.is_boot_path(p));
        rec.classes = pre.classes().iter().map(|s| s.to_string()).collect();
        if let Some(r) = policy::first_match(&self.policy.packages.never_install, &pkg.name) {
            rec.verdict = SKIP.into();
            rec.reason = format!("never installed ({}): {}", r.pattern, r.reason);
            return Flow::Continue;
        }
        if !pre.boot_files.is_empty() {
            rec.verdict = SKIP.into();
            rec.reason = format!(
                "boot-affecting: installs {} under {} - a kernel or boot change on the only boot disk \
                 is not tested on a live guest",
                pre.boot_files.len(),
                self.policy.boot_paths.join(" ")
            );
            rec.steps.push(Step::new(
                "header",
                INFO,
                pre.boot_files
                    .iter()
                    .take(5)
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(" "),
                ms(t),
            ));
            return Flow::Continue;
        }

        // --- the transaction, previewed ------------------------------------
        let t = Instant::now();
        let preview = self
            .tdnf(&["--assumeno", "install", "--", &pkg.name])
            .map(|c| self.r.exec(&c, None, self.policy.limits.install_secs));
        let preview = match preview {
            Ok(e) => e,
            Err(e) => {
                rec.steps.push(Step::new("resolve", FAIL, e, ms(t)));
                return Flow::Continue;
            }
        };
        let txn = match parse::tdnf_txn(&preview.stdout) {
            Ok(t) => t,
            Err(e) => {
                rec.steps.push(Step::new(
                    "resolve",
                    FAIL,
                    format!(
                        "dependency resolution against the media failed: {e}; {}",
                        clip(preview.stderr.trim())
                    ),
                    ms(t),
                ));
                return Flow::Continue;
            }
        };
        let others = txn.other_than(&["Install"]);
        if !others.is_empty() {
            rec.verdict = SKIP.into();
            rec.reason = format!(
                "the transaction would change installed packages ({}); preinstalled packages are never removed or replaced",
                others.join("; ")
            );
            return Flow::Continue;
        }
        let plan: BTreeSet<String> = txn.get("Install").iter().map(Pkg::key).collect();
        if let Some(foreign) = txn.get("Install").iter().find(|p| p.repo != REPO_ID) {
            rec.steps.push(Step::new(
                "resolve",
                FAIL,
                format!(
                    "{} would come from repo {:?}, not the media",
                    foreign.key(),
                    foreign.repo
                ),
                ms(t),
            ));
            return Flow::Continue;
        }
        if !txn.get("Install").iter().any(|p| p.name == pkg.name) {
            rec.steps.push(Step::new(
                "resolve",
                FAIL,
                format!("the transaction does not install {}", pkg.name),
                ms(t),
            ));
            return Flow::Continue;
        }
        rec.steps.push(Step::new(
            "resolve",
            PASS,
            format!(
                "{} package(s): {}",
                plan.len(),
                plan.iter().cloned().collect::<Vec<_>>().join(" ")
            ),
            ms(t),
        ));

        // --- install ---------------------------------------------------------
        let cursor = match self.cursor() {
            Ok(c) => c,
            Err(e) => return Flow::Abort(format!("journal cursor unavailable: {e}")),
        };
        let t = Instant::now();
        let inst = self
            .tdnf(&["-y", "install", "--", &pkg.name])
            .map(|c| self.r.exec(&c, None, self.policy.limits.install_secs))
            .unwrap_or_default();
        if transport_lost(&inst) {
            return Flow::Abort(format!("ssh lost during the install of {}", pkg.name));
        }
        let now = match self.installed() {
            Ok(n) => n,
            Err(e) => return Flow::Abort(e),
        };
        let added: BTreeSet<String> = now
            .keys()
            .filter(|k| !self.baseline.contains_key(*k))
            .cloned()
            .collect();
        let lost: Vec<String> = self
            .baseline
            .keys()
            .filter(|k| !now.contains_key(*k))
            .cloned()
            .collect();
        rec.installed = added.iter().cloned().collect();
        if !lost.is_empty() {
            return Flow::Abort(format!(
                "installing {} removed baseline package(s): {}",
                pkg.name,
                lost.join(" ")
            ));
        }
        if inst.ok() && added == plan {
            rec.steps.push(Step::new(
                "install",
                PASS,
                format!(
                    "{} package(s) added, exactly the previewed set",
                    added.len()
                ),
                ms(t),
            ));
        } else {
            rec.steps.push(Step::new(
                "install",
                FAIL,
                format!(
                    "tdnf exit {:?}; added {:?}, previewed {:?}; {}",
                    inst.code,
                    added,
                    plan,
                    clip(inst.stderr.trim())
                ),
                ms(t),
            ));
        }
        if let Some(p) = now.values().find(|p| p.name == pkg.name) {
            rec.evr = p.evr.clone();
        }

        let unit_names = if now.values().any(|p| p.name == pkg.name) {
            self.test_installed(pkg, rec)
        } else {
            Vec::new()
        };
        if let Some(why) = self.lost.clone() {
            return Flow::Abort(why);
        }
        self.journal_window(&cursor, rec);
        if added.is_empty() {
            return Flow::Continue;
        }

        // --- remove, and prove the baseline is back --------------------------
        let names: Vec<String> = added
            .iter()
            .filter_map(|k| now.get(k).map(|p| p.name.clone()))
            .collect();
        let refs: Vec<&str> = names.iter().map(String::as_str).collect();
        let owned = match self.files_of(&refs, false) {
            Ok(f) => f,
            Err(e) => {
                rec.steps.push(Step::new(
                    "files",
                    FAIL,
                    format!("file lists of the added packages: {e}"),
                    0,
                ));
                Vec::new()
            }
        };
        let files: BTreeSet<String> = owned
            .iter()
            .filter(|e| !e.is_dir() && !e.is_ghost())
            .map(|e| e.path.clone())
            .collect();
        let config: BTreeSet<String> = owned
            .iter()
            .filter(|e| e.is_config())
            .map(|e| e.path.clone())
            .collect();
        if let Flow::Abort(why) = self.remove(&names, &added, rec) {
            return Flow::Abort(why);
        }
        self.residue(&unit_names, &files, &config, rec)
    }

    /// Test an installed package; returns the unit names it ships, for the
    /// residue check after removal.
    fn test_installed(&mut self, pkg: &Pkg, rec: &mut PkgRecord) -> Vec<String> {
        // systemd must see what the package shipped. A package whose
        // scriptlets did not reload it is recorded, then reloaded, so the
        // unit tests exercise the unit files on disk.
        let files = match self.files_of(&[pkg.name.as_str()], false) {
            Ok(f) => f,
            Err(e) => {
                rec.steps.push(Step::new("files", FAIL, e, 0));
                return Vec::new();
            }
        };
        let c = classify::classify(&files, |p| self.policy.is_boot_path(p));
        rec.classes = c.classes().iter().map(|s| s.to_string()).collect();
        let unit_names: Vec<String> = c.units.iter().map(|u| u.name.clone()).collect();
        self.verify_rpm(&pkg.name, rec);
        self.libraries(&c, rec);
        let version = rec.evr.split('-').next().unwrap_or("").to_string();
        self.clis(&c, &version, rec);
        let real: Vec<&classify::UnitFile> = c.units.iter().collect();
        if real.is_empty() {
            return unit_names;
        }
        let t = Instant::now();
        let mut stale = Vec::new();
        for u in &real {
            if let Ok(p) = units::show(self.r, &u.name, self.policy.limits.query_secs) {
                if p.get("NeedDaemonReload").map(String::as_str) == Some("yes") {
                    stale.push(u.name.clone());
                }
            }
        }
        if !stale.is_empty() {
            let e = self.r.exec(
                "systemctl daemon-reload",
                None,
                self.policy.limits.query_secs,
            );
            rec.steps.push(Step::new(
                "daemon-reload",
                INFO,
                format!(
                    "systemd still had the pre-install view of {} after install (the package's scriptlets did not reload it); daemon-reload exit {:?}",
                    stale.join(" "),
                    e.code
                ),
                ms(t),
            ));
        }
        for u in real {
            if let Some(p) = units::plan_static(&u.name, u.alias) {
                rec.units.push(record::UnitResult {
                    unit: u.name.clone(),
                    kind: u.kind().to_string(),
                    plan: p.label(),
                    status: SKIP.into(),
                    outcome: p.label(),
                    ..Default::default()
                });
                continue;
            }
            let props = match units::show(self.r, &u.name, self.policy.limits.query_secs) {
                Ok(p) => p,
                Err(e) => {
                    rec.units.push(record::UnitResult {
                        unit: u.name.clone(),
                        kind: u.kind().to_string(),
                        plan: "unreadable".into(),
                        status: FAIL.into(),
                        outcome: e,
                        ..Default::default()
                    });
                    continue;
                }
            };
            match units::plan(
                &u.name,
                u.alias,
                &props,
                self.policy,
                &self.protected_active,
            ) {
                units::Plan::Cycle { deadman } => {
                    self.declared_conflicts.extend(
                        props
                            .get("Conflicts")
                            .map(|c| c.split_whitespace().map(str::to_string).collect::<Vec<_>>())
                            .unwrap_or_default(),
                    );
                    let nonce = format!("{}-{}", self.nonce, self.seq);
                    self.seq += 1;
                    let mut ctx = units::Ctx {
                        r: self.r,
                        policy: self.policy,
                        nonce: &nonce,
                    };
                    let c = units::cycle(&mut ctx, &u.name, deadman);
                    rec.units.push(c.res);
                    if c.session_lost {
                        self.lost = Some(format!("testing {} lost the ssh session", u.name));
                        return unit_names;
                    }
                }
                p @ units::Plan::Skip(_) => rec.units.push(record::UnitResult {
                    unit: u.name.clone(),
                    kind: u.kind().to_string(),
                    plan: p.label(),
                    status: SKIP.into(),
                    outcome: p.label(),
                    ..Default::default()
                }),
                p @ units::Plan::Fail(_) => rec.units.push(record::UnitResult {
                    unit: u.name.clone(),
                    kind: u.kind().to_string(),
                    plan: p.label(),
                    status: FAIL.into(),
                    outcome: p.label(),
                    ..Default::default()
                }),
            }
        }
        unit_names
    }

    /// Remove exactly what the install added - previewed first, and refused
    /// if the removal would touch anything else.
    fn remove(&mut self, names: &[String], added: &BTreeSet<String>, rec: &mut PkgRecord) -> Flow {
        let refs: Vec<&str> = names.iter().map(String::as_str).collect();
        let t = Instant::now();
        let mut args = vec!["--assumeno", "remove", "--"];
        args.extend_from_slice(&refs);
        let preview = self
            .tdnf(&args)
            .map(|c| self.r.exec(&c, None, self.policy.limits.remove_secs));
        let txn = preview
            .as_ref()
            .map_err(|e| e.clone())
            .and_then(|e| parse::tdnf_txn(&e.stdout));
        match &txn {
            Ok(t2)
                if t2.other_than(&["Remove"]).is_empty()
                    && t2
                        .get("Remove")
                        .iter()
                        .map(Pkg::key)
                        .collect::<BTreeSet<_>>()
                        == *added => {}
            Ok(t2) => {
                return Flow::Abort(format!(
                    "removing what {} added would also change: {} (Remove={:?})",
                    rec.package,
                    t2.other_than(&["Remove"]).join("; "),
                    t2.get("Remove").iter().map(Pkg::key).collect::<Vec<_>>()
                ))
            }
            Err(e) => {
                rec.steps
                    .push(Step::new("remove-preview", FAIL, e.clone(), ms(t)));
            }
        }
        let mut args = vec!["-y", "remove", "--"];
        args.extend_from_slice(&refs);
        let e = self
            .tdnf(&args)
            .map(|c| self.r.exec(&c, None, self.policy.limits.remove_secs))
            .unwrap_or_default();
        if transport_lost(&e) {
            return Flow::Abort(format!("ssh lost while removing {}", rec.package));
        }
        let mut now = match self.installed() {
            Ok(n) => n,
            Err(err) => return Flow::Abort(err),
        };
        let mut left: Vec<String> = now
            .keys()
            .filter(|k| !self.baseline.contains_key(*k))
            .cloned()
            .collect();
        if e.ok() && left.is_empty() {
            rec.steps.push(Step::new(
                "remove",
                PASS,
                format!(
                    "{} package(s) removed; the package set equals the baseline",
                    added.len()
                ),
                ms(t),
            ));
        } else {
            rec.steps.push(Step::new(
                "remove",
                FAIL,
                format!(
                    "tdnf exit {:?}; still installed: {}; {}",
                    e.code,
                    left.join(" "),
                    clip(e.stderr.trim())
                ),
                ms(t),
            ));
            // Only what this run added, by rpm directly, scriptlets first,
            // then without: the guest must get back to its baseline.
            for extra in [&[][..], &["--noscripts"][..]] {
                if left.is_empty() {
                    break;
                }
                let names: Vec<String> = left
                    .iter()
                    .filter_map(|k| now.get(k).map(|p| p.name.clone()))
                    .collect();
                let mut v = vec!["rpm", "-e"];
                v.extend_from_slice(extra);
                v.push("--");
                v.extend(names.iter().map(String::as_str));
                if let Ok(c) = argv(&v) {
                    let r = self.r.exec(&c, None, self.policy.limits.remove_secs);
                    rec.steps.push(Step::new(
                        "remove-fallback",
                        INFO,
                        format!(
                            "{} -> exit {:?} {}",
                            v.join(" "),
                            r.code,
                            clip(r.stderr.trim())
                        ),
                        0,
                    ));
                }
                now = match self.installed() {
                    Ok(n) => n,
                    Err(err) => return Flow::Abort(err),
                };
                left = now
                    .keys()
                    .filter(|k| !self.baseline.contains_key(*k))
                    .cloned()
                    .collect();
            }
        }
        let lost: Vec<String> = self
            .baseline
            .keys()
            .filter(|k| !now.contains_key(*k))
            .cloned()
            .collect();
        if !lost.is_empty() || !left.is_empty() {
            return Flow::Abort(format!(
                "after removing {} the package set is not the baseline: missing {:?}, extra {:?}",
                rec.package, lost, left
            ));
        }
        Flow::Continue
    }

    fn residue(
        &mut self,
        unit_names: &[String],
        files: &BTreeSet<String>,
        config: &BTreeSet<String>,
        rec: &mut PkgRecord,
    ) -> Flow {
        let q = self.policy.limits.query_secs;
        // units gone
        if !unit_names.is_empty() {
            let t = Instant::now();
            let mut loaded = Vec::new();
            for u in unit_names {
                if let Ok(p) = units::show(self.r, u, q) {
                    if p.get("LoadState").map(String::as_str) != Some("not-found") {
                        loaded.push(format!(
                            "{u} LoadState={}",
                            p.get("LoadState").cloned().unwrap_or_default()
                        ));
                    }
                }
            }
            let mut reloaded = false;
            if !loaded.is_empty() {
                let _ = self.r.exec("systemctl daemon-reload", None, q);
                reloaded = true;
                loaded.retain(|l| {
                    let u = l.split(' ').next().unwrap_or("");
                    units::show(self.r, u, q)
                        .map(|p| p.get("LoadState").map(String::as_str) != Some("not-found"))
                        .unwrap_or(true)
                });
            }
            if loaded.is_empty() {
                rec.steps.push(Step::new(
                    "units-gone",
                    PASS,
                    format!(
                        "{} unit(s) no longer known to systemd{}",
                        unit_names.len(),
                        if reloaded {
                            " (only after a daemon-reload the package did not do)"
                        } else {
                            ""
                        }
                    ),
                    ms(t),
                ));
            } else {
                rec.steps.push(Step::new(
                    "units-gone",
                    FAIL,
                    format!(
                        "still loaded after removal and daemon-reload: {}",
                        loaded.join(" ")
                    ),
                    ms(t),
                ));
            }
        }
        // files gone
        if !files.is_empty() {
            let t = Instant::now();
            let list: String = files.iter().map(|f| format!("{f}\n")).collect();
            let e = self.r.exec(EXISTING, Some(list.as_bytes()), q);
            if !e.ok() {
                rec.steps.push(Step::new(
                    "files-gone",
                    FAIL,
                    format!("existence check: exit {:?}", e.code),
                    ms(t),
                ));
            } else {
                let left: Vec<&str> = e.stdout.lines().collect();
                let (cfg_left, other): (Vec<&str>, Vec<&str>) =
                    left.iter().partition(|p| config.contains(**p));
                if other.is_empty() {
                    rec.steps.push(Step::new(
                        "files-gone",
                        PASS,
                        format!(
                            "none of {} packaged file(s) remain{}",
                            files.len(),
                            if cfg_left.is_empty() {
                                String::new()
                            } else {
                                format!("; kept %config: {}", cfg_left.join(" "))
                            }
                        ),
                        ms(t),
                    ));
                } else {
                    rec.steps.push(Step::new(
                        "files-gone",
                        FAIL,
                        format!("left behind: {}", other.join(" ")),
                        ms(t),
                    ));
                }
            }
        }
        // processes gone
        let t = Instant::now();
        let e = self.r.exec(PROC_EXES, None, q);
        let left = leftover_processes(&parse::exe_list(&e.stdout), files);
        if left.is_empty() {
            rec.steps.push(Step::new(
                "processes-gone",
                PASS,
                "no process runs a file of the removed packages",
                ms(t),
            ));
        } else {
            rec.steps
                .push(Step::new("processes-gone", FAIL, left.join(" | "), ms(t)));
        }
        // failed units: none new; clear what this package left so the next
        // package starts from the baseline
        let t = Instant::now();
        match self.failed_units() {
            Ok(now) => {
                let new: Vec<String> = now.difference(&self.failed_baseline).cloned().collect();
                if new.is_empty() {
                    rec.steps.push(Step::new(
                        "failed-units",
                        PASS,
                        format!("{} failed unit(s), as at baseline", now.len()),
                        ms(t),
                    ));
                } else {
                    rec.steps.push(Step::new(
                        "failed-units",
                        FAIL,
                        format!("newly failed: {}", new.join(" ")),
                        ms(t),
                    ));
                    for u in &new {
                        if let Ok(c) = argv(&["systemctl", "reset-failed", "--", u]) {
                            let _ = self.r.exec(&c, None, q);
                        }
                    }
                }
            }
            Err(e) => rec.steps.push(Step::new("failed-units", FAIL, e, ms(t))),
        }
        // baseline units still active; restart what the package stopped
        let t = Instant::now();
        match self.active_units() {
            Ok(now) => {
                let gone: Vec<String> = self.active_baseline.difference(&now).cloned().collect();
                if gone.is_empty() {
                    rec.steps.push(Step::new(
                        "baseline-units",
                        PASS,
                        format!(
                            "all {} baseline unit(s) still active",
                            self.active_baseline.len()
                        ),
                        ms(t),
                    ));
                } else {
                    for u in &gone {
                        if let Ok(c) = argv(&["systemctl", "start", "--", u]) {
                            let _ = self.r.exec(&c, None, self.policy.limits.unit_start_secs);
                        }
                    }
                    let again = self.active_units().unwrap_or_default();
                    let still: Vec<String> = gone
                        .iter()
                        .filter(|u| !again.contains(*u))
                        .cloned()
                        .collect();
                    // A stop the unit under test DECLARED (Conflicts=) is how
                    // systemd is meant to behave; an undeclared one is not.
                    let undeclared: Vec<&String> = gone
                        .iter()
                        .filter(|u| !self.declared_conflicts.contains(*u))
                        .collect();
                    rec.steps.push(Step::new(
                        "baseline-units",
                        if undeclared.is_empty() && still.is_empty() {
                            INFO
                        } else {
                            FAIL
                        },
                        format!(
                            "{} {}; restarted: {}",
                            if undeclared.is_empty() {
                                "stopped through a declared Conflicts= of a unit under test:"
                            } else {
                                "stopped by this package without a declared Conflicts=:"
                            },
                            gone.join(" "),
                            if still.is_empty() {
                                "all".to_string()
                            } else {
                                format!("NOT {}", still.join(" "))
                            }
                        ),
                        ms(t),
                    ));
                    if !still.is_empty() {
                        return Flow::Abort(format!(
                            "baseline unit(s) {} could not be restarted after {}",
                            still.join(" "),
                            rec.package
                        ));
                    }
                }
            }
            Err(e) => rec.steps.push(Step::new("baseline-units", FAIL, e, ms(t))),
        }
        Flow::Continue
    }
}

fn ms(t: Instant) -> u64 {
    t.elapsed().as_millis() as u64
}

// ------------------------------------------------------------- the run ----

/// Everything the orchestration needs from the host side.
pub struct Target<'a> {
    pub cfg: &'a Config,
    pub perm: &'a Permutation,
    pub iso: &'a Path,
    pub ip: &'a str,
    pub stamp: &'a str,
}

/// Entry from `verify`: `c` is the checks file the verify run is writing.
pub fn run(
    t: &Target,
    c: &mut Checks,
    verify_failures: usize,
    o: &Opts,
    log: &mut dyn FnMut(&str),
) -> Result<Summary, String> {
    let policy = match Policy::load(o.policy.as_deref()) {
        Ok(p) => p,
        Err(e) => {
            c.check("pkg.policy", "-", Status::Fail, "valid", "invalid", &e);
            return Err(e);
        }
    };
    c.check(
        "pkg.policy",
        "-",
        Status::Info,
        "",
        &policy.sha256,
        &format!(
            "{} (reviewed {})",
            o.policy
                .as_ref()
                .map(|p| p.display().to_string())
                .unwrap_or_else(|| "embedded schema/package-lifecycle-policy.json".into()),
            policy.reviewed
        ),
    );
    if verify_failures > 0 && !o.force_unverified {
        let why = format!(
            "verify recorded {verify_failures} failing check(s); package verdicts on a guest that is not \
             known-good are unattributable. Fix the row, or pass --pkg-force-unverified"
        );
        c.check(
            "pkg.precondition",
            "-",
            Status::Skip,
            "verify clean",
            &format!("{verify_failures} fail"),
            &why,
        );
        log(&why);
        return Ok(Summary {
            aborted: Some(why),
            ..Default::default()
        });
    }

    // One private directory for the ssh control socket.
    let ctl_dir = std::env::temp_dir().join(format!("sharukhan-ssh-{}", nonce()));
    std::fs::create_dir(&ctl_dir).map_err(|e| format!("{}: {e}", ctl_dir.display()))?;
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&ctl_dir, std::fs::Permissions::from_mode(0o700))
            .map_err(|e| format!("{}: {e}", ctl_dir.display()))?;
    }
    let mut g = Guest::new(&t.cfg.ssh_user, t.ip, &t.cfg.ssh_key(), 10);
    g.control = Some(ctl_dir.join("cm"));
    let result = {
        let mut r = remote::GuestRemote { guest: &g };
        run_on(t, &mut r, &policy, c, o, log)
    };
    g.close_control();
    let _ = std::fs::remove_file(ctl_dir.join("cm"));
    let _ = std::fs::remove_dir(&ctl_dir);
    result
}

fn attach_media(
    t: &Target,
    r: &mut dyn Remote,
    c: &mut Checks,
    log: &mut dyn FnMut(&str),
) -> Result<String, String> {
    let vol = media::volume_id(t.iso)?;
    if !media::valid_volume_id(&vol) {
        return Err(format!(
            "ISO volume id {vol:?} is not an ISO 9660 identifier"
        ));
    }
    let vmx = t.cfg.vmx_path(&t.perm.id);
    let text = std::fs::read_to_string(&vmx).map_err(|e| format!("{}: {e}", vmx.display()))?;
    let named = media::vmx_iso(&text)
        .ok_or_else(|| format!("{} has no {}.fileName", vmx.display(), media::CDROM_DEVICE))?;
    let real = std::fs::canonicalize(t.iso).map_err(|e| format!("{}: {e}", t.iso.display()))?;
    let want =
        crate::winpath::win_path_checked(&real.to_string_lossy()).map_err(|e| format!("{e:?}"))?;
    if !media::same_windows_path(&named, &want) {
        return Err(format!(
            "the VM's {} holds {named}, not this row's ISO {want}; refusing to test packages from another medium",
            media::CDROM_DEVICE
        ));
    }
    let q = 60;
    let find = format!(
        "blkid -t TYPE=iso9660 -o device 2>/dev/null | while read -r d; do [ \"$(blkid -s LABEL -o value \"$d\")\" = {} ] && echo \"$d\"; done; true",
        sq(&vol)?
    );
    let mounted = r.exec(
        &argv(&["findmnt", "-n", "-o", "SOURCE", "--mountpoint", MOUNT_POINT])?,
        None,
        q,
    );
    let device;
    if mounted.ok() && !mounted.stdout.trim().is_empty() {
        device = mounted.stdout.trim().to_string();
        let lab = r.exec(
            &argv(&["blkid", "-s", "LABEL", "-o", "value", &device])?,
            None,
            q,
        );
        if lab.stdout.trim() != vol {
            return Err(format!(
                "{MOUNT_POINT} is mounted from {device} labelled {:?}, not {vol}",
                lab.stdout.trim()
            ));
        }
    } else {
        let mut dev = r
            .exec(&find, None, q)
            .stdout
            .trim()
            .lines()
            .next()
            .unwrap_or("")
            .to_string();
        if dev.is_empty() {
            let vmx_win = crate::winpath::win_path_checked(&vmx.to_string_lossy())
                .map_err(|e| format!("{e:?}"))?;
            let (rc, said) = media::named_device(&t.cfg.vmrun, &vmx_win, true);
            log(&format!(
                "vmrun connectNamedDevice {}: rc={rc:?} {said}",
                media::CDROM_DEVICE
            ));
            let t0 = Instant::now();
            while dev.is_empty() && t0.elapsed().as_secs() < 60 {
                std::thread::sleep(std::time::Duration::from_secs(2));
                dev = r
                    .exec(&find, None, q)
                    .stdout
                    .trim()
                    .lines()
                    .next()
                    .unwrap_or("")
                    .to_string();
            }
            if dev.is_empty() {
                return Err(format!(
                    "no iso9660 device labelled {vol} appeared in the guest within 60 s of connecting {} (vmrun rc={rc:?}: {said})",
                    media::CDROM_DEVICE
                ));
            }
        }
        let m = r.exec(
            &format!(
                "mkdir -p {mp} && mount -o ro,nodev,nosuid,noexec -t iso9660 {} {mp}",
                sq(&dev)?,
                mp = sq(MOUNT_POINT)?
            ),
            None,
            q,
        );
        if !m.ok() {
            return Err(format!(
                "mount {dev}: exit {:?}: {}",
                m.code,
                clip(m.stderr.trim())
            ));
        }
        device = dev;
    }
    let repomd = r.exec(
        &argv(&[
            "test",
            "-f",
            &format!("{MOUNT_POINT}/RPMS/repodata/repomd.xml"),
        ])?,
        None,
        q,
    );
    if !repomd.ok() {
        return Err(format!(
            "{MOUNT_POINT}/RPMS/repodata/repomd.xml is missing: the medium carries no repository"
        ));
    }
    c.check(
        "pkg.media_attached",
        "-",
        Status::Pass,
        &vol,
        &vol,
        &format!("{device} mounted read-only at {MOUNT_POINT}; the VMX names {named}"),
    );
    Ok(vol)
}

fn detach_media(t: &Target, r: &mut dyn Remote, c: &mut Checks) {
    let u = r.exec(
        &format!("umount {}", sq(MOUNT_POINT).unwrap_or_default()),
        None,
        60,
    );
    let vmx = t.cfg.vmx_path(&t.perm.id);
    let (rc, said) = match crate::winpath::win_path_checked(&vmx.to_string_lossy()) {
        Ok(w) => media::named_device(&t.cfg.vmrun, &w, false),
        Err(e) => (None, format!("{e:?}")),
    };
    c.check(
        "pkg.media_detached",
        "-",
        Status::Info,
        "",
        &format!("umount exit {:?}; disconnect rc {rc:?}", u.code),
        &clip(&said),
    );
}

fn run_on(
    t: &Target,
    r: &mut dyn Remote,
    policy: &Policy,
    c: &mut Checks,
    o: &Opts,
    log: &mut dyn FnMut(&str),
) -> Result<Summary, String> {
    let started = Instant::now();
    let q = policy.limits.query_secs;
    let secret = t.cfg.guest_password().ok().map(str::to_string);

    // --- guest identity ------------------------------------------------------
    let mid = r
        .exec("cat /etc/machine-id", None, q)
        .stdout
        .trim()
        .to_string();
    if mid.len() != 32 || !mid.chars().all(|ch| ch.is_ascii_hexdigit()) {
        c.check(
            "pkg.guest",
            "-",
            Status::Fail,
            "machine-id",
            &mid,
            "no usable /etc/machine-id; resumable state cannot be keyed",
        );
        return Err(format!("guest machine-id unreadable: {mid:?}"));
    }
    let state = r
        .exec("systemctl is-system-running", None, q)
        .stdout
        .trim()
        .to_string();
    c.check(
        "pkg.guest",
        "-",
        Status::Info,
        "",
        &mid,
        &format!("machine-id; system state {state}"),
    );

    // --- media ---------------------------------------------------------------
    if let Err(e) = attach_media(t, r, c, log) {
        c.check(
            "pkg.media_attached",
            "-",
            Status::Fail,
            "the row's ISO mounted",
            "not attached",
            &e,
        );
        return Err(e);
    }
    // The host's own reading of the ISO: what the guest's repository must
    // match file for file.
    let media_files: BTreeSet<String> = crate::oracle::media_rpms(t.iso).into_iter().collect();
    let result = run_attached(
        t,
        r,
        policy,
        c,
        o,
        log,
        &mid,
        secret.as_deref(),
        started,
        &media_files,
    );
    detach_media(t, r, c);
    result
}

#[allow(clippy::too_many_arguments)]
fn run_attached(
    t: &Target,
    r: &mut dyn Remote,
    policy: &Policy,
    c: &mut Checks,
    o: &Opts,
    log: &mut dyn FnMut(&str),
    machine_id: &str,
    secret: Option<&str>,
    started: Instant,
    files: &BTreeSet<String>,
) -> Result<Summary, String> {
    let q = policy.limits.query_secs;
    let mut s = Session {
        r,
        policy,
        nonce: nonce(),
        seq: 0,
        baseline: BTreeMap::new(),
        failed_baseline: BTreeSet::new(),
        active_baseline: BTreeSet::new(),
        protected_active: BTreeSet::new(),
        boot_errors: Vec::new(),
        cli_disabled: None,
        lost: None,
        declared_conflicts: BTreeSet::new(),
    };

    // --- the repository is the media ------------------------------------------
    let listing = s.tdnf(&["repoquery", "--available"])?;
    let e = s.r.exec(&listing, None, policy.limits.install_secs);
    let avail = match parse::tdnf_list(&e.stdout) {
        Ok(v) => v,
        Err(err) => {
            let why = format!("{err}; stderr: {}", clip(e.stderr.trim()));
            c.check(
                "pkg.repo_is_media",
                "-",
                Status::Fail,
                "listing",
                "none",
                &why,
            );
            return Err(why);
        }
    };
    let listed: BTreeSet<String> = avail
        .iter()
        .map(|p| media::rpm_file_name(&p.name, &p.evr, &p.arch))
        .collect();
    let foreign: Vec<&Pkg> = avail.iter().filter(|p| p.repo != REPO_ID).collect();
    let unmatched: Vec<&String> = listed.symmetric_difference(files).collect();
    if files.is_empty() || !unmatched.is_empty() || !foreign.is_empty() {
        let why = format!(
            "tdnf lists {} package(s), the ISO holds {} RPM file(s); {} differ (e.g. {:?}); {} from other repos",
            listed.len(),
            files.len(),
            unmatched.len(),
            unmatched.iter().take(5).collect::<Vec<_>>(),
            foreign.len()
        );
        c.check(
            "pkg.repo_is_media",
            "-",
            Status::Fail,
            &files.len().to_string(),
            &listed.len().to_string(),
            &why,
        );
        return Err(why);
    }
    c.check(
        "pkg.repo_is_media",
        "-",
        Status::Pass,
        &files.len().to_string(),
        &listed.len().to_string(),
        "control: every package tdnf offers is an RPM file on this ISO and vice versa",
    );
    c.check(
        "pkg.gpgcheck",
        "-",
        Status::Info,
        "",
        "--nogpgcheck",
        "locally built media RPMs carry no signature (rpm -qpi: Signature (none)); the medium's identity is \
         proven by the VMX path, volume id and the file-for-file listing above instead",
    );

    // --- baseline ----------------------------------------------------------------
    let now = s.installed()?;
    let base_file = t
        .cfg
        .results_dir
        .join(&t.perm.id)
        .join(format!("pkglife-baseline-{machine_id}.txt"));
    let baseline: BTreeMap<String, Pkg> = if base_file.is_file() {
        let text = std::fs::read_to_string(&base_file)
            .map_err(|e| format!("{}: {e}", base_file.display()))?;
        let keys: BTreeSet<String> = text
            .lines()
            .filter(|l| !l.is_empty())
            .map(parse::strip_epoch_key)
            .collect();
        let lost: Vec<&String> = keys.iter().filter(|k| !now.contains_key(*k)).collect();
        if !lost.is_empty() {
            let why = format!(
                "the guest lost {} baseline package(s) since {} was written (e.g. {:?}); reinstall the row",
                lost.len(),
                base_file.display(),
                lost.iter().take(5).collect::<Vec<_>>()
            );
            c.check(
                "pkg.baseline",
                "-",
                Status::Fail,
                "baseline intact",
                "lost packages",
                &why,
            );
            return Err(why);
        }
        let extra: Vec<String> = now.keys().filter(|k| !keys.contains(*k)).cloned().collect();
        let base: BTreeMap<String, Pkg> = now
            .iter()
            .filter(|(k, _)| keys.contains(*k))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        if !extra.is_empty() {
            // An interrupted run left packages behind: remove exactly those.
            s.baseline = base.clone();
            let names: Vec<String> = extra
                .iter()
                .filter_map(|k| now.get(k).map(|p| p.name.clone()))
                .collect();
            let added: BTreeSet<String> = extra.iter().cloned().collect();
            let mut scratch = PkgRecord {
                package: "(reconcile)".into(),
                ..Default::default()
            };
            if let Flow::Abort(why) = s.remove(&names, &added, &mut scratch) {
                c.check(
                    "pkg.baseline",
                    "-",
                    Status::Fail,
                    "reconciled",
                    "not reconciled",
                    &why,
                );
                return Err(why);
            }
            c.check(
                "pkg.baseline",
                "-",
                Status::Info,
                "",
                &format!("{} packages", base.len()),
                &format!(
                    "reconciled with {}: removed {} left over by an interrupted run: {}",
                    base_file.display(),
                    extra.len(),
                    extra.join(" ")
                ),
            );
        } else {
            c.check(
                "pkg.baseline",
                "-",
                Status::Pass,
                &keys.len().to_string(),
                &now.len().to_string(),
                &format!("the guest is at the baseline in {}", base_file.display()),
            );
        }
        base
    } else {
        // First run on this guest: the baseline is what is installed now, and
        // it must agree with what verify harvested from the same guest.
        let harvest = t
            .cfg
            .results_dir
            .join(&t.perm.id)
            .join(format!("logs-{}", t.stamp))
            .join("rpm-qa.txt");
        let harvested = std::fs::read_to_string(&harvest).ok();
        if let Some(h) = &harvested {
            if let Err(diff) = harvest_matches(h, &now) {
                let why = format!(
                    "the package set changed between the verify harvest and now ({diff}); \
                     the guest is not the one verify saw"
                );
                c.check(
                    "pkg.baseline",
                    "-",
                    Status::Fail,
                    "harvest == now",
                    "differs",
                    &why,
                );
                return Err(why);
            }
        }
        let text: String = now.keys().map(|k| format!("{k}\n")).collect();
        std::fs::write(&base_file, text).map_err(|e| format!("{}: {e}", base_file.display()))?;
        c.check(
            "pkg.baseline",
            "-",
            Status::Info,
            "",
            &format!("{} packages", now.len()),
            &format!(
                "first run on this guest; written to {} ({})",
                base_file.display(),
                if harvested.is_some() {
                    "matches the verify harvest of this run"
                } else {
                    "no verify harvest of this run to compare with"
                }
            ),
        );
        now
    };
    s.baseline = baseline;
    s.failed_baseline = s.failed_units()?;
    // Only units the guest means to keep running are held to "still active
    // afterwards": enabled ones, plus the protected ones. A bus-activated
    // service that exits when idle (systemd-timedated, measured on k09) going
    // inactive is not something a package did.
    let enabled = s.enabled_unit_files()?;
    let active = s.active_units()?;
    s.active_baseline = active
        .iter()
        .filter(|u| {
            enabled.contains(*u) || policy::first_match(&policy.units.protected, u).is_some()
        })
        .cloned()
        .collect();
    match units::ssh_listener_unit(s.r, q) {
        Ok(u) => {
            s.protected_active.insert(u.clone());
            c.check(
                "pkg.ssh_unit",
                "-",
                Status::Info,
                "",
                &u,
                "derived from the port 22 listener's cgroup; never stopped or conflicted",
            );
        }
        Err(e) => c.check(
            "pkg.ssh_unit",
            "-",
            Status::Info,
            "",
            "not derived",
            &format!("{e}; the policy's protected list still applies"),
        ),
    }
    for u in &s.active_baseline {
        if policy::first_match(&policy.units.protected, u).is_some() {
            s.protected_active.insert(u.clone());
        }
    }
    let boot_cmd = argv(&["journalctl", "-b", "-p", "0..3", "-o", "json", "--no-pager"])?;
    let be = s.r.exec(&boot_cmd, None, q);
    s.boot_errors = match parse::journal_json(&be.stdout) {
        Ok(v) if be.ok() => v,
        Ok(_) | Err(_) => {
            let why = format!("this boot's journal errors are unreadable (exit {:?}); preinstalled units cannot be judged", be.code);
            c.check(
                "pkg.boot_journal",
                "-",
                Status::Fail,
                "readable",
                "unreadable",
                &why,
            );
            return Err(why);
        }
    };
    c.check(
        "pkg.boot_journal",
        "-",
        Status::Info,
        "",
        &s.boot_errors.len().to_string(),
        "err-or-worse entries this boot before the run; preinstalled units are judged against these only",
    );

    // --- controls -----------------------------------------------------------------
    match s.control_journal() {
        Ok(m) => c.check(
            "pkg.control.journal",
            "-",
            Status::Pass,
            "found",
            "found",
            &m,
        ),
        Err(e) => {
            c.check(
                "pkg.control.journal",
                "-",
                Status::Fail,
                "found",
                "not found",
                &e,
            );
            return Err(format!(
                "journal control failed, every journal verdict would be vacuous: {e}"
            ));
        }
    }
    match s.control_unit() {
        Ok(m) => c.check(
            "pkg.control.unit_failure",
            "-",
            Status::Pass,
            "failed",
            "failed",
            &m,
        ),
        Err(e) => {
            c.check(
                "pkg.control.unit_failure",
                "-",
                Status::Fail,
                "failed",
                "not judged failed",
                &e,
            );
            return Err(format!(
                "unit control failed, every daemon verdict would be vacuous: {e}"
            ));
        }
    }
    match s.control_cli() {
        Ok(m) => c.check(
            "pkg.control.cli",
            "-",
            Status::Pass,
            "sandboxed; good passes, bad fails",
            "as expected",
            &m,
        ),
        Err(e) => {
            c.check(
                "pkg.control.cli",
                "-",
                Status::Fail,
                "sandboxed; good passes, bad fails",
                "not",
                &e,
            );
            s.cli_disabled = Some(e);
        }
    }

    // --- candidates -------------------------------------------------------------------
    let mut carried: Vec<PkgRecord> = Vec::new();
    if o.resume {
        let latest = t
            .cfg
            .results_dir
            .join(&t.perm.id)
            .join("pkglife-latest.jsonl");
        if latest.exists() {
            let prev = record::read(&latest)?;
            let from = std::fs::canonicalize(&latest)
                .ok()
                .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
                .unwrap_or_default();
            carried = record::carry(prev, machine_id, &policy.sha256);
            for r in carried.iter_mut() {
                r.carried_from.get_or_insert(from.clone());
            }
        }
    }
    let done: BTreeSet<String> = carried.iter().map(|r| r.package.clone()).collect();
    let cands = candidates(&avail, o.packages.as_deref(), o.limit, &done)?;
    let mut w = record::Writer::create(&t.cfg.results_dir, &t.perm.id, t.stamp)?;
    let mut sum = Summary {
        carried: carried.len(),
        ..Default::default()
    };
    for mut r in carried {
        r.stamp = t.stamp.to_string();
        w.write(&r)?;
        tally(&mut sum, &r.verdict);
    }
    log(&format!(
        "package lifecycle: {} candidate(s), {} carried over, budget {}s",
        cands.len(),
        sum.carried,
        o.budget_secs
    ));

    let names_installed: BTreeSet<String> = s.baseline.values().map(|p| p.name.clone()).collect();
    for (i, pkg) in cands.iter().enumerate() {
        let mut rec = PkgRecord {
            perm: t.perm.id.clone(),
            stamp: t.stamp.to_string(),
            machine_id: machine_id.to_string(),
            policy_sha256: policy.sha256.clone(),
            package: pkg.name.clone(),
            evr: pkg.evr.clone(),
            arch: pkg.arch.clone(),
            ..Default::default()
        };
        if let Some(why) = &sum.aborted {
            rec.verdict = NOT_REACHED.into();
            rec.reason = why.clone();
            w.write(&rec)?;
            sum.not_reached += 1;
            continue;
        }
        if started.elapsed().as_secs() >= o.budget_secs {
            sum.aborted = Some(format!(
                "budget of {}s spent after {i} package(s)",
                o.budget_secs
            ));
            rec.verdict = NOT_REACHED.into();
            rec.reason = sum.aborted.clone().unwrap_or_default();
            w.write(&rec)?;
            sum.not_reached += 1;
            continue;
        }
        let t0 = Instant::now();
        let flow = if names_installed.contains(&pkg.name) {
            if let Some(p) = s.baseline.values().find(|p| p.name == pkg.name) {
                rec.evr = p.evr.clone();
            }
            s.preinstalled(&pkg.name, &mut rec)
        } else {
            s.fresh(pkg, &mut rec)
        };
        rec.duration_ms = ms(t0);
        rec.settle();
        scrub_record(&mut rec, secret);
        if let Flow::Abort(why) = flow {
            rec.steps
                .push(Step::new("guest-state", FAIL, why.clone(), 0));
            rec.settle();
            // try to recover the session once before giving up
            let back = wait_reachable(s.r, policy.limits.reconnect_secs);
            sum.aborted = Some(format!(
                "{} ({})",
                why,
                if back {
                    "guest reachable"
                } else {
                    "guest unreachable"
                }
            ));
        }
        w.write(&rec)?;
        tally(&mut sum, &rec.verdict);
        let status = match rec.verdict.as_str() {
            PASS => Status::Pass,
            FAIL => Status::Fail,
            _ => Status::Skip,
        };
        c.check(
            &format!("pkg.life.{}", pkg.name),
            "-",
            status,
            PASS,
            &rec.verdict,
            &clip(&format!("{}; {}", rec.summary(), rec.reason)),
        );
        log(&format!(
            "[{}/{}] {:<32} {:<5} {} ms {}",
            i + 1,
            cands.len(),
            pkg.name,
            rec.verdict,
            rec.duration_ms,
            parse::head(&rec.reason, 160)
        ));
    }

    // --- the guest must end where it started ----------------------------------------------
    match s.installed() {
        Ok(end) if end.keys().collect::<Vec<_>>() == s.baseline.keys().collect::<Vec<_>>() => c
            .check(
                "pkg.baseline_restored",
                "-",
                Status::Pass,
                &s.baseline.len().to_string(),
                &end.len().to_string(),
                "the package set at the end equals the baseline",
            ),
        Ok(end) => c.check(
            "pkg.baseline_restored",
            "-",
            Status::Fail,
            &s.baseline.len().to_string(),
            &end.len().to_string(),
            "the package set at the end differs from the baseline",
        ),
        Err(e) => c.check(
            "pkg.baseline_restored",
            "-",
            Status::Fail,
            "readable",
            "unreadable",
            &e,
        ),
    }
    c.check(
        "pkg.summary",
        "-",
        Status::Info,
        "",
        &format!(
            "{} pass, {} fail, {} skip, {} not reached ({} carried over)",
            sum.pass, sum.fail, sum.skip, sum.not_reached, sum.carried
        ),
        &format!(
            "{} in {}s; records in {}{}",
            cands.len(),
            started.elapsed().as_secs(),
            w.path.display(),
            sum.aborted
                .as_ref()
                .map(|a| format!("; stopped: {a}"))
                .unwrap_or_default()
        ),
    );
    Ok(sum)
}

fn tally(sum: &mut Summary, verdict: &str) {
    match verdict {
        PASS => sum.pass += 1,
        FAIL => sum.fail += 1,
        NOT_REACHED => sum.not_reached += 1,
        _ => sum.skip += 1,
    }
}

fn wait_reachable(r: &mut dyn Remote, secs: u64) -> bool {
    let t = Instant::now();
    loop {
        if r.fresh_reachable() {
            return true;
        }
        if t.elapsed().as_secs() >= secs {
            return false;
        }
        std::thread::sleep(std::time::Duration::from_secs(5));
    }
}

/// The guest password must never reach the evidence, whatever a package
/// printed.
pub fn scrub_record(rec: &mut PkgRecord, secret: Option<&str>) {
    let Some(pw) = secret.filter(|p| !p.is_empty()) else {
        return;
    };
    let fix = |s: &mut String| {
        if s.contains(pw) {
            *s = s.replace(pw, crate::phases::REDACTED);
        }
    };
    fix(&mut rec.reason);
    for st in rec.steps.iter_mut() {
        fix(&mut st.detail);
    }
    for u in rec.units.iter_mut() {
        fix(&mut u.outcome);
        u.steps.iter_mut().for_each(|st| fix(&mut st.detail));
        u.journal_errors.iter_mut().for_each(&fix);
    }
    for cl in rec.clis.iter_mut() {
        fix(&mut cl.reason);
        for a in cl.attempts.iter_mut() {
            fix(&mut a.stdout);
            fix(&mut a.stderr);
            fix(&mut a.verdict);
        }
    }
    rec.journal_errors.iter_mut().for_each(fix);
}

#[cfg(test)]
mod tests;
