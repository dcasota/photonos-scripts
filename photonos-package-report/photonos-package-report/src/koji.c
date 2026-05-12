/* koji.c — KojiFedoraProjectLookUp port.
 * Mirrors photonos-package-report.ps1 L 1520-1572.
 *
 * PS source (verbatim, condensed):
 *
 *     function KojiFedoraProjectLookUp {
 *         param([parameter(Mandatory=$true)][string]$ArtefactName)
 *         $SourceRPMFileURL=""
 *         $SourceTagURL="https://src.fedoraproject.org/rpms/$ArtefactName/blob/main/f/sources"
 *         try {
 *             $ArtefactDownloadName=((((((invoke-restmethod -uri $SourceTagURL ...)
 *                 -split '<code class') -split '</code>')[1]) -split '\(') -split '\)')[1]
 *             $ArtefactVersion=$ArtefactDownloadName -ireplace "${ArtefactName}-",""
 *             if ($ArtefactName -ieq "connect-proxy") {$ArtefactVersion=$ArtefactDownloadName -ireplace "ssh-connect-",""}
 *             if ($ArtefactName -ieq "python-pbr")    {$ArtefactVersion=$ArtefactDownloadName -ireplace "pbr-",""}
 *             $ArtefactVersion=$ArtefactVersion -ireplace ".tar.gz",""
 *             $ArtefactVersion=$ArtefactVersion -ireplace "v",""
 *
 *             $SourceTagURL="https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion"
 *             $Names = ((invoke-restmethod ...) -split '/">') -split '/</a>'
 *             $Names = $Names | foreach-object { if (!($_ | select-string '<' -simplematch)) {$_}}
 *             $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
 *             $lastItem = $Names | Sort-Object {...} | select-object -last 1
 *
 *             $SourceTagURL="https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion/$NameLatest/src/"
 *             $Names = ((invoke-restmethod ...) -split '<a href="') -split '"'
 *             $Names = $Names | where {!($_ -match '<') -and ($_ -match '.src.rpm')}
 *             $lastItem = $Names | Sort-Object {...} | select-object -last 1
 *
 *             $SourceRPMFileURL = "https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion/$NameLatest/src/$SourceRPMFileName"
 *         } catch { ... silent ... }
 *         return $SourceRPMFileURL
 *     }
 *
 * The HTML parsing logic is factored into four pr_koji_* helpers so we
 * can unit-test them deterministically against canned input without
 * touching the network.
 */
#include "pr_koji.h"
#include "pr_strutil.h"

#include <curl/curl.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* ----- libcurl GET into heap buffer --------------------------------- */

typedef struct { char *buf; size_t len; size_t cap; } httpbuf_t;

static size_t collect_cb(char *p, size_t s, size_t n, void *u)
{
    httpbuf_t *b = (httpbuf_t *)u;
    size_t add = s * n;
    if (b->len + add + 1 > b->cap) {
        size_t nc = b->cap == 0 ? 4096 : b->cap;
        while (nc < b->len + add + 1) nc *= 2;
        char *np = (char *)realloc(b->buf, nc);
        if (!np) return 0;
        b->buf = np; b->cap = nc;
    }
    memcpy(b->buf + b->len, p, add);
    b->len += add;
    b->buf[b->len] = '\0';
    return add;
}

static int http_get(const char *url, long timeout_ms, char **out_body)
{
    *out_body = NULL;
    CURL *c = curl_easy_init();
    if (!c) return -1;
    httpbuf_t b = {0};
    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     timeout_ms);
    curl_easy_setopt(c, CURLOPT_USERAGENT,      "photonos-package-report/C");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  collect_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,      &b);
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);
    if (rc != CURLE_OK || status < 200 || status >= 300) {
        free(b.buf);
        return -1;
    }
    *out_body = b.buf;
    return 0;
}

/* ----- Pure parsers ------------------------------------------------- */

