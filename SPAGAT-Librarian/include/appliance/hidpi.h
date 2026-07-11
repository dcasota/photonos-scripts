/*
 * appliance/hidpi.h — adapter shim for the external HiDPI framebuffer
 * tier probe.
 *
 * See appliance/hitl.h for the two-mode adapter pattern. The HiDPI tier
 * probe is an appliance feature; the standalone build simply reports
 * the legacy 80x25 tier from the pure decision function and no-ops the
 * probe stages.
 */

#ifndef SPAGAT_APPLIANCE_HIDPI_SHIM_H
#define SPAGAT_APPLIANCE_HIDPI_SHIM_H

#ifdef SPAGAT_APPLIANCE_BUILD

#include "spagat_hidpi.h"

#else  /* !SPAGAT_APPLIANCE_BUILD — standalone / public build */

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    TIER_80x25 = 0,
    TIER_160x60,
    TIER_AUTO
} SpagatHidpiTier;

typedef struct SpagatHidpiProbe {
    bool fb0_readable;
    bool drm_card0_present;
    int  fb_width_px;
    int  fb_height_px;
    int  font_cell_w;
    int  font_cell_h;
    bool habv4_gesture_present;
} SpagatHidpiProbe;

static inline int spagat_hidpi_parse_boot_param(const char *cmdline,
                                                SpagatHidpiProbe *out) {
    (void)cmdline; (void)out;
    return 0;
}

static inline int spagat_hidpi_probe_vt_ioctl(SpagatHidpiProbe *out) {
    (void)out;
    return 0;
}

static inline int spagat_hidpi_measure_font_cell(SpagatHidpiProbe *out) {
    (void)out;
    return 0;
}

static inline SpagatHidpiTier spagat_hidpi_decide_tier(
    const SpagatHidpiProbe *p) {
    (void)p;
    /* Legacy tier is the safe default for the public build. */
    return TIER_80x25;
}

static inline int spagat_hidpi_subscribe_console(SpagatHidpiTier tier) {
    (void)tier;
    return 0;
}

#ifdef __cplusplus
}
#endif

#endif /* SPAGAT_APPLIANCE_BUILD */

#endif /* SPAGAT_APPLIANCE_HIDPI_SHIM_H */
