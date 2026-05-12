/* spec_value.c — Get-SpecValue.
 * Mirrors photonos-package-report.ps1 L 234-245.
 *
 * PS source for reference (verbatim):
 *
 *   function Get-SpecValue {
 *       param(
 *           [string[]]$Content,
 *           [string]$Pattern,
 *           [string]$Replace
 *       )
 *       $match = $Content | Select-String -Pattern $Pattern | Select-Object -First 1
 *       if ($match) {
 *           return ($match.ToString() -ireplace $Replace, "").Trim()
 *       }
 *       return $null
 *   }
 *
 * Semantics preserved 1:1:
 *   1. Iterate input lines in order; the FIRST one that matches Pattern
 *      (case-insensitive, regex) is taken — equivalent to
 *      `Select-String -Pattern $Pattern | Select-Object -First 1`.
 *   2. On that line, apply `-ireplace $Replace, ""` — case-insensitive
 *      PCRE2 substitute of ALL non-overlapping matches with empty string.
 *      (PS -ireplace replaces all matches; same as PCRE2_SUBSTITUTE_GLOBAL.)
 *   3. Trim ASCII whitespace from both ends. PS Trim() with no argument
 *      trims Char.IsWhiteSpace(); for the byte content we ever encounter in
 *      .spec files (ASCII), strchr(" \t\r\n\v\f", c) suffices.
 *   4. No match → NULL (PS $null).
 *
 * Returns a heap-allocated NUL-terminated string the caller frees, or NULL.
 */
#include "photonos_package_report.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* Trim ASCII whitespace from both ends. Returns malloc'd string. */
static char *trim_dup(const char *s, size_t len)
{
    size_t a = 0, b = len;
    while (a < b && isspace((unsigned char)s[a])) a++;
    while (b > a && isspace((unsigned char)s[b - 1])) b--;
    char *out = (char *)malloc(b - a + 1);
    if (!out) return NULL;
    memcpy(out, s + a, b - a);
    out[b - a] = '\0';
    return out;
}

char *get_spec_value(char **content, size_t n_lines,
                     const char *pattern, const char *replace)
{
    if (content == NULL || n_lines == 0 || pattern == NULL) return NULL;

    /* -------- Compile the match pattern (case-insensitive). ----------- */
    int        err_code = 0;
    PCRE2_SIZE err_off  = 0;
    pcre2_code *re_match = pcre2_compile(
        (PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED,
        PCRE2_CASELESS, &err_code, &err_off, NULL);
    if (re_match == NULL) {
        PCRE2_UCHAR buf[256];
        pcre2_get_error_message(err_code, buf, sizeof buf);
        fprintf(stderr, "get_spec_value: pcre2_compile(pattern='%s') failed at %zu: %s\n",
                pattern, (size_t)err_off, (char *)buf);
        return NULL;
    }
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re_match, NULL);

    /* -------- Find the first matching line (PS Select-Object -First 1). */
    int matched_idx = -1;
    for (size_t i = 0; i < n_lines; i++) {
        if (content[i] == NULL) continue;
        int rc = pcre2_match(re_match,
                             (PCRE2_SPTR)content[i],
                             PCRE2_ZERO_TERMINATED,
                             0, 0, md, NULL);
        if (rc >= 0) { matched_idx = (int)i; break; }
    }
    pcre2_match_data_free(md);
    pcre2_code_free(re_match);

    if (matched_idx < 0) return NULL;

    /* -------- Apply -ireplace $Replace, "" to the matched line. -------
     * If $Replace is NULL or empty, the PS operator is a no-op; we still
     * trim. */
    const char *line   = content[matched_idx];
    size_t      llen   = strlen(line);

    if (replace == NULL || replace[0] == '\0') {
        return trim_dup(line, llen);
    }

    pcre2_code *re_repl = pcre2_compile(
        (PCRE2_SPTR)replace, PCRE2_ZERO_TERMINATED,
        PCRE2_CASELESS, &err_code, &err_off, NULL);
    if (re_repl == NULL) {
        PCRE2_UCHAR buf[256];
        pcre2_get_error_message(err_code, buf, sizeof buf);
        fprintf(stderr, "get_spec_value: pcre2_compile(replace='%s') failed at %zu: %s\n",
                replace, (size_t)err_off, (char *)buf);
        return trim_dup(line, llen);
    }

    /* Output buffer: replacement is "", so worst case == line length + NUL. */
    PCRE2_SIZE out_len = llen + 1;
    PCRE2_UCHAR *out_buf = (PCRE2_UCHAR *)malloc(out_len);
    if (!out_buf) { pcre2_code_free(re_repl); return NULL; }

    int rc = pcre2_substitute(
        re_repl,
        (PCRE2_SPTR)line, llen,
        0,
        PCRE2_SUBSTITUTE_GLOBAL,
        NULL, NULL,
        (PCRE2_SPTR)"", 0,
        out_buf, &out_len);

    if (rc < 0) {
        /* Buffer too small? Shouldn't happen since replacement is "", but
         * be defensive. */
        if (rc == PCRE2_ERROR_NOMEMORY) {
            free(out_buf);
            out_buf = (PCRE2_UCHAR *)malloc(out_len + 1);
            if (!out_buf) { pcre2_code_free(re_repl); return NULL; }
            rc = pcre2_substitute(
                re_repl,
                (PCRE2_SPTR)line, llen,
                0,
                PCRE2_SUBSTITUTE_GLOBAL,
                NULL, NULL,
                (PCRE2_SPTR)"", 0,
                out_buf, &out_len);
        }
        if (rc < 0) {
            PCRE2_UCHAR ebuf[256];
            pcre2_get_error_message(rc, ebuf, sizeof ebuf);
            fprintf(stderr, "get_spec_value: pcre2_substitute failed: %s\n", (char *)ebuf);
            free(out_buf);
            pcre2_code_free(re_repl);
            return NULL;
        }
    }
    pcre2_code_free(re_repl);

    char *trimmed = trim_dup((const char *)out_buf, out_len);
    free(out_buf);
    return trimmed;
}
