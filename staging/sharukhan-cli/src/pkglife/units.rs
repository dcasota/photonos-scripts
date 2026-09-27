//! Daemon tests: enable, start, stay up, stop, disable - and the journal of
//! exactly that window.
//!
//! ## What is decided before anything runs ([`plan`])
//!
//! | situation                                          | plan                         |
//! |----------------------------------------------------|------------------------------|
//! | alias (symlink) of another unit                    | skip: tested under its name  |
//! | template `foo@.service`                            | skip: needs an instance name, whose meaning is package-specific |
//! | target/mount/automount/swap/slice/scope/device     | skip: starting them changes mounts, swap or pulls whole dependency trees |
//! | LoadState bad-setting/error/masked/not-found       | FAIL: the unit file does not load |
//! | `units.protected` (sshd, journald, dbus, networkd...) or the unit owning the ssh listener | skip: the harness's own session and evidence depend on it |
//! | `units.never_start` (reviewed, with reason)        | skip                          |
//! | RefuseManualStart=yes                              | skip: systemd itself forbids it |
//! | Conflicts= names an ACTIVE protected unit          | skip: starting it would stop that unit |
//! | Before= a network ordering target, or `units.network_affecting` | cycle under a dead-man switch |
//! | otherwise                                          | cycle                         |
//!
//! ## How a start is judged ([`judge_start`])
//!
//! `systemctl start` blocks until the start job completes, bounded by
//! `timeout` in the guest - the wait is measured, not guessed. Then:
//!
//! | observed                                                | outcome              |
//! |---------------------------------------------------------|----------------------|
//! | the bound fired                                         | FAIL timed out        |
//! | ConditionResult=no, not active                          | SKIP condition (the unmet condition is quoted from the journal) |
//! | AssertResult=no                                         | FAIL assertion        |
//! | ActiveState=failed or Result≠success                    | FAIL (Result, exit code/status) - unless `units.requires_config` declares it, then SKIP with the evidence |
//! | service active/running, or active/exited with RemainAfterExit | pass            |
//! | Type=oneshot inactive with Result=success               | pass (ran to completion) |
//! | any other service inactive after start                   | FAIL: exited at once  |
//! | socket active/listening; timer or path active/waiting    | pass                 |
//! | anything else (still activating, auto-restart)           | FAIL                 |
//!
//! A started unit must then STAY up for `stability_secs`: same MainPID, same
//! NRestarts, still active. Stop must leave it inactive (not failed) with no
//! main process; disable must leave it disabled. The unit's journal between
//! the cursor taken before enable and the end of the cycle must hold no entry
//! of priority err or worse.

use crate::pkglife::parse::{self, JEntry};
use crate::pkglife::policy::{first_match, Policy};
use crate::pkglife::record::{clip, Step, UnitResult, FAIL, INFO, PASS, SKIP};
use crate::pkglife::remote::{argv, transport_lost, Remote};
use std::collections::{BTreeMap, BTreeSet};
use std::time::Instant;

pub const PROPS: &str = "Id,LoadState,ActiveState,SubState,Result,Type,UnitFileState,\
UnitFilePreset,MainPID,ExecMainCode,ExecMainStatus,ConditionResult,AssertResult,\
RefuseManualStart,RemainAfterExit,Before,Conflicts,NRestarts,NeedDaemonReload,Triggers";

pub type Props = BTreeMap<String, String>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Plan {
    Cycle { deadman: bool },
    Skip(String),
    Fail(String),
}

impl Plan {
    pub fn label(&self) -> String {
        match self {
            Plan::Cycle { deadman: false } => "cycle".into(),
            Plan::Cycle { deadman: true } => "cycle under dead-man switch".into(),
            Plan::Skip(why) => format!("skip: {why}"),
            Plan::Fail(why) => format!("fail: {why}"),
        }
    }
}

fn words(p: &Props, k: &str) -> Vec<String> {
    p.get(k)
        .map(|v| v.split_whitespace().map(str::to_string).collect())
        .unwrap_or_default()
}

fn prop<'a>(p: &'a Props, k: &str) -> &'a str {
    p.get(k).map(String::as_str).unwrap_or("")
}

pub const STARTABLE: [&str; 4] = ["service", "socket", "timer", "path"];

/// The part of the plan that needs no unit properties - which matters,
/// because `systemctl show` refuses a template name outright (measured:
/// openssh-socket's `sshd@.service`), so these must be decided first.
pub fn plan_static(name: &str, alias: bool) -> Option<Plan> {
    if alias {
        return Some(Plan::Skip(
            "alias of another unit; tested under that name".into(),
        ));
    }
    let kind = name.rsplit('.').next().unwrap_or("");
    if name.contains("@.") {
        return Some(Plan::Skip(
            "template unit: needs an instance name whose meaning is package-specific".into(),
        ));
    }
    if !STARTABLE.contains(&kind) {
        return Some(Plan::Skip(format!(
            "{kind} units are not started: they change mounts or swap, or pull whole dependency trees"
        )));
    }
    None
}

