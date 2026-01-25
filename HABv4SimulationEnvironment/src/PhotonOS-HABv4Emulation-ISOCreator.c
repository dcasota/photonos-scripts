/*
 * PhotonOS-HABv4Emulation-ISOCreator.c
 *
 * Complete HABv4 Secure Boot simulation environment and ISO creator for Photon OS.
 * Replaces the bash-based HABv4-installer.sh with a native C implementation.
 *
 * Features:
 *   - Key generation (PK, KEK, DB, MOK, SRK, CSF, IMG)
 *   - eFuse simulation
 *   - Ventoy component download (SUSE shim, MokManager)
 *   - Secure Boot ISO creation
 *   - eFuse USB dongle creation
 *   - Full kernel build support (optional)
 *   - eFuse USB verification mode
 *
 * Usage:
 *   PhotonOS-HABv4Emulation-ISOCreator [OPTIONS]
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/utsname.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <time.h>

#include "rpm_secureboot_patcher.h"

#define VERSION "1.5.0"
#define PROGRAM_NAME "PhotonOS-HABv4Emulation-ISOCreator"

/* Default configuration */
#define DEFAULT_RELEASE "5.0"
#define DEFAULT_MOK_DAYS 180
#define DEFAULT_KEYS_DIR "/root/hab_keys"
#define DEFAULT_EFUSE_DIR "/root/efuse_sim"
#define DEFAULT_EFIBOOT_SIZE_MB 16

#define VENTOY_VERSION "1.1.10"
#define VENTOY_URL "https://github.com/ventoy/Ventoy/releases/download/v" VENTOY_VERSION "/ventoy-" VENTOY_VERSION "-linux.tar.gz"

/* ANSI colors */
#define RED     "\x1b[31m"
#define GREEN   "\x1b[32m"
#define YELLOW  "\x1b[33m"
#define BLUE    "\x1b[34m"
#define CYAN    "\x1b[36m"
#define RESET   "\x1b[0m"

/* GPG key configuration for RPM signing */
#define GPG_KEY_NAME "HABv4 RPM Signing Key"
#define GPG_KEY_EMAIL "habv4-rpm@local"
#define GPG_KEY_FILE "RPM-GPG-KEY-habv4"

/* Configuration structure */
typedef struct {
    char release[16];
    char keys_dir[512];
    char efuse_dir[512];
    char photon_dir[512];
    char input_iso[512];
    char output_iso[512];
    char efuse_usb_device[128];
    char diagnose_iso_path[512];
    int mok_days;
    int build_iso;
    int generate_keys;
    int setup_efuse;
    int full_kernel_build;
    int efuse_usb_mode;
    int rpm_signing;          /* Enable GPG signing of MOK RPM packages */
    int cleanup;
    int verbose;
    int yes_to_all;
} config_t;

/* Global config */
static config_t cfg;

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

static void log_info(const char *fmt, ...) {
    va_list args;
    printf(GREEN "[INFO]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

static void log_step(const char *fmt, ...) {
    va_list args;
    printf(BLUE "[STEP]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

static void log_warn(const char *fmt, ...) {
    va_list args;
    printf(YELLOW "[WARN]" RESET " ");
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

static int run_cmd(const char *cmd) {
    if (cfg.verbose) {
        printf("  $ %s\n", cmd);
    }
    int ret = system(cmd);
    return WEXITSTATUS(ret);
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static int dir_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

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

static long get_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return st.st_size;
}

static const char *get_host_arch(void) {
    struct utsname uts;
    if (uname(&uts) == 0) {
        if (strcmp(uts.machine, "x86_64") == 0) return "x86_64";
        if (strcmp(uts.machine, "aarch64") == 0) return "aarch64";
    }
    return "unknown";
}

/* ============================================================================
 * Key Generation
 * ============================================================================ */

static int generate_key_pair(const char *name, const char *subject, int bits, int days) {
    char cmd[1024];
    char key_path[512], crt_path[512], der_path[512];
    
    snprintf(key_path, sizeof(key_path), "%s/%s.key", cfg.keys_dir, name);
    snprintf(crt_path, sizeof(crt_path), "%s/%s.crt", cfg.keys_dir, name);
    snprintf(der_path, sizeof(der_path), "%s/%s.der", cfg.keys_dir, name);
    
    if (file_exists(key_path)) {
        if (cfg.verbose) log_info("%s key already exists", name);
        return 0;
    }
    
    snprintf(cmd, sizeof(cmd),
        "openssl req -new -x509 -newkey rsa:%d -nodes "
        "-keyout '%s' -out '%s' -days %d "
        "-subj '%s' 2>/dev/null",
        bits, key_path, crt_path, days, subject);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate %s key", name);
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd),
        "openssl x509 -in '%s' -outform DER -out '%s' 2>/dev/null",
        crt_path, der_path);
    run_cmd(cmd);
    
    log_info("Generated %s key", name);
    return 0;
}

static int generate_mok_key(void) {
    char cmd[2048];
    char key_path[512], crt_path[512], der_path[512], cnf_path[512];
    
    snprintf(key_path, sizeof(key_path), "%s/MOK.key", cfg.keys_dir);
    snprintf(crt_path, sizeof(crt_path), "%s/MOK.crt", cfg.keys_dir);
    snprintf(der_path, sizeof(der_path), "%s/MOK.der", cfg.keys_dir);
    snprintf(cnf_path, sizeof(cnf_path), "/tmp/mok_%d.cnf", getpid());
    
    if (file_exists(key_path)) {
        if (cfg.verbose) log_info("MOK key already exists");
        return 0;
    }
    
    FILE *f = fopen(cnf_path, "w");
    if (!f) {
        log_error("Failed to create MOK config");
        return -1;
    }
    
    fprintf(f,
        "[ req ]\n"
        "default_bits = 2048\n"
        "distinguished_name = req_dn\n"
        "prompt = no\n"
        "x509_extensions = v3_ext\n"
        "\n"
        "[ req_dn ]\n"
        "CN = HABv4 Secure Boot MOK\n"
        "O = HABv4\n"
        "C = US\n"
        "\n"
        "[ v3_ext ]\n"
        "subjectKeyIdentifier = hash\n"
        "authorityKeyIdentifier = keyid:always,issuer\n"
        "basicConstraints = critical, CA:FALSE\n"
        "keyUsage = critical, digitalSignature\n"
        "extendedKeyUsage = codeSigning\n"
    );
    fclose(f);
    
    snprintf(cmd, sizeof(cmd),
        "openssl req -new -x509 -newkey rsa:2048 -nodes "
        "-keyout '%s' -out '%s' -days %d -config '%s' 2>/dev/null",
        key_path, crt_path, cfg.mok_days, cnf_path);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate MOK key");
        unlink(cnf_path);
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd),
        "openssl x509 -in '%s' -outform DER -out '%s' 2>/dev/null",
        crt_path, der_path);
    run_cmd(cmd);
    
    unlink(cnf_path);
    log_info("Generated MOK key (validity: %d days)", cfg.mok_days);
    return 0;
}

static int generate_srk_key(void) {
    char cmd[1024];
    char pem_path[512], pub_path[512], hash_path[512];
    
    snprintf(pem_path, sizeof(pem_path), "%s/srk.pem", cfg.keys_dir);
    snprintf(pub_path, sizeof(pub_path), "%s/srk_pub.pem", cfg.keys_dir);
    snprintf(hash_path, sizeof(hash_path), "%s/srk_hash.bin", cfg.keys_dir);
    
    if (file_exists(pem_path)) {
        if (cfg.verbose) log_info("SRK key already exists");
        return 0;
    }
    
    snprintf(cmd, sizeof(cmd), "openssl genrsa -out '%s' 4096 2>/dev/null", pem_path);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate SRK key");
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd), 
        "openssl rsa -in '%s' -pubout -out '%s' 2>/dev/null", pem_path, pub_path);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd),
        "openssl dgst -sha256 -binary '%s' > '%s'", pub_path, hash_path);
    run_cmd(cmd);
    
    log_info("Generated SRK key");
    return 0;
}

static int generate_simple_key(const char *name, int bits) {
    char cmd[1024];
    char pem_path[512], pub_path[512];
    
    snprintf(pem_path, sizeof(pem_path), "%s/%s.pem", cfg.keys_dir, name);
    snprintf(pub_path, sizeof(pub_path), "%s/%s_pub.pem", cfg.keys_dir, name);
    
    if (file_exists(pem_path)) {
        if (cfg.verbose) log_info("%s key already exists", name);
        return 0;
    }
    
    snprintf(cmd, sizeof(cmd), "openssl genrsa -out '%s' %d 2>/dev/null", pem_path, bits);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate %s key", name);
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd),
        "openssl rsa -in '%s' -pubout -out '%s' 2>/dev/null", pem_path, pub_path);
    run_cmd(cmd);
    
    log_info("Generated %s key", name);
    return 0;
}

static int generate_all_keys(void) {
    log_step("Generating cryptographic keys...");
    
    mkdir_p(cfg.keys_dir);
    
    if (generate_key_pair("PK", "/CN=HABv4 Platform Key/O=HABv4/C=US", 2048, 3650) != 0)
        return -1;
    if (generate_key_pair("KEK", "/CN=HABv4 Key Exchange Key/O=HABv4/C=US", 2048, 3650) != 0)
        return -1;
    if (generate_key_pair("DB", "/CN=HABv4 Signature Database Key/O=HABv4/C=US", 2048, 3650) != 0)
        return -1;
    
    if (generate_mok_key() != 0)
        return -1;
    
    if (generate_srk_key() != 0)
        return -1;
    if (generate_simple_key("csf", 2048) != 0)
        return -1;
    if (generate_simple_key("img", 2048) != 0)
        return -1;
    
    char cmd[1024];
    char kmod_path[512];
    snprintf(kmod_path, sizeof(kmod_path), "%s/kernel_module_signing.pem", cfg.keys_dir);
    if (!file_exists(kmod_path)) {
        snprintf(cmd, sizeof(cmd),
            "openssl req -new -x509 -newkey rsa:4096 -nodes "
            "-keyout '%s' -out '%s' -days 3650 "
            "-subj '/CN=HABv4 Kernel Module Signing/O=HABv4/C=US' 2>/dev/null",
            kmod_path, kmod_path);
        run_cmd(cmd);
        log_info("Generated kernel module signing key");
    }
    
    log_info("All keys generated in %s", cfg.keys_dir);
    return 0;
}

