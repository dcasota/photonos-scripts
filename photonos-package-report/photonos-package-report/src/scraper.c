/* scraper.c — HTTP directory-listing scraper.
 *
 * Phase M task M20, FRD-018.
 *
 * One-shot libcurl GET + PCRE2 extraction of <a href="..."> values.
 * Used by CheckURLHealth's non-git update-detection path. Mirrors PS
 * L 4258-4283 (Invoke-WebRequest + .Links.href).
 */
#include "pr_scraper.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BODY_CAP_BYTES (1 * 1024 * 1024)   /* 1 MiB defensive cap */

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
    if (b->overflow) return n;  /* keep draining so curl finishes cleanly */
    if (b->len + n > BODY_CAP_BYTES) {
        b->overflow = 1;
        return n;
    }
    if (b->len + n > b->cap) {
        size_t newcap = b->cap ? b->cap * 2 : 16384;
        while (newcap < b->len + n) newcap *= 2;
        char *p = (char *)realloc(b->data, newcap);
        if (!p) {
            b->overflow = 1;
            return n;
        }
        b->data = p;
        b->cap = newcap;
    }
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    return n;
}

/* Compile once per process. */
static pcre2_code *g_href_re = NULL;

static pcre2_code *compile_href_re(void)
{
    if (g_href_re) return g_href_re;
    /* Match  <a ... href="VALUE" ... >  or  href='VALUE'.
     * Captures VALUE in group 1 (double-quoted) or group 2 (single-quoted).
     * Case-insensitive on the tag/attribute, raw on the value.
     * `[^"]*` and `[^']*` handle simple href values (no embedded same-quote).
     */
    PCRE2_SPTR pattern = (PCRE2_SPTR)"<a[^>]*\\bhref\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')";
    int errornumber = 0;
    PCRE2_SIZE erroroffset = 0;
    pcre2_code *re = pcre2_compile(pattern, PCRE2_ZERO_TERMINATED,
                                    PCRE2_CASELESS | PCRE2_DOTALL,
                                    &errornumber, &erroroffset, NULL);
    if (re == NULL) {
        fprintf(stderr, "pr_scraper: pcre2_compile failed at offset %zu err %d\n",
                (size_t)erroroffset, errornumber);
        return NULL;
    }
    g_href_re = re;
    return re;
}

int pr_scrape_listing(const char *url, char ***out_names, size_t *out_n)
{
    if (out_names == NULL || out_n == NULL) return -1;
    *out_names = NULL;
    *out_n = 0;
    if (url == NULL || *url == '\0') return -1;

    struct body_buf body = {0};
    CURL *c = curl_easy_init();
    if (!c) return -1;

    curl_easy_setopt(c, CURLOPT_URL,           url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     20000L);
    curl_easy_setopt(c, CURLOPT_USERAGENT,
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/113.0.0.0 Safari/537.36");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, body_write_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,     &body);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");  /* allow gzip/deflate */

    /* Mirror PS L 4267-4282 Chrome-style headers to dodge bot
     * detection on some upstreams. */
    struct curl_slist *hdrs = NULL;
    hdrs = curl_slist_append(hdrs,
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,image/apng,*/*;q=0.8,"
        "application/signed-exchange;v=b3;q=0.7");
    hdrs = curl_slist_append(hdrs, "Accept-Language: en-US,en;q=0.9");
    hdrs = curl_slist_append(hdrs, "Cache-Control: max-age=0");
    hdrs = curl_slist_append(hdrs, "Upgrade-Insecure-Requests: 1");
    curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdrs);

    CURLcode rc = curl_easy_perform(c);
    long http_status = 0;
    if (rc == CURLE_OK) {
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &http_status);
    }
    curl_easy_cleanup(c);
    curl_slist_free_all(hdrs);

    if (rc != CURLE_OK || http_status < 200 || http_status >= 400) {
        free(body.data);
        return -1;
    }
    if (body.overflow) {
        fprintf(stderr, "pr_scraper: body too large for %s (cap %d MiB)\n",
                url, BODY_CAP_BYTES / (1024 * 1024));
        free(body.data);
        return -1;
    }
    if (body.len == 0) {
        free(body.data);
        return 0;
    }

    pcre2_code *re = compile_href_re();
    if (re == NULL) { free(body.data); return -1; }

    /* Walk the body, extracting hrefs. */
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    if (md == NULL) { free(body.data); return -1; }

    size_t cap = 32, n = 0;
    char **names = (char **)malloc(cap * sizeof(char *));
    if (!names) { pcre2_match_data_free(md); free(body.data); return -1; }

    PCRE2_SIZE offset = 0;
    while (offset < body.len) {
        int hits = pcre2_match(re, (PCRE2_SPTR)body.data, body.len,
                                offset, 0, md, NULL);
        if (hits < 0) break;
        PCRE2_SIZE *ovec = pcre2_get_ovector_pointer(md);
        /* Try double-quote group first (1), then single-quote (2). */
        PCRE2_SIZE start = ovec[2], end = ovec[3];
        if (start == PCRE2_UNSET) {
            start = ovec[4]; end = ovec[5];
        }
        if (start != PCRE2_UNSET && end > start) {
            size_t vlen = (size_t)(end - start);
            char *v = (char *)malloc(vlen + 1);
            if (v) {
                memcpy(v, body.data + start, vlen);
                v[vlen] = '\0';
                if (n == cap) {
                    size_t newcap = cap * 2;
                    char **p = (char **)realloc(names, newcap * sizeof(char *));
                    if (!p) { free(v); break; }
                    names = p; cap = newcap;
                }
                names[n++] = v;
            }
        }
        offset = ovec[1];
        if (offset == (PCRE2_SIZE)hits || offset <= ovec[0]) offset++;
    }

    pcre2_match_data_free(md);
    free(body.data);

    *out_names = names;
    *out_n = n;
    return 0;
}
