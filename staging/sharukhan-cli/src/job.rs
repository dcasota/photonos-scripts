//! The `job` table: background work that outlives the process that started it.
//!
//! A driver started with `nohup … &` is invisible to the next shell. The bash
//! harness solved that with log files and `pgrep`, which is how the self-match
//! bug got in. A row in SQLite is findable by id, survives a reboot, and says
//! what it was for.
//!
//! Only this table is written. run/permutation/check_result stay empty on
//! purpose: mc-verify.sh already writes the results as JSONL and `report`
//! reads them, and a second copy would be a second source of truth.

use rusqlite::{Connection, OpenFlags};
use std::path::Path;

pub struct Job {
    pub id: i64,
    pub kind: String,
    pub label: String,
    pub pid: Option<i64>,
    pub state: String,
    pub log_path: String,
    pub started_at: String,
    pub finished_at: String,
}

pub const RUNNING: &str = "running";
pub const DONE: &str = "done";
pub const FAILED: &str = "failed";
pub const STOPPED: &str = "stopped";

/// Opened read-write but never created: a missing database means the paths are
/// wrong, and silently creating an empty one hides that until the first query
/// returns nothing.
pub fn open_rw(path: &Path) -> Result<Connection, String> {
    if !path.exists() {
        return Err(format!("no memory database at {}", path.display()));
    }
    Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_WRITE)
        .map_err(|e| format!("opening {} read-write: {e}", path.display()))
}

pub fn now() -> String {
    // No chrono dependency. `date -u` is present everywhere this runs, and the
    // format matches the stamps mission-control writes.
    std::process::Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".into())
}

pub fn start(
    conn: &Connection,
    kind: &str,
    label: &str,
    pid: i32,
    log_path: &str,
) -> Result<i64, String> {
    conn.execute(
        "INSERT INTO job (run_id, kind, label, pid, state, log_path, started_at) \
         VALUES (NULL, ?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![kind, label, pid, RUNNING, log_path, now()],
    )
    .map_err(|e| format!("recording job: {e}"))?;
    Ok(conn.last_insert_rowid())
}

pub fn finish(conn: &Connection, id: i64, state: &str) -> Result<(), String> {
    conn.execute(
        "UPDATE job SET state = ?1, finished_at = ?2 WHERE id = ?3",
        rusqlite::params![state, now(), id],
    )
    .map_err(|e| format!("updating job {id}: {e}"))?;
    Ok(())
}

fn row(r: &rusqlite::Row) -> rusqlite::Result<Job> {
    Ok(Job {
        id: r.get(0)?,
        kind: r.get::<_, Option<String>>(1)?.unwrap_or_default(),
        label: r.get::<_, Option<String>>(2)?.unwrap_or_default(),
        pid: r.get(3)?,
        state: r.get::<_, Option<String>>(4)?.unwrap_or_default(),
        log_path: r.get::<_, Option<String>>(5)?.unwrap_or_default(),
        started_at: r.get::<_, Option<String>>(6)?.unwrap_or_default(),
        finished_at: r.get::<_, Option<String>>(7)?.unwrap_or_default(),
    })
}

const SELECT: &str =
    "SELECT id, kind, label, pid, state, log_path, started_at, COALESCE(finished_at,'') FROM job";

pub fn get(conn: &Connection, id: i64) -> Result<Option<Job>, String> {
    let mut st = conn
        .prepare(&format!("{SELECT} WHERE id = ?1"))
        .map_err(|e| format!("{e}"))?;
    let mut rows = st.query_map([id], row).map_err(|e| format!("{e}"))?;
    Ok(rows.next().and_then(|r| r.ok()))
}

pub fn list(conn: &Connection, running_only: bool) -> Result<Vec<Job>, String> {
    let sql = if running_only {
        format!("{SELECT} WHERE state = '{RUNNING}' ORDER BY id")
    } else {
        format!("{SELECT} ORDER BY id")
    };
    let mut st = conn.prepare(&sql).map_err(|e| format!("{e}"))?;
    let rows = st.query_map([], row).map_err(|e| format!("{e}"))?;
    Ok(rows.flatten().collect())
}

impl Job {
    /// What the row claims, checked against the process table. A row saying
    /// 'running' whose pid is gone is the crashed-driver case: the state is
    /// stale, not true, and reporting it as running is how a waiter waits
    /// forever.
    pub fn liveness(&self) -> &'static str {
        match self.pid {
            None => "no pid recorded",
            Some(p) if !crate::proc::alive(p as i32) => "pid not alive",
            Some(p) if !crate::proc::looks_like_sharukhan(p as i32) => "pid reused by another program",
            Some(_) => "alive",
        }
    }
    pub fn is_live(&self) -> bool {
        self.liveness() == "alive"
    }
}
