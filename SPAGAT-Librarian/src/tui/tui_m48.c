/*
 * tui_m48.c — M48-KanbanCVECard pure helpers.
 *
 * See include/spagat_m48.h for the public contract. This TU carries
 * no ncurses, no SQLite, no TUIState references; it is safe to link
 * into the unit-test binaries directly.
 */

#include "spagat_m48.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

/* strtok_r requires _POSIX_C_SOURCE >= 1 (glibc gates it behind
 * feature-test macros). The appliance top-level CMake already sets
 * _POSIX_C_SOURCE=200809L; we redundantly guard the fallback here so
 * a bare `gcc -std=c11 -Iinclude -Isrc` still builds cleanly. */
#if !defined(_POSIX_C_SOURCE)
#  define _POSIX_C_SOURCE 200809L
#endif
extern char *strtok_r(char *str, const char *delim, char **saveptr);

/* Case-insensitive strcmp — the canonical branch strings are
 * ("5.0/SPECS/91"), but operator-entered ones from the Edit dialog
 * may drift. */
static int str_ieq(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++;
        b++;
    }
    return *a == *b;
}

SpagatM48BranchColor m48_branch_color(const char *branch) {
    if (!branch || !branch[0]) return M48_BRANCH_COLOR_OTHER;

    /* Exact canonical strings first — canonical branch labels
     * (4.0 / 5.0 / 5.0/SPECS/90 / 5.0/SPECS/91 / 6.0). */
    if (str_ieq(branch, "4.0")) return M48_BRANCH_COLOR_40;
    if (str_ieq(branch, "5.0")) return M48_BRANCH_COLOR_50;
    if (str_ieq(branch, "6.0")) return M48_BRANCH_COLOR_60;
    if (str_ieq(branch, "5.0/SPECS/90")) return M48_BRANCH_COLOR_SPECS_90;
    if (str_ieq(branch, "5.0/SPECS/91")) return M48_BRANCH_COLOR_SPECS_91;

    /* Unknown branch → OTHER (rendered white). Don't try to be clever
     * about substring matching — an unknown "5.0-rc" shouldn't silently
     * masquerade as the 5.0 release branch and mislead the operator. */
    return M48_BRANCH_COLOR_OTHER;
}

bool m48_validate_cve_id(const char *id) {
    if (!id) return false;

    /* Prefix must be exactly "CVE-" (uppercase). */
    if (strncmp(id, "CVE-", 4) != 0) return false;
    const char *p = id + 4;

    /* Year: exactly 4 digits. */
    for (int i = 0; i < 4; i++) {
        if (!isdigit((unsigned char)p[i])) return false;
    }
    p += 4;
    if (*p != '-') return false;
    p++;

    /* Sequence: 4+ digits, no upper bound (some CVEs run to 7+). */
    int seq_len = 0;
    while (*p) {
        if (!isdigit((unsigned char)*p)) return false;
        seq_len++;
        p++;
    }
    return seq_len >= 4;
}

bool m48_validate_commit_sha(const char *sha) {
    if (!sha) return false;
    if (sha[0] == '\0') return true;  /* Empty = unset, valid. */

    int len = 0;
    while (sha[len]) {
        char c = sha[len];
        bool ok = (c >= '0' && c <= '9') ||
                  (c >= 'a' && c <= 'f') ||
                  (c >= 'A' && c <= 'F');
        if (!ok) return false;
        len++;
        if (len > 40) return false;
    }
    return len == 40;
}

/* Trim leading/trailing whitespace, mutating `s` in place. Returns
 * the (possibly-advanced) start pointer. */
static char *inplace_trim(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    if (!*s) return s;
    char *end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) *end-- = '\0';
    return s;
}

