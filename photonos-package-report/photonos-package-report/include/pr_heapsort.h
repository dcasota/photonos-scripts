/* pr_heapsort.h — Doug-Finke heapsort with ASCII-byte concat comparator.
 *
 * Mirrors photonos-package-report.ps1 L 1576-1641 — a max-heapsort over
 * an array of strings where the comparator is:
 *
 *   key(s) := int64( concat( for b in bytes(s): format(b, "000") ) )
 *
 * Example: "abc" → "097098099" → 97098099 (fits in int64).
 *
 * For ASCII-only strings the resulting key has the same ordering as
 * strcmp (lexicographic), so HeapSort behaves like a lex sort for short
 * inputs. For inputs longer than 6 bytes the int64 conversion overflows
 * (1000^7 = 1e21 > 9.2e18); PS throws OverflowException on hit, the C
 * port silently truncates because `int64_t` C wraps. This quirk is
 * preserved per CLAUDE.md invariant #2 — the only PS call site
 * (PS L 4252 for docbook-xml.spec) feeds short fragment strings so
 * overflow is unreachable in practice.
 *
 * Mutates the input array in place. Returns 0 on success, -1 on alloc
 * failure. After return the array is sorted ascending by the key,
 * so the last element is the maximum.
 */
#ifndef PR_HEAPSORT_H
#define PR_HEAPSORT_H

#include <stddef.h>

int pr_heapsort_strings(char **arr, size_t n);

#endif /* PR_HEAPSORT_H */
