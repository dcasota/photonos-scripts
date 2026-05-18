/* stable_source.c — stable-source URL resolver (ADR-0015 Option A).
 *
 * For GitHub auto-archive URLs of the form
 *   https://github.com/<org>/<proj>/archive/refs/tags/<tag>.tar.gz
 * probe candidate release-asset URLs and return the first that
 * responds 200. The auto-archive is regenerated on demand, so its
 * SHA drifts. Release-assets are immutable.
 *
 * Per-host allowlist starts at github.com only.
 *
 * Public API:
 *   pr_resolve_stable_source_url(spec, latest_tag, current_url)
 *     -> char* (malloc'd) on success; NULL on no-match or any failure.
 *
 * The function is called by `check_urlhealth.c` just before SHA
 * computation. Failure modes are silent — fall through to the
 * caller's existing URL.
 */
#include "pr_stable_source.h"

#include <curl/curl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* libcurl HEAD probe — returns the HTTP status or 0 on transport
 * failure. Follows redirects (release-asset URLs often 302 to the
 * CDN). Body is discarded. */
static long head_status(const char *url)
{
    CURL *c = curl_easy_init();
    if (!c) return 0;
    curl_easy_setopt(c, CURLOPT_URL, url);
    curl_easy_setopt(c, CURLOPT_NOBODY, 1L);
    curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(c, CURLOPT_TIMEOUT_MS, 10000L);
    curl_easy_setopt(c, CURLOPT_USERAGENT,
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36");
    long status = 0;
    CURLcode rc = curl_easy_perform(c);
    if (rc == CURLE_OK) {
        curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
    }
    curl_easy_cleanup(c);
    return status;
}

/* Extract `org/proj` and `tag` from a GitHub auto-archive URL.
 * Pattern: https://github.com/<org>/<proj>/archive/refs/tags/<tag>.tar.gz
 * (or .tar.xz, .tar.bz2, .tar.lz, .tgz, .zip).
 *
 * On success fills *org_proj_out and *tag_out with malloc'd strings
 * and returns 0. On no-match returns -1; caller treats as "not a
 * github auto-archive". */
static int parse_github_auto_archive(const char *url,
                                     char **org_proj_out,
                                     char **tag_out)
{
    if (url == NULL) return -1;
    const char *prefix = "https://github.com/";
    if (strncmp(url, prefix, strlen(prefix)) != 0) return -1;

    const char *after = url + strlen(prefix);
    const char *archive = strstr(after, "/archive/refs/tags/");
    if (archive == NULL) return -1;

    /* org/proj is the slice [after, archive). */
    size_t op_len = (size_t)(archive - after);
    if (op_len == 0) return -1;

    /* Tag is the rest after "/archive/refs/tags/" minus the extension. */
    const char *tag_start = archive + strlen("/archive/refs/tags/");
    if (*tag_start == '\0') return -1;

    /* Strip known archive extensions from the end. */
    static const char *exts[] = {
        ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.lz", ".tgz", ".zip", NULL,
    };
    size_t tag_len = strlen(tag_start);
    for (int i = 0; exts[i]; i++) {
        size_t el = strlen(exts[i]);
        if (tag_len >= el
            && strcasecmp(tag_start + tag_len - el, exts[i]) == 0) {
            tag_len -= el;
            break;
        }
    }
    if (tag_len == 0) return -1;

    char *op = (char *)malloc(op_len + 1);
    char *tg = (char *)malloc(tag_len + 1);
    if (op == NULL || tg == NULL) { free(op); free(tg); return -1; }
    memcpy(op, after, op_len);  op[op_len] = '\0';
    memcpy(tg, tag_start, tag_len); tg[tag_len] = '\0';

    *org_proj_out = op;
    *tag_out      = tg;
    return 0;
}

/* Strip the trailing ".spec" from spec_name to produce a project-like
 * candidate (e.g. "abseil-cpp.spec" → "abseil-cpp"). Returns malloc'd
 * string or NULL. */
static char *spec_to_proj(const char *spec_name)
{
    if (spec_name == NULL) return NULL;
    size_t n = strlen(spec_name);
    size_t suf = strlen(".spec");
    if (n > suf && strcasecmp(spec_name + n - suf, ".spec") == 0) {
        n -= suf;
    }
    char *out = (char *)malloc(n + 1);
    if (out == NULL) return NULL;
    memcpy(out, spec_name, n);
    out[n] = '\0';
    return out;
}

char *pr_resolve_stable_source_url(const char *spec_name,
                                   const char *latest_tag,
                                   const char *current_url)
{
    (void)latest_tag;  /* Not yet used — tag is extracted from current_url
                        * since the tag in the URL is what got SHA'd. */

    char *org_proj = NULL;
    char *tag      = NULL;
    if (parse_github_auto_archive(current_url, &org_proj, &tag) != 0) {
        return NULL;
    }

    char *proj_from_spec = spec_to_proj(spec_name);

    /* Candidate release-asset URL patterns, in order of likelihood:
     *   1. releases/download/<tag>/<spec_proj>-<tag>.tar.gz
     *   2. releases/download/<tag>/<tag>.tar.gz
     *   3. releases/download/<tag>/<spec_proj>-<tag>.tar.xz
     *   4. releases/download/<tag>/<spec_proj>-<tag>.tar.bz2
     *   5. releases/download/<tag>/<spec_proj>-<tag>.tgz
     *
     * The github-repo project name (org_proj's second segment) is
     * also a candidate, but the spec's own name is more reliable for
     * Photon's mapping (the spec often re-names a repo for clarity,
     * e.g. `abseil-cpp.spec` for the github repo `abseil/abseil-cpp`).
     * Try spec-name first; if it differs from the github-proj name,
     * also try the github-proj name. */
    const char *github_proj = strchr(org_proj, '/');
    github_proj = github_proj ? github_proj + 1 : NULL;

    const char *proj_candidates[3] = {NULL, NULL, NULL};
    int nproj = 0;
    if (proj_from_spec != NULL && proj_from_spec[0] != '\0') {
        proj_candidates[nproj++] = proj_from_spec;
    }
    if (github_proj != NULL && github_proj[0] != '\0') {
        int dup = 0;
        for (int i = 0; i < nproj; i++) {
            if (strcasecmp(proj_candidates[i], github_proj) == 0) {
                dup = 1; break;
            }
        }
        if (!dup) proj_candidates[nproj++] = github_proj;
    }

    static const char *exts[] = {
        ".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", NULL,
    };

    char *result = NULL;
    /* First try `<tag>.tar.gz` (no project prefix). */
    {
        char *url = NULL;
        if (asprintf(&url,
                     "https://github.com/%s/releases/download/%s/%s.tar.gz",
                     org_proj, tag, tag) >= 0) {
            if (head_status(url) == 200) {
                result = url;
            } else {
                free(url);
            }
        }
    }
    /* Then try `<proj>-<tag><ext>` for each (proj, ext) pair. */
    for (int p = 0; result == NULL && p < nproj; p++) {
        for (int e = 0; result == NULL && exts[e]; e++) {
            char *url = NULL;
            if (asprintf(&url,
                         "https://github.com/%s/releases/download/%s/%s-%s%s",
                         org_proj, tag, proj_candidates[p], tag,
                         exts[e]) >= 0) {
                if (head_status(url) == 200) {
                    result = url;
                } else {
                    free(url);
                }
            }
        }
    }

    free(org_proj);
    free(tag);
    free(proj_from_spec);
    return result;
}
