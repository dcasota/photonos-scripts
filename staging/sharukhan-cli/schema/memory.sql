-- sharukhan memory database schema.
--
-- Generated from the live database on 2026-09-09T22:27:02Z, which is the
-- system of record. sharukhan opens this database READ-ONLY (src/memory.rs) and
-- never creates it, so without this file a lost database could not be recreated
-- from anything in the repository.
--
-- Apply with:  sqlite3 memory.db < schema/memory.sql

CREATE TABLE IF NOT EXISTS run (
    id             INTEGER PRIMARY KEY,
    started_at     TEXT NOT NULL,           -- ISO-8601 UTC
    finished_at    TEXT,
    tool_version   TEXT NOT NULL,
    host           TEXT NOT NULL,
    selector       TEXT,                    -- --only / --all as given
    exit_code      INTEGER
);
CREATE TABLE IF NOT EXISTS permutation (
    id             INTEGER PRIMARY KEY,
    run_id         INTEGER NOT NULL REFERENCES run(id),
    perm_id        TEXT NOT NULL,           -- p01, k03, s02 ...
    iso_type       TEXT NOT NULL,
    poi            TEXT NOT NULL,
    stig           TEXT NOT NULL,
    fs             TEXT NOT NULL,
    mode           TEXT NOT NULL,           -- ks | ui
    ks_variant     TEXT,
    doc_verdict    TEXT,                    -- what the matrix recorded pre-PR
    expected       TEXT,
    result         TEXT,                    -- pass | fail | error | skipped
    started_at     TEXT,
    finished_at    TEXT,
    UNIQUE (run_id, perm_id)
);
CREATE TABLE IF NOT EXISTS check_result (
    id             INTEGER PRIMARY KEY,
    permutation_id INTEGER NOT NULL REFERENCES permutation(id),
    check_id       TEXT NOT NULL,           -- media.stig_packages, guest.selinux ...
    pr             TEXT,                    -- PR#22, POI#11, or NULL
    status         TEXT NOT NULL,           -- pass | fail | skip | info
    expected       TEXT,
    actual         TEXT,
    detail         TEXT,
    is_control     INTEGER NOT NULL DEFAULT 0,  -- negative controls
    recorded_at    TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS artifact (
    id             INTEGER PRIMARY KEY,
    run_id         INTEGER REFERENCES run(id),
    permutation_id INTEGER REFERENCES permutation(id),
    kind           TEXT NOT NULL,           -- iso | patch | kickstart | vmx | log | tree
    path           TEXT NOT NULL,
    sha256         TEXT,
    note           TEXT,
    recorded_at    TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS finding (
    id             INTEGER PRIMARY KEY,
    slug           TEXT NOT NULL UNIQUE,
    title          TEXT NOT NULL,
    category       TEXT NOT NULL,           -- portability | hypervisor | build | tooling | defect
    severity       TEXT NOT NULL,           -- blocker | high | medium | low
    evidence       TEXT NOT NULL,           -- what was actually observed
    consequence    TEXT NOT NULL,           -- what it breaks if ignored
    mitigation     TEXT,                    -- what sharukhan must do
    verified       INTEGER NOT NULL DEFAULT 0,
    source         TEXT,                    -- where it was found
    recorded_at    TEXT NOT NULL,
    superseded_by  INTEGER REFERENCES finding(id)
);
CREATE TABLE IF NOT EXISTS job (
    id             INTEGER PRIMARY KEY,
    run_id         INTEGER REFERENCES run(id),
    kind           TEXT NOT NULL,           -- build | install | verify
    label          TEXT NOT NULL,
    pid            INTEGER,
    state          TEXT NOT NULL,           -- running | done | failed | stopped
    log_path       TEXT,
    started_at     TEXT NOT NULL,
    finished_at    TEXT
);
CREATE INDEX IF NOT EXISTS idx_check_perm   ON check_result(permutation_id);
CREATE INDEX IF NOT EXISTS idx_check_pr     ON check_result(pr) WHERE pr IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_check_status ON check_result(status);
CREATE INDEX IF NOT EXISTS idx_perm_run     ON permutation(run_id);
CREATE INDEX IF NOT EXISTS idx_finding_cat  ON finding(category);
CREATE VIEW IF NOT EXISTS v_permutation_report AS
SELECT p.perm_id, p.iso_type, p.poi, p.stig, p.fs, p.mode,
       p.doc_verdict, p.result,
       (SELECT COUNT(*) FROM check_result c WHERE c.permutation_id = p.id AND c.status='fail') AS failed_checks,
       (SELECT GROUP_CONCAT(DISTINCT c.pr) FROM check_result c
          WHERE c.permutation_id = p.id AND c.status='fail' AND c.pr IS NOT NULL) AS prs_implicated
FROM permutation p
/* v_permutation_report(perm_id,iso_type,poi,stig,fs,mode,doc_verdict,result,failed_checks,prs_implicated) */;
CREATE VIEW IF NOT EXISTS v_control_integrity AS
SELECT p.perm_id,
       SUM(CASE WHEN c.is_control=1 THEN 1 ELSE 0 END) AS controls,
       SUM(CASE WHEN c.is_control=1 AND c.status='pass' THEN 1 ELSE 0 END) AS controls_ok
FROM permutation p LEFT JOIN check_result c ON c.permutation_id = p.id
GROUP BY p.perm_id
/* v_control_integrity(perm_id,controls,controls_ok) */;
CREATE TABLE IF NOT EXISTS next_step (
  id INTEGER PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  rationale TEXT,
  blocked_by TEXT,
  est_cost TEXT,
  priority INTEGER,
  state TEXT DEFAULT 'open',
  recorded_at TEXT
);