/* ============================================================================
 * GPG Key Generation for RPM Signing
 * ============================================================================ */

static int generate_gpg_keys(void) {
    char gpg_pub[512], gpg_home[512], gpg_batch[512];
    char cmd[2048];
    
    snprintf(gpg_pub, sizeof(gpg_pub), "%s/%s", cfg.keys_dir, GPG_KEY_FILE);
    snprintf(gpg_home, sizeof(gpg_home), "%s/.gnupg", cfg.keys_dir);
    
    /* Check if GPG key already exists */
    if (file_exists(gpg_pub)) {
        log_info("GPG key already exists: %s", gpg_pub);
        return 0;
    }
    
    log_step("Generating GPG key pair for RPM signing...");
    
    /* Create GNUPGHOME directory */
    mkdir_p(gpg_home);
    snprintf(cmd, sizeof(cmd), "chmod 700 '%s'", gpg_home);
    run_cmd(cmd);
    
    /* Create batch file for unattended key generation */
    snprintf(gpg_batch, sizeof(gpg_batch), "%s/gpg_batch.txt", cfg.keys_dir);
    FILE *f = fopen(gpg_batch, "w");
    if (!f) {
        log_error("Failed to create GPG batch file");
        return -1;
    }
    
    fprintf(f,
        "%%echo Generating %s\n"
        "Key-Type: RSA\n"
        "Key-Length: 4096\n"
        "Key-Usage: sign\n"
        "Name-Real: %s\n"
        "Name-Email: %s\n"
        "Expire-Date: 0\n"
        "%%no-protection\n"
        "%%commit\n"
        "%%echo Done\n",
        GPG_KEY_NAME, GPG_KEY_NAME, GPG_KEY_EMAIL
    );
    fclose(f);
    
    /* Generate key */
    snprintf(cmd, sizeof(cmd), 
        "GNUPGHOME='%s' gpg --batch --gen-key '%s' 2>/dev/null",
        gpg_home, gpg_batch);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate GPG key");
        unlink(gpg_batch);
        return -1;
    }
    
    /* Export public key (ASCII armored) */
    snprintf(cmd, sizeof(cmd),
        "GNUPGHOME='%s' gpg --export --armor '%s' > '%s' 2>/dev/null",
        gpg_home, GPG_KEY_NAME, gpg_pub);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to export GPG public key");
        unlink(gpg_batch);
        return -1;
    }
    
    /* Cleanup batch file */
    unlink(gpg_batch);
    
    log_info("GPG key pair generated: %s", GPG_KEY_NAME);
    log_info("Public key exported to: %s", gpg_pub);
    return 0;
}

/* ============================================================================
 * eFuse Simulation
 * ============================================================================ */

static int setup_efuse_simulation(void) {
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

static int create_efuse_usb(const char *device) {
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
    
    char mount_point[256];
    snprintf(mount_point, sizeof(mount_point), "/tmp/habefuse_%d", getpid());
    mkdir_p(mount_point);
    
    snprintf(cmd, sizeof(cmd), "mount '%s' '%s'", partition, mount_point);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to mount partition");
        rmdir(mount_point);
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
    
    log_info("eFuse USB dongle created on %s (label: EFUSE_SIM)", device);
    return 0;
}

/* ============================================================================
 * Ventoy Components
 * ============================================================================ */

/* Forward declaration */
static int download_ventoy_components_fallback(void);

/* Get the directory containing the executable */
static void get_executable_dir(char *dir, size_t size) {
    char path[512];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (len > 0) {
        path[len] = '\0';
        char *last_slash = strrchr(path, '/');
        if (last_slash) {
            *last_slash = '\0';
            strncpy(dir, path, size - 1);
            dir[size - 1] = '\0';
            return;
        }
    }
    strncpy(dir, ".", size - 1);
}

static int extract_embedded_shim_components(void) {
    log_step("Extracting embedded SUSE shim components...");
    
    char shim_path[512], mok_path[512];
    snprintf(shim_path, sizeof(shim_path), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mok_path, sizeof(mok_path), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    if (file_exists(shim_path) && file_exists(mok_path)) {
        log_info("SUSE shim components already exist");
        return 0;
    }
    
    /* Find embedded data files relative to executable */
    char exe_dir[512], data_dir[512];
    get_executable_dir(exe_dir, sizeof(exe_dir));
    snprintf(data_dir, sizeof(data_dir), "%s/../data", exe_dir);
    
    char shim_gz[512], mok_gz[512];
    snprintf(shim_gz, sizeof(shim_gz), "%s/shim-suse.efi.gz", data_dir);
    snprintf(mok_gz, sizeof(mok_gz), "%s/MokManager-suse.efi.gz", data_dir);
    
    char cmd[1024];
    
    if (file_exists(shim_gz) && file_exists(mok_gz)) {
        log_info("Using embedded SUSE shim components");
        
        snprintf(cmd, sizeof(cmd), "gunzip -c '%s' > '%s'", shim_gz, shim_path);
        if (run_cmd(cmd) != 0) {
            log_error("Failed to extract shim-suse.efi");
            return -1;
        }
        
        snprintf(cmd, sizeof(cmd), "gunzip -c '%s' > '%s'", mok_gz, mok_path);
        if (run_cmd(cmd) != 0) {
            log_error("Failed to extract MokManager-suse.efi");
            return -1;
        }
        
        log_info("Extracted shim-suse.efi");
        log_info("Extracted MokManager-suse.efi");
        return 0;
    }
    
    log_warn("Embedded shim components not found at %s", data_dir);
    log_info("Falling back to Ventoy download...");
    
    /* Fallback: download from Ventoy if embedded files not found */
    return download_ventoy_components_fallback();
}

static int download_ventoy_components_fallback(void) {
    log_step("Downloading Ventoy components (fallback)...");
    
    char shim_path[512], mok_path[512];
    snprintf(shim_path, sizeof(shim_path), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mok_path, sizeof(mok_path), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    char work_dir[256];
    snprintf(work_dir, sizeof(work_dir), "/tmp/ventoy_%d", getpid());
    mkdir_p(work_dir);
    
    char cmd[2048];
    
    log_info("Downloading Ventoy %s...", VENTOY_VERSION);
    snprintf(cmd, sizeof(cmd),
        "wget -q --show-progress -O '%s/ventoy.tar.gz' '%s'",
        work_dir, VENTOY_URL);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to download Ventoy");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd), "cd '%s' && tar -xzf ventoy.tar.gz", work_dir);
    run_cmd(cmd);
    
    char disk_img[512], mount_point[256];
    snprintf(disk_img, sizeof(disk_img), "%s/ventoy-%s/ventoy/ventoy.disk.img", work_dir, VENTOY_VERSION);
    snprintf(mount_point, sizeof(mount_point), "%s/mnt", work_dir);
    
    char xz_img[520];
    snprintf(xz_img, sizeof(xz_img), "%s.xz", disk_img);
    if (file_exists(xz_img)) {
        snprintf(cmd, sizeof(cmd), "xz -dk '%s'", xz_img);
        run_cmd(cmd);
    }
    
    if (file_exists(disk_img)) {
        mkdir_p(mount_point);
        snprintf(cmd, sizeof(cmd), "mount -o loop,ro '%s' '%s'", disk_img, mount_point);
        
        if (run_cmd(cmd) == 0) {
            snprintf(cmd, sizeof(cmd), "cp '%s/EFI/BOOT/BOOTX64.EFI' '%s/shim-suse.efi'",
                mount_point, cfg.keys_dir);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "cp '%s/EFI/BOOT/MokManager.efi' '%s/MokManager-suse.efi'",
                mount_point, cfg.keys_dir);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "umount '%s'", mount_point);
            run_cmd(cmd);
        }
    }
    
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
    run_cmd(cmd);
    
    if (file_exists(shim_path)) {
        log_info("SUSE shim downloaded");
        log_info("MokManager downloaded");
    } else {
        log_error("Failed to extract Ventoy components");
        return -1;
    }
    
    return 0;
}

/* ============================================================================
 * Full Kernel Build (Restored from bash script)
 * ============================================================================ */

static int build_linux_kernel(void) {
    const char *arch = get_host_arch();
    
    log_step("Linux %s kernel build...", arch);
    
    if (!cfg.full_kernel_build) {
        log_info("Skipping full kernel build (use --full-kernel-build to enable)");
        log_info("Note: Full kernel build takes several hours");
        return 0;
    }
    
    log_warn("Full kernel build requested - this will take several hours!");
    printf("\n");
    printf("The full kernel build process includes:\n");
    printf("  1. Downloading kernel source from kernel.org\n");
    printf("  2. Configuring kernel with Secure Boot options\n");
    printf("  3. Building kernel and modules\n");
    printf("  4. Signing kernel with MOK key\n");
    printf("  5. Signing all modules with kernel module signing key\n");
    printf("\n");
    
    char kernel_dir[512];
    snprintf(kernel_dir, sizeof(kernel_dir), "%s/linux-%s", cfg.photon_dir, arch);
    
    if (strcmp(arch, "x86_64") == 0) {
        log_step("Building Linux kernel for x86_64...");
        
        /* Check for kernel source */
        if (!file_exists(kernel_dir)) {
            log_info("Kernel source not found at %s", kernel_dir);
            log_info("To build kernel manually:");
            printf("  1. git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git %s\n", kernel_dir);
            printf("  2. cd %s\n", kernel_dir);
            printf("  3. make defconfig\n");
            printf("  4. Enable CONFIG_MODULE_SIG=y, CONFIG_MODULE_SIG_ALL=y\n");
            printf("  5. Copy %s/kernel_module_signing.pem to certs/signing_key.pem\n", cfg.keys_dir);
            printf("  6. make -j$(nproc)\n");
            printf("  7. Sign vmlinuz with sbsign using MOK.key\n");
            return 0;
        }
        
        char cmd[2048];
        
        /* Copy signing key */
        snprintf(cmd, sizeof(cmd), "cp '%s/kernel_module_signing.pem' '%s/certs/signing_key.pem'",
            cfg.keys_dir, kernel_dir);
        run_cmd(cmd);
        
        /* Build kernel */
        snprintf(cmd, sizeof(cmd), "cd '%s' && make -j$(nproc)", kernel_dir);
        log_info("Running: make -j$(nproc) in %s", kernel_dir);
        log_warn("This will take a long time...");
        
        if (run_cmd(cmd) != 0) {
            log_error("Kernel build failed");
            return -1;
        }
        
        /* Sign kernel */
        char vmlinuz[512], vmlinuz_signed[512];
        snprintf(vmlinuz, sizeof(vmlinuz), "%s/arch/x86/boot/bzImage", kernel_dir);
        snprintf(vmlinuz_signed, sizeof(vmlinuz_signed), "%s/vmlinuz-signed", kernel_dir);
        
        if (file_exists(vmlinuz)) {
            snprintf(cmd, sizeof(cmd),
                "sbsign --key '%s/MOK.key' --cert '%s/MOK.crt' --output '%s' '%s'",
                cfg.keys_dir, cfg.keys_dir, vmlinuz_signed, vmlinuz);
            run_cmd(cmd);
            log_info("Kernel signed: %s", vmlinuz_signed);
        }
        
        log_info("x86_64 kernel build complete");
        
    } else if (strcmp(arch, "aarch64") == 0) {
        log_step("Building Linux kernel for aarch64...");
        
        if (!file_exists(kernel_dir)) {
            log_info("Kernel source not found at %s", kernel_dir);
            log_info("For aarch64, consider using linux-imx:");
            printf("  git clone --depth 1 -b lf-6.6.y https://github.com/nxp-imx/linux-imx.git %s\n", kernel_dir);
            return 0;
        }
        
        char cmd[2048];
        snprintf(cmd, sizeof(cmd), "cd '%s' && make -j$(nproc) Image", kernel_dir);
        log_info("Running: make -j$(nproc) Image in %s", kernel_dir);
        
        if (run_cmd(cmd) != 0) {
            log_error("Kernel build failed");
            return -1;
        }
        
        log_info("aarch64 kernel build complete");
        
    } else {
        log_warn("Unknown architecture: %s", arch);
        return -1;
    }
    
    return 0;
}

/* ============================================================================
 * ISO Creation
 * ============================================================================ */

static int find_base_iso(char *iso_path, size_t path_size) {
    char iso_dir[512];
    snprintf(iso_dir, sizeof(iso_dir), "%s/stage", cfg.photon_dir);
    mkdir_p(iso_dir);
    
    DIR *dir = opendir(iso_dir);
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (strstr(entry->d_name, "photon-") && 
                strstr(entry->d_name, ".iso") &&
                strstr(entry->d_name, "-secureboot") == NULL) {
                snprintf(iso_path, path_size, "%s/%s", iso_dir, entry->d_name);
                closedir(dir);
                return 0;
            }
        }
        closedir(dir);
    }
    
    log_info("No base ISO found, attempting download...");
    
    const char *iso_name;
    if (strcmp(cfg.release, "5.0") == 0) {
        iso_name = "photon-5.0-dde71ec57.x86_64.iso";
    } else if (strcmp(cfg.release, "4.0") == 0) {
        iso_name = "photon-4.0-ca7c9e933.iso";
    } else if (strcmp(cfg.release, "6.0") == 0) {
        iso_name = "photon-6.0-minimal.iso";
    } else {
        log_error("Unknown Photon OS release: %s", cfg.release);
        return -1;
    }
    
    snprintf(iso_path, path_size, "%s/%s", iso_dir, iso_name);
    
    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
        "wget -q --show-progress -O '%s' "
        "'https://packages.vmware.com/photon/%s/GA/iso/%s'",
        iso_path, cfg.release, iso_name);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to download ISO");
        log_info("Please place a Photon OS ISO in %s/", iso_dir);
        return -1;
    }
    
    return 0;
}

