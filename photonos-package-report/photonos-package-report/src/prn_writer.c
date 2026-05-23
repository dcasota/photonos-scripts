/* prn_writer.c — .prn report writer.
 *
 * Mirrors photonos-package-report.ps1 L 5048-5078 (the per-branch
 * outer loop in GenerateUrlHealthReports). The header line, the row
 * regex filter, the ascending sort, and the append semantics all
 * match PS byte-for-byte.
 *
 * Concurrency: pr_prn_append_rows() takes flock(LOCK_EX) for the
 * duration of the write so parallel Phase 7 workers cannot interleave.
 */
#include "pr_prn.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/file.h>

/* M52 / ADR-0016: ICU collation so the row sort matches PowerShell's
 * Sort-Object byte-for-byte (see cmp_str_asc below). */
#include <unicode/ucol.h>
#include <unicode/utypes.h>

/* PS L 5068: header literal, verbatim. ADR-0014 (Accepted Option B):
 * when PR_EMIT_MULTI_SHA env var is set, append `,SHA256Name,SHA512Name`
 * for cols 13/14. The default 12-col header keeps the cached PS snapshot
 * comparison stable until the snapshot is refreshed with the matching
 * PS-side change. */
const char PR_PRN_HEADER[] =
    "Spec,Source0 original,Modified Source0 for url health check,"
    "UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,"
    "UpdateDownloadName,warning,ArchivationDate";

static const char PR_PRN_HEADER_MULTI[] =
    "Spec,Source0 original,Modified Source0 for url health check,"
    "UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,"
    "UpdateDownloadName,warning,ArchivationDate,SHA256Name,SHA512Name";

struct pr_prn {
    FILE       *f;
    int         fd;
    pcre2_code *re_filter;
};

pr_prn_t *pr_prn_open(const char *path)
{
    if (path == NULL) return NULL;
    pr_prn_t *ctx = (pr_prn_t *)calloc(1, sizeof *ctx);
    if (!ctx) return NULL;

    ctx->f = fopen(path, "w");
    if (!ctx->f) { free(ctx); return NULL; }
    ctx->fd = fileno(ctx->f);

    /* Compile the row filter once. Pattern from PS L 5070:
     *   ^(.*?)([a-zA-Z0-9][a-zA-Z0-9._-]*\.spec.*)$
     * We want capture group 2. */
    int       err_code = 0;
    PCRE2_SIZE err_off = 0;
    ctx->re_filter = pcre2_compile(
        (PCRE2_SPTR)"^(.*?)([a-zA-Z0-9][a-zA-Z0-9._-]*\\.spec.*)$",
        PCRE2_ZERO_TERMINATED, 0, &err_code, &err_off, NULL);
    if (!ctx->re_filter) {
        fclose(ctx->f);
        free(ctx);
        return NULL;
    }

    /* Header — ADR-0014: 14-col header when PR_EMIT_MULTI_SHA is set. */
    if (getenv("PR_EMIT_MULTI_SHA") != NULL) {
        fwrite(PR_PRN_HEADER_MULTI, 1, sizeof(PR_PRN_HEADER_MULTI) - 1, ctx->f);
    } else {
        fwrite(PR_PRN_HEADER, 1, sizeof(PR_PRN_HEADER) - 1, ctx->f);
    }
    fputc('\n', ctx->f);
    return ctx;
}

const char *pr_prn_strip(const char *row)
{
    /* Static compile of the same pattern; used by callers (and tests)
     * that don't have a pr_prn_t in hand. */
    static pcre2_code *re = NULL;
    if (re == NULL) {
        int       err_code = 0;
        PCRE2_SIZE err_off = 0;
        re = pcre2_compile(
            (PCRE2_SPTR)"^(.*?)([a-zA-Z0-9][a-zA-Z0-9._-]*\\.spec.*)$",
            PCRE2_ZERO_TERMINATED, 0, &err_code, &err_off, NULL);
        if (!re) return NULL;
    }
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    int rc = pcre2_match(re, (PCRE2_SPTR)row, PCRE2_ZERO_TERMINATED, 0, 0, md, NULL);
    const char *out = NULL;
    if (rc >= 0) {
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        /* Group 2 starts at ov[4]. */
        out = row + ov[4];
    }
    pcre2_match_data_free(md);
    return out;
}

