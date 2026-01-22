/*
 * hab_iso.c - HAB Secure Boot ISO Builder
 *
 * Creates Secure Boot enabled ISOs for Photon OS
 *
 * This tool:
 * 1. Extracts a Photon OS ISO
 * 2. Replaces EFI boot components with Secure Boot chain
 * 3. Creates new efiboot.img with proper structure
 * 4. Rebuilds the ISO with hybrid boot support
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>

#define HAB_VERSION "1.0"

/* Default paths */
#define HAB_KEYS_DIR "/root/hab_keys"
#define EFIBOOT_SIZE_MB 16

/* Required files */
static const char *required_files[] = {
    "shim-suse.efi",
    "MokManager-suse.efi",
    "hab-preloader-signed.efi",
    "MOK.der",
    NULL
};

/* ANSI colors */
#define RED     "\x1b[31m"
#define GREEN   "\x1b[32m"
#define YELLOW  "\x1b[33m"
#define RESET   "\x1b[0m"

static int verbose = 0;

static void log_info(const char *fmt, ...) {
    va_list args;
    printf(GREEN "[INFO]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

static void log_error(const char *fmt, ...) {
    va_list args;
    fprintf(stderr, RED "[ERROR]" RESET " ");
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
}

static void log_warn(const char *fmt, ...) {
    va_list args;
    printf(YELLOW "[WARN]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

/* Execute a command and return exit status */
static int run_cmd(const char *cmd) {
    if (verbose) {
        printf("  $ %s\n", cmd);
    }
    int ret = system(cmd);
    return WEXITSTATUS(ret);
}

/* Execute command with output capture */
static int run_cmd_output(const char *cmd, char *output, size_t output_size) {
    FILE *fp = popen(cmd, "r");
    if (!fp) return -1;
    
    size_t total = 0;
    while (total < output_size - 1) {
        size_t n = fread(output + total, 1, output_size - total - 1, fp);
        if (n == 0) break;
        total += n;
    }
    output[total] = '\0';
    
    return pclose(fp);
}

/* Check if file exists */
static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

/* Create directory recursively */
static int mkdir_p(const char *path) {
    char tmp[512];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (tmp[len - 1] == '/')
        tmp[len - 1] = 0;
    
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755);
}

/* Copy file */
static int copy_file(const char *src, const char *dst) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", src, dst);
    return run_cmd(cmd);
}

/* Check required HAB files */
static int check_hab_files(const char *keys_dir) {
    char path[512];
    int missing = 0;
    
    log_info("Checking HAB key files...");
    
    for (const char **f = required_files; *f; f++) {
        snprintf(path, sizeof(path), "%s/%s", keys_dir, *f);
        if (!file_exists(path)) {
            log_error("Missing: %s", path);
            missing++;
        }
    }
    
    if (missing) {
        log_error("Run build.sh to generate required files");
        return -1;
    }
    
    log_info("All HAB files present");
    return 0;
}

/* Extract ISO to directory */
static int extract_iso(const char *iso_path, const char *dest_dir) {
    char cmd[1024];
    
    log_info("Extracting ISO: %s", iso_path);
    
    mkdir_p(dest_dir);
    
    snprintf(cmd, sizeof(cmd),
             "xorriso -osirrox on -indev '%s' -extract / '%s' 2>/dev/null",
             iso_path, dest_dir);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to extract ISO");
        return -1;
    }
    
    return 0;
}

/* Create FAT filesystem image */
static int create_fat_image(const char *path, int size_mb) {
    char cmd[1024];
    
    /* Create empty file */
    snprintf(cmd, sizeof(cmd), "dd if=/dev/zero of='%s' bs=1M count=%d 2>/dev/null",
             path, size_mb);
    if (run_cmd(cmd) != 0) return -1;
    
    /* Format as FAT */
    snprintf(cmd, sizeof(cmd), "mkfs.vfat -F 12 -n EFIBOOT '%s' >/dev/null 2>&1", path);
    if (run_cmd(cmd) != 0) return -1;
    
    return 0;
}

/* Update efiboot.img with Secure Boot components */
static int update_efiboot(const char *iso_dir, const char *keys_dir, const char *grub_real) {
    char efiboot_path[512];
    char mount_dir[512];
    char cmd[1024];
    char src[512], dst[512];
    
    snprintf(efiboot_path, sizeof(efiboot_path), "%s/boot/grub2/efiboot.img", iso_dir);
    snprintf(mount_dir, sizeof(mount_dir), "/tmp/hab_efiboot_%d", getpid());
    
    log_info("Updating efiboot.img...");
    
    /* Create new efiboot.img */
    char new_efiboot[512];
    snprintf(new_efiboot, sizeof(new_efiboot), "/tmp/efiboot_new_%d.img", getpid());
    
    if (create_fat_image(new_efiboot, EFIBOOT_SIZE_MB) != 0) {
        log_error("Failed to create FAT image");
        return -1;
    }
    
    /* Mount it */
    mkdir_p(mount_dir);
    snprintf(cmd, sizeof(cmd), "mount -o loop '%s' '%s'", new_efiboot, mount_dir);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to mount efiboot.img");
        return -1;
    }
    
    /* Create directory structure */
    snprintf(dst, sizeof(dst), "%s/EFI/BOOT", mount_dir);
    mkdir_p(dst);
    
    /* Copy SUSE shim as BOOTX64.EFI */
    snprintf(src, sizeof(src), "%s/shim-suse.efi", keys_dir);
    snprintf(dst, sizeof(dst), "%s/EFI/BOOT/BOOTX64.EFI", mount_dir);
    copy_file(src, dst);
    
    /* Copy shimx64.efi to root */
    snprintf(dst, sizeof(dst), "%s/shimx64.efi", mount_dir);
    copy_file(src, dst);
    
    /* Copy HAB PreLoader as grub.efi */
    snprintf(src, sizeof(src), "%s/hab-preloader-signed.efi", keys_dir);
    snprintf(dst, sizeof(dst), "%s/EFI/BOOT/grub.efi", mount_dir);
    copy_file(src, dst);
    
    /* Copy grubx64_real.efi (VMware's GRUB) */
    snprintf(dst, sizeof(dst), "%s/EFI/BOOT/grubx64_real.efi", mount_dir);
    copy_file(grub_real, dst);
    
    /* Copy MokManager to ROOT (SUSE shim looks for \mmx64.efi) */
    snprintf(src, sizeof(src), "%s/MokManager-suse.efi", keys_dir);
    snprintf(dst, sizeof(dst), "%s/mmx64.efi", mount_dir);
    copy_file(src, dst);
    
    /* Also copy MokManager.efi to EFI/BOOT */
    snprintf(dst, sizeof(dst), "%s/EFI/BOOT/MokManager.efi", mount_dir);
    copy_file(src, dst);
    
    /* Copy MOK certificate to ROOT for enrollment */
    snprintf(src, sizeof(src), "%s/MOK.der", keys_dir);
    snprintf(dst, sizeof(dst), "%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer", mount_dir);
    copy_file(src, dst);
    
    /* Create minimal grub.cfg for bootstrap */
    snprintf(dst, sizeof(dst), "%s/EFI/BOOT/grub.cfg", mount_dir);
    FILE *f = fopen(dst, "w");
    if (f) {
        fprintf(f, "search --file --set=root /isolinux/isolinux.cfg\n");
        fprintf(f, "set prefix=($root)/boot/grub2\n");
        fprintf(f, "configfile $prefix/grub.cfg\n");
        fclose(f);
    }
    
    /* Unmount */
    snprintf(cmd, sizeof(cmd), "umount '%s'", mount_dir);
    run_cmd(cmd);
    rmdir(mount_dir);
    
    /* Replace original efiboot.img */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", new_efiboot, efiboot_path);
    run_cmd(cmd);
    unlink(new_efiboot);
    
    log_info("efiboot.img updated (%d MB)", EFIBOOT_SIZE_MB);
    return 0;
}

