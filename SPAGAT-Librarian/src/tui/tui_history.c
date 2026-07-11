/* ---------------------------------------------------------------------------
 * tui_history.c — Phase-2 implementation of the M18 history view (kanban
 * view #2). This file is the C-side production replacement for the operator
 * shim at src/tools/spagat-console-shims/m18_history_probe.py and provides
 * the definitions for every function declared in
 *
 *     src/containers/spagat-console/include/spagat_history.h
 *
 * NOTICE / UPSTREAM-WORTHY FRAMING
 * --------------------------------
 * This file extends the v0.3.0 ncurses/SQLite spagat-console (memory:
 * project-existing-v03-console). It is CLI-app territory — operator-facing,
 * regression-tested, and upstream-worthy. Per
 * feedback_local_first_test_before_upstream the workflow is:
 *
 *     1. operator builds + runs the regression suite in WSL2 / VMware
 *        Workstation on a Linux host with CMake + ncurses + sqlite3;
 *     2. only after green smokes does the change get pushed upstream to
 *        photonos-scripts/SPAGAT-Librarian.
 *
 * NEEDS-OPERATOR-VALIDATION-IN-WSL2
 * ---------------------------------
 * I (the agent) cannot compile this on the appliance Windows host. The
 * operator validates by running, on a Linux host:
 *
 *     make -C src/containers/spagat-console build
 *
 * (CMake + ncurses + sqlite3 toolchain). Every NEEDS-OPERATOR-VALIDATION-
 * IN-WSL2 marker below flags a syscall or third-party API surface that the
 * agent could not link/compile here and that the operator MUST exercise on
 * the reference WSL/Linux host before any upstream push.
 *
 * Cross-references
 * ----------------
 *   - Header / contract:        src/containers/spagat-console/include/spagat_history.h
 *   - Design doc (normative):   docs/M18-history-view-design.md
 *   - Acceptance fixtures:      tests/fixtures/m18-acceptance.yaml
 *                               (15 fixtures M18-1 .. M18-15)
 *   - Python sibling shim:      src/tools/spagat-console-shims/m18_history_probe.py
 *                               (mirrors the same contract from outside the
 *                               C tree; this file's algorithm choices
 *                               follow it unless the C-side has a clearly
 *                               better option, in which case see the
 *                               NEEDS-V3-OPTIMIZATION markers below)
 *   - Parent style header:      src/containers/spagat-console/include/spagat.h
 *   - Sibling tui_*.c pattern:  src/containers/spagat-console/src/tui/tui_dialogs.c
 *   - Project helpers:          src/containers/spagat-console/src/util/util.h
 *
 * Driving rule: feedback-no-guess-lowest-impact-per-step — when a syscall
 * constant, ncurses function, or sqlite3 API is uncertain the call is
 * paired with a NEEDS-OPERATOR-VALIDATION-IN-WSL2 marker rather than
 * invented out of thin air.
 * ---------------------------------------------------------------------------
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "spagat_history.h"
#include "../util/util.h"

/* sqlite3 is the storage layer per ADR-0022 D3 (WAL mode, NORMAL sync).
 * NEEDS-OPERATOR-VALIDATION-IN-WSL2: <sqlite3.h> is not present on the
 * agent's Windows host; the operator must confirm the include path resolves
 * against the appliance Linux toolchain (libsqlite3-dev). */
#include <sqlite3.h>

/* --------------------------------------------------------------------------
 * File-internal state. The header documents that the connection is
 * process-global ("callers MUST pair every successful open() with a
 * close()"), so the SQLite handle lives as a static module global.
 * No other globals — keeps the surface composable.
 * -------------------------------------------------------------------------- */
static sqlite3 *g_history_db = NULL;

/* Initial reserve for result arrays. Pagination caps at 100 rows
 * (M18-15 / SpagatHistoryQuery.limit default), so 16 is a sane first hop
 * before we grow geometrically. */
#define HISTORY_INITIAL_CAP 16

/* Schema mirrors the Python shim verbatim (m18_history_probe.py _SCHEMA)
 * so the two implementations stay byte-compatible on the same DB file. */
