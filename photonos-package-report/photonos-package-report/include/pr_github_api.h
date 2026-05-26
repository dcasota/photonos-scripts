/* pr_github_api.h — github.com tag/release detection via the JSON API.
 *
 * PS photonos-package-report.ps1 L 2786-2849: for ANY Source0 on github.com
 * that has no explicit lookup gitSource (and is not one of the curated HTML
 * tags-page specs handled by pr_github_tags.h), PS derives <owner>/<repo> from
 * the Source0 URL and queries the github JSON API:
 *   Source0 contains "/archive/"           -> /repos/<o>/<r>/tags     (.name)
 *   Source0 contains "/releases/download/" -> /repos/<o>/<r>/releases  (.tag_name)
 * The collected tag names then feed the standard version pipeline.
 */
#ifndef PR_GITHUB_API_H
#define PR_GITHUB_API_H

#include <stddef.h>

/* True when `source0` is a github.com URL whose tag/release list can be
 * derived via the JSON API (contains "/archive/" or "/releases/download/"). */
int pr_github_api_eligible_source0(const char *source0);

/* Derive <owner>/<repo> + endpoint from `source0`, GET the github JSON API
 * (Bearer `token` when non-NULL/empty), and return the tag names (heap array,
 * caller frees each + the array). Returns 0 on success (even if 0 names), -1
 * on error. */
int pr_github_api_names(const char *source0, const char *token,
                        char ***names_out, size_t *n_out);

#endif /* PR_GITHUB_API_H */