static int create_secure_boot_iso(void) {
    log_step("Creating Secure Boot ISO...");
    
    char base_iso[512];
    
    if (strlen(cfg.input_iso) > 0) {
        strncpy(base_iso, cfg.input_iso, sizeof(base_iso) - 1);
        if (!file_exists(base_iso)) {
            log_error("Input ISO not found: %s", base_iso);
            return -1;
        }
    } else {
        if (find_base_iso(base_iso, sizeof(base_iso)) != 0) {
            return -1;
        }
    }
    
    log_info("Base ISO: %s", base_iso);
    
    char output_iso[512];
    if (strlen(cfg.output_iso) > 0) {
        strncpy(output_iso, cfg.output_iso, sizeof(output_iso) - 1);
    } else {
        strncpy(output_iso, base_iso, sizeof(output_iso) - 1);
        char *ext = strstr(output_iso, ".iso");
        if (ext) {
            strcpy(ext, "-secureboot.iso");
        }
    }
    
    /* MOK key paths for signing custom GRUB stub and kernel */
    char mok_key[512], mok_crt[512];
    snprintf(mok_key, sizeof(mok_key), "%s/MOK.key", cfg.keys_dir);
    snprintf(mok_crt, sizeof(mok_crt), "%s/MOK.crt", cfg.keys_dir);
    
    char shim_path[512], mokm_path[512];
    snprintf(shim_path, sizeof(shim_path), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mokm_path, sizeof(mokm_path), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    /* Auto-extract embedded SUSE shim components if missing */
    if (!file_exists(shim_path) || !file_exists(mokm_path)) {
        if (extract_embedded_shim_components() != 0) {
            log_error("Failed to extract SUSE shim components");
            return -1;
        }
    }
    
    char work_dir[256], iso_extract[512], efi_mount[256];
    snprintf(work_dir, sizeof(work_dir), "/root/tmp_iso_%d", getpid());
    snprintf(iso_extract, sizeof(iso_extract), "%s/iso", work_dir);
    snprintf(efi_mount, sizeof(efi_mount), "%s/efi", work_dir);
    
    mkdir_p(iso_extract);
    mkdir_p(efi_mount);
    
    char cmd[2048];
    
    log_info("Extracting ISO...");
    snprintf(cmd, sizeof(cmd), "xorriso -osirrox on -indev '%s' -extract / '%s' 2>/dev/null",
        base_iso, iso_extract);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to extract ISO");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        return -1;
    }
    
    /* Get VMware's original GRUB for "VMware Original" boot option
     * VMware's GRUB is inside efiboot.img, need to extract it */
    char vmware_grub[512];
    char orig_efiboot[512], efi_extract[512];
    snprintf(orig_efiboot, sizeof(orig_efiboot), "%s/boot/grub2/efiboot.img", iso_extract);
    snprintf(efi_extract, sizeof(efi_extract), "%s/efi_orig", work_dir);
    snprintf(vmware_grub, sizeof(vmware_grub), "%s/vmware_grub.efi", work_dir);
    
    mkdir_p(efi_extract);
    if (file_exists(orig_efiboot)) {
        snprintf(cmd, sizeof(cmd), "mount -o loop '%s' '%s' 2>/dev/null", orig_efiboot, efi_extract);
        if (run_cmd(cmd) == 0) {
            char efi_grub[512];
            snprintf(efi_grub, sizeof(efi_grub), "%s/EFI/BOOT/grubx64.efi", efi_extract);
            if (file_exists(efi_grub)) {
                snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", efi_grub, vmware_grub);
                run_cmd(cmd);
                log_info("Extracted VMware's GRUB from efiboot.img");
            }
            snprintf(cmd, sizeof(cmd), "umount '%s' 2>/dev/null", efi_extract);
            run_cmd(cmd);
        }
    }
    
    /* Sign kernel with MOK key for Custom MOK boot option
     * This allows the unsigned Photon OS kernel to be trusted by shim
     * after the user enrolls our MOK certificate */
    char kernel_path[512];
    char signed_kernel[512];
    snprintf(kernel_path, sizeof(kernel_path), "%s/isolinux/vmlinuz", iso_extract);
    snprintf(signed_kernel, sizeof(signed_kernel), "%s/vmlinuz-signed", work_dir);
    
    if (file_exists(mok_key) && file_exists(mok_crt) && file_exists(kernel_path)) {
        log_info("Signing kernel with MOK key...");
        snprintf(cmd, sizeof(cmd), "sbsign --key '%s' --cert '%s' --output '%s' '%s' 2>/dev/null",
            mok_key, mok_crt, signed_kernel, kernel_path);
        if (run_cmd(cmd) == 0 && file_exists(signed_kernel)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", signed_kernel, kernel_path);
            run_cmd(cmd);
            log_info("Kernel signed with MOK key (CN=HABv4 Secure Boot MOK)");
        } else {
            log_warn("Failed to sign kernel - will use unsigned kernel");
        }
    }
    
    /* Create kickstart files for MOK and Standard installations
     * The kickstart approach with ui:true provides interactive installation
     * while enforcing the correct package selection. We also patch the
     * installer to fix the progress_bar AttributeError bug. */
    log_info("Creating kickstart files and patching installer...");
    
    /* Create MOK kickstart on ISO root */
    char mok_ks_path[512], std_ks_path[512];
    snprintf(mok_ks_path, sizeof(mok_ks_path), "%s/mok_ks.cfg", iso_extract);
    snprintf(std_ks_path, sizeof(std_ks_path), "%s/standard_ks.cfg", iso_extract);
    
    /* Create MOK kickstart - uses MOK-signed packages */
    FILE *f = fopen(mok_ks_path, "w");
    if (f) {
        fprintf(f,
            "{\n"
            "    \"hostname\": \"photon-mok\",\n"
            "    \"password\": {\n"
            "        \"crypted\": false,\n"
            "        \"text\": \"changeme\"\n"
            "    },\n"
            "    \"disk\": \"/dev/sda\",\n"
            "    \"partitions\": [\n"
            "        {\"mountpoint\": \"/\", \"size\": 0, \"filesystem\": \"ext4\"},\n"
            "        {\"mountpoint\": \"/boot\", \"size\": 300, \"filesystem\": \"ext4\"},\n"
            "        {\"size\": 256, \"filesystem\": \"swap\"}\n"
            "    ],\n"
            "    \"bootmode\": \"efi\",\n"
            "    \"linux_flavor\": \"linux-mok\",\n"
            "    \"packages\": [\n"
            "        \"minimal\",\n"
            "        \"initramfs\",\n"
            "        \"linux-mok\",\n"
            "        \"grub2-efi-image-mok\",\n"
            "        \"shim-signed-mok\"\n"
            "    ],\n"
            "    \"postinstall\": [\n"
            "        \"#!/bin/sh\",\n"
            "        \"echo 'Photon OS installed with MOK Secure Boot support' > /etc/mok-secureboot\",\n"
        );
        
        /* Add GPG key import if RPM signing is enabled */
        if (cfg.rpm_signing) {
            fprintf(f,
                "        \"rpm --import /cdrom/%s\",\n"
                "        \"echo 'gpgcheck=1' >> /etc/yum.repos.d/photon.repo\",\n"
                "        \"echo 'GPG key imported for MOK RPM verification' >> /etc/mok-secureboot\",\n",
                GPG_KEY_FILE
            );
        }
        
        fprintf(f,
            "        \"echo 'Remember to enroll MOK key on first boot if not already done' >> /etc/mok-secureboot\"\n"
            "    ],\n"
            "    \"ui\": true\n"
            "}\n"
        );
        fclose(f);
        log_info("Created MOK kickstart: mok_ks.cfg");
    }
    
    /* Create standard kickstart - uses original VMware packages */
    f = fopen(std_ks_path, "w");
    if (f) {
        fprintf(f,
            "{\n"
            "    \"hostname\": \"photon-standard\",\n"
            "    \"password\": {\n"
            "        \"crypted\": false,\n"
            "        \"text\": \"changeme\"\n"
            "    },\n"
            "    \"disk\": \"/dev/sda\",\n"
            "    \"partitions\": [\n"
            "        {\"mountpoint\": \"/\", \"size\": 0, \"filesystem\": \"ext4\"},\n"
            "        {\"mountpoint\": \"/boot\", \"size\": 300, \"filesystem\": \"ext4\"},\n"
            "        {\"size\": 256, \"filesystem\": \"swap\"}\n"
            "    ],\n"
            "    \"bootmode\": \"efi\",\n"
            "    \"linux_flavor\": \"linux\",\n"
            "    \"packages\": [\n"
            "        \"minimal\",\n"
            "        \"initramfs\",\n"
            "        \"linux\",\n"
            "        \"grub2-efi-image\",\n"
            "        \"shim-signed\"\n"
            "    ],\n"
            "    \"ui\": true\n"
            "}\n"
        );
        fclose(f);
        log_info("Created standard kickstart: standard_ks.cfg");
    }
    
    /* Extract initrd to patch the installer for progress_bar bug fix
     * Bug: When ui:true in kickstart, installer crashes with AttributeError
     * if exception occurs before progress_bar is created.
     * Fix: Initialize progress_bar=None and add null checks before access */
    char initrd_extract[512], initrd_orig[512], initrd_new[512];
    snprintf(initrd_extract, sizeof(initrd_extract), "%s/initrd_mod", work_dir);
    snprintf(initrd_orig, sizeof(initrd_orig), "%s/isolinux/initrd.img", iso_extract);
    snprintf(initrd_new, sizeof(initrd_new), "%s/initrd_new.img", work_dir);
    
    snprintf(cmd, sizeof(cmd), "mkdir -p '%s'", initrd_extract);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "cd '%s' && zcat '%s' | cpio -idm 2>/dev/null", initrd_extract, initrd_orig);
    run_cmd(cmd);
    
    /* Apply progress_bar fix to installer.py
     * This fixes the AttributeError when using kickstart with ui:true */
    char installer_py[512];
    snprintf(installer_py, sizeof(installer_py), 
        "%s/usr/lib/python3.11/site-packages/photon_installer/installer.py", initrd_extract);
    
    if (file_exists(installer_py)) {
        log_info("Applying progress_bar fix to installer.py...");
        
        /* The fix needs to be surgical - only fix exit_gracefully(), not all ui checks.
         * We use a Python script to make precise changes. */
        
        char patch_script[512];
        snprintf(patch_script, sizeof(patch_script), "%s/patch_installer.py", work_dir);
        
        FILE *pf = fopen(patch_script, "w");
        if (pf) {
            fprintf(pf,
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "\n"
                "with open(sys.argv[1], 'r') as f:\n"
                "    content = f.read()\n"
                "\n"
                "# Fix 1: Add progress_bar = None and window = None after self.cwd = os.getcwd()\n"
                "old = 'self.cwd = os.getcwd()'\n"
                "new = '''self.cwd = os.getcwd()\n"
                "        self.progress_bar = None  # Fix: prevent AttributeError in exit_gracefully\n"
                "        self.window = None        # Fix: prevent AttributeError in exit_gracefully'''\n"
                "content = content.replace(old, new, 1)\n"
                "\n"
                "# Fix 2: In exit_gracefully, add None checks for progress_bar and window\n"
                "old_exit = '''if self.install_config['ui']:\n"
                "                self.progress_bar.hide()\n"
                "                self.window.addstr(0, 0, 'Oops, Installer got interrupted.'''\n"
                "new_exit = '''if self.install_config['ui'] and self.progress_bar is not None:\n"
                "                self.progress_bar.hide()\n"
                "            if self.install_config['ui'] and self.window is not None:\n"
                "                self.window.addstr(0, 0, 'Oops, Installer got interrupted.'''\n"
                "content = content.replace(old_exit, new_exit, 1)\n"
                "\n"
                "with open(sys.argv[1], 'w') as f:\n"
                "    f.write(content)\n"
                "\n"
                "print('Patch applied successfully')\n"
            );
            fclose(pf);
            
            snprintf(cmd, sizeof(cmd), "python3 '%s' '%s' 2>&1", patch_script, installer_py);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "rm -f '%s'", patch_script);
            run_cmd(cmd);
        }
        
        log_info("Patched installer.py with progress_bar fix");
    } else {
        log_warn("installer.py not found at expected path");
    }
    
    /* Repack initrd */
    snprintf(cmd, sizeof(cmd), 
        "cd '%s' && find . | cpio -o -H newc 2>/dev/null | gzip -9 > '%s'",
        initrd_extract, initrd_new);
    run_cmd(cmd);
    
    /* Replace original initrd */
    snprintf(cmd, sizeof(cmd), "mv '%s' '%s'", initrd_new, initrd_orig);
    run_cmd(cmd);
    log_info("Updated initrd with progress_bar fix");
    
    /* Cleanup initrd extract directory */
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", initrd_extract);
    run_cmd(cmd);
    
    /* Build custom GRUB stub with 6-option menu (NO shim_lock module)
     * This stub presents options for Custom MOK vs VMware Original boot */
    char stub_cfg[512], custom_stub[512], signed_stub[512];
    snprintf(stub_cfg, sizeof(stub_cfg), "%s/stub-menu.cfg", work_dir);
    snprintf(custom_stub, sizeof(custom_stub), "%s/grub-stub.efi", work_dir);
    snprintf(signed_stub, sizeof(signed_stub), "%s/grub-stub-signed.efi", work_dir);
    
    log_info("Building custom GRUB stub (6-option menu, no shim_lock)...");
    
    /* Create stub menu configuration (Embedded in GRUB binary)
     * This config runs first. It finds the ISO root and loads the 
     * modified /boot/grub2/grub.cfg which has the theme and our options */
    f = fopen(stub_cfg, "w");
    if (f) {
        fprintf(f,
            "search --no-floppy --file --set=root /isolinux/isolinux.cfg\n"
            "set prefix=($root)/boot/grub2\n"
            "configfile ($root)/boot/grub2/grub.cfg\n"
        );
        fclose(f);
    }
    
    /* Create sbat.csv for SBAT metadata (CRITICAL for modern shims) */
    char sbat_csv[512];
    snprintf(sbat_csv, sizeof(sbat_csv), "%s/sbat.csv", work_dir);
    f = fopen(sbat_csv, "w");
    if (f) {
        fprintf(f,
            "sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md\n"
            "grub,3,Free Software Foundation,grub,2.06,https://www.gnu.org/software/grub/\n"
        );
        fclose(f);
    }
    
    /* Build GRUB stub WITHOUT shim_lock module but WITH SBAT data
     * Include probe (for UUID detection), gfxmenu (for themed menus),
     * png/jpeg/tga (for background images), and gfxterm_background */
    snprintf(cmd, sizeof(cmd),
        "grub2-mkimage -O x86_64-efi -o '%s' -c '%s' -p /boot/grub2 --sbat '%s' "
        "normal search configfile linux chain fat part_gpt part_msdos iso9660 "
        "boot echo reboot halt test true loadenv read all_video gfxterm font efi_gop "
        "probe gfxmenu png jpeg tga gfxterm_background "
        "2>/dev/null",
        custom_stub, stub_cfg, sbat_csv);
    
    if (run_cmd(cmd) != 0 || !file_exists(custom_stub)) {
        log_error("Failed to build custom GRUB stub");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        return -1;
    }
    
    /* Sign custom stub with MOK key */
    snprintf(cmd, sizeof(cmd), "sbsign --key '%s' --cert '%s' --output '%s' '%s' 2>/dev/null",
        mok_key, mok_crt, signed_stub, custom_stub);
    if (run_cmd(cmd) != 0 || !file_exists(signed_stub)) {
        log_error("Failed to sign custom GRUB stub");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        return -1;
    }
    log_info("Custom GRUB stub built and signed");
    
    /* Save custom GRUB stub to keys directory for RPM patcher.
     * The SUSE shim and MokManager are already in keys_dir from extraction. */
    char saved_grub[512];
    snprintf(saved_grub, sizeof(saved_grub), "%s/grub-mok.efi", cfg.keys_dir);
    
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", signed_stub, saved_grub);
    run_cmd(cmd);
    log_info("Saved custom GRUB stub to keys directory: %s", saved_grub);
    
    log_info("Creating efiboot.img...");
    char new_efiboot[512], efiboot_path[512];
    snprintf(new_efiboot, sizeof(new_efiboot), "%s/efiboot.img", work_dir);
    snprintf(efiboot_path, sizeof(efiboot_path), "%s/boot/grub2/efiboot.img", iso_extract);
    
    snprintf(cmd, sizeof(cmd), "dd if=/dev/zero of='%s' bs=1M count=%d status=none",
        new_efiboot, DEFAULT_EFIBOOT_SIZE_MB);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "mkfs.vfat -F 12 -n EFIBOOT '%s' >/dev/null 2>&1", new_efiboot);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "mount -o loop '%s' '%s'", new_efiboot, efi_mount);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to mount efiboot.img");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        return -1;
    }
    
    char efi_boot_dir[512];
    snprintf(efi_boot_dir, sizeof(efi_boot_dir), "%s/EFI/BOOT", efi_mount);
    mkdir_p(efi_boot_dir);
    
    /* SUSE shim (Microsoft-signed) */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/BOOTX64.EFI'", shim_path, efi_mount);
    run_cmd(cmd);
    
    /* Custom GRUB stub (MOK-signed, 6-option menu, NO shim_lock) */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grub.efi'", signed_stub, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubx64.efi'", signed_stub, efi_mount);
    run_cmd(cmd);
    
    /* VMware's original GRUB for "VMware Original" option (will fail with unsigned kernel) */
    if (file_exists(vmware_grub)) {
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubx64_real.efi'", vmware_grub, efi_mount);
        run_cmd(cmd);
    }
    
    /* MokManager for certificate enrollment */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/MokManager.efi'", mokm_path, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/mmx64.efi'", mokm_path, efi_mount);
    run_cmd(cmd);
    
    /* MOK certificate for enrollment (CN=HABv4 Secure Boot MOK) */
    char our_mok_der[512];
    snprintf(our_mok_der, sizeof(our_mok_der), "%s/MOK.der", cfg.keys_dir);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer'", our_mok_der, efi_mount);
    run_cmd(cmd);
    
    /* IA32 (32-bit UEFI) support in efiboot.img */
    char ia32_shim[512], ia32_preloader[512], ia32_grub[512], ia32_mokm[512];
    snprintf(ia32_shim, sizeof(ia32_shim), "%s/shim-ia32.efi", cfg.keys_dir);
    snprintf(ia32_preloader, sizeof(ia32_preloader), "%s/ventoy-preloader-ia32.efi", cfg.keys_dir);
    snprintf(ia32_grub, sizeof(ia32_grub), "%s/ventoy-grub-real-ia32.efi", cfg.keys_dir);
    snprintf(ia32_mokm, sizeof(ia32_mokm), "%s/MokManager-ia32.efi", cfg.keys_dir);
    
    if (file_exists(ia32_shim)) {
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/BOOTIA32.EFI'", ia32_shim, efi_mount);
        run_cmd(cmd);
        if (file_exists(ia32_preloader)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubia32.efi'", ia32_preloader, efi_mount);
            run_cmd(cmd);
        }
        if (file_exists(ia32_grub)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubia32_real.efi'", ia32_grub, efi_mount);
            run_cmd(cmd);
        }
        if (file_exists(ia32_mokm)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/mmia32.efi'", ia32_mokm, efi_mount);
            run_cmd(cmd);
        }
        log_info("IA32 (32-bit UEFI) support added to efiboot.img");
    }
    
    /* No separate stub menu in efiboot.img - we modify /boot/grub2/grub.cfg instead */
    
    snprintf(cmd, sizeof(cmd), "sync && umount '%s'", efi_mount);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", new_efiboot, efiboot_path);
    run_cmd(cmd);
    
    log_info("Updating ISO EFI directory...");
    snprintf(efi_boot_dir, sizeof(efi_boot_dir), "%s/EFI/BOOT", iso_extract);
    mkdir_p(efi_boot_dir);
    
    /* SUSE shim (Microsoft-signed) */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/BOOTX64.EFI'", shim_path, iso_extract);
    run_cmd(cmd);
    
    /* Custom GRUB stub (MOK-signed, 6-option menu, NO shim_lock) */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grub.efi'", signed_stub, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubx64.efi'", signed_stub, iso_extract);
    run_cmd(cmd);
    
    /* VMware's original GRUB for "VMware Original" option */
    if (file_exists(vmware_grub)) {
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubx64_real.efi'", vmware_grub, iso_extract);
        run_cmd(cmd);
    }
    
    /* MokManager */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/MokManager.efi'", mokm_path, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/mmx64.efi'", mokm_path, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/MokManager.efi'", mokm_path, iso_extract);
    run_cmd(cmd);
    
    /* MOK certificate for enrollment (CN=HABv4 Secure Boot MOK) */
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer'", our_mok_der, iso_extract);
    run_cmd(cmd);
    
    /* Modify the original /boot/grub2/grub.cfg to add our menu options
     * while keeping the original theme and graphics settings intact.
     * This avoids graphics mode conflicts from chaining configs. */
    char original_grub_cfg[512];
    char modified_grub_cfg[512];
    snprintf(original_grub_cfg, sizeof(original_grub_cfg), "%s/boot/grub2/grub.cfg", iso_extract);
    snprintf(modified_grub_cfg, sizeof(modified_grub_cfg), "%s/boot/grub2/grub.cfg.new", iso_extract);
    
    f = fopen(modified_grub_cfg, "w");
    if (f) {
        /* Write the themed grub.cfg with 6 menu entries */
        if (cfg.efuse_usb_mode) {
            /* eFuse mode: Check for USB dongle before showing menu */
            fprintf(f,
                "# Photon OS Installer - HABv4 Secure Boot with eFuse Verification\n"
                "# Theme and graphics settings from original VMware config\n"
                "\n"
                "# eFuse USB dongle verification\n"
                "set efuse_verified=0\n"
                "search --no-floppy --label EFUSE_SIM --set=efuse_disk\n"
                "if [ -n \"$efuse_disk\" ]; then\n"
                "    if [ -f ($efuse_disk)/efuse_sim/srk_fuse.bin ]; then\n"
                "        set efuse_verified=1\n"
                "    fi\n"
                "fi\n"
                "\n"
                "if [ \"$efuse_verified\" = \"0\" ]; then\n"
                "    echo \"\"\n"
                "    echo \"=========================================\"\n"
                "    echo \"  HABv4 SECURITY: eFuse USB Required\"\n"
                "    echo \"=========================================\"\n"
                "    echo \"\"\n"
                "    echo \"Insert eFuse USB dongle (label: EFUSE_SIM)\"\n"
                "    echo \"and select 'Retry' to continue.\"\n"
                "    echo \"\"\n"
                "    set timeout=-1\n"
                "    menuentry \"Retry - Search for eFuse USB\" {\n"
                "        configfile /boot/grub2/grub.cfg\n"
                "    }\n"
                "    menuentry \"Reboot\" {\n"
                "        reboot\n"
                "    }\n"
                "    menuentry \"Shutdown\" {\n"
                "        halt\n"
                "    }\n"
                "else\n"
                "    # eFuse verified - show full menu\n"
                "    set default=0\n"
                "    set timeout=5\n"
                "    loadfont ascii\n"
                "    set gfxmode=\"1024x768\"\n"
                "    gfxpayload=keep\n"
                "    set theme=/boot/grub2/themes/photon/theme.txt\n"
                "    terminal_output gfxterm\n"
                "\n"
                "    menuentry \"Install (Custom MOK) - For Physical Hardware\" {\n"
                "        linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=LABEL=PHOTON_SB_%s ks=cdrom:/mok_ks.cfg\n"
                "        initrd /isolinux/initrd.img\n"
                "    }\n"
                "\n"
                "    menuentry \"Install (VMware Original) - For VMware VMs\" {\n"
                "        linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=LABEL=PHOTON_SB_%s ks=cdrom:/standard_ks.cfg\n"
                "        initrd /isolinux/initrd.img\n"
                "    }\n"
                "\n"
                "    menuentry \"MokManager - Enroll/Delete MOK Keys\" {\n"
                "        chainloader /EFI/BOOT/MokManager.efi\n"
                "    }\n"
                "\n"
                "    menuentry \"Reboot into UEFI Firmware Settings\" {\n"
                "        fwsetup\n"
                "    }\n"
                "\n"
                "    menuentry \"Reboot\" {\n"
                "        reboot\n"
                "    }\n"
                "\n"
                "    menuentry \"Shutdown\" {\n"
                "        halt\n"
                "    }\n"
                "fi\n",
                cfg.release, cfg.release
            );
            log_info("eFuse USB verification mode ENABLED in grub.cfg");
        } else {
            /* Standard mode: 6-option menu with kickstart */
            fprintf(f,
                "# Photon OS Installer - Modified for Secure Boot\n"
                "# Theme and graphics settings from original VMware config\n"
                "\n"
                "set default=0\n"
                "set timeout=5\n"
                "loadfont ascii\n"
                "set gfxmode=\"1024x768\"\n"
                "gfxpayload=keep\n"
                "set theme=/boot/grub2/themes/photon/theme.txt\n"
                "terminal_output gfxterm\n"
                "\n"
                "menuentry \"Install (Custom MOK) - For Physical Hardware\" {\n"
                "    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=LABEL=PHOTON_SB_%s ks=cdrom:/mok_ks.cfg\n"
                "    initrd /isolinux/initrd.img\n"
                "}\n"
                "\n"
                "menuentry \"Install (VMware Original) - For VMware VMs\" {\n"
                "    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=LABEL=PHOTON_SB_%s ks=cdrom:/standard_ks.cfg\n"
                "    initrd /isolinux/initrd.img\n"
                "}\n"
                "\n"
                "menuentry \"MokManager - Enroll/Delete MOK Keys\" {\n"
                "    chainloader /EFI/BOOT/MokManager.efi\n"
                "}\n"
                "\n"
                "menuentry \"Reboot into UEFI Firmware Settings\" {\n"
                "    fwsetup\n"
                "}\n"
                "\n"
                "menuentry \"Reboot\" {\n"
                "    reboot\n"
                "}\n"
                "\n"
                "menuentry \"Shutdown\" {\n"
                "    halt\n"
                "}\n",
                cfg.release, cfg.release
            );
        }
        fclose(f);
        
        /* Replace original with modified */
        snprintf(cmd, sizeof(cmd), "mv '%s' '%s'", modified_grub_cfg, original_grub_cfg);
        run_cmd(cmd);
        log_info("Modified /boot/grub2/grub.cfg with 6 menu options");
    }
    
    /* IA32 (32-bit UEFI) support in ISO root */
    if (file_exists(ia32_shim)) {
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/BOOTIA32.EFI'", ia32_shim, iso_extract);
        run_cmd(cmd);
        if (file_exists(ia32_preloader)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubia32.efi'", ia32_preloader, iso_extract);
            run_cmd(cmd);
        }
        if (file_exists(ia32_grub)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubia32_real.efi'", ia32_grub, iso_extract);
            run_cmd(cmd);
        }
        if (file_exists(ia32_mokm)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/mmia32.efi'", ia32_mokm, iso_extract);
            run_cmd(cmd);
        }
        log_info("IA32 (32-bit UEFI) support added to ISO");
    }
    
    /* Build MOK-signed RPM packages for installation */
    log_info("Building MOK-signed RPM packages for installation...");
    {
        char photon_release_dir[512];
        snprintf(photon_release_dir, sizeof(photon_release_dir), "/root/%s", cfg.release);
        
        int rpm_ret = rpm_patch_secureboot_packages(
            photon_release_dir,
            iso_extract,
            mok_key,
            mok_crt,
            cfg.verbose
        );
        
        if (rpm_ret != 0) {
            log_warn("MOK RPM package build failed (code: %d)", rpm_ret);
            log_warn("Installation with 'Install (Custom MOK)' may not work on target system");
            log_warn("Live boot from ISO will still work");
        } else {
            log_info("MOK-signed RPM packages built and integrated");
            
            /* Sign MOK RPMs with GPG if enabled */
            if (cfg.rpm_signing) {
                log_info("GPG signing MOK RPM packages...");
                
                /* Generate GPG keys if needed */
                if (generate_gpg_keys() != 0) {
                    log_warn("Failed to generate GPG keys, skipping RPM signing");
                } else {
                    /* MOK RPMs are built to /tmp/rpm_mok_build/output by rpm_secureboot_patcher */
                    rpm_build_config_t sign_cfg = {0};
                    char output_dir[512], gpg_home[512];
                    snprintf(output_dir, sizeof(output_dir), "/tmp/rpm_mok_build/output");
                    snprintf(gpg_home, sizeof(gpg_home), "%s/.gnupg", cfg.keys_dir);
                    sign_cfg.output_dir = output_dir;
                    
                    if (rpm_sign_mok_packages(&sign_cfg, gpg_home, GPG_KEY_NAME) != 0) {
                        log_warn("Failed to sign MOK RPM packages");
                    } else {
                        /* Copy GPG public key to ISO root */
                        char gpg_pub[512], gpg_iso[512];
                        snprintf(gpg_pub, sizeof(gpg_pub), "%s/%s", cfg.keys_dir, GPG_KEY_FILE);
                        snprintf(gpg_iso, sizeof(gpg_iso), "%s/%s", iso_extract, GPG_KEY_FILE);
                        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", gpg_pub, gpg_iso);
                        run_cmd(cmd);
                        log_info("GPG public key copied to ISO root");
                    }
                }
            }
        }
    }
    
    log_info("Building ISO...");
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
        "-V 'PHOTON_SB_%s' "
        ". 2>&1 | tail -5",
        iso_extract, output_iso, cfg.release);
    
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
    run_cmd(cmd);
    
    if (file_exists(output_iso)) {
        printf("\n");
        log_info("=========================================");
        log_info("Secure Boot ISO Created!");
        log_info("=========================================");
        log_info("ISO: %s", output_iso);
        log_info("Size: %ld MB", get_file_size(output_iso) / (1024 * 1024));
        if (cfg.efuse_usb_mode) {
            log_info("eFuse USB Mode: ENABLED (dongle required)");
        }
        printf("\n");
        printf("Boot Chain:\n");
        printf("  UEFI -> BOOTX64.EFI (SUSE shim, Microsoft-signed)\n");
        printf("       -> grub.efi (Custom GRUB stub, MOK-signed, NO shim_lock)\n");
        printf("       -> GRUB Menu (5 sec timeout):\n");
        printf("          1. Install (Custom MOK) - For Physical Hardware\n");
        printf("          2. Install (VMware Original) - For VMware VMs\n");
        printf("          3. MokManager - Enroll/Delete MOK keys\n");
        printf("          4. Reboot into UEFI Firmware Settings\n");
        printf("          5-6. Reboot/Shutdown\n");
        printf("\n");
        printf("First Boot Instructions:\n");
        printf("  1. Boot from USB with UEFI Secure Boot ENABLED\n");
        printf("  2. You should see a BLUE MokManager screen (shim's)\n");
        printf("     " YELLOW "NOTE:" RESET " If you see your laptop's security dialog instead,\n");
        printf("           check that CSM/Legacy boot is DISABLED in BIOS.\n");
        printf("  3. Select 'Enroll key from disk'\n");
        printf("  4. Navigate to USB root -> ENROLL_THIS_KEY_IN_MOKMANAGER.cer\n");
        printf("     (This is YOUR MOK certificate: CN=HABv4 Secure Boot MOK)\n");
        printf("  5. Confirm and select REBOOT (not continue)\n");
        printf("  6. After reboot, GRUB Menu appears (5 sec timeout)\n");
        printf("  7. Select installation option:\n");
        printf("     - 'Install (Custom MOK)' for PHYSICAL hardware with Secure Boot\n");
        printf("     - 'Install (VMware Original)' for VMware virtual machines\n");
        printf("  8. Follow the interactive installer prompts\n");
        printf("     (Disk, hostname, password are configurable; packages are preset)\n");
        if (cfg.efuse_usb_mode) {
            printf("\neFuse USB Mode:\n");
            printf("  - Insert USB dongle labeled 'EFUSE_SIM' before boot\n");
            printf("  - Create dongle with: %s -u /dev/sdX\n", PROGRAM_NAME);
        }
        log_info("=========================================");
        return 0;
    } else {
        log_error("Failed to create ISO");
        return -1;
    }
}

