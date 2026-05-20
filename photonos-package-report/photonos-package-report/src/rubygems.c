/* rubygems.c — rubygems.org latest-version detection (M34).
 *
 * Ports photonos-package-report.ps1 L 3402-3456. RubyGems exposes a
 * JSON API that is far more reliable than HTML scraping:
 *   GET https://rubygems.org/api/v1/versions/<gem_name>.json
 *     -> [ {"number":"X.Y.Z", ... ,"prerelease":false, ...}, ... ]
 * sorted newest-first by created_at. PS takes the first object whose
 * "prerelease" is false.
 *
 * JSON is parsed with PCRE2 (consistent with koji.c's manual-parse
 * approach; avoids a json-c link dependency). The RubyGems schema
 * emits "number" before "prerelease" within each version object with
 * no nested object between them, so a non-greedy match pairs them
 * within the same object.
 */
#include "pr_rubygems.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BODY_CAP_BYTES (8 * 1024 * 1024)   /* gems with many versions */

struct body_buf {
    char  *data;
    size_t len;
    size_t cap;
    int    overflow;
};

static size_t body_write_cb(void *ptr, size_t size, size_t nmemb, void *userdata)
{
    struct body_buf *b = (struct body_buf *)userdata;
    size_t n = size * nmemb;
    if (b->overflow) return n;
    if (b->len + n > BODY_CAP_BYTES) { b->overflow = 1; return n; }
    if (b->len + n > b->cap) {
        size_t newcap = b->cap ? b->cap * 2 : 16384;
        while (newcap < b->len + n) newcap *= 2;
        char *p = (char *)realloc(b->data, newcap);
        if (!p) { b->overflow = 1; return n; }
        b->data = p;
        b->cap = newcap;
    }
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    return n;
}

/* Compile once: capture group 1 = version number, group 2 = prerelease
 * boolean. PCRE2_DOTALL so `.` spans the inter-field whitespace/newlines. */
static pcre2_code     *RE_VER;
static pthread_once_t  g_ver_once = PTHREAD_ONCE_INIT;

static void init_re_ver(void)
{
    int        err = 0;
    PCRE2_SIZE off = 0;
    RE_VER = pcre2_compile(
        (PCRE2_SPTR)"\"number\"\\s*:\\s*\"([^\"]+)\".*?\"prerelease\"\\s*:\\s*(true|false)",
        PCRE2_ZERO_TERMINATED, PCRE2_DOTALL, &err, &off, NULL);
    if (!RE_VER) {
        PCRE2_UCHAR ebuf[256];
        pcre2_get_error_message(err, ebuf, sizeof ebuf);
        fprintf(stderr, "rubygems.c: re_compile failed: %s\n", (char *)ebuf);
        abort();
    }
}

char *pr_rubygems_latest_version(const char *gem_name)
{
    if (gem_name == NULL || gem_name[0] == '\0') return NULL;

    char *url = NULL;
    if (asprintf(&url, "https://rubygems.org/api/v1/versions/%s.json", gem_name) < 0)
        return NULL;

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
        free(body.data);
        return NULL;
    }

    pthread_once(&g_ver_once, init_re_ver);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(RE_VER, NULL);
    if (!md) { free(body.data); return NULL; }

    char *result = NULL;
    PCRE2_SIZE offset = 0;
    while (offset < body.len) {
        int hits = pcre2_match(RE_VER, (PCRE2_SPTR)body.data, body.len,
                                offset, 0, md, NULL);
        if (hits < 0) break;
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        /* group 1 = number, group 2 = prerelease */
        PCRE2_SIZE num_s = ov[2], num_e = ov[3];
        PCRE2_SIZE pre_s = ov[4], pre_e = ov[5];
        if (num_s != PCRE2_UNSET && pre_s != PCRE2_UNSET) {
            size_t pre_len = (size_t)(pre_e - pre_s);
            int is_prerelease = (pre_len == 4
                && strncmp(body.data + pre_s, "true", 4) == 0);
            if (!is_prerelease) {
                /* First stable version in newest-first order — take it. */
                size_t vlen = (size_t)(num_e - num_s);
                result = (char *)malloc(vlen + 1);
                if (result) {
                    memcpy(result, body.data + num_s, vlen);
                    result[vlen] = '\0';
                }
                break;
            }
        }
        offset = ov[1];
        if (offset <= ov[0]) offset++;
    }

    pcre2_match_data_free(md);
    free(body.data);
    return result;
}
