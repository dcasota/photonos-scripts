/* pr_hook.h — per-spec override hook interface.
 *
 * Mirrors the PS pattern at photonos-package-report.ps1 (scattered, 96
 * specs / 142 blocks):
 *
 *     if ($currentTask.spec -ilike 'inih.spec') {
 *         $UpdateDownloadName = $UpdateDownloadName -ireplace "^r","libinih-"
 *     }
 *
 * In the C port each PS block lives in its own translation unit under
 * `src/hooks/<spec_basename>.c`. The file is generated as a skeleton by
 * `tools/extract-spec-hooks.sh` (with the PS body embedded as a comment)
 * and hand-translated by the dev agent.
 *
 * The dispatch table `build/generated/pr_hook_dispatch.c` is regenerated
 * on every build by `tools/generate-hook-dispatch.sh`, which scans the
 * existing hook files and emits a sorted array of {spec_basename, fn}
 * pairs.
 *
 * Hook lookup is O(log N) over the sorted table.
 */
#ifndef PR_HOOK_H
#define PR_HOOK_H

#include "pr_types.h"

/* Forward declaration. The concrete pr_state_t lands in Phase 6 when
 * CheckURLHealth gains its per-task scratch space. Hooks needing state
 * fields will compile against the real struct once it lands. */
typedef struct pr_state pr_state_t;

/* Hook function signature. Returns 0 on success, non-zero to abort the
 * per-task workflow. Mirrors PS exception/early-return semantics inside
 * the override block. */
typedef int (*pr_hook_fn)(pr_task_t *task, pr_state_t *state);

/* Look up the hook function for a given spec basename (e.g. "inih.spec").
 * Returns NULL if no hook exists. Match is case-sensitive — PS uses
 * `-ilike` but the spec basenames stored in the dispatch table are
 * already canonical lower-case from the extractor.
 *
 * The returned function pointer is stable for the lifetime of the
 * process — the dispatch table is static const data baked at compile time.
 */
pr_hook_fn pr_hooks_find(const char *spec_basename);

/* Convenience wrapper: look up and call. Returns 0 if no hook exists
 * (treated as "no override needed"), or the hook's return value. */
int pr_hooks_run(pr_task_t *task, pr_state_t *state);

/* The dispatch table itself. Each entry is one (spec, fn) pair, sorted
 * by `spec` strcmp ordering. Generated; do not modify by hand. */
typedef struct {
    const char *spec;   /* e.g. "inih.spec" */
    pr_hook_fn  fn;
} pr_hook_entry_t;

/* Externs filled in by the generated dispatch translation unit. */
extern const pr_hook_entry_t pr_hook_dispatch[];
extern const size_t          pr_hook_dispatch_count;

#endif /* PR_HOOK_H */
