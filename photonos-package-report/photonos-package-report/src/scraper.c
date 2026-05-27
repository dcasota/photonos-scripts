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

/* GET `url` into *body. `chrome` selects the Chrome UA + browser header set
 * (PS L4385-4400 fallback path); otherwise a minimal request with the simple
 * "photonos-package-report/C" UA and no extra headers, mirroring PS's PRIMARY
 * attempt (L4378, bare Invoke-RestMethod with the default agent). Returns 0
 * on a usable 2xx/3xx non-overflow body; -1 otherwise. Caller frees body.data. */
static int fetch_listing_body(const char *url, int chrome, struct body_buf *body)
{
    CURL *c = curl_easy_init();
    if (!c) return -1;

    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     20000L);
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  body_write_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,      body);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");  /* allow gzip/deflate */

    struct curl_slist *hdrs = NULL;
    if (chrome) {
        curl_easy_setopt(c, CURLOPT_USERAGENT,
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/113.0.0.0 Safari/537.36");
        /* Mirror PS L 4267-4282 Chrome-style headers to dodge bot
         * detection on some upstreams. */
        hdrs = curl_slist_append(hdrs,
            "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,"
            "image/avif,image/webp,image/apng,*/*;q=0.8,"
            "application/signed-exchange;v=b3;q=0.7");
        hdrs = curl_slist_append(hdrs, "Accept-Language: en-US,en;q=0.9");
        hdrs = curl_slist_append(hdrs, "Cache-Control: max-age=0");
        hdrs = curl_slist_append(hdrs, "Upgrade-Insecure-Requests: 1");
        curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdrs);
    } else {
        curl_easy_setopt(c, CURLOPT_USERAGENT, "photonos-package-report/C");
    }

    CURLcode rc = curl_easy_perform(c);
    long http_status = 0;
    if (rc == CURLE_OK) {
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &http_status);
    }
    curl_easy_cleanup(c);
    if (hdrs) curl_slist_free_all(hdrs);

    if (getenv("PR_SCRAPE_DEBUG")) {
        fprintf(stderr, "pr_scrape: url=%s chrome=%d rc=%d http=%ld body_len=%zu overflow=%d\n",
                url, chrome, (int)rc, http_status, body->len, body->overflow);
    }

    if (rc != CURLE_OK || http_status < 200 || http_status >= 400) return -1;
    if (body->overflow) {
        fprintf(stderr, "pr_scraper: body too large for %s (cap %d MiB)\n",
                url, BODY_CAP_BYTES / (1024 * 1024));
        return -1;
    }
    return 0;
}

