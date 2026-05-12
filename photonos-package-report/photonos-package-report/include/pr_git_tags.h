/* pr_git_tags.h — `git tag -l` output parser.
 *
 * Mirrors the parsing chain at photonos-package-report.ps1 L 2441-2444:
 *
 *     $tagLines = @($tagOutput -split "`r?`n"
 *                   | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
 *     if (!([string]::IsNullOrEmpty($customRegex))) {
 *         $Names = @($tagLines | Where-Object { $_ -match $customRegex }
 *                              | ForEach-Object { $_.Trim() })
 *     } else {
 *         $Names = @($tagLines | ForEach-Object { $_.Trim() })
 *     }
 *
 * The runtime call that produces $tagOutput (Invoke-GitWithTimeout
 * "tag -l") lives in Phase 6d when we wire local-clone management
 * into the orchestrator. This module exposes only the deterministic
 * post-processing so it can be unit-tested without git.
 */
#ifndef PR_GIT_TAGS_H
#define PR_GIT_TAGS_H

#include <stddef.h>

/* Parse `git tag -l` stdout into a heap array of trimmed, non-empty
 * tag basenames. If `custom_regex` is non-NULL and non-empty, only
 * lines matching the regex (case-sensitive, PCRE2) are kept.
 *
 * Sets *out_names to a malloc'd array of malloc'd strings and *out_n
 * to its length. Caller frees with pr_git_tags_free().
 *
 * Returns 0 on success, -1 on memory failure, -2 on regex compile
 * failure.
 */
int  pr_parse_tag_list(const char *git_output,
                       const char *custom_regex,
                       char     ***out_names,
                       size_t     *out_n);

void pr_git_tags_free(char **names, size_t n);

#endif /* PR_GIT_TAGS_H */
