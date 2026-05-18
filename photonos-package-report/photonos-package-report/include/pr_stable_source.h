/* pr_stable_source.h — stable-source URL resolver (ADR-0015 Option A).
 *
 * When `current_url` is a GitHub auto-archive URL like
 *   https://github.com/<org>/<proj>/archive/refs/tags/<tag>.tar.gz
 * GitHub regenerates the tarball on demand and its SHA drifts.
 * Maintainers who publish release-assets upload a stable tarball
 * available at
 *   https://github.com/<org>/<proj>/releases/download/<tag>/<asset>
 * whose SHA is fixed forever (until the asset is deleted).
 *
 * This resolver probes the common release-asset URL variants via HEAD
 * and returns the first one that responds 200. The caller uses the
 * returned URL for SHA computation; col 6 (UpdateURL) stays unchanged.
 *
 * Per-host allowlist starts with github.com only. Non-github URLs
 * return NULL and the caller falls back to `current_url`.
 *
 * Returns a malloc'd URL string on success, NULL on no match or on
 * any transport/parse failure. Caller owns the result.
 */
#ifndef PR_STABLE_SOURCE_H
#define PR_STABLE_SOURCE_H

char *pr_resolve_stable_source_url(const char *spec_name,
                                   const char *latest_tag,
                                   const char *current_url);

#endif /* PR_STABLE_SOURCE_H */
