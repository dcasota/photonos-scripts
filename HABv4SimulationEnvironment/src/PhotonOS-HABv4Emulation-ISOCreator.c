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

#define VERSION "1.9.10"
#define PROGRAM_NAME "PhotonOS-HABv4Emulation-ISOCreator"

/* Default configuration */
#define DEFAULT_RELEASE "5.0"
#define DEFAULT_MOK_DAYS 180
#define DEFAULT_MOK_KEY_BITS 2048
#define DEFAULT_CERT_WARN_DAYS 30
#define DEFAULT_KEYS_DIR "/root/hab_keys"
#define DEFAULT_EFUSE_DIR "/root/efuse_sim"
#define DEFAULT_EFIBOOT_SIZE_MB 16

/* Valid key sizes (whitelist) */
static const int VALID_KEY_SIZES[] = {2048, 3072, 4096, 0};

#define VENTOY_VERSION "1.1.10"
#define VENTOY_URL "https://github.com/ventoy/Ventoy/releases/download/v" VENTOY_VERSION "/ventoy-" VENTOY_VERSION "-linux.tar.gz"

/* SHA3-256 checksums for download integrity verification
 * Security: Prevents man-in-the-middle attacks substituting malicious binaries
 * To update checksums:
 *   openssl dgst -sha3-256 ventoy-X.X.X-linux.tar.gz
 *   (mount ventoy.disk.img and checksum EFI files) */
#define VENTOY_SHA3_256 "9ef8f77e05e5a0f8231e196cef5759ce1a0ffd31abeac4c1a92f76b9c9a8d620"
#define SUSE_SHIM_SHA3_256 "7856a4588396b9bc1392af09885beef8833fa86381cf1a2a0f0ac5e6e7411ba5"
#define SUSE_MOKMANAGER_SHA3_256 "00a3b4653c4098c8d6557b8a2b61c0f7d05b20ee619ec786940d0b28970ee104"

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
    char drivers_dir[512];    /* Custom drivers directory (--drivers=DIR) */
    int mok_days;
    int mok_key_bits;         /* RSA key size: 2048, 3072, or 4096 */
    int cert_warn_days;       /* Days before expiration to warn */
    int build_iso;
    int generate_keys;
    int setup_efuse;
    int efuse_usb_mode;
    int rpm_signing;          /* Enable GPG signing of MOK RPM packages */
    int check_certs;          /* Check certificate expiration */
    int include_drivers;      /* Include driver RPMs from drivers directory */
    int cleanup;
    int verbose;
    int yes_to_all;
} config_t;

/* Global config */
static config_t cfg;

/* Valid release versions (whitelist for input validation) */
static const char *VALID_RELEASES[] = {"4.0", "5.0", "6.0", NULL};

/* Default drivers directory (relative to source tree) */
#define DEFAULT_DRIVERS_DIR "drivers/RPM"

/* ============================================================================
 * Driver-to-Kernel-Config Mapping
 * ============================================================================
 * Maps driver RPM name prefixes to required kernel CONFIG options.
 * When --drivers is specified, the tool scans for RPMs and enables
 * the corresponding kernel configs during build.
 * ============================================================================ */

typedef struct {
    const char *driver_prefix;      /* RPM name prefix to match */
    const char *description;        /* Human-readable description */
    const char *kernel_configs;     /* Space-separated CONFIG_* options */
} driver_kernel_map_t;

