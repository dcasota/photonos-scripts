//! Getting run results into the memory database, and keeping them there.
//!
//! The evidence files under `results/<perm>/checks-<stamp>.jsonl` are the source
//! of truth: they are written line by line as a row is verified, so they survive
//! a crash mid-run and can be diffed against each other. The database is a
//! queryable index *derived* from them.
//!
//! It had not been derived from anything. `run`, `permutation` and
//! `check_result` were declared in the schema and never written - 1,111 check
//! records sat on disk while every one of those tables held zero rows. Findings
//! and next steps were current only because they were typed in by hand, which
//! is a maintenance model that lasts exactly as long as someone remembers.
//!
//! So ingest is idempotent and re-runnable over the whole tree: `run` is keyed
//! by its stamp, `permutation` by `(run, perm)`, and a re-ingest replaces a
//! permutation's checks rather than duplicating them. That makes "keep the
//! database up to date" a command rather than a discipline, and lets `run` call
//! it after each row without special-casing the first time.

use crate::config::Config;
use crate::matrix::{self, Permutation};
use rusqlite::{params, Connection};
use std::collections::BTreeMap;
use std::path::Path;

pub struct Summary {
    pub runs: usize,
    pub permutations: usize,
    pub checks: usize,
    pub packages: usize,
}

/// The per-package lifecycle records (FRD-002). Created here rather than only
/// in schema/memory.sql because ingest is the table's only writer and must
/// not depend on someone having re-applied the schema first.
pub const PACKAGE_LIFECYCLE_DDL: &str = "
CREATE TABLE IF NOT EXISTS package_lifecycle (
    id             INTEGER PRIMARY KEY,
    permutation_id INTEGER NOT NULL REFERENCES permutation(id),
    package        TEXT NOT NULL,
    evr            TEXT,
    arch           TEXT,
    origin         TEXT,           -- fresh | preinstalled
    classes        TEXT,           -- daemon,cli,library,data
    verdict        TEXT NOT NULL,  -- pass | fail | skip | not-reached
    reason         TEXT,
    duration_ms    INTEGER,
    failed_parts   INTEGER NOT NULL DEFAULT 0,
    machine_id     TEXT,
    policy_sha256  TEXT,
    record         TEXT NOT NULL,  -- the full JSON evidence record
    recorded_at    TEXT NOT NULL,
    UNIQUE (permutation_id, package)
);
CREATE INDEX IF NOT EXISTS idx_pkglife_perm    ON package_lifecycle(permutation_id);
CREATE INDEX IF NOT EXISTS idx_pkglife_verdict ON package_lifecycle(verdict);
CREATE VIEW IF NOT EXISTS v_package_lifecycle AS
SELECT p.perm_id, l.package, l.evr, l.origin, l.classes, l.verdict, l.reason, l.duration_ms,
       p.finished_at AS stamp
FROM package_lifecycle l JOIN permutation p ON p.id = l.permutation_id;
";

/// Check ids that are negative controls by namespace. Derived at ingest so
/// the frozen evidence line format does not have to change.
pub fn is_control(check_id: &str) -> bool {
    check_id.starts_with("pkg.control.")
}

/// One lifecycle record, reduced to the indexed columns plus the full JSON.
struct LifeRow {
    package: String,
    evr: String,
    arch: String,
    origin: String,
    classes: String,
    verdict: String,
    reason: String,
    duration_ms: i64,
    failed_parts: i64,
    machine_id: String,
    policy: String,
    record: String,
}

fn parse_life(line: &str) -> Option<LifeRow> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    let s = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    let package = s("package");
    let verdict = s("verdict");
    if package.is_empty() || verdict.is_empty() {
        return None;
    }
    let count_failed = |k: &str| {
        v.get(k)
            .and_then(|x| x.as_array())
            .map(|a| {
                a.iter()
                    .filter(|e| e.get("status").and_then(|s| s.as_str()) == Some("fail"))
                    .count()
            })
            .unwrap_or(0)
    };
    Some(LifeRow {
        package,
        evr: s("evr"),
        arch: s("arch"),
        origin: s("origin"),
        classes: v
            .get("classes")
            .and_then(|x| x.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|c| c.as_str())
                    .collect::<Vec<_>>()
                    .join(",")
            })
            .unwrap_or_default(),
        verdict,
        reason: s("reason"),
        duration_ms: v.get("duration_ms").and_then(|x| x.as_i64()).unwrap_or(0),
        failed_parts: (count_failed("steps") + count_failed("units") + count_failed("clis")) as i64,
        machine_id: s("machine_id"),
        policy: s("policy_sha256"),
        record: line.to_string(),
    })
}