/* Step 1: find the FIRST `<code class...>...</code>` block, then
 * inside that block find the substring between '(' and ')'.
 *
 * PS:
 *   ((((((html -split '<code class') -split '</code>')[1]) -split '\(') -split '\)')[1]
 *
 * Breakdown:
 *   - split on '<code class' → take element [1] (everything after the
 *     first `<code class`)
 *   - split on '</code>'    → take element [1] -- BUT PS array indexing
 *     after two -splits gets confusing. Inspecting the chain again:
 *
 *     "$html -split '<code class'" returns an array; element [1] is the
 *     text after the first opener. Then "-split '</code>'" splits that;
 *     element [0] is what's inside the <code> tag, [1] is what comes
 *     after `</code>`. The PS author wrote `[1]` here meaning the
 *     text BETWEEN the first `<code class>` and the corresponding
 *     `</code>` — except it's actually `[0]` of the inner split. Real
 *     Fedora pages always have a single `(` after `</code>` outside the
 *     tag, like `<code class>X</code> (filename.tar.gz)`. The PS chain
 *     ultimately extracts whatever sits between the `(` and `)` AFTER
 *     `</code>`. We honour that.
 *
 * The C parser implements this:
 *   1. Find "<code class" anchor.
 *   2. From there, find "</code>".
 *   3. From there, find next '('.
 *   4. From there, find next ')'.
 *   5. Return the bytes between '(' and ')'.
 */
char *pr_koji_parse_artefact_download_name(const char *html)
{
    if (html == NULL) return NULL;
    const char *p = strstr(html, "<code class");
    if (!p) return NULL;
    p = strstr(p, "</code>");
    if (!p) return NULL;
    p += 7; /* past "</code>" */
    p = strchr(p, '(');
    if (!p) return NULL;
    p++;
    const char *q = strchr(p, ')');
    if (!q) return NULL;
    size_t n = (size_t)(q - p);
    char *out = (char *)malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, p, n);
    out[n] = '\0';
    return out;
}

/* Step 2: derive version. PS L 1543-1547 chain:
 *   $v = $download_name -ireplace "<name>-",""
 *   if name == "connect-proxy"  : $v = $download_name -ireplace "ssh-connect-",""
 *   if name == "python-pbr"     : $v = $download_name -ireplace "pbr-",""
 *   $v = $v -ireplace ".tar.gz",""
 *   $v = $v -ireplace "v",""
 *
 * Note: the special-case branches REPLACE $v entirely (off $download_name),
 * not on top of the previous $v. We preserve that.
 *
 * Note: the final ireplace "v","" strips *every* occurrence of 'v',
 * case-insensitively — a quirk of the PS author that we must keep
 * (CLAUDE.md invariant #2: bug-fixes flow PS → spec → C, not vice versa).
 */
char *pr_koji_derive_version(const char *artefact_name, const char *download_name)
{
    if (artefact_name == NULL || download_name == NULL) return NULL;

    char *v = NULL;
    /* default: strip "<name>-" */
    size_t nlen = strlen(artefact_name);
    char *needle = (char *)malloc(nlen + 2);
    if (!needle) return NULL;
    memcpy(needle, artefact_name, nlen);
    needle[nlen] = '-';
    needle[nlen + 1] = '\0';
    /* duplicate download_name into a heap copy first (istr_replace_all
     * takes ownership). */
    v = (char *)malloc(strlen(download_name) + 1);
    if (!v) { free(needle); return NULL; }
    memcpy(v, download_name, strlen(download_name) + 1);
    v = istr_replace_all(v, needle, "");
    free(needle);

    /* Special cases override `v` from `download_name`. */
    if (strcasecmp(artefact_name, "connect-proxy") == 0) {
        free(v);
        v = (char *)malloc(strlen(download_name) + 1);
        if (!v) return NULL;
        memcpy(v, download_name, strlen(download_name) + 1);
        v = istr_replace_all(v, "ssh-connect-", "");
    } else if (strcasecmp(artefact_name, "python-pbr") == 0) {
        free(v);
        v = (char *)malloc(strlen(download_name) + 1);
        if (!v) return NULL;
        memcpy(v, download_name, strlen(download_name) + 1);
        v = istr_replace_all(v, "pbr-", "");
    }

    v = istr_replace_all(v, ".tar.gz", "");
    v = istr_replace_all(v, "v", "");
    return v;
}

