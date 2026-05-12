/* pr_version.h — Parse-Version + Compare-VersionStrings + Convert-ToVersion.
 *
 * 1:1 port of photonos-package-report.ps1 L 1736-1905.
 *
 * Parse-Version produces a tagged union over 6 shapes:
 *
 *   PR_VER_DATE_VERSION   "YYYYMMDD-X.Y"    -> Date int64 + VersionNumber string
 *   PR_VER_VERSION_DATE   "X.Y.YYYYMMDD"    -> Date int64 + VersionNumber string
 *   PR_VER_STANDARD       "X.Y.Z(...)"      -> int components[]
 *                         "YYYY.Q#.#"       -> int [year, quarter, patch]
 *                         "1.9.15p5"        -> int [1, 9, 15, 5]  (letter-split)
 *   PR_VER_INTEGER        "^\d+$"           -> int64 (leading zeros trimmed)
 *   PR_VER_DECIMAL        "0.91"            -> double
 *   PR_VER_STRING         fallback          -> raw string
 *
 * Compare-VersionStrings returns -1 / 0 / +1 over 8 rules; the PS rule
 * ordering and short-circuit behaviour is preserved verbatim.
 *
 * Convert-ToVersion (PS L 1888) is implemented as `pr_version_convert`
 * — it returns the components / value / raw string in a form callers
 * can dispatch on.
 */
#ifndef PR_VERSION_H
#define PR_VERSION_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    PR_VER_DATE_VERSION = 0,
    PR_VER_VERSION_DATE,
    PR_VER_STANDARD,
    PR_VER_INTEGER,
    PR_VER_DECIMAL,
    PR_VER_STRING,
} pr_version_type_t;

typedef struct {
    pr_version_type_t  type;
    /* DATE_VERSION + VERSION_DATE */
    int64_t            date;            /* YYYYMMDD */
    char              *version_number;  /* "X.Y" — heap, owned */
    /* STANDARD */
    int               *components;
    size_t             n_components;
    /* INTEGER */
    int64_t            int_value;
    /* DECIMAL */
    double             dec_value;
    /* STRING (and the raw input — kept for diagnostic output) */
    char              *str_value;       /* heap, owned */
} pr_version_t;

/* Parse `s` into *out. Returns 0 on success. *out must be zeroed by
 * the caller before the call; on success pr_version_free() releases
 * any heap-owned fields. */
int  pr_version_parse(const char *s, pr_version_t *out);
void pr_version_free(pr_version_t *v);

/* Compare two version strings. Returns:
 *    +1 if a > b
 *    -1 if a < b
 *     0 if a == b
 *    -2 on parse error (mirrors PS Write-Error + return $null path).
 */
int pr_version_compare(const char *a, const char *b);

#endif /* PR_VERSION_H */
