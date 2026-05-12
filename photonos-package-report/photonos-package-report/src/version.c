/* version.c — Parse-Version + Compare-VersionStrings port.
 *
 * Mirrors photonos-package-report.ps1 L 1736-1905 line-for-line.
 *
 * PS-source mapping:
 *   PS L 1744-1800 → pr_version_parse
 *   PS L 1804-1885 → pr_version_compare (8 rules, in PS order)
 *   PS L 1888-1903 → not strictly needed: pr_version_parse already
 *                     gives callers the typed view Convert-ToVersion
 *                     returned in PS.
 *
 * Regex patterns are compiled once via pthread_once.
 */
#include "pr_version.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <ctype.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* --- one-time PCRE2 pattern compile -------------------------------- */
static pcre2_code *RE_DATE_VERSION;   /* ^\d{8}-\d+\.\d+ */
static pcre2_code *RE_VERSION_DATE;   /* ^\d+\.\d+\.\d{8} */
static pcre2_code *RE_QUARTERLY;      /* ^(\d{4})\.Q(\d+)\.(\d+)$ */
static pcre2_code *RE_STANDARD;       /* ^\d+(\.\d+)+$ */
static pcre2_code *RE_LETTER_EMBED;   /* ^\d+(\.\d+)*\.\d+[a-zA-Z]\d+$ */
static pcre2_code *RE_INT;            /* ^\d+$ */

static pthread_once_t g_re_once = PTHREAD_ONCE_INIT;

