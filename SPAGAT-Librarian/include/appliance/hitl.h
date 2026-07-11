/*
 * appliance/hitl.h — adapter shim for the external HITL approval overlay.
 *
 * This header is the T-PUB boundary between the generic console TUI and
 * the appliance-integration implementation living under
 * src/tui/appliance/. Two build modes:
 *
 *   - Appliance build  (-DSPAGAT_APPLIANCE_BUILD): this header forwards
 *     to the real appliance interface header; the implementation in
 *     src/tui/appliance/tui_hitl.c is linked into the binary.
 *
 *   - Standalone build (no SPAGAT_APPLIANCE_BUILD):  this header supplies
 *     a minimal HitlState struct + inline no-op function bodies so the
 *     kanban TUI compiles and links WITHOUT the appliance overlay. The
 *     public console never surfaces the HITL overlay in this mode.
 *
 * Callers should include this shim (not the underlying appliance header)
 * so the same source compiles cleanly under both build modes. See task
 * #569 refactor + tier-manifest T-PUB / T-INT split.
 */

#ifndef SPAGAT_APPLIANCE_HITL_SHIM_H
#define SPAGAT_APPLIANCE_HITL_SHIM_H

#ifdef SPAGAT_APPLIANCE_BUILD

/* Appliance build: real interface is defined in spagat_hitl.h and the
 * matching implementation is linked from src/tui/appliance/tui_hitl.c. */
#include "spagat_hitl.h"

#else  /* !SPAGAT_APPLIANCE_BUILD — standalone / public build */

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Public-build stub type. The kanban TUI holds this by value so it
 * must have a concrete layout; only the fields the T-PUB TUI callers
 * directly reference are exposed. `active` is always false in this
 * build — the overlay is not available and the caller's guard
 * (`if (state->hitl.active) ...`) short-circuits cleanly. */
typedef struct HitlState {
    bool active;
    int _reserved_public_stub;
} HitlState;

typedef struct HitlVerdict {
    int _reserved_public_stub;
} HitlVerdict;

/* No-op stubs — the public build has no HITL overlay to drive. Every
 * entry point becomes a silent no-op. Return values pick the "nothing
 * happened" branch on the caller side. */
static inline void hitl_init(HitlState *state) { (void)state; }
static inline void hitl_toggle(HitlState *state) { (void)state; }
static inline int  hitl_refresh(HitlState *state) { (void)state; return 0; }
static inline int  hitl_decide(HitlState *state, bool approve) {
    (void)state; (void)approve; return 0;
}
static inline void hitl_cursor_up(HitlState *state) { (void)state; }
static inline void hitl_cursor_down(HitlState *state) { (void)state; }
static inline const HitlVerdict *hitl_current(const HitlState *state) {
    (void)state; return NULL;
}
static inline const char *hitl_inbox_path(void) { return ""; }
static inline const char *hitl_unsigned_path(void) { return ""; }
static inline bool hitl_is_known_source_schema(const char *schema) {
    (void)schema; return false;
}

/* The two rendering entry points also become no-ops. They take the
 * terminal dimensions in the appliance interface; ignore them here. */
static inline void tui_hitl_draw(HitlState *state,
                                 int term_height,
                                 int term_width) {
    (void)state; (void)term_height; (void)term_width;
}
static inline void tui_hitl_show_details(HitlState *state,
                                         int term_height,
                                         int term_width) {
    (void)state; (void)term_height; (void)term_width;
}

#ifdef __cplusplus
}
#endif

#endif /* SPAGAT_APPLIANCE_BUILD */

#endif /* SPAGAT_APPLIANCE_HITL_SHIM_H */