/* Extract every <a href="..."> value from `body` into a fresh names array. */
static int extract_hrefs(const struct body_buf *body, char ***out_names, size_t *out_n)
{
    *out_names = NULL;
    *out_n = 0;

    pcre2_code *re = compile_href_re();
    if (re == NULL) return -1;
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    if (md == NULL) return -1;

    size_t cap = 32, n = 0;
    char **names = (char **)malloc(cap * sizeof(char *));
    if (!names) { pcre2_match_data_free(md); return -1; }

    PCRE2_SIZE offset = 0;
    while (offset < body->len) {
        int hits = pcre2_match(re, (PCRE2_SPTR)body->data, body->len,
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
                memcpy(v, body->data + start, vlen);
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
    *out_names = names;
    *out_n = n;
    return 0;
}

int pr_scrape_listing(const char *url, char ***out_names, size_t *out_n)
{
    if (out_names == NULL || out_n == NULL) return -1;
    *out_names = NULL;
    *out_n = 0;
    if (url == NULL || *url == '\0') return -1;

    /* PS L4378-4404 does the listing fetch in two stages: a primary
     * bare request (default agent), then a Chrome-UA retry on failure.
     * urlhealth.c already mirrors this two-stage pattern; the scraper did
     * not. Keep the Chrome attempt as the PRIMARY here so every spec that
     * already detects stays byte-identical (it returns on chrome=1 and
     * never reaches the fallback); only add the simple-UA fallback for
     * specs the Chrome attempt fails to scrape (e.g. dist.schmorp.de/libev,
     * which serves its autoindex to the "photonos-package-report/C" agent
     * — the same UA urlhealth used to get 200 on the file — but not Chrome). */
    for (int chrome = 1; chrome >= 0; chrome--) {
        struct body_buf body = {0};
        int frc = fetch_listing_body(url, chrome, &body);
        if (frc == 0 && body.len > 0) {
            char **names = NULL;
            size_t  n     = 0;
            int erc = extract_hrefs(&body, &names, &n);
            free(body.data);
            if (getenv("PR_SCRAPE_DEBUG")) {
                fprintf(stderr, "pr_scrape: url=%s chrome=%d hrefs=%zu\n",
                        url, chrome, n);
            }
            if (erc == 0 && n > 0) {
                *out_names = names;
                *out_n     = n;
                return 0;
            }
            /* Body fetched but no hrefs — free and try the next stage. */
            if (names) {
                for (size_t i = 0; i < n; i++) free(names[i]);
                free(names);
            }
        } else {
            free(body.data);
        }
    }
    return -1;
}

/* M44 / PS L 4363-4367: extract <Key>...</Key> values from an S3-bucket
 * XML listing (json-c is hosted on s3.amazonaws.com). The caller filters
 * by prefix and drops the unwanted variants. Mirrors pr_scrape_listing's
 * fetch but matches the XML <Key> element instead of <a href>. */
int pr_scrape_keys(const char *url, char ***out_names, size_t *out_n)
{
    if (out_names == NULL || out_n == NULL) return -1;
    *out_names = NULL;
    *out_n = 0;
    if (url == NULL || *url == '\0') return -1;

    struct body_buf body = {0};
    CURL *c = curl_easy_init();
    if (!c) return -1;
    curl_easy_setopt(c, CURLOPT_URL,             url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION,  1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,      20000L);
    curl_easy_setopt(c, CURLOPT_USERAGENT,       "PowerShell");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,   body_write_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,       &body);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
    CURLcode rc = curl_easy_perform(c);
    long http_status = 0;
    if (rc == CURLE_OK) curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &http_status);
    curl_easy_cleanup(c);

    if (rc != CURLE_OK || http_status < 200 || http_status >= 400
        || body.overflow || body.len == 0) {
        free(body.data);
        return (rc == CURLE_OK && body.len == 0) ? 0 : -1;
    }

    int err = 0; PCRE2_SIZE eoff = 0;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)"<Key>([^<]*)</Key>",
                                   PCRE2_ZERO_TERMINATED, 0, &err, &eoff, NULL);
    if (!re) { free(body.data); return -1; }
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    if (!md) { pcre2_code_free(re); free(body.data); return -1; }

    size_t cap = 32, n = 0;
    char **names = (char **)malloc(cap * sizeof *names);
    if (!names) { pcre2_match_data_free(md); pcre2_code_free(re); free(body.data); return -1; }

    PCRE2_SIZE offset = 0;
    while (offset < body.len) {
        int hits = pcre2_match(re, (PCRE2_SPTR)body.data, body.len, offset, 0, md, NULL);
        if (hits < 0) break;
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        PCRE2_SIZE s = ov[2], e = ov[3];
        if (s != PCRE2_UNSET && e > s) {
            size_t vlen = (size_t)(e - s);
            char *v = (char *)malloc(vlen + 1);
            if (v) {
                memcpy(v, body.data + s, vlen); v[vlen] = '\0';
                if (n == cap) {
                    char **p = (char **)realloc(names, cap * 2 * sizeof *names);
                    if (!p) { free(v); break; }
                    names = p; cap *= 2;
                }
                names[n++] = v;
            }
        }
        offset = ov[1];
        if (offset <= ov[0]) offset++;
    }

    pcre2_match_data_free(md);
    pcre2_code_free(re);
    free(body.data);
    *out_names = names;
    *out_n = n;
    return 0;
}