static pcre2_code *compile_or_die(const char *pat)
{
    int        err_code = 0;
    PCRE2_SIZE err_off  = 0;
    pcre2_code *re = pcre2_compile(
        (PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED, 0, &err_code, &err_off, NULL);
    if (!re) {
        PCRE2_UCHAR ebuf[256];
        pcre2_get_error_message(err_code, ebuf, sizeof ebuf);
        fprintf(stderr, "version.c: compile('%s') failed at %zu: %s\n",
                pat, (size_t)err_off, (char *)ebuf);
        abort();
    }
    return re;
}

static void init_patterns(void)
{
    RE_DATE_VERSION = compile_or_die("^\\d{8}-\\d+\\.\\d+");
    RE_VERSION_DATE = compile_or_die("^\\d+\\.\\d+\\.\\d{8}");
    RE_QUARTERLY    = compile_or_die("^(\\d{4})\\.Q(\\d+)\\.(\\d+)$");
    RE_STANDARD     = compile_or_die("^\\d+(\\.\\d+)+$");
    RE_LETTER_EMBED = compile_or_die("^\\d+(\\.\\d+)*\\.\\d+[a-zA-Z]\\d+$");
    RE_INT          = compile_or_die("^\\d+$");
}

/* Helper: PCRE2 match-only convenience. Returns 1 on match. */
static int re_match(pcre2_code *re, const char *s)
{
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    int rc = pcre2_match(re, (PCRE2_SPTR)s, PCRE2_ZERO_TERMINATED, 0, 0, md, NULL);
    pcre2_match_data_free(md);
    return rc >= 0;
}

/* Helper: extract captures from a successful match into out_caps[]. */
static int re_match_groups(pcre2_code *re, const char *s,
                           char **out_caps, int max_caps)
{
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    int rc = pcre2_match(re, (PCRE2_SPTR)s, PCRE2_ZERO_TERMINATED, 0, 0, md, NULL);
    int n = 0;
    if (rc > 0) {
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        n = rc - 1;  /* exclude group 0 = whole match */
        if (n > max_caps) n = max_caps;
        for (int i = 0; i < n; i++) {
            PCRE2_SIZE start = ov[2 * (i + 1)];
            PCRE2_SIZE end   = ov[2 * (i + 1) + 1];
            size_t len = end - start;
            out_caps[i] = (char *)malloc(len + 1);
            memcpy(out_caps[i], s + start, len);
            out_caps[i][len] = '\0';
        }
    }
    pcre2_match_data_free(md);
    return n;
}

/* --- helpers ------------------------------------------------------- */

static char *xstrdup_or_null(const char *s)
{
    if (s == NULL) return NULL;
    size_t n = strlen(s);
    char *p = (char *)malloc(n + 1);
    if (p) memcpy(p, s, n + 1);
    return p;
}

/* In-place replace every occurrence of `a` with `b`. Returns new heap
 * pointer; frees `in`. For the PS `-replace '-', '.'` step. */
static char *replace_char(char *in, char a, char b)
{
    if (in == NULL) return NULL;
    for (char *p = in; *p; p++) {
        if (*p == a) *p = b;
    }
    return in;
}

/* Split `s` on `delim` byte. Returns NULL-terminated heap array; each
 * element is a heap copy. `*out_n` set. */
static char **split_char(const char *s, char delim, size_t *out_n)
{
    *out_n = 0;
    size_t cap = 8;
    char **toks = (char **)malloc((cap + 1) * sizeof *toks);
    if (!toks) return NULL;
    const char *cur = s;
    while (1) {
        const char *hit = strchr(cur, delim);
        size_t len = hit ? (size_t)(hit - cur) : strlen(cur);
        if (*out_n == cap) {
            cap *= 2;
            char **np = (char **)realloc(toks, (cap + 1) * sizeof *toks);
            if (!np) break;
            toks = np;
        }
        char *piece = (char *)malloc(len + 1);
        memcpy(piece, cur, len);
        piece[len] = '\0';
        toks[(*out_n)++] = piece;
        if (!hit) break;
        cur = hit + 1;
    }
    toks[*out_n] = NULL;
    return toks;
}

static void free_tokens(char **toks)
{
    if (!toks) return;
    for (size_t i = 0; toks[i]; i++) free(toks[i]);
    free(toks);
}

static int64_t parse_int64(const char *s)
{
    return (int64_t)strtoll(s, NULL, 10);
}

/* PS .TrimStart('0'): drop leading '0' bytes; empty result -> "0". */
static char *trim_leading_zeros_dup(const char *s)
{
    while (*s == '0') s++;
    if (*s == '\0') return xstrdup_or_null("0");
    return xstrdup_or_null(s);
}

/* PS double.TryParse: returns 1 on success and writes *out. */
static int try_parse_double(const char *s, double *out)
{
    char *end = NULL;
    double v = strtod(s, &end);
    if (end == s || *end != '\0') return 0;
    *out = v;
    return 1;
}

/* Split `part` on runs of ASCII letters, push the all-digit pieces into
 * `components`. Used for Case 3b (1.9.15p5 → 1 9 15 5). */
static int split_letter_embed_push(const char *part, int **components,
                                   size_t *n, size_t *cap)
{
    const char *p = part;
    while (*p) {
        while (*p && isalpha((unsigned char)*p)) p++;
        if (!*p) break;
        const char *start = p;
        while (*p && !isalpha((unsigned char)*p)) p++;
        size_t len = (size_t)(p - start);
        if (len == 0) continue;
        char buf[32]; if (len >= sizeof buf) len = sizeof buf - 1;
        memcpy(buf, start, len);
        buf[len] = '\0';
        if (*n == *cap) {
            *cap = *cap == 0 ? 8 : *cap * 2;
            int *np = (int *)realloc(*components, *cap * sizeof **components);
            if (!np) return -1;
            *components = np;
        }
        (*components)[(*n)++] = (int)strtol(buf, NULL, 10);
    }
    return 0;
}

/* Push all components from a plain `n.n.n...` string into components. */
static int push_dot_ints(const char *s, int **components, size_t *n, size_t *cap)
{
    size_t nt;
    char **toks = split_char(s, '.', &nt);
    if (!toks) return -1;
    for (size_t i = 0; i < nt; i++) {
        if (*n == *cap) {
            *cap = *cap == 0 ? 8 : *cap * 2;
            int *np = (int *)realloc(*components, *cap * sizeof **components);
            if (!np) { free_tokens(toks); return -1; }
            *components = np;
        }
        (*components)[(*n)++] = (int)strtol(toks[i], NULL, 10);
    }
    free_tokens(toks);
    return 0;
}

/* ----- pr_version_parse -------------------------------------------- */

int pr_version_parse(const char *s, pr_version_t *out)
{
    if (s == NULL || out == NULL) return -1;
    pthread_once(&g_re_once, init_patterns);

    memset(out, 0, sizeof *out);
    out->str_value = xstrdup_or_null(s);  /* always keep raw */

    /* PS L 1746: $normalizedVersion = $InputVersion -replace '-','.' */
    char *norm = xstrdup_or_null(s);
    norm = replace_char(norm, '-', '.');

    /* Case 1: DateVersion — ^\d{8}-\d+\.\d+ matches the RAW input. */
    if (re_match(RE_DATE_VERSION, s)) {
        size_t nt;
        char **parts = split_char(norm, '.', &nt);
        if (parts && nt >= 3) {
            out->type           = PR_VER_DATE_VERSION;
            out->date           = parse_int64(parts[0]);
            size_t v_len = strlen(parts[1]) + 1 + strlen(parts[2]) + 1;
            out->version_number = (char *)malloc(v_len);
            snprintf(out->version_number, v_len, "%s.%s", parts[1], parts[2]);
        }
        free_tokens(parts);
        free(norm);
        return 0;
    }
    /* Case 2: VersionDate — ^\d+\.\d+\.\d{8} on RAW input. */
    if (re_match(RE_VERSION_DATE, s)) {
        size_t nt;
        char **parts = split_char(norm, '.', &nt);
        if (parts && nt >= 3) {
            out->type           = PR_VER_VERSION_DATE;
            out->date           = parse_int64(parts[2]);
            size_t v_len = strlen(parts[0]) + 1 + strlen(parts[1]) + 1;
            out->version_number = (char *)malloc(v_len);
            snprintf(out->version_number, v_len, "%s.%s", parts[0], parts[1]);
        }
        free_tokens(parts);
        free(norm);
        return 0;
    }
    /* Case 2b: Quarterly YYYY.Q#.# */
    {
        char *caps[3] = {0};
        int ngot = re_match_groups(RE_QUARTERLY, s, caps, 3);
        if (ngot == 3) {
            out->type         = PR_VER_STANDARD;
            out->n_components = 3;
            out->components   = (int *)calloc(3, sizeof *out->components);
            out->components[0] = (int)strtol(caps[0], NULL, 10);  /* year */
            out->components[1] = (int)strtol(caps[1], NULL, 10);  /* quarter */
            out->components[2] = (int)strtol(caps[2], NULL, 10);  /* patch */
            free(caps[0]); free(caps[1]); free(caps[2]);
            free(norm);
            return 0;
        }
        free(caps[0]); free(caps[1]); free(caps[2]);
    }
    /* Case 3: Standard X.Y(.Z...) — on NORMALIZED input. */
    if (re_match(RE_STANDARD, norm)) {
        out->type = PR_VER_STANDARD;
        size_t cap = 0;
        if (push_dot_ints(norm, &out->components, &out->n_components, &cap) != 0) {
            free(norm); return -1;
        }
        free(norm);
        return 0;
    }
    /* Case 3b: letter-embedded — on NORMALIZED input. */
    if (re_match(RE_LETTER_EMBED, norm)) {
        out->type = PR_VER_STANDARD;
        size_t nt;
        char **parts = split_char(norm, '.', &nt);
        if (parts) {
            size_t cap = 0;
            for (size_t i = 0; i < nt; i++) {
                /* If the part is all-digit, push it as one component;
                 * otherwise split on letter runs. */
                int has_alpha = 0;
                for (const char *p = parts[i]; *p; p++) {
                    if (isalpha((unsigned char)*p)) { has_alpha = 1; break; }
                }
                if (!has_alpha) {
                    if (out->n_components == cap) {
                        cap = cap == 0 ? 8 : cap * 2;
                        int *np = (int *)realloc(out->components, cap * sizeof *out->components);
                        if (!np) { free_tokens(parts); free(norm); return -1; }
                        out->components = np;
                    }
                    out->components[out->n_components++] =
                        (int)strtol(parts[i], NULL, 10);
                } else {
                    split_letter_embed_push(parts[i], &out->components,
                                            &out->n_components, &cap);
                }
            }
            free_tokens(parts);
        }
        free(norm);
        return 0;
    }
    /* Case 4: Integer — ^\d+$ on RAW input. */
    if (re_match(RE_INT, s)) {
        char *trimmed = trim_leading_zeros_dup(s);
        out->type      = PR_VER_INTEGER;
        out->int_value = parse_int64(trimmed);
        free(trimmed);
        free(norm);
        return 0;
    }
    /* Case 5: Decimal (or String fallback). Run on NORMALIZED-and-
     * trim-leading-zeros, just like PS. */
    {
        char *trimmed = trim_leading_zeros_dup(norm);
        double dv;
        if (try_parse_double(trimmed, &dv)) {
            out->type      = PR_VER_DECIMAL;
            out->dec_value = dv;
        } else {
            out->type = PR_VER_STRING;
            /* str_value already holds the raw input. */
        }
        free(trimmed);
    }
    free(norm);
    return 0;
}

void pr_version_free(pr_version_t *v)
{
    if (v == NULL) return;
    free(v->version_number);
    free(v->components);
    free(v->str_value);
    memset(v, 0, sizeof *v);
}

/* ----- pr_version_compare ------------------------------------------ */

static int is_date_type(pr_version_type_t t)
{
    return t == PR_VER_DATE_VERSION || t == PR_VER_VERSION_DATE;
}

int pr_version_compare(const char *a, const char *b)
{
    pr_version_t v1 = {0}, v2 = {0};
    if (pr_version_parse(a, &v1) != 0) return -2;
    if (pr_version_parse(b, &v2) != 0) { pr_version_free(&v1); return -2; }

    int result = 0;

    /* Rule 1: Both date-based. */
    if (is_date_type(v1.type) && is_date_type(v2.type)) {
        if      (v1.date > v2.date) result = 1;
        else if (v1.date < v2.date) result = -1;
        else {
            int c = strcmp(v1.version_number ? v1.version_number : "",
                           v2.version_number ? v2.version_number : "");
            if      (c > 0) result = 1;
            else if (c < 0) result = -1;
            else            result = 0;
        }
        goto done;
    }
    /* Rule 2: One side date-based. */
    if (is_date_type(v1.type) && !is_date_type(v2.type)) { result = 1;  goto done; }
    if (is_date_type(v2.type) && !is_date_type(v1.type)) { result = -1; goto done; }

    /* Rule 3: Both StandardVersion. */
    if (v1.type == PR_VER_STANDARD && v2.type == PR_VER_STANDARD) {
        size_t maxn = v1.n_components > v2.n_components ? v1.n_components : v2.n_components;
        for (size_t i = 0; i < maxn; i++) {
            int c1 = i < v1.n_components ? v1.components[i] : 0;
            int c2 = i < v2.n_components ? v2.components[i] : 0;
            if (c1 > c2) { result = 1;  goto done; }
            if (c1 < c2) { result = -1; goto done; }
        }
        result = 0;
        goto done;
    }
    /* Rule 4: Both Integer. */
    if (v1.type == PR_VER_INTEGER && v2.type == PR_VER_INTEGER) {
        if      (v1.int_value > v2.int_value) result = 1;
        else if (v1.int_value < v2.int_value) result = -1;
        else                                  result = 0;
        goto done;
    }
    /* Rule 5: Both Decimal. */
    if (v1.type == PR_VER_DECIMAL && v2.type == PR_VER_DECIMAL) {
        if      (v1.dec_value > v2.dec_value) result = 1;
        else if (v1.dec_value < v2.dec_value) result = -1;
        else                                  result = 0;
        goto done;
    }
    /* Rule 6: Integer vs Decimal. */
    if (v1.type == PR_VER_INTEGER && v2.type == PR_VER_DECIMAL) {
        int64_t r = (int64_t)v2.dec_value;
        if      (v1.int_value > r) result = 1;
        else if (v1.int_value < r) result = -1;
        else                       result = 0;
        goto done;
    }
    if (v2.type == PR_VER_INTEGER && v1.type == PR_VER_DECIMAL) {
        int64_t l = (int64_t)v1.dec_value;
        if      (l > v2.int_value) result = 1;
        else if (l < v2.int_value) result = -1;
        else                       result = 0;
        goto done;
    }
    /* Rule 7: Standard vs (Integer | Decimal). */
    if (v1.type == PR_VER_STANDARD &&
        (v2.type == PR_VER_INTEGER || v2.type == PR_VER_DECIMAL)) {
        int64_t c2 = v2.type == PR_VER_INTEGER ? v2.int_value : (int64_t)v2.dec_value;
        int     c1 = v1.n_components > 0 ? v1.components[0] : 0;
        if      ((int64_t)c1 > c2) result = 1;
        else if ((int64_t)c1 < c2) result = -1;
        else                       result = 0;
        goto done;
    }
    if (v2.type == PR_VER_STANDARD &&
        (v1.type == PR_VER_INTEGER || v1.type == PR_VER_DECIMAL)) {
        int64_t c1 = v1.type == PR_VER_INTEGER ? v1.int_value : (int64_t)v1.dec_value;
        int     c2 = v2.n_components > 0 ? v2.components[0] : 0;
        if      (c1 > (int64_t)c2) result = 1;
        else if (c1 < (int64_t)c2) result = -1;
        else                       result = 0;
        goto done;
    }
    /* Rule 8: String fallback — compare .Value as strings. PS uses
     *   $v1.Value -gt $v2.Value
     * which on mixed types coerces both via the left-hand operand. We
     * use the raw `str_value` we always kept. */
    {
        int c = strcmp(v1.str_value ? v1.str_value : "",
                       v2.str_value ? v2.str_value : "");
        if      (c > 0) result = 1;
        else if (c < 0) result = -1;
        else            result = 0;
    }

done:
    pr_version_free(&v1);
    pr_version_free(&v2);
    return result;
}
