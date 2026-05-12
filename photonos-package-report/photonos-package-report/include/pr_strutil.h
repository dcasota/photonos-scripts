/* pr_strutil.h — small string helpers shared across the C port.
 *
 * The PS script leans heavily on three string idioms:
 *   - `[string].Replace(a, b)`            : case-SENSITIVE literal replace
 *   - `$s -ireplace pattern, replacement` : case-INSENSITIVE regex replace
 *   - `$s -ilike '*needle*'`              : case-INSENSITIVE substring test
 *
 * For PS patterns that are always literal tokens (e.g. `%{url}`,
 * `%{?dist}`, `%{name}`, the 15 secondary tokens), full regex is
 * unnecessary — they translate to plain case-sensitive or case-
 * insensitive literal replacement. Where the PS author exploited regex
 * meta-characters (anchors, character classes, captures), we reach for
 * PCRE2 via Get-SpecValue / dedicated callsites.
 *
 * Both functions below take ownership of `in` (free it), allocate a new
 * heap string, and return it. They never return NULL on success.
 * On allocation failure they leave `in` untouched and return NULL.
 */
#ifndef PR_STRUTIL_H
#define PR_STRUTIL_H

#include <stddef.h>

/* PS [string]::Replace(a, b) — case-SENSITIVE literal replace of every
 * non-overlapping occurrence of `a` with `b`. Used by ParseDirectory at
 * PS L 270-275 to strip release-modifier tokens like `%{?dist}`. */
char *str_replace_all(char *in, const char *a, const char *b);

/* PS -ireplace LITERAL, replacement — case-INSENSITIVE literal replace
 * of every non-overlapping occurrence of `a` with `b`. The PS operator
 * is regex-aware, but the substitutions we port at PS L 2172-2199 use
 * static `%{token}` patterns where the only regex meta-characters
 * (`{`, `}`, `%`) have no quantifier semantics. Treating them as
 * literals yields the same bytes as -ireplace would. */
char *istr_replace_all(char *in, const char *a, const char *b);

#endif /* PR_STRUTIL_H */
