/* git_tags.c — `git tag -l` output parser.
 * Mirrors photonos-package-report.ps1 L 2441-2444 verbatim.
 */
#include "pr_git_tags.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void pr_git_tags_free(char **names, size_t n)
{
    if (!names) return;
    for (size_t i = 0; i < n; i++) free(names[i]);
    free(names);
}

/* trim ASCII whitespace from both ends, return malloc'd copy. */
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

int pr_parse_tag_list(const char *git_output,
                      const char *custom_regex,
                      char     ***out_names,
                      size_t     *out_n)
{
    if (out_names == NULL || out_n == NULL) return -1;
    *out_names = NULL;
    *out_n     = 0;
    if (git_output == NULL) return 0;

    /* Optional regex compile. */
    pcre2_code *re = NULL;
    if (custom_regex != NULL && custom_regex[0] != '\0') {
        int        err_code = 0;
        PCRE2_SIZE err_off  = 0;
        re = pcre2_compile((PCRE2_SPTR)custom_regex, PCRE2_ZERO_TERMINATED,
                            0, &err_code, &err_off, NULL);
        if (re == NULL) {
            PCRE2_UCHAR ebuf[256];
            pcre2_get_error_message(err_code, ebuf, sizeof ebuf);
            fprintf(stderr, "pr_parse_tag_list: compile('%s') failed at %zu: %s\n",
                    custom_regex, (size_t)err_off, (char *)ebuf);
            return -2;
        }
    }
    pcre2_match_data *md = re ? pcre2_match_data_create_from_pattern(re, NULL) : NULL;

    /* Split on \r?\n. Walk the buffer once, emit one trimmed copy per
     * non-blank line (optionally regex-filtered). */
    size_t cap = 64;
    char **arr = (char **)malloc(cap * sizeof *arr);
    if (!arr) { if (md) pcre2_match_data_free(md); if (re) pcre2_code_free(re); return -1; }
    size_t count = 0;

    const char *p = git_output;
    while (*p) {
        const char *line_start = p;
        while (*p && *p != '\n' && *p != '\r') p++;
        size_t llen = (size_t)(p - line_start);
        /* skip the line terminator. */
        if (*p == '\r') p++;
        if (*p == '\n') p++;

        if (llen == 0) continue;

        /* trim + non-blank gate. */
        char *trimmed = trim_dup(line_start, llen);
        if (!trimmed) goto fail;
        if (trimmed[0] == '\0') { free(trimmed); continue; }

        /* regex gate. */
        if (re) {
            int rc = pcre2_match(re, (PCRE2_SPTR)trimmed, PCRE2_ZERO_TERMINATED,
                                  0, 0, md, NULL);
            if (rc < 0) { free(trimmed); continue; }
        }

        if (count == cap) {
            cap *= 2;
            char **np = (char **)realloc(arr, cap * sizeof *arr);
            if (!np) { free(trimmed); goto fail; }
            arr = np;
        }
        arr[count++] = trimmed;
    }

    if (md) pcre2_match_data_free(md);
    if (re) pcre2_code_free(re);
    *out_names = arr;
    *out_n     = count;
    return 0;

fail:
    for (size_t i = 0; i < count; i++) free(arr[i]);
    free(arr);
    if (md) pcre2_match_data_free(md);
    if (re) pcre2_code_free(re);
    return -1;
}
