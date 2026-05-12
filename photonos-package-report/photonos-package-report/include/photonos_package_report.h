/* photonos_package_report.h — forward declarations in PS source order.
 *
 * Every function below has a 1:1 counterpart in
 * `../photonos-package-report.ps1`. The PS line range is annotated.
 * Function names mirror PS function names (PascalCase-Hyphen → snake_case).
 *
 * Functions appear here in the SAME order as they are defined in the PS
 * script. Do not reorder. Do not split. Do not introduce helpers that have
 * no PS counterpart (CLAUDE.md invariant #1, ADR-0006).
 */
#ifndef PHOTONOS_PACKAGE_REPORT_H
#define PHOTONOS_PACKAGE_REPORT_H

#include "pr_types.h"

#include <stdbool.h>

/* --- PS L 111-118: function Convert-ToBoolean($value) ---------------- */
/* Returns 1 (true) or 0 (false). Mirrors PS rules:
 *   if value matches '$true'|'true'|'1'  -> 1
 *   if value matches '$false'|'false'|'0' -> 0
 *   otherwise: 1 iff value is non-NULL and non-empty (PS [bool] cast)
 */
int convert_to_boolean(const char *value);

/* --- PS L 133-160: function Test-DiskSpace ------------------------- */
/* Returns 1 on success or insufficient-data, 0 when space below required.
 * Emits a Write-Warning-equivalent line to stderr when low.
 *
 * Operation is a free-text label included in the warning text, matching
 * PS exactly: "DISK SPACE LOW: {avail} MB available, {required} MB
 * required for {operation} on {resolvedPath}".
 */
int test_disk_space(const char *path, long required_mb, const char *operation);

/* --- PS L 163-231: function Invoke-GitWithTimeout ------------------ */
/* Runs `git <arguments>` in working_directory with a wall-clock timeout.
 *
 * On success returns 0 and writes captured stdout into *out_stdout
 * (caller must free). On timeout writes a warning and returns -2.
 * On non-zero git exit writes stderr to its own warning and returns the
 * git exit code (always > 0). On internal error returns -1.
 *
 * timeout_seconds == 0 → default of 14400 (4 hours), matching PS L 167.
 */
int invoke_git_with_timeout(const char *arguments,
                            const char *working_directory,
                            int timeout_seconds,
                            char **out_stdout);

#endif /* PHOTONOS_PACKAGE_REPORT_H */