/// Replace, never append: a permutation's lifecycle rows are exactly the
/// records of its pkglife file.
fn ingest_lifecycle(
    conn: &Connection,
    pid: i64,
    file: &Path,
    stamp: &str,
) -> Result<usize, String> {
    let text = std::fs::read_to_string(file).map_err(|e| format!("{}: {e}", file.display()))?;
    conn.execute(
        "DELETE FROM package_lifecycle WHERE permutation_id = ?1",
        params![pid],
    )
    .map_err(|e| format!("{e}"))?;
    let mut n = 0;
    for r in text.lines().filter_map(parse_life) {
        // A record can appear twice when a resumed run carried it and then
        // re-tested nothing; the later line wins.
        conn.execute(
            "INSERT OR REPLACE INTO package_lifecycle
               (permutation_id, package, evr, arch, origin, classes, verdict, reason,
                duration_ms, failed_parts, machine_id, policy_sha256, record, recorded_at)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)",
            params![
                pid,
                r.package,
                r.evr,
                r.arch,
                r.origin,
                r.classes,
                r.verdict,
                r.reason,
                r.duration_ms,
                r.failed_parts,
                r.machine_id,
                r.policy,
                r.record,
                stamp
            ],
        )
        .map_err(|e| format!("{e}"))?;
        n += 1;
    }
    Ok(n)
}

#[derive(Debug)]
struct Record {
    /// Read only by the parser test. The ingest path keys on the row id it was
    /// given rather than on the one inside the file, so a mislabelled record
    /// cannot silently retarget a different permutation.
    #[allow(dead_code)]
    perm: String,
    check: String,
    pr: String,
    status: String,
    expected: String,
    actual: String,
    detail: String,
}

/// Minimal field extraction. The writer is `evidence.rs` and the shape is
/// fixed, so a full JSON parse buys nothing here; but a record missing `perm`
/// or `check` is skipped rather than guessed at.
fn parse(line: &str) -> Option<Record> {
    let v: serde_json::Value = serde_json::from_str(line).ok()?;
    let get = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    let perm = get("perm");
    let check = get("check");
    if perm.is_empty() || check.is_empty() {
        return None;
    }
    Some(Record {
        perm,
        check,
        pr: get("pr"),
        status: get("status"),
        expected: get("expected"),
        actual: get("actual"),
        detail: get("detail"),
    })
}

fn open_rw(path: &Path) -> Result<Connection, String> {
    Connection::open(path).map_err(|e| format!("{}: {e}", path.display()))
}