/* ============================================================================
 * Cleanup
 * ============================================================================ */

static int do_cleanup(void) {
    log_step("Cleaning up...");
    
    char cmd[1024];
    
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", cfg.keys_dir);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", cfg.efuse_dir);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "rm -rf '%s/stage'/*-secureboot.iso 2>/dev/null || true", cfg.photon_dir);
    run_cmd(cmd);
    
    log_info("Cleanup complete");
    return 0;
}

/* ============================================================================
 * ISO Diagnostics
 * ============================================================================ */

static int diagnose_iso(const char *iso_path) {
    log_step("Diagnosing ISO: %s", iso_path);
    
    if (!file_exists(iso_path)) {
        log_error("ISO file not found: %s", iso_path);
        return -1;
    }
    
    char work_dir[256], cmd[2048];
    snprintf(work_dir, sizeof(work_dir), "/tmp/iso_diagnose_%d", getpid());
    mkdir_p(work_dir);
    
    int errors = 0, warnings = 0;
    
    printf("\n");
    log_info("=== ISO Structure Analysis ===");
    
    /* Check El Torito boot records */
    printf("\n[Boot Modes]\n");
    snprintf(cmd, sizeof(cmd), "xorriso -indev '%s' -pvd_info 2>&1 | grep -i 'El Torito'", iso_path);
    if (system(cmd) == 0) {
        printf("  " GREEN "[OK]" RESET " El Torito boot records present\n");
    } else {
        printf("  " RED "[FAIL]" RESET " Missing El Torito boot records\n");
        errors++;
    }
    
    /* Extract EFI/BOOT */
    snprintf(cmd, sizeof(cmd), "xorriso -osirrox on -indev '%s' -extract /EFI/BOOT '%s/EFI_BOOT' 2>/dev/null", 
        iso_path, work_dir);
    system(cmd);
    
    /* Check required EFI files */
    printf("\n[EFI Boot Files (x64)]\n");
    const char *efi_files[] = {"BOOTX64.EFI", "grub.efi", "MokManager.efi", NULL};
    for (int i = 0; efi_files[i]; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/EFI_BOOT/%s", work_dir, efi_files[i]);
        if (file_exists(path)) {
            printf("  " GREEN "[OK]" RESET " %s\n", efi_files[i]);
        } else {
            printf("  " RED "[FAIL]" RESET " %s missing\n", efi_files[i]);
            errors++;
        }
    }
    
    /* Check cascade architecture: grub.efi (stub) + grubx64_real.efi (full GRUB) */
    printf("\n[GRUB Cascade Architecture]\n");
    char grub_stub_path[512], grub_real_path[512];
    snprintf(grub_stub_path, sizeof(grub_stub_path), "%s/EFI_BOOT/grub.efi", work_dir);
    snprintf(grub_real_path, sizeof(grub_real_path), "%s/EFI_BOOT/grubx64_real.efi", work_dir);
    
    if (file_exists(grub_stub_path)) {
        long stub_size = get_file_size(grub_stub_path);
        if (stub_size < 100000) {  /* Less than 100KB = stub (expected) */
            printf("  " GREEN "[OK]" RESET " grub.efi is %ld KB (custom stub - expected)\n", stub_size / 1024);
            
            /* Check if grubx64_real.efi exists for cascade */
            if (file_exists(grub_real_path)) {
                long real_size = get_file_size(grub_real_path);
                printf("  " GREEN "[OK]" RESET " grubx64_real.efi is %ld KB (full GRUB)\n", real_size / 1024);
                printf("  " GREEN "[OK]" RESET " Cascade architecture: stub -> real GRUB\n");
            } else {
                printf("  " RED "[FAIL]" RESET " grubx64_real.efi MISSING!\n");
                printf("             Stub needs grubx64_real.efi to chainload\n");
                errors++;
            }
        } else {
            printf("  " GREEN "[OK]" RESET " grub.efi is %ld KB - full GRUB binary\n", stub_size / 1024);
        }
    }
    
    /* Check optional IA32 files */
    printf("\n[EFI Boot Files (IA32 - optional)]\n");
    const char *ia32_files[] = {"BOOTIA32.EFI", "grubia32.efi", "mmia32.efi", NULL};
    for (int i = 0; ia32_files[i]; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/EFI_BOOT/%s", work_dir, ia32_files[i]);
        if (file_exists(path)) {
            printf("  " GREEN "[OK]" RESET " %s\n", ia32_files[i]);
        } else {
            printf("  " YELLOW "[--]" RESET " %s not present (optional)\n", ia32_files[i]);
        }
    }
    
    /* Verify signatures */
    printf("\n[Signature Verification]\n");
    char shim_path[512], grub_path[512];
    snprintf(shim_path, sizeof(shim_path), "%s/EFI_BOOT/BOOTX64.EFI", work_dir);
    snprintf(grub_path, sizeof(grub_path), "%s/EFI_BOOT/grub.efi", work_dir);
    
    if (file_exists(shim_path)) {
        snprintf(cmd, sizeof(cmd), "sbverify --list '%s' 2>&1 | grep -q 'Microsoft'", shim_path);
        if (system(cmd) == 0) {
            printf("  " GREEN "[OK]" RESET " BOOTX64.EFI signed by Microsoft\n");
        } else {
            printf("  " YELLOW "[WARN]" RESET " BOOTX64.EFI signature not verified as Microsoft\n");
            warnings++;
        }
    }
    
    if (file_exists(grub_path)) {
        snprintf(cmd, sizeof(cmd), "sbverify --list '%s' 2>&1 | grep -q 'CN=grub'", grub_path);
        if (system(cmd) == 0) {
            printf("  " GREEN "[OK]" RESET " grub.efi signed with CN=grub\n");
        } else {
            printf("  " YELLOW "[WARN]" RESET " grub.efi signature not verified as CN=grub\n");
            warnings++;
        }
    }
    
    /* Check MOK certificate */
    printf("\n[MOK Certificate]\n");
    snprintf(cmd, sizeof(cmd), "xorriso -osirrox on -indev '%s' -extract /ENROLL_THIS_KEY_IN_MOKMANAGER.cer '%s/mok.cer' 2>/dev/null", 
        iso_path, work_dir);
    system(cmd);
    
    char mok_cert[512];
    snprintf(mok_cert, sizeof(mok_cert), "%s/mok.cer", work_dir);
    if (file_exists(mok_cert)) {
        snprintf(cmd, sizeof(cmd), "openssl x509 -in '%s' -inform DER -noout -subject 2>&1 | grep -q 'CN.*=.*grub'", mok_cert);
        if (system(cmd) == 0) {
            printf("  " GREEN "[OK]" RESET " ENROLL_THIS_KEY_IN_MOKMANAGER.cer present (CN=grub)\n");
        } else {
            printf("  " YELLOW "[WARN]" RESET " Certificate present but CN may not match\n");
            warnings++;
        }
    } else {
        printf("  " RED "[FAIL]" RESET " ENROLL_THIS_KEY_IN_MOKMANAGER.cer missing at ISO root\n");
        errors++;
    }
    
    /* Check original GRUB config (for themed installer menu) */
    printf("\n[Original GRUB Config]\n");
    snprintf(cmd, sizeof(cmd), "xorriso -osirrox on -indev '%s' -extract /boot/grub2/grub.cfg '%s/grub_orig.cfg' 2>/dev/null", 
        iso_path, work_dir);
    system(cmd);
    
    char grub_orig[512];
    snprintf(grub_orig, sizeof(grub_orig), "%s/grub_orig.cfg", work_dir);
    if (file_exists(grub_orig)) {
        printf("  " GREEN "[OK]" RESET " /boot/grub2/grub.cfg exists (original themed menu)\n");
        /* Verify it has the theme setting */
        snprintf(cmd, sizeof(cmd), "grep -q 'theme=' '%s'", grub_orig);
        if (system(cmd) == 0) {
            printf("  " GREEN "[OK]" RESET " Has theme setting (will show Photon OS background)\n");
        } else {
            printf("  " YELLOW "[WARN]" RESET " No theme setting found\n");
            warnings++;
        }
    } else {
        printf("  " RED "[FAIL]" RESET " /boot/grub2/grub.cfg missing\n");
        printf("             Custom MOK boot path will not work\n");
        errors++;
    }
    
    /* Check efiboot.img */
    printf("\n[EFI Boot Image]\n");
    snprintf(cmd, sizeof(cmd), "xorriso -osirrox on -indev '%s' -extract /boot/grub2/efiboot.img '%s/efiboot.img' 2>/dev/null", 
        iso_path, work_dir);
    system(cmd);
    
    char efiboot[512];
    snprintf(efiboot, sizeof(efiboot), "%s/efiboot.img", work_dir);
    if (file_exists(efiboot)) {
        printf("  " GREEN "[OK]" RESET " efiboot.img present\n");
        long size = get_file_size(efiboot);
        printf("  " GREEN "[OK]" RESET " Size: %ld KB\n", size / 1024);
    } else {
        printf("  " RED "[FAIL]" RESET " efiboot.img missing\n");
        errors++;
    }
    
    /* Summary */
    printf("\n");
    log_info("=== Diagnosis Summary ===");
    if (errors == 0 && warnings == 0) {
        printf(GREEN "All checks passed! ISO should boot correctly.\n" RESET);
    } else if (errors == 0) {
        printf(YELLOW "%d warning(s). ISO may still work.\n" RESET, warnings);
    } else {
        printf(RED "%d error(s), %d warning(s). ISO may have boot issues.\n" RESET, errors, warnings);
    }
    
    printf("\n");
    log_info("=== First Boot Checklist ===");
    printf("1. " YELLOW "CRITICAL:" RESET " Disable CSM/Legacy boot in BIOS\n");
    printf("2. Enable UEFI Secure Boot\n");
    printf("3. Boot from USB\n");
    printf("4. You should see a " CYAN "BLUE MokManager screen" RESET " (shim's)\n");
    printf("   " RED "NOT" RESET " your laptop's manufacturer security dialog\n");
    printf("5. Enroll the certificate and REBOOT\n");
    
    /* Cleanup */
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
    system(cmd);
    
    return errors;
}

