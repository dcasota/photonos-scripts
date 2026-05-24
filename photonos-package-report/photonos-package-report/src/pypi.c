/* pypi.c — PyPI JSON-API latest-version detection (python family).
 *
 * Many python-* specs have a Source0 on files.pythonhosted.org / pypi.python.org
 * whose upstream has no usable git tags (e.g. pyjsparser's github mirror is
 * tagless). The authoritative source is the PyPI JSON API that backs the
 * /project/<pkg>/#files page:
 *   GET https://pypi.org/pypi/<pkg>/json
 *     info.version            -> latest release
 *     urls[] (latest's files) -> the sdist filename + hashed download URL
 *
 * Parsed with PCRE2 (no json-c dependency), same approach as rubygems.c. The
 * version is info.version (the first "version" key in the document — info is
 * the leading object). The sdist URL/name are taken from the top-level "urls"
 * array (the latest version's files), scoped past the "urls": key so the
 * earlier "releases" map (older versions' files) is never matched.
 */
#include "pr_pypi.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BODY_CAP_BYTES (32 * 1024 * 1024)   /* releases map can be large */

struct body_buf { char *data; size_t len, cap; int overflow; };

static size_t body_write_cb(void *ptr, size_t size, size_t nmemb, void *userdata)
{
    struct body_buf *b = (struct body_buf *)userdata;
    size_t n = size * nmemb;
    if (b->overflow) return n;
    if (b->len + n > BODY_CAP_BYTES) { b->overflow = 1; return n; }
    if (b->len + n > b->cap) {
        size_t nc = b->cap ? b->cap * 2 : 65536;
        while (nc < b->len + n) nc *= 2;
        char *p = (char *)realloc(b->data, nc);
        if (!p) { b->overflow = 1; return n; }
        b->data = p; b->cap = nc;
    }
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    return n;
}

static pcre2_code *RE_VER, *RE_URLS, *RE_SDIST;
static pthread_once_t g_once = PTHREAD_ONCE_INIT;

static pcre2_code *compile(const char *pat)
{
    int err = 0; PCRE2_SIZE off = 0;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED,
                                   PCRE2_DOTALL, &err, &off, NULL);
    if (!re) {
        PCRE2_UCHAR e[256]; pcre2_get_error_message(err, e, sizeof e);
        fprintf(stderr, "pypi.c: compile('%s') failed: %s\n", pat, (char *)e);
        abort();
    }
    return re;
}

static void init_re(void)
{
    /* First "version":"X" key — info.version (info is the leading object). */
    RE_VER  = compile("\"version\"\\s*:\\s*\"([^\"]+)\"");
    /* Top-level "urls": array start (not "project_urls"). */
    RE_URLS = compile("\"urls\"\\s*:\\s*\\[");
    /* A source-archive download URL inside the urls array. */
    RE_SDIST = compile("\"url\"\\s*:\\s*\"(https://[^\"]+\\.(?:tar\\.gz|tar\\.bz2|tar\\.xz|zip|tgz))\"");
}

static char *capture(pcre2_code *re, const char *s, size_t len, size_t from,
                     PCRE2_SIZE *match_end)
{
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    if (!md) return NULL;
    char *out = NULL;
    int rc = pcre2_match(re, (PCRE2_SPTR)s, len, from, 0, md, NULL);
    if (rc >= 0) {
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        if (match_end) *match_end = ov[1];
        if (rc >= 2 && ov[2] != PCRE2_UNSET) {
            size_t l = (size_t)(ov[3] - ov[2]);
            out = (char *)malloc(l + 1);
            if (out) { memcpy(out, s + ov[2], l); out[l] = '\0'; }
        } else if (match_end) {
            /* matched, no capture group requested */
        }
    }
    pcre2_match_data_free(md);
    return out;
}

char *pr_pypi_latest_version(const char *package,
                             char **out_sdist_url, char **out_sdist_name)
{
    if (out_sdist_url)  *out_sdist_url  = NULL;
    if (out_sdist_name) *out_sdist_name = NULL;
    if (package == NULL || package[0] == '\0') return NULL;

    char *url = NULL;
    if (asprintf(&url, "https://pypi.org/pypi/%s/json", package) < 0) return NULL;

    struct body_buf body = {0};
    CURL *c = curl_easy_init();
    if (!c) { free(url); return NULL; }
    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     20000L);
    curl_easy_setopt(c, CURLOPT_USERAGENT,      "photonos-package-report/C");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  body_write_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,      &body);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
    CURLcode rc = curl_easy_perform(c);
    long status = 0;
    if (rc == CURLE_OK) curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);
    free(url);
    if (rc != CURLE_OK || status < 200 || status >= 300 || body.overflow || body.len == 0) {
        free(body.data); return NULL;
    }

    pthread_once(&g_once, init_re);

    char *version = capture(RE_VER, body.data, body.len, 0, NULL);

    if (version && (out_sdist_url || out_sdist_name)) {
        /* Scope the sdist search to the top-level "urls" array (latest's
         * files), past the earlier "releases" map. */
        PCRE2_SIZE urls_end = 0;
        char *dummy = capture(RE_URLS, body.data, body.len, 0, &urls_end);
        free(dummy);
        size_t from = urls_end ? urls_end : 0;
        char *surl = capture(RE_SDIST, body.data, body.len, from, NULL);
        if (surl) {
            char *base = strrchr(surl, '/');
            char *name = strdup(base ? base + 1 : surl);
            if (out_sdist_url)  *out_sdist_url  = surl; else free(surl);
            if (out_sdist_name) *out_sdist_name = name; else free(name);
        }
    }

    free(body.data);
    return version;
}
