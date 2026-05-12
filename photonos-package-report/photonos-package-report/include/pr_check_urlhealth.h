/* pr_check_urlhealth.h — CheckURLHealth orchestrator (Phase 6a scaffold).
 *
 * Mirrors photonos-package-report.ps1 L 1574-4934 in surface but only
 * the minimal call chain is wired in 6a:
 *
 *   1. Look up the task in the Source0LookupData table (Phase 3a).
 *   2. Apply the per-spec exception hook (Phase 3b stub).
 *   3. Run pr_source0_substitute on the resolved Source0 (Phase 4).
 *   4. Probe with urlhealth() (Phase 5).
 *   5. Compose the 12-column .prn row from PS L 4933.
 *
 * Phase 6b-6f will progressively flesh out the columns currently
 * stubbed to "":
 *   - version comparison, UpdateAvailable           → Phase 6b
 *   - git tag enumeration (HeapSort + Versioncompare)→ Phase 6c
 *   - anomaly handlers (PS L 2205-3000)             → Phase 6d
 *   - multi-branch diff reports                      → Phase 6e
 *
 * The function returns a malloc'd row string the caller frees. NULL on
 * memory error. The row is NOT terminated by a newline — pr_prn_append_rows
 * adds that.
 */
#ifndef PR_CHECK_URLHEALTH_H
#define PR_CHECK_URLHEALTH_H

#include "pr_types.h"
#include "source0_lookup.h"

/* Returns a malloc'd 12-column comma-separated row mirroring PS L 4933.
 * Columns currently stubbed to "" are commented as such inside the body. */
char *check_urlhealth(pr_task_t                       *task,
                      const pr_source0_lookup_table_t *lookup_table);

#endif /* PR_CHECK_URLHEALTH_H */