/* ============================================================================
 * Verification
 * ============================================================================ */

static int verify_installation(void) {
    log_step("Verifying installation...");
    
    int errors = 0;
    
    const char *keys[] = {"MOK.key", "MOK.crt", "MOK.der", "srk.pem", NULL};
    for (int i = 0; keys[i]; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", cfg.keys_dir, keys[i]);
        if (file_exists(path)) {
            printf("  " GREEN "[OK]" RESET " %s\n", keys[i]);
        } else {
            printf("  " RED "[--]" RESET " %s missing\n", keys[i]);
            errors++;
        }
    }
    
    const char *ventoy[] = {"shim-suse.efi", "MokManager-suse.efi", NULL};
    for (int i = 0; ventoy[i]; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", cfg.keys_dir, ventoy[i]);
        if (file_exists(path)) {
            printf("  " GREEN "[OK]" RESET " %s\n", ventoy[i]);
        } else {
            printf("  " RED "[--]" RESET " %s missing\n", ventoy[i]);
            errors++;
        }
    }
    
    char path[512];
    snprintf(path, sizeof(path), "%s/hab-preloader-signed.efi", cfg.keys_dir);
    if (file_exists(path)) {
        printf("  " GREEN "[OK]" RESET " HAB PreLoader (signed)\n");
    } else {
        snprintf(path, sizeof(path), "%s/ventoy-preloader.efi", cfg.keys_dir);
        if (file_exists(path)) {
            printf("  " YELLOW "[OK]" RESET " SUSE shim components (for custom stub)\n");
        } else {
            printf("  " RED "[--]" RESET " No PreLoader found\n");
            errors++;
        }
    }
    
    snprintf(path, sizeof(path), "%s/srk_fuse.bin", cfg.efuse_dir);
    if (file_exists(path)) {
        printf("  " GREEN "[OK]" RESET " eFuse simulation\n");
    } else {
        printf("  " YELLOW "[--]" RESET " eFuse simulation missing\n");
    }
    
    printf("\n");
    if (errors == 0) {
        log_info("All verifications passed");
    } else {
        log_warn("%d verification(s) failed", errors);
    }
    
    return errors;
}

