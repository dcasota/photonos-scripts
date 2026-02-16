#include "sysaware.h"
#include "ai.h"
#include "../agent/agent.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SNAP_BUF_SIZE   4096
#define VALUE_BUF_SIZE  512
#define CHANGES_DEFAULT 2048
#define LINE_MAX_LEN    512
#define PATH_MAX_LEN    SPAGAT_PATH_MAX

/* Known fact keys and the prefix they match in sysinfo_snapshot output */
static const struct {
    const char *prefix;   /* line prefix to match (e.g. "OS: ") */
    const char *key;      /* memory key to store under */
} fact_map[] = {
    {"OS: ",       "system.os"},
    {"Host: ",     "system.hostname"},
    {"CPU: ",      "system.cpu"},
    {"RAM: ",      "system.ram"},
    {"User: ",     "system.user"},
    {"Time: ",     "system.time"},
    {"Network: ",  "system.network"},
};
#define FACT_MAP_COUNT (int)(sizeof(fact_map) / sizeof(fact_map[0]))

/* Keys to track for change detection (subset that is meaningful to diff) */
static const char *change_keys[] = {
    "system.os",
    "system.hostname",
    "system.cpu",
    "system.ram",
    "system.user",
    "system.network",
};
#define CHANGE_KEY_COUNT (int)(sizeof(change_keys) / sizeof(change_keys[0]))

/* ------------------------------------------------------------------ */
/* helpers                                                            */
/* ------------------------------------------------------------------ */

/*
 * Parse the snapshot text and call cb(key, value, ctx) for every fact found.
 * Returns the number of facts found.
 */
typedef void (*fact_cb)(const char *key, const char *value, void *ctx);

static int parse_snapshot(const char *snap, fact_cb cb, void *ctx) {
    if (!snap) return 0;

    int count = 0;
    const char *p = snap;

    while (*p) {
        /* extract one line */
        const char *eol = strchr(p, '\n');
        int len = eol ? (int)(eol - p) : (int)strlen(p);
        if (len <= 0) { p = eol ? eol + 1 : p + len; continue; }

        char line[LINE_MAX_LEN];
        int cpy = len < (int)sizeof(line) - 1 ? len : (int)sizeof(line) - 1;
        memcpy(line, p, cpy);
        line[cpy] = '\0';

        /* Check for disk/storage lines: "  /path ..." */
        if (line[0] == ' ' && line[1] == ' ' && line[2] == '/') {
            /* e.g. "  /     48.0 GiB total, 12.3 GiB used ..." */
            char *s = line + 2;  /* skip leading spaces */
            /* extract mount point */
            char mount[64];
            int mi = 0;
            while (*s && *s != ' ' && mi < (int)sizeof(mount) - 1)
                mount[mi++] = *s++;
            mount[mi] = '\0';
            while (*s == ' ') s++;

            /* build key: system.disk./ or system.disk./home */
            char key[128];
            snprintf(key, sizeof(key), "system.disk.%s", mount);

            if (cb) cb(key, s, ctx);
            count++;
        } else {
            /* Check against known prefix map */
            for (int i = 0; i < FACT_MAP_COUNT; i++) {
                size_t plen = strlen(fact_map[i].prefix);
                if (strncmp(line, fact_map[i].prefix, plen) == 0) {
                    const char *val = line + plen;
                    if (cb) cb(fact_map[i].key, val, ctx);
                    count++;
                    break;
                }
            }
        }

        p = eol ? eol + 1 : p + len;
    }
    return count;
}

/* callback context for store_facts */
typedef struct {
    int stored;
} store_ctx;

static void store_cb(const char *key, const char *value, void *ctx) {
    store_ctx *sc = (store_ctx *)ctx;
    if (ai_memory_set(0, "system", key, value))
        sc->stored++;
}

/* ------------------------------------------------------------------ */
/* public API                                                         */
/* ------------------------------------------------------------------ */

int sysaware_store_facts(void) {
    char snap[SNAP_BUF_SIZE];
    int n = sysinfo_snapshot(snap, sizeof(snap));
    if (n <= 0) return 0;

    store_ctx sc = {0};
    parse_snapshot(snap, store_cb, &sc);
    return sc.stored;
}

/* ------------------------------------------------------------------ */

int sysaware_detect_changes(char *changes, int changes_size) {
    if (!changes || changes_size < 1) return 0;
    changes[0] = '\0';

    char snap[SNAP_BUF_SIZE];
    int n = sysinfo_snapshot(snap, sizeof(snap));
    if (n <= 0) return 0;

    /*
     * Build a small lookup table of current values by parsing the snapshot.
     * We only track the keys listed in change_keys[].
     */
    char current_values[CHANGE_KEY_COUNT][VALUE_BUF_SIZE];
    memset(current_values, 0, sizeof(current_values));

    /* Walk the snapshot once and fill current_values */
    const char *p = snap;
    while (*p) {
        const char *eol = strchr(p, '\n');
        int len = eol ? (int)(eol - p) : (int)strlen(p);
        if (len <= 0) { p = eol ? eol + 1 : p + len; continue; }

        char line[LINE_MAX_LEN];
        int cpy = len < (int)sizeof(line) - 1 ? len : (int)sizeof(line) - 1;
        memcpy(line, p, cpy);
        line[cpy] = '\0';

        for (int i = 0; i < FACT_MAP_COUNT; i++) {
            size_t plen = strlen(fact_map[i].prefix);
            if (strncmp(line, fact_map[i].prefix, plen) != 0) continue;
            /* find which change_key matches */
            for (int k = 0; k < CHANGE_KEY_COUNT; k++) {
                if (strcmp(fact_map[i].key, change_keys[k]) == 0) {
                    str_safe_copy(current_values[k], line + plen,
                                  VALUE_BUF_SIZE);
                    break;
                }
            }
            break;
        }
        p = eol ? eol + 1 : p + len;
    }

    /* Compare against stored values */
    int num_changes = 0;
    int pos = 0;

    for (int k = 0; k < CHANGE_KEY_COUNT; k++) {
        if (current_values[k][0] == '\0') continue;

        char stored[VALUE_BUF_SIZE];
        bool had_stored = ai_memory_get(0, "system", change_keys[k],
                                        stored, sizeof(stored));
        if (!had_stored || stored[0] == '\0') {
            /* First run – report as new */
            int w = snprintf(changes + pos, changes_size - pos,
                             "NEW: %s = %s\n", change_keys[k],
                             current_values[k]);
            if (w > 0) pos += w;
            num_changes++;
        } else if (strcmp(stored, current_values[k]) != 0) {
            int w = snprintf(changes + pos, changes_size - pos,
                             "CHANGED: %s: %s -> %s\n",
                             change_keys[k], stored, current_values[k]);
            if (w > 0) pos += w;
            num_changes++;
        }
    }

    return num_changes;
}

