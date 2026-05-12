/* hook_dispatch.c — binary-search lookup over the generated dispatch table.
 *
 * The table itself lives in `build/generated/pr_hook_dispatch.c`, written
 * by `tools/generate-hook-dispatch.sh` at build time. That generator
 * scans the hook source files for entry points and emits:
 *
 *     const pr_hook_entry_t pr_hook_dispatch[] = {
 *         { "inih.spec",          hook_inih_spec },
 *         { "open-vm-tools.spec", hook_open_vm_tools_spec },
 *         ...
 *     };
 *     const size_t pr_hook_dispatch_count = N;
 *
 * Entries are sorted by `spec` strcmp order so `pr_hooks_find` can do
 * O(log N) bsearch.
 */
#include "pr_hook.h"

#include <stdlib.h>
#include <string.h>

static int entry_cmp(const void *key, const void *member)
{
    const char            *k = (const char *)key;
    const pr_hook_entry_t *m = (const pr_hook_entry_t *)member;
    return strcmp(k, m->spec);
}

pr_hook_fn pr_hooks_find(const char *spec_basename)
{
    if (spec_basename == NULL || pr_hook_dispatch_count == 0) return NULL;
    const pr_hook_entry_t *hit = (const pr_hook_entry_t *)bsearch(
        spec_basename,
        pr_hook_dispatch,
        pr_hook_dispatch_count,
        sizeof(pr_hook_entry_t),
        entry_cmp);
    return hit ? hit->fn : NULL;
}

int pr_hooks_run(pr_task_t *task, pr_state_t *state)
{
    if (task == NULL || task->Spec == NULL) return 0;
    pr_hook_fn fn = pr_hooks_find(task->Spec);
    return fn ? fn(task, state) : 0;
}