/* ============================================================================
 * Help and Usage
 * ============================================================================ */

static void show_help(void) {
    printf("%s v%s - HABv4 Secure Boot Simulation Environment\n\n", PROGRAM_NAME, VERSION);
    printf("Usage: %s [OPTIONS]\n\n", PROGRAM_NAME);
    printf("Options:\n");
    printf("  -r, --release=VERSION      Photon OS release: 4.0, 5.0, 6.0 (default: %s)\n", DEFAULT_RELEASE);
    printf("  -i, --input=ISO            Input ISO file (default: auto-detect in ~/<release>/stage/)\n");
    printf("  -o, --output=ISO           Output ISO file (default: <input>-secureboot.iso)\n");
    printf("  -k, --keys-dir=DIR         Keys directory (default: %s)\n", DEFAULT_KEYS_DIR);
    printf("  -e, --efuse-dir=DIR        eFuse directory (default: %s)\n", DEFAULT_EFUSE_DIR);
    printf("  -m, --mok-days=DAYS        MOK certificate validity in days (default: %d, max: 3650)\n", DEFAULT_MOK_DAYS);
    printf("  -b, --build-iso            Build Secure Boot ISO\n");
    printf("  -g, --generate-keys        Generate cryptographic keys\n");
    printf("  -s, --setup-efuse          Setup eFuse simulation\n");
    printf("  -u, --create-efuse-usb=DEV Create eFuse USB dongle on device (e.g., /dev/sdb)\n");
    printf("  -E, --efuse-usb            Enable eFuse USB dongle verification in GRUB\n");
    printf("  -R, --rpm-signing          Enable GPG signing of MOK RPM packages\n");
    printf("  -F, --full-kernel-build    Build kernel from source (takes hours)\n");
    printf("  -D, --diagnose=ISO         Diagnose an existing ISO for Secure Boot issues\n");
    printf("  -c, --clean                Clean up all artifacts\n");
    printf("  -v, --verbose              Verbose output\n");
    printf("  -y, --yes                  Auto-confirm destructive operations (e.g., erase USB)\n");
    printf("  -h, --help                 Show this help\n");
    printf("\n");
    printf("Default behavior (no action flags):\n");
    printf("  When no action flags (-b, -g, -s, -d, -u, -c, -F) are specified,\n");
    printf("  the tool runs: -g -s -d (generate keys, setup eFuse, download Ventoy)\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s                         # Default: setup keys, eFuse, Ventoy\n", PROGRAM_NAME);
    printf("  %s -b                      # Build Secure Boot ISO\n", PROGRAM_NAME);
    printf("  %s -r 4.0 -b               # Build for Photon OS 4.0\n", PROGRAM_NAME);
    printf("  %s -i in.iso -o out.iso -b # Specify input/output ISO\n", PROGRAM_NAME);
    printf("  %s -E -b                   # Build ISO with eFuse USB verification\n", PROGRAM_NAME);
    printf("  %s -R -b                   # Build ISO with RPM signing\n", PROGRAM_NAME);
    printf("  %s -u /dev/sdb             # Create eFuse USB dongle\n", PROGRAM_NAME);
    printf("  %s -F                      # Full kernel build (hours)\n", PROGRAM_NAME);
    printf("  %s -D /path/to/iso         # Diagnose existing ISO\n", PROGRAM_NAME);
    printf("  %s -c                      # Cleanup all artifacts\n", PROGRAM_NAME);
    printf("\n");
}