/* ------------------------------------------------------------------ */

bool sysaware_refresh_system_md(const char *workspace_dir) {
    if (!workspace_dir) return false;

    char path[PATH_MAX_LEN];
    snprintf(path, sizeof(path), "%s/SYSTEM.md", workspace_dir);

    /* Read existing file to preserve sections */
    char observations[4096] = "";
    char change_history[4096] = "";

    FILE *existing = fopen(path, "r");
    if (existing) {
        char fbuf[8192];
        size_t rd = fread(fbuf, 1, sizeof(fbuf) - 1, existing);
        fbuf[rd] = '\0';
        fclose(existing);

        /* Preserve ## Observations section */
        const char *obs = strstr(fbuf, "## Observations");
        if (obs) {
            str_safe_copy(observations, obs, sizeof(observations));
        }

        /* Preserve ## Change History content */
        const char *ch_start = strstr(fbuf, "## Change History\n");
        if (ch_start) {
            ch_start += strlen("## Change History\n");
            const char *ch_end = strstr(ch_start, "\n## ");
            size_t ch_len;
            if (ch_end)
                ch_len = (size_t)(ch_end - ch_start);
            else
                ch_len = strlen(ch_start);
            if (ch_len >= sizeof(change_history))
                ch_len = sizeof(change_history) - 1;
            memcpy(change_history, ch_start, ch_len);
            change_history[ch_len] = '\0';
        }
    }

    /* Get current snapshot */
    char snap[SNAP_BUF_SIZE];
    int n = sysinfo_snapshot(snap, sizeof(snap));
    if (n <= 0) return false;

    /* Get timestamp */
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    char ts[64];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm);

    /* Detect changes for the change history section */
    char changes[CHANGES_DEFAULT];
    int num_changes = sysaware_detect_changes(changes, sizeof(changes));

    /* Write the new SYSTEM.md */
    FILE *f = fopen(path, "w");
    if (!f) return false;

    fprintf(f, "# System Environment\n\n");
    fprintf(f, "*Auto-generated by SPAGAT-Librarian on %s*\n\n", ts);

    /* Current Snapshot */
    fprintf(f, "## Current Snapshot\n\n");
    fprintf(f, "```\n%s\n```\n\n", snap);

    /* Stored Facts */
    fprintf(f, "## Stored Facts\n\n");
    /* Enumerate known keys from memory */
    for (int i = 0; i < FACT_MAP_COUNT; i++) {
        char val[VALUE_BUF_SIZE];
        if (ai_memory_get(0, "system", fact_map[i].key, val, sizeof(val))
            && val[0] != '\0') {
            fprintf(f, "- **%s** = %s\n", fact_map[i].key, val);
        }
    }
    /* Also check disk keys */
    const char *disk_mounts[] = {"/", "/home", NULL};
    for (int i = 0; disk_mounts[i]; i++) {
        char key[128], val[VALUE_BUF_SIZE];
        snprintf(key, sizeof(key), "system.disk.%s", disk_mounts[i]);
        if (ai_memory_get(0, "system", key, val, sizeof(val))
            && val[0] != '\0') {
            fprintf(f, "- **%s** = %s\n", key, val);
        }
    }
    fprintf(f, "\n");

    /* Change History */
    fprintf(f, "## Change History\n\n");
    /* Existing history first */
    if (change_history[0] != '\0') {
        fprintf(f, "%s", change_history);
    }
    /* Append new changes with timestamp */
    if (num_changes > 0) {
        fprintf(f, "### %s\n\n", ts);
        fprintf(f, "%s\n", changes);
    }

    /* Observations (preserved from previous file) */
    if (observations[0] != '\0') {
        fprintf(f, "%s", observations);
    } else {
        fprintf(f, "## Observations\n\n");
        fprintf(f, "*No observations recorded yet.*\n");
    }

    fclose(f);
    return true;
}

/* ------------------------------------------------------------------ */

int sysaware_update(const char *workspace_dir) {
    int facts = sysaware_store_facts();

    char changes[CHANGES_DEFAULT];
    int num_changes = sysaware_detect_changes(changes, sizeof(changes));

    if (num_changes > 0) {
        journal_log(JOURNAL_INFO, "sysaware: %d changes detected",
                    num_changes);
    }

    sysaware_refresh_system_md(workspace_dir);

    return facts;
}
