/* package_report.c — cross-branch package version-matrix report.
 *
 * Phase M task M60. Mirrors photonos-package-report.ps1 L 5556-5585.
 */
#include "pr_package_report.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <unicode/ucol.h>
#include <unicode/utypes.h>

/* ICU collation, same as the .prn row sort (ADR-0016 / M52): matches
 * PowerShell's `Sort-Object Spec, SubRelease`. Sorting the full row string
 * orders by Spec, then the SubRelease field, then the version columns —
 * equivalent to PS's two-key sort for distinct (Spec, SubRelease). */
static UCollator    *g_coll = NULL;
static pthread_once_t g_coll_once = PTHREAD_ONCE_INIT;

static void init_coll(void)
{
    UErrorCode s = U_ZERO_ERROR;
    UCollator *c = ucol_open("en-US", &s);
    if (U_FAILURE(s) || c == NULL) { if (c) ucol_close(c); g_coll = NULL; return; }
    ucol_setStrength(c, UCOL_SECONDARY);
    g_coll = c;
}

static int row_cmp(const void *a, const void *b)
{
    const char *x = *(const char *const *)a;
    const char *y = *(const char *const *)b;
    pthread_once(&g_coll_once, init_coll);
    if (g_coll == NULL) return strcmp(x, y);
    UErrorCode s = U_ZERO_ERROR;
    UCollationResult r = ucol_strcollUTF8(g_coll, x, -1, y, -1, &s);
    if (U_FAILURE(s)) return strcmp(x, y);
    return (r == UCOL_LESS) ? -1 : (r == UCOL_GREATER) ? 1 : 0;
}

/* PS `$PackagesXMain[$PackagesXMain.Spec.IndexOf($spec)].version`: the
 * version (Version-Release) of the FIRST non-subrelease occurrence of
 * `spec` in `l`, or "" if absent. */
static const char *main_version(const pr_task_list_t *l, const char *spec)
{
    for (size_t i = 0; i < l->count; i++) {
        const pr_task_t *t = &l->items[i];
        if (t->SubRelease && t->SubRelease[0] != '\0') continue;
        if (t->Spec && strcmp(t->Spec, spec) == 0)
            return t->Version ? t->Version : "";
    }
    return "";
}

/* Version of the (spec, subRelease) pair in `l` (PS subrelease append:
 * `Where-Object Spec -eq … -and SubRelease -eq … | Select -First 1`). */
static const char *sr_version(const pr_task_list_t *l,
                              const char *spec, const char *sr)
{
    for (size_t i = 0; i < l->count; i++) {
        const pr_task_t *t = &l->items[i];
        if (t->Spec && strcmp(t->Spec, spec) == 0
            && t->SubRelease && strcmp(t->SubRelease, sr) == 0)
            return t->Version ? t->Version : "";
    }
    return "";
}

int pr_write_package_report(const pr_task_list_t *const lists[8],
                            const char *const labels[8],
                            const char *output_path)
{
    if (lists == NULL || labels == NULL || output_path == NULL) return -1;
    for (int k = 0; k < 8; k++) if (lists[k] == NULL) return -1;

    /* Worst-case row count = sum of all task counts across the 8 branches. */
    size_t cap = 0;
    for (int k = 0; k < 8; k++) cap += lists[k]->count;
    if (cap == 0) cap = 1;
    char **rows = (char **)malloc(cap * sizeof *rows);
    if (!rows) return -1;
    size_t n = 0;

    /* Main rows (SubRelease empty): one per non-subrelease task occurrence;
     * each is byte-identical for a given Spec (main_version queries all 8
     * branches), so the sort+dedup below collapses duplicates to one row
     * per Spec — matching PS's `-Unique`. */
    for (int k = 0; k < 8; k++) {
        for (size_t i = 0; i < lists[k]->count; i++) {
            const pr_task_t *t = &lists[k]->items[i];
            if (t->SubRelease && t->SubRelease[0] != '\0') continue;
            if (t->Spec == NULL) continue;
            char *row = NULL;
            if (asprintf(&row, "%s,,%s,%s,%s,%s,%s,%s,%s,%s",
                         t->Spec,
                         main_version(lists[0], t->Spec),
                         main_version(lists[1], t->Spec),
                         main_version(lists[2], t->Spec),
                         main_version(lists[3], t->Spec),
                         main_version(lists[4], t->Spec),
                         main_version(lists[5], t->Spec),
                         main_version(lists[6], t->Spec),
                         main_version(lists[7], t->Spec)) >= 0 && row) {
                rows[n++] = row;
            }
        }
    }

    /* Subrelease rows: one per distinct (Spec, SubRelease). Version columns
     * only for the numeric branches 3.0/4.0/5.0/6.0 (lists[0..3]);
     * common/dev/master/main are always empty (PS hardcodes them ""). Generated
     * per subrelease task occurrence; duplicates collapse in the sort. */
    for (int k = 0; k < 8; k++) {
        for (size_t i = 0; i < lists[k]->count; i++) {
            const pr_task_t *t = &lists[k]->items[i];
            if (!(t->SubRelease && t->SubRelease[0] != '\0')) continue;
            if (t->Spec == NULL) continue;
            char *row = NULL;
            if (asprintf(&row, "%s,%s,%s,%s,%s,%s,,,,",
                         t->Spec, t->SubRelease,
                         sr_version(lists[0], t->Spec, t->SubRelease),
                         sr_version(lists[1], t->Spec, t->SubRelease),
                         sr_version(lists[2], t->Spec, t->SubRelease),
                         sr_version(lists[3], t->Spec, t->SubRelease)) >= 0 && row) {
                rows[n++] = row;
            }
        }
    }

    /* PS `Sort-Object Spec, SubRelease -Unique`. */
    qsort(rows, n, sizeof *rows, row_cmp);

    FILE *f = fopen(output_path, "w");
    if (!f) {
        for (size_t i = 0; i < n; i++) free(rows[i]);
        free(rows);
        return -1;
    }
    (void)labels;  /* fixed PS column order; header is literal below. */
    fputs("Spec,SubRelease,photon-3.0,photon-4.0,photon-5.0,photon-6.0,"
          "photon-common,photon-dev,photon-master,photon-main\n", f);
    const char *prev = NULL;
    for (size_t i = 0; i < n; i++) {
        if (prev && strcmp(prev, rows[i]) == 0) continue;  /* -Unique */
        fputs(rows[i], f);
        fputc('\n', f);
        prev = rows[i];
    }

    int rc = fflush(f) == 0 ? 0 : -1;
    if (fclose(f) != 0) rc = -1;
    for (size_t i = 0; i < n; i++) free(rows[i]);
    free(rows);
    return rc;
}
