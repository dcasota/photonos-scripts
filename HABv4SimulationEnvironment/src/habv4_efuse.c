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

/* ============================================================================
 * eFuse Virtual USB Image Creation (file-backed)
 * ============================================================================
 *
 * Sibling of create_efuse_usb that targets a regular file via losetup -fP.
 * Byte-equivalent output to the physical-USB path on a stick of the same
 * size, so `dd if=foo.img of=/dev/sdX bs=4M` produces a stick
 * indistinguishable from `--create-efuse-usb=/dev/sdX`.
 *
 * The file is suitable for direct attachment to QEMU as a virtual USB drive:
 *   -drive if=none,id=efuse,format=raw,file=foo.img
 *   -device usb-storage,drive=efuse,bus=ehci.0
 *
 * Requires: loop kernel module (CONFIG_BLK_DEV_LOOP=y) + root for losetup.
 * Returns 0 on success, non-zero on failure.
 */
int create_efuse_img(const char *out_path, int size_mb) {
    if (!out_path || !*out_path) {
        log_error("eFuse img path required");
        return -1;
    }
    if (size_mb <= 0) size_mb = 64;
    if (size_mb < 16 || size_mb > 32768) {
        log_error("eFuse img size must be 16..32768 MB (got %d)", size_mb);
        return -1;
    }

    log_step("Creating eFuse virtual USB image at %s (%d MB)...", out_path, size_mb);

    char cmd[1024];

    /* 1. Allocate sparse file of the requested size. */
    snprintf(cmd, sizeof(cmd),
             "dd if=/dev/zero of='%s' bs=1M count=0 seek=%d 2>/dev/null",
             out_path, size_mb);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to allocate img file %s", out_path);
        return -1;
    }

    /* 2. Attach as loop device (with partition scan); capture device path. */
    char loop_dev_file[256];
    snprintf(loop_dev_file, sizeof(loop_dev_file),
             "/tmp/habv4-loop-%d.txt", (int)getpid());
    snprintf(cmd, sizeof(cmd),
             "losetup -fP --show '%s' > '%s'",
             out_path, loop_dev_file);
    if (run_cmd(cmd) != 0) {
        log_error("losetup failed - is the loop kernel module available?");
        unlink(loop_dev_file);
        return -1;
    }

    char loop_dev[128] = {0};
    FILE *lf = fopen(loop_dev_file, "r");
    if (!lf || !fgets(loop_dev, sizeof(loop_dev), lf)) {
        log_error("Could not read loop device path");
        if (lf) fclose(lf);
        unlink(loop_dev_file);
        return -1;
    }
    fclose(lf);
    unlink(loop_dev_file);
    size_t loop_len = strlen(loop_dev);
    while (loop_len > 0 && (loop_dev[loop_len-1] == '\n' || loop_dev[loop_len-1] == '\r')) {
        loop_dev[--loop_len] = '\0';
    }
    if (loop_len == 0 || loop_dev[0] != '/') {
        log_error("losetup returned unexpected output: '%s'", loop_dev);
        return -1;
    }
    log_info("loop device: %s", loop_dev);

    /* 3. Partition table (same GPT type as the physical path). */
    snprintf(cmd, sizeof(cmd),
             "sfdisk '%s' <<EOF\nlabel: gpt\ntype=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7\nEOF",
             loop_dev);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to create partition table");
        snprintf(cmd, sizeof(cmd), "losetup -d '%s' 2>/dev/null || true", loop_dev);
        run_cmd(cmd);
        return -1;
    }

    /* 4. Re-read partition table; loop partition is /dev/loopNp1. */
    snprintf(cmd, sizeof(cmd), "partprobe '%s' 2>/dev/null || true", loop_dev);
    run_cmd(cmd);
    sleep(1);

    char partition[256];
    snprintf(partition, sizeof(partition), "%sp1", loop_dev);

    snprintf(cmd, sizeof(cmd),
             "mkfs.vfat -F 32 -n 'EFUSE_SIM' '%s'", partition);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to format partition");
        snprintf(cmd, sizeof(cmd), "losetup -d '%s' 2>/dev/null || true", loop_dev);
        run_cmd(cmd);
        return -1;
    }

    /* 5. Mount + copy payload (same files as the physical-USB path). */
    char *mount_point = create_secure_tempdir("habefuseimg");
    if (!mount_point) {
        log_error("Failed to create secure temp directory");
        snprintf(cmd, sizeof(cmd), "losetup -d '%s' 2>/dev/null || true", loop_dev);
        run_cmd(cmd);
        return -1;
    }
    snprintf(cmd, sizeof(cmd), "mount '%s' '%s'", partition, mount_point);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to mount loop partition");
        rmdir(mount_point);
        free(mount_point);
        snprintf(cmd, sizeof(cmd), "losetup -d '%s' 2>/dev/null || true", loop_dev);
        run_cmd(cmd);
        return -1;
    }

    char efuse_path[512];
    snprintf(efuse_path, sizeof(efuse_path), "%s/efuse_sim", mount_point);
    mkdir_p(efuse_path);

    snprintf(cmd, sizeof(cmd), "cp '%s'/* '%s/' 2>/dev/null || true", cfg.efuse_dir, efuse_path);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s/srk_hash.bin' '%s/' 2>/dev/null || true", cfg.keys_dir, efuse_path);
    run_cmd(cmd);

    if (cfg.rpm_signing) {
        char gpg_src[512], gpg_dst[512];
        snprintf(gpg_src, sizeof(gpg_src), "%s/%s", cfg.keys_dir, GPG_KEY_FILE);
        snprintf(gpg_dst, sizeof(gpg_dst), "%s/%s", mount_point, GPG_KEY_FILE);
        if (file_exists(gpg_src)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", gpg_src, gpg_dst);
            run_cmd(cmd);
            log_info("GPG public key copied to eFuse virtual USB");
        }
    }

    /* 6. Unmount + detach. */
    snprintf(cmd, sizeof(cmd), "umount '%s'", mount_point);
    run_cmd(cmd);
    rmdir(mount_point);
    free(mount_point);

    snprintf(cmd, sizeof(cmd), "losetup -d '%s'", loop_dev);
    if (run_cmd(cmd) != 0) {
        log_warn("losetup -d failed for %s (leak - please detach manually)", loop_dev);
    }

    log_info("eFuse virtual USB image created: %s (label: EFUSE_SIM, %d MB)",
             out_path, size_mb);
    log_info("  QEMU:  -drive if=none,id=efuse,format=raw,file=%s -device usb-storage,drive=efuse,bus=ehci.0", out_path);
    log_info("  Flash: sudo dd if=%s of=/dev/sdX bs=4M status=progress", out_path);
    return 0;
}
