/* diskspace.c — Test-DiskSpace.
 * Mirrors photonos-package-report.ps1 L 133-160.
 *
 * PS source for reference (verbatim, ASCII transcript):
 *
 *   function Test-DiskSpace {
 *       param(
 *           [Parameter(Mandatory)][string]$Path,
 *           [Parameter(Mandatory)][long]$RequiredMB,
 *           [string]$Operation = "operation"
 *       )
 *       try {
 *           $resolvedPath = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { $Path }
 *           if ($IsLinux -or $IsMacOS) {
 *               $dfLine = & df -BM $resolvedPath 2>&1 | Select-Object -Last 1
 *               if ($dfLine -match '(\d+)M\s+\d+%') {
 *                   $availMB = [long]$Matches[1]
 *               } else { return $true }
 *           } else {
 *               ... [Windows branch — N/A on Photon, ADR-0008]
 *           }
 *           if ($availMB -lt $RequiredMB) {
 *               Write-Warning ("DISK SPACE LOW: {0} MB available, {1} MB required for {2} on {3}"
 *                              -f $availMB, $RequiredMB, $Operation, $resolvedPath)
 *               return $false
 *           }
 *           return $true
 *       } catch {
 *           Write-Warning "Disk space check failed for ${Path}: $_ - proceeding"
 *           return $true
 *       }
 *   }
 *
 * The C port uses statvfs(3) — the system call `df -BM` queries internally.
 * Same observable behaviour, same warning text. No shell-out.
 */
#include "photonos_package_report.h"

#include <stdio.h>
#include <stdlib.h>
#include <sys/statvfs.h>
#include <limits.h>
#include <errno.h>
#include <string.h>

int test_disk_space(const char *path, long required_mb, const char *operation)
{
    if (operation == NULL) operation = "operation"; /* matches PS default */

    /* $resolvedPath = if (Test-Path $Path) { (Resolve-Path $Path).Path } else { $Path } */
    char resolved[PATH_MAX];
    const char *resolved_path;
    if (realpath(path, resolved) != NULL) {
        resolved_path = resolved;
    } else {
        resolved_path = path;
    }

    /* Linux/macOS branch — equivalent to `df -BM $resolvedPath`. */
    struct statvfs sv;
    if (statvfs(resolved_path, &sv) != 0) {
        /* PS catch-block path. */
        fprintf(stderr, "WARNING: Disk space check failed for %s: %s - proceeding\n",
                path, strerror(errno));
        return 1;
    }

    /* PS regex match '(\d+)M\s+\d+%' captures the "Avail" column of df -BM.
     * That value equals (f_bavail * f_frsize) rounded down to MB. */
    long avail_mb = (long)((sv.f_bavail * (unsigned long long)sv.f_frsize) / (1024UL * 1024UL));

    if (avail_mb < required_mb) {
        fprintf(stderr, "WARNING: DISK SPACE LOW: %ld MB available, %ld MB required for %s on %s\n",
                avail_mb, required_mb, operation, resolved_path);
        return 0;
    }
    return 1;
}