/// Ingest every `checks-<stamp>.jsonl` under `results/`.
///
/// `checks-latest.jsonl` is a symlink to one of them and is skipped, or every
/// latest run would be counted twice.
pub fn all(cfg: &Config) -> Result<Summary, String> {
    let rows: BTreeMap<String, Permutation> = matrix::load(&cfg.matrix_tsv)
        .unwrap_or_default()
        .into_iter()
        .map(|p| (p.id.clone(), p))
        .collect();

    // stamp -> (perm -> file)
    let mut byrun: BTreeMap<String, BTreeMap<String, std::path::PathBuf>> = BTreeMap::new();
    let dirs = std::fs::read_dir(&cfg.results_dir)
        .map_err(|e| format!("{}: {e}", cfg.results_dir.display()))?;
    for d in dirs.flatten() {
        if !d.path().is_dir() {
            continue;
        }
        let perm = d.file_name().to_string_lossy().to_string();
        let Ok(files) = std::fs::read_dir(d.path()) else {
            continue;
        };
        for f in files.flatten() {
            let p = f.path();
            if p.is_symlink() {
                continue;
            }
            let Some(name) = p.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            let Some(stamp) = name
                .strip_prefix("checks-")
                .and_then(|s| s.strip_suffix(".jsonl"))
            else {
                continue;
            };
            if stamp == "latest" {
                continue;
            }
            byrun
                .entry(stamp.to_string())
                .or_default()
                .insert(perm.clone(), p);
        }
        // The retired fixed-name file, from before results became timestamped.
        // Skipping it is only safe where a stamped run has superseded it - and
        // it is not: p01 and media-check have no stamped run at all, so that
        // file is their ONLY evidence. Ingest it under a stamp derived from its
        // mtime so it sorts with the rest and stays idempotent.
        let retired = d.path().join("checks.jsonl");
        if retired.is_file() && !retired.is_symlink() {
            let stamp = mtime_stamp(&retired);
            byrun
                .entry(stamp)
                .or_default()
                .insert(perm.clone(), retired);
        }
    }

    let conn = open_rw(&cfg.memory_db)?;
    conn.execute_batch(PACKAGE_LIFECYCLE_DDL)
        .map_err(|e| format!("package_lifecycle schema: {e}"))?;
    let host = hostname();
    let ver = env!("CARGO_PKG_VERSION");
    let mut sum = Summary {
        runs: 0,
        permutations: 0,
        checks: 0,
        packages: 0,
    };

    for (stamp, perms) in &byrun {
        // One run per stamp, keyed by the stamp itself so re-ingest updates
        // rather than duplicates.
        let selector: Vec<&str> = perms.keys().map(|s| s.as_str()).collect();
        let run_id: i64 = match conn.query_row(
            "SELECT id FROM run WHERE started_at = ?1",
            params![stamp],
            |r| r.get(0),
        ) {
            Ok(id) => {
                conn.execute(
                    "UPDATE run SET selector = ?2, tool_version = ?3 WHERE id = ?1",
                    params![id, selector.join(","), ver],
                )
                .map_err(|e| format!("{e}"))?;
                id
            }
            Err(_) => {
                conn.execute(
                    "INSERT INTO run (started_at, tool_version, host, selector) VALUES (?1,?2,?3,?4)",
                    params![stamp, ver, host, selector.join(",")],
                )
                .map_err(|e| format!("{e}"))?;
                conn.last_insert_rowid()
            }
        };
        sum.runs += 1;

        for (perm, file) in perms {
            let text = std::fs::read_to_string(file).unwrap_or_default();
            let recs: Vec<Record> = text.lines().filter_map(parse).collect();
            if recs.is_empty() {
                continue;
            }
            let fail = recs.iter().filter(|r| r.status == "fail").count();
            let pass = recs.iter().filter(|r| r.status == "pass").count();
            let result = if fail > 0 {
                format!("{fail} fail")
            } else {
                format!("{pass} pass")
            };
            let m = rows.get(perm);
            let (iso, poi, stig, fs, mode) = m
                .map(|p| {
                    (
                        p.iso_type.clone(),
                        p.poi.clone(),
                        p.stig.clone(),
                        p.fs.clone(),
                        p.mode.clone(),
                    )
                })
                .unwrap_or_else(|| ("?".into(), "?".into(), "?".into(), "?".into(), "?".into()));

            let pid: i64 = match conn.query_row(
                "SELECT id FROM permutation WHERE run_id = ?1 AND perm_id = ?2",
                params![run_id, perm],
                |r| r.get(0),
            ) {
                Ok(id) => {
                    conn.execute(
                        "UPDATE permutation SET result = ?2, finished_at = ?3 WHERE id = ?1",
                        params![id, result, stamp],
                    )
                    .map_err(|e| format!("{e}"))?;
                    id
                }
                Err(_) => {
                    conn.execute(
                        "INSERT INTO permutation
                           (run_id, perm_id, iso_type, poi, stig, fs, mode, ks_variant,
                            doc_verdict, expected, result, started_at, finished_at)
                         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?12)",
                        params![
                            run_id,
                            perm,
                            iso,
                            poi,
                            stig,
                            fs,
                            mode,
                            m.map(|p| p.variant.clone()).unwrap_or_default(),
                            m.map(|p| p.doc.clone()).unwrap_or_default(),
                            m.map(|p| p.expect.clone()).unwrap_or_default(),
                            result,
                            stamp
                        ],
                    )
                    .map_err(|e| format!("{e}"))?;
                    conn.last_insert_rowid()
                }
            };
            sum.permutations += 1;

            // Replace, never append: a re-ingest of the same evidence must not
            // double the checks.
            conn.execute(
                "DELETE FROM check_result WHERE permutation_id = ?1",
                params![pid],
            )
            .map_err(|e| format!("{e}"))?;
            for r in &recs {
                conn.execute(
                    "INSERT INTO check_result
                       (permutation_id, check_id, pr, status, expected, actual, detail, is_control, recorded_at)
                     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                    params![
                        pid,
                        r.check,
                        r.pr,
                        r.status,
                        r.expected,
                        r.actual,
                        r.detail,
                        is_control(&r.check) as i64,
                        stamp
                    ],
                )
                .map_err(|e| format!("{e}"))?;
                sum.checks += 1;
            }
            // The lifecycle records of the same run sit beside its checks
            // file under the same stamp.
            let life = file.with_file_name(format!("pkglife-{stamp}.jsonl"));
            if life.is_file() && !life.is_symlink() {
                sum.packages += ingest_lifecycle(&conn, pid, &life, stamp)?;
            }
        }
    }
    Ok(sum)
}

