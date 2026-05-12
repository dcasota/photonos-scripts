/* SPEC: samba-client.spec */
/* samba_client.c — per-spec hook for samba-client.spec.
 *
 * PS source (photonos-package-report.ps1 L 4732, verbatim):
 *
 *     if ($currentTask.spec -ilike 'samba-client.spec') {
 *         $UpdateDownloadName = $UpdateDownloadName -ireplace "samba-samba-","samba-"
 *     }
 *
 * Semantics: replace the literal substring `samba-samba-` with `samba-`
 * inside UpdateDownloadName, case-insensitive (PS -ireplace).
 *
 * Phase 4/6 will land the actual mutation. For now the hook is a no-op.
 */
#include "pr_hook.h"

int hook_samba_client_spec(pr_task_t *task, pr_state_t *state)
{
    (void)task;
    (void)state;
    /* TODO Phase 4/6:
     *   ireplace_all(state->UpdateDownloadName, "samba-samba-", "samba-");
     */
    return 0;
}