/* Update ISO root EFI directory */
static int update_iso_efi(const char *iso_dir, const char *keys_dir, const char *grub_real) {
    char src[512], dst[512];
    char efi_boot[512];
    
    log_info("Updating ISO EFI directory...");
    
    snprintf(efi_boot, sizeof(efi_boot), "%s/EFI/BOOT", iso_dir);
    mkdir_p(efi_boot);
    
    /* Copy SUSE shim as BOOTX64.EFI */
    snprintf(src, sizeof(src), "%s/shim-suse.efi", keys_dir);
    snprintf(dst, sizeof(dst), "%s/BOOTX64.EFI", efi_boot);
    copy_file(src, dst);
    
    /* Copy HAB PreLoader as grub.efi */
    snprintf(src, sizeof(src), "%s/hab-preloader-signed.efi", keys_dir);
    snprintf(dst, sizeof(dst), "%s/grub.efi", efi_boot);
    copy_file(src, dst);
    
    /* Copy grubx64_real.efi */
    snprintf(dst, sizeof(dst), "%s/grubx64_real.efi", efi_boot);
    copy_file(grub_real, dst);
    
    /* Copy MokManager to EFI/BOOT */
    snprintf(src, sizeof(src), "%s/MokManager-suse.efi", keys_dir);
    snprintf(dst, sizeof(dst), "%s/MokManager.efi", efi_boot);
    copy_file(src, dst);
    
    /* Copy mmx64.efi to ISO root */
    snprintf(dst, sizeof(dst), "%s/mmx64.efi", iso_dir);
    copy_file(src, dst);
    
    /* Copy MOK certificate to ISO root */
    snprintf(src, sizeof(src), "%s/MOK.der", keys_dir);
    snprintf(dst, sizeof(dst), "%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer", iso_dir);
    copy_file(src, dst);
    
    return 0;
}