static const char *kHistorySchemaSQL =
    "CREATE TABLE IF NOT EXISTS history_records ("
    "    event_id       TEXT PRIMARY KEY,"
    "    package        TEXT,"
    "    verdict        TEXT,"
    "    timestamp      INTEGER NOT NULL,"
    "    severity       TEXT NOT NULL,"
    "    rpm_nvr        TEXT,"
    "    provenance     TEXT,"
    "    ttl_expires_at INTEGER"
    ");"
    "CREATE INDEX IF NOT EXISTS h_by_ts       ON history_records (timestamp DESC);"
    "CREATE INDEX IF NOT EXISTS h_by_package  ON history_records (package);"
    "CREATE INDEX IF NOT EXISTS h_by_verdict  ON history_records (verdict);"
    "CREATE INDEX IF NOT EXISTS h_by_severity ON history_records (severity);"
    "CREATE INDEX IF NOT EXISTS h_by_ttl"
    "    ON history_records (ttl_expires_at)"
    "    WHERE ttl_expires_at IS NOT NULL;";

/* Mapping from the SpagatHistorySeverity enum to the TEXT representation
 * stored in the `severity` column. Index by enum value. */
static const char *kSeverityNames[] = {
    "CRITICAL", /* SEV_CRITICAL = 0 */
    "HIGH",     /* SEV_HIGH     = 1 */
    "MEDIUM",   /* SEV_MEDIUM   = 2 */
    "LOW",      /* SEV_LOW      = 3 */
    "INFO"      /* SEV_INFO     = 4 */
};
#define HISTORY_SEVERITY_COUNT \
    ((int)(sizeof(kSeverityNames) / sizeof(kSeverityNames[0])))

/* Reverse map: severity TEXT -> SpagatHistorySeverity. Defaults to
 * SEV_INFO for unrecognised values (the most permissive bucket — matches
 * the shim's behaviour when severity is missing from a source record). */
static SpagatHistorySeverity history_severity_from_text(const char *text) {
    if (text != NULL) {
        for (int i = 0; i < HISTORY_SEVERITY_COUNT; i++) {
            if (str_equals_ignore_case(text, kSeverityNames[i])) {
                return (SpagatHistorySeverity)i;
            }
        }
    }
    return SEV_INFO;
}

/* spagat_history.h line 112:
 *   int spagat_history_open(const char *db_path);
 *
 * Open (and lazily initialise) the history SQLite database. Mirrors the
 * Python shim's open_db() — WAL mode, synchronous=NORMAL, schema applied
 * idempotently. On first open we additionally run PRAGMA integrity_check
 * per M18-12; a non-"ok" verdict closes the handle and returns -1 so the
 * caller can trigger the rebuild-from-sources path documented in the
 * design doc §6.
 *
 * Acceptance: M18-1 (indexer ingest), M18-2 (open-and-render budget),
 *             M18-12 (integrity-check at startup). */
int spagat_history_open(const char *db_path) {
    if (db_path == NULL || db_path[0] == '\0') return -1;
    if (g_history_db != NULL) return 0; /* already open — idempotent */

    /* NEEDS-OPERATOR-VALIDATION-IN-WSL2: sqlite3_open_v2 + SQLITE_OPEN_*
     * flags are sqlite3-amalgamation specific; verify the link line in
     * src/containers/spagat-console/CMakeLists.txt picks up libsqlite3. */
    int rc = sqlite3_open_v2(
        db_path, &g_history_db,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
    if (rc != SQLITE_OK) {
        if (g_history_db != NULL) {
            sqlite3_close(g_history_db);
            g_history_db = NULL;
        }
        return -1;
    }

    /* ADR-0022 D3: WAL mode + NORMAL sync. Failure to set these is not
     * fatal (the DB still opens) but logged-via-return so callers can
     * downgrade gracefully. */
    char *err = NULL;
    (void)sqlite3_exec(g_history_db, "PRAGMA journal_mode=WAL;", NULL, NULL, &err);
    if (err != NULL) { sqlite3_free(err); err = NULL; }
    (void)sqlite3_exec(g_history_db, "PRAGMA synchronous=NORMAL;", NULL, NULL, &err);
    if (err != NULL) { sqlite3_free(err); err = NULL; }

    /* Apply schema idempotently. The CREATE statements use IF NOT EXISTS
     * so this is safe on every open. */
    rc = sqlite3_exec(g_history_db, kHistorySchemaSQL, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        if (err != NULL) sqlite3_free(err);
        sqlite3_close(g_history_db);
        g_history_db = NULL;
        return -1;
    }

    /* M18-12: PRAGMA integrity_check at first open. A non-"ok" verdict
     * signals corruption; we close + return -1 so the caller can rebuild
     * from the federated sources (see design doc §6). */
    sqlite3_stmt *stmt = NULL;
    rc = sqlite3_prepare_v2(g_history_db, "PRAGMA integrity_check;", -1, &stmt, NULL);
    if (rc == SQLITE_OK && stmt != NULL) {
        bool integrity_ok = false;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *verdict = sqlite3_column_text(stmt, 0);
            if (verdict != NULL && strcmp((const char *)verdict, "ok") == 0) {
                integrity_ok = true;
            }
        }
        sqlite3_finalize(stmt);
        if (!integrity_ok) {
            sqlite3_close(g_history_db);
            g_history_db = NULL;
            return -1;
        }
    }
    /* If prepare failed (very old sqlite3) we deliberately fall through —
     * integrity_check is best-effort hardening, not load-bearing for
     * basic reads. */

    return 0;
}

