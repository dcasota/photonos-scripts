//! `sharukhan sync start | resume | status | approve | abort`: a 5.0 sync as a
//! resumable state machine in memory.db.
//!
//!   ANALYZE -> REBASE -> VERIFY -> PREPARE -> FASTLOOP -> GATE -> PUBLISH -> DONE
//!
//! Each stage is a row in `sync_stage` with its state, its evidence (a log
//! under results/sync/<run>/) and a detail line. The run is one row in
//! `sync_run`. Rules, from the Atlaso review and from this harness's own
//! failures:
//!
//! * One run at a time.
//! * Before every stage the inputs are re-checked: the fork's base heads and
//!   every PR head recorded by ANALYZE must still be what they were. If one
//!   moved the run stops ("superseded"); a new run starts from the new state.
//! * A stage left `running` by a process that is gone (a crash, a WSL restart)
//!   is `interrupted` and runs again on resume; every stage is idempotent.
//! * `abort` takes effect between stages, never inside PUBLISH.
//! * A refused rebase or a failed check stops the run as `needs-decision` -
//!   that is the input of the escalation (step 5), not something to retry.
//!   `sync decide` records the answer: a resolved candidate (checked to sit
//!   on its new parent) and, when the PR moves, the base it moves to on
//!   GitHub; `sync body --set` a description reviewed for the new change.
//!   Resuming keeps every PR already rebased or resolved, so candidates built
//!   on them stay valid, and retries only the rest.
//! * Nothing reaches GitHub before PUBLISH. Rebased heads live in the gate
//!   repository as sync/<run>/<branch>; PREPARE points the gate's branches at
//!   them so variant patches and builds use them, and records the old values.
//! * A branch an upstream PR is opened from is shared by both PRs, so PUBLISH
//!   pushes it, and every PR stacked on it, to staging/<branch> instead;
//!   STAGEVM checks the staged code is the gated code and installs
//!   MC_STAGED_ROWS from it; UPSTREAM checks both descriptions (the upstream
//!   one never names the fork) and a clean merge onto upstream's base, waits
//!   for `sync approve-upstream` whatever publish_dcasota says, then moves
//!   the shared branch and edits both descriptions in place.
//! * PUBLISH pushes with --force-with-lease against the PR heads ANALYZE saw,
//!   then puts each PR's description, carried to the new head by `prbody`,
//!   and checks GitHub shows both. With publish_dcasota=auto it goes ahead
//!   only when every description passes the lint; otherwise, and always with
//!   publish_dcasota=approve, it waits for `sync approve`. An approved push
//!   whose description fails the lint leaves that description as it was and
//!   says so: pushing code under a description that no longer matches it is
//!   not publishing, so that PR stays a decision.

use rusqlite::{Connection, OptionalExtension};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const STAGES: &[&str] = &["ANALYZE", "REBASE", "VERIFY", "PREPARE", "FASTLOOP", "GATE", "PUBLISH", "STAGEVM", "UPSTREAM", "DONE"];

pub const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS sync_run (
    id          INTEGER PRIMARY KEY,
    started_at  TEXT NOT NULL,
    state       TEXT NOT NULL,     -- running | paused | needs-decision | awaiting-approval | superseded | aborted | failed | done
    fork        TEXT NOT NULL,     -- owner/name of the fork on GitHub
    repo        TEXT NOT NULL,     -- the gate repository
    bases       TEXT NOT NULL,     -- root=old..new, comma separated
    publish     TEXT NOT NULL,     -- auto | approve | preview
    against     TEXT,              -- where the new bases come from: the fork, or another repository (preview)
    approved    INTEGER NOT NULL DEFAULT 0,
    abort       INTEGER NOT NULL DEFAULT 0,
    pid         INTEGER,
    detail      TEXT,
    finished_at TEXT
);
CREATE TABLE IF NOT EXISTS sync_stage (
    run_id      INTEGER NOT NULL REFERENCES sync_run(id),
    name        TEXT NOT NULL,
    state       TEXT NOT NULL,     -- pending | running | done | failed | skipped | interrupted
    started_at  TEXT,
    finished_at TEXT,
    evidence    TEXT,
    detail      TEXT,
    PRIMARY KEY (run_id, name)
);
CREATE TABLE IF NOT EXISTS sync_pr (
    run_id      INTEGER NOT NULL REFERENCES sync_run(id),
    number      INTEGER NOT NULL,
    branch      TEXT NOT NULL,
    root        TEXT NOT NULL,
    parent      TEXT,              -- the branch a stacked PR sits on
    gh_head     TEXT NOT NULL,     -- the lease: GitHub's head when ANALYZE ran
    action      TEXT NOT NULL,     -- keep | rebase
    new_head    TEXT,              -- sync/<run>/<branch> after REBASE
    state       TEXT NOT NULL,     -- pending | rebased | refused | resolved (by `sync decide`) | verified | failed | pushed (description unfit) | staged (on staging/<branch>, for the vmware stage) | published
    detail      TEXT,
    PRIMARY KEY (run_id, number)
);
";

pub fn ensure_schema(c: &Connection) -> Result<(), String> {
    c.execute_batch(SCHEMA).map_err(|e| format!("sync schema: {e}"))?;
    // added after the first runs: the repository the new bases come from
    let has: bool = c
        .prepare("SELECT 1 FROM pragma_table_info('sync_run') WHERE name = 'against'")
        .and_then(|mut s| s.exists([]))
        .map_err(sql)?;
    if !has {
        c.execute_batch("ALTER TABLE sync_run ADD COLUMN against TEXT").map_err(sql)?;
    }
    // added with `sync decide`: the base a PR moves to on GitHub
    let has: bool = c
        .prepare("SELECT 1 FROM pragma_table_info('sync_pr') WHERE name = 'base_to'")
        .and_then(|mut s| s.exists([]))
        .map_err(sql)?;
    if !has {
        c.execute_batch("ALTER TABLE sync_pr ADD COLUMN base_to TEXT").map_err(sql)?;
    }
    // added with the vmware stage: the upstream PR opened from the branch, and its approval
    // and with `sync start --rebase-all`: every PR moves to the new base, not only the ones it must
    for (table, col, decl) in [
        ("sync_pr", "upstream_pr", "INTEGER"),
        ("sync_run", "upstream_approved", "INTEGER NOT NULL DEFAULT 0"),
        ("sync_run", "rebase_all", "INTEGER NOT NULL DEFAULT 0"),
    ] {
        let has: bool = c
            .prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name = '{col}'"))
            .and_then(|mut s| s.exists([]))
            .map_err(sql)?;
        if !has {
            c.execute_batch(&format!("ALTER TABLE {table} ADD COLUMN {col} {decl}")).map_err(sql)?;
        }
    }
    Ok(())
}

fn sql(e: rusqlite::Error) -> String {
    format!("memory.db: {e}")
}

fn now() -> String {
    crate::job::now()
}

pub fn in_host_namespace() -> bool {
    match (fs::read_link("/proc/self/ns/mnt"), fs::read_link("/proc/1/ns/mnt")) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

fn pid_alive(pid: i64) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

/// Mark stages left `running` by a process that is gone as `interrupted`.
pub fn recover(c: &Connection, run: i64) -> Result<usize, String> {
    let pid: Option<i64> = c.query_row("SELECT pid FROM sync_run WHERE id = ?1", [run], |r| r.get(0)).map_err(sql)?;
    if pid.is_some_and(pid_alive) && pid != Some(std::process::id() as i64) {
        return Ok(0);
    }
    c.execute(
        "UPDATE sync_stage SET state = 'interrupted', finished_at = ?1, detail = coalesce(detail, '') || ' (process gone)' \
         WHERE run_id = ?2 AND state = 'running'",
        rusqlite::params![now(), run],
    )
    .map_err(sql)
}

fn set_stage(c: &Connection, run: i64, name: &str, state: &str, evidence: Option<&str>, detail: &str) -> Result<(), String> {
    let (start, end) = match state {
        "running" => (Some(now()), None),
        _ => (None, Some(now())),
    };
    c.execute(
        "UPDATE sync_stage SET state = ?1, started_at = coalesce(?2, started_at), finished_at = ?3, \
         evidence = coalesce(?4, evidence), detail = ?5 WHERE run_id = ?6 AND name = ?7",
        rusqlite::params![state, start, end, evidence, detail, run, name],
    )
    .map(|_| ())
    .map_err(sql)
}

fn set_run(c: &Connection, run: i64, state: &str, detail: &str) -> Result<(), String> {
    let fin = matches!(state, "done" | "aborted" | "superseded" | "failed").then(now);
    c.execute(
        "UPDATE sync_run SET state = ?1, detail = ?2, finished_at = coalesce(?3, finished_at) WHERE id = ?4",
        rusqlite::params![state, detail, fin, run],
    )
    .map(|_| ())
    .map_err(sql)
}

pub fn parse_bases(s: &str) -> Result<BTreeMap<String, (String, String)>, String> {
    let mut m = BTreeMap::new();
    for part in s.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        let (root, range) = part.split_once('=').ok_or_else(|| format!("{part}: expected root=old..new"))?;
        let (old, new) = range.split_once("..").ok_or_else(|| format!("{part}: expected root=old..new"))?;
        m.insert(root.to_string(), (old.to_string(), new.to_string()));
    }
    if m.is_empty() {
        return Err("no bases".into());
    }
    Ok(m)
}

