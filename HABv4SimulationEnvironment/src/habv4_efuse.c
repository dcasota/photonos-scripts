/*
 * habv4_efuse.c
 *
 * eFuse simulation and USB dongle creation functions for
 * PhotonOS-HABv4Emulation-ISOCreator
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include "habv4_common.h"

/* ============================================================================
 * eFuse Simulation Setup
 * ============================================================================ */

int setup_efuse_simulation(void) {
    log_step("Setting up eFuse simulation...");
    
    mkdir_p(cfg.efuse_dir);
    
    char src[512], dst[512];
    snprintf(src, sizeof(src), "%s/srk_hash.bin", cfg.keys_dir);
    snprintf(dst, sizeof(dst), "%s/srk_fuse.bin", cfg.efuse_dir);
    
    if (file_exists(src)) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", src, dst);
        run_cmd(cmd);
    }
    
    snprintf(dst, sizeof(dst), "%s/sec_config.bin", cfg.efuse_dir);
    FILE *f = fopen(dst, "wb");
    if (f) {
        fputc(0x02, f);
        fclose(f);
    }
    
    snprintf(dst, sizeof(dst), "%s/sec_config.txt", cfg.efuse_dir);
    f = fopen(dst, "w");
    if (f) {
        fprintf(f, "Closed\n");
        fclose(f);
    }
    
    snprintf(dst, sizeof(dst), "%s/efuse_map.txt", cfg.efuse_dir);
    f = fopen(dst, "w");
    if (f) {
        fprintf(f,
            "# HABv4 eFuse Simulation Map\n"
            "# ==========================\n"
            "# OCOTP_CFG5 (0x460): Security Configuration\n"
            "#   Bit 1: SEC_CONFIG (0=Open, 1=Closed)\n"
            "#   Bit 0: SJC_DISABLE\n"
            "# OCOTP_SRK0-7 (0x580-0x5FC): SRK Hash (256 bits)\n"
            "\n"
            "SEC_CONFIG=Closed\n"
            "SJC_DISABLE=0\n"
            "SRK_LOCK=1\n"
            "SRK_REVOKE=0x00\n"
        );
        fclose(f);
    }
    
    log_info("eFuse simulation created in %s", cfg.efuse_dir);
    return 0;
}

/* ============================================================================
 * eFuse USB Dongle Creation
 * ============================================================================ */

int create_efuse_usb(const char *device) {
    log_step("Creating eFuse USB dongle on %s...", device);
    
    struct stat st;
    if (stat(device, &st) != 0 || !S_ISBLK(st.st_mode)) {
        log_error("Device not found or not a block device: %s", device);
        return -1;
    }
    
    printf(YELLOW "WARNING: This will ERASE all data on %s!\n" RESET, device);
    
    if (!cfg.yes_to_all) {
        printf("Continue? [y/N] ");
        fflush(stdout);
        
        char confirm[8];
        if (fgets(confirm, sizeof(confirm), stdin) == NULL || 
            (confirm[0] != 'y' && confirm[0] != 'Y')) {
            log_info("Aborted");
            return 0;
        }
    } else {
        printf("Auto-confirmed with -y flag\n");
    }
    
    char cmd[1024];
    
    /* Use sfdisk instead of parted (more commonly available) */
    snprintf(cmd, sizeof(cmd), "sfdisk '%s' <<EOF\nlabel: gpt\ntype=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\nEOF", device);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to create partition table");
        return -1;
    }
    
    char partition[256];
    if (strstr(device, "nvme") != NULL) {
        snprintf(partition, sizeof(partition), "%sp1", device);
    } else {
        snprintf(partition, sizeof(partition), "%s1", device);
    }
    
    /* Wait for partition to appear */
    sleep(2);
    snprintf(cmd, sizeof(cmd), "partprobe '%s' 2>/dev/null || true", device);
    run_cmd(cmd);
    sleep(1);
    
    snprintf(cmd, sizeof(cmd), "mkfs.vfat -F 32 -n 'EFUSE_SIM' '%s'", partition);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to format partition");
        return -1;
    }
    
    /* Security: Use mkdtemp for secure temp directory */
    char *mount_point = create_secure_tempdir("habefuse");
    if (!mount_point) {
        log_error("Failed to create secure temp directory");
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd), "mount '%s' '%s'", partition, mount_point);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to mount partition");
        rmdir(mount_point);
        free(mount_point);
        return -1;
    }
    
    char efuse_path[512];
    snprintf(efuse_path, sizeof(efuse_path), "%s/efuse_sim", mount_point);
    mkdir_p(efuse_path);
    
    snprintf(cmd, sizeof(cmd), "cp '%s'/* '%s/' 2>/dev/null || true", cfg.efuse_dir, efuse_path);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "cp '%s/srk_hash.bin' '%s/' 2>/dev/null || true", cfg.keys_dir, efuse_path);
    run_cmd(cmd);
    
    /* Copy GPG public key if RPM signing is enabled */
    if (cfg.rpm_signing) {
        char gpg_src[512], gpg_dst[512];
        snprintf(gpg_src, sizeof(gpg_src), "%s/%s", cfg.keys_dir, GPG_KEY_FILE);
        snprintf(gpg_dst, sizeof(gpg_dst), "%s/%s", mount_point, GPG_KEY_FILE);
        
        if (file_exists(gpg_src)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", gpg_src, gpg_dst);
            run_cmd(cmd);
            log_info("GPG public key copied to eFuse USB");
        }
    }
    
    snprintf(cmd, sizeof(cmd), "umount '%s'", mount_point);
    run_cmd(cmd);
    rmdir(mount_point);
    free(mount_point);
    
    log_info("eFuse USB dongle created on %s (label: EFUSE_SIM)", device);
    return 0;
}