/* Build final ISO */
static int build_iso(const char *iso_dir, const char *output_iso) {
    char cmd[2048];
    
    log_info("Building ISO: %s", output_iso);
    
    snprintf(cmd, sizeof(cmd),
        "cd '%s' && xorriso -as mkisofs "
        "-o '%s' "
        "-isohybrid-mbr /usr/share/syslinux/isohdpfx.bin "
        "-c isolinux/boot.cat "
        "-b isolinux/isolinux.bin "
        "-no-emul-boot -boot-load-size 4 -boot-info-table "
        "-eltorito-alt-boot "
        "-e boot/grub2/efiboot.img "
        "-no-emul-boot -isohybrid-gpt-basdat "
        "-V PHOTON_SB "
        ". 2>&1 | tail -3",
        iso_dir, output_iso);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to build ISO");
        return -1;
    }
    
    log_info("ISO created successfully");
    return 0;
}

/* Find VMware GRUB in extracted ISO */
static int find_vmware_grub(const char *iso_dir, char *grub_path, size_t path_size) {
    char path[512];
    
    /* Check common locations - including grubx64_real.efi which our previous builds use */
    const char *locations[] = {
        "EFI/BOOT/grubx64_real.efi",
        "EFI/BOOT/grubx64.efi",
        "EFI/BOOT/GRUBX64.EFI",
        "boot/efi/EFI/BOOT/grubx64.efi",
        NULL
    };
    
    for (const char **loc = locations; *loc; loc++) {
        snprintf(path, sizeof(path), "%s/%s", iso_dir, *loc);
        if (file_exists(path)) {
            /* Verify it's VMware signed (case insensitive) */
            char cmd[1024], output[256];
            snprintf(cmd, sizeof(cmd), "sbverify --list '%s' 2>&1 | grep -i -E 'vmware|photon'", path);
            if (run_cmd_output(cmd, output, sizeof(output)) == 0 && strlen(output) > 0) {
                strncpy(grub_path, path, path_size - 1);
                grub_path[path_size - 1] = '\0';
                return 0;
            }
            /* Also accept if the file exists and is signed (any signature) */
            snprintf(cmd, sizeof(cmd), "sbverify --list '%s' 2>&1 | grep -q 'signature'", path);
            if (run_cmd(cmd) == 0) {
                log_warn("Found signed GRUB (not VMware): %s", path);
                strncpy(grub_path, path, path_size - 1);
                grub_path[path_size - 1] = '\0';
                return 0;
            }
        }
    }
    
    log_error("Signed GRUB not found in ISO");
    return -1;
}

