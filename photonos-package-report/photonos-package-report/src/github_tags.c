/* github_tags.c — github.com tags-page release detection (M38).
 *
 * Ports the HTML special-case half of PS's github branch
 * (photonos-package-report.ps1 L 2766-2872 + L 2878-2885). See
 * pr_github_tags.h for the overview.
 */
#include "pr_github_tags.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define BODY_CAP_BYTES (32 * 1024 * 1024)   /* tags pages are ~250 KB+ */

int pr_github_is_html_tags_spec(const char *spec)
{
    if (spec == NULL) return 0;
    /* PS L 2791-2816 verbatim. */
    static const char *const list[] = {
        "apr-util.spec", "go.spec", "httpd.spec", "hwloc.spec",
        "jna.spec", "libmodulemd.spec", "libnsl.spec", "libxkbcommon.spec",
        "lmdb.spec", "logrotate.spec", "mariadb.spec", "mkinitcpio.spec",
        "npth.spec", "openjdk11.spec", "openjdk17.spec", "openjdk21.spec",
        "paho-c.spec", "python-coverage.spec", "python-decorator.spec",
        "python-hypothesis.spec", "python-networkx.spec", "python-rsa.spec",
        "python-wheel.spec", "selinux-policy.spec", NULL,
    };
    for (int i = 0; list[i]; i++)
        if (strcasecmp(spec, list[i]) == 0) return 1;
    return 0;
}

char *pr_github_tags_html_url(const char *source0)
{
    if (source0 == NULL || source0[0] == '\0') return NULL;

    /* PS L 2774-2780: strip scheme/host + /archive[/refs/tags], then the
     * first two path segments are <owner>/<repo>. */
    const char *p = source0;
    static const char *const hosts[] = {
        "https://github.com", "https://www.github.com",
        "http://github.com",  "http://www.github.com", NULL,
    };
    for (int i = 0; hosts[i]; i++) {
        size_t hl = strlen(hosts[i]);
        if (strncasecmp(p, hosts[i], hl) == 0) { p += hl; break; }
    }
    /* p now begins with "/<owner>/<repo>/...". Split segments. */
    while (*p == '/') p++;
    const char *owner_s = p;
    const char *owner_e = strchr(owner_s, '/');
    if (owner_e == NULL) return NULL;
    const char *repo_s = owner_e + 1;
    const char *repo_e = strchr(repo_s, '/');
    if (repo_e == NULL) repo_e = repo_s + strlen(repo_s);
    if (repo_e == repo_s) return NULL;

    char *url = NULL;
    if (asprintf(&url, "https://github.com/%.*s/%.*s/tags",
                 (int)(owner_e - owner_s), owner_s,
                 (int)(repo_e - repo_s), repo_s) < 0)
        url = NULL;
    return url;
}

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
        size_t newcap = b->cap ? b->cap * 2 : 262144;
        while (newcap < b->len + n) newcap *= 2;
        char *q = (char *)realloc(b->data, newcap);
        if (!q) { b->overflow = 1; return n; }
        b->data = q;
        b->cap = newcap;
    }
    memcpy(b->data + b->len, ptr, n);
    b->len += n;
    return n;
}

static pcre2_code     *RE_TAG;
static pthread_once_t  g_tag_once = PTHREAD_ONCE_INIT;

static void init_re_tag(void)
{
    int        err = 0;
    PCRE2_SIZE off = 0;
    /* Capture the leaf of an /archive/refs/tags/<leaf> href (PS L 2870). */
    RE_TAG = pcre2_compile((PCRE2_SPTR)"/archive/refs/tags/([^\"]+)",
                           PCRE2_ZERO_TERMINATED, 0, &err, &off, NULL);
    if (!RE_TAG) {
        PCRE2_UCHAR ebuf[256];
        pcre2_get_error_message(err, ebuf, sizeof ebuf);
        fprintf(stderr, "github_tags.c: re_compile failed: %s\n", (char *)ebuf);
        abort();
    }
}

/* PS L 2878-2882: drop assets whose name contains these markers. */
static int is_dropped_asset(const char *s)
{
    static const char *const drops[] = {
        ".whl", ".asc", ".dmg", ".zip", ".exe", NULL,
    };
    for (int i = 0; drops[i]; i++)
        if (strstr(s, drops[i]) != NULL) return 1;
    return 0;
}

static void strip_archive_ext(char *s)
{
    static const char *const exts[] = {
        ".tar.gz", ".tar.bz2", ".tar.xz", NULL,
    };
    for (int e = 0; exts[e]; e++) {
        size_t el = strlen(exts[e]);
        char *hit;
        while ((hit = strstr(s, exts[e])) != NULL)
            memmove(hit, hit + el, strlen(hit + el) + 1);
    }
}

int pr_github_scrape_tags_html(const char *url, char ***names_out, size_t *n_out)
{
    if (url == NULL || names_out == NULL || n_out == NULL) return -1;
    *names_out = NULL;
    *n_out = 0;

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
    long status = 0;
    if (rc == CURLE_OK) curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(c);

    if (rc != CURLE_OK || status < 200 || status >= 300 || body.overflow || body.len == 0) {
        free(body.data);
        return -1;
    }

    pthread_once(&g_tag_once, init_re_tag);
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(RE_TAG, NULL);
    if (!md) { free(body.data); return -1; }

    size_t cap = 64, n = 0;
    char **names = (char **)malloc(cap * sizeof *names);
    if (!names) { pcre2_match_data_free(md); free(body.data); return -1; }

    PCRE2_SIZE offset = 0;
    while (offset < body.len) {
        int hits = pcre2_match(RE_TAG, (PCRE2_SPTR)body.data, body.len,
                                offset, 0, md, NULL);
        if (hits < 0) break;
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        PCRE2_SIZE vs = ov[2], ve = ov[3];
        if (vs != PCRE2_UNSET && ve > vs) {
            size_t vlen = (size_t)(ve - vs);
            char *val = (char *)malloc(vlen + 1);
            if (val) {
                memcpy(val, body.data + vs, vlen);
                val[vlen] = '\0';
                if (is_dropped_asset(val)) {
                    free(val);
                } else {
                    strip_archive_ext(val);
                    /* Dedup: the page lists each tag's .tar.gz and .zip;
                     * the .zip is dropped above, but guard anyway. */
                    int dup = 0;
                    for (size_t k = 0; k < n; k++)
                        if (names[k] && strcmp(names[k], val) == 0) { dup = 1; break; }
                    if (dup) {
                        free(val);
                    } else {
                        if (n == cap) {
                            cap *= 2;
                            char **q = (char **)realloc(names, cap * sizeof *names);
                            if (!q) { free(val); break; }
                            names = q;
                        }
                        names[n++] = val;
                    }
                }
            }
        }
        offset = ov[1];
        if (offset <= ov[0]) offset++;
    }

    pcre2_match_data_free(md);
    free(body.data);

    if (n == 0) { free(names); return -1; }
    *names_out = names;
    *n_out = n;
    return 0;
}
