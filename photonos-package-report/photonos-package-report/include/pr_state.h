/* pr_state.h — per-task scratch state.
 *
 * In PS, `CheckURLHealth` mutates a handful of local variables as it
 * walks each task: $Source0, $version, $UpdateAvailable, $UpdateURL,
 * $HealthUpdateURL, $UpdateDownloadName, $SHAValue, $Warning,
 * $ArchivationDate. These are the columns the function ultimately
 * concatenates into the .prn row at PS L 4933.
 *
 * In the C port these locals are wrapped in pr_state_t so they can be
 * passed to:
 *   - pr_source0_substitute() (Phase 4)
 *   - urlhealth()             (Phase 5)
 *   - pr_hooks_run()          (Phase 3b — per-spec exception bodies)
 *
 * The struct is the *only* concrete definition of pr_state_t. Phase 3b
 * forward-declared it; that forward decl is now satisfied by including
 * this header before pr_hook.h.
 *
 * All string fields are heap-allocated empty strings ("") by
 * pr_state_init(). Hook bodies mutate them in-place via the strutil
 * helpers; pr_state_free() releases everything.
 */
#ifndef PR_STATE_H
#define PR_STATE_H

#include <stddef.h>

/* Concrete definition. Phase 3b forward-declared `struct pr_state`. */
struct pr_state {
    char *Source0;             /* PS local $Source0 — Source0 after substitution */
    char *version;             /* PS local $version */
    char *UpdateAvailable;     /* PS $UpdateAvailable: "" / "Update available" / ... */
    char *UpdateURL;
    char *HealthUpdateURL;
    char *UpdateDownloadName;
    char *SHAValue;
    char *Warning;
    char *ArchivationDate;
};

typedef struct pr_state pr_state_t;

/* Lifecycle. Both are safe to call on a zero-initialised struct. */
void pr_state_init(pr_state_t *s);
void pr_state_free(pr_state_t *s);

#endif /* PR_STATE_H */
