/* url_util.c — URL helpers.
 * Mirrors photonos-package-report.ps1 L 4716-4718.
 */
#include "pr_url_util.h"

#include <stdlib.h>
#include <string.h>

static char *xstrndup(const char *s, size_t n)
{
    char *p = (char *)malloc(n + 1);
    if (!p) return NULL;
    memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

char *pr_basename_from_url(const char *url)
{
    if (url == NULL || url[0] == '\0') return NULL;
    size_t n = strlen(url);

    /* SourceForge-style: URL ends with "/download". Return penultimate
     * segment. */
    static const char DOWNLOAD[] = "/download";
    static const size_t DLEN     = sizeof(DOWNLOAD) - 1;
    if (n > DLEN && memcmp(url + n - DLEN, DOWNLOAD, DLEN) == 0) {
        /* Skip the trailing "/download", then find the previous '/'. */
        const char *end   = url + n - DLEN;
        const char *start = end;
        while (start > url && *(start - 1) != '/') start--;
        if (start == end) {
            /* No prior segment — pathological "/download" only. */
            return xstrndup("", 0);
        }
        return xstrndup(start, (size_t)(end - start));
    }

    /* Default: last segment after the final '/'. */
    const char *last_slash = strrchr(url, '/');
    if (last_slash == NULL) {
        /* No slash anywhere — treat the whole string as the basename. */
        return xstrndup(url, n);
    }
    return xstrndup(last_slash + 1, n - (size_t)(last_slash - url) - 1);
}
