/* pr_types.h — types shared across the C port.
 *
 * Mirrors PS global variables and the per-spec PSCustomObject built in
 * ParseDirectory at photonos-package-report.ps1 L 247-379.
 *
 * Field naming follows PS canonical case verbatim. No fields are added,
 * removed, or renamed beyond the PS source-of-truth.
 */
#ifndef PR_TYPES_H
#define PR_TYPES_H

#include <stdint.h>
#include <stddef.h>

/* Buffer ceilings used by fixed-size paths. */
#define PR_MAX_PATH  4096
#define PR_MAX_LINE  4096
#define PR_MAX_NAME   256

/* ===== Param block — mirrors PS L 83-108 ============================== */
typedef struct {
    const char *github_token;                                                  /* L 84  */
    const char *gitlab_freedesktop_org_username;                               /* L 85  */
    const char *gitlab_freedesktop_org_token;                                  /* L 86  */
    const char *workingDir;                                                    /* L 87  */
    const char *upstreamsDir;                                                  /* L 88  */
    const char *scansDir;                                                      /* L 89  */
    const char *UpstreamsExclusionList;                                        /* L 95  */
    int GeneratePh3URLHealthReport;                                            /* L 96  */
    int GeneratePh4URLHealthReport;                                            /* L 97  */
    int GeneratePh5URLHealthReport;                                            /* L 98  */
    int GeneratePh6URLHealthReport;                                            /* L 99  */
    int GeneratePhCommonURLHealthReport;                                       /* L 100 */
    int GeneratePhDevURLHealthReport;                                          /* L 101 */
    int GeneratePhMasterURLHealthReport;                                       /* L 102 */
    int GeneratePhPackageReport;                                               /* L 103 */
    int GeneratePhCommontoPhMasterDiffHigherPackageVersionReport;              /* L 104 */
    int GeneratePh5toPh6DiffHigherPackageVersionReport;                        /* L 105 */
    int GeneratePh4toPh5DiffHigherPackageVersionReport;                        /* L 106 */
    int GeneratePh3toPh4DiffHigherPackageVersionReport;                        /* L 107 */
} pr_params_t;

/* ===== Per-spec task — mirrors PS PSCustomObject built at L 345-372 ====
 *
 * The 26 fields below appear in the SAME order as the PS hashtable. Field
 * names match PS verbatim (PS is case-insensitive; we preserve canonical
 * PS spelling and access from C via these names).
 *
 * Every string is heap-allocated and owned by the pr_task_t. Empty PS
 * values land here as "" (non-NULL, length 0). Missing PS values that
 * would otherwise be $null also land here as "".
 *
 * The `content` array is the file's lines (one per element, no trailing
 * newlines). `content_lines` is its length. Indices 0..content_lines-1
 * are valid; lines[content_lines] is NULL.
 *
 * NOTE: PS exposes case-insensitive property access; C does not. The
 * recent regression on 2026-05-11 traced to PS allowing both
 * `$currentTask.Name` and `$currentTask.name`. In C we canonicalise to a
 * single field; helper accessors below answer either spelling.
 */
typedef struct {
    char **content;                /* PS L 346: $content */
    size_t content_lines;
    char  *Spec;                   /* PS L 347: $currentFile.Name */
    char  *Version;                /* PS L 348: "$version-$release" */
    char  *Name;                   /* PS L 349: leaf of $currentFile.DirectoryName */
    char  *SubRelease;             /* PS L 350: first numeric path component, or "" */
    char  *SpecRelativePath;       /* PS L 351 */
    char  *Source0;                /* PS L 352: Get-SpecValue ^Source0: */
    char  *url;                    /* PS L 353: Get-SpecValue ^URL: */
    char  *SHAName;                /* PS L 354: first %define sha1/sha256/sha512 */
    char  *srcname;                /* PS L 355 */
    char  *gem_name;               /* PS L 356 */
    char  *group;                  /* PS L 357 */
    char  *extra_version;          /* PS L 358 */
    char  *main_version;           /* PS L 359 */
    char  *upstreamversion;        /* PS L 360 */
    char  *dialogsubversion;       /* PS L 361 */
    char  *subversion;             /* PS L 362 */
    char  *byaccdate;              /* PS L 363 */
    char  *libedit_release;        /* PS L 364 */
    char  *libedit_version;        /* PS L 365 */
    char  *ncursessubversion;      /* PS L 366 */
    char  *cpan_name;              /* PS L 367 */
    char  *xproto_ver;             /* PS L 368 */
    char  *_url_src;               /* PS L 369 */
    char  *_repo_ver;              /* PS L 370 */
    char  *commit_id;              /* PS L 371 */
} pr_task_t;

/* A growable list of pr_task_t. ParseDirectory returns one of these
 * (mirrors `[System.Collections.Generic.List[PSCustomObject]]`).
 */
typedef struct {
    pr_task_t *items;
    size_t      count;
    size_t      cap;
} pr_task_list_t;

void pr_task_free(pr_task_t *task);
void pr_task_list_init(pr_task_list_t *list);
void pr_task_list_free(pr_task_list_t *list);
int  pr_task_list_add(pr_task_list_t *list, pr_task_t *task);  /* moves task; returns 0 on ok */

#endif /* PR_TYPES_H */