static const driver_kernel_map_t DRIVER_KERNEL_MAP[] = {
    /* ===== Wi-Fi Subsystem Prerequisites =====
     * These must be enabled FIRST for any Wi-Fi driver to work.
     * Photon ESX kernel has CONFIG_WIRELESS=n CONFIG_WLAN=n by default.
     * We include these in each Wi-Fi driver's configs to ensure subsystem is enabled. */
    
    /* Intel Wi-Fi drivers (iwlwifi for AX200/AX201/AX210/AX211/BE200 etc.) */
    {"linux-firmware-iwlwifi", "Intel Wi-Fi 6/6E/7 (iwlwifi)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_IWLWIFI=m CONFIG_IWLMVM=m CONFIG_IWLDVM=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    
    /* Realtek Wi-Fi drivers */
    {"linux-firmware-rtw88", "Realtek Wi-Fi (rtw88)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_RTW88=m CONFIG_RTW88_CORE=m CONFIG_RTW88_PCI=m CONFIG_RTW88_USB=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    {"linux-firmware-rtw89", "Realtek Wi-Fi (rtw89)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_RTW89=m CONFIG_RTW89_CORE=m CONFIG_RTW89_PCI=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    
    /* Broadcom Wi-Fi drivers */
    {"linux-firmware-brcm", "Broadcom Wi-Fi (brcmfmac)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_BRCMFMAC=m CONFIG_BRCMUTIL=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    
    /* Qualcomm/Atheros Wi-Fi drivers */
    {"linux-firmware-ath10k", "Qualcomm Atheros Wi-Fi (ath10k)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_ATH10K=m CONFIG_ATH10K_PCI=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    {"linux-firmware-ath11k", "Qualcomm Atheros Wi-Fi (ath11k)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_ATH11K=m CONFIG_ATH11K_PCI=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    
    /* MediaTek Wi-Fi drivers */
    {"linux-firmware-mediatek", "MediaTek Wi-Fi (mt76)",
     "CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m "
     "CONFIG_MT76=m CONFIG_MT7921E=m CONFIG_MT7921S=m CONFIG_MT7921U=m "
     "CONFIG_CRYPTO_CCM=y CONFIG_CRYPTO_GCM=y CONFIG_CRYPTO_CMAC=y CONFIG_CRYPTO_AES=y "
     "CONFIG_CRYPTO_AEAD=y CONFIG_CRYPTO_SEQIV=y CONFIG_CRYPTO_CTR=y CONFIG_CRYPTO_GHASH=y"},
    
    /* Intel Ethernet drivers */
    {"linux-firmware-e1000e", "Intel Ethernet (e1000e)",
     "CONFIG_E1000E=m"},
    {"linux-firmware-igb", "Intel Gigabit Ethernet (igb)",
     "CONFIG_IGB=m"},
    {"linux-firmware-ixgbe", "Intel 10GbE (ixgbe)",
     "CONFIG_IXGBE=m"},
    
    /* NVIDIA GPU drivers (requires proprietary module, just enable deps) */
    {"nvidia-driver", "NVIDIA GPU (proprietary)",
     "CONFIG_DRM=m CONFIG_DRM_KMS_HELPER=m"},
    
    /* Sentinel */
    {NULL, NULL, NULL}
};

/* ============================================================================
 * Security Functions
 * ============================================================================ */

/**
 * Validate that a path contains no dangerous characters or sequences.
 * Returns 1 if path is safe, 0 if path contains dangerous content.
 * 
 * Security: Prevents command injection and path traversal attacks.
 */
static int validate_path_safe(const char *path) {
    if (!path || !*path) return 0;
    
    /* Check for path traversal attempts */
    if (strstr(path, "..") != NULL) {
        return 0;
    }
    
    /* Check for shell metacharacters that could enable command injection */
    const char *dangerous_chars = ";|&$`\\\"'\n\r\t";
    for (const char *p = path; *p; p++) {
        if (strchr(dangerous_chars, *p) != NULL) {
            return 0;
        }
    }
    
    /* Check for null bytes (could truncate strings) */
    size_t len = strlen(path);
    for (size_t i = 0; i < len; i++) {
        if (path[i] == '\0') return 0;
    }
    
    return 1;
}

/**
 * Validate release version against whitelist.
 * Returns 1 if release is valid, 0 otherwise.
 * 
 * Security: Prevents arbitrary input in release parameter.
 */
static int validate_release(const char *release) {
    if (!release || !*release) return 0;
    
    for (int i = 0; VALID_RELEASES[i] != NULL; i++) {
        if (strcmp(release, VALID_RELEASES[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

/**
 * Create a secure temporary directory using mkdtemp().
 * Returns allocated string with path, or NULL on failure.
 * Caller must free the returned string.
 * 
 * Security: Prevents symlink attacks and race conditions.
 */
static char* create_secure_tempdir(const char *prefix) {
    char template[512];
    snprintf(template, sizeof(template), "/tmp/%s_XXXXXX", prefix);
    
    char *result = mkdtemp(template);
    if (!result) {
        return NULL;
    }
    
    /* Set restrictive permissions */
    chmod(result, 0700);
    
    return strdup(result);
}

/**
 * Sanitize a command string for logging (mask sensitive paths).
 * Returns a static buffer - not thread safe, for logging only.
 * 
 * Security: Prevents sensitive path disclosure in logs.
 */
static const char* sanitize_cmd_for_log(const char *cmd) {
    static char sanitized[2048];
    
    /* Copy command but mask key file paths */
    strncpy(sanitized, cmd, sizeof(sanitized) - 1);
    sanitized[sizeof(sanitized) - 1] = '\0';
    
    /* Mask private key references */
    char *key_pos;
    while ((key_pos = strstr(sanitized, ".key")) != NULL) {
        /* Find start of path (look backwards for space or quote) */
        char *path_start = key_pos;
        while (path_start > sanitized && *path_start != ' ' && *path_start != '\'') {
            path_start--;
        }
        if (*path_start == ' ' || *path_start == '\'') path_start++;
        
        /* Replace path with [PRIVATE_KEY] */
        size_t remaining = strlen(key_pos + 4);
        memmove(path_start + 13, key_pos + 4, remaining + 1);
        memcpy(path_start, "[PRIVATE_KEY]", 13);
    }
    
    return sanitized;
}

/**
 * Validate RSA key size against whitelist.
 * Returns 1 if valid, 0 otherwise.
 */
static int validate_key_size(int bits) {
    for (int i = 0; VALID_KEY_SIZES[i] != 0; i++) {
        if (bits == VALID_KEY_SIZES[i]) {
            return 1;
        }
    }
    return 0;
}

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
        /* Security: Sanitize command output to mask sensitive paths */
        printf("  $ %s\n", sanitize_cmd_for_log(cmd));
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
 * Certificate Monitoring
 * ============================================================================ */

/**
 * Check certificate expiration and return days until expiry.
 * Returns: positive = days remaining, 0 = expired today, negative = already expired
 * Returns -9999 on error.
 * 
 * Security: Monitors certificate validity to prevent using expired certs.
 */
static int check_certificate_expiry(const char *cert_path) {
    char cmd[1024];
    char output[256];
    FILE *fp;
    
    /* Use openssl to get expiry date in seconds since epoch */
    snprintf(cmd, sizeof(cmd), 
        "openssl x509 -in '%s' -noout -enddate 2>/dev/null | "
        "sed 's/notAfter=//'", cert_path);
    
    fp = popen(cmd, "r");
    if (!fp) return -9999;
    
    if (fgets(output, sizeof(output), fp) == NULL) {
        pclose(fp);
        return -9999;
    }
    pclose(fp);
    
    /* Remove trailing newline */
    size_t len = strlen(output);
    if (len > 0 && output[len-1] == '\n') output[len-1] = '\0';
    
    /* Parse the date and calculate days remaining */
    snprintf(cmd, sizeof(cmd),
        "echo $(( ($(date -d '%s' +%%s) - $(date +%%s)) / 86400 ))", output);
    
    fp = popen(cmd, "r");
    if (!fp) return -9999;
    
    int days = -9999;
    if (fscanf(fp, "%d", &days) != 1) {
        days = -9999;
    }
    pclose(fp);
    
    return days;
}

/**
 * Check all certificates in keys directory and report status.
 * Returns number of certificates with warnings/errors.
 */
static int check_all_certificates(const char *keys_dir, int warn_days) {
    int issues = 0;
    const char *cert_files[] = {"MOK.crt", "DB.crt", "KEK.crt", "PK.crt", NULL};
    
    log_step("Checking certificate expiration (warn if < %d days)...", warn_days);
    
    for (int i = 0; cert_files[i] != NULL; i++) {
        char cert_path[512];
        snprintf(cert_path, sizeof(cert_path), "%s/%s", keys_dir, cert_files[i]);
        
        if (!file_exists(cert_path)) {
            continue;  /* Skip non-existent certs */
        }
        
        int days = check_certificate_expiry(cert_path);
        
        if (days == -9999) {
            printf("  " YELLOW "[WARN]" RESET " %s: Unable to check expiration\n", cert_files[i]);
            issues++;
        } else if (days < 0) {
            printf("  " RED "[EXPIRED]" RESET " %s: Expired %d days ago!\n", cert_files[i], -days);
            issues++;
        } else if (days == 0) {
            printf("  " RED "[EXPIRED]" RESET " %s: Expires TODAY!\n", cert_files[i]);
            issues++;
        } else if (days <= warn_days) {
            printf("  " YELLOW "[WARNING]" RESET " %s: Expires in %d days\n", cert_files[i], days);
            issues++;
        } else {
            printf("  " GREEN "[OK]" RESET " %s: Valid for %d more days\n", cert_files[i], days);
        }
    }
    
    if (issues == 0) {
        log_info("All certificates are valid");
    } else {
        log_warn("%d certificate(s) need attention", issues);
    }
    
    return issues;
}

/* ============================================================================
 * Download Integrity Verification
 * ============================================================================ */

/**
 * Verify SHA3-256 checksum of a file.
 * Returns 1 if checksum matches, 0 if mismatch or error.
 * 
 * Security: Prevents man-in-the-middle attacks on downloaded files.
 */
static int verify_sha3_256(const char *file_path, const char *expected_hash) {
    char cmd[1024];
    char output[512];
    FILE *fp;
    
    /* Calculate SHA3-256 using openssl */
    snprintf(cmd, sizeof(cmd), 
        "openssl dgst -sha3-256 '%s' 2>/dev/null | awk '{print $NF}'", file_path);
    
    fp = popen(cmd, "r");
    if (!fp) {
        log_error("Failed to run SHA3-256 verification");
        return 0;
    }
    
    if (fgets(output, sizeof(output), fp) == NULL) {
        pclose(fp);
        log_error("Failed to read SHA3-256 output");
        return 0;
    }
    pclose(fp);
    
    /* Remove trailing newline */
    size_t len = strlen(output);
    if (len > 0 && output[len-1] == '\n') output[len-1] = '\0';
    
    /* Compare hashes (case-insensitive) */
    if (strcasecmp(output, expected_hash) == 0) {
        return 1;
    }
    
    log_error("SHA3-256 checksum mismatch!");
    log_error("  Expected: %s", expected_hash);
    log_error("  Got:      %s", output);
    return 0;
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
    
    /* Security: Use keys_dir for temp config instead of predictable /tmp path */
    snprintf(cnf_path, sizeof(cnf_path), "%s/.mok_config.tmp", cfg.keys_dir);
    
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
        "default_bits = %d\n"
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
        "extendedKeyUsage = codeSigning\n",
        cfg.mok_key_bits
    );
    fclose(f);
    
    snprintf(cmd, sizeof(cmd),
        "openssl req -new -x509 -newkey rsa:%d -nodes "
        "-keyout '%s' -out '%s' -days %d -config '%s' 2>/dev/null",
        cfg.mok_key_bits, key_path, crt_path, cfg.mok_days, cnf_path);
    
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
    log_info("Generated MOK key (%d-bit RSA, validity: %d days)", cfg.mok_key_bits, cfg.mok_days);
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
    
    /* Security: Use mkdtemp for secure temp directory */
    char *work_dir = create_secure_tempdir("ventoy");
    if (!work_dir) {
        log_error("Failed to create secure temp directory");
        return -1;
    }
    
    char cmd[2048];
    
    log_info("Downloading Ventoy %s...", VENTOY_VERSION);
    snprintf(cmd, sizeof(cmd),
        "wget -q --show-progress -O '%s/ventoy.tar.gz' '%s'",
        work_dir, VENTOY_URL);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to download Ventoy");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    
    /* Security: Verify SHA3-256 checksum to prevent MITM attacks */
    char ventoy_archive[512];
    snprintf(ventoy_archive, sizeof(ventoy_archive), "%s/ventoy.tar.gz", work_dir);
    
    log_info("Verifying SHA3-256 checksum...");
    if (!verify_sha3_256(ventoy_archive, VENTOY_SHA3_256)) {
        log_error("Ventoy archive integrity check FAILED!");
        log_error("The downloaded file may have been tampered with.");
        log_error("Please verify your network connection and try again.");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    log_info("SHA3-256 checksum verified OK");
    
    snprintf(cmd, sizeof(cmd), "cd '%s' && tar -xzf ventoy.tar.gz", work_dir);
    run_cmd(cmd);
    
    char disk_img[512], mount_point[512];
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
    free(work_dir);
    
    if (file_exists(shim_path)) {
        /* Security: Verify SHA3-256 checksums of extracted EFI binaries */
        log_info("Verifying extracted EFI binary checksums...");
        
        if (!verify_sha3_256(shim_path, SUSE_SHIM_SHA3_256)) {
            log_error("SUSE shim integrity check FAILED!");
            log_error("The extracted shim binary does not match expected checksum.");
            return -1;
        }
        log_info("SUSE shim SHA3-256 verified OK");
        
        if (!verify_sha3_256(mok_path, SUSE_MOKMANAGER_SHA3_256)) {
            log_error("MokManager integrity check FAILED!");
            log_error("The extracted MokManager binary does not match expected checksum.");
            return -1;
        }
        log_info("MokManager SHA3-256 verified OK");
        
        log_info("All Ventoy components verified and extracted successfully");
    } else {
        log_error("Failed to extract Ventoy components");
        return -1;
    }
    
    return 0;
}

/* ============================================================================
 * Full Kernel Build
 * ============================================================================
 * Directory structure for kernel sources:
 *   Release 4.0: /root/4.0/SPECS/linux/ (spec files and patches)
 *   Release 5.0: /root/5.0/SPECS/linux/ + /root/common/SPECS/linux/v6.1/
 *   Release 6.0: /root/common/SPECS/linux/v6.12/
 * 
 * Kernel source tarballs: /root/{release}/stage/SOURCES/linux-{version}.tar.xz
 * ============================================================================ */

/* Get kernel version from spec file */
static int get_kernel_version_from_spec(char *version, size_t ver_size) {
    char spec_path[512];
    snprintf(spec_path, sizeof(spec_path), "%s/SPECS/linux/linux.spec", cfg.photon_dir);
    
    FILE *f = fopen(spec_path, "r");
    if (!f) {
        log_warn("Spec file not found: %s", spec_path);
        return -1;
    }
    
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        /* Look for "Version:" line */
        if (strncmp(line, "Version:", 8) == 0) {
            /* Parse: "Version:        6.1.161" */
            char *ver_start = line + 8;
            while (*ver_start == ' ' || *ver_start == '\t') ver_start++;
            
            /* Remove trailing whitespace/newline */
            char *ver_end = ver_start;
            while (*ver_end && *ver_end != '\n' && *ver_end != '\r' && *ver_end != ' ') ver_end++;
            *ver_end = '\0';
            
            strncpy(version, ver_start, ver_size - 1);
            version[ver_size - 1] = '\0';
            fclose(f);
            return 0;
        }
    }
    
    fclose(f);
    return -1;
}

/* Find kernel source tarball for the release */
static int find_kernel_tarball(char *tarball_path, size_t path_size, char *version, size_t ver_size) {
    char sources_dir[512];
    snprintf(sources_dir, sizeof(sources_dir), "%s/stage/SOURCES", cfg.photon_dir);
    
    /* First, try to get version from spec file */
    char spec_version[64] = {0};
    if (get_kernel_version_from_spec(spec_version, sizeof(spec_version)) == 0) {
        /* Look for the specific tarball matching spec version */
        snprintf(tarball_path, path_size, "%s/linux-%s.tar.xz", sources_dir, spec_version);
        if (file_exists(tarball_path)) {
            strncpy(version, spec_version, ver_size - 1);
            version[ver_size - 1] = '\0';
            return 0;
        }
        
        /* Try .tar.gz extension */
        snprintf(tarball_path, path_size, "%s/linux-%s.tar.gz", sources_dir, spec_version);
        if (file_exists(tarball_path)) {
            strncpy(version, spec_version, ver_size - 1);
            version[ver_size - 1] = '\0';
            return 0;
        }
        
        /* Tarball for spec version not found - warn and offer download URL */
        log_warn("Kernel tarball for spec version %s not found", spec_version);
        log_info("Download from: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-%s.tar.xz", spec_version);
        log_info("Place in: %s/", sources_dir);
        log_info("Falling back to scanning for available tarballs...");
    }
    
    /* Fallback: scan directory for any linux-6.x tarball */
    DIR *dir = opendir(sources_dir);
    if (!dir) {
        log_warn("Sources directory not found: %s", sources_dir);
        return -1;
    }
    
    /* Parse target major.minor from spec version (e.g., 6.1 from 6.1.161) */
    int target_major = 0, target_minor = 0;
    if (spec_version[0] != '\0') {
        sscanf(spec_version, "%d.%d", &target_major, &target_minor);
    }
    
    /* Find the highest version tarball available, preferring same major.minor as spec */
    char best_tarball[512] = {0};
    char best_version[64] = {0};
    int best_major = 0, best_minor = 0, best_patch = 0;
    int best_matches_series = 0;
    
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "linux-6.", 8) == 0 && 
            (strstr(entry->d_name, ".tar.xz") || strstr(entry->d_name, ".tar.gz"))) {
            /* Skip firmware tarballs */
            if (strstr(entry->d_name, "firmware")) continue;
            
            /* Extract version from filename: linux-6.1.159.tar.xz -> 6.1.159 */
            const char *ver_start = entry->d_name + 6; /* skip "linux-" */
            const char *ver_end = strstr(ver_start, ".tar");
            if (!ver_end) continue;
            
            char this_version[64];
            size_t len = ver_end - ver_start;
            if (len >= sizeof(this_version)) continue;
            strncpy(this_version, ver_start, len);
            this_version[len] = '\0';
            
            /* Parse version numbers for comparison */
            int major = 0, minor = 0, patch = 0;
            sscanf(this_version, "%d.%d.%d", &major, &minor, &patch);
            
            /* Check if this version matches the spec's major.minor series */
            int matches_series = (target_major > 0 && major == target_major && minor == target_minor);
            
            /* Prefer versions that match the spec's series, then highest within that */
            int better = 0;
            if (matches_series && !best_matches_series) {
                /* This matches series, previous best didn't - always better */
                better = 1;
            } else if (matches_series == best_matches_series) {
                /* Both match (or don't) - compare version numbers */
                if (major > best_major || 
                    (major == best_major && minor > best_minor) ||
                    (major == best_major && minor == best_minor && patch > best_patch)) {
                    better = 1;
                }
            }
            /* If best matches series but this doesn't, keep best */
            
            if (better) {
                best_major = major;
                best_minor = minor;
                best_patch = patch;
                best_matches_series = matches_series;
                snprintf(best_tarball, sizeof(best_tarball), "%s/%s", sources_dir, entry->d_name);
                strncpy(best_version, this_version, sizeof(best_version) - 1);
            }
        }
    }
    closedir(dir);
    
    if (best_tarball[0] != '\0') {
        strncpy(tarball_path, best_tarball, path_size - 1);
        tarball_path[path_size - 1] = '\0';
        strncpy(version, best_version, ver_size - 1);
        version[ver_size - 1] = '\0';
        
        if (spec_version[0] != '\0' && strcmp(best_version, spec_version) != 0) {
            log_warn("Using kernel %s (spec file expects %s)", best_version, spec_version);
        }
        return 0;
    }
    
    return -1;
}

/* Get kernel config path based on release and architecture */
/* ============================================================================
 * Driver Integration Functions
 * ============================================================================ */

/**
 * Scan drivers directory for RPM files and return count.
 * Populates driver_rpms array with paths (up to max_rpms).
 * Returns number of RPMs found.
 */
static int scan_driver_rpms(const char *drivers_dir, char driver_rpms[][512], int max_rpms) {
    int count = 0;
    
    if (!dir_exists(drivers_dir)) {
        return 0;
    }
    
    DIR *dir = opendir(drivers_dir);
    if (!dir) {
        return 0;
    }
    
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && count < max_rpms) {
        /* Only process .rpm files */
        const char *ext = strstr(entry->d_name, ".rpm");
        if (ext && ext[4] == '\0') {
            snprintf(driver_rpms[count], 512, "%s/%s", drivers_dir, entry->d_name);
            count++;
        }
    }
    closedir(dir);
    
    return count;
}

/**
 * Extract RPM base name (without version/release/arch) from filename.
 * Example: "linux-firmware-iwlwifi-ax211-20260128-1.ph5.noarch.rpm" -> "linux-firmware-iwlwifi"
 */
static void extract_rpm_base_name(const char *rpm_path, char *base_name, size_t size) {
    /* Get just the filename */
    const char *filename = strrchr(rpm_path, '/');
    filename = filename ? filename + 1 : rpm_path;
    
    /* Copy to working buffer */
    char temp[256];
    strncpy(temp, filename, sizeof(temp) - 1);
    temp[sizeof(temp) - 1] = '\0';
    
    /* Remove .rpm extension */
    char *ext = strstr(temp, ".rpm");
    if (ext) *ext = '\0';
    
    /* Remove architecture suffix (.noarch, .x86_64, etc.) */
    char *arch_suffixes[] = {".noarch", ".x86_64", ".aarch64", ".i686", NULL};
    for (int i = 0; arch_suffixes[i]; i++) {
        char *arch = strstr(temp, arch_suffixes[i]);
        if (arch) {
            *arch = '\0';
            break;
        }
    }
    
    /* Remove version-release (find last two '-' before the end) */
    char *last_dash = strrchr(temp, '-');
    if (last_dash) {
        *last_dash = '\0';
        last_dash = strrchr(temp, '-');
        if (last_dash) {
            *last_dash = '\0';
        }
    }
    
    strncpy(base_name, temp, size - 1);
    base_name[size - 1] = '\0';
}

/**
 * Get kernel configs required for a driver RPM.
 * Returns the kernel_configs string from DRIVER_KERNEL_MAP, or NULL if not found.
 */
static const char* get_kernel_configs_for_driver(const char *rpm_base_name) {
    for (int i = 0; DRIVER_KERNEL_MAP[i].driver_prefix != NULL; i++) {
        /* Check if the RPM base name starts with the driver prefix */
        if (strncmp(rpm_base_name, DRIVER_KERNEL_MAP[i].driver_prefix, 
                    strlen(DRIVER_KERNEL_MAP[i].driver_prefix)) == 0) {
            return DRIVER_KERNEL_MAP[i].kernel_configs;
        }
    }
    return NULL;
}

/**
 * Apply driver-specific kernel configurations.
 * Scans drivers directory and enables required kernel configs.
 * Returns 0 on success, -1 on error.
 */
static int apply_driver_kernel_configs(const char *kernel_src, const char *drivers_dir) {
    char driver_rpms[64][512];
    int rpm_count = scan_driver_rpms(drivers_dir, driver_rpms, 64);
    
    if (rpm_count == 0) {
        log_info("No driver RPMs found in %s", drivers_dir);
        return 0;
    }
    
    log_info("Found %d driver RPM(s) in %s", rpm_count, drivers_dir);
    
    int configs_applied = 0;
    char cmd[4096];
    
    for (int i = 0; i < rpm_count; i++) {
        char base_name[256];
        extract_rpm_base_name(driver_rpms[i], base_name, sizeof(base_name));
        
        const char *kernel_configs = get_kernel_configs_for_driver(base_name);
        if (kernel_configs) {
            log_info("  Enabling kernel configs for: %s", base_name);
            
            /* Parse and apply each config option */
            char configs_copy[1024];
            strncpy(configs_copy, kernel_configs, sizeof(configs_copy) - 1);
            configs_copy[sizeof(configs_copy) - 1] = '\0';
            
            char *config = strtok(configs_copy, " ");
            while (config) {
                /* Parse CONFIG_NAME=value */
                char *equals = strchr(config, '=');
                if (equals) {
                    *equals = '\0';
                    char *config_name = config;
                    char *config_value = equals + 1;
                    
                    if (strcmp(config_value, "y") == 0) {
                        snprintf(cmd, sizeof(cmd), 
                            "cd '%s' && scripts/config --enable %s", 
                            kernel_src, config_name);
                    } else if (strcmp(config_value, "m") == 0) {
                        snprintf(cmd, sizeof(cmd), 
                            "cd '%s' && scripts/config --module %s", 
                            kernel_src, config_name);
                    } else {
                        snprintf(cmd, sizeof(cmd), 
                            "cd '%s' && scripts/config --set-str %s %s", 
                            kernel_src, config_name, config_value);
                    }
                    
                    if (cfg.verbose) {
                        printf("    %s=%s\n", config_name, config_value);
                    }
                    run_cmd(cmd);
                    configs_applied++;
                }
                config = strtok(NULL, " ");
            }
        } else {
            log_warn("  No kernel config mapping for: %s", base_name);
        }
    }
    
    if (configs_applied > 0) {
        log_info("Applied %d driver kernel configurations", configs_applied);
    }
    
    return 0;
}

/**
 * Copy driver RPMs to ISO and update packages_mok.json.
 * Returns 0 on success, -1 on error.
 */
static int integrate_driver_rpms(const char *drivers_dir, const char *iso_extract, 
                                  const char *initrd_extract) {
    char driver_rpms[64][512];
    int rpm_count = scan_driver_rpms(drivers_dir, driver_rpms, 64);
    
    if (rpm_count == 0) {
        return 0;
    }
    
    log_info("Integrating %d driver RPM(s) into ISO...", rpm_count);
    
    char cmd[2048];
    char rpms_dir[512];
    snprintf(rpms_dir, sizeof(rpms_dir), "%s/RPMS/noarch", iso_extract);
    mkdir_p(rpms_dir);
    snprintf(rpms_dir, sizeof(rpms_dir), "%s/RPMS/x86_64", iso_extract);
    mkdir_p(rpms_dir);
    
    /* Copy and optionally sign each driver RPM */
    char gpg_home[512];
    snprintf(gpg_home, sizeof(gpg_home), "%s/.gnupg", cfg.keys_dir);
    int sign_rpms = cfg.rpm_signing && dir_exists(gpg_home);
    
    for (int i = 0; i < rpm_count; i++) {
        const char *rpm_path = driver_rpms[i];
        const char *filename = strrchr(rpm_path, '/');
        filename = filename ? filename + 1 : rpm_path;
        
        /* Determine target directory based on architecture */
        char target_rpm[512];
        if (strstr(filename, ".noarch.rpm")) {
            snprintf(target_rpm, sizeof(target_rpm), "%s/RPMS/noarch/%s", iso_extract, filename);
        } else {
            snprintf(target_rpm, sizeof(target_rpm), "%s/RPMS/x86_64/%s", iso_extract, filename);
        }
        
        /* Copy RPM first */
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", rpm_path, target_rpm);
        run_cmd(cmd);
        
        /* Sign the RPM if --rpm-signing enabled */
        if (sign_rpms) {
            snprintf(cmd, sizeof(cmd), 
                "GNUPGHOME='%s' rpm --define '_gpg_name %s' --addsign '%s' 2>/dev/null",
                gpg_home, GPG_KEY_NAME, target_rpm);
            if (run_cmd(cmd) == 0) {
                log_info("  Signed and copied: %s", filename);
            } else {
                log_info("  Copied (signing failed): %s", filename);
            }
        } else {
            log_info("  Copied: %s", filename);
        }
    }
    
    /* Update packages_mok.json to include driver packages */
    char packages_json[512];
    snprintf(packages_json, sizeof(packages_json), "%s/installer/packages_mok.json", initrd_extract);
    
    if (file_exists(packages_json)) {
        log_info("Updating packages_mok.json with driver packages...");
        
        /* Create a Python script to add driver packages */
        char update_script[512];
        snprintf(update_script, sizeof(update_script), "%s/update_packages.py", iso_extract);
        
        FILE *f = fopen(update_script, "w");
        if (f) {
            fprintf(f,
                "#!/usr/bin/env python3\n"
                "import json\n"
                "import sys\n"
                "\n"
                "with open(sys.argv[1], 'r') as fp:\n"
                "    data = json.load(fp)\n"
                "\n"
                "# Add driver packages\n"
                "driver_packages = sys.argv[2:]\n"
                "for pkg in driver_packages:\n"
                "    if pkg not in data['packages']:\n"
                "        data['packages'].append(pkg)\n"
                "        print(f'Added: {pkg}')\n"
                "\n"
                "with open(sys.argv[1], 'w') as fp:\n"
                "    json.dump(data, fp, indent=4)\n"
            );
            fclose(f);
            
            /* Build command with all driver package names */
            char pkg_args[2048] = "";
            for (int i = 0; i < rpm_count; i++) {
                char base_name[256];
                extract_rpm_base_name(driver_rpms[i], base_name, sizeof(base_name));
                
                /* Append full package name (with version) for better specificity */
                const char *filename = strrchr(driver_rpms[i], '/');
                filename = filename ? filename + 1 : driver_rpms[i];
                char pkg_name[256];
                strncpy(pkg_name, filename, sizeof(pkg_name) - 1);
                char *ext = strstr(pkg_name, ".rpm");
                if (ext) *ext = '\0';
                /* Remove arch suffix */
                char *arch = strstr(pkg_name, ".noarch");
                if (!arch) arch = strstr(pkg_name, ".x86_64");
                if (arch) *arch = '\0';
                /* Remove version-release */
                char *dash = strrchr(pkg_name, '-');
                if (dash) *dash = '\0';
                dash = strrchr(pkg_name, '-');
                if (dash) *dash = '\0';
                
                strcat(pkg_args, " '");
                strcat(pkg_args, pkg_name);
                strcat(pkg_args, "'");
            }
            
            snprintf(cmd, sizeof(cmd), "python3 '%s' '%s'%s 2>&1", 
                     update_script, packages_json, pkg_args);
            run_cmd(cmd);
            
            unlink(update_script);
        }
    }
    
    return 0;
}

static int find_kernel_config(char *config_path, size_t path_size, const char *arch, const char *flavor) {
    char path[512];
    
    /* Determine config filename based on arch and flavor */
    const char *config_name;
    if (strcmp(flavor, "esx") == 0) {
        if (strcmp(arch, "x86_64") == 0) {
            config_name = "config-esx_x86_64";
        } else {
            config_name = "config-esx_aarch64";
        }
    } else if (strcmp(flavor, "rt") == 0) {
        config_name = "config-rt";
    } else {
        /* Default/generic config */
        if (strcmp(arch, "aarch64") == 0) {
            config_name = "config_aarch64";
        } else {
            config_name = "config";
        }
    }
    
    /* Check release-specific SPECS first */
    snprintf(path, sizeof(path), "%s/SPECS/linux/%s", cfg.photon_dir, config_name);
    if (file_exists(path)) {
        strncpy(config_path, path, path_size - 1);
        return 0;
    }
    
    /* Check common SPECS based on release */
    const char *kernel_version_dir = NULL;
    if (strcmp(cfg.release, "5.0") == 0) {
        kernel_version_dir = "v6.1";
    } else if (strcmp(cfg.release, "6.0") == 0) {
        kernel_version_dir = "v6.12";
    }
    
    if (kernel_version_dir) {
        snprintf(path, sizeof(path), "/root/common/SPECS/linux/%s/%s", kernel_version_dir, config_name);
        if (file_exists(path)) {
            strncpy(config_path, path, path_size - 1);
            return 0;
        }
    }
    
    return -1;
}

static int build_linux_kernel(void) {
    const char *arch = get_host_arch();
    char cmd[4096];
    
    log_step("Linux %s kernel build...", arch);
    
    log_warn("Kernel build will take a long time (1-4 hours depending on CPU)!");
    printf("\n");
    printf("The full kernel build process includes:\n");
    printf("  1. Extracting kernel source tarball\n");
    printf("  2. Applying Photon OS kernel config\n");
    printf("  3. Configuring for Secure Boot (MODULE_SIG, LOCK_DOWN)\n");
    printf("  4. Building kernel and modules\n");
    printf("  5. Signing kernel with MOK key\n");
    printf("  6. Signing all modules with kernel module signing key\n");
    printf("\n");
    
    /* Find kernel source tarball */
    char tarball_path[512], kernel_version[64];
    if (find_kernel_tarball(tarball_path, sizeof(tarball_path), 
                            kernel_version, sizeof(kernel_version)) != 0) {
        log_error("No kernel source tarball found in %s/stage/SOURCES/", cfg.photon_dir);
        log_info("Expected: linux-6.x.x.tar.xz");
        log_info("Download from: https://cdn.kernel.org/pub/linux/kernel/v6.x/");
        return -1;
    }
    
    log_info("Found kernel source: %s (version %s)", tarball_path, kernel_version);
    
    /* Setup build directory */
    char build_dir[512], kernel_src[512];
    snprintf(build_dir, sizeof(build_dir), "%s/kernel-build", cfg.photon_dir);
    snprintf(kernel_src, sizeof(kernel_src), "%s/linux-%s", build_dir, kernel_version);
    
    /* Clean and create build directory */
    snprintf(cmd, sizeof(cmd), "rm -rf '%s' && mkdir -p '%s'", build_dir, build_dir);
    run_cmd(cmd);
    
    /* Extract kernel source */
    log_info("Extracting kernel source...");
    if (strstr(tarball_path, ".tar.xz")) {
        snprintf(cmd, sizeof(cmd), "tar -xJf '%s' -C '%s'", tarball_path, build_dir);
    } else {
        snprintf(cmd, sizeof(cmd), "tar -xzf '%s' -C '%s'", tarball_path, build_dir);
    }
    if (run_cmd(cmd) != 0) {
        log_error("Failed to extract kernel source");
        return -1;
    }
    
    if (!file_exists(kernel_src)) {
        log_error("Kernel source directory not found after extraction: %s", kernel_src);
        return -1;
    }
    
    /* Find and copy kernel config */
    char config_path[512];
    const char *flavor = "esx"; /* Default to esx for better VM support */
    
    if (find_kernel_config(config_path, sizeof(config_path), arch, flavor) == 0) {
        log_info("Using kernel config: %s", config_path);
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/.config'", config_path, kernel_src);
        run_cmd(cmd);
        
        /* Copy Photon certificate bundle if it exists (required by CONFIG_SYSTEM_TRUSTED_KEYS) */
        char cert_bundle_src[512], cert_bundle_dst[512];
        
        /* Try release-specific SPECS first */
        snprintf(cert_bundle_src, sizeof(cert_bundle_src), "%s/SPECS/linux/photon-cert-bundle.pem", cfg.photon_dir);
        if (!file_exists(cert_bundle_src)) {
            /* Try common SPECS */
            const char *kernel_version_dir = NULL;
            if (strcmp(cfg.release, "5.0") == 0) kernel_version_dir = "v6.1";
            else if (strcmp(cfg.release, "6.0") == 0) kernel_version_dir = "v6.12";
            if (kernel_version_dir) {
                snprintf(cert_bundle_src, sizeof(cert_bundle_src), "/root/common/SPECS/linux/%s/photon-cert-bundle.pem", kernel_version_dir);
            }
        }
        
        if (file_exists(cert_bundle_src)) {
            snprintf(cert_bundle_dst, sizeof(cert_bundle_dst), "%s/photon-cert-bundle.pem", kernel_src);
            log_info("Copying Photon certificate bundle...");
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", cert_bundle_src, cert_bundle_dst);
            run_cmd(cmd);
        } else {
            /* Disable SYSTEM_TRUSTED_KEYS if bundle not found */
            log_warn("Photon certificate bundle not found, disabling CONFIG_SYSTEM_TRUSTED_KEYS");
            snprintf(cmd, sizeof(cmd), 
                "cd '%s' && scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ''",
                kernel_src);
            run_cmd(cmd);
        }
    } else {
        log_warn("No Photon kernel config found, using defconfig");
        snprintf(cmd, sizeof(cmd), "cd '%s' && make defconfig", kernel_src);
        run_cmd(cmd);
    }
    
    /* Configure Secure Boot options */
    log_info("Configuring kernel for Secure Boot...");
    snprintf(cmd, sizeof(cmd),
        "cd '%s' && "
        "scripts/config --enable CONFIG_MODULE_SIG && "
        "scripts/config --enable CONFIG_MODULE_SIG_ALL && "
        "scripts/config --enable CONFIG_MODULE_SIG_SHA512 && "
        "scripts/config --set-str CONFIG_MODULE_SIG_HASH sha512 && "
        "scripts/config --enable CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY && "
        "scripts/config --enable CONFIG_SECURITY_LOCKDOWN_LSM && "
        "scripts/config --enable CONFIG_SECURITY_LOCKDOWN_LSM_EARLY && "
        "scripts/config --enable CONFIG_EFI_STUB && "
        "scripts/config --enable CONFIG_EFI",
        kernel_src);
    run_cmd(cmd);
    
    /* Configure USB drivers as built-in for reliable USB boot
     * This eliminates the need for rd.driver.pre kernel parameters
     * because the drivers are compiled into the kernel itself.
     * Essential for both installer (ISO boot) and installed system (USB boot) */
    log_info("Configuring USB drivers as built-in...");
    snprintf(cmd, sizeof(cmd),
        "cd '%s' && "
        "scripts/config --enable CONFIG_USB && "
        "scripts/config --enable CONFIG_USB_SUPPORT && "
        "scripts/config --enable CONFIG_USB_PCI && "
        "scripts/config --enable CONFIG_USB_XHCI_HCD && "
        "scripts/config --enable CONFIG_USB_XHCI_PCI && "
        "scripts/config --enable CONFIG_USB_EHCI_HCD && "
        "scripts/config --enable CONFIG_USB_EHCI_PCI && "
        "scripts/config --enable CONFIG_USB_UHCI_HCD && "
        "scripts/config --enable CONFIG_USB_STORAGE && "
        "scripts/config --enable CONFIG_USB_UAS && "
        "scripts/config --enable CONFIG_BLK_DEV_SD && "
        "scripts/config --enable CONFIG_SCSI && "
        "scripts/config --enable CONFIG_SCSI_MOD",
        kernel_src);
    run_cmd(cmd);
    
    /* Apply driver-specific kernel configs if --drivers specified */
    if (cfg.include_drivers && cfg.drivers_dir[0] != '\0') {
        log_info("Applying kernel configs for driver packages...");
        if (apply_driver_kernel_configs(kernel_src, cfg.drivers_dir) == 0) {
            log_info("Driver kernel configs applied successfully");
        } else {
            log_warn("Some driver kernel configs may not have been applied");
        }
    }
    
    /* Copy module signing key */
    char signing_key[512];
    snprintf(signing_key, sizeof(signing_key), "%s/kernel_module_signing.pem", cfg.keys_dir);
    if (file_exists(signing_key)) {
        log_info("Installing module signing key...");
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/certs/signing_key.pem'", signing_key, kernel_src);
        run_cmd(cmd);
        
        /* Configure kernel to use our signing key */
        snprintf(cmd, sizeof(cmd),
            "cd '%s' && "
            "scripts/config --set-str CONFIG_MODULE_SIG_KEY certs/signing_key.pem && "
            "scripts/config --enable CONFIG_MODULE_SIG_FORCE",
            kernel_src);
        run_cmd(cmd);
    }
    
    /* Update config with new options */
    snprintf(cmd, sizeof(cmd), "cd '%s' && make olddefconfig", kernel_src);
    run_cmd(cmd);
    
    /* Build kernel */
    log_step("Building Linux kernel for %s...", arch);
    log_warn("This will take a very long time (1-4 hours depending on CPU)...");
    
    int nproc = 4; /* Default */
    FILE *fp = popen("nproc", "r");
    if (fp) {
        fscanf(fp, "%d", &nproc);
        pclose(fp);
    }
    
    if (strcmp(arch, "x86_64") == 0) {
        snprintf(cmd, sizeof(cmd), "cd '%s' && make -j%d bzImage modules 2>&1", kernel_src, nproc);
    } else if (strcmp(arch, "aarch64") == 0) {
        snprintf(cmd, sizeof(cmd), "cd '%s' && make -j%d Image modules 2>&1", kernel_src, nproc);
    } else {
        log_error("Unsupported architecture: %s", arch);
        return -1;
    }
    
    log_info("Running: make -j%d in %s", nproc, kernel_src);
    if (run_cmd(cmd) != 0) {
        log_error("Kernel build failed");
        return -1;
    }
    
    /* Find and sign the kernel image */
    char vmlinuz[512], vmlinuz_signed[512];
    if (strcmp(arch, "x86_64") == 0) {
        snprintf(vmlinuz, sizeof(vmlinuz), "%s/arch/x86/boot/bzImage", kernel_src);
    } else {
        snprintf(vmlinuz, sizeof(vmlinuz), "%s/arch/arm64/boot/Image", kernel_src);
    }
    snprintf(vmlinuz_signed, sizeof(vmlinuz_signed), "%s/vmlinuz-%s-mok", build_dir, kernel_version);
    
    if (file_exists(vmlinuz)) {
        log_info("Signing kernel with MOK key...");
        snprintf(cmd, sizeof(cmd),
            "sbsign --key '%s/MOK.key' --cert '%s/MOK.crt' --output '%s' '%s'",
            cfg.keys_dir, cfg.keys_dir, vmlinuz_signed, vmlinuz);
        if (run_cmd(cmd) == 0) {
            log_info("Kernel signed successfully: %s", vmlinuz_signed);
            
            /* Copy to a well-known location for ISO build */
            char final_kernel[512];
            snprintf(final_kernel, sizeof(final_kernel), "%s/vmlinuz-mok", cfg.keys_dir);
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", vmlinuz_signed, final_kernel);
            run_cmd(cmd);
            log_info("Signed kernel available at: %s", final_kernel);
        } else {
            log_warn("Failed to sign kernel - sbsign error");
        }
    } else {
        log_error("Kernel image not found: %s", vmlinuz);
        return -1;
    }
    
    /* Install modules to a staging area */
    char modules_dir[512];
    snprintf(modules_dir, sizeof(modules_dir), "%s/modules", build_dir);
    snprintf(cmd, sizeof(cmd), "cd '%s' && make INSTALL_MOD_PATH='%s' modules_install", 
             kernel_src, modules_dir);
    log_info("Installing kernel modules...");
    run_cmd(cmd);
    
    log_info("%s kernel build complete!", arch);
    log_info("Kernel version: %s", kernel_version);
    log_info("Build directory: %s", build_dir);
    log_info("Signed kernel: %s/vmlinuz-mok", cfg.keys_dir);
    
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
    
    /* Step 0: Build custom kernel with USB drivers as built-in (mandatory in v1.9.0+) */
    log_info("Building custom kernel with built-in USB drivers...");
    if (build_linux_kernel() != 0) {
        log_error("Kernel build failed - cannot create Secure Boot ISO");
        return -1;
    }
    
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
    
    /* Extract initrd to add MOK package options and apply patches
     * 
     * IMPORTANT: We do NOT use kickstart files for interactive installation!
     * The Photon OS installer only runs its interactive UI when NO kickstart is provided.
     * If any kickstart is passed (even with ui:true), the installer tries to use those
     * values directly and fails if required fields (like disk) are missing.
     *
     * Instead, we modify the initrd to:
     * 1. Add MOK package options to build_install_options_all.json
     * 2. Create packages_mok.json with MOK-signed packages
     * 3. Apply progress_bar bug fix (in case of errors during installation)
     *
     * The GRUB menu will boot WITHOUT ks= parameter, launching the full interactive
     * installer where users can select "Photon MOK Secure Boot" as their package choice. */
    log_info("Modifying initrd for MOK package options...");
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
                "# Fix 3: In _execute_modules, add None check for progress_bar.update_message\n"
                "# This is called from _load_preinstall BEFORE progress_bar is created\n"
                "old_exec = '''if self.install_config.get('ui', False):\n"
                "                self.progress_bar.update_message('Setting up GRUB')'''\n"
                "new_exec = '''if self.install_config.get('ui', False) and self.progress_bar is not None:\n"
                "                self.progress_bar.update_message('Setting up GRUB')'''\n"
                "content = content.replace(old_exec, new_exec)\n"
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
    
    /* Patch linuxselector.py to recognize linux-mok kernel flavor
     * The LinuxSelector class has a hardcoded dict of known kernel flavors.
     * Without this patch, selecting packages with linux-mok causes ZeroDivisionError
     * because no menu items are created (linux-mok not in the dict). */
    char linuxselector_py[512];
    snprintf(linuxselector_py, sizeof(linuxselector_py),
        "%s/usr/lib/python3.11/site-packages/photon_installer/linuxselector.py", initrd_extract);
    
    if (file_exists(linuxselector_py)) {
        log_info("Patching linuxselector.py to recognize linux-mok...");
        
        char patch_linux_script[512];
        snprintf(patch_linux_script, sizeof(patch_linux_script), "%s/patch_linuxselector.py", work_dir);
        
        FILE *pf = fopen(patch_linux_script, "w");
        if (pf) {
            fprintf(pf,
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "\n"
                "with open(sys.argv[1], 'r') as f:\n"
                "    content = f.read()\n"
                "\n"
                "# Add linux-mok to the linux_flavors dictionary\n"
                "old = 'linux_flavors = {\"linux\":\"Generic\"'\n"
                "new = 'linux_flavors = {\"linux-mok\":\"MOK Secure Boot\", \"linux\":\"Generic\"'\n"
                "content = content.replace(old, new, 1)\n"
                "\n"
                "with open(sys.argv[1], 'w') as f:\n"
                "    f.write(content)\n"
                "\n"
                "print('linuxselector.py patched for linux-mok')\n"
            );
            fclose(pf);
            
            snprintf(cmd, sizeof(cmd), "python3 '%s' '%s' 2>&1", patch_linux_script, linuxselector_py);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "rm -f '%s'", patch_linux_script);
            run_cmd(cmd);
        }
        log_info("Patched linuxselector.py with linux-mok support");
    } else {
        log_warn("linuxselector.py not found at expected path");
    }
    
    /* Option C: Add "Photon MOK Secure Boot" as new entry in build_install_options_all.json
     * This preserves original Minimal/Developer/etc options while adding explicit MOK choice.
     * See ADR-001 in DROID_SKILL_GUIDE.md for rationale. */
    char options_json[512], mok_packages_json[512];
    snprintf(options_json, sizeof(options_json), "%s/installer/build_install_options_all.json", initrd_extract);
    snprintf(mok_packages_json, sizeof(mok_packages_json), "%s/installer/packages_mok.json", initrd_extract);
    
    if (file_exists(options_json)) {
        log_info("Adding MOK Secure Boot option to installer...");
        
        /* Create packages_mok.json with MOK-signed packages
         * Note: grub2-theme provides /boot/grub2/fonts/ascii.pf2 and theme files
         * which are required for the themed GRUB menu to display properly */
        FILE *f = fopen(mok_packages_json, "w");
        if (f) {
            fprintf(f,
                "{\n"
                "    \"packages\": [\n"
                "        \"minimal\",\n"
                "        \"linux-mok\",\n"
                "        \"initramfs\",\n"
                "        \"grub2-efi-image-mok\",\n"
                "        \"grub2-theme\",\n"
                "        \"shim-signed-mok\",\n"
                "        \"lvm2\",\n"
                "        \"less\",\n"
                "        \"sudo\",\n"
                "        \"libnl\",\n"
                "        \"wpa_supplicant\",\n"
                "        \"wireless-regdb\",\n"
                "        \"iw\",\n"
                "        \"wifi-config\"\n"
                "    ]\n"
                "}\n"
            );
            /* Note: WiFi packages include:
             * - wireless-regdb: kernel.org wireless regulatory database
             * - iw: nl80211 wireless configuration utility
             * - wifi-config: configures wpa_supplicant, disables iwlwifi LAR, DHCP for wlan0
             * - wpa_supplicant: from Photon 5.0 repos
             * - libnl: dependency of iw, from Photon 5.0 repos
             * Custom packages must be in drivers/RPM and built with --drivers flag. */
            fclose(f);
            log_info("Created packages_mok.json");
        }
        
        /* Add MOK option to build_install_options_all.json as first entry
         * Renumber existing visible options (1->2, 2->3, etc.) */
        char add_mok_script[512];
        snprintf(add_mok_script, sizeof(add_mok_script), "%s/add_mok_option.py", work_dir);
        
        FILE *pf = fopen(add_mok_script, "w");
        if (pf) {
            fprintf(pf,
                "#!/usr/bin/env python3\n"
                "import json\n"
                "import sys\n"
                "from collections import OrderedDict\n"
                "\n"
                "with open(sys.argv[1], 'r') as f:\n"
                "    options = json.load(f, object_pairs_hook=OrderedDict)\n"
                "\n"
                "# Renumber existing visible options (1->2, 2->3, etc.)\n"
                "for key, value in options.items():\n"
                "    if value.get('visible', False) and 'title' in value:\n"
                "        title = value['title']\n"
                "        if len(title) > 1 and title[0].isdigit() and title[1] == '.':\n"
                "            new_num = int(title[0]) + 1\n"
                "            value['title'] = str(new_num) + title[1:]\n"
                "\n"
                "# Create new ordered dict with MOK option first\n"
                "new_options = OrderedDict()\n"
                "new_options['mok'] = {\n"
                "    'title': '1. Photon MOK Secure Boot',\n"
                "    'packagelist_file': 'packages_mok.json',\n"
                "    'visible': True\n"
                "}\n"
                "\n"
                "# Add all existing options after MOK\n"
                "for key, value in options.items():\n"
                "    new_options[key] = value\n"
                "\n"
                "with open(sys.argv[1], 'w') as f:\n"
                "    json.dump(new_options, f, indent=4)\n"
                "\n"
                "print('MOK option added as first entry')\n"
            );
            fclose(pf);
            
            snprintf(cmd, sizeof(cmd), "python3 '%s' '%s' 2>&1", add_mok_script, options_json);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "rm -f '%s'", add_mok_script);
            run_cmd(cmd);
        }
        log_info("Added 'Photon MOK Secure Boot' to installer package selection");
    } else {
        log_warn("build_install_options_all.json not found in initrd");
    }
    
    /* Patch mk-setup-grub.sh to fix boot parameters for USB/FIPS compatibility
     * This is necessary because:
     * 1. The installer creates grub.cfg from this template AFTER all RPM scriptlets run
     * 2. Neither %post nor %posttrans can reliably modify grub.cfg
     * 3. We must patch the template itself to ensure proper boot parameters
     */
    char grub_setup_script[512];
    snprintf(grub_setup_script, sizeof(grub_setup_script), 
        "%s/usr/lib/python3.11/site-packages/photon_installer/mk-setup-grub.sh", initrd_extract);
    
    if (file_exists(grub_setup_script)) {
        log_info("Patching mk-setup-grub.sh for USB boot compatibility...");
        
        /* Keep graphical mode for splash screen - don't change gfxpayload or terminal_output
         * The black screen issue was caused by missing USB drivers in initrd, not graphics mode.
         * The linux-mok %post script now includes USB drivers via dracut --add-drivers.
         */
        
        /* Add USB boot parameters to EXTRA_PARAMS:
         * - rootwait: Wait for root device to appear (essential for USB)
         * - usbcore.autosuspend=-1: Disable USB autosuspend for reliability
         * - rd.driver.pre=xhci_pci,ehci_pci,usb_storage: Force-load USB drivers
         *   early in initrd before root device is accessed
         *
         * Using rd.driver.pre kernel parameter is cleaner than dracut config files
         * because it's visible in grub.cfg and doesn't require modifying initrd.
         */
        snprintf(cmd, sizeof(cmd), 
            "sed -i 's/EXTRA_PARAMS=\"\"/EXTRA_PARAMS=\"rootwait usbcore.autosuspend=-1 rd.driver.pre=xhci_pci,ehci_pci,usb_storage\"/' '%s'", 
            grub_setup_script);
        run_cmd(cmd);
        
        /* Also ensure EXTRA_PARAMS are added even when not empty (nvme case) */
        snprintf(cmd, sizeof(cmd), 
            "sed -i 's/EXTRA_PARAMS=rootwait$/EXTRA_PARAMS=\"rootwait usbcore.autosuspend=-1 rd.driver.pre=xhci_pci,ehci_pci,usb_storage\"/' '%s'", 
            grub_setup_script);
        run_cmd(cmd);
        
        log_info("Patched mk-setup-grub.sh: Added USB boot params with rd.driver.pre");
        
        /* Add eFuse USB verification to installed system's grub.cfg if enabled
         * This must be added to mk-setup-grub.sh template because:
         * 1. The installer generates grub.cfg AFTER all RPM %posttrans scripts run
         * 2. %posttrans modifications get overwritten by mk-setup-grub.sh
         * 3. Only patching the template ensures eFuse verification persists
         *
         * We inject the eFuse verification code BEFORE the menuentry line in the heredoc */
        if (cfg.efuse_usb_mode) {
            log_info("Adding eFuse USB verification to installed system grub.cfg...");
            
            /* Create a Python script to inject eFuse verification into mk-setup-grub.sh
             * We insert the eFuse check code just before 'menuentry "Photon"' */
            char efuse_patch_script[512];
            snprintf(efuse_patch_script, sizeof(efuse_patch_script), "%s/patch_efuse_grub.py", work_dir);
            
            FILE *epf = fopen(efuse_patch_script, "w");
            if (epf) {
                fprintf(epf,
                    "#!/usr/bin/env python3\n"
                    "import sys\n"
                    "\n"
                    "with open(sys.argv[1], 'r') as f:\n"
                    "    content = f.read()\n"
                    "\n"
                    "# eFuse verification code to inject before menuentry\n"
                    "efuse_code = '''\n"
                    "# HABv4 eFuse USB Verification\n"
                    "set efuse_verified=0\n"
                    "search --no-floppy --label EFUSE_SIM --set=efuse_disk\n"
                    "if [ -n \"\\\\$efuse_disk\" ]; then\n"
                    "    if [ -f (\\\\$efuse_disk)/efuse_sim/srk_fuse.bin ]; then\n"
                    "        set efuse_verified=1\n"
                    "    fi\n"
                    "fi\n"
                    "if [ \"\\\\$efuse_verified\" = \"0\" ]; then\n"
                    "    terminal_output console\n"
                    "    echo \"\"\n"
                    "    echo \"=========================================\"\n"
                    "    echo \"  HABv4 SECURITY: eFuse USB Required\"\n"
                    "    echo \"=========================================\"\n"
                    "    echo \"\"\n"
                    "    echo \"Insert eFuse USB dongle (label: EFUSE_SIM)\"\n"
                    "    echo \"and press any key to retry.\"\n"
                    "    echo \"\"\n"
                    "    read anykey\n"
                    "    configfile \\\\${BOOT_DIR}/grub2/grub.cfg\n"
                    "fi\n"
                    "# Restore graphical terminal for themed boot menu after eFuse verification\n"
                    "terminal_output gfxterm\n"
                    "\n"
                    "'''\n"
                    "\n"
                    "# Find the menuentry line and insert efuse code before it\n"
                    "marker = 'menuentry \"Photon\"'\n"
                    "if marker in content:\n"
                    "    content = content.replace(marker, efuse_code + marker)\n"
                    "    print('eFuse verification code injected before menuentry')\n"
                    "else:\n"
                    "    print('WARNING: menuentry not found, eFuse code not injected')\n"
                    "\n"
                    "with open(sys.argv[1], 'w') as f:\n"
                    "    f.write(content)\n"
                );
                fclose(epf);
                
                snprintf(cmd, sizeof(cmd), "python3 '%s' '%s' 2>&1", efuse_patch_script, grub_setup_script);
                run_cmd(cmd);
                
                snprintf(cmd, sizeof(cmd), "rm -f '%s'", efuse_patch_script);
                run_cmd(cmd);
                
                log_info("eFuse USB verification added to mk-setup-grub.sh template");
            }
        }
    } else {
        log_warn("mk-setup-grub.sh not found in initrd - grub.cfg may have suboptimal settings");
    }
    
    /* Integrate driver RPMs if --drivers specified
     * This MUST happen BEFORE initrd is repacked so packages_mok.json can be updated */
    if (cfg.include_drivers && cfg.drivers_dir[0] != '\0') {
        log_info("Integrating driver RPMs...");
        if (integrate_driver_rpms(cfg.drivers_dir, iso_extract, initrd_extract) == 0) {
            log_info("Driver RPMs integrated successfully");
        } else {
            log_warn("Some driver RPMs may not have been integrated");
        }
    }
    
    /* Install GPG keys into initrd for RPM signature verification
     * TDNF supports multiple keys via space-separated paths in gpgkey config.
     * We install both VMware's keys (from photon-repos) and our HABv4 key
     * to verify both original Photon packages and our custom MOK packages. */
    if (cfg.rpm_signing) {
        char gpg_key_dest_dir[512], photon_iso_repo[512];
        snprintf(gpg_key_dest_dir, sizeof(gpg_key_dest_dir), "%s/etc/pki/rpm-gpg", initrd_extract);
        snprintf(photon_iso_repo, sizeof(photon_iso_repo), "%s/etc/yum.repos.d/photon-iso.repo", initrd_extract);
        
        log_info("Installing GPG keys into initrd for package verification...");
        snprintf(cmd, sizeof(cmd), "mkdir -p '%s'", gpg_key_dest_dir);
        run_cmd(cmd);
        
        /* Extract VMware's GPG keys from photon-repos package */
        char photon_repos_rpm[512];
        snprintf(photon_repos_rpm, sizeof(photon_repos_rpm), 
            "%s/RPMS/noarch/photon-repos-*.rpm", iso_extract);
        snprintf(cmd, sizeof(cmd),
            "cd '%s' && rpm2cpio %s 2>/dev/null | cpio -idm './etc/pki/rpm-gpg/*' 2>/dev/null",
            initrd_extract, photon_repos_rpm);
        if (run_cmd(cmd) == 0) {
            log_info("VMware GPG keys extracted from photon-repos");
        }
        
        /* Install our HABv4 GPG key */
        char habv4_key_src[512], habv4_key_dest[512];
        snprintf(habv4_key_src, sizeof(habv4_key_src), "%s/%s", iso_extract, GPG_KEY_FILE);
        snprintf(habv4_key_dest, sizeof(habv4_key_dest), "%s/RPM-GPG-KEY-habv4", gpg_key_dest_dir);
        
        if (file_exists(habv4_key_src)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", habv4_key_src, habv4_key_dest);
            run_cmd(cmd);
            log_info("HABv4 GPG key installed at /etc/pki/rpm-gpg/RPM-GPG-KEY-habv4");
        } else {
            log_warn("HABv4 GPG key not found at %s", habv4_key_src);
        }
        
        /* Update photon-iso.repo to include both VMware and HABv4 keys
         * TDNF supports multiple keys via space-separated paths */
        if (file_exists(photon_iso_repo)) {
            snprintf(cmd, sizeof(cmd),
                "sed -i 's|^gpgkey=.*|gpgkey=file:///etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY "
                "file:///etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY-4096 "
                "file:///etc/pki/rpm-gpg/RPM-GPG-KEY-habv4|' '%s'",
                photon_iso_repo);
            run_cmd(cmd);
            log_info("Updated photon-iso.repo with VMware + HABv4 GPG keys");
        }
    }
    
    /* Repack initrd */
    snprintf(cmd, sizeof(cmd), 
        "cd '%s' && find . | cpio -o -H newc 2>/dev/null | gzip -9 > '%s'",
        initrd_extract, initrd_new);
    run_cmd(cmd);
    
    /* Replace original initrd */
    snprintf(cmd, sizeof(cmd), "mv '%s' '%s'", initrd_new, initrd_orig);
    run_cmd(cmd);
    log_info("Updated initrd with MOK package options");
    
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
    FILE *f = fopen(stub_cfg, "w");
    if (f) {
        fprintf(f,
            "# Use text mode initially to avoid garbled graphics on some hardware\n"
            "terminal_output console\n"
            "# Reset graphics state before loading themed config\n"
            "set gfxmode=auto\n"
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
     * png/jpeg/tga (for background images), and gfxterm_background.
     * CRITICAL: Include search_label for eFuse USB detection by label,
     * and usb/usbms for USB device support at boot time. */
    snprintf(cmd, sizeof(cmd),
        "grub2-mkimage -O x86_64-efi -o '%s' -c '%s' -p /boot/grub2 --sbat '%s' "
        "normal search search_label search_fs_uuid search_fs_file "
        "configfile linux chain fat part_gpt part_msdos iso9660 "
        "usb usbms scsi disk "
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
                "    menuentry \"Install\" {\n"
                "        linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 usbcore.autosuspend=-1 photon.media=LABEL=PHOTON_SB_%s\n"
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
                cfg.release
            );
            log_info("eFuse USB verification mode ENABLED in grub.cfg");
        } else {
            /* Standard mode: Interactive installer (NO kickstart) 
             * The installer will show the full interactive UI including:
             * - EULA acceptance
             * - Disk selection
             * - Package selection (Minimal now uses MOK packages)
             * - Hostname configuration
             * - Password configuration */
            fprintf(f,
                "# Photon OS Installer - Modified for Secure Boot\n"
                "# Interactive installation - Minimal uses MOK packages\n"
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
                "menuentry \"Install\" {\n"
                "    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 usbcore.autosuspend=-1 photon.media=LABEL=PHOTON_SB_%s\n"
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
                cfg.release
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
            cfg.verbose,
            cfg.efuse_usb_mode
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
                        /* Re-copy signed MOK RPMs to ISO (they were copied before signing) */
                        log_info("Updating ISO with signed MOK RPMs...");
                        snprintf(cmd, sizeof(cmd), 
                            "cp '%s'/*-mok-*.rpm '%s/RPMS/x86_64/' 2>/dev/null", 
                            output_dir, iso_extract);
                        run_cmd(cmd);
                        
                        /* Copy GPG public key to ISO root */
                        char gpg_pub[512], gpg_iso[512];
                        snprintf(gpg_pub, sizeof(gpg_pub), "%s/%s", cfg.keys_dir, GPG_KEY_FILE);
                        snprintf(gpg_iso, sizeof(gpg_iso), "%s/%s", iso_extract, GPG_KEY_FILE);
                        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", gpg_pub, gpg_iso);
                        run_cmd(cmd);
                        log_info("GPG public key copied to ISO root");
                        
                        /* Regenerate repodata after updating RPMs */
                        log_info("Regenerating repository metadata...");
                        snprintf(cmd, sizeof(cmd), 
                            "cd '%s/RPMS' && createrepo_c --update . 2>/dev/null || createrepo --update . 2>/dev/null",
                            iso_extract);
                        run_cmd(cmd);
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
    
    /* Security: Use mkdtemp for secure temp directory */
    char *work_dir = create_secure_tempdir("iso_diagnose");
    if (!work_dir) {
        log_error("Failed to create secure temp directory");
        return -1;
    }
    
    char cmd[2048];
    
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
    free(work_dir);
    
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
    printf("  -K, --key-bits=BITS        RSA key size: 2048, 3072, 4096 (default: %d)\n", DEFAULT_MOK_KEY_BITS);
    printf("  -W, --cert-warn=DAYS       Warn if certificate expires within DAYS (default: %d)\n", DEFAULT_CERT_WARN_DAYS);
    printf("  -C, --check-certs          Check certificate expiration status\n");
    printf("  -b, --build-iso            Build Secure Boot ISO\n");
    printf("  -g, --generate-keys        Generate cryptographic keys\n");
    printf("  -s, --setup-efuse          Setup eFuse simulation\n");
    printf("  -d, --drivers[=DIR]        Include driver RPMs (default: drivers/RPM)\n");
    printf("  -u, --create-efuse-usb=DEV Create eFuse USB dongle on device (e.g., /dev/sdb)\n");
    printf("  -E, --efuse-usb            Enable eFuse USB dongle verification in GRUB\n");
    printf("  -R, --rpm-signing          Enable GPG signing of MOK RPM packages\n");
    /* -F/--full-kernel-build removed in v1.9.0 - kernel build is now mandatory */
    printf("  -D, --diagnose=ISO         Diagnose an existing ISO for Secure Boot issues\n");
    printf("  -c, --clean                Clean up all artifacts\n");
    printf("  -v, --verbose              Verbose output\n");
    printf("  -y, --yes                  Auto-confirm destructive operations (e.g., erase USB)\n");
    printf("  -h, --help                 Show this help\n");
    printf("\n");
    printf("Security Options:\n");
    printf("  --key-bits=4096            Use 4096-bit RSA keys (stronger, slower)\n");
    printf("  --check-certs              Check all certificates for expiration\n");
    printf("  --cert-warn=60             Warn 60 days before certificate expiration\n");
    printf("\n");
    printf("Default behavior (no action flags):\n");
    printf("  When no action flags (-b, -g, -s, -d, -u, -c, -F) are specified,\n");
    printf("  the tool runs: -g -s -d (generate keys, setup eFuse, download Ventoy)\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s                         # Default: setup keys, eFuse, Ventoy\n", PROGRAM_NAME);
    printf("  %s -b                      # Build Secure Boot ISO\n", PROGRAM_NAME);
    printf("  %s -r 4.0 -b               # Build for Photon OS 4.0\n", PROGRAM_NAME);
    printf("  %s -K 4096 -m 365 -g       # Generate 4096-bit keys valid 1 year\n", PROGRAM_NAME);
    printf("  %s -C                      # Check certificate expiration status\n", PROGRAM_NAME);
    printf("  %s -E -b                   # Build ISO with eFuse USB verification\n", PROGRAM_NAME);
    printf("  %s -R -b                   # Build ISO with RPM signing\n", PROGRAM_NAME);
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
    cfg.mok_key_bits = DEFAULT_MOK_KEY_BITS;
    cfg.cert_warn_days = DEFAULT_CERT_WARN_DAYS;
    
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
        {"key-bits",          required_argument, 0, 'K'},
        {"cert-warn",         required_argument, 0, 'W'},
        {"check-certs",       no_argument,       0, 'C'},
        {"build-iso",         no_argument,       0, 'b'},
        {"generate-keys",     no_argument,       0, 'g'},
        {"setup-efuse",       no_argument,       0, 's'},
        {"drivers",           optional_argument, 0, 'd'},
        {"create-efuse-usb",  required_argument, 0, 'u'},
        {"efuse-usb",         no_argument,       0, 'E'},
        {"rpm-signing",       no_argument,       0, 'R'},
        /* {"full-kernel-build", no_argument, 0, 'F'}, -- removed in v1.9.0, kernel build is now mandatory */
        {"diagnose",          required_argument, 0, 'D'},
        {"clean",             no_argument,       0, 'c'},
        {"verbose",           no_argument,       0, 'v'},
        {"yes",               no_argument,       0, 'y'},
        {"help",              no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "r:i:o:k:e:m:K:W:Cbgsd::ERFD:cu:vyh", long_options, NULL)) != -1) {
        switch (opt) {
            case 'r':
                /* Security: Validate release against whitelist */
                if (!validate_release(optarg)) {
                    log_error("Invalid release version: %s (valid: 4.0, 5.0, 6.0)", optarg);
                    return 1;
                }
                strncpy(cfg.release, optarg, sizeof(cfg.release) - 1);
                snprintf(cfg.photon_dir, sizeof(cfg.photon_dir), "%s/%s", home, cfg.release);
                break;
            case 'i':
                /* Security: Validate path for command injection */
                if (!validate_path_safe(optarg)) {
                    log_error("Invalid input ISO path (contains dangerous characters)");
                    return 1;
                }
                strncpy(cfg.input_iso, optarg, sizeof(cfg.input_iso) - 1);
                break;
            case 'o':
                /* Security: Validate path for command injection */
                if (!validate_path_safe(optarg)) {
                    log_error("Invalid output ISO path (contains dangerous characters)");
                    return 1;
                }
                strncpy(cfg.output_iso, optarg, sizeof(cfg.output_iso) - 1);
                break;
            case 'k':
                /* Security: Validate path for command injection */
                if (!validate_path_safe(optarg)) {
                    log_error("Invalid keys directory path (contains dangerous characters)");
                    return 1;
                }
                strncpy(cfg.keys_dir, optarg, sizeof(cfg.keys_dir) - 1);
                break;
            case 'e':
                /* Security: Validate path for command injection */
                if (!validate_path_safe(optarg)) {
                    log_error("Invalid efuse directory path (contains dangerous characters)");
                    return 1;
                }
                strncpy(cfg.efuse_dir, optarg, sizeof(cfg.efuse_dir) - 1);
                break;
            case 'm':
                cfg.mok_days = atoi(optarg);
                if (cfg.mok_days < 1 || cfg.mok_days > 3650) {
                    log_error("MOK days must be between 1 and 3650");
                    return 1;
                }
                break;
            case 'K':
                cfg.mok_key_bits = atoi(optarg);
                if (!validate_key_size(cfg.mok_key_bits)) {
                    log_error("Invalid key size: %d (valid: 2048, 3072, 4096)", cfg.mok_key_bits);
                    return 1;
                }
                break;
            case 'W':
                cfg.cert_warn_days = atoi(optarg);
                if (cfg.cert_warn_days < 1 || cfg.cert_warn_days > 365) {
                    log_error("Certificate warning days must be between 1 and 365");
                    return 1;
                }
                break;
            case 'C':
                cfg.check_certs = 1;
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
            case 'd':
                cfg.include_drivers = 1;
                if (optarg) {
                    /* --drivers=DIR specified */
                    if (!validate_path_safe(optarg)) {
                        log_error("Invalid drivers directory path (contains dangerous characters)");
                        return 1;
                    }
                    strncpy(cfg.drivers_dir, optarg, sizeof(cfg.drivers_dir) - 1);
                } else {
                    /* --drivers without argument - use default relative to executable */
                    char exe_dir[512], project_root[512];
                    get_executable_dir(exe_dir, sizeof(exe_dir));
                    snprintf(project_root, sizeof(project_root), "%s/..", exe_dir);
                    snprintf(cfg.drivers_dir, sizeof(cfg.drivers_dir), "%s/%s", project_root, DEFAULT_DRIVERS_DIR);
                }
                break;
            case 'u':
                /* Security: Validate device path */
                if (!validate_path_safe(optarg)) {
                    log_error("Invalid USB device path (contains dangerous characters)");
                    return 1;
                }
                strncpy(cfg.efuse_usb_device, optarg, sizeof(cfg.efuse_usb_device) - 1);
                break;
            case 'E':
                cfg.efuse_usb_mode = 1;
                break;
            case 'R':
                cfg.rpm_signing = 1;
                break;
            case 'F':
                /* -F/--full-kernel-build removed in v1.9.0 - kernel build is now mandatory */
                log_warn("Option -F/--full-kernel-build is deprecated (kernel build is now mandatory)");
                break;
            case 'D':
                /* Security: Validate path for command injection */
                if (!validate_path_safe(optarg)) {
                    log_error("Invalid diagnose ISO path (contains dangerous characters)");
                    return 1;
                }
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
    
    /* Check certificate expiration if requested */
    if (cfg.check_certs) {
        int cert_issues = check_all_certificates(cfg.keys_dir, cfg.cert_warn_days);
        /* If only checking certs (no other action), exit with appropriate code */
        if (!cfg.generate_keys && !cfg.setup_efuse && 
            !cfg.build_iso &&
            strlen(cfg.efuse_usb_device) == 0) {
            return (cert_issues > 0) ? 1 : 0;
        }
    }
    
    /* Handle eFuse USB creation - but don't return early if --build-iso is also set */
    int efuse_usb_requested = (strlen(cfg.efuse_usb_device) > 0);
    if (efuse_usb_requested) {
        if (!cfg.generate_keys) cfg.generate_keys = 1;
        if (!cfg.setup_efuse) cfg.setup_efuse = 1;
    }
    
    /* If no specific action, default to full setup (generate keys) */
    if (!cfg.generate_keys && !cfg.setup_efuse && !cfg.build_iso) {
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
    printf("MOK Key Size:      %d-bit RSA\n", cfg.mok_key_bits);
    printf("MOK Validity:      %d days\n", cfg.mok_days);
    printf("Cert Warn Days:    %d\n", cfg.cert_warn_days);
    if (cfg.build_iso) printf("Build ISO:         YES\n");
    if (cfg.efuse_usb_mode) printf("eFuse USB Mode:    ENABLED\n");
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
    } else {
        /* Setup was done - suggest building ISO */
        printf("  - Build ISO:        %s -b\n", PROGRAM_NAME);
        printf("  - With eFuse mode:  %s -E -b\n", PROGRAM_NAME);
        printf("  - Create eFuse USB: %s -u /dev/sdX\n", PROGRAM_NAME);
        printf("  - Cleanup:          %s -c\n", PROGRAM_NAME);
    }
    log_info("=========================================");
    
    return 0;
}
