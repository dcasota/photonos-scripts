/* check_urlhealth.c — CheckURLHealth orchestrator scaffold (Phase 6a).
 *
 * Mirrors photonos-package-report.ps1 L 1574-4934 in *surface* — the
 * 12-column row layout from PS L 4933 is locked here. Body wires:
 *
 *   - Phase 3a Source0LookupData lookup
 *   - Phase 3b per-spec hook dispatch
 *   - Phase 4 substitution
 *   - Phase 5 urlhealth probe
 *
 * Columns 5-7, 10 are emitted as "" until Phase 6b-6d land. Columns
 * 11-12 (Warning, ArchivationDate) are populated from the Source0Lookup
 * row when one exists (PS L 2145-2153). Column 9 (SHAValue) is stubbed
 * until Phase 6d.
 */
/* _GNU_SOURCE for asprintf is provided via CMake; do not redefine. */
#include "pr_check_urlhealth.h"
#include "pr_hook.h"
#include "pr_state.h"
#include "pr_substitute.h"
#include "pr_urlhealth.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Look up the Source0Lookup row whose specfile matches task->Spec.
 * Returns NULL if the table is unset or no row matches. */
static const pr_source0_lookup_t *
lookup_row(const pr_source0_lookup_table_t *t, const char *spec)
{
    if (t == NULL || spec == NULL) return NULL;
    for (size_t i = 0; i < t->count; i++) {
        if (strcmp(t->rows[i].specfile, spec) == 0) {
            return &t->rows[i];
        }
    }
    return NULL;
}

/* xstrdup that returns "" on NULL input rather than NULL. */
static char *dup_or_empty(const char *s)
{
    if (s == NULL) s = "";
    size_t n = strlen(s);
    char *p = (char *)malloc(n + 1);
    if (p) memcpy(p, s, n + 1);
    return p;
}

char *check_urlhealth(pr_task_t                       *task,
                      const pr_source0_lookup_table_t *lookup_table)
{
    if (task == NULL || task->Spec == NULL) return NULL;

    pr_state_t state;
    pr_state_init(&state);

    /* PS L 2140-2153: Source0Lookup CSV lookup. */
    const pr_source0_lookup_t *row = lookup_row(lookup_table, task->Spec);
    if (row && row->Source0Lookup && row->Source0Lookup[0] != '\0') {
        free(state.Source0);
        state.Source0 = dup_or_empty(row->Source0Lookup);
    } else {
        free(state.Source0);
        state.Source0 = dup_or_empty(task->Source0);
    }
    /* PS L 2151-2152: pick up Warning + ArchivationDate from the
     * lookup row when present. (Strings "" otherwise.) */
    if (row) {
        free(state.Warning);
        state.Warning = dup_or_empty(row->Warning);
        free(state.ArchivationDate);
        state.ArchivationDate = dup_or_empty(row->ArchivationDate);
    }

    /* PS L 2108: $version cut. Phase 6b refines this; for 6a we use
     * task->Version verbatim. */
    free(state.version);
    state.version = dup_or_empty(task->Version);

    /* Phase 3b per-spec exception hook. */
    pr_hooks_run(task, &state);

    /* Phase 4 substitution (PS L 2172-2199). */
    pr_source0_substitute(task, &state.Source0, state.version);

    /* Phase 5 urlhealth probe. Skipped offline so ctest stays hermetic. */
    int health = 0;
    const char *netenv = getenv("PR_TEST_NETWORK");
    if (netenv && strcmp(netenv, "1") == 0) {
        health = urlhealth(state.Source0);
    }

    /* PS L 4933: assemble the 12-column row.
     *
     *   $currentTask.spec , $currentTask.source0 , $Source0 ,
     *   $urlhealth , $UpdateAvailable , $UpdateURL , $HealthUpdateURL ,
     *   $currentTask.Name , $SHAValue , $UpdateDownloadName , $Warning ,
     *   $ArchivationDate
     */
    char *out = NULL;
    if (asprintf(&out,
                 "%s,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s",
                 task->Spec,                                      /*  1 Spec */
                 task->Source0 ? task->Source0 : "",              /*  2 Source0 original */
                 state.Source0,                                   /*  3 Source0 (rewritten) */
                 health,                                          /*  4 UrlHealth (0 offline) */
                 state.UpdateAvailable,                           /*  5 — Phase 6b */
                 state.UpdateURL,                                 /*  6 — Phase 6c */
                 state.HealthUpdateURL,                           /*  7 — Phase 6c */
                 task->Name,                                      /*  8 Name */
                 state.SHAValue,                                  /*  9 — Phase 6d */
                 state.UpdateDownloadName,                        /* 10 — Phase 6c */
                 state.Warning,                                   /* 11 from lookup row */
                 state.ArchivationDate                            /* 12 from lookup row */
                 ) < 0) {
        out = NULL;
    }

    pr_state_free(&state);
    return out;
}
