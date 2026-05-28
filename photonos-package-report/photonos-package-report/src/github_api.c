/* github_api.c — github.com tag/release detection via the JSON API.
 *
 * Ports the general (non-HTML-special-case) half of PS's github branch
 * (photonos-package-report.ps1 L 2786-2849). See pr_github_api.h.
 *
 * libcurl + PCRE2 (no json-c), same approach as pypi.c / rubygems.c.
 */
#include "pr_github_api.h"

#include <curl/curl.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define BODY_CAP_BYTES (32 * 1024 * 1024)

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

int pr_github_api_eligible_source0(const char *source0)
{
    if (source0 == NULL || source0[0] == '\0') return 0;
    if (strcasestr(source0, "github.com") == NULL) return 0;
    return (strstr(source0, "/archive/") != NULL
            || strstr(source0, "/releases/download/") != NULL);
}

/* Strip scheme/host + /archive[/refs/tags] (PS L2794-2800), then split: the
 * first two path segments are <owner>/<repo>. Caller frees both outputs. */
static int derive_owner_repo(const char *source0, char **owner, char **repo)
{
    *owner = NULL; *repo = NULL;
    const char *p = source0;
    static const char *const hosts[] = {
        "https://github.com", "https://www.github.com",
        "http://github.com",  "http://www.github.com", NULL,
    };
    for (int i = 0; hosts[i]; i++) {
        size_t hl = strlen(hosts[i]);
        if (strncasecmp(p, hosts[i], hl) == 0) { p += hl; break; }
    }
    while (*p == '/') p++;
    const char *o_s = p;
    const char *o_e = strchr(o_s, '/');
    if (o_e == NULL) return -1;
    const char *r_s = o_e + 1;
    const char *r_e = strchr(r_s, '/');
    size_t r_len = r_e ? (size_t)(r_e - r_s) : strlen(r_s);
    if (o_e == o_s || r_len == 0) return -1;
    *owner = strndup(o_s, (size_t)(o_e - o_s));
    *repo  = strndup(r_s, r_len);
    if (!*owner || !*repo) { free(*owner); free(*repo); *owner = *repo = NULL; return -1; }
    return 0;
}

static pcre2_code *RE_NAME, *RE_TAGNAME;
static pthread_once_t g_once = PTHREAD_ONCE_INIT;

static pcre2_code *compile(const char *pat)
{
    int err = 0; PCRE2_SIZE off = 0;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pat, PCRE2_ZERO_TERMINATED,
                                   0, &err, &off, NULL);
    if (!re) { fprintf(stderr, "github_api.c: compile('%s') failed\n", pat); abort(); }
    return re;
}

static void init_re(void)
{
    RE_NAME    = compile("\"name\"\\s*:\\s*\"([^\"]*)\"");
    RE_TAGNAME = compile("\"tag_name\"\\s*:\\s*\"([^\"]*)\"");
}

/* Collect every capture-group-1 match of `re` in `body` into the names array. */
static void collect_all(pcre2_code *re, const char *body, size_t len,
                        char ***names, size_t *n, size_t *cap)
{
    pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
    if (!md) return;
    PCRE2_SIZE off = 0;
    while (off <= len) {
        int rc = pcre2_match(re, (PCRE2_SPTR)body, len, off, 0, md, NULL);
        if (rc < 0) break;
        PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        if (rc >= 2 && ov[2] != PCRE2_UNSET && ov[3] >= ov[2]) {
            size_t l = (size_t)(ov[3] - ov[2]);
            char *s = (char *)malloc(l + 1);
            if (s) {
                memcpy(s, body + ov[2], l); s[l] = '\0';
                if (*n >= *cap) {
                    size_t nc = *cap ? *cap * 2 : 32;
                    char **p = (char **)realloc(*names, nc * sizeof(char *));
                    if (!p) { free(s); break; }
                    *names = p; *cap = nc;
                }
                (*names)[(*n)++] = s;
            }
        }
        PCRE2_SIZE next = ov[1];
        off = (next > off) ? next : off + 1;
    }
    pcre2_match_data_free(md);
}

