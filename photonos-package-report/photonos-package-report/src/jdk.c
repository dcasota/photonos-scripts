/* jdk.c — Get-HighestJdkVersion port.
 * Mirrors photonos-package-report.ps1 L 1638-1735 line-for-line.
 *
 * Parse jdk-X[.Y[.Z]][+B][-ga] / "jdk-X+B" / "jdk-X" into Major / Minor /
 * Patch / Build / IsGa. Sort descending by (Major, Minor, Patch, IsGa-then-Build).
 * Return Original -ireplace "jdk-".
 */
#include "pr_jdk.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct {
    const char *original;     /* not owned */
    int  major;
    int  minor;
    int  patch;
    int  build;
    int  is_ga;
} jdk_version_t;

/* Returns 1 if `s` starts with `prefix` (case-sensitive). */
static int starts_with(const char *s, const char *prefix)
{
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

/* Returns 1 if every character in [s, s+len) is a digit. */
static int all_digit(const char *s, size_t len)
{
    if (len == 0) return 0;
    for (size_t i = 0; i < len; i++) {
        if (!isdigit((unsigned char)s[i])) return 0;
    }
    return 1;
}

static int parse_int(const char *s)
{
    return (int)strtol(s, NULL, 10);
}

/* PS L 1648-1697: parse a single tag string. */
static void parse_one(const char *version, int default_major, const char *filter,
                       jdk_version_t *out)
{
    out->original = version;
    out->major    = default_major;
    out->minor    = 0;
    out->patch    = 0;
    out->build    = 0;
    out->is_ga    = 0;

    /* PS L 1661-1662: remove the literal "<filter>" prefix.
     * In C, `version` is guaranteed to start with `filter` (we only
     * called parse_one on filtered names). Skip it. */
    const char *p = version;
    size_t fl = strlen(filter);
    if (strncmp(p, filter, fl) == 0) p += fl;

    /* PS L 1665-1668: check for "-ga" suffix and strip it. */
    size_t plen = strlen(p);
    if (plen >= 3 && strcmp(p + plen - 3, "-ga") == 0) {
        out->is_ga = 1;
        plen -= 3;
    }

    /* Work on a heap copy so we can null-terminate after splitting. */
    char *body = (char *)malloc(plen + 1);
    if (!body) return;
    memcpy(body, p, plen);
    body[plen] = '\0';

    /* PS L 1671: split on '+' — version vs build. */
    char *plus = strchr(body, '+');
    char *version_part = body;
    char *build_part   = NULL;
    if (plus) { *plus = '\0'; build_part = plus + 1; }

    /* PS L 1675-1690: parse dotted version or bare major.
     *
     * M119: PS uses [string].Split(".") which preserves empty tokens
     * (".0.32" → ["", "0", "32"]). strtok_r collapses consecutive
     * delimiters and skips leading ones (".0.32" → ["0", "32"]),
     * shifting the slot mapping so the version-leading-dot case (which
     * is the common one because the filter prefix ate "jdk-11" off
     * "jdk-11.0.32+2") silently wrote major=0 then minor=32. The
     * comparator then ranked "jdk-11+28" (parses as 11.0.0+28) ABOVE
     * "jdk-11.0.32+2" (parses as 0.32.0+2). Replace strtok_r with a
     * manual split that mirrors .Split(".") exactly. */
    if (strchr(version_part, '.') != NULL) {
        const char *cur = version_part;
        int idx = 0;
        while (1) {
            const char *dot = strchr(cur, '.');
            size_t tlen = dot ? (size_t)(dot - cur) : strlen(cur);
            if (tlen > 0 && all_digit(cur, tlen)) {
                char buf[32];
                size_t cl = tlen < sizeof buf - 1 ? tlen : sizeof buf - 1;
                memcpy(buf, cur, cl);
                buf[cl] = '\0';
                int v = parse_int(buf);
                if      (idx == 0) out->major = v;
                else if (idx == 1) out->minor = v;
                else if (idx == 2) out->patch = v;
            }
            if (!dot) break;
            cur = dot + 1;
            idx++;
        }
    } else if (all_digit(version_part, strlen(version_part))) {
        /* Bare major: "11", "17", ... */
        out->major = parse_int(version_part);
    }

    if (build_part && all_digit(build_part, strlen(build_part))) {
        out->build = parse_int(build_part);
    }

    free(body);
}

/* qsort comparator: descending by (Major, Minor, Patch, IsGa-prio, Build). */
static int cmp_jdk_desc(const void *a, const void *b)
{
    const jdk_version_t *x = (const jdk_version_t *)a;
    const jdk_version_t *y = (const jdk_version_t *)b;
    if (x->major != y->major) return y->major - x->major;
    if (x->minor != y->minor) return y->minor - x->minor;
    if (x->patch != y->patch) return y->patch - x->patch;
    /* PS L 1718: IsGa => [int]::MaxValue, else Build. We model that
     * by treating is_ga as a tiebreaker BEFORE build. */
    if (x->is_ga != y->is_ga) return y->is_ga - x->is_ga;
    return y->build - x->build;
}

char *pr_get_highest_jdk_version(char **names, size_t n,
                                 int major_release,
                                 const char *filter)
{
    if (names == NULL || n == 0 || filter == NULL || filter[0] == '\0') return NULL;

    /* PS L 1654: filter to names starting with `<filter>` (no '*' here
     * because the input is already individual tag strings, not the
     * full git tag list — PS `-like '<filter>*'` is just prefix-match). */
    jdk_version_t *parsed = (jdk_version_t *)calloc(n, sizeof *parsed);
    if (!parsed) return NULL;
    size_t k = 0;
    for (size_t i = 0; i < n; i++) {
        if (names[i] == NULL) continue;
        if (!starts_with(names[i], filter)) continue;
        parse_one(names[i], major_release, filter, &parsed[k++]);
    }
    if (k == 0) { free(parsed); return NULL; }

    qsort(parsed, k, sizeof *parsed, cmp_jdk_desc);

    /* PS L 1733: return Original -ireplace "jdk-",""
     * For the C port, strip the literal "jdk-" prefix once. */
    const char *winner = parsed[0].original;
    const char *strip  = "jdk-";
    size_t slen = strlen(strip);
    if (strncasecmp(winner, strip, slen) == 0) winner += slen;

    char *out = strdup(winner);
    free(parsed);
    return out;
}