fn git(repo: &Path, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git").arg("-C").arg(repo).args(args).output().map_err(|e| format!("git: {e}"))?;
    if !o.status.success() {
        return Err(format!("git {}: {}", args.join(" "), String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).trim().to_string())
}

// --- starting a run -----------------------------------------------------------

/// The last base a sync completed on, per root (`upstream_head` repo "synced").
pub fn synced_base(c: &Connection, root: &str) -> Option<String> {
    c.query_row("SELECT value FROM upstream_head WHERE repo = 'synced' AND ref = ?1", [root], |r| r.get(0)).ok()
}

pub fn start(c: &Connection, fork: &str, repo: &Path, roots: &[&str], publish: &str, against: Option<&str>, rebase_all: bool) -> Result<i64, String> {
    if let Ok((id, state)) = c.query_row(
        "SELECT id, state FROM sync_run WHERE state IN ('running', 'paused', 'needs-decision', 'awaiting-approval') ORDER BY id DESC LIMIT 1",
        [],
        |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
    ) {
        return Err(format!("sync run {id} is {state}; resume, approve or abort it first"));
    }
    if !matches!(publish, "auto" | "approve" | "preview") {
        return Err(format!("publish_dcasota={publish}: valid are auto and approve"));
    }
    let source = against.unwrap_or(fork);
    let publish = if source != fork { "preview" } else { publish };
    let mut parts = Vec::new();
    for root in roots {
        let old = synced_base(c, root).ok_or_else(|| {
            format!("no synced base recorded for {root}: record the base the PRs sit on with `sharukhan sync baseline {root} <sha>`")
        })?;
        let new = crate::watch::head(source, root)?;
        git(repo, &["fetch", "-q", &format!("https://github.com/{source}.git"), &format!("+refs/heads/{root}:refs/sync/base/{root}")])?;
        parts.push(format!("{root}={old}..{new}"));
    }
    c.execute(
        "INSERT INTO sync_run (started_at, state, fork, repo, bases, publish, pid, against, rebase_all) VALUES (?1, 'running', ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        rusqlite::params![now(), fork, repo.to_string_lossy(), parts.join(","), publish, std::process::id() as i64, source, rebase_all as i64],
    )
    .map_err(sql)?;
    let id = c.last_insert_rowid();
    for s in STAGES {
        c.execute("INSERT INTO sync_stage (run_id, name, state) VALUES (?1, ?2, 'pending')", rusqlite::params![id, s])
            .map_err(sql)?;
    }
    Ok(id)
}

// --- the input recheck ------------------------------------------------------

/// Still the state ANALYZE planned for? The fork's base heads and every PR head.
pub fn inputs_moved(c: &Connection, run: i64, fork: &str, bases: &BTreeMap<String, (String, String)>) -> Result<Option<String>, String> {
    let source: String = c
        .query_row("SELECT coalesce(against, fork) FROM sync_run WHERE id = ?1", [run], |r| r.get(0))
        .unwrap_or_else(|_| fork.to_string());
    for (root, (_, new)) in bases {
        let now_head = crate::watch::head(&source, root)?;
        if &now_head != new {
            return Ok(Some(format!("{source} {root} moved from {} to {}", &new[..9.min(new.len())], &now_head[..9])));
        }
    }
    // a PR this run pushed is expected at its new head
    let leases: Vec<(i64, String)> = c
        .prepare("SELECT number, CASE WHEN state IN ('pushed','published') THEN new_head ELSE gh_head END FROM sync_pr WHERE run_id = ?1")
        .and_then(|mut s| s.query_map([run], |r| Ok((r.get(0)?, r.get(1)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    if leases.is_empty() {
        return Ok(None);
    }
    let current: BTreeMap<u64, String> = crate::sync::open_prs(fork)?.into_iter().map(|p| (p.number, p.gh_head)).collect();
    for (n, lease) in leases {
        match current.get(&(n as u64)) {
            Some(h) if *h == lease => {}
            Some(h) => return Ok(Some(format!("PR #{n} moved on GitHub to {} since ANALYZE", &h[..9]))),
            None => return Ok(Some(format!("PR #{n} is no longer open"))),
        }
    }
    Ok(None)
}

// --- stages -------------------------------------------------------------------

struct Ctx<'a> {
    c: &'a Connection,
    run: i64,
    fork: String,
    repo: PathBuf,
    bases: BTreeMap<String, (String, String)>,
    dir: PathBuf,
    publish: String,
    upstream: String,
}

enum Outcome {
    Done(String),
    Skipped(String),
    NeedsDecision(String),
    Waiting(String),
    Failed(String),
}

fn child(ctx: &Ctx, name: &str, args: &[&str]) -> Result<bool, String> {
    let exe = std::env::current_exe().map_err(|e| format!("current_exe: {e}"))?;
    let log = ctx.dir.join(format!("{name}.log"));
    let f = fs::OpenOptions::new().create(true).append(true).open(&log).map_err(|e| format!("{}: {e}", log.display()))?;
    let g = f.try_clone().map_err(|e| format!("{e}"))?;
    let st = Command::new(exe)
        .args(args)
        .stdout(Stdio::from(f))
        .stderr(Stdio::from(g))
        .status()
        .map_err(|e| format!("sharukhan {}: {e}", args.join(" ")))?;
    Ok(st.success())
}

fn analyze(ctx: &Ctx) -> Result<Outcome, String> {
    let bases: BTreeMap<String, (String, String)> =
        ctx.bases.iter().map(|(k, (o, _))| (k.clone(), (o.clone(), format!("refs/sync/base/{k}")))).collect();
    let mut lines = Vec::new();
    let res = crate::sync::analyze(&ctx.repo, &ctx.fork, &bases, &mut |l| lines.push(l.to_string()))?;
    let prs = crate::sync::open_prs(&ctx.fork)?;
    ctx.c.execute("DELETE FROM sync_pr WHERE run_id = ?1", [ctx.run]).map_err(sql)?;
    let rebase_all: bool = ctx
        .c
        .query_row("SELECT rebase_all FROM sync_run WHERE id = ?1", [ctx.run], |r| r.get::<_, i64>(0))
        .map_err(sql)?
        != 0;
    let mut rebase = 0;
    for a in &res {
        let pr = prs.iter().find(|p| p.number == a.number).ok_or("PR vanished during analyze")?;
        let parent = crate::sync::root_base(pr, &prs, &bases.keys().map(String::as_str).collect::<Vec<_>>()).and_then(|x| x.1);
        let needs = needs_rebase(a, rebase_all);
        let verdict = if rebase_all && !needs_rebase(a, false) {
            format!("{}; rebased on request (--rebase-all)", crate::sync::verdict(a))
        } else {
            crate::sync::verdict(a).to_string()
        };
        if !a.in_sync {
            return Ok(Outcome::NeedsDecision(format!("PR #{} local head differs from GitHub: sync them first", a.number)));
        }
        rebase += needs as usize;
        ctx.c
            .execute(
                "INSERT INTO sync_pr (run_id, number, branch, root, parent, gh_head, action, state, detail) VALUES (?1,?2,?3,?4,?5,?6,?7,'pending',?8)",
                rusqlite::params![ctx.run, a.number as i64, a.head_ref, a.root, parent, pr.gh_head, if needs { "rebase" } else { "keep" }, verdict],
            )
            .map_err(sql)?;
        lines.push(format!("#{} {} {verdict}", a.number, a.head_ref));
    }
    // a PR stacked on one that is rebased must move with it
    loop {
        let n = ctx
            .c
            .execute(
                "UPDATE sync_pr SET action = 'rebase', detail = 'its parent is rebased' WHERE run_id = ?1 AND action = 'keep' \
                 AND parent IN (SELECT branch FROM sync_pr WHERE run_id = ?1 AND action = 'rebase')",
                [ctx.run],
            )
            .map_err(sql)?;
        if n == 0 {
            break;
        }
        rebase += n;
    }
    fs::write(ctx.dir.join("ANALYZE.log"), lines.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    Ok(Outcome::Done(format!("{} PR(s), {rebase} to rebase", res.len())))
}

/// A PR must move when it no longer merges or upstream touched its files; with
/// `--rebase-all` every PR moves, so each one sits on the new base.
fn needs_rebase(a: &crate::sync::Analysis, rebase_all: bool) -> bool {
    rebase_all || a.merge.is_err() || !a.touched.is_empty()
}

/// `sync start` takes these flags only: a typo or `--help` must not start a run.
const START_USAGE: &str = "sync start [--fork <owner/repo>] [--repo <git dir>] [--against <owner/repo>] [--until <stage>] [--rebase-all]";

fn check_start_args(args: &[String]) -> Result<(), String> {
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--fork" | "--repo" | "--against" | "--until" => {
                if args.get(i + 1).is_none_or(|v| v.starts_with("--")) {
                    return Err(format!("{} needs a value; usage: {START_USAGE}", args[i]));
                }
                i += 2;
            }
            "--rebase-all" => i += 1,
            other => return Err(format!("{other}: not an option of sync start; usage: {START_USAGE}")),
        }
    }
    Ok(())
}

/// Stack depth, so parents rebase before their children.
fn depth(branch: &str, rows: &[(i64, String, String, Option<String>)]) -> usize {
    let mut d = 0;
    let mut cur = branch.to_string();
    while let Some(p) = rows.iter().find(|r| r.1 == cur).and_then(|r| r.3.clone()) {
        d += 1;
        cur = p;
        if d > 30 {
            break;
        }
    }
    d
}

fn rebase_stage(ctx: &Ctx) -> Result<Outcome, String> {
    let who = crate::author::resolve(Some(&ctx.repo))?;
    let mut rows: Vec<(i64, String, String, Option<String>)> = ctx
        .c
        .prepare("SELECT number, branch, root, parent FROM sync_pr WHERE run_id = ?1 AND action = 'rebase' AND state NOT IN ('rebased', 'resolved')")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    if rows.is_empty() {
        let earlier: i64 = ctx
            .c
            .query_row("SELECT count(*) FROM sync_pr WHERE run_id = ?1 AND state IN ('rebased', 'resolved')", [ctx.run], |r| r.get(0))
            .map_err(sql)?;
        return Ok(if earlier > 0 {
            Outcome::Done(format!("{earlier} PR(s) rebased or resolved"))
        } else {
            Outcome::Skipped("nothing to rebase".into())
        });
    }
    let all: Vec<(i64, String, String, Option<String>)> = ctx
        .c
        .prepare("SELECT number, branch, root, parent FROM sync_pr WHERE run_id = ?1")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    rows.sort_by_key(|r| depth(&r.1, &all));
    let date = Command::new("date").args(["-u", "+%a %b %d %Y"]).output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
    let mut refused = Vec::new();
    let mut log = Vec::new();
    let mut stopped: Vec<String> = Vec::new();
    for (n, branch, root, parent) in &rows {
        // on top of a parent that could not move, a child cannot move either
        if let Some(p) = parent.as_ref().filter(|p| stopped.contains(p)) {
            let why = format!("blocked: its parent {p} was not rebased");
            ctx.c
                .execute("UPDATE sync_pr SET state = 'refused', detail = ?1 WHERE run_id = ?2 AND number = ?3", rusqlite::params![why, ctx.run, n])
                .map_err(sql)?;
            log.push(format!("#{n} {branch} {why}"));
            refused.push(format!("#{n}: {why}"));
            stopped.push(branch.clone());
            continue;
        }
        let (old_root, _) = &ctx.bases[root];
        let new_root = format!("refs/sync/base/{root}");
        let src = format!("refs/heads/{branch}");
        // a stacked PR moves onto its parent's new head; its own commits start at the old parent head
        let (own_base, new_base) = match parent {
            None => (git(&ctx.repo, &["merge-base", &src, old_root])?, new_root.clone()),
            Some(p) => {
                // the parent head the child is built on: its staging branch when
                // a sync published the child on a staged parent (sync::parent_head)
                let old_parent = crate::sync::parent_head(&ctx.repo, &ctx.fork, p, &src)?;
                let new_parent = git(&ctx.repo, &["rev-parse", "--verify", "-q", &format!("refs/heads/sync/{}/{p}", ctx.run)])
                    .unwrap_or_else(|_| old_parent.clone());
                (git(&ctx.repo, &["merge-base", &src, &old_parent])?, new_parent)
            }
        };
        let work = ctx.repo.join(format!(".sharukhan-sync-{}-{n}", ctx.run));
        match crate::sync::rebase(&ctx.repo, &src, &own_base, old_root, &new_base, &date, &work, parent.is_some(), &who) {
            Ok(r) => {
                let target = format!("sync/{}/{branch}", ctx.run);
                git(&ctx.repo, &["update-ref", &format!("refs/heads/{target}"), &r.head])?;
                ctx.c
                    .execute(
                        "UPDATE sync_pr SET new_head = ?1, state = 'rebased', detail = ?2 WHERE run_id = ?3 AND number = ?4",
                        rusqlite::params![r.head, r.releases.iter().map(|(f, v)| format!("{f} {v}")).collect::<Vec<_>>().join(", "), ctx.run, n],
                    )
                    .map_err(sql)?;
                log.push(format!("#{n} {branch} -> {target} {}", &r.head[..12]));
            }
            Err(e) => {
                ctx.c
                    .execute("UPDATE sync_pr SET state = 'refused', detail = ?1 WHERE run_id = ?2 AND number = ?3", rusqlite::params![e, ctx.run, n])
                    .map_err(sql)?;
                log.push(format!("#{n} {branch} REFUSED: {e}"));
                refused.push(format!("#{n}: {e}"));
                stopped.push(branch.clone());
            }
        }
    }
    fs::write(ctx.dir.join("REBASE.log"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    if refused.is_empty() {
        Ok(Outcome::Done(format!("{} PR(s) rebased", rows.len())))
    } else {
        Ok(Outcome::NeedsDecision(format!("{} rebase(s) refused: {}", refused.len(), refused.join("; "))))
    }
}

fn verify_stage(ctx: &Ctx) -> Result<Outcome, String> {
    let who = crate::author::resolve(Some(&ctx.repo))?.line();
    let rows: Vec<(i64, String, String)> = ctx
        .c
        .prepare("SELECT number, root, new_head FROM sync_pr WHERE run_id = ?1 AND state IN ('rebased', 'resolved', 'failed')")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    if rows.is_empty() {
        return Ok(Outcome::Skipped("nothing was rebased".into()));
    }
    let common = crate::builder::shared_root().join("work/common-check");
    let mut failed = Vec::new();
    let mut log = Vec::new();
    for (n, root, head) in &rows {
        let work = crate::builder::shared_root().join(format!("work/sync-verify-{}-{n}", ctx.run));
        let checks = crate::sync::verify(&ctx.repo, &format!("refs/sync/base/{root}"), head, &common, &work, &who, &mut |l| log.push(l.to_string()))?;
        let _ = fs::remove_dir_all(&work);
        let bad: Vec<String> = checks.iter().filter(|c| !c.ok).map(|c| format!("{} sr{} {}: {}", c.spec, c.subrelease, c.what, c.detail)).collect();
        log.push(format!("#{n}: {} check(s), {} failed", checks.len(), bad.len()));
        log.extend(bad.iter().map(|b| format!("  FAIL {b}")));
        log.extend(checks.iter().filter(|c| c.what == "check_spec advisory").map(|c| format!("  WARN {} sr{}: {}", c.spec, c.subrelease, c.detail)));
        let st = if bad.is_empty() { "verified" } else { "failed" };
        ctx.c.execute("UPDATE sync_pr SET state = ?1 WHERE run_id = ?2 AND number = ?3", rusqlite::params![st, ctx.run, n]).map_err(sql)?;
        if !bad.is_empty() {
            failed.push(format!("#{n}"));
        }
    }
    fs::write(ctx.dir.join("VERIFY.log"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    // advisory findings do not stop the run, but someone must hear of them
    let advisories: Vec<&String> = log.iter().filter(|l| l.starts_with("  WARN ")).collect();
    if !advisories.is_empty() {
        crate::escalate::record_once(
            ctx.c,
            "spec-advisory",
            &format!("sync run {}", ctx.run),
            &format!(
                "{} advisory spec check finding(s) a build does not stop for, e.g. {}; see VERIFY.log",
                advisories.len(),
                advisories[0].trim_start_matches("  WARN ")
            ),
        )?;
    }
    if failed.is_empty() {
        Ok(Outcome::Done(format!("{} PR(s) verified", rows.len())))
    } else {
        Ok(Outcome::NeedsDecision(format!("checks failed for {}", failed.join(" "))))
    }
}

/// Point the gate repository at the candidates and the new bases, keeping the
/// previous values beside the run so an abort can restore them.
fn prepare(ctx: &Ctx) -> Result<Outcome, String> {
    let mut saved = Vec::new();
    let mut moves: Vec<(String, String)> = ctx.bases.keys().map(|k| (k.clone(), format!("refs/sync/base/{k}"))).collect();
    let rows: Vec<(String, String)> = ctx
        .c
        .prepare("SELECT branch, new_head FROM sync_pr WHERE run_id = ?1 AND state = 'verified'")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    moves.extend(rows);
    for (branch, target) in &moves {
        let old = git(&ctx.repo, &["rev-parse", "--verify", "-q", &format!("refs/heads/{branch}")]).unwrap_or_default();
        let new = git(&ctx.repo, &["rev-parse", target])?;
        saved.push(format!("{branch}\t{old}"));
        git(&ctx.repo, &["update-ref", &format!("refs/heads/{branch}"), &new])?;
    }
    fs::write(ctx.dir.join("PREPARE.saved-refs.tsv"), saved.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    let cfg = crate::config::Config::load();
    for (tree, branch) in [(cfg.build_common.as_str(), cfg.build_common.as_str()), (cfg.release.as_str(), cfg.release.as_str())] {
        let dir = cfg.build_root.join(tree);
        if let Err(e) = reset_build_tree(&dir, &cfg.variant_patches, &ctx.repo, branch) {
            return Ok(Outcome::NeedsDecision(e));
        }
    }
    if !child(ctx, "PREPARE", &["variant-patches"])? {
        return Ok(Outcome::Failed("variant-patches failed, see PREPARE.log".into()));
    }
    Ok(Outcome::Done(format!("{} ref(s) pointed at the candidates; variant patches regenerated", moves.len())))
}

/// Files sharukhan's own fixups change in a build tree (buildmode::Fixup) and
/// the injections it writes; with the variant patches' files these are the
/// only dirty paths a build root may have.
const SHARUKHAN_WRITES: &[&str] = &[
    "build-config.json",
    "common/data/mc_pkg_build_options.json",
    "support/package-builder/run-in-chroot.sh",
    "SPECS/openjdk/",
    "SPECS/python3/python3.spec",
    "SPECS/sssd/sssd.spec",
    "SPECS/python3-setuptools/",
];

/// Paths a set of patches names, either side of every diff.
pub fn patch_paths(texts: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    for t in texts {
        for l in t.lines() {
            if let Some(rest) = l.strip_prefix("diff --git a/") {
                if let Some((a, b)) = rest.split_once(" b/") {
                    out.push(a.to_string());
                    out.push(b.to_string());
                }
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

/// Paths of `git status --porcelain` lines ("XY path", "XY old -> new").
pub fn porcelain_paths(text: &str) -> Vec<String> {
    text.lines()
        .filter(|l| l.len() > 3)
        .flat_map(|l| {
            let p = &l[3..];
            match p.split_once(" -> ") {
                Some((a, b)) => vec![a.trim_matches('"').to_string(), b.trim_matches('"').to_string()],
                None => vec![p.trim_matches('"').to_string()],
            }
        })
        .collect()
}

/// A dirty path is explained when a patch names it or sharukhan writes it.
pub fn unexplained(dirty: &[String], named: &[String]) -> Vec<String> {
    dirty
        .iter()
        .filter(|d| !named.contains(d) && !SHARUKHAN_WRITES.iter().any(|w| if w.ends_with('/') { d.starts_with(w) } else { d == w }))
        .cloned()
        .collect()
}

/// Verify the tree holds nothing but what a variant patch or sharukhan put
/// there, then clean it and fast-forward it to `branch` of the gate repository.
fn reset_build_tree(dir: &Path, patches: &Path, gate: &Path, branch: &str) -> Result<(), String> {
    let mounted = fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    if mounted.lines().any(|l| l.split(' ').nth(4).is_some_and(|m| m.starts_with(&dir.join("stage/photonroot").to_string_lossy().to_string()))) {
        return Err(format!("{}: a build sandbox is still mounted under the stage", dir.display()));
    }
    let texts: Vec<String> = fs::read_dir(patches)
        .map_err(|e| format!("{}: {e}", patches.display()))?
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "patch"))
        .filter_map(|e| fs::read_to_string(e.path()).ok())
        .collect();
    let named = patch_paths(&texts);
    // not through git(): its trim() would eat the first line's leading status column
    let o = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["status", "--porcelain", "--untracked-files=all"])
        .output()
        .map_err(|e| format!("git status: {e}"))?;
    if !o.status.success() {
        return Err(format!("git status in {}: {}", dir.display(), String::from_utf8_lossy(&o.stderr).trim()));
    }
    let dirty = porcelain_paths(&String::from_utf8_lossy(&o.stdout));
    let odd = unexplained(&dirty, &named);
    if !odd.is_empty() {
        return Err(format!(
            "{} has {} change(s) no variant patch or sharukhan fixup explains, e.g. {}: someone edited it; not cleaning",
            dir.display(),
            odd.len(),
            odd.iter().take(3).cloned().collect::<Vec<_>>().join(", ")
        ));
    }
    git(dir, &["clean", "-q", "-fd"])?;
    git(dir, &["checkout", "-q", "--", "."])?;
    git(dir, &["fetch", "-q", &gate.to_string_lossy(), branch])?;
    git(dir, &["merge", "-q", "--ff-only", "FETCH_HEAD"]).map_err(|e| format!("{}: not a fast-forward to the new {branch}: {e}", dir.display()))?;
    Ok(())
}

fn kernel_touched(ctx: &Ctx) -> Result<bool, String> {
    let rows: Vec<String> = ctx
        .c
        .prepare("SELECT new_head FROM sync_pr WHERE run_id = ?1 AND state = 'verified'")
        .and_then(|mut s| s.query_map([ctx.run], |r| r.get(0)).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    for h in rows {
        for (root, _) in &ctx.bases {
            let files = git(&ctx.repo, &["diff", "--name-only", &format!("refs/sync/base/{root}"), &h])?;
            if files.lines().any(|f| f.contains("/linux/") || f.starts_with("SPECS/linux")) {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

/// The fast-loop rows from MC_FASTLOOP_ROWS, read from the matrix: each must
/// be a minimal ISO of the default variant; its canister is the matrix's.
/// An equivalent-kernel row runs only when the sync touched a kernel spec.
pub fn fastloop_rows(cfg: &crate::config::Config, kernel: bool) -> Result<Vec<(String, String, String)>, String> {
    let matrix = crate::matrix::load(&cfg.matrix_tsv)?;
    let dflt = crate::variants::load(&cfg.variants_file)?.default_variant().name.clone();
    let mut out = Vec::new();
    for id in &cfg.fastloop_rows {
        let p = matrix.iter().find(|p| &p.id == id).ok_or_else(|| format!("MC_FASTLOOP_ROWS: {id} is not a row of {}", cfg.matrix_tsv.display()))?;
        if p.iso_type != "minimal" || p.poi != dflt {
            return Err(format!("MC_FASTLOOP_ROWS: {id} is {}/{}, not a minimal ISO of the default variant {dflt}", p.iso_type, p.poi));
        }
        if p.canister == "equivalent" && !kernel {
            continue;
        }
        out.push((id.clone(), p.poi.clone(), p.canister.clone()));
    }
    if out.is_empty() {
        return Err("MC_FASTLOOP_ROWS names no row to run".into());
    }
    Ok(out)
}

fn fastloop(ctx: &Ctx) -> Result<Outcome, String> {
    let cfg = crate::config::Config::load();
    let rows = fastloop_rows(&cfg, kernel_touched(ctx)?)?;
    for (row, poi, canister) in &rows {
        let (row, poi, canister) = (row.as_str(), poi.as_str(), canister.as_str());
        if !child(ctx, "FASTLOOP", &["build-iso", "--iso-type", "minimal", "--poi", poi, "--canister", canister, "--allow-build", "--force"])? {
            return Ok(Outcome::NeedsDecision(format!("minimal/{poi}/{canister} did not build, see FASTLOOP.log")));
        }
        let _ = child(ctx, "FASTLOOP", &["teardown", "--id", row]);
        for ph in ["create-vm", "install", "verify"] {
            if !child(ctx, "FASTLOOP", &[ph, "--id", row])? {
                return Ok(Outcome::NeedsDecision(format!("{row} failed at {ph}, see FASTLOOP.log")));
            }
        }
    }
    Ok(Outcome::Done(format!("{} fast-loop row(s) passed", rows.len())))
}

fn gate(ctx: &Ctx) -> Result<Outcome, String> {
    if child(ctx, "GATE", &["run", "--all", "--allow-build"])? {
        Ok(Outcome::Done("every admissible row passed".into()))
    } else {
        Ok(Outcome::NeedsDecision("the gate has failures, see GATE.log and the run's report".into()))
    }
}

/// The facts of PR `n` in this run: its root's bases, its parent's heads.
fn row_facts(ctx: &Ctx, n: i64) -> Result<crate::prbody::Facts, String> {
    let (root, old_head, new_head, parent): (String, String, String, Option<i64>) = ctx
        .c
        .query_row(
            "SELECT p.root, p.gh_head, p.new_head, (SELECT q.number FROM sync_pr q WHERE q.run_id = p.run_id AND q.branch = p.parent) \
             FROM sync_pr p WHERE p.run_id = ?1 AND p.number = ?2",
            rusqlite::params![ctx.run, n],
            |r| Ok((r.get(0)?, r.get(1)?, r.get::<_, Option<String>>(2)?.unwrap_or_default(), r.get(3)?)),
        )
        .map_err(sql)?;
    if new_head.is_empty() {
        return Err(format!("#{n} has no candidate in run {}", ctx.run));
    }
    let (old_base, _) = ctx.bases.get(&root).ok_or_else(|| format!("#{n}: root {root} is not a base of the run"))?;
    // a stacked PR's own commits start at its parent's head, before and after
    let own: Option<(String, String)> = match parent {
        None => None,
        Some(p) => ctx
            .c
            .query_row("SELECT gh_head, coalesce(new_head, gh_head) FROM sync_pr WHERE run_id = ?1 AND number = ?2", rusqlite::params![ctx.run, p], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .ok(),
    };
    crate::prbody::gather(
        &ctx.repo,
        old_base,
        &format!("refs/sync/base/{root}"),
        &old_head,
        &new_head,
        parent.map(|p| p as u64),
        own.as_ref().map(|(a, b)| (a.as_str(), b.as_str())),
    )
}

/// One PR's description carried to its new head: (current, carried, lint
/// problems). A reviewed description (`sync body --set`) replaces the carried
/// one; the review answers the change comparison, the rest of the lint holds.
fn carried_body(ctx: &Ctx, n: i64) -> Result<(String, String, Vec<String>), String> {
    let o = Command::new("gh")
        .args(["pr", "view", &n.to_string(), "-R", &ctx.fork, "--json", "body", "--jq", ".body"])
        .output()
        .map_err(|e| format!("gh pr view: {e}"))?;
    if !o.status.success() {
        return Err(format!("gh pr view {n}: {}", String::from_utf8_lossy(&o.stderr).trim()));
    }
    let current = String::from_utf8_lossy(&o.stdout).replace("\r\n", "\n").trim_end().to_string() + "\n";
    let mut facts = row_facts(ctx, n)?;
    let reviewed = ctx.dir.join("PUBLISH").join(format!("{n}.reviewed"));
    let carried = match fs::read_to_string(&reviewed) {
        Ok(text) => {
            facts.change_differs.clear();
            text
        }
        Err(_) => crate::prbody::rewrite(&current, &facts),
    };
    let problems = crate::prbody::lint(&carried, &facts);
    Ok((current, carried, problems))
}

fn put_body(ctx: &Ctx, n: i64, file: &Path, want: &str) -> Result<(), String> {
    let before = fs::read_to_string(file.with_extension("orig")).unwrap_or_default();
    let o = Command::new("gh")
        .args(["pr", "edit", &n.to_string(), "-R", &ctx.fork, "--body-file"])
        .arg(file)
        .output()
        .map_err(|e| format!("gh pr edit: {e}"))?;
    if !o.status.success() {
        return Err(format!("gh pr edit {n}: {}", String::from_utf8_lossy(&o.stderr).trim()));
    }
    let o = Command::new("gh").args(["pr", "view", &n.to_string(), "-R", &ctx.fork, "--json", "body", "--jq", ".body"]).output().map_err(|e| format!("{e}"))?;
    let got = String::from_utf8_lossy(&o.stdout).replace("\r\n", "\n");
    if got.trim_end() != want.trim_end() {
        return Err(format!("#{n}: GitHub shows a different description after the edit"));
    }
    let lines = before.lines().zip(want.lines()).filter(|(a, b)| a != b).count() + before.lines().count().abs_diff(want.lines().count());
    crate::watch::record(
        ctx.c,
        "sync-description-edited",
        &format!("{}#{n}", ctx.fork),
        None,
        None,
        &format!(
            "sync run {} carried the description ({lines} line(s): moved paths, Releases; the PR's own change is the same); \
             previous text in PUBLISH/{n}.orig, `sharukhan sync body --restore {} {n}` puts it back",
            ctx.run, ctx.run
        ),
    )?;
    Ok(())
}

/// Move a PR to the base `sync decide` gave it, and check GitHub shows it.
fn retarget(ctx: &Ctx, n: i64) -> Result<Option<String>, String> {
    let base: Option<String> = ctx
        .c
        .query_row("SELECT base_to FROM sync_pr WHERE run_id = ?1 AND number = ?2", rusqlite::params![ctx.run, n], |r| r.get(0))
        .map_err(sql)?;
    let Some(base) = base else { return Ok(None) };
    let view = || -> Result<String, String> {
        let o = Command::new("gh")
            .args(["pr", "view", &n.to_string(), "-R", &ctx.fork, "--json", "baseRefName", "--jq", ".baseRefName"])
            .output()
            .map_err(|e| format!("gh: {e}"))?;
        Ok(String::from_utf8_lossy(&o.stdout).trim().to_string())
    };
    if view()? != base {
        let o = Command::new("gh").args(["pr", "edit", &n.to_string(), "-R", &ctx.fork, "--base", &base]).output().map_err(|e| format!("gh: {e}"))?;
        if !o.status.success() {
            return Err(format!("gh pr edit {n} --base {base}: {}", String::from_utf8_lossy(&o.stderr).trim()));
        }
        if view()? != base {
            return Err(format!("#{n}: GitHub does not show base {base} after the edit"));
        }
    }
    Ok(Some(base))
}

fn publish(ctx: &Ctx, approved: bool) -> Result<Outcome, String> {
    // `pushed`: an earlier pass pushed the code and left an unfit description;
    // only the description is looked at again (someone may have rewritten it)
    let pushed: BTreeMap<i64, ()> = ctx
        .c
        .prepare("SELECT number FROM sync_pr WHERE run_id = ?1 AND state = 'pushed'")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, ()))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    let rows: Vec<(i64, String, String, String, String, Option<i64>)> = ctx
        .c
        .prepare(
            "SELECT p.number, p.branch, p.gh_head, p.new_head, p.root, (SELECT q.number FROM sync_pr q WHERE q.run_id = p.run_id AND q.branch = p.parent) \
             FROM sync_pr p WHERE p.run_id = ?1 AND p.state IN ('verified', 'pushed')",
        )
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    if rows.is_empty() {
        return Ok(Outcome::Skipped("nothing to publish".into()));
    }
    let bodies = ctx.dir.join("PUBLISH");
    fs::create_dir_all(&bodies).map_err(|e| format!("{}: {e}", bodies.display()))?;
    // a branch an upstream PR is opened from moves only in the UPSTREAM stage
    let pairs = upstream_pairs(&ctx.upstream, &ctx.fork)?;
    let parents: Vec<(i64, String, Option<String>)> = ctx
        .c
        .prepare("SELECT number, branch, parent FROM sync_pr WHERE run_id = ?1 AND state IN ('verified', 'pushed')")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    let hold = held(&parents, &pairs);
    let mut table = Vec::new();
    let mut plan = Vec::new();
    let mut unfit = 0;
    for (n, branch, lease, new, _root, _parent) in &rows {
        let (current, carried, problems) = carried_body(ctx, *n)?;
        let file = bodies.join(format!("{n}.body"));
        fs::write(&file, &carried).map_err(|e| format!("{}: {e}", file.display()))?;
        let orig = bodies.join(format!("{n}.orig"));
        if !orig.exists() {
            fs::write(&orig, &current).map_err(|e| format!("{}: {e}", orig.display()))?;
        }
        let changed = carried != current;
        let note = match (problems.is_empty(), changed) {
            (true, true) => "description carried (changed)".to_string(),
            (true, false) => "description unchanged".to_string(),
            (false, _) => format!("DESCRIPTION UNFIT: {}", problems.join("; ")),
        };
        unfit += !problems.is_empty() as usize;
        let staged = if hold.contains(n) {
            match pairs.get(branch) {
                Some(u) => format!(" -> staging/{branch}, upstream #{u} waits for the UPSTREAM stage"),
                None => format!(" -> staging/{branch}, stacked on a branch an upstream PR uses"),
            }
        } else {
            String::new()
        };
        table.push(format!("#{n} {branch} {}..{} {note}{staged}", &lease[..9], &new[..9]));
        plan.push((*n, branch.clone(), lease.clone(), new.clone(), file, carried, changed && problems.is_empty(), problems));
    }
    fs::write(ctx.dir.join("PUBLISH.table"), table.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    if !approved && (ctx.publish != "auto" || unfit > 0) {
        let why = if unfit > 0 {
            format!("{unfit} description(s) fail the lint")
        } else {
            "publish_dcasota=approve".to_string()
        };
        return Ok(Outcome::Waiting(format!(
            "{} push(es) prepared (PUBLISH.table, PUBLISH/<n>.body); {why}, so `sharukhan sync approve {}` is required",
            rows.len(),
            ctx.run
        )));
    }
    let url = format!("https://github.com/{}.git", ctx.fork);
    let mut log = Vec::new();
    let mut left = Vec::new();
    for (n, branch, lease, new, file, carried, put, problems) in &plan {
        if hold.contains(n) && !pushed.contains_key(n) {
            // the code goes to a branch no PR uses; both PRs move after the staged VM and approval
            let staging = format!("staging/{branch}");
            let old = remote_head(&ctx.fork, &staging)?.unwrap_or_default();
            let o = Command::new("git")
                .arg("-C")
                .arg(&ctx.repo)
                .args(["push", &format!("--force-with-lease=refs/heads/{staging}:{old}"), &url, &format!("{new}:refs/heads/{staging}")])
                .output()
                .map_err(|e| format!("git push: {e}"))?;
            if !o.status.success() {
                fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
                return Ok(Outcome::Failed(format!("push of #{n} to {staging} refused: {}", String::from_utf8_lossy(&o.stderr).trim())));
            }
            if remote_head(&ctx.fork, &staging)?.as_deref() != Some(new.as_str()) {
                fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
                return Ok(Outcome::Failed(format!("#{n}: GitHub does not show {staging} at {new} after the push")));
            }
            ctx.c
                .execute(
                    "UPDATE sync_pr SET state = 'staged', upstream_pr = ?1 WHERE run_id = ?2 AND number = ?3",
                    rusqlite::params![pairs.get(branch).map(|u| *u as i64), ctx.run, n],
                )
                .map_err(sql)?;
            log.push(format!("#{n} {branch} {}..{} staged on {staging}, verified on GitHub; the PR waits for the UPSTREAM stage", &lease[..9], &new[..9]));
            continue;
        }
        if pushed.contains_key(n) {
            if *put {
                if let Err(e) = put_body(ctx, *n, file, carried) {
                    fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
                    return Ok(Outcome::Failed(format!("#{n}: description not updated: {e}")));
                }
            }
            if problems.is_empty() {
                ctx.c.execute("UPDATE sync_pr SET state = 'published' WHERE run_id = ?1 AND number = ?2", rusqlite::params![ctx.run, n]).map_err(sql)?;
                log.push(format!("#{n} {branch} pushed earlier, description now fit"));
            } else {
                left.push(format!("#{n}"));
                log.push(format!("#{n} {branch} pushed earlier, description still unfit"));
            }
            continue;
        }
        let o = Command::new("git")
            .arg("-C")
            .arg(&ctx.repo)
            .args(["push", &format!("--force-with-lease=refs/heads/{branch}:{lease}"), &url, &format!("{new}:refs/heads/{branch}")])
            .output()
            .map_err(|e| format!("git push: {e}"))?;
        if !o.status.success() {
            fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
            return Ok(Outcome::Failed(format!("push of #{n} refused: {}", String::from_utf8_lossy(&o.stderr).trim())));
        }
        let mut gh = String::new();
        for _ in 0..6 {
            gh = crate::sync::open_prs(&ctx.fork)?.into_iter().find(|p| p.number as i64 == *n).map(|p| p.gh_head).unwrap_or_default();
            if &gh == new {
                break;
            }
            std::thread::sleep(std::time::Duration::from_secs(10));
        }
        if &gh != new {
            fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
            return Ok(Outcome::Failed(format!("#{n}: GitHub reports {gh} after the push, not {new}")));
        }
        let moved_to = match retarget(ctx, *n) {
            Ok(b) => b,
            Err(e) => {
                fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
                return Ok(Outcome::Failed(format!("#{n} pushed, base not moved: {e}")));
            }
        };
        if *put {
            if let Err(e) = put_body(ctx, *n, file, carried) {
                fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").ok();
                return Ok(Outcome::Failed(format!("#{n} pushed, description not updated: {e}")));
            }
        }
        if let Some(b) = &moved_to {
            log.push(format!("#{n} {branch} now based on {b}"));
        }
        let st = if problems.is_empty() { "published" } else { "pushed" };
        ctx.c.execute("UPDATE sync_pr SET state = ?1 WHERE run_id = ?2 AND number = ?3", rusqlite::params![st, ctx.run, n]).map_err(sql)?;
        let desc = if !problems.is_empty() {
            left.push(format!("#{n}"));
            "description left as it was (fails the lint)"
        } else if *put {
            "description updated"
        } else {
            "description unchanged"
        };
        log.push(format!("#{n} {branch} {}..{} verified on GitHub, {desc}", &lease[..9], &new[..9]));
    }
    fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    let staged = rows.iter().filter(|r| hold.contains(&r.0)).count();
    if left.is_empty() {
        Ok(Outcome::Done(format!("{} PR(s) pushed and verified, {staged} staged for the UPSTREAM stage", rows.len() - staged)))
    } else {
        Ok(Outcome::NeedsDecision(format!(
            "the descriptions of {} fail the lint (PUBLISH.table); rewrite them on GitHub, then `sharukhan sync resume {}`",
            left.join(" "),
            ctx.run
        )))
    }
}

// --- the upstream stage --------------------------------------------------------
//
// An upstream PR opened from a fork branch shares that branch with the fork's
// own PR: GitHub cannot give a PR another head, and its maintainers keep
// their conversation on the PR they have. So the branch is not pushed in
// PUBLISH. The code goes to staging/<branch>, a branch no PR uses; STAGEVM
// proves it on the staged VM; UPSTREAM waits for `sync approve-upstream`,
// then moves the shared branch - both PRs see the new code at that moment -
// and edits both descriptions in place, no comment and no new PR.

/// Open upstream PRs whose head is a branch of the fork: branch -> number.
pub fn parse_pairs(tsv: &str, owner: &str) -> BTreeMap<String, u64> {
    tsv.lines()
        .filter_map(|l| {
            let mut f = l.split('\t');
            let (n, who, head) = (f.next()?.parse().ok()?, f.next()?, f.next()?);
            (who.eq_ignore_ascii_case(owner) && !head.is_empty()).then(|| (head.to_string(), n))
        })
        .collect()
}

pub fn upstream_pairs(upstream: &str, fork: &str) -> Result<BTreeMap<String, u64>, String> {
    let owner = fork.split('/').next().filter(|o| !o.is_empty()).ok_or_else(|| format!("{fork}: not owner/name"))?;
    let o = Command::new("gh")
        .args(["pr", "list", "-R", upstream, "--state", "open", "--limit", "300", "--json", "number,headRepositoryOwner,headRefName"])
        .args(["--jq", ".[] | [.number, .headRepositoryOwner.login, .headRefName] | @tsv"])
        .output()
        .map_err(|e| format!("gh pr list -R {upstream}: {e}"))?;
    if !o.status.success() {
        return Err(format!("gh pr list -R {upstream}: {}", String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(parse_pairs(&String::from_utf8_lossy(&o.stdout), owner))
}

/// The PRs held for the upstream stage: those an upstream PR uses, and every
/// PR stacked on a held one - pushed now, a child would show its parent's new
/// commits on the fork before the parent itself moves.
pub fn held(rows: &[(i64, String, Option<String>)], pairs: &BTreeMap<String, u64>) -> std::collections::BTreeSet<i64> {
    let mut held: std::collections::BTreeSet<i64> = rows.iter().filter(|r| pairs.contains_key(&r.1)).map(|r| r.0).collect();
    loop {
        let before = held.len();
        for (n, _, parent) in rows {
            if let Some(p) = parent {
                if rows.iter().any(|r| &r.1 == p && held.contains(&r.0)) {
                    held.insert(*n);
                }
            }
        }
        if held.len() == before {
            return held;
        }
    }
}

/// A branch's head on the fork, none when it does not exist.
fn remote_head(fork: &str, branch: &str) -> Result<Option<String>, String> {
    let o = Command::new("git")
        .args(["ls-remote", &format!("https://github.com/{fork}.git"), &format!("refs/heads/{branch}")])
        .output()
        .map_err(|e| format!("git ls-remote: {e}"))?;
    if !o.status.success() {
        return Err(format!("git ls-remote {fork} {branch}: {}", String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).split_whitespace().next().filter(|h| h.len() == 40).map(str::to_string))
}

fn gh_pr_field(repo: &str, n: u64, field: &str) -> Result<String, String> {
    let o = Command::new("gh")
        .args(["pr", "view", &n.to_string(), "-R", repo, "--json", field, "--jq", &format!(".{field}")])
        .output()
        .map_err(|e| format!("gh pr view: {e}"))?;
    if !o.status.success() {
        return Err(format!("gh pr view {n} -R {repo}: {}", String::from_utf8_lossy(&o.stderr).trim()));
    }
    Ok(String::from_utf8_lossy(&o.stdout).replace("\r\n", "\n"))
}

/// What an upstream description may not say: the fork's owner, or a PR
/// number that is neither one of the upstream PRs of this fork nor already in
/// the description the maintainers have.
pub fn cross_org(text: &str, current: &str, owner: &str, allowed: &std::collections::BTreeSet<u64>) -> Vec<String> {
    let nums = |t: &str| -> Vec<u64> {
        let b = t.as_bytes();
        let mut v = Vec::new();
        for (i, _) in t.match_indices('#') {
            if i > 0 && (b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'&') {
                continue;
            }
            let d: String = t[i + 1..].chars().take_while(char::is_ascii_digit).collect();
            if let Ok(n) = d.parse() {
                v.push(n);
            }
        }
        v
    };
    let mut p = Vec::new();
    if text.to_lowercase().contains(&owner.to_lowercase()) {
        p.push(format!("names {owner}: an upstream description does not refer to the fork"));
    }
    let had = nums(current);
    let mut bad: Vec<u64> = nums(text).into_iter().filter(|n| !allowed.contains(n) && !had.contains(n)).collect();
    bad.sort();
    bad.dedup();
    if !bad.is_empty() {
        p.push(format!(
            "names {}: not an upstream PR of this fork, nor in the description upstream has",
            bad.iter().map(|n| format!("#{n}")).collect::<Vec<_>>().join(" ")
        ));
    }
    p
}

/// The rows waiting for the upstream stage, parents first.
fn staged_rows(ctx: &Ctx) -> Result<Vec<(i64, String, String, String, Option<u64>)>, String> {
    let mut rows: Vec<(i64, String, String, String, Option<u64>)> = ctx
        .c
        .prepare("SELECT number, branch, gh_head, new_head, upstream_pr FROM sync_pr WHERE run_id = ?1 AND state = 'staged'")
        .and_then(|mut s| {
            s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get::<_, Option<i64>>(4)?.map(|u| u as u64))))
                .map(|x| x.flatten().collect())
        })
        .map_err(sql)?;
    let all: Vec<(i64, String, String, Option<String>)> = ctx
        .c
        .prepare("SELECT number, branch, root, parent FROM sync_pr WHERE run_id = ?1")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    rows.sort_by_key(|r| depth(&r.1, &all));
    Ok(rows)
}

/// The staged code is the gated code, upstream's PR has not moved, and the
/// staged VM rows pass on it.
fn stagevm(ctx: &Ctx) -> Result<Outcome, String> {
    let rows = staged_rows(ctx)?;
    if rows.is_empty() {
        return Ok(Outcome::Skipped("no PR waits for the UPSTREAM stage".into()));
    }
    let mut log = Vec::new();
    for (n, branch, lease, new, up) in &rows {
        let staging = format!("staging/{branch}");
        if remote_head(&ctx.fork, &staging)?.as_deref() != Some(new.as_str()) {
            return Ok(Outcome::NeedsDecision(format!("#{n}: {staging} on GitHub is not the gated candidate {}", &new[..12])));
        }
        if let Some(u) = up {
            let head = gh_pr_field(&ctx.upstream, *u, "headRefOid")?;
            if head.trim() != lease {
                return Ok(Outcome::NeedsDecision(format!("{}#{u} moved to {} since ANALYZE: someone pushed to {branch}", ctx.upstream, head.trim())));
            }
        }
        log.push(format!("#{n} {staging} = {} (gated), upstream {}", &new[..12], up.map(|u| format!("#{u} unmoved")).unwrap_or_else(|| "none (stacked)".into())));
    }
    fs::write(ctx.dir.join("STAGEVM.checked"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    let cfg = crate::config::Config::load();
    let matrix = crate::matrix::load(&cfg.matrix_tsv)?;
    for id in &cfg.staged_rows {
        if !matrix.iter().any(|p| &p.id == id) {
            return Err(format!("MC_STAGED_ROWS: {id} is not a row of {}", cfg.matrix_tsv.display()));
        }
    }
    if cfg.staged_rows.is_empty() {
        return Err("MC_STAGED_ROWS names no row: the staged VM is how the UPSTREAM stage is earned".into());
    }
    let only = cfg.staged_rows.join(",");
    if child(ctx, "STAGEVM", &["run", "--only", &only, "--allow-build"])? {
        Ok(Outcome::Done(format!("{} staged PR(s) are the gated code; staged VM {only} passed", rows.len())))
    } else {
        Ok(Outcome::NeedsDecision(format!("the staged VM {only} failed, see STAGEVM.log")))
    }
}

/// An upstream PR's description carried to the new head: (current, carried,
/// problems). Facts of the whole change, as upstream sees it: no stack.
fn upstream_body(ctx: &Ctx, n: i64, up: u64, allowed: &std::collections::BTreeSet<u64>) -> Result<(String, String, Vec<String>), String> {
    let current = gh_pr_field(&ctx.upstream, up, "body")?.trim_end().to_string() + "\n";
    let (root, old_head, new_head): (String, String, String) = ctx
        .c
        .query_row("SELECT root, gh_head, new_head FROM sync_pr WHERE run_id = ?1 AND number = ?2", rusqlite::params![ctx.run, n], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .map_err(sql)?;
    let (old_base, _) = ctx.bases.get(&root).ok_or_else(|| format!("#{n}: root {root} is not a base of the run"))?;
    let mut facts = crate::prbody::gather(&ctx.repo, old_base, &format!("refs/sync/base/{root}"), &old_head, &new_head, None, None)?;
    let reviewed = ctx.dir.join("PUBLISH").join(format!("{n}.upstream.reviewed"));
    let carried = match fs::read_to_string(&reviewed) {
        Ok(text) => {
            facts.change_differs.clear();
            text
        }
        Err(_) => crate::prbody::rewrite(&current, &facts),
    };
    let owner = ctx.fork.split('/').next().unwrap_or(&ctx.fork);
    let mut problems = crate::prbody::lint(&carried, &facts);
    problems.extend(cross_org(&carried, &current, owner, allowed));
    Ok((current, carried, problems))
}

fn put_upstream_body(ctx: &Ctx, up: u64, file: &Path, want: &str) -> Result<(), String> {
    let o = Command::new("gh").args(["pr", "edit", &up.to_string(), "-R", &ctx.upstream, "--body-file"]).arg(file).output().map_err(|e| format!("gh pr edit: {e}"))?;
    if !o.status.success() {
        return Err(format!("gh pr edit {up} -R {}: {}", ctx.upstream, String::from_utf8_lossy(&o.stderr).trim()));
    }
    if gh_pr_field(&ctx.upstream, up, "body")?.trim_end() != want.trim_end() {
        return Err(format!("{}#{up}: GitHub shows a different description after the edit", ctx.upstream));
    }
    crate::watch::record(
        ctx.c,
        "sync-description-edited",
        &format!("{}#{up}", ctx.upstream),
        None,
        None,
        &format!("sync run {} updated the description in place; previous text in PUBLISH/<n>.upstream.orig", ctx.run),
    )?;
    Ok(())
}

/// Whether `head` merges cleanly onto the upstream PR's base: None when it
/// does, else the conflicting paths. Asked before anything is pushed.
fn upstream_conflicts(ctx: &Ctx, up: u64, head: &str) -> Result<Option<Vec<String>>, String> {
    let base = gh_pr_field(&ctx.upstream, up, "baseRefName")?.trim().to_string();
    let local = format!("refs/sync/upstream/{base}");
    git(&ctx.repo, &["fetch", "-q", &format!("https://github.com/{}.git", ctx.upstream), &format!("+refs/heads/{base}:{local}")])?;
    let o = Command::new("git")
        .arg("-C")
        .arg(&ctx.repo)
        .args(["merge-tree", "--write-tree", "--name-only", "--no-messages", &local, head])
        .output()
        .map_err(|e| format!("git merge-tree: {e}"))?;
    match o.status.code() {
        Some(0) => Ok(None),
        Some(1) => Ok(Some(String::from_utf8_lossy(&o.stdout).lines().skip(1).filter(|l| !l.is_empty()).map(str::to_string).collect())),
        _ => Err(format!("git merge-tree {local} {head}: {}", String::from_utf8_lossy(&o.stderr).trim())),
    }
}

/// GitHub's merge verdict for an upstream PR, once it has computed one.
fn mergeable(ctx: &Ctx, up: u64) -> Result<String, String> {
    let mut m = String::new();
    for _ in 0..12 {
        m = gh_pr_field(&ctx.upstream, up, "mergeable")?.trim().to_string();
        if m != "UNKNOWN" {
            break;
        }
        std::thread::sleep(std::time::Duration::from_secs(10));
    }
    Ok(m)
}

fn upstream_stage(ctx: &Ctx, approved: bool) -> Result<Outcome, String> {
    let rows = staged_rows(ctx)?;
    if rows.is_empty() {
        return Ok(Outcome::Skipped("no PR waits for the UPSTREAM stage".into()));
    }
    let bodies = ctx.dir.join("PUBLISH");
    fs::create_dir_all(&bodies).map_err(|e| format!("{}: {e}", bodies.display()))?;
    let allowed: std::collections::BTreeSet<u64> = upstream_pairs(&ctx.upstream, &ctx.fork)?.into_values().collect();
    let mut table = Vec::new();
    let mut plan = Vec::new();
    let mut unfit = Vec::new();
    for (n, branch, lease, new, up) in &rows {
        let (fork_now, fork_body, fork_problems) = carried_body(ctx, *n)?;
        let ffile = bodies.join(format!("{n}.body"));
        fs::write(&ffile, &fork_body).map_err(|e| format!("{}: {e}", ffile.display()))?;
        let forig = bodies.join(format!("{n}.orig"));
        if !forig.exists() {
            fs::write(&forig, &fork_now).map_err(|e| format!("{e}"))?;
        }
        let mut line = format!("#{n} {branch} {}..{}: fork description {}", &lease[..9], &new[..9], if fork_problems.is_empty() { "fit" } else { "UNFIT" });
        let mut problems: Vec<String> = fork_problems.iter().map(|p| format!("fork: {p}")).collect();
        let up_plan = match up {
            Some(u) => {
                let (now, body, p) = upstream_body(ctx, *n, *u, &allowed)?;
                let ufile = bodies.join(format!("{n}.upstream.body"));
                fs::write(&ufile, &body).map_err(|e| format!("{}: {e}", ufile.display()))?;
                let uorig = bodies.join(format!("{n}.upstream.orig"));
                if !uorig.exists() {
                    fs::write(&uorig, &now).map_err(|e| format!("{e}"))?;
                }
                line.push_str(&format!(
                    "; {}#{u} description {}",
                    ctx.upstream,
                    if !p.is_empty() { "UNFIT" } else if body != now { "carried (changed)" } else { "unchanged" }
                ));
                problems.extend(p.iter().map(|x| format!("upstream: {x}")));
                if let Some(paths) = upstream_conflicts(ctx, *u, new)? {
                    problems.push(format!("upstream: conflicts with {}#{u}'s base in {}", ctx.upstream, paths.join(", ")));
                }
                Some((*u, ufile, body.clone(), body != now))
            }
            None => None,
        };
        if !problems.is_empty() {
            line.push_str(&format!(" -- {}", problems.join("; ")));
            unfit.push(format!("#{n}: {}", problems.join("; ")));
        }
        table.push(line);
        plan.push((*n, branch.clone(), lease.clone(), new.clone(), ffile, fork_body.clone(), fork_body != fork_now, up_plan));
    }
    fs::write(ctx.dir.join("UPSTREAM.table"), table.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    if !unfit.is_empty() {
        return Ok(Outcome::NeedsDecision(format!(
            "nothing pushed; {} (UPSTREAM.table). A description: `sharukhan sync body --set {r} <pr> <file>` (fork) or \
             `sharukhan sync body --set-upstream {r} <pr> <file>` (upstream); a conflict: `sharukhan sync decide`; then `sharukhan sync resume {r}`",
            unfit.join(" | "),
            r = ctx.run
        )));
    }
    if !approved {
        return Ok(Outcome::Waiting(format!(
            "{} PR(s) staged and proven on the staged VM (UPSTREAM.table); `sharukhan sync approve-upstream {}` moves each shared \
             branch and updates both descriptions in place",
            rows.len(),
            ctx.run
        )));
    }
    let url = format!("https://github.com/{}.git", ctx.fork);
    let mut log = Vec::new();
    let mut conflicts = Vec::new();
    let fail = |log: &Vec<String>, why: String| -> Result<Outcome, String> {
        fs::write(ctx.dir.join("UPSTREAM.log"), log.join("\n") + "\n").ok();
        Ok(Outcome::Failed(why))
    };
    for (n, branch, lease, new, ffile, fbody, fput, up) in &plan {
        if let Some((u, ..)) = up {
            let head = gh_pr_field(&ctx.upstream, *u, "headRefOid")?;
            if head.trim() != lease {
                return fail(&log, format!("{}#{u} moved to {} since ANALYZE; nothing pushed for #{n}", ctx.upstream, head.trim()));
            }
        }
        let o = Command::new("git")
            .arg("-C")
            .arg(&ctx.repo)
            .args(["push", &format!("--force-with-lease=refs/heads/{branch}:{lease}"), &url, &format!("{new}:refs/heads/{branch}")])
            .output()
            .map_err(|e| format!("git push: {e}"))?;
        if !o.status.success() {
            return fail(&log, format!("push of #{n} refused: {}", String::from_utf8_lossy(&o.stderr).trim()));
        }
        // both PRs must show the new head
        let mut seen = (String::new(), String::new());
        for _ in 0..6 {
            seen.0 = gh_pr_field(&ctx.fork, *n as u64, "headRefOid")?.trim().to_string();
            seen.1 = match up {
                Some((u, ..)) => gh_pr_field(&ctx.upstream, *u, "headRefOid")?.trim().to_string(),
                None => new.clone(),
            };
            if &seen.0 == new && &seen.1 == new {
                break;
            }
            std::thread::sleep(std::time::Duration::from_secs(10));
        }
        if &seen.0 != new || &seen.1 != new {
            return fail(&log, format!("#{n}: GitHub shows {} (fork) and {} (upstream) after the push, not {new}", seen.0, seen.1));
        }
        if let Err(e) = retarget(ctx, *n) {
            return fail(&log, format!("#{n} pushed, base not moved: {e}"));
        }
        if *fput {
            if let Err(e) = put_body(ctx, *n, ffile, fbody) {
                return fail(&log, format!("#{n} pushed, fork description not updated: {e}"));
            }
        }
        let mut line = format!("#{n} {branch} {}..{} verified on GitHub", &lease[..9], &new[..9]);
        if let Some((u, ufile, ubody, uput)) = up {
            if *uput {
                if let Err(e) = put_upstream_body(ctx, *u, ufile, ubody) {
                    return fail(&log, format!("#{n} pushed, {}#{u} description not updated: {e}", ctx.upstream));
                }
            }
            let m = mergeable(ctx, *u)?;
            if m == "CONFLICTING" {
                conflicts.push(format!("{}#{u}", ctx.upstream));
            }
            line.push_str(&format!("; {}#{u} {}, {m}", ctx.upstream, if *uput { "description updated" } else { "description unchanged" }));
        }
        // the staging branch has done its job
        let staging = format!("staging/{branch}");
        let del = Command::new("git").arg("-C").arg(&ctx.repo).args(["push", &format!("--force-with-lease=refs/heads/{staging}:{new}"), &url, &format!(":refs/heads/{staging}")]).output();
        if !del.map(|o| o.status.success()).unwrap_or(false) {
            line.push_str(&format!("; {staging} not deleted"));
        }
        ctx.c.execute("UPDATE sync_pr SET state = 'published' WHERE run_id = ?1 AND number = ?2", rusqlite::params![ctx.run, n]).map_err(sql)?;
        log.push(line);
    }
    fs::write(ctx.dir.join("UPSTREAM.log"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    if conflicts.is_empty() {
        Ok(Outcome::Done(format!("{} PR(s) moved; every upstream PR mergeable", plan.len())))
    } else {
        Ok(Outcome::NeedsDecision(format!(
            "{} conflict with upstream's base: the code moved and the descriptions are updated, but upstream must rebase or the branch must be resolved",
            conflicts.join(" ")
        )))
    }
}

fn done(ctx: &Ctx) -> Result<Outcome, String> {
    record_synced(ctx.c, &ctx.bases)?;
    Ok(Outcome::Done("synced bases recorded".into()))
}

/// The new heads become the bases the next run measures from.
fn record_synced(c: &Connection, bases: &BTreeMap<String, (String, String)>) -> Result<(), String> {
    for (root, (_, new)) in bases {
        c.execute(
            "INSERT INTO upstream_head (repo, ref, value, seen_at) VALUES ('synced', ?1, ?2, ?3) \
             ON CONFLICT(repo, ref) DO UPDATE SET value = excluded.value, seen_at = excluded.seen_at",
            rusqlite::params![root, new, now()],
        )
        .map_err(sql)?;
    }
    Ok(())
}

/// What an abort keeps once PUBLISH is done: the published PRs sit on the new
/// bases on GitHub, so their gate refs and the base refs stay at the new heads,
/// and the new bases are recorded as synced (else the next run counts the
/// upstream commits under them as the PRs' own). Staged and unpublished PRs
/// did not move on GitHub and are restored. Before PUBLISH: nothing is kept.
fn kept_after_publish(c: &Connection, run: i64) -> Result<(Vec<String>, BTreeMap<String, (String, String)>), String> {
    let published: bool = c
        .prepare("SELECT 1 FROM sync_stage WHERE run_id = ?1 AND name = 'PUBLISH' AND state = 'done'")
        .and_then(|mut s| s.exists([run]))
        .map_err(sql)?;
    if !published {
        return Ok((Vec::new(), BTreeMap::new()));
    }
    let bases_s: String = c.query_row("SELECT bases FROM sync_run WHERE id = ?1", [run], |r| r.get(0)).map_err(sql)?;
    let bases = parse_bases(&bases_s)?;
    let mut keep: Vec<String> = c
        .prepare("SELECT branch FROM sync_pr WHERE run_id = ?1 AND state = 'published'")
        .and_then(|mut s| s.query_map([run], |r| r.get::<_, String>(0)).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    keep.extend(bases.keys().cloned());
    Ok((keep, bases))
}

/// Run the remaining stages of `run` until it finishes or stops.
pub fn drive(c: &Connection, run: i64, results: &Path, until: Option<&str>) -> Result<String, String> {
    recover(c, run)?;
    let (fork, repo, bases, approved, publish_mode, upstream_approved): (String, String, String, i64, String, i64) = c
        .query_row("SELECT fork, repo, bases, approved, publish, upstream_approved FROM sync_run WHERE id = ?1", [run], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))
        })
        .map_err(sql)?;
    c.execute("UPDATE sync_run SET pid = ?1, state = 'running' WHERE id = ?2", rusqlite::params![std::process::id() as i64, run]).map_err(sql)?;
    let ctx = Ctx {
        c,
        run,
        fork,
        repo: PathBuf::from(repo),
        bases: parse_bases(&bases)?,
        dir: results.join("sync").join(run.to_string()),
        publish: publish_mode,
        upstream: crate::config::Config::load().upstream,
    };
    fs::create_dir_all(&ctx.dir).map_err(|e| format!("{}: {e}", ctx.dir.display()))?;
    for name in STAGES {
        // a run started before a stage existed gets it, pending
        let state: String = match c
            .query_row("SELECT state FROM sync_stage WHERE run_id = ?1 AND name = ?2", rusqlite::params![run, name], |r| r.get(0))
            .optional()
            .map_err(sql)?
        {
            Some(s) => s,
            None => {
                c.execute("INSERT INTO sync_stage (run_id, name, state) VALUES (?1, ?2, 'pending')", rusqlite::params![run, name]).map_err(sql)?;
                "pending".to_string()
            }
        };
        if matches!(state.as_str(), "done" | "skipped") {
            continue;
        }
        let preview: bool = c
            .query_row("SELECT publish = 'preview' FROM sync_run WHERE id = ?1", [run], |r| r.get(0))
            .map_err(sql)?;
        if preview && *name == "PREPARE" {
            set_run(c, run, "done", "preview: stopped before PREPARE; candidates are in sync/<run>/<branch> of the gate repo, nothing built or published")?;
            return Ok("preview finished before PREPARE".into());
        }
        if until == Some(*name) {
            set_run(c, run, "paused", &format!("paused before {name} (--until); `sharukhan sync resume {run}` continues"))?;
            return Ok(format!("paused before {name}"));
        }
        let abort: i64 = c.query_row("SELECT abort FROM sync_run WHERE id = ?1", [run], |r| r.get(0)).map_err(sql)?;
        if abort != 0 {
            set_run(c, run, "aborted", &format!("aborted before {name}"))?;
            return Ok(format!("aborted before {name}"));
        }
        if *name != "ANALYZE" && *name != "DONE" {
            if let Some(why) = inputs_moved(c, run, &ctx.fork, &ctx.bases)? {
                set_run(c, run, "superseded", &why)?;
                return Ok(format!("superseded: {why}"));
            }
        }
        if matches!(*name, "FASTLOOP" | "GATE" | "STAGEVM") && !in_host_namespace() {
            return Err(format!("{name} builds and installs: run sharukhan in the host mount namespace (nsenter --target 1 --mount)"));
        }
        set_stage(c, run, name, "running", Some(&ctx.dir.to_string_lossy()), "")?;
        let out = match *name {
            "ANALYZE" => analyze(&ctx),
            "REBASE" => rebase_stage(&ctx),
            "VERIFY" => verify_stage(&ctx),
            "PREPARE" => prepare(&ctx),
            "FASTLOOP" => fastloop(&ctx),
            "GATE" => gate(&ctx),
            "PUBLISH" => publish(&ctx, approved != 0),
            "STAGEVM" => stagevm(&ctx),
            "UPSTREAM" => upstream_stage(&ctx, upstream_approved != 0),
            _ => done(&ctx),
        };
        match out {
            Ok(Outcome::Done(d)) => set_stage(c, run, name, "done", None, &d)?,
            Ok(Outcome::Skipped(d)) => set_stage(c, run, name, "skipped", None, &d)?,
            Ok(Outcome::NeedsDecision(d)) => {
                set_stage(c, run, name, "failed", None, &d)?;
                set_run(c, run, "needs-decision", &format!("{name}: {d}"))?;
                return Ok(format!("needs a decision at {name}: {d}"));
            }
            Ok(Outcome::Waiting(d)) => {
                set_stage(c, run, name, "pending", None, &d)?;
                set_run(c, run, "awaiting-approval", &d)?;
                return Ok(format!("waiting at {name}: {d}"));
            }
            Ok(Outcome::Failed(d)) | Err(d) => {
                set_stage(c, run, name, "failed", None, &d)?;
                set_run(c, run, "failed", &format!("{name}: {d}"))?;
                return Ok(format!("failed at {name}: {d}"));
            }
        }
    }
    set_run(c, run, "done", "every stage done")?;
    Ok("done".into())
}

/// Restore the gate repository refs PREPARE moved (abort, superseded).
pub fn restore_refs(results: &Path, run: i64, repo: &Path, keep: &[String]) -> Result<usize, String> {
    // the run's candidates go with it
    let cands = git(repo, &["for-each-ref", "--format=%(refname)", &format!("refs/heads/sync/{run}/")])?;
    for r in cands.lines().filter(|l| !l.is_empty()) {
        git(repo, &["update-ref", "-d", r])?;
    }
    let p = results.join("sync").join(run.to_string()).join("PREPARE.saved-refs.tsv");
    let Ok(text) = fs::read_to_string(&p) else { return Ok(0) };
    let mut n = 0;
    for l in text.lines() {
        let Some((branch, old)) = l.split_once('\t') else { continue };
        // published: GitHub already has the new head, and the gate ref must equal it
        if keep.iter().any(|k| k == branch) {
            continue;
        }
        if old.is_empty() {
            git(repo, &["update-ref", "-d", &format!("refs/heads/{branch}")])?;
        } else {
            git(repo, &["update-ref", &format!("refs/heads/{branch}"), old])?;
        }
        n += 1;
    }
    Ok(n)
}

/// The outcome of a drive as an event, so it reaches the same channels.
fn announce(c: &Connection, run: i64, outcome: &str) -> Result<(), String> {
    let kind = if outcome == "done" || outcome.starts_with("preview finished") {
        "sync-done"
    } else if outcome.starts_with("needs a decision") {
        "sync-needs-decision"
    } else if outcome.starts_with("waiting") {
        "sync-awaiting-approval"
    } else if outcome.starts_with("superseded") {
        "sync-superseded"
    } else if outcome.starts_with("paused") || outcome.starts_with("aborted") {
        return Ok(());
    } else {
        "sync-failed"
    };
    crate::watch::record(c, kind, &format!("sync run {run}"), None, None, outcome).map(|_| ())
}

/// Open fork PRs whose branch in the gate repository is not GitHub's head:
/// (number, branch, local head, GitHub head). Such a branch holds a change
/// not published yet (or GitHub moved on), and ANALYZE refuses the run for
/// it, so `sync auto` does not start one until they agree.
pub fn unpublished(local: &dyn Fn(&str) -> Option<String>, prs: &[crate::sync::Pr]) -> Vec<(u64, String, String, String)> {
    prs.iter()
        .filter_map(|p| {
            let l = local(&p.head_ref)?;
            (l != p.gh_head).then(|| (p.number, p.head_ref.clone(), l, p.gh_head.clone()))
        })
        .collect()
}

/// Seconds since an event's stamp, if it parses.
fn age_s(at: &str) -> Option<i64> {
    Some(crate::health::epoch(&now())? - crate::health::epoch(at)?)
}

/// `sync auto`: start a run when the fork's base moved and stayed quiet. A
/// run that stops for a decision goes to `escalate` (the escalation queue),
/// on this tick and on every later one while it waits, so a queue parked by
/// a budget or a rate limit is admitted again.
pub fn auto(
    c: &Connection,
    fork: &str,
    repo: &Path,
    roots: &[&str],
    results: &Path,
    quiet_s: i64,
    escalate: &mut dyn FnMut(i64) -> Result<Vec<String>, String>,
) -> Result<String, String> {
    if let Ok((id, state)) = c.query_row(
        "SELECT id, state FROM sync_run WHERE state IN ('running', 'paused', 'needs-decision', 'awaiting-approval') ORDER BY id DESC LIMIT 1",
        [],
        |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
    ) {
        if state == "needs-decision" {
            return Ok(format!("run {id} is needs-decision; escalation: {}", escalate(id)?.join("; ")));
        }
        return Ok(format!("run {id} is {state}; nothing started"));
    }
    let subjects: Vec<String> = roots.iter().map(|r| format!("{fork}:{r}")).collect();
    let moves: Vec<(i64, String)> = c
        .prepare(&format!(
            "SELECT id, at FROM event WHERE kind = 'upstream-moved' AND subject IN ({}) AND state IN ('new','notified') ORDER BY id",
            vec!["?"; subjects.len()].join(", ")
        ))
        .and_then(|mut s| s.query_map(rusqlite::params_from_iter(subjects.iter()), |r| Ok((r.get(0)?, r.get(1)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    let Some((_, last)) = moves.last() else { return Ok("the fork's bases did not move".into()) };
    if let Some(a) = age_s(last) {
        if a < quiet_s {
            return Ok(format!("the fork moved {a}s ago; waiting for {quiet_s}s of quiet"));
        }
    }
    // a change held in the gate repository and not on GitHub would stop ANALYZE
    let prs = crate::sync::open_prs(fork)?;
    let held = unpublished(&|b| git(repo, &["rev-parse", "--verify", "-q", &format!("refs/heads/{b}")]).ok(), &prs);
    if !held.is_empty() {
        let what = held
            .iter()
            .map(|(n, b, l, g)| format!("#{n} {b} (gate {} / GitHub {})", &l[..l.len().min(10)], &g[..g.len().min(10)]))
            .collect::<Vec<_>>()
            .join(", ");
        crate::escalate::record_once(
            c,
            "sync-held",
            &format!("{fork} sync"),
            &format!("no sync started: the gate repository and GitHub differ for {what}; publish the change or reset the gate branch to GitHub's head"),
        )?;
        return Ok(format!("the fork moved, but {} PR(s) differ between the gate repository and GitHub: {what}; the sync waits", held.len()));
    }
    // a gate or build run by hand owns the gate repository and the builder
    let jobs = crate::job::live(c)?;
    if !jobs.is_empty() {
        return Ok(format!("{} running; the sync waits for it", jobs.join(", ")));
    }
    if !in_host_namespace() {
        return Err("sync auto builds and installs: run it in the host mount namespace".into());
    }
    let publish = std::env::var("MC_PUBLISH_DCASOTA").unwrap_or_else(|_| "auto".into());
    let id = start(c, fork, repo, roots, &publish, None, false)?;
    for (e, _) in &moves {
        c.execute("UPDATE event SET state = 'handled', handled_at = ?1 WHERE id = ?2", rusqlite::params![now(), e]).map_err(sql)?;
    }
    crate::watch::record(c, "sync-started", &format!("sync run {id}"), None, None, &format!("{} fork move(s)", moves.len()))?;
    let out = drive(c, id, results, None)?;
    announce(c, id, &out)?;
    if out.starts_with("needs a decision") {
        return Ok(format!("run {id}: {out}; escalation: {}", escalate(id)?.join("; ")));
    }
    Ok(format!("run {id}: {out}"))
}

/// Record a resolved candidate for a PR the run could not rebase. The
/// candidate must sit on the new position of the base it will have: the
/// root's new base, or the parent's candidate in this run.
pub fn decide(c: &Connection, run: i64, n: i64, cand: &str, base_to: Option<&str>) -> Result<String, String> {
    let (state, repo, bases): (String, String, String) =
        c.query_row("SELECT state, repo, bases FROM sync_run WHERE id = ?1", [run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(sql)?;
    let roots = parse_bases(&bases)?;
    if !matches!(state.as_str(), "needs-decision" | "paused" | "awaiting-approval") {
        return Err(format!("run {run} is {state}: decisions are taken while it waits"));
    }
    let (branch, root, parent): (String, String, Option<String>) = c
        .query_row("SELECT branch, root, parent FROM sync_pr WHERE run_id = ?1 AND number = ?2", rusqlite::params![run, n], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .map_err(|_| format!("PR #{n} is not part of run {run}"))?;
    let repo = Path::new(&repo);
    let sha = git(repo, &["rev-parse", "--verify", &format!("{cand}^{{commit}}")])?;
    // the base the PR will have: a root, or another PR of this run
    let new_parent: Option<String> = match base_to {
        Some(b) if b == root || roots.contains_key(b) => None,
        Some(b) => Some(b.to_string()),
        None => parent.clone(),
    };
    let on = match &new_parent {
        None => format!("refs/sync/base/{root}"),
        Some(p) => {
            let st: String = c
                .query_row("SELECT state FROM sync_pr WHERE run_id = ?1 AND branch = ?2", rusqlite::params![run, p], |r| r.get(0))
                .map_err(|_| format!("{p} is not a PR branch of run {run}"))?;
            let r = format!("refs/heads/sync/{run}/{p}");
            if git(repo, &["rev-parse", "--verify", "-q", &r]).is_err() {
                return Err(format!("{p} ({st}) has no candidate in run {run} yet: decide it first"));
            }
            r
        }
    };
    let ok = Command::new("git").arg("-C").arg(repo).args(["merge-base", "--is-ancestor", &on, &sha]).status().map_err(|e| format!("git: {e}"))?;
    if !ok.success() {
        return Err(format!("{cand} does not sit on {on}"));
    }
    git(repo, &["update-ref", &format!("refs/heads/sync/{run}/{branch}"), &sha])?;
    c.execute(
        "UPDATE sync_pr SET new_head = ?1, state = 'resolved', parent = ?2, base_to = ?3, detail = ?4 WHERE run_id = ?5 AND number = ?6",
        rusqlite::params![sha, new_parent, base_to, format!("resolved by decision on {on}"), run, n],
    )
    .map_err(sql)?;
    Ok(format!("#{n} {branch}: candidate {} on {on}{}", &sha[..12], base_to.map(|b| format!(", base moves to {b}")).unwrap_or_default()))
}

pub fn cli(args: &[String]) -> Option<u8> {
    let sub = args.first().map(String::as_str)?;
    if !matches!(sub, "start" | "resume" | "status" | "approve" | "abort" | "baseline" | "auto" | "lint" | "body" | "decide" | "reset-trees" | "approve-upstream") {
        return None;
    }
    let cfg = crate::config::Config::load();
    let results = cfg.results_dir.clone();
    let r = (|| -> Result<String, String> {
        let c = crate::job::open_rw(&cfg.memory_db)?;
        crate::watch::ensure_schema(&c)?;
        ensure_schema(&c)?;
        let num = |i: usize| args.get(i).and_then(|v| v.parse::<i64>().ok()).ok_or("a run id is required");
        let until_arg = args.iter().position(|a| a == "--until").and_then(|i| args.get(i + 1)).map(|s| s.to_uppercase());
        if let Some(u) = &until_arg {
            if !STAGES.contains(&u.as_str()) {
                return Err(format!("--until {u}: valid are {}", STAGES.join(" ")));
            }
        }
        let until = until_arg.as_deref();
        let flag = |n: &str| args.iter().position(|a| a == n).and_then(|i| args.get(i + 1)).map(String::as_str);
        match sub {
            "reset-trees" => {
                // the build trees back to the gate repository's branches, as PREPARE does,
                // for a gate run by hand; refused while a run or job uses them
                let busy = crate::service::busy(&cfg.memory_db)?;
                if !busy.is_empty() {
                    return Err(format!("{} running; the build trees are in use", busy.join(", ")));
                }
                let mut done = Vec::new();
                for (tree, branch) in [(cfg.build_common.as_str(), cfg.build_common.as_str()), (cfg.release.as_str(), cfg.release.as_str())] {
                    let dir = cfg.build_root.join(tree);
                    reset_build_tree(&dir, &cfg.variant_patches, &cfg.gate_repo, branch)?;
                    done.push(format!("{} = {branch} {}", dir.display(), &git(&dir, &["rev-parse", "HEAD"])?[..12]));
                }
                Ok(format!("clean: {}; `sharukhan variant-patches` makes the patches against them", done.join(", ")))
            }
            "decide" => {
                let usage = "sync decide <run> <pr> candidate <ref> [--base <branch>]";
                let id = num(1)?;
                let n = num(2)?;
                if args.get(3).map(String::as_str) != Some("candidate") {
                    return Err(usage.into());
                }
                let cand = args.get(4).ok_or(usage)?;
                decide(&c, id, n, cand, flag("--base"))
            }
            "body" if args.get(1).map(String::as_str) == Some("--set") => {
                // a description reviewed for the new change; the lint still applies, except
                // the change comparison, which the review answers
                let id = num(2)?;
                let n = num(3)?;
                let file = args.get(4).ok_or("sync body --set <run> <pr> <file|proposed>")?;
                let run_dir = results.join("sync").join(id.to_string());
                let text = if file == "proposed" {
                    // the escalation's description, only for the proposal that became the candidate
                    let p = run_dir.join("PUBLISH").join(format!("{n}.proposed"));
                    let text = fs::read_to_string(&p).map_err(|e| format!("{}: {e}", p.display()))?;
                    let for_head = fs::read_to_string(p.with_extension("proposed.head")).unwrap_or_default();
                    let (state, head): (String, Option<String>) = c
                        .query_row("SELECT state, new_head FROM sync_pr WHERE run_id = ?1 AND number = ?2", rusqlite::params![id, n], |r| Ok((r.get(0)?, r.get(1)?)))
                        .map_err(|_| format!("PR #{n} is not part of run {id}"))?;
                    if state != "resolved" || head.as_deref() != Some(for_head.trim()) {
                        let of = |x: &str| if x.is_empty() { "no recorded proposal".to_string() } else { x.chars().take(12).collect() };
                        return Err(format!(
                            "#{n}: the proposed description was written for {}, the run's candidate is {} ({state}): decide that proposal first",
                            of(for_head.trim()),
                            of(head.as_deref().unwrap_or(""))
                        ));
                    }
                    text
                } else {
                    fs::read_to_string(file).map_err(|e| format!("{file}: {e}"))?
                };
                let (fork, repo, bases): (String, String, String) =
                    c.query_row("SELECT fork, repo, bases FROM sync_run WHERE id = ?1", [id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(sql)?;
                let ctx = Ctx {
                    c: &c,
                    run: id,
                    fork,
                    repo: PathBuf::from(repo),
                    bases: parse_bases(&bases)?,
                    dir: results.join("sync").join(id.to_string()),
                    publish: String::new(),
                    upstream: cfg.upstream.clone(),
                };
                let facts = row_facts(&ctx, n)?;
                let p = crate::prbody::lint(&text, &crate::prbody::Facts { change_differs: Vec::new(), ..facts });
                if !p.is_empty() {
                    return Err(format!("#{n}: the description fails the lint: {}", p.join("; ")));
                }
                let dir = ctx.dir.join("PUBLISH");
                fs::create_dir_all(&dir).map_err(|e| format!("{e}"))?;
                fs::write(dir.join(format!("{n}.reviewed")), &text).map_err(|e| format!("{e}"))?;
                Ok(format!("#{n}: reviewed description recorded for run {id}"))
            }
            "body" if args.get(1).map(String::as_str) == Some("--set-upstream") => {
                // a description reviewed for the upstream PR; the lint and the cross-org rule hold
                let id = num(2)?;
                let n = num(3)?;
                let file = args.get(4).ok_or("sync body --set-upstream <run> <pr> <file>")?;
                let text = fs::read_to_string(file).map_err(|e| format!("{file}: {e}"))?;
                let (fork, repo, bases): (String, String, String) =
                    c.query_row("SELECT fork, repo, bases FROM sync_run WHERE id = ?1", [id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(sql)?;
                let up: Option<i64> =
                    c.query_row("SELECT upstream_pr FROM sync_pr WHERE run_id = ?1 AND number = ?2", rusqlite::params![id, n], |r| r.get(0)).map_err(sql)?;
                let up = up.ok_or_else(|| format!("#{n} has no upstream PR in run {id}"))? as u64;
                let ctx = Ctx {
                    c: &c,
                    run: id,
                    fork,
                    repo: PathBuf::from(repo),
                    bases: parse_bases(&bases)?,
                    dir: results.join("sync").join(id.to_string()),
                    publish: String::new(),
                    upstream: cfg.upstream.clone(),
                };
                let dir = ctx.dir.join("PUBLISH");
                fs::create_dir_all(&dir).map_err(|e| format!("{e}"))?;
                let target = dir.join(format!("{n}.upstream.reviewed"));
                let allowed = upstream_pairs(&ctx.upstream, &ctx.fork)?.into_values().collect();
                // judged exactly as UPSTREAM will judge it
                let tmp = dir.join(format!("{n}.upstream.candidate"));
                fs::write(&tmp, &text).map_err(|e| format!("{e}"))?;
                let prev = fs::read(&target).ok();
                fs::rename(&tmp, &target).map_err(|e| format!("{e}"))?;
                let (_, _, problems) = upstream_body(&ctx, n, up, &allowed)?;
                if !problems.is_empty() {
                    match prev {
                        Some(b) => fs::write(&target, b).map_err(|e| format!("{e}"))?,
                        None => fs::remove_file(&target).map_err(|e| format!("{e}"))?,
                    }
                    return Err(format!("#{n}: the upstream description fails: {}", problems.join("; ")));
                }
                Ok(format!("#{n}: reviewed upstream description recorded for {}#{up} in run {id}", ctx.upstream))
            }
            "body" if args.get(1).map(String::as_str) == Some("--restore") => {
                // put back the description a sync replaced
                let id = num(2)?;
                let n = num(3)?;
                let fork: String = c.query_row("SELECT fork FROM sync_run WHERE id = ?1", [id], |r| r.get(0)).map_err(sql)?;
                let orig = results.join("sync").join(id.to_string()).join("PUBLISH").join(format!("{n}.orig"));
                let text = fs::read_to_string(&orig).map_err(|e| format!("{}: {e}", orig.display()))?;
                let o = Command::new("gh").args(["pr", "edit", &n.to_string(), "-R", &fork, "--body-file"]).arg(&orig).output().map_err(|e| format!("gh: {e}"))?;
                if !o.status.success() {
                    return Err(format!("gh pr edit {n}: {}", String::from_utf8_lossy(&o.stderr).trim()));
                }
                Ok(format!("#{n}: description of before run {id} restored ({} lines)", text.lines().count()))
            }
            "body" => {
                // a description carried to a candidate head, without publishing
                let usage = "sync body --pr <n> --old-base <rev> --new-base <rev> --new-head <rev> [--parent <n> --own-old <rev> --own-new <rev>] [--out <file>]\n       sync body --restore <run> <n>";
                let repo = flag("--repo").map(Path::new).unwrap_or(cfg.gate_repo.as_path());
                let n: u64 = flag("--pr").and_then(|v| v.parse().ok()).ok_or(usage)?;
                let pr = crate::sync::open_prs(&cfg.fork)?.into_iter().find(|p| p.number == n).ok_or("no such open PR")?;
                let parent = flag("--parent").and_then(|v| v.parse().ok());
                let facts = crate::prbody::gather(
                    repo,
                    flag("--old-base").ok_or(usage)?,
                    flag("--new-base").ok_or(usage)?,
                    &pr.gh_head,
                    flag("--new-head").ok_or(usage)?,
                    parent,
                    flag("--own-old").zip(flag("--own-new")),
                )?;
                let o = Command::new("gh").args(["pr", "view", &n.to_string(), "-R", &cfg.fork, "--json", "body", "--jq", ".body"]).output().map_err(|e| format!("gh: {e}"))?;
                let body = String::from_utf8_lossy(&o.stdout).replace("\r\n", "\n");
                let carried = crate::prbody::rewrite(&body, &facts);
                if let Some(out) = flag("--out") {
                    fs::write(out, &carried).map_err(|e| format!("{out}: {e}"))?;
                }
                let mut r = String::new();
                for (a, b) in &facts.releases {
                    r.push_str(&format!("release {a} -> {b}\n"));
                }
                let moved_lines = body.lines().zip(carried.lines()).filter(|(a, b)| a != b).count();
                r.push_str(&format!("{moved_lines} line(s) changed\n"));
                let p = crate::prbody::lint(&carried, &facts);
                r.push_str(&if p.is_empty() { "lint: ok".to_string() } else { format!("lint: {}", p.join("\n      ")) });
                Ok(r)
            }
            "lint" => {
                // the descriptions on GitHub against the heads they describe now
                let fork = cfg.fork.as_str();
                let repo = cfg.gate_repo.as_path();
                let only: Vec<u64> = args[1..].iter().filter_map(|a| a.trim_start_matches('#').parse().ok()).collect();
                let prs = crate::sync::open_prs(fork)?;
                let roots = [cfg.release.as_str(), cfg.build_common.as_str()];
                let mut out = String::new();
                let mut bad = 0;
                for pr in prs.iter().filter(|p| only.is_empty() || only.contains(&p.number)) {
                    let Some((root, parent)) = crate::sync::root_base(pr, &prs, &roots) else {
                        out.push_str(&format!("#{} base {} is not a sync root\n", pr.number, pr.base));
                        continue;
                    };
                    let parent_n = parent.as_ref().and_then(|b| prs.iter().find(|p| &p.head_ref == b)).map(|p| p.number);
                    let base = git(repo, &["rev-parse", &format!("refs/heads/{root}")])?;
                    let facts = crate::prbody::gather(repo, &base, &base, &pr.gh_head, &pr.gh_head, parent_n, None)?;
                    let o = Command::new("gh")
                        .args(["pr", "view", &pr.number.to_string(), "-R", fork, "--json", "body", "--jq", ".body"])
                        .output()
                        .map_err(|e| format!("gh: {e}"))?;
                    let body = String::from_utf8_lossy(&o.stdout).replace("\r\n", "\n");
                    let p = crate::prbody::lint(&body, &facts);
                    if p.is_empty() {
                        out.push_str(&format!("#{} ok\n", pr.number));
                    } else {
                        bad += 1;
                        out.push_str(&format!("#{} {}\n", pr.number, p.join("\n    ")));
                    }
                }
                out.push_str(&format!("{bad} description(s) fail the lint"));
                Ok(out)
            }
            "baseline" => {
                let root = args.get(1).ok_or("sync baseline <root> <sha>")?;
                let sha = args.get(2).ok_or("sync baseline <root> <sha>")?;
                c.execute(
                    "INSERT INTO upstream_head (repo, ref, value, seen_at) VALUES ('synced', ?1, ?2, ?3) \
                     ON CONFLICT(repo, ref) DO UPDATE SET value = excluded.value, seen_at = excluded.seen_at",
                    rusqlite::params![root, sha, now()],
                )
                .map_err(sql)?;
                Ok(format!("synced base of {root} recorded as {sha}"))
            }
            "start" => {
                check_start_args(&args[1..])?;
                let fork = flag("--fork").unwrap_or(cfg.fork.as_str());
                let repo = flag("--repo").map(PathBuf::from).unwrap_or_else(|| cfg.gate_repo.clone());
                let publish = std::env::var("MC_PUBLISH_DCASOTA").unwrap_or_else(|_| "auto".into());
                let against = args.iter().position(|a| a == "--against").and_then(|i| args.get(i + 1)).map(String::as_str);
                let rebase_all = args.iter().any(|a| a == "--rebase-all");
                let id = start(&c, fork, &repo, &[cfg.release.as_str(), cfg.build_common.as_str()], &publish, against, rebase_all)?;
                println!("sync run {id} started");
                let out = drive(&c, id, &results, until)?;
                announce(&c, id, &out)?;
                Ok(out)
            }
            "resume" => {
                let id = num(1)?;
                let out = drive(&c, id, &results, until)?;
                announce(&c, id, &out)?;
                Ok(out)
            }
            "auto" => {
                // --quiet, else SHARUKHAN_SYNC_QUIET (the service's setting), else two hours
                let quiet_s = args.iter().position(|a| a == "--quiet").and_then(|i| args.get(i + 1)).cloned().or_else(|| std::env::var("SHARUKHAN_SYNC_QUIET").ok());
                let quiet: i64 = match quiet_s {
                    Some(v) => v.trim().parse().ok().filter(|n: &i64| *n >= 0).ok_or_else(|| format!("quiet period {v}: a number of seconds"))?,
                    None => 7200,
                };
                let r = auto(&c, &cfg.fork, &cfg.gate_repo, &[cfg.release.as_str(), cfg.build_common.as_str()], &results, quiet, &mut |run| {
                    crate::escalate::queue(&cfg, run, &mut |l| eprintln!("{l}"))
                })?;
                let channels = crate::watch::parse_channels(std::env::var("MC_NOTIFY").ok().as_deref())?;
                crate::watch::notify(&c, &channels)?;
                Ok(r)
            }
            "approve" => {
                let id = num(1)?;
                c.execute("UPDATE sync_run SET approved = 1 WHERE id = ?1", [id]).map_err(sql)?;
                let out = drive(&c, id, &results, until)?;
                announce(&c, id, &out)?;
                Ok(out)
            }
            "approve-upstream" => {
                // always a person's decision, whatever publish_dcasota says
                let id = num(1)?;
                let waiting: i64 = c
                    .query_row("SELECT count(*) FROM sync_stage WHERE run_id = ?1 AND name = 'UPSTREAM' AND state = 'pending'", [id], |r| r.get(0))
                    .map_err(sql)?;
                let st: String = c.query_row("SELECT state FROM sync_run WHERE id = ?1", [id], |r| r.get(0)).map_err(sql)?;
                if waiting == 0 || st != "awaiting-approval" {
                    return Err(format!("run {id} is {st} and not waiting at UPSTREAM"));
                }
                c.execute("UPDATE sync_run SET upstream_approved = 1 WHERE id = ?1", [id]).map_err(sql)?;
                let out = drive(&c, id, &results, until)?;
                announce(&c, id, &out)?;
                Ok(out)
            }
            "abort" => {
                let id = num(1)?;
                c.execute("UPDATE sync_run SET abort = 1 WHERE id = ?1", [id]).map_err(sql)?;
                let state: String = c.query_row("SELECT state FROM sync_run WHERE id = ?1", [id], |r| r.get(0)).map_err(sql)?;
                let publishing: i64 = c
                    .query_row("SELECT count(*) FROM sync_stage WHERE run_id = ?1 AND name = 'PUBLISH' AND state = 'running'", [id], |r| r.get(0))
                    .map_err(sql)?;
                if publishing > 0 {
                    return Ok("abort recorded; PUBLISH is running and finishes first".into());
                }
                // staged code on the fork is not undone by an abort: say where it is
                let staged: Vec<String> = c
                    .prepare("SELECT branch FROM sync_pr WHERE run_id = ?1 AND state = 'staged'")
                    .and_then(|mut s| s.query_map([id], |r| r.get::<_, String>(0)).map(|x| x.flatten().map(|b| format!("staging/{b}")).collect()))
                    .map_err(sql)?;
                let note = if staged.is_empty() { String::new() } else { format!("; on the fork, no PR uses: {}", staged.join(" ")) };
                if state != "running" {
                    let repo: String = c.query_row("SELECT repo FROM sync_run WHERE id = ?1", [id], |r| r.get(0)).map_err(sql)?;
                    let (keep, bases) = kept_after_publish(&c, id)?;
                    let n = restore_refs(&results, id, Path::new(&repo), &keep)?;
                    let published = if keep.is_empty() {
                        String::new()
                    } else {
                        record_synced(&c, &bases)?;
                        format!(
                            "; {} published PR(s) and the bases ({}) kept at their new heads, synced bases recorded",
                            keep.len() - bases.len(),
                            bases.keys().cloned().collect::<Vec<_>>().join(", ")
                        )
                    };
                    set_run(&c, id, "aborted", &format!("aborted; {n} gate ref(s) restored{published}{note}"))?;
                }
                Ok(format!("run {id}: abort recorded{note}"))
            }
            _ => {
                let mut s = c
                    .prepare("SELECT id, started_at, state, bases, coalesce(detail,'') FROM sync_run ORDER BY id DESC LIMIT 5")
                    .map_err(sql)?;
                let runs: Vec<(i64, String, String, String, String)> =
                    s.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).map_err(sql)?.flatten().collect();
                let mut out = String::new();
                for (id, at, st, bases, d) in runs {
                    out.push_str(&format!("run {id} {at} {st} {bases}\n  {d}\n"));
                    let mut q = c.prepare("SELECT name, state, coalesce(detail,'') FROM sync_stage WHERE run_id = ?1 ORDER BY rowid").map_err(sql)?;
                    for row in q.query_map([id], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?))).map_err(sql)?.flatten() {
                        out.push_str(&format!("    {:<9} {:<12} {}\n", row.0, row.1, row.2));
                    }
                }
                Ok(if out.is_empty() { "no sync runs".into() } else { out })
            }
        }
    })();
    Some(match r {
        Ok(s) => {
            println!("{s}");
            0
        }
        Err(e) => {
            eprintln!("sharukhan sync: {e}");
            1
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        crate::watch::ensure_schema(&c).unwrap();
        ensure_schema(&c).unwrap();
        c
    }

    #[test]
    fn fastloop_rows_come_from_the_matrix_and_are_checked() {
        let d = std::env::temp_dir().join(format!("shk-fastloop-{}", std::process::id()));
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("m.tsv"), "k03 minimal 2.8 yes ext4 ks stigpkgs fails pass prebuilt\nc03 minimal 2.8 no ext4 ks fips untested pass equivalent\nf01 full 2.8 no ext4 ks none works pass prebuilt\nl01 minimal latest no ext4 ks none works pass prebuilt\n").unwrap();
        fs::write(d.join("v.conf"), "[variant 2.8]\nfix/poi-a\n[variant latest]\nfix/poi-b\n[common]\n").unwrap();
        let mut cfg = crate::config::Config::defaults();
        cfg.matrix_tsv = d.join("m.tsv");
        cfg.variants_file = d.join("v.conf");
        cfg.fastloop_rows = vec!["k03".into(), "c03".into()];
        let ids = |k: bool| fastloop_rows(&cfg, k).unwrap().into_iter().map(|r| format!("{}:{}", r.0, r.2)).collect::<Vec<_>>();
        assert_eq!(ids(true), vec!["k03:prebuilt", "c03:equivalent"]);
        assert_eq!(ids(false), vec!["k03:prebuilt"], "the equivalent kernel row runs only when a kernel spec changed");
        for (rows, why) in [(vec!["zz9"], "not a row"), (vec!["f01"], "not a minimal ISO"), (vec!["l01"], "not a minimal ISO of the default")] {
            cfg.fastloop_rows = rows.into_iter().map(String::from).collect();
            let e = fastloop_rows(&cfg, true).unwrap_err();
            assert!(e.contains(why), "{e}");
        }
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn bases_parse_and_refuse_garbage() {
        let b = parse_bases("5.0=a..refs/x,common=b..c").unwrap();
        assert_eq!(b["5.0"], ("a".to_string(), "refs/x".to_string()));
        assert!(parse_bases("5.0=a").is_err());
        assert!(parse_bases("").is_err());
    }

    #[test]
    fn a_stage_of_a_dead_process_is_interrupted_and_runs_again() {
        let c = db();
        c.execute(
            "INSERT INTO sync_run (id, started_at, state, fork, repo, bases, publish, pid) VALUES (1, 't', 'running', 'f', '/r', '5.0=a..b', 'approve', 999999999)",
            [],
        )
        .unwrap();
        for s in STAGES {
            c.execute("INSERT INTO sync_stage (run_id, name, state) VALUES (1, ?1, 'pending')", [s]).unwrap();
        }
        set_stage(&c, 1, "GATE", "running", None, "").unwrap();
        assert_eq!(recover(&c, 1).unwrap(), 1);
        let st: String = c.query_row("SELECT state FROM sync_stage WHERE run_id = 1 AND name = 'GATE'", [], |r| r.get(0)).unwrap();
        assert_eq!(st, "interrupted");
    }

    /// An abort after PUBLISH keeps what GitHub already has: the published PR
    /// and the base stay at their new heads and the new base is recorded as
    /// synced; a staged PR, which did not move on GitHub, is restored.
    #[test]
    fn an_abort_after_publish_keeps_the_published_heads_and_records_the_base() {
        let d = std::env::temp_dir().join(format!("shk-abort-pub-{}-{}", std::process::id(), crate::job::stamp()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        let g = |a: &[&str]| -> String {
            let o = Command::new("git").arg("-C").arg(&d).args(a).output().unwrap();
            assert!(o.status.success(), "{a:?}: {}", String::from_utf8_lossy(&o.stderr));
            String::from_utf8_lossy(&o.stdout).trim().to_string()
        };
        g(&["init", "-q", "-b", "5.0"]);
        g(&["config", "user.email", "a@b"]);
        g(&["config", "user.name", "A B"]);
        g(&["commit", "-q", "--allow-empty", "-m", "old"]);
        let old = g(&["rev-parse", "HEAD"]);
        g(&["commit", "-q", "--allow-empty", "-m", "new"]);
        let new = g(&["rev-parse", "HEAD"]);
        for b in ["fix/pub", "fix/staged"] {
            g(&["branch", b, &new]);
        }
        let results = d.join("results");
        fs::create_dir_all(results.join("sync/1")).unwrap();
        fs::write(results.join("sync/1/PREPARE.saved-refs.tsv"), format!("5.0\t{old}\nfix/pub\t{old}\nfix/staged\t{old}\n")).unwrap();
        let c = db();
        c.execute(
            "INSERT INTO sync_run (started_at, state, fork, repo, bases, publish) VALUES ('t', 'needs-decision', 'f', ?1, ?2, 'auto')",
            rusqlite::params![d.to_string_lossy(), format!("5.0={old}..{new}")],
        )
        .unwrap();
        c.execute("INSERT INTO sync_stage (run_id, name, state) VALUES (1, 'PUBLISH', 'done')", []).unwrap();
        for (n, b, st) in [(1, "fix/pub", "published"), (2, "fix/staged", "staged")] {
            c.execute(
                "INSERT INTO sync_pr (run_id, number, branch, root, gh_head, action, state) VALUES (1, ?1, ?2, '5.0', ?3, 'rebase', ?4)",
                rusqlite::params![n, b, old, st],
            )
            .unwrap();
        }
        let (keep, bases) = kept_after_publish(&c, 1).unwrap();
        assert_eq!(restore_refs(&results, 1, &d, &keep).unwrap(), 1);
        record_synced(&c, &bases).unwrap();
        assert_eq!(g(&["rev-parse", "fix/pub"]), new);
        assert_eq!(g(&["rev-parse", "5.0"]), new);
        assert_eq!(g(&["rev-parse", "fix/staged"]), old);
        assert_eq!(synced_base(&c, "5.0").as_deref(), Some(new.as_str()));
        // before PUBLISH an abort keeps nothing
        c.execute("UPDATE sync_stage SET state = 'failed' WHERE run_id = 1 AND name = 'PUBLISH'", []).unwrap();
        assert!(kept_after_publish(&c, 1).unwrap().0.is_empty());
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn sync_start_refuses_what_it_does_not_know_instead_of_starting_a_run() {
        let a = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        for bad in [&["--help"][..], &["-h"], &["--rebase"], &["--fork"], &["--until", "--rebase-all"], &["5.0"]] {
            let e = check_start_args(&a(bad)).unwrap_err();
            assert!(e.contains("usage: sync start"), "{bad:?}: {e}");
        }
        assert!(check_start_args(&a(&[])).is_ok());
        assert!(check_start_args(&a(&["--rebase-all", "--until", "GATE", "--fork", "o/r", "--repo", "/g", "--against", "v/p"])).is_ok());
    }

    #[test]
    fn rebase_all_moves_a_pr_that_merges_cleanly_and_says_why() {
        let clean = crate::sync::Analysis {
            number: 1,
            head_ref: "fix/a".into(),
            root: "5.0".into(),
            local_head: "h".into(),
            in_sync: true,
            merge: Ok(true),
            own_commits: 1,
            equivalent: 0,
            touched: vec![],
        };
        assert!(!needs_rebase(&clean, false));
        assert!(needs_rebase(&clean, true));
        let conflict = crate::sync::Analysis { merge: Err(vec!["SPECS/a/a.spec".into()]), ..clean.clone() };
        assert!(needs_rebase(&conflict, false));
        let touched = crate::sync::Analysis { touched: vec!["SPECS/a/a.spec".into()], ..clean };
        assert!(needs_rebase(&touched, false));
    }

    #[test]
    fn rebase_all_is_kept_with_the_run_and_defaults_to_off() {
        let c = db();
        c.execute(
            "INSERT INTO sync_run (started_at, state, fork, repo, bases, publish) VALUES ('t', 'failed', 'f', '/r', 'x=a..b', 'approve')",
            [],
        )
        .unwrap();
        let v: i64 = c.query_row("SELECT rebase_all FROM sync_run WHERE id = 1", [], |r| r.get(0)).unwrap();
        assert_eq!(v, 0);
    }

    #[test]
    fn only_one_run_at_a_time_and_a_base_must_be_recorded_first() {
        let c = db();
        let e = start(&c, "dcasota/photon", Path::new("/nonexistent"), &["5.0"], "approve", None, false).unwrap_err();
        assert!(e.contains("no synced base recorded for 5.0"), "{e}");
        c.execute(
            "INSERT INTO sync_run (started_at, state, fork, repo, bases, publish) VALUES ('t', 'needs-decision', 'f', '/r', 'x=a..b', 'approve')",
            [],
        )
        .unwrap();
        let e = start(&c, "dcasota/photon", Path::new("/nonexistent"), &["5.0"], "approve", None, false).unwrap_err();
        assert!(e.contains("is needs-decision"), "{e}");
        assert!(start(&c, "f", Path::new("/x"), &[], "sometimes", None, false).is_err());
    }

    #[test]
    fn a_build_tree_may_only_hold_what_patches_and_fixups_explain() {
        let named = patch_paths(&["diff --git a/SPECS/a/a.spec b/SPECS/a/a.spec\n+x\ndiff --git a/SPECS/linux/x b/SPECS/92/linux/x\n".to_string()]);
        assert_eq!(named, vec!["SPECS/92/linux/x", "SPECS/a/a.spec", "SPECS/linux/x"]);
        let dirty: Vec<String> = ["SPECS/a/a.spec", "build-config.json", "SPECS/openjdk/openjdk21.spec", "SPECS/b/hand-edit.spec"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(unexplained(&dirty, &named), vec!["SPECS/b/hand-edit.spec"]);
    }

    #[test]
    fn porcelain_lines_keep_their_first_character() {
        let t = " M build-config.json\n?? common/data/x.json\nR  a.spec -> b.spec\n";
        assert_eq!(porcelain_paths(t), vec!["build-config.json", "common/data/x.json", "a.spec", "b.spec"]);
    }

    #[test]
    fn auto_waits_for_a_fork_move_and_for_quiet() {
        let c = db();
        let r = Path::new("/nonexistent");
        let mut asked = Vec::new();
        let mut esc = |run: i64| -> Result<Vec<String>, String> {
            asked.push(run);
            Ok(vec!["#23 verified".into()])
        };
        assert_eq!(auto(&c, "dcasota/photon", r, &["5.0", "common"], r, 7200, &mut esc).unwrap(), "the fork's bases did not move");
        crate::watch::record(&c, "upstream-moved", "vmware/photon:5.0", None, None, "1 commit(s)").unwrap();
        assert_eq!(auto(&c, "dcasota/photon", r, &["5.0", "common"], r, 7200, &mut esc).unwrap(), "the fork's bases did not move", "vmware moving is not a trigger");
        crate::watch::record(&c, "upstream-moved", "dcasota/photon:5.0", None, None, "3 commit(s)").unwrap();
        assert!(auto(&c, "dcasota/photon", r, &["5.0", "common"], r, 7200, &mut esc).unwrap().contains("waiting for 7200s of quiet"));
        // a run waiting for a decision is handed to the escalation on every tick; other states are not
        c.execute("INSERT INTO sync_run (started_at, state, fork, repo, bases, publish) VALUES ('t', 'awaiting-approval', 'f', '/r', 'x=a..b', 'approve')", []).unwrap();
        assert!(auto(&c, "dcasota/photon", r, &["5.0", "common"], r, 7200, &mut esc).unwrap().contains("is awaiting-approval; nothing started"));
        c.execute("UPDATE sync_run SET state = 'needs-decision'", []).unwrap();
        assert_eq!(auto(&c, "dcasota/photon", r, &["5.0", "common"], r, 7200, &mut esc).unwrap(), "run 1 is needs-decision; escalation: #23 verified");
        drop(esc);
        assert_eq!(asked, vec![1]);
    }

    #[test]
    fn a_change_held_in_the_gate_repository_holds_the_sync() {
        let pr = |n: u64, b: &str, h: &str| crate::sync::Pr { number: n, base: "5.0".into(), head_ref: b.into(), gh_head: h.into() };
        let prs = vec![pr(25, "fix/spec-checker-parse-matrix", "a0f2068138"), pr(23, "fix/stig", "447621c3f9"), pr(99, "new/branch", "1111111111")];
        let local = |b: &str| match b {
            "fix/spec-checker-parse-matrix" => Some("5ad76466cd".to_string()),
            "fix/stig" => Some("447621c3f9".to_string()),
            _ => None,
        };
        let held = unpublished(&local, &prs);
        assert_eq!(held, vec![(25, "fix/spec-checker-parse-matrix".to_string(), "5ad76466cd".to_string(), "a0f2068138".to_string())]);
        assert!(unpublished(&|_| None, &prs).is_empty(), "a branch the gate repository does not have is ANALYZE's to fetch");
    }

    #[test]
    fn upstream_prs_pair_with_the_forks_branches_only() {
        let tsv = "1680\tdcasota\tfix/kernel-single-source\n1675\tDCASOTA\tfix/canister-build-against-current-kernel\n1500\tsomeone\tfix/kernel-single-source\nbad line\n";
        let p = parse_pairs(tsv, "dcasota");
        assert_eq!(p.len(), 2);
        assert_eq!(p["fix/kernel-single-source"], 1680, "another owner's same-named branch is not ours");
        assert_eq!(p["fix/canister-build-against-current-kernel"], 1675);
    }

    #[test]
    fn a_paired_branch_and_everything_stacked_on_it_is_held() {
        let rows = vec![
            (24, "a".to_string(), None),
            (29, "b".to_string(), Some("a".to_string())),
            (36, "c".to_string(), Some("b".to_string())),
            (54, "d".to_string(), Some("c".to_string())),
            (23, "e".to_string(), None),
            (92, "f".to_string(), Some("e".to_string())),
        ];
        let mut pairs = BTreeMap::new();
        pairs.insert("c".to_string(), 1680u64);
        let h: Vec<i64> = held(&rows, &pairs).into_iter().collect();
        assert_eq!(h, vec![36, 54], "the paired PR and its descendants; its parents and other stacks move as usual");
        assert!(held(&rows, &BTreeMap::new()).is_empty());
    }

    #[test]
    fn an_upstream_description_never_points_at_the_fork() {
        let allowed: std::collections::BTreeSet<u64> = [1675, 1680].into_iter().collect();
        let current = "## Problem\nSee #1234 for the report.\n";
        assert!(cross_org("Stacked on #1675; see #1234.", current, "dcasota", &allowed).is_empty(), "upstream PRs and numbers upstream already has");
        let p = cross_org("Stacked on #36 (dcasota/photon#36), see https://github.com/DCASOTA/photon.", current, "dcasota", &allowed);
        assert_eq!(p.len(), 2, "{p:?}");
        assert!(p[0].contains("names dcasota") && p[1].contains("#36") && !p[1].contains("#1234"));
        assert!(cross_org("issue&#35; and abc#12 are not references", "", "x", &allowed).is_empty());
    }

    #[test]
    fn a_run_from_before_a_stage_existed_gets_it_pending() {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch(SCHEMA).unwrap();
        ensure_schema(&c).unwrap();
        ensure_schema(&c).unwrap();
        c.execute("INSERT INTO sync_run (id, started_at, state, fork, repo, bases, publish) VALUES (1, 't', 'done', 'f/p', '/r', 'x=a..b', 'auto')", []).unwrap();
        let ok: i64 = c.query_row("SELECT upstream_approved FROM sync_run WHERE id = 1", [], |r| r.get(0)).unwrap();
        assert_eq!(ok, 0, "approval is never assumed");
        assert_eq!(&STAGES[6..], ["PUBLISH", "STAGEVM", "UPSTREAM", "DONE"]);
    }

    /// Live and read-only: the real pairing, every upstream description
    /// against the cross-org rule, every paired head against upstream's base.
    /// SHARUKHAN_LIVE_REPO=<gate repository>; uses gh and the network.
    #[test]
    #[ignore]
    fn live_upstream_pairs_descriptions_and_merges() {
        let repo = std::env::var("SHARUKHAN_LIVE_REPO").expect("SHARUKHAN_LIVE_REPO=<gate repository>");
        let cfg = crate::config::Config::defaults();
        let c = Connection::open_in_memory().unwrap();
        let ctx = Ctx {
            c: &c,
            run: 0,
            fork: cfg.fork.clone(),
            repo: PathBuf::from(&repo),
            bases: BTreeMap::new(),
            dir: std::env::temp_dir(),
            publish: String::new(),
            upstream: cfg.upstream.clone(),
        };
        let pairs = upstream_pairs(&ctx.upstream, &ctx.fork).unwrap();
        assert!(!pairs.is_empty());
        let allowed: std::collections::BTreeSet<u64> = pairs.values().copied().collect();
        let owner = ctx.fork.split('/').next().unwrap();
        for (branch, u) in &pairs {
            let body = gh_pr_field(&ctx.upstream, *u, "body").unwrap();
            let p = cross_org(&body, &body, owner, &allowed);
            let head = gh_pr_field(&ctx.upstream, *u, "headRefOid").unwrap();
            let m = upstream_conflicts(&ctx, *u, head.trim()).unwrap();
            println!("#{u} {branch}: cross-org {} | merge onto base {}", if p.is_empty() { "clean".to_string() } else { p.join("; ") }, m.map(|x| format!("CONFLICTS {x:?}")).unwrap_or("clean".into()));
        }
    }

    #[test]
    fn parents_rebase_before_their_children() {
        let rows = vec![
            (36, "c".to_string(), "5.0".to_string(), Some("b".to_string())),
            (24, "a".to_string(), "5.0".to_string(), None),
            (29, "b".to_string(), "5.0".to_string(), Some("a".to_string())),
        ];
        let mut sorted = rows.clone();
        sorted.sort_by_key(|r| depth(&r.1, &rows));
        assert_eq!(sorted.iter().map(|r| r.0).collect::<Vec<_>>(), vec![24, 29, 36]);
    }
}
