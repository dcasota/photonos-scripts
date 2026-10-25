//! `sharukhan db render [<memory.db>] <MEMORY.md>`: MEMORY.md as a view of the
//! memory database (it replaced tools/gen-memory-md.py, same SQL, same text).
//!
//! Every fact is read at render time and the file names its database and the
//! moment, so a stale render is visible rather than silently authoritative.
//! The database is opened read-only: a render never writes to it, and can run
//! while a gate is recording.

use std::path::Path;

fn sev_rank(s: &str) -> u8 {
    match s {
        "blocker" => 0,
        "high" => 1,
        "medium" => 2,
        "low" => 3,
        _ => 9,
    }
}

fn capitalize(s: &str) -> String {
    let mut c = s.chars();
    c.next().map(|f| f.to_uppercase().collect::<String>() + &c.as_str().to_lowercase()).unwrap_or_default()
}

struct Finding {
    slug: String,
    title: String,
    cat: String,
    sev: String,
    ev: String,
    cons: String,
    mit: Option<String>,
    verified: bool,
    src: Option<String>,
}

pub fn render(db_path: &Path, now: &str) -> Result<(String, usize, usize), String> {
    if !db_path.exists() {
        return Err(format!("no database at {}", db_path.display()));
    }
    let db = crate::job::open_ro(db_path)?;
    let sql = |e: rusqlite::Error| format!("{}: {e}", db_path.display());
    let count = |t: &str| -> Result<i64, String> { db.query_row(&format!("SELECT COUNT(*) FROM {t}"), [], |r| r.get(0)).map_err(sql) };
    let text = |r: &rusqlite::Row, i: usize| -> rusqlite::Result<String> { Ok(r.get::<_, Option<String>>(i)?.unwrap_or_default()) };
    let mut findings: Vec<Finding> = db
        .prepare("SELECT slug,title,category,severity,evidence,consequence,mitigation,verified,source FROM finding WHERE superseded_by IS NULL")
        .and_then(|mut s| {
            s.query_map([], |r| {
                Ok(Finding {
                    slug: text(r, 0)?,
                    title: text(r, 1)?,
                    cat: text(r, 2)?,
                    sev: text(r, 3)?,
                    ev: text(r, 4)?,
                    cons: text(r, 5)?,
                    mit: r.get::<_, Option<String>>(6)?.filter(|m| !m.is_empty()),
                    verified: r.get::<_, Option<i64>>(7)?.unwrap_or(0) != 0,
                    src: r.get::<_, Option<String>>(8)?.filter(|m| !m.is_empty()),
                })
            })
            .map(|rows| rows.flatten().collect())
        })
        .map_err(sql)?;
    findings.sort_by(|a, b| (sev_rank(&a.sev), &a.cat, &a.slug).cmp(&(sev_rank(&b.sev), &b.cat, &b.slug)));
    let (runs, perms, checks, arts) = (count("run")?, count("permutation")?, count("check_result")?, count("artifact")?);
    let open_blockers: i64 =
        db.query_row("SELECT COUNT(*) FROM finding WHERE severity='blocker' AND verified=0", [], |r| r.get(0)).map_err(sql)?;

    let mut l: Vec<String> = Vec::new();
    let db_s = db_path.display();
    l.extend(
        [
            "# MEMORY.md".to_string(),
            String::new(),
            "**Generated. Do not edit.** This file is a rendering of the sharukhan memory".into(),
            "database; the database is the system of record. Editing here changes nothing and".into(),
            "will be overwritten on the next render.".into(),
            String::new(),
            format!("- Source database: `{db_s}`"),
            format!("- Rendered at: {now}"),
            format!("- Regenerate with: `sharukhan db render {db_s} MEMORY.md`"),
            String::new(),
            "| Table | Rows |".into(),
            "|---|---|".into(),
            format!("| `run` | {runs} |"),
            format!("| `permutation` | {perms} |"),
            format!("| `check_result` | {checks} |"),
            format!("| `artifact` | {arts} |"),
            format!("| `finding` | {} |", findings.len()),
            String::new(),
        ],
    );
    if open_blockers > 0 {
        l.push(format!("> **{open_blockers} unresolved blocker finding(s).** See the Blocker section."));
        l.push(String::new());
    }

    // the permutation report, straight from the view so it cannot drift from the CLI
    let rows: Vec<Vec<String>> = db
        .prepare("SELECT perm_id,iso_type,poi,stig,fs,mode,doc_verdict,result,failed_checks,prs_implicated FROM v_permutation_report ORDER BY perm_id")
        .and_then(|mut s| {
            s.query_map([], |r| {
                (0..10)
                    .map(|i| {
                        Ok(match r.get_ref(i)? {
                            rusqlite::types::ValueRef::Null => String::new(),
                            rusqlite::types::ValueRef::Integer(n) => n.to_string(),
                            rusqlite::types::ValueRef::Real(f) => f.to_string(),
                            rusqlite::types::ValueRef::Text(t) => String::from_utf8_lossy(t).to_string(),
                            rusqlite::types::ValueRef::Blob(b) => String::from_utf8_lossy(b).to_string(),
                        })
                    })
                    .collect::<rusqlite::Result<Vec<String>>>()
            })
            .map(|rows| rows.flatten().collect())
        })
        .map_err(sql)?;
    l.push("## Permutation results".into());
    l.push(String::new());
    if rows.is_empty() {
        l.push("_No permutation has completed yet._".into());
    } else {
        l.push("| ID | ISO | POI | STIG | FS | Mode | Matrix said | Result | Failed | PRs implicated |".into());
        l.push("|---|---|---|---|---|---|---|---|---|---|".into());
        for r in &rows {
            l.push(format!("| {} |", r.join(" | ")));
        }
        l.push(String::new());
        l.push("A result that reproduces the *Matrix said* value of `fails` is a PR regression.".into());
    }
    l.push(String::new());

    l.push("## Findings".into());
    l.push(String::new());
    let mut cur: Option<&str> = None;
    for f in &findings {
        if cur != Some(f.sev.as_str()) {
            cur = Some(f.sev.as_str());
            l.push(format!("### {}", capitalize(&f.sev)));
            l.push(String::new());
        }
        let flag = if f.verified { "verified" } else { "**UNRESOLVED**" };
        l.push(format!("#### `{}` — {}", f.slug, f.title));
        l.push(String::new());
        l.push(format!("*{} · {flag}*{}", f.cat, f.src.as_ref().map(|s| format!(" · source: `{s}`")).unwrap_or_default()));
        l.push(String::new());
        l.push(format!("**Observed.** {}", f.ev));
        l.push(String::new());
        l.push(format!("**Consequence.** {}", f.cons));
        if let Some(m) = &f.mit {
            l.push(String::new());
            l.push(format!("**Mitigation.** {m}"));
        }
        l.push(String::new());
    }

    // control integrity: a run whose negative controls passed proves nothing
    let ci: Vec<(String, i64, i64)> = db
        .prepare("SELECT perm_id,controls,controls_ok FROM v_control_integrity WHERE controls > 0 ORDER BY perm_id")
        .and_then(|mut s| s.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map(|rows| rows.flatten().collect()))
        .map_err(sql)?;
    if !ci.is_empty() {
        l.extend([
            "## Negative-control integrity".to_string(),
            String::new(),
            "A permutation whose controls did not all hold is **inconclusive**, not passing.".into(),
            String::new(),
            "| Permutation | Controls | Held |".into(),
            "|---|---|---|".into(),
        ]);
        for (p, c, ok) in &ci {
            l.push(format!("| {p} | {c} | {ok} |"));
        }
        l.push(String::new());
    }
    Ok((l.join("\n") + "\n", findings.len(), rows.len()))
}

