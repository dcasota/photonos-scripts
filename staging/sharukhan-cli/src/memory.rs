//! The memory database.
//!
//! Findings and run results live in SQLite so they survive the session that
//! produced them. Every query is parameterised.

use rusqlite::{Connection, OpenFlags};
use std::path::Path;

pub struct Finding {
    pub id: i64,
    pub slug: String,
    pub severity: String,
    pub status: String,
    pub summary: String,
}

pub fn open(path: &Path) -> Result<Connection, String> {
    if !path.exists() {
        return Err(format!("no memory database at {}", path.display()));
    }
    Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|e| format!("opening {}: {e}", path.display()))
}

fn columns(conn: &Connection, table: &str) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(mut st) = conn.prepare(&format!("PRAGMA table_info({table})")) {
        if let Ok(rows) = st.query_map([], |r| r.get::<_, String>(1)) {
            for r in rows.flatten() {
                out.push(r);
            }
        }
    }
    out
}

/// Read findings, tolerating schema drift: the column names are discovered
/// rather than assumed, so an older or newer database still reports something
/// useful instead of failing outright.
pub fn findings(conn: &Connection, severity: Option<&str>) -> Result<Vec<Finding>, String> {
    let cols = columns(conn, "finding");
    if cols.is_empty() {
        return Err("the database has no 'finding' table".into());
    }
    let pick = |cands: &[&str]| -> Option<String> {
        cands.iter().find(|c| cols.iter().any(|k| k == *c)).map(|c| c.to_string())
    };
    let slug = pick(&["slug", "name", "key", "title"]).unwrap_or_else(|| "rowid".into());
    let sev = pick(&["severity", "level"]).unwrap_or_else(|| "''".into());
    let status = pick(&["status", "state"]).unwrap_or_else(|| "''".into());
    let summary = pick(&["summary", "description", "detail", "body"]).unwrap_or_else(|| "''".into());

    let sql = format!(
        "SELECT rowid, {slug}, {sev}, {status}, {summary} FROM finding \
         WHERE (?1 IS NULL OR {sev} = ?1) ORDER BY rowid"
    );
    let mut st = conn.prepare(&sql).map_err(|e| format!("{e}"))?;
    let rows = st
        .query_map([severity], |r| {
            Ok(Finding {
                id: r.get(0)?,
                slug: r.get::<_, Option<String>>(1)?.unwrap_or_default(),
                severity: r.get::<_, Option<String>>(2)?.unwrap_or_default(),
                status: r.get::<_, Option<String>>(3)?.unwrap_or_default(),
                summary: r.get::<_, Option<String>>(4)?.unwrap_or_default(),
            })
        })
        .map_err(|e| format!("{e}"))?;
    Ok(rows.flatten().collect())
}

pub fn count(conn: &Connection, table: &str) -> i64 {
    conn.query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get(0))
        .unwrap_or(0)
}
