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

int verify_iso_content(const char *iso_mount_dir) {
    char path[512];
    
    snprintf(path, sizeof(path), "%s/isolinux/isolinux.bin", iso_mount_dir);
    if (!file_exists(path)) return 0;
    
    snprintf(path, sizeof(path), "%s/isolinux/initrd.img", iso_mount_dir);
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

    snprintf(cmd, sizeof(cmd),
        "%s -R -J -v -V '%s' "
        "-o '%s' "
        "-b isolinux/isolinux.bin "
        "-c isolinux/boot.cat "
        "-no-emul-boot -boot-load-size 4 -boot-info-table "
        "-eltorito-alt-boot "
        "-e boot/grub2/efiboot.img "
        "-no-emul-boot "
        "'%s' 2>&1",
        tool, volume_id, output_iso_path, iso_extract_dir);

    log_debug("ISO build command: %s", cmd);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to build ISO image");
        return -1;
    }
    
    /* Post-process with isohybrid for UEFI support */
    snprintf(cmd, sizeof(cmd), "isohybrid --uefi '%s' 2>/dev/null", output_iso_path);
    run_cmd(cmd);
    
    log_info("ISO repacked successfully: %s", output_iso_path);
    return 0;
}