/* PS Sort-Object {$_ -notlike '<*'},{($_ -replace '^.*?(\d+).*$','$1') -as [int]}
 *   | select-object -last 1
 *
 * Translates to: among entries that DO NOT start with '<', pick the one
 * whose first run-of-digits parses to the largest integer. Ties broken
 * by stable insertion order (PS Sort-Object is stable).
 *
 * Returns a malloc'd copy of the winner, or NULL if no candidate exists.
 */
static long first_int_in(const char *s)
{
    long v = -1;
    const char *p = s;
    while (*p && !isdigit((unsigned char)*p)) p++;
    if (!*p) return -1;
    v = 0;
    while (*p && isdigit((unsigned char)*p)) {
        v = v * 10 + (*p - '0');
        p++;
    }
    return v;
}

static char *pick_largest_numeric(char **cands, size_t n)
{
    long best = -1;
    int  best_idx = -1;
    for (size_t i = 0; i < n; i++) {
        const char *c = cands[i];
        if (c == NULL || c[0] == '\0') continue;
        if (c[0] == '<') continue;
        long v = first_int_in(c);
        if (v < 0) continue;
        if (v > best || best_idx < 0) {
            best = v;
            best_idx = (int)i;
        } else if (v == best) {
            /* PS stable sort: keep the EARLIER one when ties? No —
             * PS `select-object -last 1` after stable sort keeps the
             * LATER one of equal keys (since stable sort preserves
             * input order and -last 1 takes the tail). */
            best_idx = (int)i;
        }
    }
    if (best_idx < 0) return NULL;
    return strdup(cands[best_idx]);
}

/* PS:
 *   $Names = (html -split '/">') -split '/</a>'
 *   $Names = $Names | where { !($_ -match '<') -and ($_ -match '\d') }
 *   pick the one with the largest leading int.
 *
 * "Split on A, then split each result on B" — concatenate the two split
 * passes by splitting on either delimiter.
 */
char *pr_koji_pick_latest_release(const char *html)
{
    if (html == NULL) return NULL;
    /* Tokenise on either '/">' or '/</a>' boundaries. */
    char *copy = strdup(html);
    if (!copy) return NULL;

    size_t cap = 64, count = 0;
    char **toks = (char **)malloc(cap * sizeof *toks);
    if (!toks) { free(copy); return NULL; }

    char *cur = copy;
    while (*cur) {
        char *next = NULL;
        char *a = strstr(cur, "/\">");
        char *b = strstr(cur, "/</a>");
        char *hit = NULL;
        size_t hit_len = 0;
        if (a && (!b || a < b)) { hit = a; hit_len = 3; }
        else if (b)             { hit = b; hit_len = 5; }
        if (hit) {
            *hit = '\0';
            next = hit + hit_len;
        }
        /* PS where: skip if line contains '<' or has no digit. */
        int has_lt = strchr(cur, '<') != NULL;
        int has_dg = 0;
        for (const char *p = cur; *p; p++) {
            if (isdigit((unsigned char)*p)) { has_dg = 1; break; }
        }
        if (!has_lt && has_dg) {
            if (count == cap) {
                cap *= 2;
                char **np = (char **)realloc(toks, cap * sizeof *toks);
                if (!np) { free(copy); free(toks); return NULL; }
                toks = np;
            }
            toks[count++] = cur;
        }
        if (!next) break;
        cur = next;
    }

    char *winner = pick_largest_numeric(toks, count);
    free(toks);
    free(copy);
    return winner;
}