/* Main ISO fix function */
static int fix_iso(const char *input_iso, const char *output_iso, const char *keys_dir) {
    char iso_dir[512];
    char grub_real[512];
    int ret = -1;
    
    /* Create temp directory - use /root to avoid tmpfs space issues */
    snprintf(iso_dir, sizeof(iso_dir), "/root/tmp_hab_iso_%d", getpid());
    
    /* Check HAB files */
    if (check_hab_files(keys_dir) != 0) {
        return -1;
    }
    
    /* Extract ISO */
    if (extract_iso(input_iso, iso_dir) != 0) {
        goto cleanup;
    }
    
    /* Find VMware GRUB */
    if (find_vmware_grub(iso_dir, grub_real, sizeof(grub_real)) != 0) {
        log_warn("Using VMware GRUB from EFI/BOOT/grubx64.efi");
        snprintf(grub_real, sizeof(grub_real), "%s/EFI/BOOT/grubx64.efi", iso_dir);
        if (!file_exists(grub_real)) {
            log_error("No GRUB found in ISO");
            goto cleanup;
        }
    }
    
    log_info("VMware GRUB: %s", grub_real);
    
    /* Update efiboot.img */
    if (update_efiboot(iso_dir, keys_dir, grub_real) != 0) {
        goto cleanup;
    }
    
    /* Update ISO EFI directory */
    if (update_iso_efi(iso_dir, keys_dir, grub_real) != 0) {
        goto cleanup;
    }
    
    /* Build final ISO */
    if (build_iso(iso_dir, output_iso) != 0) {
        goto cleanup;
    }
    
    ret = 0;
    
cleanup:
    /* Clean up temp directory */
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", iso_dir);
    run_cmd(cmd);
    
    return ret;
}

static void usage(const char *prog) {
    printf("HAB Secure Boot ISO Builder v%s\n\n", HAB_VERSION);
    printf("Usage: %s [options] <input.iso> <output.iso>\n\n", prog);
    printf("Options:\n");
    printf("  -k <dir>    HAB keys directory (default: %s)\n", HAB_KEYS_DIR);
    printf("  -v          Verbose output\n");
    printf("  -h          Show this help\n");
    printf("\nExample:\n");
    printf("  %s photon-5.0.iso photon-5.0-secureboot.iso\n", prog);
}

int main(int argc, char *argv[]) {
    const char *keys_dir = HAB_KEYS_DIR;
    int opt;
    
    while ((opt = getopt(argc, argv, "k:vh")) != -1) {
        switch (opt) {
        case 'k':
            keys_dir = optarg;
            break;
        case 'v':
            verbose = 1;
            break;
        case 'h':
            usage(argv[0]);
            return 0;
        default:
            usage(argv[0]);
            return 1;
        }
    }
    
    if (optind + 2 > argc) {
        usage(argv[0]);
        return 1;
    }
    
    const char *input_iso = argv[optind];
    const char *output_iso = argv[optind + 1];
    
    if (!file_exists(input_iso)) {
        log_error("Input ISO not found: %s", input_iso);
        return 1;
    }
    
    log_info("HAB Secure Boot ISO Builder v%s", HAB_VERSION);
    log_info("Input:  %s", input_iso);
    log_info("Output: %s", output_iso);
    log_info("Keys:   %s", keys_dir);
    
    if (fix_iso(input_iso, output_iso, keys_dir) != 0) {
        log_error("ISO creation failed");
        return 1;
    }
    
    log_info("Done!");
    return 0;
}
