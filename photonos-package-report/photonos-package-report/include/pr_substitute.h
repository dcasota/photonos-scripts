/* pr_substitute.h — Source0 substitution core.
 *
 * Ports the substitution sequence at photonos-package-report.ps1
 * L 2172-2199 line-for-line.
 *
 * CLAUDE.md invariant #3: "No reordering of mutations on $Source0 when
 * porting. The substitution sequence at PS lines 2161-2199 must be
 * translated in source order, line for line."
 */
#ifndef PR_SUBSTITUTE_H
#define PR_SUBSTITUTE_H

#include "pr_types.h"

/* In-place mutation of *source0 mirroring PS L 2172-2199.
 *
 * Inputs:
 *   - task     : per-spec data (Name, url, and the 15 secondary tokens)
 *   - source0  : owned heap pointer; replaced with a new heap pointer
 *   - version  : the local $version string from PS context (NOT
 *                task->Version, which already has -release appended)
 *
 * On error *source0 is left untouched and the function returns -1.
 * On success returns 0.
 */
int pr_source0_substitute(pr_task_t *task, char **source0, const char *version);

#endif /* PR_SUBSTITUTE_H */