/* PS:
 *   $Names = (html -split '<a href="') -split '"'
 *   $Names = $Names | where { !($_ -match '<') -and ($_ -match '.src.rpm') }
 *   pick largest-numeric
 */
char *pr_koji_pick_latest_srpm(const char *html)
{
    if (html == NULL) return NULL;
    char *copy = strdup(html);
    if (!copy) return NULL;

    size_t cap = 64, count = 0;
    char **toks = (char **)malloc(cap * sizeof *toks);
    if (!toks) { free(copy); return NULL; }

    /* Tokenise on either '<a href="' or '"'. */
    char *cur = copy;
    while (*cur) {
        char *next = NULL;
        char *a = strstr(cur, "<a href=\"");
        char *b = strchr(cur, '"');
        char *hit = NULL;
        size_t hit_len = 0;
        if (a && (!b || a < b)) { hit = a; hit_len = 9; }
        else if (b)             { hit = b; hit_len = 1; }
        if (hit) {
            *hit = '\0';
            next = hit + hit_len;
        }
        int has_lt = strchr(cur, '<') != NULL;
        int has_srpm = strstr(cur, ".src.rpm") != NULL;
        if (!has_lt && has_srpm) {
            if (count == cap) {
                cap *= 2;
                char **np = (char **)realloc(toks, cap * sizeof *toks);
                if (!np) { free(copy); free(toks); return NULL; }
                toks = np;
            }
            toks[count++] = cur;
        }
        if (!next) break;
        cur = next;
    }
    char *winner = pick_largest_numeric(toks, count);
    free(toks);
    free(copy);
    return winner;
}

/* ----- Public entry point ------------------------------------------- */

int koji_fedora_lookup(const char *artefact_name, char **out_url)
{
    if (out_url == NULL) return -1;
    *out_url = strdup("");
    if (*out_url == NULL) return -1;
    if (artefact_name == NULL || artefact_name[0] == '\0') return 0;

    /* Step 1: GET src.fedoraproject.org sources page. */
    char url1[1024];
    snprintf(url1, sizeof url1,
             "https://src.fedoraproject.org/rpms/%s/blob/main/f/sources",
             artefact_name);

    char *body1 = NULL;
    if (http_get(url1, 10000, &body1) != 0) return 0;  /* silent miss */
    char *dlname = pr_koji_parse_artefact_download_name(body1);
    free(body1);
    if (!dlname) return 0;

    /* Step 2: derive version. */
    char *version = pr_koji_derive_version(artefact_name, dlname);
    free(dlname);
    if (!version || version[0] == '\0') { free(version); return 0; }

    /* Step 3: list release subdirs. */
    char url2[1024];
    snprintf(url2, sizeof url2,
             "https://kojipkgs.fedoraproject.org/packages/%s/%s",
             artefact_name, version);
    char *body2 = NULL;
    if (http_get(url2, 10000, &body2) != 0) { free(version); return 0; }
    char *release = pr_koji_pick_latest_release(body2);
    free(body2);
    if (!release) { free(version); return 0; }

    /* Step 4: list .src.rpm files. */
    char url3[1024];
    snprintf(url3, sizeof url3,
             "https://kojipkgs.fedoraproject.org/packages/%s/%s/%s/src/",
             artefact_name, version, release);
    char *body3 = NULL;
    if (http_get(url3, 10000, &body3) != 0) {
        free(version); free(release); return 0;
    }
    char *srpm = pr_koji_pick_latest_srpm(body3);
    free(body3);
    if (!srpm) { free(version); free(release); return 0; }

    /* Step 5: assemble final URL. */
    char final_url[2048];
    snprintf(final_url, sizeof final_url,
             "https://kojipkgs.fedoraproject.org/packages/%s/%s/%s/src/%s",
             artefact_name, version, release, srpm);
    free(version); free(release); free(srpm);

    free(*out_url);
    *out_url = strdup(final_url);
    return *out_url ? 0 : -1;
}