/* ============================================================================
 * Main
 * ============================================================================ */

int main(int argc, char *argv[]) {
    memset(&cfg, 0, sizeof(cfg));
    strncpy(cfg.release, DEFAULT_RELEASE, sizeof(cfg.release) - 1);
    strncpy(cfg.keys_dir, DEFAULT_KEYS_DIR, sizeof(cfg.keys_dir) - 1);
    strncpy(cfg.efuse_dir, DEFAULT_EFUSE_DIR, sizeof(cfg.efuse_dir) - 1);
    cfg.mok_days = DEFAULT_MOK_DAYS;
    
    char *home = getenv("HOME");
    if (!home) home = "/root";
    snprintf(cfg.photon_dir, sizeof(cfg.photon_dir), "%s/%s", home, cfg.release);
    
    static struct option long_options[] = {
        {"release",           required_argument, 0, 'r'},
        {"input",             required_argument, 0, 'i'},
        {"output",            required_argument, 0, 'o'},
        {"keys-dir",          required_argument, 0, 'k'},
        {"efuse-dir",         required_argument, 0, 'e'},
        {"mok-days",          required_argument, 0, 'm'},
        {"build-iso",         no_argument,       0, 'b'},
        {"generate-keys",     no_argument,       0, 'g'},
        {"setup-efuse",       no_argument,       0, 's'},
        {"create-efuse-usb",  required_argument, 0, 'u'},
        {"efuse-usb",         no_argument,       0, 'E'},
        {"rpm-signing",       no_argument,       0, 'R'},
        {"full-kernel-build", no_argument,       0, 'F'},
        {"diagnose",          required_argument, 0, 'D'},
        {"clean",             no_argument,       0, 'c'},
        {"verbose",           no_argument,       0, 'v'},
        {"yes",               no_argument,       0, 'y'},
        {"help",              no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "r:i:o:k:e:m:bgsERFD:cu:vyh", long_options, NULL)) != -1) {
        switch (opt) {
            case 'r':
                strncpy(cfg.release, optarg, sizeof(cfg.release) - 1);
                snprintf(cfg.photon_dir, sizeof(cfg.photon_dir), "%s/%s", home, cfg.release);
                break;
            case 'i':
                strncpy(cfg.input_iso, optarg, sizeof(cfg.input_iso) - 1);
                break;
            case 'o':
                strncpy(cfg.output_iso, optarg, sizeof(cfg.output_iso) - 1);
                break;
            case 'k':
                strncpy(cfg.keys_dir, optarg, sizeof(cfg.keys_dir) - 1);
                break;
            case 'e':
                strncpy(cfg.efuse_dir, optarg, sizeof(cfg.efuse_dir) - 1);
                break;
            case 'm':
                cfg.mok_days = atoi(optarg);
                if (cfg.mok_days < 1 || cfg.mok_days > 3650) {
                    log_error("MOK days must be between 1 and 3650");
                    return 1;
                }
                break;
            case 'b':
                cfg.build_iso = 1;
                break;
            case 'g':
                cfg.generate_keys = 1;
                break;
            case 's':
                cfg.setup_efuse = 1;
                break;
            case 'u':
                strncpy(cfg.efuse_usb_device, optarg, sizeof(cfg.efuse_usb_device) - 1);
                break;
            case 'E':
                cfg.efuse_usb_mode = 1;
                break;
            case 'R':
                cfg.rpm_signing = 1;
                break;
            case 'F':
                cfg.full_kernel_build = 1;
                break;
            case 'D':
                strncpy(cfg.diagnose_iso_path, optarg, sizeof(cfg.diagnose_iso_path) - 1);
                break;
            case 'c':
                cfg.cleanup = 1;
                break;
            case 'v':
                cfg.verbose = 1;
                break;
            case 'y':
                cfg.yes_to_all = 1;
                break;
            case 'h':
                show_help();
                return 0;
            default:
                show_help();
                return 1;
        }
    }
    
    if (geteuid() != 0) {
        log_error("This program must be run as root");
        return 1;
    }
    
    if (cfg.cleanup) {
        return do_cleanup();
    }
    
    if (strlen(cfg.diagnose_iso_path) > 0) {
        return diagnose_iso(cfg.diagnose_iso_path);
    }
    
    /* Handle eFuse USB creation - but don't return early if --build-iso is also set */
    int efuse_usb_requested = (strlen(cfg.efuse_usb_device) > 0);
    if (efuse_usb_requested) {
        if (!cfg.generate_keys) cfg.generate_keys = 1;
        if (!cfg.setup_efuse) cfg.setup_efuse = 1;
    }
    
    /* If no specific action, default to full setup (generate keys) */
    if (!cfg.generate_keys && !cfg.setup_efuse && 
        !cfg.build_iso && !cfg.full_kernel_build) {
        cfg.generate_keys = 1;
        cfg.setup_efuse = 1;
    }
    
    /* Auto-enable key generation if building ISO and keys don't exist */
    if (cfg.build_iso) {
        char mok_path[512];
        snprintf(mok_path, sizeof(mok_path), "%s/MOK.key", cfg.keys_dir);
        
        if (!file_exists(mok_path)) {
            log_info("Keys not found, auto-enabling key generation");
            cfg.generate_keys = 1;
        }
        /* SUSE shim components are extracted automatically when building ISO */
    }
    
    printf("\n");
    printf("=========================================\n");
    printf("%s v%s\n", PROGRAM_NAME, VERSION);
    printf("=========================================\n");
    printf("Host Architecture: %s\n", get_host_arch());
    printf("Photon OS Release: %s\n", cfg.release);
    printf("Keys Directory:    %s\n", cfg.keys_dir);
    printf("eFuse Directory:   %s\n", cfg.efuse_dir);
    printf("MOK Validity:      %d days\n", cfg.mok_days);
    if (cfg.build_iso) printf("Build ISO:         YES\n");
    if (cfg.efuse_usb_mode) printf("eFuse USB Mode:    ENABLED\n");
    if (cfg.full_kernel_build) printf("Full Kernel Build: YES\n");
    printf("=========================================\n\n");
    
    if (cfg.generate_keys) {
        if (generate_all_keys() != 0) return 1;
    }
    
    if (cfg.setup_efuse) {
        if (setup_efuse_simulation() != 0) return 1;
    }
    
    /* Create eFuse USB dongle if requested */
    if (efuse_usb_requested) {
        if (create_efuse_usb(cfg.efuse_usb_device) != 0) return 1;
    }
    
    if (cfg.full_kernel_build) {
        if (build_linux_kernel() != 0) return 1;
    }
    
    verify_installation();
    
    if (cfg.build_iso) {
        if (create_secure_boot_iso() != 0) return 1;
    }
    
    printf("\n");
    log_info("=========================================");
    log_info("Operation Complete!");
    log_info("=========================================");
    printf("Keys:     %s\n", cfg.keys_dir);
    printf("eFuse:    %s\n", cfg.efuse_dir);
    
    /* Dynamic next steps based on what was done */
    printf("\nNext steps:\n");
    if (cfg.build_iso) {
        /* ISO was built - suggest writing to USB or testing */
        printf("  - Write to USB:     dd if=<iso> of=/dev/sdX bs=4M status=progress\n");
        printf("  - Create eFuse USB: %s -u /dev/sdX\n", PROGRAM_NAME);
        printf("  - Rebuild with eFuse mode: %s -E -b\n", PROGRAM_NAME);
        printf("  - Cleanup:          %s -c\n", PROGRAM_NAME);
    } else if (cfg.full_kernel_build) {
        /* Kernel was built - suggest building ISO */
        printf("  - Build ISO:        %s -b\n", PROGRAM_NAME);
        printf("  - Cleanup:          %s -c\n", PROGRAM_NAME);
    } else {
        /* Setup was done - suggest building ISO */
        printf("  - Build ISO:        %s -b\n", PROGRAM_NAME);
        printf("  - With eFuse mode:  %s -E -b\n", PROGRAM_NAME);
        printf("  - Create eFuse USB: %s -u /dev/sdX\n", PROGRAM_NAME);
        printf("  - Full kernel:      %s -F\n", PROGRAM_NAME);
        printf("  - Cleanup:          %s -c\n", PROGRAM_NAME);
    }
    log_info("=========================================");
    
    return 0;
}
