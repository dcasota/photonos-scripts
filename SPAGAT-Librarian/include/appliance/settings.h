/*
 * appliance/settings.h — adapter shim for the external Settings mode.
 *
 * See appliance/hitl.h for the two-mode adapter pattern; this file uses
 * the same convention for the Settings overlay. Under the standalone
 * build the Settings mode is not available (no external config manifest
 * to render), so every entry point is a no-op stub.
 */

#ifndef SPAGAT_APPLIANCE_SETTINGS_SHIM_H
#define SPAGAT_APPLIANCE_SETTINGS_SHIM_H

#ifdef SPAGAT_APPLIANCE_BUILD

#include "spagat_settings.h"

#else  /* !SPAGAT_APPLIANCE_BUILD — standalone / public build */

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Public-build stub context. Callers hold a pointer to this and the
 * T-PUB code only reads `active` from it before any real action — the
 * short-circuit `if (state->settings && state->settings->active) …`
 * pattern compiles cleanly this way. spagat_settings_load returns NULL
 * in this build so the branch is never taken. */
typedef struct spagat_settings_ctx {
    bool active;
    int _reserved_public_stub;
} spagat_settings_ctx_t;

typedef enum {
    SPAGAT_SETTINGS_SECTION_STUB = 0
} SpagatSettingsSection;

typedef struct SpagatSettingsField {
    int _reserved_public_stub;
} SpagatSettingsField;

/* Load / free — the load always returns NULL in the public build so the
 * TUI never enters Settings mode. */
static inline const char *spagat_settings_effective_path(void) { return ""; }
static inline spagat_settings_ctx_t *spagat_settings_load(const char *p) {
    (void)p; return NULL;
}
static inline void spagat_settings_free(spagat_settings_ctx_t *ctx) {
    (void)ctx;
}

/* Overlay + cursor + query surface. All no-ops. */
static inline void spagat_settings_toggle(spagat_settings_ctx_t *ctx) {
    (void)ctx;
}
static inline void spagat_settings_cursor_up(spagat_settings_ctx_t *ctx) {
    (void)ctx;
}
static inline void spagat_settings_cursor_down(spagat_settings_ctx_t *ctx) {
    (void)ctx;
}
static inline const SpagatSettingsField *spagat_settings_current(
    const spagat_settings_ctx_t *ctx) {
    (void)ctx; return NULL;
}
static inline void spagat_settings_elide_fingerprint(const char *raw,
                                                     char *out,
                                                     size_t out_size) {
    (void)raw;
    if (out && out_size) { out[0] = '\0'; }
}
static inline const char *spagat_settings_section_label(
    SpagatSettingsSection section) {
    (void)section; return "";
}
static inline void spagat_settings_draw(spagat_settings_ctx_t *ctx) {
    (void)ctx;
}
static inline void spagat_settings_show_details(spagat_settings_ctx_t *ctx) {
    (void)ctx;
}
static inline int spagat_settings_handle_key(spagat_settings_ctx_t *ctx,
                                             int ch) {
    (void)ctx; (void)ch;
    /* Return 1 to signal "exit back to previous mode" — the standalone
     * build has no Settings state to hold in. */
    return 1;
}

/* Edit + emit surface — every call is a no-op / failure in this mode. */
static inline int spagat_settings_field_editable(
    const spagat_settings_ctx_t *ctx) {
    (void)ctx; return 0;
}
static inline int spagat_settings_edit_current_field(
    spagat_settings_ctx_t *ctx, const char *new_value) {
    (void)ctx; (void)new_value; return -1;
}
static inline int spagat_settings_has_pending(
    const spagat_settings_ctx_t *ctx) {
    (void)ctx; return 0;
}
static inline const char *spagat_settings_event_path(void) { return ""; }
static inline int spagat_settings_commit_pending(
    spagat_settings_ctx_t *ctx, const char *event_path) {
    (void)ctx; (void)event_path; return 0;
}
static inline int spagat_settings_serialise_pending(
    const spagat_settings_ctx_t *ctx, char *out, size_t out_size) {
    (void)ctx;
    if (out && out_size) { out[0] = '\0'; }
    return 0;
}

/* Deterministic clock hook — accept + ignore. */
typedef long (*spagat_settings_time_fn)(void);
static inline void spagat_settings_set_time_fn(spagat_settings_time_fn fn) {
    (void)fn;
}

#ifdef __cplusplus
}
#endif

#endif /* SPAGAT_APPLIANCE_BUILD */

#endif /* SPAGAT_APPLIANCE_SETTINGS_SHIM_H */
