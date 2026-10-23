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
//! * Nothing reaches GitHub before PUBLISH. Rebased heads live in the gate
//!   repository as sync/<run>/<branch>; PREPARE points the gate's branches at
//!   them so variant patches and builds use them, and records the old values.
//! * PUBLISH pushes with --force-with-lease against the PR heads ANALYZE saw.
//!   Until PR descriptions are generated from evidence (step 5) it waits for
//!   `sync approve`, whatever publish_dcasota says: pushing code under a
//!   description that no longer matches it is not publishing.

use rusqlite::Connection;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const STAGES: &[&str] = &["ANALYZE", "REBASE", "VERIFY", "PREPARE", "FASTLOOP", "GATE", "PUBLISH", "DONE"];

pub const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS sync_run (
    id          INTEGER PRIMARY KEY,
    started_at  TEXT NOT NULL,
    state       TEXT NOT NULL,     -- running | paused | needs-decision | awaiting-approval | superseded | aborted | failed | done
    fork        TEXT NOT NULL,     -- dcasota/photon
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
    state       TEXT NOT NULL,     -- pending | rebased | refused | verified | failed | published
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

pub fn start(c: &Connection, fork: &str, repo: &Path, roots: &[&str], publish: &str, against: Option<&str>) -> Result<i64, String> {
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
        "INSERT INTO sync_run (started_at, state, fork, repo, bases, publish, pid, against) VALUES (?1, 'running', ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![now(), fork, repo.to_string_lossy(), parts.join(","), publish, std::process::id() as i64, source],
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
    let leases: Vec<(i64, String)> = c
        .prepare("SELECT number, gh_head FROM sync_pr WHERE run_id = ?1")
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
    let mut rebase = 0;
    for a in &res {
        let pr = prs.iter().find(|p| p.number == a.number).ok_or("PR vanished during analyze")?;
        let parent = crate::sync::root_base(pr, &prs, &bases.keys().map(String::as_str).collect::<Vec<_>>()).and_then(|x| x.1);
        let needs = a.merge.is_err() || !a.touched.is_empty();
        if !a.in_sync {
            return Ok(Outcome::NeedsDecision(format!("PR #{} local head differs from GitHub: sync them first", a.number)));
        }
        rebase += needs as usize;
        ctx.c
            .execute(
                "INSERT INTO sync_pr (run_id, number, branch, root, parent, gh_head, action, state, detail) VALUES (?1,?2,?3,?4,?5,?6,?7,'pending',?8)",
                rusqlite::params![ctx.run, a.number as i64, a.head_ref, a.root, parent, pr.gh_head, if needs { "rebase" } else { "keep" }, crate::sync::verdict(a)],
            )
            .map_err(sql)?;
        lines.push(format!("#{} {} {}", a.number, a.head_ref, crate::sync::verdict(a)));
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
    let mut rows: Vec<(i64, String, String, Option<String>)> = ctx
        .c
        .prepare("SELECT number, branch, root, parent FROM sync_pr WHERE run_id = ?1 AND action = 'rebase'")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    if rows.is_empty() {
        return Ok(Outcome::Skipped("nothing to rebase".into()));
    }
    let all = rows.clone();
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
                let old_parent = git(&ctx.repo, &["rev-parse", &format!("refs/heads/{p}")])?;
                let new_parent = git(&ctx.repo, &["rev-parse", "--verify", "-q", &format!("refs/heads/sync/{}/{p}", ctx.run)])
                    .unwrap_or_else(|_| old_parent.clone());
                (git(&ctx.repo, &["merge-base", &src, &old_parent])?, new_parent)
            }
        };
        let work = ctx.repo.join(format!(".sharukhan-sync-{}-{n}", ctx.run));
        match crate::sync::rebase(&ctx.repo, &src, &own_base, old_root, &new_base, &date, &work, parent.is_some()) {
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
    let rows: Vec<(i64, String, String)> = ctx
        .c
        .prepare("SELECT number, root, new_head FROM sync_pr WHERE run_id = ?1 AND state = 'rebased'")
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
        let checks = crate::sync::verify(&ctx.repo, &format!("refs/sync/base/{root}"), head, &common, &work, &[90, 91, 92, 93], &mut |l| log.push(l.to_string()))?;
        let _ = fs::remove_dir_all(&work);
        let bad: Vec<String> = checks.iter().filter(|c| !c.ok).map(|c| format!("{} sr{} {}: {}", c.spec, c.subrelease, c.what, c.detail)).collect();
        log.push(format!("#{n}: {} check(s), {} failed", checks.len(), bad.len()));
        log.extend(bad.iter().map(|b| format!("  FAIL {b}")));
        let st = if bad.is_empty() { "verified" } else { "failed" };
        ctx.c.execute("UPDATE sync_pr SET state = ?1 WHERE run_id = ?2 AND number = ?3", rusqlite::params![st, ctx.run, n]).map_err(sql)?;
        if !bad.is_empty() {
            failed.push(format!("#{n}"));
        }
    }
    fs::write(ctx.dir.join("VERIFY.log"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
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

fn fastloop(ctx: &Ctx) -> Result<Outcome, String> {
    let mut rows = vec![("prebuilt", "k03")];
    if kernel_touched(ctx)? {
        rows.push(("equivalent", "c03"));
    }
    for (canister, row) in &rows {
        if !child(ctx, "FASTLOOP", &["build-iso", "--iso-type", "minimal", "--poi", "2.8", "--canister", canister, "--allow-build", "--force"])? {
            return Ok(Outcome::NeedsDecision(format!("minimal/2.8/{canister} did not build, see FASTLOOP.log")));
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

fn publish(ctx: &Ctx, approved: bool) -> Result<Outcome, String> {
    let rows: Vec<(i64, String, String, String)> = ctx
        .c
        .prepare("SELECT number, branch, gh_head, new_head FROM sync_pr WHERE run_id = ?1 AND state = 'verified'")
        .and_then(|mut s| s.query_map([ctx.run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map(|x| x.flatten().collect()))
        .map_err(sql)?;
    if rows.is_empty() {
        return Ok(Outcome::Skipped("nothing to publish".into()));
    }
    if !approved {
        let table: Vec<String> = rows.iter().map(|(n, b, old, new)| format!("#{n} {b} {}..{}", &old[..9], &new[..9])).collect();
        fs::write(ctx.dir.join("PUBLISH.table"), table.join("\n") + "\n").map_err(|e| format!("{e}"))?;
        return Ok(Outcome::Waiting(format!(
            "{} push(es) prepared (PUBLISH.table); PR descriptions are not generated yet, so `sharukhan sync approve {}` is required",
            rows.len(),
            ctx.run
        )));
    }
    let url = format!("https://github.com/{}.git", ctx.fork);
    let mut log = Vec::new();
    for (n, branch, lease, new) in &rows {
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
            return Ok(Outcome::Failed(format!("#{n}: GitHub reports {gh} after the push, not {new}")));
        }
        ctx.c.execute("UPDATE sync_pr SET state = 'published' WHERE run_id = ?1 AND number = ?2", rusqlite::params![ctx.run, n]).map_err(sql)?;
        log.push(format!("#{n} {branch} {}..{} verified on GitHub", &lease[..9], &new[..9]));
    }
    fs::write(ctx.dir.join("PUBLISH.log"), log.join("\n") + "\n").map_err(|e| format!("{e}"))?;
    Ok(Outcome::Done(format!("{} PR(s) pushed and verified", rows.len())))
}

fn done(ctx: &Ctx) -> Result<Outcome, String> {
    for (root, (_, new)) in &ctx.bases {
        ctx.c
            .execute(
                "INSERT INTO upstream_head (repo, ref, value, seen_at) VALUES ('synced', ?1, ?2, ?3) \
                 ON CONFLICT(repo, ref) DO UPDATE SET value = excluded.value, seen_at = excluded.seen_at",
                rusqlite::params![root, new, now()],
            )
            .map_err(sql)?;
    }
    Ok(Outcome::Done("synced bases recorded".into()))
}

/// Run the remaining stages of `run` until it finishes or stops.
pub fn drive(c: &Connection, run: i64, results: &Path, until: Option<&str>) -> Result<String, String> {
    recover(c, run)?;
    let (fork, repo, bases, approved): (String, String, String, i64) = c
        .query_row("SELECT fork, repo, bases, approved FROM sync_run WHERE id = ?1", [run], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
        .map_err(sql)?;
    c.execute("UPDATE sync_run SET pid = ?1, state = 'running' WHERE id = ?2", rusqlite::params![std::process::id() as i64, run]).map_err(sql)?;
    let ctx = Ctx {
        c,
        run,
        fork,
        repo: PathBuf::from(repo),
        bases: parse_bases(&bases)?,
        dir: results.join("sync").join(run.to_string()),
    };
    fs::create_dir_all(&ctx.dir).map_err(|e| format!("{}: {e}", ctx.dir.display()))?;
    for name in STAGES {
        let state: String = c
            .query_row("SELECT state FROM sync_stage WHERE run_id = ?1 AND name = ?2", rusqlite::params![run, name], |r| r.get(0))
            .map_err(sql)?;
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
        if matches!(*name, "FASTLOOP" | "GATE") && !in_host_namespace() {
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
pub fn restore_refs(results: &Path, run: i64, repo: &Path) -> Result<usize, String> {
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
        if old.is_empty() {
            git(repo, &["update-ref", "-d", &format!("refs/heads/{branch}")])?;
        } else {
            git(repo, &["update-ref", &format!("refs/heads/{branch}"), old])?;
        }
        n += 1;
    }
    Ok(n)
}

pub fn cli(args: &[String]) -> Option<u8> {
    let sub = args.first().map(String::as_str)?;
    if !matches!(sub, "start" | "resume" | "status" | "approve" | "abort" | "baseline") {
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
        match sub {
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
                let fork = args.iter().position(|a| a == "--fork").and_then(|i| args.get(i + 1)).map(String::as_str).unwrap_or("dcasota/photon");
                let repo = PathBuf::from(args.iter().position(|a| a == "--repo").and_then(|i| args.get(i + 1)).map(String::as_str).unwrap_or("/root/photon-mc/gate/photon.git"));
                let publish = std::env::var("MC_PUBLISH_DCASOTA").unwrap_or_else(|_| "auto".into());
                let against = args.iter().position(|a| a == "--against").and_then(|i| args.get(i + 1)).map(String::as_str);
                let id = start(&c, fork, &repo, &["5.0", "common"], &publish, against)?;
                println!("sync run {id} started");
                drive(&c, id, &results, until)
            }
            "resume" => drive(&c, num(1)?, &results, until),
            "approve" => {
                let id = num(1)?;
                c.execute("UPDATE sync_run SET approved = 1 WHERE id = ?1", [id]).map_err(sql)?;
                drive(&c, id, &results, until)
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
                if state != "running" {
                    let repo: String = c.query_row("SELECT repo FROM sync_run WHERE id = ?1", [id], |r| r.get(0)).map_err(sql)?;
                    let n = restore_refs(&results, id, Path::new(&repo))?;
                    set_run(&c, id, "aborted", &format!("aborted; {n} gate ref(s) restored"))?;
                }
                Ok(format!("run {id}: abort recorded"))
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

    #[test]
    fn only_one_run_at_a_time_and_a_base_must_be_recorded_first() {
        let c = db();
        let e = start(&c, "dcasota/photon", Path::new("/nonexistent"), &["5.0"], "approve", None).unwrap_err();
        assert!(e.contains("no synced base recorded for 5.0"), "{e}");
        c.execute(
            "INSERT INTO sync_run (started_at, state, fork, repo, bases, publish) VALUES ('t', 'needs-decision', 'f', '/r', 'x=a..b', 'approve')",
            [],
        )
        .unwrap();
        let e = start(&c, "dcasota/photon", Path::new("/nonexistent"), &["5.0"], "approve", None).unwrap_err();
        assert!(e.contains("is needs-decision"), "{e}");
        assert!(start(&c, "f", Path::new("/x"), &[], "sometimes", None).is_err());
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
