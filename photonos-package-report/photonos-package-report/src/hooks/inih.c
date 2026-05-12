/* SPEC: inih.spec */
/* inih.c — per-spec hook for inih.spec.
 *
 * PS source (photonos-package-report.ps1 L 4730, verbatim):
 *
 *     if ($currentTask.spec -ilike 'inih.spec') {
 *         $UpdateDownloadName = $UpdateDownloadName -ireplace "^r","libinih-"
 *     }
 *
 * Semantics: if `$UpdateDownloadName` starts with a lowercase or uppercase
 * 'r' (case-insensitive thanks to `-ireplace`), replace that single
 * leading character with the literal string `libinih-`.
 *
 * In C the `UpdateDownloadName` field is not yet attached to pr_task_t /
 * pr_state_t — that part of the workflow lands in Phase 4 (substitution
 * core) / Phase 6 (CheckURLHealth). For now this hook is wired into the
 * dispatch table and validated by test_phase3b but is a no-op until the
 * state struct grows the field.
 *
 * Hook is intentionally trivial — its purpose is to exercise the dispatch
 * plumbing end-to-end and serve as a template for the 95 unported hooks.
 */
#include "pr_hook.h"

int hook_inih_spec(pr_task_t *task, pr_state_t *state)
{
    (void)task;
    (void)state;
    /* TODO Phase 4/6: when pr_state_t gains the UpdateDownloadName
     * field, port the PS body:
     *
     *   if (state->UpdateDownloadName[0] == 'r' || state->UpdateDownloadName[0] == 'R') {
     *       // -ireplace "^r","libinih-"
     *       ireplace_leading(state->UpdateDownloadName, "r", "libinih-");
     *   }
     */
    return 0;
}
