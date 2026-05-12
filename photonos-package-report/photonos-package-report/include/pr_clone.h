/* pr_clone.h — local-clone manager.
 *
 * Mirrors photonos-package-report.ps1 L 2358-2456 sequentially:
 *
 *     $repoName = regex extract `/<name>\.git$` from $GitSource
 *     $ClonePath = "$UpstreamsDir/$photonDir/clones"
 *     $SourceClonePath = "$ClonePath/$repoName"
 *     if (!Test-Path $SourceClonePath)
 *         Invoke-GitWithTimeout "clone $GitSource [-b $branch] $repoName"
 *     else if (!Test-Path $SourceClonePath/.git)
 *         rm -rf $SourceClonePath; retry clone
 *     else
 *         Invoke-GitWithTimeout "fetch --prune --prune-tags --tags --force ..."
 *
 *     $tagOutput = Invoke-GitWithTimeout "tag -l"
 *     $tagLines = pr_parse_tag_list(tagOutput, customRegex)
 *
 * Phase 7 will wrap this with the FETCH_HEAD/mutex coordination from
 * Wait-ForFetchCompletion (PS L 2003-2073). For 6d we run sequentially.
 */
#ifndef PR_CLONE_H
#define PR_CLONE_H

#include <stddef.h>

/* Extract the repository name from a `git clone`-style URL.
 *
 * PS L 2363: `if ($SourceTagURL -match "/([^/]+)\.git$") { $Matches[1] }`
 *
 * Returns a malloc'd string on match. Returns NULL when the URL does
 * not end with `/<name>.git`. */
char *pr_extract_repo_name(const char *git_url);

/* Ensure a local clone exists for `git_url` under `clone_root/repo_name`.
 * If `git_branch` is non-empty, clones with `-b <branch>` / fetches origin <branch>.
 *
 * Returns 0 on success (clone exists and is healthy), -1 on failure.
 * Mirrors the PS retry-on-broken-.git logic (max 2 attempts).
 */
int pr_clone_ensure(const char *clone_root,
                    const char *git_url,
                    const char *git_branch,
                    const char *repo_name);

/* Run `git tag -l` in the clone directory and parse the output.
 * Optional case-sensitive PCRE2 filter via `custom_regex`.
 *
 * Sets *out_names + *out_n on success. Caller frees with pr_git_tags_free.
 * Returns 0 on success, -1 on failure.
 */
int pr_clone_list_tags(const char *clone_path,
                       const char *custom_regex,
                       char     ***out_names,
                       size_t     *out_n);

#endif /* PR_CLONE_H */