pub fn cli(cfg: &crate::config::Config, args: &[String]) -> Result<(), String> {
    let usage = "sharukhan db render [<memory.db>] <MEMORY.md>";
    if args.first().map(String::as_str) != Some("render") {
        return Err(usage.into());
    }
    let (db, out) = match &args[1..] {
        [out] => (cfg.memory_db.clone(), std::path::PathBuf::from(out)),
        [db, out] => (std::path::PathBuf::from(db), std::path::PathBuf::from(out)),
        _ => return Err(usage.into()),
    };
    let (text, nf, nr) = render(&db, &crate::job::now())?;
    std::fs::write(&out, text).map_err(|e| format!("{}: {e}", out.display()))?;
    println!("  rendered {}: {nf} findings, {nr} permutation rows", out.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn a_render_is_grouped_by_severity_and_flags_blockers() {
        let d = std::env::temp_dir().join(format!("shk-render-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let p = d.join("m.db");
        let _ = std::fs::remove_file(&p);
        let c = Connection::open(&p).unwrap();
        c.execute_batch(
            "CREATE TABLE run(id INTEGER); CREATE TABLE permutation(id INTEGER); CREATE TABLE check_result(id INTEGER); CREATE TABLE artifact(id INTEGER);
             CREATE TABLE finding(slug TEXT,title TEXT,category TEXT,severity TEXT,evidence TEXT,consequence TEXT,mitigation TEXT,verified INTEGER,source TEXT,superseded_by INTEGER);
             CREATE VIEW v_permutation_report AS SELECT 'k03' perm_id,'minimal' iso_type,'2.8' poi,'yes' stig,'ext4' fs,'ks' mode,'fails' doc_verdict,'pass' result,0 failed_checks,NULL prs_implicated;
             CREATE VIEW v_control_integrity AS SELECT 'k03' perm_id, 0 controls, 0 controls_ok;
             INSERT INTO finding VALUES ('b','B','build','low','e','c',NULL,1,NULL,NULL),('a','A','build','blocker','e','c','m',0,'s',NULL),('z','Z','x','high','e','c',NULL,1,NULL,5);",
        )
        .unwrap();
        drop(c);
        let (t, nf, nr) = render(&p, "2026-10-24T00:00:00Z").unwrap();
        assert_eq!((nf, nr), (2, 1), "a superseded finding is not rendered");
        assert!(t.contains("> **1 unresolved blocker finding(s).**"));
        let (bl, lo) = (t.find("### Blocker").unwrap(), t.find("### Low").unwrap());
        assert!(bl < lo);
        assert!(t.contains("*build · **UNRESOLVED*** · source: `s`") || t.contains("*build · **UNRESOLVED*** · source: `s`"));
        assert!(t.contains("| k03 | minimal | 2.8 | yes | ext4 | ks | fails | pass | 0 |  |"));
        assert!(!t.contains("Negative-control integrity"));
        let _ = std::fs::remove_dir_all(&d);
    }
}
