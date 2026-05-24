/* gnome_cache.c — gnome download-server version enumeration (cat-6 cluster B).
 *
 * The classic gnome FTP layout (ftp.gnome.org/.../sources/<module>/<M.N>/
 * <module>-<ver>.tar.*) defeats the generic listing scraper: dirname(Source0)
 * points at one minor-version dir (only the current release's files), and the
 * version-bearing parent index lists bare "M.N/" dirs (no patch level). The
 * gnome download server instead publishes a machine-readable index:
 *
 *   GET https://download.gnome.org/sources/<module>/cache.json
 *     -> [ 4, {<module>:{<ver>:{...}}}, {<module>:[<ver>,...]}, {...} ]
 *
 * Element [2] maps each module to a flat array of every released version. We
 * GET it and return that array; the standard version pipeline then picks the
 * latest and compares. Element [1] is "<module>":{...} (object), so matching
 * `"<module>" : [` selects the element-[2] array unambiguously.
 *
 * Parsed with PCRE2 (no json-c dependency), consistent with rubygems.c.
 */
#include "pr_gnome_cache.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BODY_CAP_BYTES (16 * 1024 * 1024)

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

/* Append a heap copy of [s, s+len) to a growable name list. */
static int push_name(char ***names, size_t *n, size_t *cap,
                     const char *s, size_t len)
{
    if (*n == *cap) {
        size_t nc = *cap ? *cap * 2 : 32;
        char **p = (char **)realloc(*names, nc * sizeof *p);
        if (!p) return -1;
        *names = p; *cap = nc;
    }
    char *v = (char *)malloc(len + 1);
    if (!v) return -1;
    memcpy(v, s, len);
    v[len] = '\0';
    (*names)[(*n)++] = v;
    return 0;
}

int pr_gnome_cache_versions(const char *module, char ***out_names, size_t *out_n)
{
    if (out_names) *out_names = NULL;
    if (out_n)     *out_n     = 0;
    if (module == NULL || module[0] == '\0' || out_names == NULL || out_n == NULL)
        return -1;

    char *url = NULL;
    if (asprintf(&url, "https://download.gnome.org/sources/%s/cache.json", module) < 0)
        return -1;

    struct body_buf body = {0};
    CURL *c = curl_easy_init();
    if (!c) { free(url); return -1; }
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

    if (rc != CURLE_OK || status < 200 || status >= 300
        || body.overflow || body.len == 0) {
        free(body.data);
        return -1;
    }

    /* Build  "<module>"\s*:\s*\[([^\]]*)\]  with the module name quoted
     * literally (\Q..\E) so regex metacharacters in it are inert. */
    char *pat = NULL;
    if (asprintf(&pat, "\"\\Q%s\\E\"\\s*:\\s*\\[([^\\]]*)\\]", module) < 0) {
        free(body.data);
        return -1;
    }
    int        err = 0;
    PCRE2_SIZE off = 0;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED,
                                   PCRE2_DOTALL, &err, &off, NULL);
    free(pat);
    if (!re) { free(body.data); return -1; }

    char **names = NULL;
    size_t n = 0, cap = 0;
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    if (md && pcre2_match(re, (PCRE2_SPTR)body.data, body.len, 0, 0, md, NULL) >= 0) {
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        PCRE2_SIZE as = ov[2], ae = ov[3];   /* array-body capture */
        if (as != PCRE2_UNSET && ae != PCRE2_UNSET) {
            /* Extract each "..." string inside the array slice. */
            const char *p = body.data + as;
            const char *end = body.data + ae;
            while (p < end) {
                const char *q1 = memchr(p, '"', (size_t)(end - p));
                if (!q1) break;
                q1++;
                const char *q2 = memchr(q1, '"', (size_t)(end - q1));
                if (!q2) break;
                if (q2 > q1) {
                    if (push_name(&names, &n, &cap, q1, (size_t)(q2 - q1)) != 0)
                        break;
                }
                p = q2 + 1;
            }
        }
    }
    if (md) pcre2_match_data_free(md);
    pcre2_code_free(re);
    free(body.data);

    if (n == 0) { free(names); return -1; }
    *out_names = names;
    *out_n     = n;
    return 0;
}
