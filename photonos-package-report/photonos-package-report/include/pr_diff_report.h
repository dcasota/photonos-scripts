/* pr_diff_report.h — cross-branch diff-report generator.
 *
 * Mirrors photonos-package-report.ps1 L 5440-5500:
 *
 *   "Spec,<label_a>,<label_b>" | out-file $outputfile
 *   $result | foreach-object {
 *       if ($_.SubRelease) { return }     # skip vendor-pinned subreleases
 *       if (both versions non-empty) {
 *           if (VersionCompare $a $b -eq 1) {
 *               "$spec,$a,$b" | out-file -append
 *           }
 *       }
 *   }
 *
 * In the C port the two input task lists come from
 * parse_directory(branch_a) / parse_directory(branch_b). For each
 * matching spec basename (case-sensitive strcmp), the function emits
 * one CSV row when pr_version_compare(version_a, version_b) == 1.
 *
 * Rows are filtered by the PS L 5446 SubRelease guard: tasks whose
 * SubRelease is non-empty are skipped (vendor-pinned subreleases
 * shouldn't compete in the diff).
 *
 * Output order matches the order specs appear in `tasks_a` (PS uses
 * `$result | foreach-object` which is insertion order).
 */
#ifndef PR_DIFF_REPORT_H
#define PR_DIFF_REPORT_H

#include "pr_types.h"

/* Write a diff report to `output_path`. Returns 0 on success, -1 on I/O.
 *
 * The header line is: "Spec,<label_a>,<label_b>"
 * Each emitted row: "<spec>,<version_a>,<version_b>"
 *
 * `label_a` and `label_b` are usually branch identifiers like
 * "photon-5.0" / "photon-6.0".
 */
int pr_write_diff_report(const pr_task_list_t *tasks_a,
                         const pr_task_list_t *tasks_b,
                         const char           *label_a,
                         const char           *label_b,
                         const char           *output_path);

#endif /* PR_DIFF_REPORT_H */
