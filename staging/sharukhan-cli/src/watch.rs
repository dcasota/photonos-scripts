//! `sharukhan watch`: notice what moved upstream, record it, say so once.
//!
//! The sync recipe used to start when someone looked: dcasota 5.0 moved twice
//! in one iteration and vmware moved seven commits (the kernel relocation to
//! SPECS/92 among them) while a gate was running, and each was found by hand.
//! This polls, writes one typed event per change into memory.db and sends one
//! line per event. It decides nothing else; the sync state machine reads the
//! events.
//!
//! * Branch heads come from `git ls-remote` (no API quota). A move is described
//!   by GitHub's compare (commits ahead, or "diverged" for a force push).
//! * Each watched pair (vmware branch, dcasota branch) is compared across the
//!   fork; a change of "commits ahead" is an event.
//! * Open and recently closed dcasota PRs are tracked by state, head and the
//!   number of comments and reviews.
//!
//! The first cycle records what it sees without an event per item (one
//! `watch-seeded` event), so starting the watcher does not flood the channel.
//! Notification channels come from MC_NOTIFY, comma-separated:
//! `file:<path>` (the default, /root/photon-mc/events.log), `ntfy:<url>`,
//! `gh-issue:<owner>/<repo>#<number>`. Nothing leaves the host unless a remote
//! channel is configured. An event stays `new` until every channel took it.

use rusqlite::Connection;
use std::process::Command;

