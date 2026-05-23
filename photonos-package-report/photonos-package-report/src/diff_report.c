/* diff_report.c — cross-branch diff-report generator.
 * Mirrors photonos-package-report.ps1 L 5440-5500 verbatim.
 */
#include "pr_diff_report.h"
#include "pr_version.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Look up a task by Spec in `list`, considering only NON-subrelease
 * entries and returning the FIRST match. This mirrors PS's package-matrix
 * construction: `$PackagesXMain = $PackagesX | Where-Object { -not
 * $_.SubRelease }` then `$PackagesXMain[$PackagesXMain.Spec.IndexOf($spec)]`
 * — i.e. the first non-subrelease occurrence wins, and `-Unique` collapses
 * the matrix to one row per Spec. Returns NULL if absent. */
static const pr_task_t *find_by_spec(const pr_task_list_t *list, const char *spec)
{
    if (list == NULL || spec == NULL) return NULL;
    for (size_t i = 0; i < list->count; i++) {
        const pr_task_t *t = &list->items[i];
        if (t->SubRelease && t->SubRelease[0] != '\0') continue;
        if (t->Spec && strcmp(t->Spec, spec) == 0) return t;
    }
    return NULL;
}

int pr_write_diff_report(const pr_task_list_t *tasks_a,
                         const pr_task_list_t *tasks_b,
                         const char           *label_a,
                         const char           *label_b,
                         const char           *output_path)
{
    if (tasks_a == NULL || tasks_b == NULL ||
        label_a == NULL || label_b == NULL || output_path == NULL) {
        return -1;
    }

    FILE *f = fopen(output_path, "w");
    if (!f) return -1;

    /* PS L 5442 header: "Spec,<label_a>,<label_b>" */
    fprintf(f, "Spec,%s,%s\n", label_a, label_b);

    /* Walk tasks_a in insertion order. */
    for (size_t i = 0; i < tasks_a->count; i++) {
        const pr_task_t *a = &tasks_a->items[i];

        /* PS L 5446: skip vendor-pinned subreleases. */
        if (a->SubRelease && a->SubRelease[0] != '\0') continue;

        /* Dedup: emit one row per Spec (PS `-Unique` on the matrix). Only
         * the FIRST non-subrelease occurrence is processed; a later
         * duplicate (e.g. a second linux-esx.spec in the tree) is skipped
         * because find_by_spec returns the first. */
        if (find_by_spec(tasks_a, a->Spec) != a) continue;

        const pr_task_t *b = find_by_spec(tasks_b, a->Spec);
        if (b == NULL) continue;

        /* PS L 5447: both versions non-empty. */
        const char *va = a->Version ? a->Version : "";
        const char *vb = b->Version ? b->Version : "";
        if (va[0] == '\0' || vb[0] == '\0') continue;

        /* PS L 5449: VersionCompare $a $b -eq 1 → a > b. */
        if (pr_version_compare(va, vb) == 1) {
            fprintf(f, "%s,%s,%s\n", a->Spec, va, vb);
        }
    }

    int rc = fflush(f) == 0 ? 0 : -1;
    if (fclose(f) != 0) rc = -1;
    return rc;
}
