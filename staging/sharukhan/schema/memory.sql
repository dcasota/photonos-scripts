-- sharukhan memory database.
--
-- The system of record. MEMORY.md is a generated VIEW over this file, never a
-- parallel copy, so the two cannot disagree.
--
-- Every write is parameterised at the call site; no statement in sharukhan is
-- built by string concatenation. Columns that could carry a credential are
-- redacted at the boundary before insert, and that redaction is tested.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- A single invocation of the tool.
CREATE TABLE IF NOT EXISTS run (
    id             INTEGER PRIMARY KEY,
    started_at     TEXT NOT NULL,           -- ISO-8601 UTC
    finished_at    TEXT,
    tool_version   TEXT NOT NULL,
    host           TEXT NOT NULL,
    selector       TEXT,                    -- --only / --all as given
    exit_code      INTEGER
);

-- One attempt at one permutation within a run.
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

-- One assertion. `pr` is what turns a failure into "PR#22 regressed".
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

-- Anything produced or consumed that must stay attributable.
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

-- Durable knowledge: a trap, a defect, or an environment fact worth not
-- rediscovering. This is the table MEMORY.md mostly renders.
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

-- Background work the tool can list, inspect and stop.
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

-- The report table, as a view, so the CLI and MEMORY.md cannot drift apart.
CREATE VIEW IF NOT EXISTS v_permutation_report AS
SELECT p.perm_id, p.iso_type, p.poi, p.stig, p.fs, p.mode,
       p.doc_verdict, p.result,
       (SELECT COUNT(*) FROM check_result c WHERE c.permutation_id = p.id AND c.status='fail') AS failed_checks,
       (SELECT GROUP_CONCAT(DISTINCT c.pr) FROM check_result c
          WHERE c.permutation_id = p.id AND c.status='fail' AND c.pr IS NOT NULL) AS prs_implicated
FROM permutation p;

-- A run is only trustworthy if its negative controls actually failed.
CREATE VIEW IF NOT EXISTS v_control_integrity AS
SELECT p.perm_id,
       SUM(CASE WHEN c.is_control=1 THEN 1 ELSE 0 END) AS controls,
       SUM(CASE WHEN c.is_control=1 AND c.status='pass' THEN 1 ELSE 0 END) AS controls_ok
FROM permutation p LEFT JOIN check_result c ON c.permutation_id = p.id
GROUP BY p.perm_id;