/* spagat_history.h line 118:
 *   void spagat_history_close(void);
 *
 * Close the indexer DB. Safe to call when no DB is open — the function
 * is idempotent so the M18-12 rebuild path can call close() blindly
 * before re-opening.
 *
 * Acceptance: M18-12 (clean shutdown is part of the rebuild path). */
void spagat_history_close(void) {
    if (g_history_db != NULL) {
        /* sqlite3_close flushes any pending WAL frames via its checkpoint
         * on close. */
        sqlite3_close(g_history_db);
        g_history_db = NULL;
    }
}

/* spagat_history.h line 136-138:
 *   int spagat_history_query(const SpagatHistoryQuery *q,
 *                            SpagatHistoryRecord **out,
 *                            size_t *n_out);
 *
 * Run a parameterised query against the history index. Algorithm follows
 * the Python shim's query() byte-for-byte: each filter is bound via `?`
 * placeholders (M18-14), severity is treated as a numeric lower-bound
 * filter expanded into an `IN (?,?,...)` allowlist of severity texts, and
 * rows are ordered by timestamp DESC for the F2 default render.
 *
 * Acceptance: M18-3 (incremental filter latency), M18-4 (compound filter
 *             AND semantics), M18-7 (view_audit per search — TODO see
 *             NEEDS-V3-OPTIMIZATION below), M18-14 (SQL injection probe →
 *             0 rows, no schema effect), M18-15 (pagination cursor for
 *             > 100 row result sets — caller enforces limit). */