/// A stamp in the same shape the evidence writer produces, derived from a
/// file's mtime, so pre-timestamp evidence can be indexed alongside the rest.
fn mtime_stamp(p: &Path) -> String {
    let secs = std::fs::metadata(p)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // days -> y/m/d without a date crate; the value only has to be stable,
    // ordered and unique per file.
    let days = secs / 86_400;
    let rem = secs % 86_400;
    let (mut y, mut d) = (1970u64, days);
    loop {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
        let len = if leap { 366 } else { 365 };
        if d < len {
            break;
        }
        d -= len;
        y += 1;
    }
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let ml = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    let mut m = 0usize;
    while m < 12 && d >= ml[m] {
        d -= ml[m];
        m += 1;
    }
    format!(
        "{y:04}{:02}{:02}T{:02}{:02}{:02}Z",
        m + 1,
        d + 1,
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60
    )
}

fn hostname() -> String {
    std::process::Command::new("hostname")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_record_without_a_perm_or_check_is_skipped_not_guessed() {
        assert!(parse(r#"{"perm":"k01","check":"a","status":"pass"}"#).is_some());
        assert!(parse(r#"{"check":"a","status":"pass"}"#).is_none());
        assert!(parse(r#"{"perm":"k01","status":"pass"}"#).is_none());
        assert!(parse("not json").is_none());
    }

    fn schema(conn: &Connection) {
        conn.execute_batch(
            "CREATE TABLE permutation (id INTEGER PRIMARY KEY, finished_at TEXT, perm_id TEXT);
             INSERT INTO permutation (id, perm_id, finished_at) VALUES (1, 'k09', 's1');",
        )
        .unwrap();
        conn.execute_batch(PACKAGE_LIFECYCLE_DDL).unwrap();
    }

    #[test]
    fn lifecycle_records_are_replaced_not_appended() {
        let conn = Connection::open_in_memory().unwrap();
        schema(&conn);
        let d = std::env::temp_dir().join(format!("sharukhan-ing-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let f = d.join("pkglife-s1.jsonl");
        std::fs::write(
            &f,
            concat!(
                r#"{"package":"chrony","evr":"4.3-3.ph5","arch":"x86_64","origin":"fresh","classes":["daemon","cli"],"verdict":"pass","reason":"","duration_ms":9000,"steps":[{"status":"pass"}],"units":[],"clis":[]}"#,
                "\n",
                r#"{"package":"nginx","verdict":"fail","steps":[{"status":"fail"}],"units":[{"status":"fail"}],"clis":[{"status":"pass"}]}"#,
                "\n",
                "not json\n",
                r#"{"package":"","verdict":"pass"}"#,
                "\n"
            ),
        )
        .unwrap();
        assert_eq!(ingest_lifecycle(&conn, 1, &f, "s1").unwrap(), 2);
        assert_eq!(ingest_lifecycle(&conn, 1, &f, "s1").unwrap(), 2);
        let n: i64 = conn
            .query_row("SELECT COUNT(*) FROM package_lifecycle", [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 2, "a re-ingest must not double the rows");
        let (classes, failed): (String, i64) = conn
            .query_row(
                "SELECT classes, (SELECT failed_parts FROM package_lifecycle WHERE package='nginx')
                 FROM package_lifecycle WHERE package='chrony'",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(classes, "daemon,cli");
        assert_eq!(failed, 2);
        let v: String = conn
            .query_row(
                "SELECT verdict FROM v_package_lifecycle WHERE package='nginx'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(v, "fail");
        std::fs::remove_dir_all(&d).ok();
    }

    /// schema/memory.sql is how a lost database is recreated; it must carry
    /// the same table ingest creates.
    #[test]
    fn the_schema_file_mirrors_the_lifecycle_ddl() {
        let sql = include_str!("../schema/memory.sql");
        let norm = |s: &str| s.split_whitespace().collect::<Vec<_>>().join(" ");
        assert!(norm(sql).contains(&norm(PACKAGE_LIFECYCLE_DDL)));
    }

    #[test]
    fn only_the_lifecycle_controls_are_flagged_as_controls() {
        assert!(is_control("pkg.control.journal"));
        assert!(!is_control("pkg.life.chrony"));
        assert!(!is_control("media.negative_control"));
    }

    #[test]
    fn missing_optional_fields_become_empty_rather_than_failing() {
        let r = parse(r#"{"perm":"k01","check":"guest.selinux"}"#).unwrap();
        assert_eq!(r.perm, "k01");
        assert_eq!(r.status, "");
        assert_eq!(r.detail, "");
    }
}