bool m48_parse_cve_ids(const char *raw, SpagatCveList *out) {
    if (!out) return false;
    memset(out, 0, sizeof(*out));
    if (!raw || !raw[0]) return false;

    /* Work on a mutable local copy so we can strtok/trim. Bound is
     * SPAGAT_MAX_CVE_LIST_LEN + a little slack for safety. */
    char buf[SPAGAT_MAX_CVE_LIST_LEN + 8];
    size_t rlen = strlen(raw);
    if (rlen >= sizeof(buf)) rlen = sizeof(buf) - 1;
    memcpy(buf, raw, rlen);
    buf[rlen] = '\0';

    int valid = 0;
    char *saveptr = NULL;
    char *tok = strtok_r(buf, ",", &saveptr);
    while (tok) {
        char *trimmed = inplace_trim(tok);
        if (trimmed[0]) {
            out->total_parsed++;
            if (m48_validate_cve_id(trimmed)) {
                if (out->count < SPAGAT_M48_MAX_CVE_ENTRIES) {
                    /* Copy the trimmed token into the slot. */
                    size_t tlen = strlen(trimmed);
                    if (tlen >= sizeof(out->entries[0].id)) {
                        tlen = sizeof(out->entries[0].id) - 1;
                    }
                    memcpy(out->entries[out->count].id, trimmed, tlen);
                    out->entries[out->count].id[tlen] = '\0';
                    out->count++;
                }
                valid++;
            } else {
                out->had_invalid = true;
            }
        }
        tok = strtok_r(NULL, ",", &saveptr);
    }
    return valid > 0;
}

bool m48_should_render_two_lines(const Item *item) {
    if (!item) return false;
    if (item->cve_ids[0] != '\0') return true;
    if (item->upstream_commit[0] != '\0') return true;
    if (item->backport_commit[0] != '\0') return true;
    return false;
}

int m48_format_card_line1(const Item *item, char sel_marker,
                          char *out, size_t out_size) {
    if (!item || !out || out_size == 0) return 0;
    /* Compose in a scratch buffer wide enough for the largest legal
     * combination; then copy-and-truncate into `out`. */
    char scratch[SPAGAT_MAX_TITLE_LEN + SPAGAT_MAX_BRANCH_LEN + 32];
    int n;
    if (item->git_branch[0]) {
        n = snprintf(scratch, sizeof(scratch), "%c %lld [%s] %s",
                     sel_marker, (long long)item->id,
                     item->git_branch, item->title);
    } else {
        n = snprintf(scratch, sizeof(scratch), "%c %lld %s",
                     sel_marker, (long long)item->id, item->title);
    }
    if (n < 0) { out[0] = '\0'; return 0; }
    /* Copy into caller's buffer with hard truncation. */
    size_t cap = out_size - 1;
    size_t copy = ((size_t)n < cap) ? (size_t)n : cap;
    memcpy(out, scratch, copy);
    out[copy] = '\0';
    return n;
}

int m48_format_card_line2(const Item *item, char *out, size_t out_size) {
    if (!item || !out || out_size == 0) return 0;
    out[0] = '\0';
    if (!m48_should_render_two_lines(item)) return 0;

    /* Parse the CVE list to pick the first + overflow count. */
    SpagatCveList cves;
    m48_parse_cve_ids(item->cve_ids, &cves);

    /* Short-commit rendering: first 4 hex + ".." for the upstream SHA.
     * Renders even when zero CVEs are present, matching the operator
     * preview. Falls back to no parenthetical when upstream_commit is
     * empty. */
    char short_commit[8] = {0};
    if (item->upstream_commit[0]) {
        int copy = 0;
        while (copy < 4 && item->upstream_commit[copy]) {
            short_commit[copy] = item->upstream_commit[copy];
            copy++;
        }
        short_commit[copy] = '\0';
    }

    char scratch[128];
    int pos = 0;
    /* Leading indent — 4 spaces so the CVE line sits under the title. */
    pos += snprintf(scratch + pos, sizeof(scratch) - pos, "    ");

    if (cves.count > 0) {
        pos += snprintf(scratch + pos, sizeof(scratch) - pos, "%s",
                        cves.entries[0].id);
        int extras = cves.total_parsed - 1;
        if (extras >= 1) {
            pos += snprintf(scratch + pos, sizeof(scratch) - pos, " +%d",
                            extras);
        }
        if (short_commit[0]) {
            pos += snprintf(scratch + pos, sizeof(scratch) - pos, " (%s..)",
                            short_commit);
        }
    } else if (short_commit[0]) {
        /* No CVE, upstream commit only — still worth surfacing. */
        pos += snprintf(scratch + pos, sizeof(scratch) - pos, "(%s..)",
                        short_commit);
    }

    if (pos < 0) { out[0] = '\0'; return 0; }
    size_t cap = out_size - 1;
    size_t copy = ((size_t)pos < cap) ? (size_t)pos : cap;
    memcpy(out, scratch, copy);
    out[copy] = '\0';
    return pos;
}