int spagat_history_query(const SpagatHistoryQuery *q,
                         SpagatHistoryRecord **out,
                         size_t *n_out) {
    if (out == NULL || n_out == NULL) return -1;
    *out = NULL;
    *n_out = 0;
    if (q == NULL || g_history_db == NULL) return -1;

    /* Build the SQL incrementally. Every filter compiles to a bound
     * placeholder — see M18-14 (`pkg:'; DROP TABLE ...` becomes a literal
     * substring under `package LIKE ?` and returns 0 rows). */
    char sql[2048];
    int written = snprintf(sql, sizeof(sql),
        "SELECT event_id, package, verdict, timestamp, severity, rpm_nvr "
        "FROM history_records WHERE 1=1");
    if (written < 0 || (size_t)written >= sizeof(sql)) return -1;

    if (q->package != NULL) {
        written += snprintf(sql + written, sizeof(sql) - written,
                            " AND package LIKE ?");
    }
    if (q->verdict != NULL) {
        written += snprintf(sql + written, sizeof(sql) - written,
                            " AND verdict = ?");
    }
    if (q->since != 0) {
        written += snprintf(sql + written, sizeof(sql) - written,
                            " AND timestamp >= ?");
    }
    if (q->until != 0) {
        written += snprintf(sql + written, sizeof(sql) - written,
                            " AND timestamp < ?");
    }

    /* Severity allowlist: SEV_CRITICAL (0) is most severe; min_severity
     * is the LEAST-restrictive bucket the caller will accept, so rows
     * whose severity rank is <= min_severity rank are returned. We expand
     * to `severity IN (?,?,...)` with one placeholder per allowed name
     * to keep the SQL parameterised (no string concatenation of values). */
    int sev_lo = 0;
    int sev_hi = (int)q->min_severity;
    if (sev_hi < 0) sev_hi = 0;
    if (sev_hi >= HISTORY_SEVERITY_COUNT) sev_hi = HISTORY_SEVERITY_COUNT - 1;
    int sev_count = sev_hi - sev_lo + 1;

    written += snprintf(sql + written, sizeof(sql) - written,
                        " AND severity IN (");
    for (int i = 0; i < sev_count; i++) {
        written += snprintf(sql + written, sizeof(sql) - written,
                            "%s?", i == 0 ? "" : ",");
    }
    written += snprintf(sql + written, sizeof(sql) - written, ")");

    int limit = q->limit > 0 ? q->limit : 100; /* M18-15 default page */
    int offset = q->offset > 0 ? q->offset : 0;
    written += snprintf(sql + written, sizeof(sql) - written,
                        " ORDER BY timestamp DESC LIMIT ? OFFSET ?");
    if (written < 0 || (size_t)written >= sizeof(sql)) return -1;

    sqlite3_stmt *stmt = NULL;
    /* NEEDS-OPERATOR-VALIDATION-IN-WSL2: sqlite3_prepare_v2 link surface;
     * verify against the appliance toolchain. */
    int rc = sqlite3_prepare_v2(g_history_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (stmt != NULL) sqlite3_finalize(stmt);
        return -1;
    }

    /* Bind in the same order as the clauses were appended. */
    int bind_idx = 1;
    char like_buf[SPAGAT_HISTORY_MAX_PACKAGE_LEN + 4];
    if (q->package != NULL) {
        snprintf(like_buf, sizeof(like_buf), "%%%s%%", q->package);
        sqlite3_bind_text(stmt, bind_idx++, like_buf, -1, SQLITE_TRANSIENT);
    }
    if (q->verdict != NULL) {
        sqlite3_bind_text(stmt, bind_idx++, q->verdict, -1, SQLITE_TRANSIENT);
    }
    if (q->since != 0) {
        sqlite3_bind_int64(stmt, bind_idx++, (sqlite3_int64)q->since);
    }
    if (q->until != 0) {
        sqlite3_bind_int64(stmt, bind_idx++, (sqlite3_int64)q->until);
    }
    for (int i = 0; i < sev_count; i++) {
        sqlite3_bind_text(stmt, bind_idx++, kSeverityNames[sev_lo + i],
                          -1, SQLITE_STATIC);
    }
    sqlite3_bind_int(stmt, bind_idx++, limit);
    sqlite3_bind_int(stmt, bind_idx++, offset);

    /* Materialise rows. Grow geometrically — the header guarantees the
     * caller frees via spagat_history_free_results, so this single buffer
     * is the only owned allocation. */
    size_t cap = HISTORY_INITIAL_CAP;
    size_t n = 0;
    SpagatHistoryRecord *buf = calloc(cap, sizeof(*buf));
    if (buf == NULL) {
        sqlite3_finalize(stmt);
        return -1;
    }

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (n == cap) {
            size_t new_cap = cap * 2;
            SpagatHistoryRecord *grown = realloc(buf, new_cap * sizeof(*grown));
            if (grown == NULL) {
                free(buf);
                sqlite3_finalize(stmt);
                return -1;
            }
            memset(grown + cap, 0, (new_cap - cap) * sizeof(*grown));
            buf = grown;
            cap = new_cap;
        }

        SpagatHistoryRecord *r = &buf[n];
        const unsigned char *event_id = sqlite3_column_text(stmt, 0);
        const unsigned char *package  = sqlite3_column_text(stmt, 1);
        const unsigned char *verdict  = sqlite3_column_text(stmt, 2);
        sqlite3_int64 ts              = sqlite3_column_int64(stmt, 3);
        const unsigned char *sev_text = sqlite3_column_text(stmt, 4);
        const unsigned char *rpm_nvr  = sqlite3_column_text(stmt, 5);

        str_safe_copy(r->event_id,
                      event_id ? (const char *)event_id : "",
                      sizeof(r->event_id));
        str_safe_copy(r->package,
                      package ? (const char *)package : "",
                      sizeof(r->package));
        str_safe_copy(r->verdict,
                      verdict ? (const char *)verdict : "",
                      sizeof(r->verdict));
        r->timestamp = (time_t)ts;
        r->severity = history_severity_from_text((const char *)sev_text);
        str_safe_copy(r->rpm_nvr,
                      rpm_nvr ? (const char *)rpm_nvr : "",
                      sizeof(r->rpm_nvr));
        n++;
    }
    sqlite3_finalize(stmt);

    /* NEEDS-V3-OPTIMIZATION (M18-7): the Python shim does NOT emit the
     * view_audit row — that is a TUI-side concern (operator_id + query
     * literal are TUI state, not part of the SQLite contract). The C
     * caller (tui_history view loop) is responsible for the INSERT into
     * view_audit after this function returns. Documented here so future
     * readers don't expect this function to do it. */

    *out = buf;
    *n_out = n;
    return (int)n;
}

