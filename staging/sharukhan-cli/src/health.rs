//! The automation section of `sharukhan doctor`: everything an unattended
//! sync depends on that sharukhan cannot do for itself, checked from inside.
//!
//! sharukhan runs only once WSL is up; it cannot start WSL, register a Windows
//! task or log a user in. What it can do is say precisely which precondition
//! is missing: a boot unit that did not run, a mount that is not shared, a
//! watcher whose heartbeat stopped, a laptop on battery. Every check here is
//! read-only.

use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Ok,
    Warn,
    Fail,
}

#[derive(Debug, Clone)]
pub struct Item {
    pub label: String,
    pub level: Level,
    pub detail: String,
}

fn item(label: &str, level: Level, detail: impl Into<String>) -> Item {
    Item { label: label.into(), level, detail: detail.into() }
}

fn out(prog: &str, args: &[&str]) -> Option<String> {
    let o = Command::new(prog).args(args).output().ok()?;
    o.status.success().then(|| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

/// Seconds since the epoch of an ISO-8601 UTC stamp `YYYY-MM-DDTHH:MM:SSZ`.
pub fn epoch(ts: &str) -> Option<i64> {
    let b = ts.as_bytes();
    if b.len() != 20 || b[4] != b'-' || b[7] != b'-' || b[10] != b'T' || b[19] != b'Z' {
        return None;
    }
    let n = |r: std::ops::Range<usize>| ts.get(r)?.parse::<i64>().ok();
    let (y, m, d, hh, mm, ss) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?, n(17..19)?);
    // days from civil (Howard Hinnant)
    let y2 = if m <= 2 { y - 1 } else { y };
    let era = if y2 >= 0 { y2 } else { y2 - 399 } / 400;
    let yoe = y2 - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 86400 + hh * 3600 + mm * 60 + ss)
}

fn unit(name: &str, why: &str) -> Item {
    match out("systemctl", &["is-active", name]) {
        Some(s) if s == "active" => item(name, Level::Ok, format!("active ({why})")),
        _ => item(
            name,
            Level::Fail,
            format!("not active: {why}. `systemctl status {name}`; after a WSL restart it runs at boot"),
        ),
    }
}

/// Battery status from Windows: 2 is AC power, 1 discharging; no battery is a desktop.
pub fn power_level(status: &str) -> (Level, String) {
    match status.trim() {
        "none" => (Level::Ok, "no battery (mains)".into()),
        "2" => (Level::Ok, "on AC power".into()),
        "1" => (Level::Warn, "ON BATTERY: Windows sleeps after a few minutes; long stages would be cut".into()),
        other => (Level::Warn, format!("battery status {other} (not AC)")),
    }
}