/* qsort comparator: culture-aware ascending, matching PowerShell.
 *
 * PS L 5476 sorts the result with `Sort-Object Spec, SubRelease -Unique`.
 * `Sort-Object` uses .NET CompareInfo (CurrentCulture, case-insensitive),
 * which on Linux delegates to ICU. Our rows begin with the Spec basename
 * followed by ',' (Spec is col 1), so collating the full row string with
 * the same ICU collator gives PS's exact ordering.
 *
 * History:
 *   Pre-M14 used strcmp (case-sensitive ASCII) — capitals sorted before
 *   lowercase, so `GConf.spec` preceded `abseil-cpp.spec` while PS put
 *   them case-insensitively. That mis-positioned almost every row.
 *   M14 switched to strcasecmp, fixing the case axis. But strcasecmp is
 *   still *ordinal*: it compares punctuation by byte value (`-`=0x2D,
 *   `.`=0x2E, `_`=0x5F), whereas ICU treats `-`/`.` as ignorable
 *   punctuation and weights `_` differently. That mis-ordered the
 *   punctuation families — e.g. PS put `rubygem-http_parser.rb` *before*
 *   `rubygem-http-accept`, C (strcasecmp) put it after; likewise
 *   `python-setuptools_scm` vs `-rust`, `python-backports_abc` vs
 *   `.ssl_match_hostname`, `rubygem-unf_ext` vs `unf`. Each mis-ordered
 *   row shifted relative to PS, so parity-diff.sh (row-index compare)
 *   reported phantom diffs on neighbouring rows.
 *   M52 (ADR-0016): collate via ICU `en-US`, strength SECONDARY
 *   (case-insensitive). Validated to reproduce PS's row order with zero
 *   mismatches across all branches (3.0/4.0/5.0/6.0/common).
 *
 * The collator is opened once (pthread_once); ICU collators are safe for
 * concurrent compare-only use across threads. If ICU init ever fails we
 * fall back to strcasecmp so the report still sorts (degraded ordering
 * rather than a crash). */
static UCollator    *g_collator = NULL;
static pthread_once_t g_collator_once = PTHREAD_ONCE_INIT;

static void init_collator(void)
{
    UErrorCode status = U_ZERO_ERROR;
    UCollator *c = ucol_open("en-US", &status);
    if (U_FAILURE(status) || c == NULL) {
        if (c) ucol_close(c);
        g_collator = NULL;   /* signals strcasecmp fallback */
        return;
    }
    /* SECONDARY = case-insensitive (case is a tertiary difference),
     * matching Sort-Object's default case-insensitivity. */
    ucol_setStrength(c, UCOL_SECONDARY);
    g_collator = c;
}

static int cmp_str_asc(const void *a, const void *b)
{
    const char *sa = *(const char *const *)a;
    const char *sb = *(const char *const *)b;
    pthread_once(&g_collator_once, init_collator);
    if (g_collator == NULL) return strcasecmp(sa, sb);
    UErrorCode status = U_ZERO_ERROR;
    UCollationResult r = ucol_strcollUTF8(g_collator, sa, -1, sb, -1, &status);
    if (U_FAILURE(status)) return strcasecmp(sa, sb);
    return (r == UCOL_LESS) ? -1 : (r == UCOL_GREATER) ? 1 : 0;
}

int pr_prn_append_rows(pr_prn_t *ctx, char **rows, size_t n_rows)
{
    if (ctx == NULL) return -1;
    if (rows == NULL || n_rows == 0) return 0;

    /* Filter. */
    char **kept = (char **)malloc(n_rows * sizeof *kept);
    if (!kept) return -1;
    size_t k = 0;
    for (size_t i = 0; i < n_rows; i++) {
        if (rows[i] == NULL) continue;
        const char *s = pr_prn_strip(rows[i]);
        if (s == NULL) continue;
        kept[k++] = (char *)s;
    }
    if (k == 0) { free(kept); return 0; }

    /* Sort ascending. */
    qsort(kept, k, sizeof *kept, cmp_str_asc);

    /* Locked append. */
    if (flock(ctx->fd, LOCK_EX) != 0) { free(kept); return -1; }
    for (size_t i = 0; i < k; i++) {
        fputs(kept[i], ctx->f);
        fputc('\n', ctx->f);
    }
    fflush(ctx->f);
    flock(ctx->fd, LOCK_UN);
    free(kept);
    return 0;
}

int pr_prn_close(pr_prn_t *ctx)
{
    if (ctx == NULL) return 0;
    int rc = 0;
    if (ctx->f) {
        if (fflush(ctx->f) != 0) rc = -1;
        if (fclose(ctx->f) != 0) rc = -1;
    }
    if (ctx->re_filter) pcre2_code_free(ctx->re_filter);
    free(ctx);
    return rc;
}
