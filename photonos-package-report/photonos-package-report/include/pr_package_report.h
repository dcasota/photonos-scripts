/* pr_package_report.h — cross-branch package version-matrix report.
 *
 * Phase M task M60. Mirrors photonos-package-report.ps1 L 5556-5585
 * (the GeneratePhPackageReport block).
 *
 * Emits `photonos-package-report_<ts>.prn`: one row per package with its
 * version in each of the 7 branches. Header:
 *
 *   Spec,SubRelease,photon-3.0,photon-4.0,photon-5.0,photon-6.0,
 *   photon-common,photon-dev,photon-master
 *
 * Main rows (SubRelease empty): the version (Version-Release) of the FIRST
 * non-subrelease occurrence of the spec in each branch, deduped to one row
 * per Spec (PS `$PackagesXMain[...IndexOf]` + `-Unique`). Subrelease rows
 * are appended: one per distinct (Spec, SubRelease), carrying the matching
 * version in the numeric branches (3.0-6.0) only; common/dev/master are
 * always empty (subreleases live only in the numeric release branches).
 * The combined set is sorted by (Spec, SubRelease) with the same ICU
 * collation the .prn row sort uses (ADR-0016), matching PS Sort-Object.
 */
#ifndef PR_PACKAGE_REPORT_H
#define PR_PACKAGE_REPORT_H

#include "pr_types.h"

/* `lists` and `labels` are parallel arrays of length 7, in the fixed PS
 * column order: 3.0, 4.0, 5.0, 6.0, common, dev, master. Returns 0 on
 * success, -1 on error (NULL args / open failure). */
int pr_write_package_report(const pr_task_list_t *const lists[7],
                            const char *const labels[7],
                            const char *output_path);

#endif /* PR_PACKAGE_REPORT_H */
