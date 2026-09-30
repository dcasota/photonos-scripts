/*
 * hab_iso.c
 *
 * ISO manipulation functions for HABv4
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include "hab_iso.h"
#include "../../habv4_common.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <libgen.h>

/* v1.9.86: photon-os-installer 2.9 media boot BIOS through a GRUB El Torito
 * image (isolinux/eltorito.img); POI 2.8 media through syslinux
 * (isolinux/isolinux.bin). Only an extracted tree is available here, so each
 * known BIOS image is accepted only when its own bytes identify the loader:
 * "ISOLINUX" for syslinux, GRUB cdboot.img's two error messages for GRUB. */
enum { HAB_BIOS_NONE = 0, HAB_BIOS_SYSLINUX, HAB_BIOS_GRUB };

static int hab_file_contains_all(const char *path, const char *a, const char *b) {
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    size_t cap = 4 * 1024 * 1024;
    unsigned char *buf = malloc(cap);
    if (!buf) { fclose(f); return 0; }
    size_t n = fread(buf, 1, cap, f);
    fclose(f);
    int found_a = 0, found_b = (b == NULL);
    size_t la = strlen(a), lb = b ? strlen(b) : 0;
    for (size_t i = 0; i < n; i++) {
        if (!found_a && i + la <= n && memcmp(buf + i, a, la) == 0) found_a = 1;
        if (!found_b && i + lb <= n && memcmp(buf + i, b, lb) == 0) found_b = 1;
    }
    free(buf);
    return found_a && found_b;
}

/* The BIOS boot image of an extracted Photon ISO, relative to its root. */
static int hab_bios_image(const char *tree, char *rel, size_t size) {
    char path[768];
    snprintf(path, sizeof(path), "%s/isolinux/isolinux.bin", tree);
    if (file_exists(path) && hab_file_contains_all(path, "ISOLINUX", NULL)) {
        snprintf(rel, size, "isolinux/isolinux.bin");
        return HAB_BIOS_SYSLINUX;
    }
    snprintf(path, sizeof(path), "%s/isolinux/eltorito.img", tree);
    if (file_exists(path) && hab_file_contains_all(path, "no boot info", "cdrom read fails")) {
        snprintf(rel, size, "isolinux/eltorito.img");
        return HAB_BIOS_GRUB;
    }
    rel[0] = '\0';
    return HAB_BIOS_NONE;
}

int verify_iso_content(const char *iso_mount_dir) {
    char path[512];
    
    /* v1.9.86: kernel, initrd and the UEFI image are required; the BIOS
     * image is either loader, or none on an EFI-only medium. */
    snprintf(path, sizeof(path), "%s/isolinux/vmlinuz", iso_mount_dir);
    if (!file_exists(path)) return 0;
    
    snprintf(path, sizeof(path), "%s/isolinux/initrd.img", iso_mount_dir);
    if (!file_exists(path)) return 0;
    
    snprintf(path, sizeof(path), "%s/boot/grub2/efiboot.img", iso_mount_dir);
    if (!file_exists(path)) return 0;
    
    return 1;
}

int repack_iso(const char *iso_extract_dir, const char *output_iso_path, const char *volume_id) {
    char cmd[2048];
    
    log_info("Repacking ISO: %s", output_iso_path);
    
    /* Create output directory if it doesn't exist */
    char *dir_copy = strdup(output_iso_path);
    char *dir_name = dirname(dir_copy);
    mkdir_p(dir_name);
    free(dir_copy);
    
    /* 
     * Use mkisofs/genisoimage/xorrisofs to build the ISO
     */
    const char *tool = "mkisofs";
    if (system("which mkisofs >/dev/null 2>&1") != 0) {
        if (system("which xorrisofs >/dev/null 2>&1") == 0) {
            tool = "xorrisofs";
        } else if (system("which genisoimage >/dev/null 2>&1") == 0) {
            tool = "genisoimage";
        }
    }

    char bios_rel[256], bios_args[512] = "";
    int loader = hab_bios_image(iso_extract_dir, bios_rel, sizeof(bios_rel));
    if (loader != HAB_BIOS_NONE) {
        snprintf(bios_args, sizeof(bios_args),
            "-b %s -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot ",
            bios_rel);
    } else {
        log_info("No syslinux or GRUB BIOS image in %s: building an EFI-only ISO", iso_extract_dir);
    }

    snprintf(cmd, sizeof(cmd),
        "%s -R -J -v -V '%s' "
        "-o '%s' "
        "-c isolinux/boot.cat "
        "%s"
        "-e boot/grub2/efiboot.img "
        "-no-emul-boot "
        "'%s' 2>&1",
        tool, volume_id, output_iso_path, bios_args, iso_extract_dir);

    log_debug("ISO build command: %s", cmd);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to build ISO image");
        return -1;
    }
    
    /* Post-process with isohybrid for UEFI support. isohybrid writes a
     * syslinux MBR that chains to isolinux.bin, so only syslinux media get it. */
    if (loader == HAB_BIOS_SYSLINUX) {
        snprintf(cmd, sizeof(cmd), "isohybrid --uefi '%s' 2>/dev/null", output_iso_path);
        run_cmd(cmd);
    }
    
    log_info("ISO repacked successfully: %s", output_iso_path);
    return 0;
}
