/* pr_rubygems.h — rubygems.org latest-version detection (M34).
 *
 * Mirrors photonos-package-report.ps1 L 3402-3456: when a spec's
 * Source0 points at rubygems.org, PS queries the RubyGems JSON API
 *   https://rubygems.org/api/v1/versions/<gem_name>.json
 * which returns an array of version objects sorted newest-first.
 * It filters out `"prerelease":true` entries and takes the first
 * remaining `"number"`.
 *
 * The C port parses the JSON with PCRE2 (no json-c link dependency,
 * matching the manual-parse precedent in koji.c). The RubyGems schema
 * places `"number":"X"` before `"prerelease":(true|false)` within each
 * version object with no nested object between them, so a non-greedy
 * `"number":"([^"]+)".*?"prerelease":(true|false)` pairs them safely.
 */
#ifndef PR_RUBYGEMS_H
#define PR_RUBYGEMS_H

/* GET the RubyGems versions API for `gem_name` and return the newest
 * NON-prerelease version string (malloc'd, caller frees), or NULL on
 * transport/parse failure or when no stable version exists. */
char *pr_rubygems_latest_version(const char *gem_name);

#endif /* PR_RUBYGEMS_H */
