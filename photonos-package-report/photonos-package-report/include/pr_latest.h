/* pr_latest.h — Get-LatestName port.
 *
 * Mirrors photonos-package-report.ps1 L 1907-1949.
 *
 * Given a list of candidate names (typically the output of `git tag -l`
 * trimmed and filtered), return the "latest". PS rules:
 *   1. Filter out NULL / empty / whitespace-only entries.
 *   2. If any entry matches the version-number pattern
 *        ^\d+([.-]Q?\d+)*$
 *      (e.g. "1.2", "1-2", "2024.Q1.7"), select the version-like
 *      entries and bubble-search-by-pr_version_compare for the max.
 *   3. Otherwise, sort all entries lexicographically (C locale,
 *      strcmp ascending) and return the LAST one.
 *
 * Returns a malloc'd NUL-terminated string the caller frees. Returns
 * an empty malloc'd string "" when input has no usable entries.
 */
#ifndef PR_LATEST_H
#define PR_LATEST_H

#include <stddef.h>

char *pr_get_latest_name(char **names, size_t n);

#endif /* PR_LATEST_H */
