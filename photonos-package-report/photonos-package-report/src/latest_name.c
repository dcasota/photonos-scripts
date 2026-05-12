/* latest_name.c — Get-LatestName port.
 * Mirrors photonos-package-report.ps1 L 1907-1949 line-for-line.
 *
 * PS source:
 *
 *   function Get-LatestName {
 *       param([Parameter(Mandatory=$false)]
 *             [AllowEmptyString()][AllowNull()][string[]]$Names)
 *       if ($Names) { $Names = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
 *       if (-not $Names -or $Names.Count -eq 0) { return "" }
 *
 *       $versionNames = @($Names | Where-Object { $_ -match '^\d+([.-]Q?\d+)*$' })
 *
 *       if ($versionNames -and $versionNames.Count -gt 0) {
 *           $latest = $versionNames[0]
 *           foreach ($name in $versionNames) {
 *               $result = Compare-VersionStrings -Namelatest $name -Version $latest
 *               if ($result -eq 1) { $latest = $name }
 *           }
 *           return $latest
 *       } else {
 *           try { ConvertFrom-Json $Names | Sort-Object | Select-Object -Last 1 }
 *           catch { $Names | Sort-Object | Select-Object -Last 1 }
 *       }
 *   }
 *
 * Notes:
 *   - The "ConvertFrom-Json" branch fires only when the entire $Names
 *     array is valid JSON — vanishingly rare for `git tag -l` output.
 *     We always take the lexicographic fallback (PS catch{} arm). If a
 *     real-world tag list ever turns out to be JSON we can add the
 *     parse later; the parity gate at Phase 8 will surface the gap.
 *   - "Whitespace-only" follows PS IsNullOrWhiteSpace: chars in
 *     " \t\r\n\v\f" only. UTF-8 multi-byte whitespace is not handled
 *     because PS Get-Content / git tag -l never produces such bytes.
 */
#include "pr_latest.h"
#include "pr_version.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <ctype.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Compile the version-name detector regex once. */
static pcre2_code     *RE_VERSION_NAME;
static pthread_once_t  g_re_once = PTHREAD_ONCE_INIT;

static void init_re(void)
{
    int        err_code = 0;
    PCRE2_SIZE err_off  = 0;
    RE_VERSION_NAME = pcre2_compile(
        (PCRE2_SPTR)"^\\d+([.-]Q?\\d+)*$",
        PCRE2_ZERO_TERMINATED, 0, &err_code, &err_off, NULL);
    if (!RE_VERSION_NAME) {
        PCRE2_UCHAR ebuf[256];
        pcre2_get_error_message(err_code, ebuf, sizeof ebuf);
        fprintf(stderr, "latest_name.c: re_compile failed: %s\n", (char *)ebuf);
        abort();
    }
}

static int is_version_name(const char *s)
{
    pthread_once(&g_re_once, init_re);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(RE_VERSION_NAME, NULL);
    int rc = pcre2_match(RE_VERSION_NAME, (PCRE2_SPTR)s, PCRE2_ZERO_TERMINATED,
                          0, 0, md, NULL);
    pcre2_match_data_free(md);
    return rc >= 0;
}

static int is_blank(const char *s)
{
    if (s == NULL) return 1;
    for (; *s; s++) {
        if (!isspace((unsigned char)*s)) return 0;
    }
    return 1;
}

static char *xstrdup(const char *s)
{
    size_t n = strlen(s);
    char *p = (char *)malloc(n + 1);
    if (p) memcpy(p, s, n + 1);
    return p;
}

static int cmp_strcmp(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

char *pr_get_latest_name(char **names, size_t n)
{
    /* PS: filter out null/whitespace-only entries. */
    char **kept = (char **)malloc((n + 1) * sizeof *kept);
    if (!kept) return xstrdup("");
    size_t k = 0;
    for (size_t i = 0; i < n; i++) {
        if (is_blank(names[i])) continue;
        kept[k++] = names[i];
    }
    if (k == 0) { free(kept); return xstrdup(""); }

    /* PS: select version-like entries. */
    char **vers = (char **)malloc(k * sizeof *vers);
    if (!vers) { free(kept); return xstrdup(""); }
    size_t v = 0;
    for (size_t i = 0; i < k; i++) {
        if (is_version_name(kept[i])) vers[v++] = kept[i];
    }

    char *out = NULL;
    if (v > 0) {
        /* Bubble-search-by-compare for the max (PS L 1928-1935). */
        const char *latest = vers[0];
        for (size_t i = 0; i < v; i++) {
            int rc = pr_version_compare(vers[i], latest);
            if (rc == 1) latest = vers[i];
        }
        out = xstrdup(latest);
    } else {
        /* Lexicographic sort, take last (PS L 1944 catch{} arm). */
        qsort(kept, k, sizeof *kept, cmp_strcmp);
        out = xstrdup(kept[k - 1]);
    }

    free(vers);
    free(kept);
    return out ? out : xstrdup("");
}
