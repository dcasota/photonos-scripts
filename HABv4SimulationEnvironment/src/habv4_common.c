/*
 * habv4_common.c
 *
 * Common utility functions for PhotonOS-HABv4Emulation-ISOCreator
 * Includes logging, file operations, validation, and certificate functions.
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include "habv4_common.h"

/* ============================================================================
 * Global Variables
 * ============================================================================ */

/* Valid key sizes (whitelist) */
const int VALID_KEY_SIZES[] = {2048, 3072, 4096, 0};

/* Valid release versions (whitelist) */
const char *VALID_RELEASES[] = {"4.0", "5.0", "6.0", NULL};

/* Global configuration instance */
config_t cfg;

/* Driver-to-Kernel-Config Mapping */
const driver_kernel_map_t DRIVER_KERNEL_MAP[] = {
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
    {"linux-firmware-e1000e", "Intel Ethernet (e1000e)", "CONFIG_E1000E=m"},
    {"linux-firmware-igb", "Intel Gigabit Ethernet (igb)", "CONFIG_IGB=m"},
    {"linux-firmware-ixgbe", "Intel 10GbE (ixgbe)", "CONFIG_IXGBE=m"},
    
    /* NVIDIA GPU drivers */
    {"nvidia-driver", "NVIDIA GPU (proprietary)", "CONFIG_DRM=m CONFIG_DRM_KMS_HELPER=m"},
    
    /* Sentinel */
    {NULL, NULL, NULL}
};

/* ============================================================================
 * Logging Functions
 * ============================================================================ */

void log_info(const char *fmt, ...) {
    va_list args;
    printf(GREEN "[INFO]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

void log_step(const char *fmt, ...) {
    va_list args;
    printf(BLUE "[STEP]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

void log_warn(const char *fmt, ...) {
    va_list args;
    printf(YELLOW "[WARN]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

void log_error(const char *fmt, ...) {
    va_list args;
    fprintf(stderr, RED "[ERROR]" RESET " ");
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
}

/* ============================================================================
 * Security/Validation Functions
 * ============================================================================ */

int validate_path_safe(const char *path) {
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

int validate_release(const char *release) {
    if (!release || !*release) return 0;
    
    for (int i = 0; VALID_RELEASES[i] != NULL; i++) {
        if (strcmp(release, VALID_RELEASES[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

char* create_secure_tempdir(const char *prefix) {
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

const char* sanitize_cmd_for_log(const char *cmd) {
    static char sanitized[2048];
    
    strncpy(sanitized, cmd, sizeof(sanitized) - 1);
    sanitized[sizeof(sanitized) - 1] = '\0';
    
    /* Mask private key references */
    char *key_pos;
    while ((key_pos = strstr(sanitized, ".key")) != NULL) {
        char *path_start = key_pos;
        while (path_start > sanitized && *path_start != ' ' && *path_start != '\'') {
            path_start--;
        }
        if (*path_start == ' ' || *path_start == '\'') path_start++;
        
        size_t remaining = strlen(key_pos + 4);
        memmove(path_start + 13, key_pos + 4, remaining + 1);
        memcpy(path_start, "[PRIVATE_KEY]", 13);
    }
    
    return sanitized;
}

int validate_key_size(int bits) {
    for (int i = 0; VALID_KEY_SIZES[i] != 0; i++) {
        if (bits == VALID_KEY_SIZES[i]) {
            return 1;
        }
    }
    return 0;
}

/* ============================================================================
 * Basic Utility Functions
 * ============================================================================ */

int run_cmd(const char *cmd) {
    if (cfg.verbose) {
        printf("  $ %s\n", sanitize_cmd_for_log(cmd));
    }
    int ret = system(cmd);
    return WEXITSTATUS(ret);
}

int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

int dir_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

int mkdir_p(const char *path) {
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

long get_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return st.st_size;
}

const char *get_host_arch(void) {
    struct utsname uts;
    if (uname(&uts) == 0) {
        if (strcmp(uts.machine, "x86_64") == 0) return "x86_64";
        if (strcmp(uts.machine, "aarch64") == 0) return "aarch64";
    }
    return "unknown";
}

/* ============================================================================
 * Certificate Functions
 * ============================================================================ */

int check_certificate_expiry(const char *cert_path) {
    char cmd[1024];
    char output[256];
    FILE *fp;
    
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
    
    size_t len = strlen(output);
    if (len > 0 && output[len-1] == '\n') output[len-1] = '\0';
    
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

int check_all_certificates(const char *keys_dir, int warn_days) {
    int issues = 0;
    const char *cert_files[] = {"MOK.crt", "DB.crt", "KEK.crt", "PK.crt", NULL};
    
    log_step("Checking certificate expiration (warn if < %d days)...", warn_days);
    
    for (int i = 0; cert_files[i] != NULL; i++) {
        char cert_path[512];
        snprintf(cert_path, sizeof(cert_path), "%s/%s", keys_dir, cert_files[i]);
        
        if (!file_exists(cert_path)) {
            continue;
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

int verify_sha3_256(const char *file_path, const char *expected_hash) {
    char cmd[1024];
    char output[512];
    FILE *fp;
    
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
    
    size_t len = strlen(output);
    if (len > 0 && output[len-1] == '\n') output[len-1] = '\0';
    
    if (strcasecmp(output, expected_hash) == 0) {
        return 1;
    }
    
    log_error("SHA3-256 checksum mismatch!");
    log_error("  Expected: %s", expected_hash);
    log_error("  Got:      %s", output);
    return 0;
}
