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

#endif /* PR_PER_SPEC_H */
