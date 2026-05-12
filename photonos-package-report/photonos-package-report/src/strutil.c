/* strutil.c — shared string helpers.
 * See include/pr_strutil.h for semantics.
 */
#include "pr_strutil.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>  /* strcasestr */

char *str_replace_all(char *in, const char *a, const char *b)
{
    if (in == NULL || a == NULL || a[0] == '\0') return in;
    size_t alen = strlen(a);
    size_t blen = b ? strlen(b) : 0;

    /* Count occurrences. */
    size_t count = 0;
    for (const char *p = in; (p = strstr(p, a)) != NULL; p += alen) count++;
    if (count == 0) return in;

    size_t in_len  = strlen(in);
    size_t out_len = in_len + count * (blen > alen ? blen - alen : 0)
                            - count * (alen > blen ? alen - blen : 0);
    char *out = (char *)malloc(out_len + 1);
    if (!out) return in;

    char *o = out;
    const char *cur = in;
    for (;;) {
        const char *hit = strstr(cur, a);
        if (!hit) {
            size_t tail = strlen(cur);
            memcpy(o, cur, tail);
            o += tail;
            break;
        }
        memcpy(o, cur, (size_t)(hit - cur));
        o += hit - cur;
        if (blen) { memcpy(o, b, blen); o += blen; }
        cur = hit + alen;
    }
    *o = '\0';
    free(in);
    return out;
}

char *istr_replace_all(char *in, const char *a, const char *b)
{
    if (in == NULL || a == NULL || a[0] == '\0') return in;
    size_t alen = strlen(a);
    size_t blen = b ? strlen(b) : 0;

    /* Count occurrences case-insensitively. */
    size_t count = 0;
    for (const char *p = in; (p = strcasestr(p, a)) != NULL; p += alen) count++;
    if (count == 0) return in;

    size_t in_len  = strlen(in);
    size_t out_len = in_len + count * (blen > alen ? blen - alen : 0)
                            - count * (alen > blen ? alen - blen : 0);
    char *out = (char *)malloc(out_len + 1);
    if (!out) return in;

    char *o = out;
    const char *cur = in;
    for (;;) {
        const char *hit = strcasestr(cur, a);
        if (!hit) {
            size_t tail = strlen(cur);
            memcpy(o, cur, tail);
            o += tail;
            break;
        }
        memcpy(o, cur, (size_t)(hit - cur));
        o += hit - cur;
        if (blen) { memcpy(o, b, blen); o += blen; }
        cur = hit + alen;
    }
    *o = '\0';
    free(in);
    return out;
}
