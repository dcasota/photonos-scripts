/* SPEC: open-vm-tools.spec */
/* open_vm_tools.c — per-spec hook for open-vm-tools.spec.
 *
 * PS source (photonos-package-report.ps1 L 4731, verbatim):
 *
 *     if ($currentTask.spec -ilike 'open-vm-tools.spec') {
 *         $UpdateDownloadName = [System.String]::Concat("open-vm-tools-",$UpdateDownloadName)
 *     }
 *
 * Semantics: prepend the literal string `open-vm-tools-` to the existing
 * UpdateDownloadName.
 *
 * Phase 4/6 will land the actual UpdateDownloadName mutation. For now the
 * hook is a no-op stub validating the dispatch plumbing.
 */
#include "pr_hook.h"

int hook_open_vm_tools_spec(pr_task_t *task, pr_state_t *state)
{
    (void)task;
    (void)state;
    /* TODO Phase 4/6:
     *   prepend_in_place(&state->UpdateDownloadName, "open-vm-tools-");
     */
    return 0;
}
