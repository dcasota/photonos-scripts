/* netcat.c — netcat.spec bespoke version + commit_id detection.
 *
 * Phase M task M62. Mirrors photonos-package-report.ps1 L 2540-2556.
 */
#include "pr_netcat.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NC_BODY_CAP (4 * 1024 * 1024)   /* netcat.c ~100 KB; API page small */

struct nc_buf { char *data; size_t len; int overflow; };

static size_t nc_write(void *ptr, size_t size, size_t nmemb, void *ud)
{
    struct nc_buf *b = (struct nc_buf *)ud;
    size_t n = size * nmemb;
    if (b->overflow) return n;
    if (b->len + n + 1 > NC_BODY_CAP) { b->overflow = 1; return n; }
    char *p = (char *)realloc(b->data, b->len + n + 1);
    if (!p) { b->overflow = 1; return n; }
    b->data = p;
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    b->data[b->len] = '\0';
    return n;
}

/* GET `url`; returns malloc'd NUL-terminated body (caller frees) or NULL.
 * `headers` is an optional slist (Authorization / Accept / etc.). */
static char *nc_get(const char *url, struct curl_slist *headers)
{
    CURL *c = curl_easy_init();
    if (!c) return NULL;
    struct nc_buf b = {0};
    curl_easy_setopt(c, CURLOPT_URL,             url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION,  1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,      30000L);
    curl_easy_setopt(c, CURLOPT_USERAGENT,       "photonos-package-report");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,   nc_write);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,       &b);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
    if (headers) curl_easy_setopt(c, CURLOPT_HTTPHEADER, headers);
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    if (rc == CURLE_OK) curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);
    if (rc != CURLE_OK || status < 200 || status >= 400 || b.overflow) {
        free(b.data);
        return NULL;
    }
    return b.data;  /* may be NULL only if no body written */
}

/* PS: `$netcatContent -match '\$OpenBSD:\s+netcat\.c,v\s+(\d+\.\d+)'`. */
static char *extract_version(const char *body)
{
    if (!body) return NULL;
    int err = 0; PCRE2_SIZE eoff = 0;
    pcre2_code *re = pcre2_compile(
        (PCRE2_SPTR)"\\$OpenBSD:\\s+netcat\\.c,v\\s+(\\d+\\.\\d+)",
        PCRE2_ZERO_TERMINATED, 0, &err, &eoff, NULL);
    if (!re) return NULL;
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    char *out = NULL;
    if (md && pcre2_match(re, (PCRE2_SPTR)body, strlen(body), 0, 0, md, NULL) >= 0) {
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        size_t s = ov[2], e = ov[3];
        if (s != PCRE2_UNSET && e > s) {
            out = (char *)malloc(e - s + 1);
            if (out) { memcpy(out, body + s, e - s); out[e - s] = '\0'; }
        }
    }
    if (md) pcre2_match_data_free(md);
    pcre2_code_free(re);
    return out;
}

/* PS: `$commitResponse[0].sha.Substring(0,7)` — the first "sha" value in
 * the Commits API JSON array, first 7 chars. */
static char *extract_commit_id(const char *body)
{
    if (!body) return NULL;
    const char *p = strstr(body, "\"sha\"");
    if (!p) return NULL;
    p += 5;                                   /* past "sha" */
    while (*p && *p != ':') p++;
    if (*p == ':') p++;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '"') return NULL;
    p++;                                      /* opening quote of the value */
    /* Copy up to 7 leading hex chars. */
    char *out = (char *)malloc(8);
    if (!out) return NULL;
    size_t k = 0;
    while (k < 7 && ((p[k] >= '0' && p[k] <= '9') ||
                     (p[k] >= 'a' && p[k] <= 'f') ||
                     (p[k] >= 'A' && p[k] <= 'F'))) {
        out[k] = p[k]; k++;
    }
    out[k] = '\0';
    if (k < 7) { free(out); return NULL; }
    return out;
}

int pr_netcat_detect(const char *github_token,
                     char **out_version, char **out_commit_id)
{
    if (out_version)   *out_version   = NULL;
    if (out_commit_id) *out_commit_id = NULL;

    char *raw = nc_get("https://raw.githubusercontent.com/openbsd/src/master/usr.bin/nc/netcat.c",
                       NULL);
    char *ver = extract_version(raw);
    free(raw);
    if (!ver) return -1;
    if (out_version) *out_version = ver; else free(ver);

    /* Commits API for the short sha (download name). Best-effort. */
    struct curl_slist *h = NULL;
    h = curl_slist_append(h, "Accept: application/vnd.github+json");
    char auth[512];
    if (github_token && github_token[0]) {
        snprintf(auth, sizeof auth, "Authorization: Bearer %s", github_token);
        h = curl_slist_append(h, auth);
    }
    char *api = nc_get("https://api.github.com/repos/openbsd/src/commits?path=usr.bin/nc&per_page=1", h);
    curl_slist_free_all(h);
    char *cid = extract_commit_id(api);
    free(api);
    if (out_commit_id) *out_commit_id = cid; else free(cid);

    return 0;
}
