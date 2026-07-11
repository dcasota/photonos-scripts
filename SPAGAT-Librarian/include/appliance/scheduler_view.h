/*
 * appliance/scheduler_view.h — adapter shim for the external fleet
 * scheduler view.
 *
 * See appliance/hitl.h for the two-mode adapter pattern. The scheduler
 * view is an appliance-integration feature; the standalone build
 * exposes only stub entry points that report "no calendar available".
 */

#ifndef SPAGAT_APPLIANCE_SCHEDULER_VIEW_SHIM_H
#define SPAGAT_APPLIANCE_SCHEDULER_VIEW_SHIM_H

#ifdef SPAGAT_APPLIANCE_BUILD

#include "spagat_scheduler_view.h"

#else  /* !SPAGAT_APPLIANCE_BUILD — standalone / public build */

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SpagatScheduleWindow {
    int _reserved_public_stub;
} SpagatScheduleWindow;

typedef enum {
    EDIT_APPLIED = 0,
    EDIT_GATED_L4,
    EDIT_RATE_LIMITED,
    EDIT_REJECTED
} SpagatScheduleEditOutcome;

static inline int spagat_scheduler_view_load(const char *calendar_path,
                                             SpagatScheduleWindow **out,
                                             size_t *n) {
    (void)calendar_path;
    if (out) { *out = NULL; }
    if (n) { *n = 0; }
    /* Non-zero return signals "no calendar available". */
    return -1;
}

static inline void spagat_scheduler_view_free(SpagatScheduleWindow *w,
                                              size_t n) {
    (void)w; (void)n;
}

static inline int spagat_scheduler_view_save(const char *calendar_path,
                                             const SpagatScheduleWindow *w,
                                             size_t n) {
    (void)calendar_path; (void)w; (void)n;
    return -1;
}

static inline SpagatScheduleEditOutcome spagat_scheduler_view_edit(
    SpagatScheduleWindow *w, const char *signed_gesture_or_null) {
    (void)w; (void)signed_gesture_or_null;
    return EDIT_REJECTED;
}

static inline int spagat_scheduler_view_reset(
    const char *calendar_path, const char *default_calendar_path) {
    (void)calendar_path; (void)default_calendar_path;
    return -1;
}

static inline int spagat_scheduler_view_emit_critical_deviation(
    const SpagatScheduleWindow *w, const char *bridge_dir) {
    (void)w; (void)bridge_dir;
    return -1;
}

#ifdef __cplusplus
}
#endif

#endif /* SPAGAT_APPLIANCE_BUILD */

#endif /* SPAGAT_APPLIANCE_SCHEDULER_VIEW_SHIM_H */
