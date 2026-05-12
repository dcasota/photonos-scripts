/* pr_types.h — types shared across the C port.
 *
 * Mirrors the global script-scope variables defined by the PowerShell
 * `param()` block at photonos-package-report.ps1 L 83-108 and the
 * convert-to-boolean assignments at L 120-131.
 *
 * Field names match the PS variable names verbatim (PS is case-insensitive;
 * the canonical PS-source spelling is preserved here).
 */
#ifndef PR_TYPES_H
#define PR_TYPES_H

#include <stdint.h>
#include <stddef.h>

/* Maximum lengths used in fixed-size buffers throughout the port.
 * Chosen to match the script's implicit limits (MAX_LINE_LEN in the
 * sibling C scanner is 4096; we use the same here). */
#define PR_MAX_PATH  4096
#define PR_MAX_LINE  4096
#define PR_MAX_NAME   256

/* Equivalent to the `param()` block at PS L 83-108.
 *
 * Field order in this struct matches the PS param-block declaration order
 * exactly. Phase 1 fills these via `parse_params(argc, argv, &params)`
 * (see src/params.c later); for now main() initialises them inline
 * by mirroring the PS env-fallback defaults at L 84-89.
 */
typedef struct {
    /* L 84: [string]$github_token=$env:GITHUB_TOKEN */
    const char *github_token;

    /* L 85: [string]$gitlab_freedesktop_org_username=$env:GITLAB_FREEDESKTOP_ORG_USERNAME */
    const char *gitlab_freedesktop_org_username;

    /* L 86: [string]$gitlab_freedesktop_org_token=$env:GITLAB_FREEDESKTOP_ORG_TOKEN */
    const char *gitlab_freedesktop_org_token;

    /* L 87: [string]$workingDir = $(if ($env:PUBLIC) { $env:PUBLIC } else { $HOME }) */
    const char *workingDir;

    /* L 88: [string]$upstreamsDir = "" */
    const char *upstreamsDir;

    /* L 89: [string]$scansDir = "" */
    const char *scansDir;

    /* L 95: [string]$UpstreamsExclusionList = "" */
    const char *UpstreamsExclusionList;

    /* L 96-107: report-enable flags. All default to true; after parsing
     * we run Convert-ToBoolean on each (L 120-131) so a value supplied
     * as the literal string "true"/"false"/"$true"/"$false"/"0"/"1" is
     * normalised to int 0/1.
     */
    int GeneratePh3URLHealthReport;
    int GeneratePh4URLHealthReport;
    int GeneratePh5URLHealthReport;
    int GeneratePh6URLHealthReport;
    int GeneratePhCommonURLHealthReport;
    int GeneratePhDevURLHealthReport;
    int GeneratePhMasterURLHealthReport;
    int GeneratePhPackageReport;
    int GeneratePhCommontoPhMasterDiffHigherPackageVersionReport;
    int GeneratePh5toPh6DiffHigherPackageVersionReport;
    int GeneratePh4toPh5DiffHigherPackageVersionReport;
    int GeneratePh3toPh4DiffHigherPackageVersionReport;
} pr_params_t;

#endif /* PR_TYPES_H */
