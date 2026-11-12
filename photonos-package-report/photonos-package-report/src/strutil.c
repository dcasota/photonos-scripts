/* strutil.c — shared string helpers.
 * See include/pr_strutil.h for semantics.
 */
#include "pr_strutil.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>  /* strcasestr */

typedef const char *(*find_fn)(const char *haystack, const char *needle);

static const char *find_cs(const char *h, const char *n) { return strstr(h, n); }
static const char *find_ci(const char *h, const char *n) { return strcasestr(h, n); }

/* Replace every non-overlapping occurrence of `a` (located by `find`) with
 * `b`. Takes ownership of `in`; on no match or allocation failure returns
 * `in` unchanged. */
static char *replace_all(char *in, const char *a, const char *b, find_fn find)
{
    if (in == NULL || a == NULL || a[0] == '\0') return in;
    size_t alen = strlen(a);
    size_t blen = b ? strlen(b) : 0;

    /* Count occurrences. */
    size_t count = 0;
    for (const char *p = in; (p = find(p, a)) != NULL; p += alen) count++;
    if (count == 0) return in;

    /* The hits do not overlap, so strlen(in) >= count * alen. */
    size_t out_len = strlen(in) - count * alen + count * blen;
    char *out = (char *)malloc(out_len + 1);
    if (!out) return in;

    /* Byte-wise copy: the output is the input with each of the `count` hits
     * resized from alen to blen, so `o` ends exactly at out + out_len. */
    char *o = out;
    const char *cur = in;
    const char *hit;
    while ((hit = find(cur, a)) != NULL) {
        while (cur < hit) *o++ = *cur++;
        for (size_t i = 0; i < blen; i++) *o++ = b[i];
        cur += alen;
    }
    while (*cur) *o++ = *cur++;
    *o = '\0';
    free(in);
    return out;
}

char *str_replace_all(char *in, const char *a, const char *b)
{
    return replace_all(in, a, b, find_cs);
}

char *istr_replace_all(char *in, const char *a, const char *b)
{
    return replace_all(in, a, b, find_ci);
}