/* spagat_history.h line 144:
 *   void spagat_history_free_results(SpagatHistoryRecord *recs, size_t n);
 *
 * Release the result array returned by spagat_history_query(). Safe to
 * call with recs == NULL && n == 0 per the header contract. The records
 * themselves carry only fixed-size char arrays (no nested allocations),
 * so a single free() on the outer block is sufficient.
 *
 * Acceptance: M18-2 (no leak across repeated F2 renders). */
void spagat_history_free_results(SpagatHistoryRecord *recs, size_t n) {
    (void)n; /* n is informational — the malloc'd block is the array. */
    if (recs != NULL) {
        free(recs);
    }
}

/* spagat_history.h line 164:
 *   int spagat_history_compute_ttl(SpagatHistorySeverity sev, bool has_rpm_nvr);
 *
 * Per-record TTL in days. Ladder mirrors the Python shim's
 * TTL_DAYS_BY_SEVERITY map byte-for-byte and is normatively documented in
 * docs/M18-history-view-design.md §3. Signed-release records
 * (has_rpm_nvr == true) get -1 unconditionally (the M18-9 hard floor).
 *
 * Acceptance: M18-8 (TTL purge derives ttl_expires_at from this value),
 *             M18-9 (signed-release hard floor), M18-10 (kev_listed
 *             doubling applies on top of this base, in the caller). */
int spagat_history_compute_ttl(SpagatHistorySeverity sev, bool has_rpm_nvr) {
    /* M18-9 hard floor: signed material is forever-keep regardless of
     * severity. Operator policy cannot widen this — enforced here AND
     * in the SQL of spagat_history_purge_expired below. */
    if (has_rpm_nvr) return -1;

    switch (sev) {
        case SEV_CRITICAL: return -1;  /* forever — DORA Art 13 / NIS2 */
        case SEV_HIGH:     return 730; /* 2 yr — CRA Art 13 minimum */
        case SEV_MEDIUM:   return 365; /* 1 yr — operational reuse */
        case SEV_LOW:      return 180; /* ~6 mo — operational debugging */
        case SEV_INFO:     return 90;  /* 3 mo — non-CVE chatter */
    }
    /* Defensive — an out-of-range enum gets the most-permissive bucket
     * so we never accidentally return -1 (forever-keep) for an unknown
     * severity. Mirrors the shim's ValueError but without aborting. */
    return 90;
}

/* spagat_history.h line 177:
 *   int spagat_history_purge_expired(time_t now);
 *
 * Delete every row whose ttl_expires_at < now AND whose provenance is
 * not 'signed'. The signed-release hard floor (M18-9) is baked into the
 * SQL — operator policy cannot widen it. Mirrors the Python shim's
 * purge_expired() exactly.
 *
 * Acceptance: M18-8 (TTL_REDACT per purge — see NEEDS-V3-OPTIMIZATION
 *             below; the audit emission is a TUI/scheduler concern, not
 *             part of the SQLite contract), M18-9 (signed floor enforced
 *             in SQL), M18-13 (view_audit table is NEVER purged by this
 *             function — the WHERE clause targets only history_records). */
int spagat_history_purge_expired(time_t now) {
    if (g_history_db == NULL) return -1;

    static const char *kPurgeSQL =
        "DELETE FROM history_records "
        "WHERE ttl_expires_at IS NOT NULL "
        "  AND ttl_expires_at < ? "
        "  AND (provenance IS NULL OR provenance != 'signed')";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(g_history_db, kPurgeSQL, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        if (stmt != NULL) sqlite3_finalize(stmt);
        return -1;
    }
    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)now);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return -1;

    int purged = sqlite3_changes(g_history_db);

    /* NEEDS-V3-OPTIMIZATION (M18-8): the TTL_REDACT row(s) in view_audit
     * are emitted by the spec-038 scheduler (the caller of this function)
     * once it knows the operator's last-applied policy hash. Emitting it
     * here would require pulling the policy file into the SQLite contract,
     * which we deliberately keep out per the layering in ADR-0022 D8.
     * Documented here so future readers don't double-count. */

    return purged;
}

/* End of tui_history.c — 6 public functions implemented, all signatures
 * verified verbatim against spagat_history.h (see line-quoted citations
 * above each function). */