pub fn automation(cfg: &crate::config::Config, watch_interval_s: i64) -> Vec<Item> {
    let memory_db = cfg.memory_db.as_path();
    let mut v = Vec::new();

    // the services as `sharukhan service install` writes them
    v.push(match crate::service::status(&crate::service::Paths { root: "/".into() }) {
        Ok((_, false)) => item("service files", Level::Ok, "as `sharukhan service install` writes them"),
        Ok((lines, true)) => item(
            "service files",
            Level::Warn,
            format!("{} (`sharukhan service status`)", lines.iter().filter(|l| l.contains("missing") || l.contains("differs")).cloned().collect::<Vec<_>>().join("; ")),
        ),
        Err(e) => item("service files", Level::Fail, e),
    });
    // host units the automation relies on
    v.push(unit("sharukhan-watch.service", "records upstream moves and PR changes"));
    v.push(unit("sharukhan-sync.timer", "starts a sync when the fork's base moved"));
    let builder = crate::builder::mode().unwrap_or(crate::builder::Mode::Host);
    if builder == crate::builder::Mode::Container {
        v.push(unit("photon-mc-gate-shared.service", "makes the builder's mounts reach the host"));
        let root = crate::builder::shared_root();
        v.push(match crate::builder::check_shared(&root) {
            Ok(()) => item("shared root", Level::Ok, format!("{} is a shared mount", root.display())),
            Err(e) => item("shared root", Level::Fail, e),
        });
        v.push(match crate::builder::current_image() {
            Ok((tag, true)) => item("builder image", Level::Ok, format!("{tag} is built for the current definition")),
            Ok((tag, false)) => item("builder image", Level::Warn, format!("{tag} not built yet; the next build builds it (`sharukhan builder ensure`)")),
            Err(e) => item("builder image", Level::Fail, e),
        });
    } else {
        v.push(item("builder", Level::Warn, "MC_BUILDER=host: make and the spec tools use the host's python3"));
    }

    // the watcher's liveness and what it found
    match crate::job::open_rw(memory_db) {
        Ok(c) => {
            let hb: Option<String> = c.query_row("SELECT at FROM heartbeat WHERE name = 'watch'", [], |r| r.get(0)).ok();
            let now = epoch(&crate::job::now());
            v.push(match (hb.as_deref().and_then(epoch), now) {
                (Some(t), Some(n)) if n - t <= 2 * watch_interval_s => {
                    item("watch heartbeat", Level::Ok, format!("{}s ago", n - t))
                }
                (Some(t), Some(n)) => item(
                    "watch heartbeat",
                    Level::Fail,
                    format!("{}s ago, more than twice the {watch_interval_s}s interval: the watcher is not cycling", n - t),
                ),
                _ => item("watch heartbeat", Level::Warn, "none recorded yet"),
            });
            let active: Option<(i64, String, String)> = c
                .query_row(
                    "SELECT id, state, coalesce(detail,'') FROM sync_run WHERE state IN ('running','paused','needs-decision','awaiting-approval') ORDER BY id DESC LIMIT 1",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .ok();
            v.push(match active {
                None => item("sync run", Level::Ok, "none active"),
                Some((id, st, d)) if st == "running" => item("sync run", Level::Ok, format!("run {id} running: {d}")),
                Some((id, st, d)) => item("sync run", Level::Warn, format!("run {id} {st}: {d}")),
            });
            let open: Vec<String> = c
                .prepare("SELECT kind || ' ' || subject FROM event WHERE state IN ('new','notified') ORDER BY id")
                .and_then(|mut s| s.query_map([], |r| r.get::<_, String>(0)).map(|rows| rows.flatten().collect()))
                .unwrap_or_default();
            v.push(if open.is_empty() {
                item("open events", Level::Ok, "none")
            } else {
                item("open events", Level::Warn, format!("{}: {}", open.len(), open.join("; ")))
            });
        }
        Err(e) => v.push(item("events", Level::Fail, e)),
    }

    // services the steps call
    v.push(match out("docker", &["version", "--format", "{{.Server.Version}}"]) {
        Some(s) => item("docker", Level::Ok, format!("daemon {s}")),
        None => item("docker", Level::Fail, "the docker daemon does not answer"),
    });
    // the variants file against the fork's open PRs
    v.push(match crate::variants::load(&cfg.variants_file) {
        Err(e) => item("variants", Level::Fail, e),
        Ok(vs) => match crate::sync::open_prs(&cfg.fork) {
            Err(e) => item("variants", Level::Warn, format!("could not list {}'s PRs: {e}", cfg.fork)),
            Ok(prs) => {
                let open: Vec<(u64, String, String)> = prs.into_iter().map(|p| (p.number, p.head_ref, p.base)).collect();
                let d = crate::variants::drift(&vs, &open, &cfg.release, &cfg.build_common);
                if d.not_open.is_empty() && d.unlisted.is_empty() {
                    item("variants", Level::Ok, "every listed branch is open, every open PR is covered")
                } else {
                    let mut parts: Vec<String> = d.not_open.iter().map(|b| format!("{b} not open")).collect();
                    parts.extend(d.unlisted.iter().map(|(n, h, _)| format!("#{n} {h} unlisted")));
                    item("variants", Level::Warn, format!("{} (`sharukhan variants`)", parts.join("; ")))
                }
            }
        },
    });
    // the check -> PR attribution against what is still open
    v.push(match crate::evidence::load_attribution(&cfg.check_prs) {
        Err(e) => item("check attribution", Level::Fail, e),
        Ok(attr) => {
            let open = |repo: &str| -> Option<Vec<u64>> { crate::sync::open_prs(repo).ok().map(|p| p.into_iter().map(|x| x.number).collect()) };
            match (open(&cfg.fork), open(&cfg.fork_installer)) {
                (Some(prs), Some(pois)) => {
                    let mut gone: Vec<String> = attr
                        .values()
                        .flat_map(|v| v.split(','))
                        .map(str::to_string)
                        .filter(|l| {
                            let (list, n) = match l.split_once('#') {
                                Some(("PR", n)) => (&prs, n),
                                Some(("POI", n)) => (&pois, n),
                                _ => return true,
                            };
                            n.parse::<u64>().map_or(true, |n| !list.contains(&n))
                        })
                        .collect();
                    gone.sort();
                    gone.dedup();
                    if gone.is_empty() {
                        item("check attribution", Level::Ok, format!("{} checks attributed, every PR open", attr.len()))
                    } else {
                        item("check attribution", Level::Warn, format!("not open any more: {} ({})", gone.join(" "), cfg.check_prs.display()))
                    }
                }
                _ => item("check attribution", Level::Warn, "could not list the open PRs"),
            }
        }
    });
    // the escalation a stopped sync is handed to: its key and today's budget
    v.push(match crate::escalate::enabled() {
        Err(e) => item("escalation", Level::Fail, e),
        Ok(false) => item("escalation", Level::Warn, "off (MC_ESCALATE=off): a stopped sync waits for a person"),
        Ok(true) => match crate::escalate::read_key().and_then(|k| crate::escalate::key_accepted(&k)) {
            Err(e) => item("escalation", Level::Fail, format!("{e}: a stopped sync parks its escalation")),
            Ok(()) => {
                let b = crate::escalate::Budget::from_env();
                let today: String = crate::job::now().chars().take(10).collect();
                let used: i64 = crate::job::open_rw(memory_db)
                    .ok()
                    .and_then(|c| {
                        crate::escalate::ensure_schema(&c).ok()?;
                        c.query_row("SELECT coalesce(sum(weighted),0) FROM escalation WHERE substr(started_at,1,10) = ?1", [&today], |r| r.get(0)).ok()
                    })
                    .unwrap_or(0);
                item("escalation", Level::Ok, format!("API key accepted; {used} of {} weighted tokens used today", b.per_day))
            }
        },
    });
    v.push(match out("timeout", &["20", "gh", "api", "rate_limit", "--jq", ".rate.remaining"]) {
        Some(s) => item("gh", Level::Ok, format!("authenticated, {s} API calls left this hour")),
        None => item("gh", Level::Fail, "gh cannot reach the API or is not logged in"),
    });

    // the host underneath
    if let Some(up) = std::fs::read_to_string("/proc/uptime").ok().and_then(|s| s.split_whitespace().next()?.parse::<f64>().ok()) {
        let h = (up / 3600.0) as i64;
        v.push(item("WSL uptime", Level::Ok, format!("{h}h {}m (a restart drops what the boot units do not restore)", ((up as i64) % 3600) / 60)));
    }
    let ps = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
    if Path::new(ps).exists() {
        let s = out(
            "timeout",
            &["30", ps, "-NoProfile", "-NonInteractive", "-Command", "$b=Get-CimInstance Win32_Battery; if ($b) { $b.BatteryStatus } else { 'none' }"],
        );
        v.push(match s {
            Some(s) => {
                let (l, d) = power_level(&s);
                item("Windows power", l, d)
            }
            None => item("Windows power", Level::Warn, "could not ask Windows (interop)"),
        });
    }
    v.push(if std::env::var("ANTHROPIC_API_KEY").map(|k| !k.is_empty()).unwrap_or(false) {
        item("ANTHROPIC_API_KEY", Level::Ok, "set (needed only for escalations)")
    } else {
        item("ANTHROPIC_API_KEY", Level::Warn, "not set in this environment: escalations would be parked")
    });
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stamps_convert_to_epoch_seconds() {
        assert_eq!(epoch("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(epoch("2026-10-23T17:24:25Z"), Some(1792776265));
        assert_eq!(epoch("2000-02-29T12:00:00Z"), Some(951825600));
        assert_eq!(epoch("2026-10-23 17:24:25"), None);
        assert_eq!(epoch("unknown"), None);
    }

    #[test]
    fn power_is_judged_by_windows_battery_status() {
        assert_eq!(power_level("2").0, Level::Ok);
        assert_eq!(power_level("none").0, Level::Ok);
        assert_eq!(power_level("1").0, Level::Warn);
        assert_eq!(power_level("3").0, Level::Warn);
    }
}
