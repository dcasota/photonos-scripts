/* atom_feed.c — Atom-feed tag-list scraper (FRD-019).
 *
 * One-shot libcurl GET + PCRE2 extraction of <entry><title>...</title>
 * values. Used by CheckURLHealth's non-git update-detection path when
 * the per-spec SourceTagURL override points at an atom feed (typically
 * `gitlab.freedesktop.org/.../-/tags?format=atom` or the gitlab.com
 * equivalent).
 *
 * Mirrors PS pattern `Invoke-RestMethod -uri ... | foreach name`
 * which atom-parses transparently. PS L 3784 dispatch site.
 */
#include "pr_atom_feed.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BODY_CAP_BYTES (4 * 1024 * 1024)   /* 4 MiB atom feeds */

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

/* Decode the 5 standard XML entities in-place. The output is always
 * <= input length, so memmove-style left-shift is safe.
 *   &amp;   → &
 *   &lt;    → <
 *   &gt;    → >
 *   &quot;  → "
 *   &apos;  → '
 */
static void decode_xml_entities(char *s)
{
    if (s == NULL) return;
    char *w = s;
    char *r = s;
    while (*r) {
        if (*r == '&') {
            if (strncmp(r, "&amp;",  5) == 0) { *w++ = '&';  r += 5; continue; }
            if (strncmp(r, "&lt;",   4) == 0) { *w++ = '<';  r += 4; continue; }
            if (strncmp(r, "&gt;",   4) == 0) { *w++ = '>';  r += 4; continue; }
            if (strncmp(r, "&quot;", 6) == 0) { *w++ = '"';  r += 6; continue; }
            if (strncmp(r, "&apos;", 6) == 0) { *w++ = '\''; r += 6; continue; }
        }
        *w++ = *r++;
    }
    *w = '\0';
}

/* Compile once per process. Pattern matches the inner `<title>X</title>`
 * of each `<entry>...</entry>` block. The feed-level `<title>` (outside
 * any `<entry>`) is excluded by anchoring with `<entry`. */
static pcre2_code *g_entry_title_re = NULL;

static pcre2_code *compile_entry_title_re(void)
{
    if (g_entry_title_re) return g_entry_title_re;
    /* Match an opening <entry...> through to the first nested
     * <title>VALUE</title>. PCRE2_DOTALL so . matches newlines. */
    PCRE2_SPTR pattern = (PCRE2_SPTR)"<entry[^>]*>[^<]*(?:<(?!title)[^>]*>[^<]*(?:</[^>]+>[^<]*)*)*<title[^>]*>([^<]*)</title>";
    int errornumber = 0;
    PCRE2_SIZE erroroffset = 0;
    pcre2_code *re = pcre2_compile(pattern, PCRE2_ZERO_TERMINATED,
                                    PCRE2_CASELESS | PCRE2_DOTALL,
                                    &errornumber, &erroroffset, NULL);
    if (re == NULL) {
        PCRE2_UCHAR ebuf[256];
        pcre2_get_error_message(errornumber, ebuf, sizeof ebuf);
        fprintf(stderr, "pr_atom_feed: entry-title re_compile failed at offset %zu: %s\n",
                (size_t)erroroffset, (char *)ebuf);
        return NULL;
    }
    g_entry_title_re = re;
    return re;
}

int pr_scrape_atom_feed(const char *url, char ***out_names, size_t *out_n)
{
    if (out_names == NULL || out_n == NULL) return -1;
    *out_names = NULL;
    *out_n = 0;
    if (url == NULL || *url == '\0') return -1;

    struct body_buf body = {0};
    CURL *c = curl_easy_init();
    if (!c) return -1;

    curl_easy_setopt(c, CURLOPT_URL,            url);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     20000L);
    /* gitlab.freedesktop.org's bot detection triggers on Chrome-style
     * user agents and returns an HTML challenge page instead of the
     * atom feed. PS's `Invoke-RestMethod` default UA carries
     * "PowerShell" / "WindowsPowerShell" and is whitelisted.
     * Empirically tested with `curl -A "PowerShell" ...` returns the
     * proper atom XML where Chrome UA returns the challenge page.
     *
     * Using a PowerShell-style UA here matches PS behaviour and
     * avoids the bot challenge for gitlab.freedesktop.org and
     * gitlab.com. Other hosts in the per-spec URL table
     * (gitlab.gnome.org) accept both UAs. */
    curl_easy_setopt(c, CURLOPT_USERAGENT,
        "Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) "
        "WindowsPowerShell/5.1.19041.5072");
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, body_write_cb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA,     &body);
    curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");

    struct curl_slist *hdrs = NULL;
    hdrs = curl_slist_append(hdrs, "Accept: application/atom+xml,application/xml,text/xml,*/*;q=0.5");
    hdrs = curl_slist_append(hdrs, "Accept-Language: en-US,en;q=0.9");
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
        fprintf(stderr, "pr_atom_feed: body too large for %s (cap %d MiB)\n",
                url, BODY_CAP_BYTES / (1024 * 1024));
        free(body.data);
        return -1;
    }
    if (body.len == 0) {
        free(body.data);
        return 0;
    }

    pcre2_code *re = compile_entry_title_re();
    if (re == NULL) { free(body.data); return -1; }

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
        PCRE2_SIZE start = ovec[2], end = ovec[3];
        if (start != PCRE2_UNSET && end > start) {
            size_t vlen = (size_t)(end - start);
            char *v = (char *)malloc(vlen + 1);
            if (v) {
                memcpy(v, body.data + start, vlen);
                v[vlen] = '\0';
                decode_xml_entities(v);
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
