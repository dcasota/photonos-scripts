/* pr_per_spec.h — per-spec strip-token application.
 *
 * Phase M task M27. Mirrors the per-spec switch at
 * photonos-package-report.ps1 L 2839-3060 in the GitHub-tag handling
 * block. Each spec entry adds custom strip tokens to the candidate
 * name list before the standard L 2507-2516 augmentations
 * (apply_name_replace_augmentations / M19) run.
 *
 * The PS pattern is `$replace += "<token>"` — append-only to the
 * substring-strip list. C mirrors via in-place `istr_replace_all`
 * over each token.
 *
 * Only the simple "$replace += "X"; ... break" entries are
 * implemented here. PS entries that also do custom $Names filters
 * (`$Names = @($Names | ... )`) are deferred to per-spec hook
 * functions (Phase 3b).
 */
#ifndef PR_PER_SPEC_H
#define PR_PER_SPEC_H

#include <stddef.h>

/* Apply per-spec strip tokens (PS L 2839 switch) to `names[i]` for
 * every i in [0, n). The spec name match is case-insensitive
 * (PowerShell `switch` default). No-op if the spec has no entry. */
void pr_apply_per_spec_strip_tokens(const char *spec_name,
                                    char **names, size_t n);

/* M28 — drop candidate names that contain ANY of the per-spec
 * blacklist substrings (PS pattern:
 *   `$Names = @($Names | foreach-object { if (!($_ | select-string
 *      -pattern 'X' -simplematch)) {$_}})`).
 * Match is case-INsensitive (PS `select-string -simplematch` default).
 * Dropped entries are freed and set to NULL.
 *
 * Covers the PS L 2839 switch arms for docker-20.10, falco, glib (in
 * addition to its M27 strip tokens), glslang (likewise), go, httpd. */
void pr_apply_per_spec_drop_substrings(const char *spec_name,
                                       char **names, size_t n);

/* M29 — per-spec global character replacement (PS pattern:
 *   `$Names = $Names -ireplace "-",".":` or `-replace "-",".";`).
 * For each candidate, replace every occurrence of `from` with `to`.
 * Currently covers automake, newt, salt3 ("-" → "."). */
void pr_apply_per_spec_global_replace(const char *spec_name,
                                      char **names, size_t n);

/* M33 / FRD-019 — per-spec SourceTagURL override (atom-feed dispatch).
 *
 * Returns a static, non-NULL atom-feed URL when the spec has an
 * override registered (PS L 3815-3866). Returns NULL when there is
 * no override.
 *
 * The returned pointer is owned by the table (static string literal)
 * — caller must not free.
 */
const char *pr_per_spec_source_tag_url(const char *spec_name);

/* M41 / PS L 4294-4305 — "all other types" per-spec SourceTagURL
 * override (project download page). Returns a static URL when the spec
 * is in the ported subset (launchpad / standard listings), else NULL.
 * Caller scrapes <a href> tarball links from the page and path-splits
 * each to its basename before the version pipeline. */
const char *pr_all_other_source_tag_url(const char *spec_name);

#endif /* PR_PER_SPEC_H */