/// Decide what may be done to a unit. `protected_active` is the set of active
/// units the harness depends on (policy plus the derived ssh listener unit).
pub fn plan(
    name: &str,
    alias: bool,
    props: &Props,
    policy: &Policy,
    protected_active: &BTreeSet<String>,
) -> Plan {
    if let Some(p) = plan_static(name, alias) {
        return p;
    }
    match prop(props, "LoadState") {
        "loaded" => {}
        other => {
            return Plan::Fail(format!(
                "LoadState={} - the unit file does not load",
                if other.is_empty() { "(none)" } else { other }
            ))
        }
    }
    if let Some(r) = first_match(&policy.units.protected, name) {
        return Plan::Skip(format!("protected ({}): {}", r.pattern, r.reason));
    }
    if protected_active.contains(name) {
        return Plan::Skip(
            "owns the harness's ssh session (derived from the port 22 listener)".into(),
        );
    }
    if let Some(r) = first_match(&policy.units.never_start, name) {
        return Plan::Skip(format!("never started ({}): {}", r.pattern, r.reason));
    }
    if prop(props, "RefuseManualStart") == "yes" {
        return Plan::Skip("RefuseManualStart=yes: systemd refuses a manual start".into());
    }
    let hits: Vec<String> = words(props, "Conflicts")
        .into_iter()
        .filter(|c| protected_active.contains(c))
        .collect();
    if !hits.is_empty() {
        return Plan::Skip(format!(
            "Conflicts= names active protected unit(s) {}: starting it would stop them",
            hits.join(", ")
        ));
    }
    let ordered = words(props, "Before")
        .into_iter()
        .any(|b| policy.units.network_ordering.contains(&b));
    let listed = first_match(&policy.units.network_affecting, name).is_some();
    Plan::Cycle {
        deadman: ordered || listed,
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Start {
    Up(String),
    Condition,
    Failed(String),
}

/// Judge the state a unit is in after `systemctl start` returned.
pub fn judge_start(kind: &str, start_code: Option<i32>, timed_out: bool, p: &Props) -> Start {
    if timed_out || start_code == Some(124) || start_code == Some(137) {
        return Start::Failed("start did not complete within the bound".into());
    }
    let (active, sub, result) = (
        prop(p, "ActiveState"),
        prop(p, "SubState"),
        prop(p, "Result"),
    );
    if prop(p, "ConditionResult") == "no" && active != "active" {
        return Start::Condition;
    }
    if prop(p, "AssertResult") == "no" {
        return Start::Failed("an Assert*= check failed".into());
    }
    if active == "failed" || (!result.is_empty() && result != "success") {
        return Start::Failed(format!(
            "ActiveState={active} Result={result} ExecMainCode={} ExecMainStatus={}",
            prop(p, "ExecMainCode"),
            prop(p, "ExecMainStatus")
        ));
    }
    if start_code.is_some_and(|c| c != 0) {
        return Start::Failed(format!(
            "systemctl start exited {} with ActiveState={active} SubState={sub}",
            start_code.unwrap_or(-1)
        ));
    }
    let state = format!("{active}/{sub}");
    match (kind, active, sub) {
        ("service", "active", "running") => Start::Up(state),
        ("service", "active", "exited") if prop(p, "RemainAfterExit") == "yes" => Start::Up(state),
        ("service", "inactive", _) if prop(p, "Type") == "oneshot" && result == "success" => {
            Start::Up("oneshot ran to completion".into())
        }
        ("service", "inactive", _) => Start::Failed(format!(
            "Type={} exited right after start (status {}): a daemon that does not stay up",
            prop(p, "Type"),
            prop(p, "ExecMainStatus")
        )),
        ("socket", "active", "listening") => Start::Up(state),
        ("timer" | "path", "active", "waiting" | "running") => Start::Up(state),
        _ => Start::Failed(format!("unexpected state {state} after start")),
    }
}

/// Did the unit stay the way the start left it?
pub fn judge_stable(kind: &str, before: &Props, after: &Props) -> Result<(), String> {
    let changed = |k: &str| prop(before, k) != prop(after, k);
    if changed("ActiveState") {
        return Err(format!(
            "ActiveState went {} -> {} (Result={})",
            prop(before, "ActiveState"),
            prop(after, "ActiveState"),
            prop(after, "Result")
        ));
    }
    if changed("NRestarts") {
        return Err(format!(
            "restarted: NRestarts {} -> {}",
            prop(before, "NRestarts"),
            prop(after, "NRestarts")
        ));
    }
    if kind == "service" && prop(before, "MainPID") != "0" && changed("MainPID") {
        return Err(format!(
            "main process changed {} -> {}",
            prop(before, "MainPID"),
            prop(after, "MainPID")
        ));
    }
    Ok(())
}

pub fn judge_stop(p: &Props) -> Result<(), String> {
    match (prop(p, "ActiveState"), prop(p, "MainPID")) {
        ("inactive", "0" | "") => Ok(()),
        (a, pid) => Err(format!(
            "after stop ActiveState={a} MainPID={pid} Result={}",
            prop(p, "Result")
        )),
    }
}

/// Enablement that systemctl enable/disable can meaningfully change.
pub fn toggleable(unit_file_state: &str) -> bool {
    matches!(unit_file_state, "enabled" | "disabled")
}

/// Errors (priority <= 3) in a unit's journal, as lines.
pub fn errors(entries: &[JEntry]) -> Vec<String> {
    entries
        .iter()
        .filter(|e| e.priority <= 3)
        .map(|e| clip(&e.line()))
        .collect()
}

/// systemd's own words for a skipped start: "... was skipped because of an
/// unmet condition check (ConditionPathExists=/etc/x)".
pub fn condition_evidence(entries: &[JEntry]) -> Option<String> {
    entries
        .iter()
        .find(|e| e.message.contains("condition"))
        .map(|e| clip(&e.message))
}

/// A heuristic HINT only - it never changes a status. When a start failed and
/// the unit's own journal reads like missing configuration, say so, with the
/// line, so the reviewer can decide whether a `requires_config` entry is due.
pub fn config_hint(entries: &[JEntry]) -> Option<String> {
    const WORDS: [&str; 6] = [
        "config",
        "no such file",
        "not configured",
        "missing",
        "no interfaces",
        "not found",
    ];
    entries
        .iter()
        .find(|e| {
            let m = e.message.to_lowercase();
            WORDS.iter().any(|w| m.contains(w))
        })
        .map(|e| clip(&e.message))
}

// ------------------------------------------------------------ driving -----

pub struct Ctx<'a> {
    pub r: &'a mut dyn Remote,
    pub policy: &'a Policy,
    pub nonce: &'a str,
}

fn ms(t: Instant) -> u64 {
    t.elapsed().as_millis() as u64
}

pub fn show(r: &mut dyn Remote, unit: &str, secs: u64) -> Result<Props, String> {
    let cmd = argv(&["systemctl", "show", "-p", PROPS, "--", unit])?;
    let e = r.exec(&cmd, None, secs);
    if !e.ok() {
        return Err(format!(
            "systemctl show {unit}: exit {:?}: {}",
            e.code,
            clip(e.stderr.trim())
        ));
    }
    parse::systemctl_show(&e.stdout)
}

pub fn journal_cursor(r: &mut dyn Remote, secs: u64) -> Result<String, String> {
    let e = r.exec("journalctl -n 0 --show-cursor --no-pager", None, secs);
    if !e.ok() {
        return Err(format!(
            "journalctl cursor: exit {:?}: {}",
            e.code,
            clip(&e.stderr)
        ));
    }
    parse::cursor(&e.stdout)
}

/// Entries after `cursor`, optionally only for `unit`, optionally only err+.
pub fn journal_since(
    r: &mut dyn Remote,
    cursor: &str,
    unit: Option<&str>,
    errors_only: bool,
    secs: u64,
) -> Result<Vec<JEntry>, String> {
    let after = format!("--after-cursor={cursor}");
    let mut v = vec!["journalctl", "--no-pager", "-o", "json", after.as_str()];
    if errors_only {
        v.extend(["-p", "0..3"]);
    }
    let u;
    if let Some(unit) = unit {
        u = format!("--unit={unit}");
        v.push(&u);
    }
    let e = r.exec(&argv(&v)?, None, secs);
    if !e.ok() {
        return Err(format!(
            "journalctl: exit {:?}: {}",
            e.code,
            clip(&e.stderr)
        ));
    }
    parse::journal_json(&e.stdout)
}

fn step(res: &mut UnitResult, name: &str, status: &str, detail: impl Into<String>, t: Instant) {
    res.steps.push(Step::new(name, status, detail, ms(t)));
}

fn sysctl(ctx: &mut Ctx, verb: &str, unit: &str, secs: u64) -> crate::pkglife::remote::Exec {
    match argv(&["systemctl", verb, "--", unit]) {
        Ok(c) => ctx.r.exec(&c, None, secs),
        Err(e) => crate::pkglife::remote::Exec {
            stderr: e,
            ..Default::default()
        },
    }
}

/// Outcome of a whole cycle for the orchestrator: the result, plus whether the
/// ssh session was lost (the run must stop and say so).
pub struct Cycled {
    pub res: UnitResult,
    pub session_lost: bool,
}

/// Enable -> start -> stay up -> stop -> disable, with the journal window.
pub fn cycle(ctx: &mut Ctx, unit: &str, deadman: bool) -> Cycled {
    let kind = unit.rsplit('.').next().unwrap_or("").to_string();
    let lim = ctx.policy.limits.clone();
    let mut res = UnitResult {
        unit: unit.to_string(),
        kind: kind.clone(),
        plan: Plan::Cycle { deadman }.label(),
        ..Default::default()
    };
    let mut lost = false;
    let t = Instant::now();
    let cursor = match journal_cursor(ctx.r, lim.query_secs) {
        Ok(c) => c,
        Err(e) => {
            step(&mut res, "journal-cursor", FAIL, e, t);
            res.status = FAIL.into();
            res.outcome = "journal cursor unavailable; the window cannot be isolated".into();
            return Cycled {
                res,
                session_lost: false,
            };
        }
    };
    let before = match show(ctx.r, unit, lim.query_secs) {
        Ok(p) => p,
        Err(e) => {
            step(&mut res, "show", FAIL, e, t);
            res.status = FAIL.into();
            res.outcome = "unit state unreadable".into();
            return Cycled {
                res,
                session_lost: false,
            };
        }
    };

    // --- enable ----------------------------------------------------------
    let ufs = prop(&before, "UnitFileState").to_string();
    let t = Instant::now();
    let mut we_enabled = false;
    match ufs.as_str() {
        "disabled" => {
            let e = sysctl(ctx, "enable", unit, lim.query_secs);
            let after = show(ctx.r, unit, lim.query_secs).unwrap_or_default();
            if e.ok() && prop(&after, "UnitFileState") == "enabled" {
                we_enabled = true;
                step(&mut res, "enable", PASS, "disabled -> enabled", t);
            } else {
                step(
                    &mut res,
                    "enable",
                    FAIL,
                    format!(
                        "exit {:?}, UnitFileState={}: {}",
                        e.code,
                        prop(&after, "UnitFileState"),
                        e.stderr.trim()
                    ),
                    t,
                );
            }
        }
        "enabled" => step(
            &mut res,
            "enable",
            INFO,
            format!(
                "already enabled at install (UnitFilePreset={}): the preset enables it",
                prop(&before, "UnitFilePreset")
            ),
            t,
        ),
        other => step(
            &mut res,
            "enable",
            INFO,
            format!("UnitFileState={other}: enable/disable do not apply"),
            t,
        ),
    }

    // --- dead-man switch -------------------------------------------------
    let deadman_unit = format!("sharukhan-deadman-{}", ctx.nonce);
    if deadman {
        let t = Instant::now();
        let secs = format!("--on-active={}", lim.deadman_secs);
        let unit_arg = format!("--unit={deadman_unit}");
        let armed = argv(&[
            "systemd-run",
            "--quiet",
            "--collect",
            &unit_arg,
            &secs,
            "--timer-property=AccuracySec=1s",
            "/usr/bin/systemctl",
            "stop",
            "--",
            unit,
        ])
        .map(|c| ctx.r.exec(&c, None, lim.query_secs));
        match armed {
            Ok(e) if e.ok() => step(
                &mut res,
                "dead-man-arm",
                PASS,
                format!(
                    "{deadman_unit}.timer stops {unit} after {}s unless disarmed",
                    lim.deadman_secs
                ),
                t,
            ),
            Ok(e) => {
                step(
                    &mut res,
                    "dead-man-arm",
                    FAIL,
                    format!("could not arm: exit {:?}: {}", e.code, e.stderr.trim()),
                    t,
                );
                res.status = FAIL.into();
                res.outcome = "not started: the safety net could not be armed".into();
                return Cycled {
                    res,
                    session_lost: false,
                };
            }
            Err(e) => {
                step(&mut res, "dead-man-arm", FAIL, e, t);
                res.status = FAIL.into();
                res.outcome = "not started: the safety net could not be armed".into();
                return Cycled {
                    res,
                    session_lost: false,
                };
            }
        }
    }

    // --- start -----------------------------------------------------------
    let t = Instant::now();
    let e = sysctl(ctx, "start", unit, lim.unit_start_secs);
    let start_ms = ms(t);
    if deadman {
        let t2 = Instant::now();
        if ctx.r.fresh_reachable() {
            let disarm = argv(&["systemctl", "stop", "--", &format!("{deadman_unit}.timer")])
                .map(|c| ctx.r.exec(&c, None, lim.query_secs));
            let ok = matches!(&disarm, Ok(d) if d.ok());
            step(
                &mut res,
                "ssh-after-start",
                PASS,
                format!(
                    "a new ssh connection succeeded after start; dead-man {}",
                    if ok { "disarmed" } else { "disarm FAILED" }
                ),
                t2,
            );
            if !ok {
                step(
                    &mut res,
                    "dead-man-disarm",
                    FAIL,
                    "the timer could not be stopped",
                    t2,
                );
            }
        } else {
            // Wait out the switch, then prove the guest came back.
            let deadline = Instant::now()
                + std::time::Duration::from_secs(lim.deadman_secs + lim.reconnect_secs);
            let mut back = false;
            while Instant::now() < deadline {
                std::thread::sleep(std::time::Duration::from_secs(5));
                if ctx.r.fresh_reachable() {
                    back = true;
                    break;
                }
            }
            step(
                &mut res,
                "ssh-after-start",
                FAIL,
                if back {
                    format!(
                        "starting {unit} refused new ssh connections; reachable again after the \
                         dead-man switch stopped it ({} ms)",
                        ms(t2)
                    )
                } else {
                    format!(
                        "starting {unit} cut ssh and the guest did not come back within {}s",
                        lim.deadman_secs + lim.reconnect_secs
                    )
                },
                t2,
            );
            res.status = FAIL.into();
            res.outcome = "cut the harness's ssh access".into();
            return Cycled {
                res,
                session_lost: !back,
            };
        }
    }
    if transport_lost(&e) {
        lost = true;
    }
    let started = show(ctx.r, unit, lim.query_secs).unwrap_or_default();
    let verdict = judge_start(&kind, e.code, e.timed_out, &started);
    let window = journal_since(ctx.r, &cursor, Some(unit), false, lim.query_secs);
    let entries = window.as_ref().cloned().unwrap_or_default();
    let mut up = false;
    match &verdict {
        Start::Up(state) => {
            up = true;
            res.steps
                .push(Step::new("start", PASS, state.clone(), start_ms));
        }
        Start::Condition => {
            res.steps.push(Step::new(
                "start",
                SKIP,
                format!(
                    "skipped (condition): {}",
                    condition_evidence(&entries)
                        .unwrap_or_else(|| "ConditionResult=no (systemd logged no detail)".into())
                ),
                start_ms,
            ));
            res.outcome = "skipped (condition)".into();
        }
        Start::Failed(why) => {
            let declared = first_match(&ctx.policy.units.requires_config, unit);
            let hint = config_hint(&entries)
                .map(|h| format!("; journal: {h}"))
                .unwrap_or_default();
            match declared {
                Some(r) => {
                    res.steps.push(Step::new(
                        "start",
                        SKIP,
                        format!(
                            "failed as declared (requires configuration: {}): {why}{hint}",
                            r.reason
                        ),
                        start_ms,
                    ));
                    res.outcome = "needs configuration (declared)".into();
                }
                None => {
                    res.steps.push(Step::new(
                        "start",
                        FAIL,
                        format!("{why}; stderr: {}{hint}", clip(e.stderr.trim())),
                        start_ms,
                    ));
                    res.outcome = "failed to start".into();
                }
            }
        }
    }

    // --- stays up --------------------------------------------------------
    if up && !lost {
        let t = Instant::now();
        std::thread::sleep(std::time::Duration::from_secs(lim.stability_secs));
        match show(ctx.r, unit, lim.query_secs) {
            Ok(later) => match judge_stable(&kind, &started, &later) {
                Ok(()) => step(
                    &mut res,
                    "stays-up",
                    PASS,
                    format!(
                        "unchanged after {}s: {}/{} MainPID={} NRestarts={}",
                        lim.stability_secs,
                        prop(&later, "ActiveState"),
                        prop(&later, "SubState"),
                        prop(&later, "MainPID"),
                        prop(&later, "NRestarts")
                    ),
                    t,
                ),
                Err(why) => step(&mut res, "stays-up", FAIL, why, t),
            },
            Err(e) => step(&mut res, "stays-up", FAIL, e, t),
        }
    }

    // --- stop (always: a failed start can leave a process behind) ---------
    let t = Instant::now();
    let e = sysctl(ctx, "stop", unit, lim.unit_stop_secs);
    let stopped = show(ctx.r, unit, lim.query_secs).unwrap_or_default();
    match (e.ok(), judge_stop(&stopped)) {
        (true, Ok(())) => step(&mut res, "stop", PASS, "inactive, no main process", t),
        (true, Err(why)) if !up => step(&mut res, "stop", INFO, why, t),
        (_, r) => step(
            &mut res,
            "stop",
            FAIL,
            format!(
                "exit {:?}; {}",
                e.code,
                r.err().unwrap_or_else(|| e.stderr.trim().to_string())
            ),
            t,
        ),
    }
    // Clear a failed state this test caused, so the next package's baseline
    // of failed units is not inherited from this one. It is recorded above.
    let _ = sysctl(ctx, "reset-failed", unit, lim.query_secs);

    // --- disable -----------------------------------------------------------
    let t = Instant::now();
    let now = show(ctx.r, unit, lim.query_secs).unwrap_or_default();
    if prop(&now, "UnitFileState") == "enabled" {
        let e = sysctl(ctx, "disable", unit, lim.query_secs);
        let after = show(ctx.r, unit, lim.query_secs).unwrap_or_default();
        if e.ok() && prop(&after, "UnitFileState") == "disabled" {
            step(
                &mut res,
                "disable",
                PASS,
                format!(
                    "enabled -> disabled{}",
                    if we_enabled {
                        ""
                    } else {
                        " (was enabled by preset)"
                    }
                ),
                t,
            );
        } else {
            step(
                &mut res,
                "disable",
                FAIL,
                format!(
                    "exit {:?}, UnitFileState={}: {}",
                    e.code,
                    prop(&after, "UnitFileState"),
                    e.stderr.trim()
                ),
                t,
            );
        }
    } else if toggleable(&ufs) {
        step(
            &mut res,
            "disable",
            FAIL,
            format!(
                "UnitFileState={} before disable; expected enabled",
                prop(&now, "UnitFileState")
            ),
            t,
        );
    }

    // --- the journal of exactly this window ------------------------------
    let t = Instant::now();
    match journal_since(ctx.r, &cursor, Some(unit), false, lim.query_secs) {
        Ok(all) => {
            res.journal_errors = errors(&all);
            if res.journal_errors.is_empty() {
                step(
                    &mut res,
                    "journal",
                    PASS,
                    format!("{} entries in the window, none err or worse", all.len()),
                    t,
                );
            } else {
                let d = format!(
                    "{} entr(ies) of priority err or worse: {}",
                    res.journal_errors.len(),
                    res.journal_errors.join(" | ")
                );
                step(&mut res, "journal", FAIL, d, t);
            }
        }
        Err(e) => step(&mut res, "journal", FAIL, e, t),
    }
    if let Err(e) = window {
        step(&mut res, "journal-at-start", INFO, e, Instant::now());
    }

    res.status = if res.steps.iter().any(|s| s.status == FAIL) {
        FAIL.into()
    } else if res.steps.iter().any(|s| s.status == PASS)
        && !res
            .steps
            .iter()
            .any(|s| s.name == "start" && s.status == SKIP)
    {
        PASS.into()
    } else {
        SKIP.into()
    };
    if res.outcome.is_empty() {
        res.outcome = if res.status == PASS {
            "cycled".into()
        } else {
            "failed".into()
        };
    }
    Cycled {
        res,
        session_lost: lost,
    }
}

/// A preinstalled unit is part of the baseline the guest depends on, so it is
/// OBSERVED, never started or stopped: its state, and the errors it logged
/// before the lifecycle run began (`boot_errors`, taken once at the start so
/// later packages cannot pollute it).
pub fn observe(
    r: &mut dyn Remote,
    unit: &str,
    policy: &Policy,
    baseline_failed: &BTreeSet<String>,
    boot_errors: &[JEntry],
) -> UnitResult {
    let kind = unit.rsplit('.').next().unwrap_or("").to_string();
    let mut res = UnitResult {
        unit: unit.to_string(),
        kind,
        plan: "observe: preinstalled units are never started or stopped".into(),
        ..Default::default()
    };
    let t = Instant::now();
    match show(r, unit, policy.limits.query_secs) {
        Ok(p) => {
            let state = format!(
                "{}/{} UnitFileState={}",
                prop(&p, "ActiveState"),
                prop(&p, "SubState"),
                prop(&p, "UnitFileState")
            );
            if prop(&p, "LoadState") != "loaded" {
                step(
                    &mut res,
                    "state",
                    FAIL,
                    format!("LoadState={} ({state})", prop(&p, "LoadState")),
                    t,
                );
            } else if baseline_failed.contains(unit) || prop(&p, "ActiveState") == "failed" {
                step(
                    &mut res,
                    "state",
                    FAIL,
                    format!("failed at baseline ({state})"),
                    t,
                );
            } else {
                step(&mut res, "state", PASS, state, t);
            }
        }
        Err(e) => step(&mut res, "state", FAIL, e, t),
    }
    let mine: Vec<JEntry> = boot_errors
        .iter()
        .filter(|e| e.unit == unit)
        .cloned()
        .collect();
    res.journal_errors = errors(&mine);
    let t = Instant::now();
    if res.journal_errors.is_empty() {
        step(
            &mut res,
            "journal",
            PASS,
            "no err-or-worse entries this boot before the run",
            t,
        );
    } else {
        let d = format!(
            "{} this boot: {}",
            res.journal_errors.len(),
            res.journal_errors.join(" | ")
        );
        step(&mut res, "journal", FAIL, d, t);
    }
    res.status = if res.steps.iter().any(|s| s.status == FAIL) {
        FAIL.into()
    } else {
        PASS.into()
    };
    res.outcome = "observed".into();
    res
}

/// The unit that owns the process listening on port 22 - the harness's own
/// session - derived, not assumed to be called sshd.service.
pub fn ssh_listener_unit(r: &mut dyn Remote, secs: u64) -> Result<String, String> {
    let e = r.exec("ss -Hltnp", None, secs);
    if !e.ok() {
        return Err(format!("ss: exit {:?}: {}", e.code, clip(&e.stderr)));
    }
    let pids = parse::listeners_on_port(&e.stdout, 22);
    let pid = pids
        .first()
        .ok_or_else(|| "no process listens on port 22".to_string())?;
    let c = r.exec(&format!("cat /proc/{pid}/cgroup"), None, secs);
    parse::unit_of_cgroup(&c.stdout)
        .ok_or_else(|| format!("pid {pid}'s cgroup names no unit: {}", clip(&c.stdout)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pkglife::remote::fake::{self, Fake};

    fn props(s: &str) -> Props {
        parse::systemctl_show(s).unwrap()
    }
    fn pol() -> Policy {
        Policy::embedded().unwrap()
    }
    fn none() -> BTreeSet<String> {
        BTreeSet::new()
    }

    const LOADED: &str = "LoadState=loaded\nBefore=shutdown.target\nConflicts=shutdown.target\n";

    #[test]
    fn planning_follows_the_documented_table() {
        let p = pol();
        let l = props(LOADED);
        assert_eq!(
            plan("chronyd.service", false, &l, &p, &none()),
            Plan::Cycle { deadman: false }
        );
        assert!(
            matches!(plan("x.service", true, &l, &p, &none()), Plan::Skip(w) if w.contains("alias"))
        );
        assert!(
            matches!(plan("getty@.service", false, &l, &p, &none()), Plan::Skip(w) if w.contains("template"))
        );
        assert!(
            matches!(plan("x.mount", false, &l, &p, &none()), Plan::Skip(w) if w.contains("mount units"))
        );
        assert!(matches!(
            plan("x.target", false, &l, &p, &none()),
            Plan::Skip(_)
        ));
        assert!(
            matches!(plan("sshd.service", false, &l, &p, &none()), Plan::Skip(w) if w.starts_with("protected"))
        );
        assert!(
            matches!(plan("watchdog.service", false, &l, &p, &none()), Plan::Skip(w) if w.contains("reboots"))
        );
        let bad = props("LoadState=bad-setting\n");
        assert!(
            matches!(plan("x.service", false, &bad, &p, &none()), Plan::Fail(w) if w.contains("bad-setting"))
        );
        assert!(
            matches!(plan("x.service", false, &props("Id=x\n"), &p, &none()), Plan::Fail(w) if w.contains("(none)"))
        );
        let refuse = props("LoadState=loaded\nRefuseManualStart=yes\n");
        assert!(
            matches!(plan("x.service", false, &refuse, &p, &none()), Plan::Skip(w) if w.contains("RefuseManualStart"))
        );
    }

    #[test]
    fn the_derived_ssh_unit_and_its_conflicts_are_protected() {
        let p = pol();
        let mut prot = BTreeSet::new();
        prot.insert("sshd-custom.service".to_string());
        let l = props(LOADED);
        assert!(
            matches!(plan("sshd-custom.service", false, &l, &p, &prot), Plan::Skip(w) if w.contains("port 22"))
        );
        // openssh-socket's sshd.socket: Conflicts=sshd.service
        let sock = props("LoadState=loaded\nConflicts=sshd-custom.service shutdown.target\n");
        assert!(
            matches!(plan("other.socket", false, &sock, &p, &prot), Plan::Skip(w) if w.contains("Conflicts"))
        );
        // negative control: conflicting with an INACTIVE protected unit is fine
        assert_eq!(
            plan("other.socket", false, &sock, &p, &none()),
            Plan::Cycle { deadman: false }
        );
    }

    #[test]
    fn firewalls_are_recognised_by_ordering_and_by_the_reviewed_list() {
        let p = pol();
        // nftables.service as shipped on the 5.0 media
        let nft = props("LoadState=loaded\nBefore=network-pre.target shutdown.target\nConflicts=iptables.service\n");
        assert_eq!(
            plan("anything.service", false, &nft, &p, &none()),
            Plan::Cycle { deadman: true }
        );
        // ebtables: only After=network.target, caught by the list
        assert_eq!(
            plan("ebtables.service", false, &props(LOADED), &p, &none()),
            Plan::Cycle { deadman: true }
        );
        // negative control: After= a network target is not providing one
        let after = props("LoadState=loaded\nAfter=network.target\nBefore=multi-user.target\n");
        assert_eq!(
            plan("web.service", false, &after, &p, &none()),
            Plan::Cycle { deadman: false }
        );
    }

    #[test]
    fn start_judgement_covers_every_documented_row() {
        let j = |kind, code, to, s: &str| judge_start(kind, code, to, &props(s));
        assert_eq!(
            j(
                "service",
                Some(0),
                false,
                "ActiveState=active\nSubState=running\nResult=success\n"
            ),
            Start::Up("active/running".into())
        );
        assert!(
            matches!(j("service", None, true, "ActiveState=activating\n"), Start::Failed(w) if w.contains("bound"))
        );
        assert!(matches!(
            j("service", Some(124), false, "ActiveState=activating\n"),
            Start::Failed(_)
        ));
        assert_eq!(
            j(
                "service",
                Some(0),
                false,
                "ActiveState=inactive\nConditionResult=no\nResult=success\n"
            ),
            Start::Condition
        );
        assert!(
            matches!(j("service", Some(1), false, "ActiveState=inactive\nAssertResult=no\n"), Start::Failed(w) if w.contains("Assert"))
        );
        assert!(matches!(
            j("service", Some(1), false, "ActiveState=failed\nResult=exit-code\nExecMainCode=1\nExecMainStatus=1\n"),
            Start::Failed(w) if w.contains("Result=exit-code")
        ));
        // chrony-wait.service, captured
        assert!(matches!(
            j("service", Some(0), false, "ActiveState=active\nSubState=exited\nResult=success\nRemainAfterExit=yes\nType=oneshot\n"),
            Start::Up(_)
        ));
        assert!(matches!(
            j("service", Some(0), false, "ActiveState=inactive\nSubState=dead\nResult=success\nType=oneshot\n"),
            Start::Up(w) if w.contains("completion")
        ));
        assert!(matches!(
            j("service", Some(0), false, "ActiveState=inactive\nSubState=dead\nResult=success\nType=simple\nExecMainStatus=0\n"),
            Start::Failed(w) if w.contains("does not stay up")
        ));
        assert!(matches!(
            j(
                "service",
                Some(0),
                false,
                "ActiveState=active\nSubState=exited\nResult=success\nRemainAfterExit=no\n"
            ),
            Start::Failed(_)
        ));
        assert!(matches!(
            j(
                "socket",
                Some(0),
                false,
                "ActiveState=active\nSubState=listening\nResult=success\n"
            ),
            Start::Up(_)
        ));
        assert!(matches!(
            j(
                "timer",
                Some(0),
                false,
                "ActiveState=active\nSubState=waiting\nResult=success\n"
            ),
            Start::Up(_)
        ));
        assert!(matches!(
            j(
                "path",
                Some(0),
                false,
                "ActiveState=active\nSubState=waiting\nResult=success\n"
            ),
            Start::Up(_)
        ));
        assert!(matches!(
            j(
                "service",
                Some(0),
                false,
                "ActiveState=activating\nSubState=auto-restart\nResult=success\n"
            ),
            Start::Failed(_)
        ));
        assert!(
            matches!(j("service", Some(3), false, "ActiveState=active\nSubState=running\nResult=success\n"), Start::Failed(w) if w.contains("exited 3"))
        );
    }

    #[test]
    fn stability_catches_restarts_and_deaths() {
        let a = props("ActiveState=active\nMainPID=10\nNRestarts=0\n");
        assert!(judge_stable("service", &a, &a).is_ok());
        assert!(judge_stable(
            "service",
            &a,
            &props("ActiveState=failed\nMainPID=0\nNRestarts=0\n")
        )
        .is_err());
        assert!(judge_stable(
            "service",
            &a,
            &props("ActiveState=active\nMainPID=10\nNRestarts=1\n")
        )
        .is_err());
        assert!(judge_stable(
            "service",
            &a,
            &props("ActiveState=active\nMainPID=11\nNRestarts=0\n")
        )
        .is_err());
        let oneshot = props("ActiveState=active\nMainPID=0\nNRestarts=0\n");
        assert!(judge_stable("service", &oneshot, &oneshot).is_ok());
    }

    #[test]
    fn stop_and_toggle_judgements() {
        assert!(judge_stop(&props("ActiveState=inactive\nMainPID=0\n")).is_ok());
        assert!(judge_stop(&props("ActiveState=failed\nMainPID=0\nResult=exit-code\n")).is_err());
        assert!(judge_stop(&props("ActiveState=deactivating\nMainPID=4\n")).is_err());
        assert!(toggleable("enabled") && toggleable("disabled"));
        assert!(!toggleable("static") && !toggleable("indirect") && !toggleable("masked"));
    }

    fn je(p: u8, unit: &str, msg: &str) -> JEntry {
        JEntry {
            priority: p,
            message: msg.into(),
            unit: unit.into(),
            identifier: String::new(),
            realtime_us: 0,
        }
    }

    #[test]
    fn journal_helpers_pick_errors_conditions_and_hints() {
        let e = vec![
            je(6, "a.service", "Starting A..."),
            je(4, "a.service", "Running with root privileges"),
            je(
                3,
                "a.service",
                "cannot open /etc/a.conf: No such file or directory",
            ),
            je(
                6,
                "a.service",
                "A was skipped because of an unmet condition check (ConditionPathExists=/etc/a)",
            ),
        ];
        assert_eq!(errors(&e).len(), 1);
        assert!(condition_evidence(&e)
            .unwrap()
            .contains("ConditionPathExists"));
        assert!(config_hint(&e).unwrap().contains("a.conf"));
        // negative controls
        assert!(errors(&e[..2]).is_empty());
        assert!(condition_evidence(&e[..2]).is_none());
        assert!(config_hint(&e[..1]).is_none());
    }

    const CURSOR: &str = "-- cursor: s=1;i=2\n";

    /// A guest answering one cycle in order. `up` says whether the start
    /// succeeds, which decides whether the stability re-read happens.
    fn scripted(start: &str, after: &str, up: bool) -> Fake {
        let mut f = Fake::new();
        f.on("--show-cursor", fake::ok(CURSOR))
            .once(
                "'show'",
                fake::ok(
                    "LoadState=loaded\nActiveState=inactive\nUnitFileState=disabled\nMainPID=0\n",
                ),
            )
            .on("'enable'", fake::ok(""))
            .once("'show'", fake::ok("UnitFileState=enabled\n"))
            .on("'start'", fake::ok(""))
            .once("'show'", fake::ok(start));
        if up {
            f.once("'show'", fake::ok(start));
        }
        f.on("'stop'", fake::ok(""))
            .on("'reset-failed'", fake::ok(""))
            .once("'show'", fake::ok(after))
            .once("'show'", fake::ok("UnitFileState=enabled\n"))
            .on("'disable'", fake::ok(""))
            .once("'show'", fake::ok("UnitFileState=disabled\n"))
            .on("journalctl", fake::ok(""));
        f
    }

    #[test]
    fn a_healthy_daemon_cycles_through_every_step() {
        let mut p = pol();
        p.limits.stability_secs = 0;
        let mut f = scripted(
            "ActiveState=active\nSubState=running\nResult=success\nMainPID=5\nNRestarts=0\n",
            "ActiveState=inactive\nMainPID=0\n",
            true,
        );
        let mut ctx = Ctx {
            r: &mut f,
            policy: &p,
            nonce: "n1",
        };
        let c = cycle(&mut ctx, "chronyd.service", false);
        let names: Vec<(&str, &str)> = c
            .res
            .steps
            .iter()
            .map(|s| (s.name.as_str(), s.status.as_str()))
            .collect();
        assert_eq!(
            names,
            vec![
                ("enable", PASS),
                ("start", PASS),
                ("stays-up", PASS),
                ("stop", PASS),
                ("disable", PASS),
                ("journal", PASS)
            ],
            "{:?}",
            c.res.steps
        );
        assert_eq!(c.res.status, PASS);
        assert!(!c.session_lost);
        assert_eq!(f.ran("--after-cursor=s=1;i=2"), 2);
    }

    #[test]
    fn a_daemon_that_fails_and_logs_errors_fails_with_the_lines() {
        let mut p = pol();
        p.limits.stability_secs = 0;
        let mut f = scripted(
            "ActiveState=failed\nSubState=failed\nResult=exit-code\nExecMainCode=1\nExecMainStatus=1\n",
            "ActiveState=failed\nMainPID=0\n",
            false,
        );
        f.rules.retain(|r| r.needle != "journalctl");
        f.on(
            "journalctl",
            fake::ok(r#"{"_SYSTEMD_UNIT":"x.service","PRIORITY":"3","MESSAGE":"fatal: no config /etc/x.conf"}"#),
        );
        let mut ctx = Ctx {
            r: &mut f,
            policy: &p,
            nonce: "n2",
        };
        let c = cycle(&mut ctx, "x.service", false);
        assert_eq!(c.res.status, FAIL);
        let start = c.res.steps.iter().find(|s| s.name == "start").unwrap();
        assert_eq!(start.status, FAIL);
        assert!(
            start.detail.contains("Result=exit-code") && start.detail.contains("no config"),
            "{}",
            start.detail
        );
        assert_eq!(c.res.journal_errors.len(), 1);
        // a failed start's stop is information, not a second failure
        assert_eq!(
            c.res
                .steps
                .iter()
                .find(|s| s.name == "stop")
                .unwrap()
                .status,
            INFO
        );
    }

    #[test]
    fn a_declared_requires_config_failure_is_a_skip_with_evidence() {
        let mut p = pol();
        p.limits.stability_secs = 0;
        p.units.requires_config.push(crate::pkglife::policy::Rule {
            pattern: "x.service".into(),
            reason: "needs /etc/x.conf written by the operator".into(),
        });
        let mut f = scripted(
            "ActiveState=failed\nResult=exit-code\n",
            "ActiveState=inactive\nMainPID=0\n",
            false,
        );
        let mut ctx = Ctx {
            r: &mut f,
            policy: &p,
            nonce: "n3",
        };
        let c = cycle(&mut ctx, "x.service", false);
        let start = c.res.steps.iter().find(|s| s.name == "start").unwrap();
        assert_eq!(start.status, SKIP);
        assert!(start.detail.contains("declared"));
        assert_eq!(c.res.status, SKIP);
        assert_eq!(c.res.outcome, "needs configuration (declared)");
    }

    #[test]
    fn a_condition_skipped_unit_is_skipped_not_failed() {
        let mut p = pol();
        p.limits.stability_secs = 0;
        let mut f = scripted(
            "ActiveState=inactive\nConditionResult=no\nResult=success\n",
            "ActiveState=inactive\nMainPID=0\n",
            false,
        );
        let mut ctx = Ctx {
            r: &mut f,
            policy: &p,
            nonce: "n4",
        };
        let c = cycle(&mut ctx, "netconsole.service", false);
        assert_eq!(c.res.outcome, "skipped (condition)");
        assert_ne!(c.res.status, FAIL, "{:?}", c.res.steps);
    }

    #[test]
    fn a_firewall_that_cuts_ssh_is_rolled_back_and_failed() {
        let mut p = pol();
        p.limits.stability_secs = 0;
        p.limits.deadman_secs = 0;
        p.limits.reconnect_secs = 0;
        let mut f = scripted("ActiveState=active\nSubState=exited\n", "", true);
        f.on("sharukhan-deadman", fake::ok(""));
        f.reachable = false;
        let mut ctx = Ctx {
            r: &mut f,
            policy: &p,
            nonce: "n5",
        };
        let c = cycle(&mut ctx, "nftables.service", true);
        assert_eq!(c.res.status, FAIL);
        assert!(c.session_lost);
        assert_eq!(c.res.outcome, "cut the harness's ssh access");
        assert_eq!(f.ran("--on-active=0"), 1);
    }

    #[test]
    fn a_reachable_firewall_is_disarmed_and_tested() {
        let mut p = pol();
        p.limits.stability_secs = 0;
        let mut f = scripted(
            "ActiveState=active\nSubState=exited\nResult=success\nRemainAfterExit=yes\nMainPID=0\nNRestarts=0\n",
            "ActiveState=inactive\nMainPID=0\n",
            true,
        );
        f.on("sharukhan-deadman", fake::ok(""));
        let mut ctx = Ctx {
            r: &mut f,
            policy: &p,
            nonce: "n6",
        };
        let c = cycle(&mut ctx, "nftables.service", true);
        assert_eq!(c.res.status, PASS, "{:?}", c.res.steps);
        assert!(c
            .res
            .steps
            .iter()
            .any(|s| s.name == "ssh-after-start" && s.detail.contains("disarmed")));
        assert_eq!(
            f.ran("'systemctl' 'stop' '--' 'sharukhan-deadman-n6.timer'"),
            1
        );
    }

    #[test]
    fn preinstalled_units_are_observed_only() {
        let p = pol();
        let mut f = Fake::new();
        f.on(
            "'show'",
            fake::ok(
                "LoadState=loaded\nActiveState=active\nSubState=running\nUnitFileState=enabled\n",
            ),
        );
        let boot = vec![je(
            3,
            "systemd-resolved.service",
            "JENTROPY-ERROR: algif_rng_open():135",
        )];
        let r = observe(&mut f, "systemd-resolved.service", &p, &none(), &boot);
        assert_eq!(r.status, FAIL);
        assert_eq!(r.journal_errors.len(), 1);
        let r = observe(&mut f, "chronyd.service", &p, &none(), &boot);
        assert_eq!(r.status, PASS);
        assert!(f.ran("'start'") == 0 && f.ran("'stop'") == 0);
        let mut failed = BTreeSet::new();
        failed.insert("chronyd.service".to_string());
        assert_eq!(
            observe(&mut f, "chronyd.service", &p, &failed, &[]).status,
            FAIL
        );
    }

    #[test]
    fn the_ssh_unit_is_derived_from_the_listener() {
        let mut f = Fake::new();
        f.on(
            "ss -Hltnp",
            fake::ok("LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=812,fd=3))\n"),
        )
        .on(
            "/proc/812/cgroup",
            fake::ok("0::/system.slice/sshd.service\n"),
        );
        assert_eq!(ssh_listener_unit(&mut f, 5).unwrap(), "sshd.service");
        let mut g = Fake::new();
        g.on("ss -Hltnp", fake::ok(""));
        assert!(ssh_listener_unit(&mut g, 5).is_err());
        let mut h = Fake::new();
        h.on("ss -Hltnp", fake::rc(1, "", "ss: not found"));
        assert!(ssh_listener_unit(&mut h, 5).is_err());
    }
}