int pr_github_api_names(const char *source0, const char *token,
                        char ***names_out, size_t *n_out)
{
    *names_out = NULL; *n_out = 0;
    if (!pr_github_api_eligible_source0(source0)) return -1;

    char *owner = NULL, *repo = NULL;
    if (derive_owner_repo(source0, &owner, &repo) != 0) return -1;

    /* PS L2803-2807: /archive/ -> /tags ; /releases/download/ -> /releases. */
    int is_releases = (strstr(source0, "/releases/download/") != NULL)
                      && (strstr(source0, "/archive/") == NULL);

    pthread_once(&g_once, init_re);

    /* M110: paginate ONLY for repos where the single-page (default ~30
     * entries) fetch misses the proper semver tags. Full-validation run
     * 26600507754 found 2 strict regressions when paginating globally
     * (libsepol 3.10→20200710, python3-hatchling empty→Warning) because
     * pagination uncovers buried date-form tags that win the version compare
     * over a semver currently in the first page — yet PS keeps the semver
     * (PS doesn't paginate by default). Restrict pagination to an explicit
     * allowlist of (owner, repo) pairs proven to need it; everyone else
     * uses the original single-page behaviour (max_pages=1). Add to the
     * allowlist when a future investigation shows a repo's semver tag is
     * beyond page 1 AND PS sees it. */
    static const struct { const char *owner; const char *repo; } paginate_allow[] = {
        {"fedora-sysv", "chkconfig"},   /* alternatives.spec — 1.33 at idx 161 */
    };
    int max_pages = 1;
    for (size_t i = 0; i < sizeof paginate_allow / sizeof paginate_allow[0]; i++) {
        if (strcasecmp(paginate_allow[i].owner, owner) == 0
            && strcasecmp(paginate_allow[i].repo,  repo)  == 0) {
            max_pages = 20;    /* 20 pages × 100 = 2 000 tags safety bound */
            break;
        }
    }

    char **names = NULL; size_t n = 0, cap = 0;
    int   ok    = 0;

    int paginate = (max_pages > 1);
    for (int page = 1; page <= max_pages; page++) {
        char *api = NULL;
        /* Non-allowlisted repos use the original URL (no query) for
         * byte-identical pre-M110 behaviour. Allowlisted repos use
         * ?per_page=100&page=N. */
        int rc_a;
        if (paginate) {
            rc_a = asprintf(&api,
                            "https://api.github.com/repos/%s/%s/%s?per_page=100&page=%d",
                            owner, repo, is_releases ? "releases" : "tags", page);
        } else {
            rc_a = asprintf(&api,
                            "https://api.github.com/repos/%s/%s/%s",
                            owner, repo, is_releases ? "releases" : "tags");
        }
        if (rc_a < 0) {
            break;
        }
        struct body_buf body = {0};
        CURL *c = curl_easy_init();
        if (!c) { free(api); break; }
        struct curl_slist *hdr = NULL;
        hdr = curl_slist_append(hdr, "Accept: application/vnd.github.v3+json");
        char *auth = NULL;
        if (token && token[0]) {
            if (asprintf(&auth, "Authorization: Bearer %s", token) >= 0)
                hdr = curl_slist_append(hdr, auth);
        }
        curl_easy_setopt(c, CURLOPT_URL,            api);
        curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(c, CURLOPT_TIMEOUT_MS,     20000L);
        curl_easy_setopt(c, CURLOPT_USERAGENT,      "photonos-package-report/C");
        curl_easy_setopt(c, CURLOPT_HTTPHEADER,     hdr);
        curl_easy_setopt(c, CURLOPT_WRITEFUNCTION,  body_write_cb);
        curl_easy_setopt(c, CURLOPT_WRITEDATA,      &body);
        curl_easy_setopt(c, CURLOPT_ACCEPT_ENCODING, "");
        CURLcode rc = curl_easy_perform(c);
        long status = 0;
        if (rc == CURLE_OK) curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
        curl_easy_cleanup(c);
        curl_slist_free_all(hdr);
        free(auth);
        free(api);

        if (rc != CURLE_OK || status < 200 || status >= 300 || body.overflow || body.len == 0) {
            free(body.data);
            if (page == 1) goto done;   /* preserve the prior failure return */
            break;
        }

        size_t before = n;
        if (is_releases) {
            /* PS L2846: releases -> .tag_name; L2847-2849 fallback to .name. */
            collect_all(RE_TAGNAME, body.data, body.len, &names, &n, &cap);
            if (n == before)
                collect_all(RE_NAME, body.data, body.len, &names, &n, &cap);
        } else {
            collect_all(RE_NAME, body.data, body.len, &names, &n, &cap);
        }
        free(body.data);

        size_t added = n - before;
        ok = 1;
        /* A partial page means no more pages follow. An empty array on a
         * non-first page is also the end. */
        if (added < 100) break;
    }

done:
    free(owner); free(repo);
    *names_out = names; *n_out = n;
    return ok ? 0 : -1;
}