pub const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS upstream_head (
    repo      TEXT NOT NULL,           -- owner/name, or a pseudo source (ahead:, pr:)
    ref       TEXT NOT NULL,           -- branch, pair or PR number
    value     TEXT NOT NULL,           -- sha, commits ahead, or PR state|head|comments|reviews
    seen_at   TEXT NOT NULL,
    PRIMARY KEY (repo, ref)
);
CREATE TABLE IF NOT EXISTS event (
    id          INTEGER PRIMARY KEY,
    at          TEXT NOT NULL,
    source      TEXT NOT NULL,         -- watch
    kind        TEXT NOT NULL,         -- see watch.rs KINDS
    subject     TEXT NOT NULL,
    old         TEXT,
    new         TEXT,
    detail      TEXT NOT NULL,
    state       TEXT NOT NULL DEFAULT 'new',   -- new | notified | handled | ignored
    notified_at TEXT,
    handled_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_event_state ON event(state);
CREATE TABLE IF NOT EXISTS heartbeat (
    name   TEXT PRIMARY KEY,
    at     TEXT NOT NULL,
    detail TEXT
);
";

/// The closed vocabulary of event kinds.
pub const KINDS: &[&str] = &[
    "watch-seeded",
    "upstream-moved",
    "reference-ahead",
    "reference-caught-up",
    "pr-head-moved",
    "pr-closed",
    "pr-merged",
    "pr-reopened",
    "pr-commented",
    "pr-reviewed",
    "watch-error",
    "watch-recovered",
    "sync-started",
    "sync-needs-decision",
    "sync-awaiting-approval",
    "sync-superseded",
    "sync-failed",
    "sync-done",
    "sync-description-edited",
    "spec-advisory",
    "sync-held",
    "escalation-proposed",
    "escalation-failed",
    "escalation-parked",
];

/// What is watched: branch heads, and (reference, fork) pairs.
pub struct Watch {
    pub heads: Vec<(String, String)>,
    pub pairs: Vec<((String, String), (String, String))>,
    pub pr_repos: Vec<String>,
}

/// The fork and its upstream on the release and common lines, and the
/// installer repositories, all from the configuration.
pub fn default_watch(cfg: &crate::config::Config) -> Watch {
    let h = |r: &str, b: &str| (r.to_string(), b.to_string());
    let (up, fork, rel, com) = (cfg.upstream.as_str(), cfg.fork.as_str(), cfg.release.as_str(), cfg.build_common.as_str());
    let (iup, ifork, ib) = (cfg.upstream_installer.as_str(), cfg.fork_installer.as_str(), cfg.installer_branch.as_str());
    Watch {
        heads: vec![h(up, rel), h(up, com), h(fork, rel), h(fork, com), h(iup, ib), h(ifork, ib)],
        pairs: vec![(h(up, rel), h(fork, rel)), (h(up, com), h(fork, com)), (h(iup, ib), h(ifork, ib))],
        pr_repos: vec![fork.to_string(), ifork.to_string()],
    }
}

fn run(prog: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(prog)
        .args(args)
        .output()
        .map_err(|e| format!("running {prog}: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "{prog} {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

pub fn ensure_schema(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(SCHEMA).map_err(|e| format!("event schema: {e}"))
}

fn remembered(conn: &Connection, repo: &str, r: &str) -> Option<String> {
    conn.query_row(
        "SELECT value FROM upstream_head WHERE repo = ?1 AND ref = ?2",
        rusqlite::params![repo, r],
        |row| row.get(0),
    )
    .ok()
}

fn remember(conn: &Connection, repo: &str, r: &str, value: &str) -> Result<(), String> {
    conn.execute(
        "INSERT INTO upstream_head (repo, ref, value, seen_at) VALUES (?1, ?2, ?3, ?4) \
         ON CONFLICT(repo, ref) DO UPDATE SET value = excluded.value, seen_at = excluded.seen_at",
        rusqlite::params![repo, r, value, crate::job::now()],
    )
    .map(|_| ())
    .map_err(|e| format!("upstream_head: {e}"))
}

pub fn record(
    conn: &Connection,
    kind: &str,
    subject: &str,
    old: Option<&str>,
    new: Option<&str>,
    detail: &str,
) -> Result<i64, String> {
    if !KINDS.contains(&kind) {
        return Err(format!("unknown event kind {kind}"));
    }
    conn.execute(
        "INSERT INTO event (at, source, kind, subject, old, new, detail) VALUES (?1, 'watch', ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![crate::job::now(), kind, subject, old, new, detail],
    )
    .map_err(|e| format!("event: {e}"))?;
    Ok(conn.last_insert_rowid())
}

/// The head of `branch` in `repo`, by `git ls-remote`.
pub fn head(repo: &str, branch: &str) -> Result<String, String> {
    let out = run(
        "git",
        &["ls-remote", &format!("https://github.com/{repo}.git"), &format!("refs/heads/{branch}")],
    )?;
    out.split_whitespace()
        .next()
        .filter(|s| s.len() == 40)
        .map(str::to_string)
        .ok_or_else(|| format!("{repo} has no branch {branch}"))
}

/// `(status, ahead_by)` of `head` relative to `base` (GitHub compare,
/// `owner:branch` or sha on either side).
pub fn compare(repo: &str, base: &str, head: &str) -> Result<(String, i64), String> {
    let out = run(
        "gh",
        &["api", &format!("repos/{repo}/compare/{base}...{head}"), "--jq", "[.status, .ahead_by] | @tsv"],
    )?;
    let mut f = out.trim().split('\t');
    let status = f.next().unwrap_or("").to_string();
    let ahead = f.next().and_then(|a| a.parse().ok()).ok_or_else(|| format!("compare {base}...{head}: {out}"))?;
    Ok((status, ahead))
}

/// One PR as tracked: state, head, comment and review counts.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PrState {
    pub state: String,
    pub head: String,
    pub comments: i64,
    pub reviews: i64,
}

impl PrState {
    pub fn encode(&self) -> String {
        format!("{}|{}|{}|{}", self.state, self.head, self.comments, self.reviews)
    }
    pub fn decode(s: &str) -> Option<PrState> {
        let f: Vec<&str> = s.split('|').collect();
        if f.len() != 4 {
            return None;
        }
        Some(PrState {
            state: f[0].into(),
            head: f[1].into(),
            comments: f[2].parse().ok()?,
            reviews: f[3].parse().ok()?,
        })
    }
}

/// The events a PR's change produces, in a stable order.
pub fn pr_events(old: &PrState, new: &PrState) -> Vec<(&'static str, String)> {
    let mut out = Vec::new();
    if old.state != new.state {
        let kind = match new.state.as_str() {
            "MERGED" => "pr-merged",
            "CLOSED" => "pr-closed",
            _ => "pr-reopened",
        };
        out.push((kind, format!("{} -> {}", old.state, new.state)));
    }
    if old.head != new.head {
        out.push(("pr-head-moved", format!("{} -> {}", short(&old.head), short(&new.head))));
    }
    if new.comments > old.comments {
        out.push(("pr-commented", format!("{} new comment(s)", new.comments - old.comments)));
    }
    if new.reviews > old.reviews {
        out.push(("pr-reviewed", format!("{} new review(s)", new.reviews - old.reviews)));
    }
    out
}

fn short(s: &str) -> &str {
    &s[..9.min(s.len())]
}

pub fn prs(repo: &str) -> Result<Vec<(i64, PrState)>, String> {
    let out = run(
        "gh",
        &[
            "pr", "list", "-R", repo, "--state", "all", "--limit", "200",
            "--json", "number,state,headRefOid,comments,reviews",
            "--jq", ".[] | [.number, .state, .headRefOid, (.comments|length), (.reviews|length)] | @tsv",
        ],
    )?;
    let mut v = Vec::new();
    for l in out.lines() {
        let f: Vec<&str> = l.split('\t').collect();
        if f.len() != 5 {
            continue;
        }
        let (Ok(n), Ok(c), Ok(r)) = (f[0].parse(), f[3].parse(), f[4].parse()) else { continue };
        v.push((n, PrState { state: f[1].into(), head: f[2].into(), comments: c, reviews: r }));
    }
    Ok(v)
}

/// One polling cycle. Returns the ids of the events it recorded.
pub fn cycle(conn: &Connection, w: &Watch) -> Result<Vec<i64>, String> {
    let seeded = conn
        .query_row("SELECT count(*) FROM upstream_head", [], |r| r.get::<_, i64>(0))
        .unwrap_or(0)
        > 0;
    let mut ids = Vec::new();
    let mut errors = Vec::new();
    let mut seen = 0;

    for (repo, branch) in &w.heads {
        match head(repo, branch) {
            Ok(sha) => {
                seen += 1;
                let old = remembered(conn, repo, branch);
                if let (true, Some(o)) = (seeded, old.as_deref()) {
                    if o != sha {
                        let what = match compare(repo, o, &sha) {
                            Ok((status, ahead)) => format!("{ahead} commit(s), {status}"),
                            Err(e) => format!("compare failed: {e}"),
                        };
                        ids.push(record(conn, "upstream-moved", &format!("{repo}:{branch}"), Some(o), Some(&sha), &what)?);
                    }
                }
                remember(conn, repo, branch, &sha)?;
            }
            Err(e) => errors.push(e),
        }
    }

    for ((rr, rb), (fr, fb)) in &w.pairs {
        let name = format!("{rr}:{rb}>{fr}:{fb}");
        let owner = rr.split('/').next().unwrap_or("");
        let fork_owner = fr.split('/').next().unwrap_or("");
        match compare(fr, &format!("{fork_owner}:{fb}"), &format!("{owner}:{rb}")) {
            Ok((status, ahead)) => {
                let old = remembered(conn, "ahead", &name).and_then(|v| v.parse::<i64>().ok());
                let changed = old != Some(ahead);
                if changed && (seeded || ahead > 0) {
                    let kind = if ahead > 0 { "reference-ahead" } else { "reference-caught-up" };
                    let detail = format!("{rr} {rb} is {ahead} commit(s) ahead of {fr} {fb} ({status})");
                    ids.push(record(
                        conn,
                        kind,
                        &name,
                        old.map(|o| o.to_string()).as_deref(),
                        Some(&ahead.to_string()),
                        &detail,
                    )?);
                }
                remember(conn, "ahead", &name, &ahead.to_string())?;
            }
            Err(e) => errors.push(e),
        }
    }

    for repo in &w.pr_repos {
        match prs(repo) {
            Ok(list) => {
                for (n, st) in list {
                    let key = format!("#{n}");
                    let src = format!("pr:{repo}");
                    let old = remembered(conn, &src, &key).and_then(|v| PrState::decode(&v));
                    if let (true, Some(o)) = (seeded, old.as_ref()) {
                        for (kind, detail) in pr_events(o, &st) {
                            ids.push(record(conn, kind, &format!("{repo}{key}"), None, None, &detail)?);
                        }
                    }
                    remember(conn, &src, &key, &st.encode())?;
                }
            }
            Err(e) => errors.push(e),
        }
    }

    if !seeded && seen > 0 {
        ids.push(record(conn, "watch-seeded", "watch", None, None, &format!("{seen} branch head(s) recorded"))?);
    }
    // An outage repeats the same error every cycle: record it when it changes,
    // and once when it clears, not every time.
    let errs = errors.join(" | ");
    let last = remembered(conn, "error", "watch").unwrap_or_default();
    if errs != last {
        if errs.is_empty() {
            ids.push(record(conn, "watch-recovered", "watch", None, None, &format!("cleared: {last}"))?);
        } else {
            ids.push(record(conn, "watch-error", "watch", None, None, &errs)?);
        }
        remember(conn, "error", "watch", &errs)?;
    }
    conn.execute(
        "INSERT INTO heartbeat (name, at, detail) VALUES ('watch', ?1, ?2) \
         ON CONFLICT(name) DO UPDATE SET at = excluded.at, detail = excluded.detail",
        rusqlite::params![crate::job::now(), format!("{} event(s) this cycle", ids.len())],
    )
    .map_err(|e| format!("heartbeat: {e}"))?;
    Ok(ids)
}

// --- notification ------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Channel {
    File(String),
    Ntfy(String),
    GhIssue { repo: String, number: u64 },
}

pub fn parse_channels(v: Option<&str>) -> Result<Vec<Channel>, String> {
    let v = v.map(str::trim).filter(|s| !s.is_empty()).unwrap_or("file:/root/photon-mc/events.log");
    let mut out = Vec::new();
    for c in v.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        let (k, rest) = c.split_once(':').ok_or_else(|| format!("MC_NOTIFY entry {c}: expected kind:target"))?;
        out.push(match k {
            "file" if rest.starts_with('/') => Channel::File(rest.into()),
            "ntfy" if rest.starts_with("https://") => Channel::Ntfy(rest.into()),
            "gh-issue" => {
                let (repo, n) = rest.split_once('#').ok_or_else(|| format!("{c}: expected gh-issue:owner/repo#number"))?;
                if repo.split('/').count() != 2 {
                    return Err(format!("{c}: expected gh-issue:owner/repo#number"));
                }
                Channel::GhIssue { repo: repo.into(), number: n.parse().map_err(|_| format!("{c}: bad issue number"))? }
            }
            _ => return Err(format!("MC_NOTIFY entry {c}: valid are file:/abs/path, ntfy:https://..., gh-issue:owner/repo#n")),
        });
    }
    Ok(out)
}

/// The one line an event is announced with.
pub fn line(at: &str, kind: &str, subject: &str, detail: &str) -> String {
    format!("{at} {kind} {subject}: {detail}")
}

fn send(ch: &Channel, text: &str) -> Result<(), String> {
    match ch {
        Channel::File(p) => {
            use std::io::Write;
            let mut f = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(p)
                .map_err(|e| format!("{p}: {e}"))?;
            writeln!(f, "{text}").map_err(|e| format!("{p}: {e}"))
        }
        Channel::Ntfy(url) => run("curl", &["-fsS", "-m", "20", "-d", text, url]).map(|_| ()),
        Channel::GhIssue { repo, number } => {
            run("gh", &["issue", "comment", &number.to_string(), "-R", repo, "--body", text]).map(|_| ())
        }
    }
}

/// Announce every `new` event on every channel; an event is marked notified
/// only when all channels took it, so a failed channel retries next cycle.
pub fn notify(conn: &Connection, channels: &[Channel]) -> Result<usize, String> {
    let mut stmt = conn
        .prepare("SELECT id, at, kind, subject, detail FROM event WHERE state = 'new' ORDER BY id")
        .map_err(|e| format!("event: {e}"))?;
    let rows: Vec<(i64, String, String, String, String)> = stmt
        .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)))
        .map_err(|e| format!("event: {e}"))?
        .filter_map(Result::ok)
        .collect();
    let mut sent = 0;
    for (id, at, kind, subject, detail) in rows {
        let text = line(&at, &kind, &subject, &detail);
        if channels.iter().all(|c| send(c, &text).is_ok()) {
            conn.execute(
                "UPDATE event SET state = 'notified', notified_at = ?1 WHERE id = ?2",
                rusqlite::params![crate::job::now(), id],
            )
            .map_err(|e| format!("event: {e}"))?;
            sent += 1;
        }
    }
    Ok(sent)
}

