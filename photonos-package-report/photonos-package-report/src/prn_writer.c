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
#include <unistd.h>
#include <sys/file.h>

/* PS L 5068: header literal, verbatim. */
const char PR_PRN_HEADER[] =
    "Spec,Source0 original,Modified Source0 for url health check,"
    "UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,"
    "UpdateDownloadName,warning,ArchivationDate";

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

    /* Header. */
    fwrite(PR_PRN_HEADER, 1, sizeof(PR_PRN_HEADER) - 1, ctx->f);
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

/* qsort comparator: locale-C strcmp ascending. */
static int cmp_str_asc(const void *a, const void *b)
{
    const char *const *sa = (const char *const *)a;
    const char *const *sb = (const char *const *)b;
    return strcmp(*sa, *sb);
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
