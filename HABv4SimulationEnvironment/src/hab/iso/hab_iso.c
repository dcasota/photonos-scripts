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
     * Flags explanation:
     * -o : output file
     * -b : boot image (isolinux.bin)
     * -c : boot catalog (boot.cat)
     * -no-emul-boot : "El Torito" no emulation mode
     * -boot-load-size 4 : load 4 sectors
     * -boot-info-table : patch boot info table
     * -eltorito-alt-boot : start second boot entry parameters (for EFI)
     * -e : EFI boot image
     * -no-emul-boot : no emulation for EFI
     * -isohybrid-gpt-basdat : hybrid MBR/GPT
     * -R : Rock Ridge extensions
     * -J : Joliet extensions
     * -V : Volume ID
     */
    snprintf(cmd, sizeof(cmd),
        "mkisofs -R -J -v -V '%s' "
        "-o '%s' "
        "-b isolinux/isolinux.bin "
        "-c isolinux/boot.cat "
        "-no-emul-boot -boot-load-size 4 -boot-info-table "
        "-eltorito-alt-boot "
        "-e boot/grub2/efiboot.img "
        "-no-emul-boot -isohybrid-gpt-basdat "
        "'%s' 2>&1",
        volume_id, output_iso_path, iso_extract_dir);
        
    /* If mkisofs is not found, try genisoimage or xorrisofs */
    if (system("which mkisofs >/dev/null 2>&1") != 0) {
        if (system("which xorrisofs >/dev/null 2>&1") == 0) {
            cmd[0] = 'x'; cmd[1] = 'o'; cmd[2] = 'r'; cmd[3] = 'r'; cmd[4] = 'i'; cmd[5] = 's'; cmd[6] = 'o'; cmd[7] = 'f'; cmd[8] = 's';
        } else if (system("which genisoimage >/dev/null 2>&1") == 0) {
             cmd[0] = 'g'; cmd[1] = 'e'; cmd[2] = 'n'; cmd[3] = 'i'; cmd[4] = 's'; cmd[5] = 'o'; cmd[6] = 'i'; cmd[7] = 'm'; cmd[8] = 'a'; cmd[9] = 'g'; cmd[10] = 'e';
        }
    }

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