// --- CLI --------------------------------------------------------------------

/// `sharukhan watch [--once] [--interval <seconds>]` and
/// `sharukhan events [--new] | ack <id> | ignore <id>`.
pub fn cli(cmd: &str, args: &[String]) -> u8 {
    let cfg = crate::config::Config::load();
    let r = (|| -> Result<(), String> {
        let conn = crate::job::open_rw(&cfg.memory_db)?;
        ensure_schema(&conn)?;
        match cmd {
            "watch" => {
                let once = args.iter().any(|a| a == "--once");
                let interval: u64 = match args.iter().position(|a| a == "--interval") {
                    Some(i) => args
                        .get(i + 1)
                        .and_then(|v| v.parse().ok())
                        .filter(|v| *v >= 60)
                        .ok_or("--interval takes seconds, at least 60")?,
                    None => 900,
                };
                let channels = parse_channels(std::env::var("MC_NOTIFY").ok().as_deref())?;
                let w = default_watch(&cfg);
                loop {
                    let ids = cycle(&conn, &w)?;
                    let sent = notify(&conn, &channels)?;
                    println!("{} watch: {} event(s), {} notified", crate::job::now(), ids.len(), sent);
                    if once {
                        return Ok(());
                    }
                    std::thread::sleep(std::time::Duration::from_secs(interval));
                }
            }
            "events" => match args.first().map(String::as_str) {
                Some(op @ ("ack" | "ignore")) => {
                    let id: i64 = args.get(1).and_then(|v| v.parse().ok()).ok_or("events ack|ignore <id>")?;
                    let state = if op == "ack" { "handled" } else { "ignored" };
                    let n = conn
                        .execute(
                            "UPDATE event SET state = ?1, handled_at = ?2 WHERE id = ?3",
                            rusqlite::params![state, crate::job::now(), id],
                        )
                        .map_err(|e| format!("event: {e}"))?;
                    if n == 0 {
                        return Err(format!("no event {id}"));
                    }
                    println!("event {id}: {state}");
                    Ok(())
                }
                other => {
                    let only_open = other == Some("--new");
                    let sql = if only_open {
                        "SELECT id, at, kind, subject, detail, state FROM event WHERE state IN ('new','notified') ORDER BY id"
                    } else {
                        "SELECT id, at, kind, subject, detail, state FROM event ORDER BY id DESC LIMIT 50"
                    };
                    let mut stmt = conn.prepare(sql).map_err(|e| format!("event: {e}"))?;
                    let rows = stmt
                        .query_map([], |r| {
                            Ok(format!(
                                "{:>5} {:<9} {}",
                                r.get::<_, i64>(0)?,
                                r.get::<_, String>(5)?,
                                line(&r.get::<_, String>(1)?, &r.get::<_, String>(2)?, &r.get::<_, String>(3)?, &r.get::<_, String>(4)?)
                            ))
                        })
                        .map_err(|e| format!("event: {e}"))?;
                    for l in rows.flatten() {
                        println!("{l}");
                    }
                    Ok(())
                }
            },
            _ => Err(format!("unknown command {cmd}")),
        }
    })();
    match r {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("sharukhan {cmd}: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        ensure_schema(&c).unwrap();
        c
    }

    #[test]
    fn a_pr_change_is_described_by_every_field_that_changed() {
        let a = PrState { state: "OPEN".into(), head: "a".repeat(40), comments: 1, reviews: 0 };
        let mut b = a.clone();
        assert!(pr_events(&a, &b).is_empty());
        b.head = "b".repeat(40);
        b.comments = 3;
        b.state = "MERGED".into();
        let e = pr_events(&a, &b);
        assert_eq!(e.iter().map(|x| x.0).collect::<Vec<_>>(), vec!["pr-merged", "pr-head-moved", "pr-commented"]);
        assert_eq!(e[2].1, "2 new comment(s)");
        assert_eq!(PrState::decode(&b.encode()), Some(b));
        assert_eq!(PrState::decode("x|y"), None);
    }

    #[test]
    fn channels_default_to_a_local_file_and_refuse_anything_unclear() {
        assert_eq!(parse_channels(None).unwrap(), vec![Channel::File("/root/photon-mc/events.log".into())]);
        let c = parse_channels(Some("file:/tmp/e.log, ntfy:https://ntfy.example/t, gh-issue:dcasota/photon#7")).unwrap();
        assert_eq!(c[2], Channel::GhIssue { repo: "dcasota/photon".into(), number: 7 });
        assert!(parse_channels(Some("file:relative.log")).is_err());
        assert!(parse_channels(Some("ntfy:http://insecure")).is_err());
        assert!(parse_channels(Some("gh-issue:photon#x")).is_err());
        assert!(parse_channels(Some("mail:x")).is_err());
    }

    #[test]
    fn events_use_the_closed_vocabulary_and_notify_marks_only_delivered_ones() {
        let c = db();
        assert!(record(&c, "something-else", "s", None, None, "d").is_err());
        let id = record(&c, "upstream-moved", "vmware/photon:5.0", Some("a"), Some("b"), "2 commit(s), ahead").unwrap();
        let t = std::env::temp_dir().join(format!("shk-events-{}.log", std::process::id()));
        let _ = std::fs::remove_file(&t);
        let bad = vec![Channel::File(t.to_string_lossy().into()), Channel::File("/nonexistent-dir/x.log".into())];
        assert_eq!(notify(&c, &bad).unwrap(), 0);
        let state: String = c.query_row("SELECT state FROM event WHERE id = ?1", [id], |r| r.get(0)).unwrap();
        assert_eq!(state, "new", "a channel that failed must get the event again");
        assert_eq!(notify(&c, &[Channel::File(t.to_string_lossy().into())]).unwrap(), 1);
        let text = std::fs::read_to_string(&t).unwrap();
        assert!(text.contains("upstream-moved vmware/photon:5.0: 2 commit(s), ahead"), "{text}");
        assert_eq!(notify(&c, &[Channel::File(t.to_string_lossy().into())]).unwrap(), 0);
        let _ = std::fs::remove_file(&t);
    }

    #[test]
    fn an_outage_is_one_error_event_and_one_recovery_not_one_per_cycle() {
        let c = db();
        // a watch with only an unreachable head: every cycle fails the same way
        let w = Watch {
            heads: vec![("no-such-owner-zz/no-such-repo-zz".into(), "x".into())],
            pairs: vec![],
            pr_repos: vec![],
        };
        let errors = |c: &Connection| -> i64 {
            c.query_row("SELECT count(*) FROM event WHERE kind = 'watch-error'", [], |r| r.get(0)).unwrap()
        };
        cycle(&c, &w).unwrap();
        cycle(&c, &w).unwrap();
        assert_eq!(errors(&c), 1);
        let ok = Watch { heads: vec![], pairs: vec![], pr_repos: vec![] };
        cycle(&c, &ok).unwrap();
        let rec: i64 = c.query_row("SELECT count(*) FROM event WHERE kind = 'watch-recovered'", [], |r| r.get(0)).unwrap();
        assert_eq!(rec, 1);
        cycle(&c, &ok).unwrap();
        let rec2: i64 = c.query_row("SELECT count(*) FROM event WHERE kind = 'watch-recovered'", [], |r| r.get(0)).unwrap();
        assert_eq!(rec2, 1);
    }

    #[test]
    fn remembered_values_are_replaced_not_duplicated() {
        let c = db();
        remember(&c, "vmware/photon", "5.0", "a").unwrap();
        remember(&c, "vmware/photon", "5.0", "b").unwrap();
        assert_eq!(remembered(&c, "vmware/photon", "5.0").as_deref(), Some("b"));
        let n: i64 = c.query_row("SELECT count(*) FROM upstream_head", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1);
    }
}
