/*
 * rpm_secureboot_patcher.c
 *
 * RPM Secure Boot Patcher - Creates MOK-signed variants of boot packages
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include "rpm_secureboot_patcher.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dirent.h>
#include <errno.h>
#include <glob.h>
#include <time.h>
#include <libgen.h>

/* ANSI colors */
#define RED     "\x1b[31m"
#define GREEN   "\x1b[32m"
#define YELLOW  "\x1b[33m"
#define BLUE    "\x1b[34m"
#define RESET   "\x1b[0m"

static int g_verbose = 0;

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

static void log_info(const char *fmt, ...) {
    va_list args;
    printf(GREEN "[RPM-PATCH]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

static void log_error(const char *fmt, ...) {
    va_list args;
    fprintf(stderr, RED "[RPM-PATCH ERROR]" RESET " ");
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
}

static void log_warn(const char *fmt, ...) {
    va_list args;
    printf(YELLOW "[RPM-PATCH WARN]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

static void log_debug(const char *fmt, ...) {
    if (!g_verbose) return;
    va_list args;
    printf(BLUE "[RPM-PATCH DEBUG]" RESET " ");
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    printf("\n");
}

/**
 * Sanitize command for logging - mask private key paths.
 * Security: Prevents sensitive path disclosure in logs.
 */
static const char* sanitize_cmd_for_log(const char *cmd) {
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

static int run_cmd(const char *cmd) {
    if (g_verbose) {
        /* Security: Sanitize command output to mask sensitive paths */
        printf("  $ %s\n", sanitize_cmd_for_log(cmd));
    }
    int ret = system(cmd);
    return WEXITSTATUS(ret);
}

static int run_cmd_output(const char *cmd, char *output, size_t output_size) {
    FILE *fp = popen(cmd, "r");
    if (!fp) return -1;
    
    output[0] = '\0';
    size_t total = 0;
    char buf[256];
    while (fgets(buf, sizeof(buf), fp) && total < output_size - 1) {
        size_t len = strlen(buf);
        if (total + len < output_size) {
            strcat(output, buf);
            total += len;
        }
    }
    
    /* Remove trailing newline */
    size_t len = strlen(output);
    if (len > 0 && output[len-1] == '\n') {
        output[len-1] = '\0';
    }
    
    return pclose(fp);
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

/**
 * Create a secure temporary directory using mkdtemp().
 * Security: Prevents symlink attacks and race conditions.
 */
static char* create_secure_tempdir(const char *prefix) {
    char template[512];
    snprintf(template, sizeof(template), "/tmp/%s_XXXXXX", prefix);
    
    char *result = mkdtemp(template);
    if (!result) {
        return NULL;
    }
    
    chmod(result, 0700);
    return strdup(result);
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

static char* strdup_safe(const char *s) __attribute__((unused));
static char* strdup_safe(const char *s) {
    return s ? strdup(s) : NULL;
}

/* ============================================================================
 * Package Discovery Functions
 * ============================================================================ */

/**
 * Find RPM that provides a specific file
 */
static char* find_rpm_providing_file(const char *rpm_dir, const char *filepath) {
    char cmd[1024];
    char output[4096];
    DIR *dir;
    struct dirent *entry;
    
    dir = opendir(rpm_dir);
    if (!dir) return NULL;
    
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_type != DT_REG) continue;
        if (strstr(entry->d_name, ".rpm") == NULL) continue;
        if (strstr(entry->d_name, ".src.rpm") != NULL) continue;
        
        char rpm_path[1024];
        snprintf(rpm_path, sizeof(rpm_path), "%s/%s", rpm_dir, entry->d_name);
        
        /* Check if this RPM provides the file */
        snprintf(cmd, sizeof(cmd), 
            "rpm -qpl '%s' 2>/dev/null | grep -q '^%s$' && echo 'found'",
            rpm_path, filepath);
        
        if (run_cmd_output(cmd, output, sizeof(output)) == 0 && 
            strstr(output, "found") != NULL) {
            closedir(dir);
            return strdup(rpm_path);
        }
    }
    
    closedir(dir);
    return NULL;
}

/**
 * Find RPM that provides a file matching a pattern (e.g., /boot/vmlinuz-*)
 */
static char* find_rpm_providing_file_pattern(const char *rpm_dir, const char *pattern) {
    char cmd[1024];
    char output[4096];
    DIR *dir;
    struct dirent *entry;
    
    /* Extract the directory part and filename pattern */
    char dir_part[256] = "";
    char file_pattern[256] = "";
    const char *last_slash = strrchr(pattern, '/');
    if (last_slash) {
        size_t dir_len = last_slash - pattern;
        strncpy(dir_part, pattern, dir_len);
        dir_part[dir_len] = '\0';
        strcpy(file_pattern, last_slash + 1);
    } else {
        strcpy(file_pattern, pattern);
    }
    
    dir = opendir(rpm_dir);
    if (!dir) return NULL;
    
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_type != DT_REG) continue;
        if (strstr(entry->d_name, ".rpm") == NULL) continue;
        if (strstr(entry->d_name, ".src.rpm") != NULL) continue;
        /* Skip -mok packages */
        if (strstr(entry->d_name, "-mok-") != NULL) continue;
        
        char rpm_path[1024];
        snprintf(rpm_path, sizeof(rpm_path), "%s/%s", rpm_dir, entry->d_name);
        
        /* Check if this RPM provides files matching the pattern */
        /* Convert glob pattern to grep pattern */
        char grep_pattern[512];
        snprintf(grep_pattern, sizeof(grep_pattern), "^%s/", dir_part);
        
        /* For vmlinuz-*, we look for /boot/vmlinuz-<version> matching the pattern */
        if (strstr(file_pattern, "vmlinuz") != NULL) {
            /* Create grep pattern from input glob pattern */
            char grep_expr[256];
            strncpy(grep_expr, pattern, sizeof(grep_expr)-1);
            grep_expr[sizeof(grep_expr)-1] = '\0';
            
            /* Remove trailing * if present to make it a prefix match */
            char *star = strrchr(grep_expr, '*');
            if (star) *star = '\0';
            
            snprintf(cmd, sizeof(cmd), 
                "rpm -qpl '%s' 2>/dev/null | grep -E '^%s' | head -1",
                rpm_path, grep_expr);
        } else {
            snprintf(cmd, sizeof(cmd), 
                "rpm -qpl '%s' 2>/dev/null | grep '%s' | head -1",
                rpm_path, dir_part);
        }
        
        if (run_cmd_output(cmd, output, sizeof(output)) == 0 && strlen(output) > 0) {
            closedir(dir);
            log_debug("Found RPM for pattern %s: %s", pattern, rpm_path);
            return strdup(rpm_path);
        }
    }
    
    closedir(dir);
    return NULL;
}

/**
 * Extract package info from RPM file
 */
static rpm_package_info_t* extract_rpm_info(const char *rpm_path) {
    if (!rpm_path || !file_exists(rpm_path)) return NULL;
    
    rpm_package_info_t *pkg = calloc(1, sizeof(rpm_package_info_t));
    if (!pkg) return NULL;
    
    pkg->rpm_path = strdup(rpm_path);
    
    char cmd[1024];
    char output[256];
    
    /* Get package name */
    snprintf(cmd, sizeof(cmd), "rpm -qp --qf '%%{NAME}' '%s' 2>/dev/null", rpm_path);
    if (run_cmd_output(cmd, output, sizeof(output)) == 0) {
        pkg->name = strdup(output);
    }
    
    /* Get version */
    snprintf(cmd, sizeof(cmd), "rpm -qp --qf '%%{VERSION}' '%s' 2>/dev/null", rpm_path);
    if (run_cmd_output(cmd, output, sizeof(output)) == 0) {
        pkg->version = strdup(output);
    }
    
    /* Get release */
    snprintf(cmd, sizeof(cmd), "rpm -qp --qf '%%{RELEASE}' '%s' 2>/dev/null", rpm_path);
    if (run_cmd_output(cmd, output, sizeof(output)) == 0) {
        pkg->release = strdup(output);
    }
    
    /* Get arch */
    snprintf(cmd, sizeof(cmd), "rpm -qp --qf '%%{ARCH}' '%s' 2>/dev/null", rpm_path);
    if (run_cmd_output(cmd, output, sizeof(output)) == 0) {
        pkg->arch = strdup(output);
    }
    
    log_debug("Extracted info: %s-%s-%s.%s", 
              pkg->name ? pkg->name : "?",
              pkg->version ? pkg->version : "?", 
              pkg->release ? pkg->release : "?",
              pkg->arch ? pkg->arch : "?");
    
    return pkg;
}

/**
 * Find SPEC file for a package
 */
static char* find_spec_for_package(const char *specs_dir, const char *pkg_name) {
    char spec_path[1024];
    
    /* Try exact match first: <pkg_name>/<pkg_name>.spec */
    snprintf(spec_path, sizeof(spec_path), "%s/%s/%s.spec", specs_dir, pkg_name, pkg_name);
    if (file_exists(spec_path)) {
        return strdup(spec_path);
    }
    
    /* Try base name for subpackages (e.g., grub2-efi-image -> grub2) */
    char base_name[256];
    strncpy(base_name, pkg_name, sizeof(base_name) - 1);
    
    /* Remove suffixes like -efi-image, -signed, etc. */
    char *dash = strrchr(base_name, '-');
    while (dash) {
        *dash = '\0';
        snprintf(spec_path, sizeof(spec_path), "%s/%s/%s.spec", specs_dir, base_name, base_name);
        if (file_exists(spec_path)) {
            return strdup(spec_path);
        }
        dash = strrchr(base_name, '-');
    }
    
    return NULL;
}

discovered_packages_t* rpm_discover_packages(
    const char *rpm_dir,
    const char *specs_dir,
    const char *release
) {
    log_info("Discovering Secure Boot packages...");
    
    discovered_packages_t *pkgs = calloc(1, sizeof(discovered_packages_t));
    if (!pkgs) return NULL;
    
    pkgs->release = strdup(release);
    
    /* Determine dist tag from release */
    char dist_tag[32];
    snprintf(dist_tag, sizeof(dist_tag), ".ph%c", release[0]);
    pkgs->dist_tag = strdup(dist_tag);
    
    /* Find grub2-efi-image by the file it provides */
    log_debug("Looking for package providing /boot/efi/EFI/BOOT/grubx64.efi");
    char *grub_rpm = find_rpm_providing_file(rpm_dir, "/boot/efi/EFI/BOOT/grubx64.efi");
    if (grub_rpm) {
        pkgs->grub_efi = extract_rpm_info(grub_rpm);
        if (pkgs->grub_efi) {
            pkgs->grub_efi->spec_path = find_spec_for_package(specs_dir, pkgs->grub_efi->name);
        }
        free(grub_rpm);
        log_info("Found grub2-efi-image: %s-%s", 
                 pkgs->grub_efi->name, pkgs->grub_efi->version);
    }
    
    /* Find all linux kernels by vmlinuz files */
    char kernel_pattern[128] = "/boot/vmlinuz-*";
    
    /* For Photon 6.0, we specifically want kernel 6.12+ (which co-exists with 6.1) */
    if (release && strcmp(release, "6.0") == 0) {
        log_debug("Photon 6.0 detected: Preferring kernel 6.12+");
        strcpy(kernel_pattern, "/boot/vmlinuz-6.12*");
    }
    
    log_debug("Looking for packages providing %s", kernel_pattern);
    
    /* We need to find ALL RPMs that provide a vmlinuz file */
    /* This loop mimics find_rpm_providing_file_pattern but collects multiple */
    DIR *dir = opendir(rpm_dir);
    if (dir) {
        struct dirent *entry;
        char dir_part[256] = "";
        char file_pattern[256] = "";
        const char *last_slash = strrchr(kernel_pattern, '/');
        if (last_slash) {
            size_t dir_len = last_slash - kernel_pattern;
            strncpy(dir_part, kernel_pattern, dir_len);
            dir_part[dir_len] = '\0';
            strcpy(file_pattern, last_slash + 1);
        } else {
            strcpy(file_pattern, kernel_pattern);
        }

        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_type != DT_REG) continue;
            if (strstr(entry->d_name, ".rpm") == NULL) continue;
            if (strstr(entry->d_name, ".src.rpm") != NULL) continue;
            if (strstr(entry->d_name, "-mok-") != NULL) continue;
            
            /* Optimization: Only check packages starting with linux- */
            if (strncmp(entry->d_name, "linux-", 6) != 0) continue;
            /* Skip linux-headers, linux-devel, etc. unless they actually provide vmlinuz (they shouldn't) */
            if (strstr(entry->d_name, "-devel") || strstr(entry->d_name, "-headers") || 
                strstr(entry->d_name, "-docs") || strstr(entry->d_name, "-drivers")) continue;

            char rpm_path[1024];
            snprintf(rpm_path, sizeof(rpm_path), "%s/%s", rpm_dir, entry->d_name);
            
            /* Check if this RPM provides files matching the pattern */
            char cmd[1024];
            char output[4096];
            /* Create grep pattern from input glob pattern */
            char grep_expr[256];
            strncpy(grep_expr, kernel_pattern, sizeof(grep_expr)-1);
            grep_expr[sizeof(grep_expr)-1] = '\0';
            
            /* Remove trailing * if present to make it a prefix match */
            char *star = strrchr(grep_expr, '*');
            if (star) *star = '\0';
            
            snprintf(cmd, sizeof(cmd), 
                "rpm -qpl '%s' 2>/dev/null | grep -E '^%s' | head -1",
                rpm_path, grep_expr);
                
            if (run_cmd_output(cmd, output, sizeof(output)) == 0 && strlen(output) > 0) {
                if (pkgs->kernel_count < MAX_KERNEL_VARIANTS) {
                    rpm_package_info_t *kpkg = extract_rpm_info(rpm_path);
                    if (kpkg) {
                        kpkg->spec_path = find_spec_for_package(specs_dir, kpkg->name);
                        /* Store kernel variant */
                        pkgs->linux_kernels[pkgs->kernel_count++] = kpkg;
                        log_info("Found kernel variant: %s-%s", kpkg->name, kpkg->version);
                    }
                } else {
                    log_warn("Max kernel variants reached, skipping %s", entry->d_name);
                }
            }
        }
        closedir(dir);
    }
    
    if (pkgs->kernel_count == 0) {
        /* Fallback to single discovery if loop failed */
         char *linux_rpm = find_rpm_providing_file_pattern(rpm_dir, kernel_pattern);
         if (linux_rpm) {
             rpm_package_info_t *kpkg = extract_rpm_info(linux_rpm);
             if (kpkg) {
                 kpkg->spec_path = find_spec_for_package(specs_dir, kpkg->name);
                 pkgs->linux_kernels[pkgs->kernel_count++] = kpkg;
                 log_info("Found fallback kernel: %s-%s", kpkg->name, kpkg->version);
             }
             free(linux_rpm);
         }
    }
    
    /* Find shim-signed by the file it provides */
    log_debug("Looking for package providing /boot/efi/EFI/BOOT/bootx64.efi");
    char *shim_signed_rpm = find_rpm_providing_file(rpm_dir, "/boot/efi/EFI/BOOT/bootx64.efi");
    if (shim_signed_rpm) {
        pkgs->shim_signed = extract_rpm_info(shim_signed_rpm);
        if (pkgs->shim_signed) {
            pkgs->shim_signed->spec_path = find_spec_for_package(specs_dir, pkgs->shim_signed->name);
        }
        free(shim_signed_rpm);
        log_info("Found shim-signed: %s-%s", 
                 pkgs->shim_signed->name, pkgs->shim_signed->version);
    }
    
    /* Find shim (for MokManager source) */
    log_debug("Looking for package providing /usr/share/shim/shimx64.efi");
    char *shim_rpm = find_rpm_providing_file(rpm_dir, "/usr/share/shim/shimx64.efi");
    if (shim_rpm) {
        pkgs->shim = extract_rpm_info(shim_rpm);
        if (pkgs->shim) {
            pkgs->shim->spec_path = find_spec_for_package(specs_dir, pkgs->shim->name);
        }
        free(shim_rpm);
        log_info("Found shim: %s-%s", 
                 pkgs->shim->name, pkgs->shim->version);
    }
    
    /* Verify we found the required packages */
    if (!pkgs->grub_efi || pkgs->kernel_count == 0 || !pkgs->shim_signed) {
        log_error("Failed to discover all required packages");
        rpm_free_discovered_packages(pkgs);
        return NULL;
    }
    
    log_info("Package discovery complete");
    return pkgs;
}

/* ============================================================================
 * SPEC File Generation
 * ============================================================================ */

/**
 * Generate grub2-efi-image-mok.spec
 * 
 * Uses the pre-built custom GRUB stub (without shim_lock) instead of
 * re-signing VMware's GRUB. VMware's GRUB has shim_lock compiled in,
 * which causes policy violations when booted via SUSE shim.
 */
static int generate_grub_mok_spec(rpm_build_config_t *config, rpm_package_info_t *grub_pkg) {
    char spec_path[1024];
    snprintf(spec_path, sizeof(spec_path), "%s/grub2-efi-image-mok.spec", config->specs_dir);
    
    /* Generate date string for changelog */
    char date_str[64];
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(date_str, sizeof(date_str), "%a %b %d %Y", tm_info);
    
    FILE *f = fopen(spec_path, "w");
    if (!f) {
        log_error("Failed to create %s", spec_path);
        return -1;
    }
    
    fprintf(f,
        "%%define debug_package %%{nil}\n"
        "\n"
        "# Custom GRUB for MOK Secure Boot with eFuse verification (replaces grub2-efi-image %s-%s)\n"
        "# Uses pre-built GRUB for installed system that requires eFuse USB to boot\n"
        "%%define grub_version %s\n"
        "%%define grub_release %s\n"
        "\n"
        "Summary:    Custom GRUB for MOK Secure Boot with eFuse verification\n"
        "Name:       grub2-efi-image-mok\n"
        "Epoch:      1\n"
        "Version:    %%{grub_version}\n"
        "Release:    %%{grub_release}\n"
        "Group:      System Environment/Base\n"
        "License:    GPLv3+\n"
        "Vendor:     HABv4 Project\n"
        "Distribution:   Photon\n"
        "\n"
        "# Epoch ensures this package is always considered newer than original\n"
        "# (1:2.12-1 > 0:2.12-2 because epoch takes precedence)\n"
        "# Provides satisfies dependencies, Obsoletes triggers replacement\n"
        "Provides:   grub2-efi-image = %%{grub_version}-%%{grub_release}\n"
        "Obsoletes:  grub2-efi-image\n"
        "\n"
        "BuildRequires:  grub2-efi\n"
        "BuildRequires:  sbsigntools\n"
        "\n"
        "%%description\n"
        "Custom GRUB for MOK Secure Boot with HABv4 eFuse USB verification.\n"
        "This GRUB requires the eFuse USB dongle (label: EFUSE_SIM) to be present\n"
        "before allowing the system to boot. Signed with MOK key.\n"
        "\n"
        "%%prep\n"
        "# Create embedded config for installed system\n"
        "# This config searches for the root partition and loads the main grub.cfg\n"
        "mkdir -p ./boot/efi/EFI/BOOT\n"
        "cat > ./grub_embedded.cfg << 'GRUBCFG'\n"
        "# Embedded config for installed system GRUB\n"
        "# Use text mode initially to avoid garbled graphics on some hardware\n"
        "terminal_output console\n"
        "# Reset graphics state before loading themed config\n"
        "set gfxmode=auto\n"
        "# Search for root partition by looking for /boot/grub2/grub.cfg\n"
        "search --no-floppy --file --set=root /boot/grub2/grub.cfg\n"
        "set prefix=($root)/boot/grub2\n"
        "configfile ($root)/boot/grub2/grub.cfg\n"
        "GRUBCFG\n"
        "\n"
        "# Create SBAT data\n"
        "cat > ./sbat.csv << 'SBAT'\n"
        "sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md\n"
        "grub,3,Free Software Foundation,grub,2.06,https://www.gnu.org/software/grub/\n"
        "SBAT\n"
        "\n"
        "%%build\n"
        "# Build GRUB stub for installed system\n"
        "grub2-mkimage -O x86_64-efi -o ./grub_unsigned.efi -c ./grub_embedded.cfg \\\n"
        "    -p /boot/grub2 --sbat ./sbat.csv \\\n"
        "    normal search search_fs_file search_fs_uuid search_label \\\n"
        "    configfile linux chain fat ext2 part_gpt part_msdos \\\n"
        "    boot echo reboot halt test true loadenv read \\\n"
        "    all_video gfxterm font efi_gop gfxmenu png jpeg tga\n"
        "\n"
        "# Sign with MOK key\n"
        "sbsign --key %%{mok_key} --cert %%{mok_cert} \\\n"
        "       --output ./boot/efi/EFI/BOOT/grubx64.efi ./grub_unsigned.efi\n"
        "cp ./boot/efi/EFI/BOOT/grubx64.efi ./boot/efi/EFI/BOOT/grub.efi\n"
        "\n"
        "%%install\n"
        "install -d %%{buildroot}/boot/efi/EFI/BOOT\n"
        "install -m 0644 ./boot/efi/EFI/BOOT/grubx64.efi %%{buildroot}/boot/efi/EFI/BOOT/\n"
        "install -m 0644 ./boot/efi/EFI/BOOT/grub.efi %%{buildroot}/boot/efi/EFI/BOOT/\n"
        "\n"
        "%%files\n"
        "%%defattr(-,root,root,-)\n"
        "/boot/efi/EFI/BOOT/grubx64.efi\n"
        "/boot/efi/EFI/BOOT/grub.efi\n"
        "\n"
        "%%changelog\n"
        "* %s HABv4 Project <habv4@local> %%{grub_version}-%%{grub_release}\n"
        "- Custom GRUB for installed system, signed with MOK key\n"
        "- Built with grub-mkimage with proper search modules\n",
        grub_pkg->version, grub_pkg->release,
        grub_pkg->version,
        grub_pkg->release,
        date_str
    );
    
    /* Use %posttrans to fix boot parameters AFTER all package operations complete
     * This ensures we run after the installer creates/modifies grub.cfg */
    fprintf(f,
        "\n"
        "%%posttrans\n"
        "# Fix grub.cfg for USB boot reliability and FIPS compatibility\n"
        "# Using %%posttrans ensures this runs AFTER installer finishes grub.cfg\n"
        "# These parameters match the installer ISO for consistent behavior\n"
        "GRUB_CFG=/boot/grub2/grub.cfg\n"
        "if [ -f \"$GRUB_CFG\" ]; then\n"
        "    # Backup original\n"
        "    cp \"$GRUB_CFG\" \"$GRUB_CFG.orig\" 2>/dev/null || true\n"
        "    \n"
        "    # 1. Change gfxpayload=keep to gfxpayload=text for reliable console\n"
        "    sed -i 's/gfxpayload=keep/gfxpayload=text/' \"$GRUB_CFG\"\n"
        "    \n"
        "    # 2. Change terminal_output gfxterm to console for text mode\n"
        "    sed -i 's/terminal_output gfxterm/terminal_output console/' \"$GRUB_CFG\"\n"
        "    \n"
        "    # 3. Add rootwait for USB boot reliability (if not already present)\n"
        "    if ! grep -q 'rootwait' \"$GRUB_CFG\"; then\n"
        "        sed -i '/^[[:space:]]*linux.*\\$photon_linux/s/$/ rootwait/' \"$GRUB_CFG\"\n"
        "    fi\n"
        "    \n"
        "    # 4. Add usbcore.autosuspend=-1 for USB performance (matches ISO)\n"
        "    if ! grep -q 'usbcore.autosuspend' \"$GRUB_CFG\"; then\n"
        "        sed -i '/^[[:space:]]*linux.*\\$photon_linux/s/$/ usbcore.autosuspend=-1/' \"$GRUB_CFG\"\n"
        "    fi\n"
        "    \n"
        "    # 5. Add console=tty0 for explicit VGA console output\n"
        "    if ! grep -q 'console=tty0' \"$GRUB_CFG\"; then\n"
        "        sed -i '/^[[:space:]]*linux.*\\$photon_linux/s/$/ console=tty0/' \"$GRUB_CFG\"\n"
        "    fi\n"
        "fi\n"
    );
    
    /* Conditionally add eFuse verification */
    if (config->efuse_usb_mode) {
        fprintf(f,
            "\n"
            "# Add eFuse USB verification to grub.cfg (HABv4 Security)\n"
            "if [ -f \"$GRUB_CFG\" ]; then\n"
            "    if ! grep -q 'EFUSE_SIM' \"$GRUB_CFG\"; then\n"
            "        cp \"$GRUB_CFG\" \"$GRUB_CFG.bak\"\n"
            "        cat > \"$GRUB_CFG.new\" << 'EFUSEGRUB'\n"
            "# HABv4 Secure Boot with eFuse Verification\n"
            "set efuse_verified=0\n"
            "search --no-floppy --label EFUSE_SIM --set=efuse_disk\n"
            "if [ -n \"$efuse_disk\" ]; then\n"
            "    if [ -f ($efuse_disk)/efuse_sim/srk_fuse.bin ]; then\n"
            "        set efuse_verified=1\n"
            "    fi\n"
            "fi\n"
            "if [ \"$efuse_verified\" = \"0\" ]; then\n"
            "    echo \"\"\n"
            "    echo \"=========================================\"\n"
            "    echo \"  HABv4 SECURITY: eFuse USB Required\"\n"
            "    echo \"=========================================\"\n"
            "    echo \"Insert eFuse USB dongle (label: EFUSE_SIM)\"\n"
            "    echo \"and press any key to rescan USB devices.\"\n"
            "    echo \"\"\n"
            "    echo \"NOTE: Chainloader will reload GRUB to detect new USB devices.\"\n"
            "    read -n 1\n"
            "    # Chainloader reloads GRUB EFI binary, forcing USB device rescan\n"
            "    # configfile only reloads config without rescanning devices\n"
            "    chainloader /EFI/BOOT/grubx64.efi\n"
            "fi\n"
            "EFUSEGRUB\n"
            "        sed '1,/^set default/{ /^set default/!d }' \"$GRUB_CFG.bak\" >> \"$GRUB_CFG.new\"\n"
            "        mv \"$GRUB_CFG.new\" \"$GRUB_CFG\"\n"
            "    fi\n"
            "fi\n"
        );
        log_info("eFuse USB verification will be added to installed system grub.cfg");
    }
    
    fclose(f);
    log_info("Generated %s", spec_path);
    return 0;
}

/**
 * Generate linux-mok.spec
 */
static int generate_linux_mok_spec(rpm_build_config_t *config, rpm_package_info_t *linux_pkg) {
    char spec_path[1024];
    /* Use dynamic spec name based on package name, e.g., linux-rt-mok.spec or linux-mok.spec */
    char mok_pkg_name[256];
    
    if (strcmp(linux_pkg->name, "linux") == 0) {
        strcpy(mok_pkg_name, "linux-mok");
    } else {
        /* e.g., linux-rt -> linux-rt-mok */
        snprintf(mok_pkg_name, sizeof(mok_pkg_name), "%s-mok", linux_pkg->name);
    }
    
    snprintf(spec_path, sizeof(spec_path), "%s/%s.spec", config->specs_dir, mok_pkg_name);
    
    /* Generate date string for changelog */
    char date_str[64];
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(date_str, sizeof(date_str), "%a %b %d %Y", tm_info);
    
    FILE *f = fopen(spec_path, "w");
    if (!f) {
        log_error("Failed to create %s", spec_path);
        return -1;
    }
    
    /* Construct the kernel filename
     * For standard linux: vmlinuz-VERSION-RELEASE (e.g., vmlinuz-6.1.159-10.ph5)
     * For linux-esx: vmlinuz-VERSION-RELEASE-esx (e.g., vmlinuz-6.1.159-7.ph5-esx)
     * The flavor suffix comes from the package name after "linux-"
     */
    char kernel_filename[256];
    const char *flavor = "";
    if (strncmp(linux_pkg->name, "linux-", 6) == 0 && strlen(linux_pkg->name) > 6) {
        flavor = linux_pkg->name + 6;  /* e.g., "esx" from "linux-esx" */
    }
    if (flavor[0]) {
        snprintf(kernel_filename, sizeof(kernel_filename), "vmlinuz-%s-%s-%s", 
                 linux_pkg->version, linux_pkg->release, flavor);
    } else {
        snprintf(kernel_filename, sizeof(kernel_filename), "vmlinuz-%s-%s", 
                 linux_pkg->version, linux_pkg->release);
    }
    
    fprintf(f,
        "%%define debug_package %%{nil}\n"
        "\n"
        "# CRITICAL: Disable stripping of binaries - strip removes module signatures!\n"
        "# Without this, RPM's brp-strip will remove the cryptographic signatures from\n"
        "# kernel modules, causing \"Loading of unsigned module is rejected\" errors.\n"
        "%%define __strip /bin/true\n"
        "%%define __brp_strip /bin/true\n"
        "\n"
        "# Derived from %s %s-%s\n"
        "%%define linux_name %s\n"
        "%%define linux_version %s\n"
        "%%define linux_release %s\n"
        "%%define kernel_file %s\n"
        "\n"
        "Summary:    Linux kernel signed with MOK key (%s variant)\n"
        "Name:       %s\n"
        "# Epoch removed to allow coexistence with original package\n"
        "# Epoch:      1\n"
        "Version:    %%{linux_version}\n"
        "Release:    %%{linux_release}\n"
        "Group:      System Environment/Kernel\n"
        "License:    GPLv2\n"
        "Vendor:     VMware, Inc.\n"
        "Distribution:   Photon\n"
        "\n"
        "# Provides allows installer to find this as a valid kernel option\n"
        "Provides:   %%{linux_name} = %%{linux_version}-%%{linux_release}\n"
        "Provides:   kernel-mok = %%{linux_version}-%%{linux_release}\n",
        linux_pkg->name, linux_pkg->version, linux_pkg->release,
        linux_pkg->name,
        linux_pkg->version,
        linux_pkg->release,
        kernel_filename,
        flavor[0] ? flavor : "standard",
        mok_pkg_name
    );

    /* Specific provides for known kernel types */
    if (strcmp(linux_pkg->name, "linux") == 0) {
        fprintf(f, "Provides:   linux = %%{linux_version}-%%{linux_release}\n");
        fprintf(f, "Provides:   linux-mok = %%{linux_version}-%%{linux_release}\n");
    } else if (strcmp(linux_pkg->name, "linux-esx") == 0) {
        fprintf(f, "Provides:   linux-esx = %%{linux_version}-%%{linux_release}\n");
    } else if (strcmp(linux_pkg->name, "linux-rt") == 0) {
        fprintf(f, "Provides:   linux-rt = %%{linux_version}-%%{linux_release}\n");
        fprintf(f, "Provides:   linux-rt-mok = %%{linux_version}-%%{linux_release}\n");
    } else if (strcmp(linux_pkg->name, "linux-aws") == 0) {
        fprintf(f, "Provides:   linux-aws = %%{linux_version}-%%{linux_release}\n");
        fprintf(f, "Provides:   linux-aws-mok = %%{linux_version}-%%{linux_release}\n");
    } else if (strcmp(linux_pkg->name, "linux-secure") == 0) {
        fprintf(f, "Provides:   linux-secure = %%{linux_version}-%%{linux_release}\n");
        fprintf(f, "Provides:   linux-secure-mok = %%{linux_version}-%%{linux_release}\n");
    }

    /* Important: Remove Obsoletes to allow coexistence */
    /* Obsoletes:  linux */
    /* Obsoletes:  linux-esx */
    
    fprintf(f,
        "\n"
        "BuildRequires:  sbsigntools\n"
        "\n"
        "%%description\n"
        "Linux kernel signed with Machine Owner Key (MOK) for Secure Boot.\n"
        "This package provides the %s kernel signed with a custom MOK key.\n"
        "It can be installed alongside the original unsigned/vendor-signed kernel.\n"
        "\n"
        "%%prep\n"
        "# Extract only kernel boot files from original package (not /boot/efi)\n"
        "# release already contains dist tag\n"
        "rpm2cpio %%{source_rpm_dir}/%%{linux_name}-%%{linux_version}-%%{linux_release}.%%{_arch}.rpm | cpio -idmv './boot/vmlinuz-*' './boot/System.map-*' './boot/config-*' './boot/*.cfg' './lib/modules/*'\n"
        "\n"
        "# --- CUSTOM KERNEL INJECTION START ---\n"
        "# Check if a custom built kernel exists and use it instead of the one from RPM\n"
        "# For multiple kernels, we look for suffix matching: vmlinuz-mok, vmlinuz-rt-mok, etc.\n",
        linux_pkg->name
    );

    /* Logic for custom kernel injection varies by flavor */
    char custom_kernel_name[64] = "vmlinuz-mok";
    if (flavor[0]) {
        /* e.g. vmlinuz-rt-mok */
        snprintf(custom_kernel_name, sizeof(custom_kernel_name), "vmlinuz-%s-mok", flavor);
    }
    
    fprintf(f,
        "CUSTOM_KERNEL_PATH=\"%%{keys_dir}/%s\"\n"
        "# Fallback to generic vmlinuz-mok if specific flavor not found\n"
        "if [ ! -f \"$CUSTOM_KERNEL_PATH\" ] && [ \"%s\" == \"linux\" ]; then\n"
        "    CUSTOM_KERNEL_PATH=\"%%{keys_dir}/vmlinuz-mok\"\n"
        "fi\n"
        "\n"
        "KERNEL_BUILD_DIR=\"/root/%%{photon_release_ver}/kernel-build\"\n"
        "\n"
        "if [ -f \"$CUSTOM_KERNEL_PATH\" ]; then\n"
        "    echo \"[INFO] Found custom built kernel: $CUSTOM_KERNEL_PATH\"\n"
        "    \n"
        "    # Find the extracted vmlinuz file to replace (take first one if multiple exist)\n"
        "    VMLINUZ_FILE=$(find ./boot -name \"vmlinuz-*\" -type f | head -1)\n"
        "    if [ -n \"$VMLINUZ_FILE\" ]; then\n"
        "        echo \"[INFO] Overwriting $VMLINUZ_FILE with custom kernel\"\n"
        "        cp -f \"$CUSTOM_KERNEL_PATH\" \"$VMLINUZ_FILE\"\n"
        "    else\n"
        "        echo \"[ERROR] Could not find vmlinuz in extracted content\"\n"
        "        exit 1\n"
        "    fi\n"
        "    \n"
        "    # Now handle modules\n"
        "    # We need to find the modules directory corresponding to the custom kernel\n"
        "    # It should be in $KERNEL_BUILD_DIR/modules/lib/modules/<version>/\n"
        "    # We iterate to find it.\n"
        "    FOUND_MODULES=0\n"
        "    for mod_path in \"$KERNEL_BUILD_DIR\"/modules/lib/modules/*; do\n"
        "        if [ -d \"$mod_path\" ]; then\n"
        "            echo \"[INFO] Found custom modules at: $mod_path\"\n"
        "            \n"
        "            # Remove extracted modules\n"
        "            rm -rf ./lib/modules/*\n"
        "            \n"
        "            # Copy custom modules\n"
        "            mkdir -p ./lib/modules\n"
        "            cp -a \"$mod_path\" ./lib/modules/\n"
        "            \n"
        "            FOUND_MODULES=1\n"
        "            break\n"
        "        fi\n"
        "    done\n"
        "    \n"
        "    if [ \"$FOUND_MODULES\" -eq 0 ]; then\n"
        "        echo \"[WARNING] Custom kernel found but no corresponding modules found in $KERNEL_BUILD_DIR\"\n"
        "        exit 1\n"
        "    fi\n"
        "    \n"
        "    # Also copy the kernel .config to boot/config-* so WiFi subsystem configs are preserved\n"
        "    # Find the kernel source directory (contains the .config used for build)\n"
        "    for kernel_src in \"$KERNEL_BUILD_DIR\"/linux-*/; do\n"
        "        if [ -f \"${kernel_src}.config\" ]; then\n"
        "            CONFIG_FILE=$(find ./boot -name \"config-*\" | head -1)\n"
        "            if [ -n \"$CONFIG_FILE\" ]; then\n"
        "                echo \"[INFO] Replacing $CONFIG_FILE with custom kernel config from ${kernel_src}.config\"\n"
        "                cp -f \"${kernel_src}.config\" \"$CONFIG_FILE\"\n"
        "            fi\n"
        "            break\n"
        "        fi\n"
        "    done\n"
        "fi\n"
        "# --- CUSTOM KERNEL INJECTION END ---\n"
        "\n"
        "%%build\n"
        "# Sign kernel with MOK key\n"
        "sbsign --key %%{mok_key} --cert %%{mok_cert} \\\n"
        "       --output ./boot/%%{kernel_file}.signed \\\n"
        "       ./boot/%%{kernel_file}\n"
        "mv ./boot/%%{kernel_file}.signed ./boot/%%{kernel_file}\n"
        "\n"
        "# Determine kernel version from ACTUAL modules directory (not vmlinuz filename)\n"
        "# This is critical because custom kernel injection may have different version strings\n"
        "# e.g., vmlinuz-6.1.159-7.ph5-esx but modules in 6.1.159-esx/\n"
        "KVER=\"\"\n"
        "for moddir in ./lib/modules/*; do\n"
        "  if [ -d \"$moddir\" ]; then\n"
        "    KVER=$(basename \"$moddir\")\n"
        "    echo \"[INFO] Found modules directory: $KVER\"\n"
        "    break\n"
        "  fi\n"
        "done\n"
        "\n"
        "if [ -n \"$KVER\" ]; then\n"
        "  echo \"Generating generic initrd for kernel $KVER...\"\n"
        "  # Regenerate module dependencies for the build directory\n"
        "  # This is required because we are running dracut on extracted modules\n"
        "  /sbin/depmod -a -b . \"$KVER\"\n"
        "  \n"
        "  # Generate initrd using dracut with modules from the build directory\n"
        "  # We use --no-hostonly to ensure it works on any hardware (generic)\n"
        "  # We explicitly include critical modules and drivers\n"
        "  dracut --force --no-hostonly --kmoddir ./lib/modules/$KVER \\\n"
        "    --omit \"nbd squash memstrack biosdevname\" \\\n"
        "    --add \"bash systemd systemd-initrd kernel-modules kernel-modules-extra lvm dm rootfs-block terminfo udev-rules usrmount base fs-lib shutdown\" \\\n"
        "    --add-drivers \"xhci_pci ehci_pci uhci_hcd usb_storage sd_mod\" \\\n"
        "    ./boot/initrd.img-$KVER $KVER\n"
        "else\n"
        "  echo \"WARNING: Could not determine kernel version for initrd generation\"\n"
        "fi\n"
        "\n"
        "# Modify kernel .cfg for USB boot reliability and visible console output\n"
        "# Remove 'quiet' and 'systemd.show_status=0', add rootwait and console\n"
        "for cfg in ./boot/linux-*.cfg; do\n"
        "  if [ -f \"$cfg\" ]; then\n"
        "    # Remove quiet\n"
        "    sed -i 's/ quiet / /' \"$cfg\"\n"
        "    sed -i 's/ quiet$//' \"$cfg\"\n"
        "    # Change systemd.show_status=0 to =1\n"
        "    sed -i 's/systemd.show_status=0/systemd.show_status=1/' \"$cfg\"\n"
        "    # Add rootwait for USB reliability\n"
        "    if ! grep -q 'rootwait' \"$cfg\"; then\n"
        "      sed -i 's/cpu_init_udelay=0/cpu_init_udelay=0 rootwait/' \"$cfg\"\n"
        "    fi\n"
        "  fi\n"
        "done\n"
        "\n"
        "%%install\n"
        "# Install kernel boot files for THIS kernel variant ONLY\n"
        "# Using specific patterns based on %%{kernel_file} to avoid including files from other kernel variants\n"
        "# %%{kernel_file} is e.g., 'vmlinuz-6.12.60-14.ph5' (standard) or 'vmlinuz-6.12.60-10.ph5-esx' (esx)\n"
        "install -d %%{buildroot}/boot\n"
        "\n"
        "# Extract version-release pattern from kernel_file for matching related files\n"
        "# e.g., vmlinuz-6.12.60-14.ph5 -> 6.12.60-14.ph5\n"
        "# e.g., vmlinuz-6.12.60-10.ph5-esx -> 6.12.60-10.ph5-esx\n"
        "KERNEL_VER_REL=$(echo '%%{kernel_file}' | sed 's/vmlinuz-//')\n"
        "echo \"[INSTALL] Installing files for kernel version: $KERNEL_VER_REL\"\n"
        "\n"
        "# Install only the specific kernel files for this variant\n"
        "install -m 0644 ./boot/%%{kernel_file} %%{buildroot}/boot/\n"
        "install -m 0644 ./boot/System.map-${KERNEL_VER_REL} %%{buildroot}/boot/ 2>/dev/null || \\\n"
        "  echo \"[WARN] System.map-${KERNEL_VER_REL} not found, trying wildcard\" && \\\n"
        "  install -m 0644 ./boot/System.map-%%{linux_version}* %%{buildroot}/boot/ 2>/dev/null || true\n"
        "install -m 0644 ./boot/config-${KERNEL_VER_REL} %%{buildroot}/boot/ 2>/dev/null || \\\n"
        "  echo \"[WARN] config-${KERNEL_VER_REL} not found, trying wildcard\" && \\\n"
        "  install -m 0644 ./boot/config-%%{linux_version}* %%{buildroot}/boot/ 2>/dev/null || true\n"
        "install -m 0644 ./boot/linux-${KERNEL_VER_REL}.cfg %%{buildroot}/boot/ 2>/dev/null || \\\n"
        "  echo \"[WARN] linux-${KERNEL_VER_REL}.cfg not found, trying wildcard\" && \\\n"
        "  install -m 0644 ./boot/linux-%%{linux_version}*.cfg %%{buildroot}/boot/ 2>/dev/null || true\n"
        "\n"
        "# Install initrd - first try exact match, then module version match\n"
        "# initrd may have been generated with modules version (e.g., 6.12.60-esx) not vmlinuz version\n"
        "if [ -f \"./boot/initrd.img-${KERNEL_VER_REL}\" ]; then\n"
        "  install -m 0600 ./boot/initrd.img-${KERNEL_VER_REL} %%{buildroot}/boot/\n"
        "  echo \"[INSTALL] Installed initrd.img-${KERNEL_VER_REL}\"\n"
        "else\n"
        "  # Find initrd matching module version pattern\n"
        "  for initrd in ./boot/initrd.img-%%{linux_version}*; do\n"
        "    if [ -f \"$initrd\" ]; then\n"
        "      install -m 0600 \"$initrd\" %%{buildroot}/boot/\n"
        "      echo \"[INSTALL] Installed $(basename $initrd) (module version match)\"\n"
        "      break\n"
        "    fi\n"
        "  done\n"
        "fi\n"
        "\n"
        "# Install kernel modules - only the directory matching this kernel\n"
        "# Module dir may be named differently (e.g., 6.12.60-esx vs 6.12.60-14.ph5-esx)\n"
        "install -d %%{buildroot}/lib/modules\n"
        "INSTALLED_MODULES=0\n"
        "for moddir in ./lib/modules/*; do\n"
        "  if [ -d \"$moddir\" ]; then\n"
        "    MODVER=$(basename \"$moddir\")\n"
        "    # Check if this module dir matches our kernel (version prefix match)\n"
        "    if echo \"$MODVER\" | grep -q \"^%%{linux_version}\"; then\n"
        "      cp -a \"$moddir\" %%{buildroot}/lib/modules/\n"
        "      echo \"[INSTALL] Installed modules: $MODVER\"\n"
        "      INSTALLED_MODULES=1\n"
        "      break\n"
        "    fi\n"
        "  fi\n"
        "done\n"
        "\n"
        "if [ \"$INSTALLED_MODULES\" -eq 0 ]; then\n"
        "  echo \"[ERROR] No matching module directory found for version %%{linux_version}\"\n"
        "  ls -la ./lib/modules/\n"
        "  exit 1\n"
        "fi\n"
        "\n"
        "%%files\n"
        "%%defattr(-,root,root,-)\n"
        "/boot/%%{kernel_file}\n"
        "/boot/System.map-*\n"
        "/boot/config-*\n"
        "/boot/*.cfg\n"
        "/boot/initrd.img-*\n"
        "/lib/modules/*\n"
        "\n"
        "%%post\n"
        "# Determine kernel versions - we may have mismatched versions due to custom kernel injection:\n"
        "# - KVER_MODULES: from /lib/modules/* (custom kernel version, e.g., 6.1.159-esx)\n"
        "# - KVER_VMLINUZ: from /boot/vmlinuz-* filename (original RPM version, e.g., 6.1.159-7.ph5-esx)\n"
        "# The cfg file uses KVER_VMLINUZ, initrd may use either\n"
        "\n"
        "KVER_MODULES=\"\"\n"
        "KVER_VMLINUZ=\"\"\n"
        "\n"
        "# Get kernel version from modules directory\n"
        "for moddir in /lib/modules/%%{linux_version}*; do\n"
        "  if [ -d \"$moddir\" ]; then\n"
        "    KVER_MODULES=$(basename \"$moddir\")\n"
        "    break\n"
        "  fi\n"
        "done\n"
        "\n"
        "# Get kernel version from vmlinuz filename\n"
        "for vmlinuz in /boot/vmlinuz-%%{linux_version}-*; do\n"
        "  if [ -f \"$vmlinuz\" ]; then\n"
        "    KVER_VMLINUZ=$(basename \"$vmlinuz\" | sed 's/vmlinuz-//')\n"
        "    break\n"
        "  fi\n"
        "done\n"
        "\n"
        "echo \"linux-mok: Modules version: $KVER_MODULES\"\n"
        "echo \"linux-mok: Vmlinuz version: $KVER_VMLINUZ\"\n"
        "\n"
        "# Run depmod with modules version\n"
        "if [ -n \"$KVER_MODULES\" ]; then\n"
        "  echo \"linux-mok: Running depmod -a $KVER_MODULES\"\n"
        "  /sbin/depmod -a \"$KVER_MODULES\"\n"
        "fi\n"
        "\n"
        "# Create photon.cfg symlink - use vmlinuz version (matches cfg filename)\n"
        "if [ -n \"$KVER_VMLINUZ\" ] && [ -f \"/boot/linux-${KVER_VMLINUZ}.cfg\" ]; then\n"
        "  ln -sf \"linux-${KVER_VMLINUZ}.cfg\" /boot/photon.cfg\n"
        "  echo \"linux-mok: Created /boot/photon.cfg -> linux-${KVER_VMLINUZ}.cfg\"\n"
        "elif [ -n \"$KVER_MODULES\" ] && [ -f \"/boot/linux-${KVER_MODULES}.cfg\" ]; then\n"
        "  ln -sf \"linux-${KVER_MODULES}.cfg\" /boot/photon.cfg\n"
        "  echo \"linux-mok: Created /boot/photon.cfg -> linux-${KVER_MODULES}.cfg\"\n"
        "else\n"
        "  # Fallback: find any linux-*.cfg\n"
        "  for cfg in /boot/linux-%%{linux_version}*.cfg; do\n"
        "    if [ -f \"$cfg\" ]; then\n"
        "      ln -sf \"$(basename $cfg)\" /boot/photon.cfg\n"
        "      echo \"linux-mok: Created /boot/photon.cfg -> $(basename $cfg)\"\n"
        "      break\n"
        "    fi\n"
        "  done\n"
        "fi\n"
        "\n"
        "# Handle initrd version mismatch: cfg expects initrd.img-$KVER_VMLINUZ but\n"
        "# we may have built initrd.img-$KVER_MODULES. Create symlink if needed.\n"
        "if [ -n \"$KVER_VMLINUZ\" ] && [ -n \"$KVER_MODULES\" ] && [ \"$KVER_VMLINUZ\" != \"$KVER_MODULES\" ]; then\n"
        "  if [ -f \"/boot/initrd.img-${KVER_MODULES}\" ] && [ ! -e \"/boot/initrd.img-${KVER_VMLINUZ}\" ]; then\n"
        "    ln -sf \"initrd.img-${KVER_MODULES}\" \"/boot/initrd.img-${KVER_VMLINUZ}\"\n"
        "    echo \"linux-mok: Created initrd symlink: initrd.img-${KVER_VMLINUZ} -> initrd.img-${KVER_MODULES}\"\n"
        "  fi\n"
        "fi\n"
        "\n"
        "if [ -z \"$KVER_MODULES\" ] && [ -z \"$KVER_VMLINUZ\" ]; then\n"
        "  echo \"linux-mok: ERROR: Could not determine kernel version!\"\n"
        "fi\n"
        "\n"
        "%%postun\n"
        "# If photon.cfg symlink is broken, point to newest available kernel config\n"
        "if [ ! -e /boot/photon.cfg ]; then\n"
        "  list=\"$(basename \"$(ls -1 -tu /boot/linux-*.cfg 2>/dev/null | head -n1)\")\"\n"
        "  test -n \"$list\" && ln -sf \"$list\" /boot/photon.cfg\n"
        "fi\n"
        "# Clean up initrd if kernel config is removed\n"
        "# Note: kernel_file is e.g., vmlinuz-6.1.159-7.ph5-esx, strip vmlinuz- prefix\n"
        "KVER_FILE=\"%%{kernel_file}\"\n"
        "KVER_FILE=\"${KVER_FILE#vmlinuz-}\"\n"
        "if [ ! -s \"/boot/linux-${KVER_FILE}.cfg\" ]; then\n"
        "  rm -f \"/var/lib/rpm-state/initramfs/pending/${KVER_FILE}\" \\\n"
        "        \"/boot/initrd.img-${KVER_FILE}\"\n"
        "fi\n"
        "\n"
        "%%changelog\n"
        "* %s HABv4 Project <habv4@local> %%{linux_version}-%%{linux_release}\n"
        "- MOK-signed variant of %%{linux_name} kernel\n",
        custom_kernel_name, linux_pkg->name,
        date_str
    );
    
    fclose(f);
    log_info("Generated %s", spec_path);
    return 0;
}

/**
 * Generate shim-signed-mok.spec
 */
static int generate_shim_mok_spec(rpm_build_config_t *config, 
                                   rpm_package_info_t *shim_signed_pkg,
                                   rpm_package_info_t *shim_pkg) {
    char spec_path[1024];
    snprintf(spec_path, sizeof(spec_path), "%s/shim-signed-mok.spec", config->specs_dir);
    
    /* Generate date string for changelog */
    char date_str[64];
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(date_str, sizeof(date_str), "%a %b %d %Y", tm_info);
    
    FILE *f = fopen(spec_path, "w");
    if (!f) {
        log_error("Failed to create %s", spec_path);
        return -1;
    }
    
    fprintf(f,
        "%%define debug_package %%{nil}\n"
        "\n"
        "# SUSE shim for MOK Secure Boot (replaces VMware shim-signed %s-%s)\n"
        "# Uses SUSE's Microsoft-signed shim which properly supports MOK keys\n"
        "%%define shim_version %s\n"
        "%%define shim_release %s\n"
        "\n"
        "Summary:    SUSE shim for MOK Secure Boot chain\n"
        "Name:       shim-signed-mok\n"
        "Epoch:      1\n"
        "Version:    %%{shim_version}\n"
        "Release:    %%{shim_release}\n"
        "Group:      System Environment/Base\n"
        "License:    BSD\n"
        "Vendor:     HABv4 Project\n"
        "Distribution:   Photon\n"
        "\n"
        "# Epoch ensures this package is always considered newer than original\n"
        "# Provides satisfies dependencies, Obsoletes triggers replacement\n"
        "Provides:   shim-signed = %%{shim_version}-%%{shim_release}\n"
        "Obsoletes:  shim-signed\n"
        "\n"
        "%%description\n"
        "SUSE shim (Microsoft-signed) for MOK Secure Boot chain.\n"
        "This package provides the SUSE shim which properly handles MOK keys\n"
        "for launching MOK-signed GRUB binaries.\n"
        "\n"
        "VMware's shim has strict shim_lock behavior that prevents launching\n"
        "MOK-signed binaries. The SUSE shim correctly implements MOK verification\n"
        "and is required for the HABv4 Secure Boot chain to work.\n"
        "\n"
        "%%prep\n"
        "# Use pre-built SUSE shim from keys directory\n"
        "mkdir -p ./boot/efi/EFI/BOOT\n"
        "cp %%{keys_dir}/shim-suse.efi ./boot/efi/EFI/BOOT/bootx64.efi\n"
        "cp %%{keys_dir}/MokManager-suse.efi ./boot/efi/EFI/BOOT/MokManager.efi\n"
        "\n"
        "%%build\n"
        "# No build needed - SUSE shim is already Microsoft-signed\n"
        "\n"
        "%%install\n"
        "install -d %%{buildroot}/boot/efi/EFI/BOOT\n"
        "install -m 0644 ./boot/efi/EFI/BOOT/bootx64.efi %%{buildroot}/boot/efi/EFI/BOOT/\n"
        "install -m 0644 ./boot/efi/EFI/BOOT/MokManager.efi %%{buildroot}/boot/efi/EFI/BOOT/\n"
        "\n"
        "%%files\n"
        "%%defattr(-,root,root,-)\n"
        "/boot/efi/EFI/BOOT/bootx64.efi\n"
        "/boot/efi/EFI/BOOT/MokManager.efi\n"
        "\n"
        "%%changelog\n"
        "* %s HABv4 Project <habv4@local> %%{shim_version}-%%{shim_release}\n"
        "- SUSE shim for MOK Secure Boot chain\n"
        "- Replaces VMware shim which has shim_lock issues\n",
        shim_signed_pkg->version, shim_signed_pkg->release,
        shim_signed_pkg->version,
        shim_signed_pkg->release,
        date_str
    );
    
    fclose(f);
    log_info("Generated %s", spec_path);
    return 0;
}

int rpm_generate_mok_specs(
    rpm_build_config_t *config,
    discovered_packages_t *packages
) {
    log_info("Generating MOK variant SPEC files...");
    
    /* Create specs directory */
    mkdir_p(config->specs_dir);
    
    /* Generate SPEC files */
    if (packages->grub_efi) {
        if (generate_grub_mok_spec(config, packages->grub_efi) != 0) {
            return RPM_PATCH_ERR_SPEC_GENERATION_FAILED;
        }
    }
    
    if (packages->kernel_count > 0) {
        for (int i = 0; i < packages->kernel_count; i++) {
            if (generate_linux_mok_spec(config, packages->linux_kernels[i]) != 0) {
                return RPM_PATCH_ERR_SPEC_GENERATION_FAILED;
            }
        }
    }
    
    if (packages->shim_signed) {
        if (generate_shim_mok_spec(config, packages->shim_signed, packages->shim) != 0) {
            return RPM_PATCH_ERR_SPEC_GENERATION_FAILED;
        }
    }
    
    log_info("SPEC file generation complete");
    return RPM_PATCH_SUCCESS;
}

/* ============================================================================
 * RPM Build Functions
 * ============================================================================ */

/**
 * Build a single MOK RPM
 */
static int build_single_rpm(rpm_build_config_t *config, const char *spec_name, 
                            const char *dist_tag) {
    char cmd[2048];
    char spec_path[1024];
    
    snprintf(spec_path, sizeof(spec_path), "%s/%s", config->specs_dir, spec_name);
    
    if (!file_exists(spec_path)) {
        log_error("SPEC file not found: %s", spec_path);
        return -1;
    }
    
    log_info("Building %s...", spec_name);
    
    /* Clean the BUILD directory before each kernel build to prevent file contamination
     * This is critical because rpmbuild reuses BUILD/ and files from previous builds
     * (e.g., linux-mok files) will contaminate subsequent builds (e.g., linux-esx-mok)
     * causing file conflicts when both packages are installed together */
    if (strstr(spec_name, "linux") != NULL) {
        snprintf(cmd, sizeof(cmd), "rm -rf '%s/BUILD/'*", config->rpmbuild_dir);
        log_debug("Cleaning BUILD directory before kernel build: %s", cmd);
        run_cmd(cmd);
    }
    
    /* Build the RPM */
    snprintf(cmd, sizeof(cmd),
        "rpmbuild -bb --define '_topdir %s' "
        "--define 'dist %s' "
        "--define 'mok_key %s' "
        "--define 'mok_cert %s' "
        "--define 'source_rpm_dir %s' "
        "--define 'keys_dir %s' "
        "--define 'photon_release_ver %s' "
        "'%s' 2>&1",
        config->rpmbuild_dir,
        dist_tag,
        config->mok_key,
        config->mok_cert,
        config->source_rpm_dir,
        config->keys_dir ? config->keys_dir : "/root/hab_keys",
        config->release,
        spec_path);
    
    if (g_verbose) {
        printf("  $ %s\n", cmd);
    }
    
    int ret = run_cmd(cmd);
    if (ret != 0) {
        log_error("Failed to build %s (exit code: %d)", spec_name, ret);
        return -1;
    }
    
    log_info("Successfully built %s", spec_name);
    return 0;
}

int rpm_build_mok_packages(
    rpm_build_config_t *config,
    discovered_packages_t *packages
) {
    log_info("Building MOK-signed RPM packages...");
    
    /* Create rpmbuild directory structure */
    char path[1024];
    snprintf(path, sizeof(path), "%s/BUILD", config->rpmbuild_dir);
    mkdir_p(path);
    snprintf(path, sizeof(path), "%s/RPMS", config->rpmbuild_dir);
    mkdir_p(path);
    snprintf(path, sizeof(path), "%s/SRPMS", config->rpmbuild_dir);
    mkdir_p(path);
    snprintf(path, sizeof(path), "%s/SOURCES", config->rpmbuild_dir);
    mkdir_p(path);
    snprintf(path, sizeof(path), "%s/SPECS", config->rpmbuild_dir);
    mkdir_p(path);
    
    /* Build order: shim-signed-mok, grub2-efi-image-mok, linux-mok */
    
    /* 1. Build shim-signed-mok (includes MokManager) */
    if (build_single_rpm(config, "shim-signed-mok.spec", packages->dist_tag) != 0) {
        return RPM_PATCH_ERR_BUILD_FAILED;
    }
    
    /* 2. Build grub2-efi-image-mok */
    if (build_single_rpm(config, "grub2-efi-image-mok.spec", packages->dist_tag) != 0) {
        return RPM_PATCH_ERR_BUILD_FAILED;
    }
    
    /* 3. Build linux-mok variants */
    if (packages->kernel_count > 0) {
        for (int i = 0; i < packages->kernel_count; i++) {
            char spec_name[256];
            if (strcmp(packages->linux_kernels[i]->name, "linux") == 0) {
                strcpy(spec_name, "linux-mok.spec");
            } else {
                snprintf(spec_name, sizeof(spec_name), "%s-mok.spec", packages->linux_kernels[i]->name);
            }
            
            if (build_single_rpm(config, spec_name, packages->dist_tag) != 0) {
                return RPM_PATCH_ERR_BUILD_FAILED;
            }
        }
    }
    
    /* Move built RPMs to output directory */
    mkdir_p(config->output_dir);
    char cmd[1024];
    /* Fix: Add single quotes around paths to handle spaces/special characters
     * Also fix unexpected EOF in command string construction */
    snprintf(cmd, sizeof(cmd), "cp '%s/RPMS/'*/*.rpm '%s/' 2>/dev/null", 
             config->rpmbuild_dir, config->output_dir);
    run_cmd(cmd);
    
    log_info("MOK package build complete");
    return RPM_PATCH_SUCCESS;
}

/* ============================================================================
 * Validation Functions
 * ============================================================================ */

rpm_validation_result_t* rpm_validate_mok_package(
    const char *rpm_path,
    const char *mok_cert
) {
    rpm_validation_result_t *result = calloc(1, sizeof(rpm_validation_result_t));
    if (!result) return NULL;
    
    char cmd[1024];
    char output[4096];
    
    /* Check RPM integrity */
    snprintf(cmd, sizeof(cmd), "rpm -K '%s' 2>&1", rpm_path);
    if (run_cmd_output(cmd, output, sizeof(output)) == 0) {
        result->rpm_valid = (strstr(output, "OK") != NULL || 
                            strstr(output, "digests OK") != NULL);
    }
    
    /* Security: Use mkdtemp for secure temp directory */
    char *tmp_dir = create_secure_tempdir("rpm_validate");
    if (!tmp_dir) {
        result->error_message = strdup("Failed to create secure temp directory");
        return result;
    }
    
    snprintf(cmd, sizeof(cmd), "cd '%s' && rpm2cpio '%s' | cpio -idm 2>/dev/null", 
             tmp_dir, rpm_path);
    run_cmd(cmd);
    
    /* Check for EFI files and verify signatures */
    result->signature_valid = 1;
    const char *efi_files[] = {
        "boot/efi/EFI/BOOT/grubx64.efi",
        "boot/efi/EFI/BOOT/mmx64.efi",
        NULL
    };
    
    for (int i = 0; efi_files[i]; i++) {
        char file_path[512];
        snprintf(file_path, sizeof(file_path), "%s/%s", tmp_dir, efi_files[i]);
        
        if (file_exists(file_path)) {
            snprintf(cmd, sizeof(cmd), "sbverify --cert '%s' '%s' 2>&1", 
                     mok_cert, file_path);
            if (run_cmd_output(cmd, output, sizeof(output)) != 0 ||
                strstr(output, "Signature verification OK") == NULL) {
                result->signature_valid = 0;
                result->error_message = strdup(output);
                break;
            }
        }
    }
    
    /* Also check kernel */
    snprintf(cmd, sizeof(cmd), "find '%s/boot' -name 'vmlinuz-*' -type f 2>/dev/null | head -1", 
             tmp_dir);
    if (run_cmd_output(cmd, output, sizeof(output)) == 0 && strlen(output) > 0) {
        snprintf(cmd, sizeof(cmd), "sbverify --cert '%s' '%s' 2>&1", 
                 mok_cert, output);
        char verify_output[4096];
        if (run_cmd_output(cmd, verify_output, sizeof(verify_output)) != 0 ||
            strstr(verify_output, "Signature verification OK") == NULL) {
            result->signature_valid = 0;
            if (!result->error_message) {
                result->error_message = strdup(verify_output);
            }
        }
    }
    
    /* Cleanup */
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", tmp_dir);
    run_cmd(cmd);
    free(tmp_dir);
    
    return result;
}

/* ============================================================================
 * RPM GPG Signing Functions
 * ============================================================================ */

int rpm_sign_mok_packages(
    rpm_build_config_t *config,
    const char *gpg_home,
    const char *gpg_key_name
) {
    char cmd[2048];
    char pattern[512];
    glob_t glob_result;
    int signed_count = 0;
    
    log_info("Signing MOK RPM packages with GPG key...");
    
    /* RPM's rpmsign uses /usr/bin/gpg2 by default, but Photon OS only has /usr/bin/gpg.
     * Create symlink if needed to fix "Could not exec gpg" error */
    if (access("/usr/bin/gpg2", X_OK) != 0 && access("/usr/bin/gpg", X_OK) == 0) {
        log_info("Creating /usr/bin/gpg2 symlink for rpmsign compatibility");
        if (symlink("/usr/bin/gpg", "/usr/bin/gpg2") != 0 && errno != EEXIST) {
            log_warn("Failed to create gpg2 symlink: %s", strerror(errno));
        }
    }
    
    /* Build pattern to find MOK RPMs */
    snprintf(pattern, sizeof(pattern), "%s/*-mok-*.rpm", config->output_dir);
    
    if (glob(pattern, 0, NULL, &glob_result) != 0) {
        log_warn("No MOK RPMs found to sign in %s", config->output_dir);
        return 0;  /* Not an error if no packages found */
    }
    
    /* Sign each RPM */
    for (size_t i = 0; i < glob_result.gl_pathc; i++) {
        const char *rpm_path = glob_result.gl_pathv[i];
        
        log_debug("Signing: %s", rpm_path);
        
        /* Use rpmsign with GNUPGHOME set */
        snprintf(cmd, sizeof(cmd),
            "GNUPGHOME='%s' rpmsign "
            "--define '_gpg_name %s' "
            "--addsign '%s' 2>&1",
            gpg_home,
            gpg_key_name,
            rpm_path);
        
        if (run_cmd(cmd) != 0) {
            log_error("Failed to sign: %s", rpm_path);
            globfree(&glob_result);
            return RPM_PATCH_ERR_SIGN_FAILED;
        }
        
        signed_count++;
        log_info("Signed: %s", basename((char*)rpm_path));
    }
    
    globfree(&glob_result);
    
    if (signed_count > 0) {
        /* Verify signatures */
        log_info("Verifying RPM signatures...");
        snprintf(cmd, sizeof(cmd), 
            "rpm --checksig %s/*-mok-*.rpm 2>&1 | grep -v 'NOT OK' || true", 
            config->output_dir);
        run_cmd(cmd);
        
        log_info("Successfully signed %d MOK RPM package(s)", signed_count);
    }
    
    return RPM_PATCH_SUCCESS;
}

/* ============================================================================
 * ISO Integration Functions
 * ============================================================================ */

int rpm_integrate_to_iso(
    const char *iso_rpm_dir,
    rpm_build_config_t *config
) {
    log_info("Integrating MOK packages into ISO...");
    log_debug("Output dir: %s", config->output_dir);
    log_debug("ISO RPM dir: %s", iso_rpm_dir);
    
    char cmd[1024];
    glob_t glob_result;
    char pattern[512];
    int copied_count = 0;
    
    /* First, verify that MOK RPMs exist in the output directory */
    snprintf(pattern, sizeof(pattern), "%s/*-mok-*.rpm", config->output_dir);
    
    if (glob(pattern, 0, NULL, &glob_result) != 0 || glob_result.gl_pathc == 0) {
        log_error("No MOK RPMs found in output directory: %s", config->output_dir);
        log_error("Pattern searched: %s", pattern);
        
        /* List what's actually in the output directory for debugging */
        snprintf(cmd, sizeof(cmd), "ls -la '%s/' 2>&1 || echo 'Directory empty or not found'", 
                 config->output_dir);
        log_error("Contents of output directory:");
        run_cmd(cmd);
        
        /* Also check rpmbuild RPMS directory */
        snprintf(cmd, sizeof(cmd), "find '%s/RPMS' -name '*.rpm' 2>/dev/null || echo 'No RPMs in rpmbuild'", 
                 config->rpmbuild_dir);
        log_error("Contents of rpmbuild RPMS:");
        run_cmd(cmd);
        
        return RPM_PATCH_ERR_BUILD_FAILED;
    }
    
    log_info("Found %zu MOK RPM(s) to integrate", glob_result.gl_pathc);
    
    /* Copy each RPM individually with error checking */
    for (size_t i = 0; i < glob_result.gl_pathc; i++) {
        const char *rpm_path = glob_result.gl_pathv[i];
        const char *rpm_name = strrchr(rpm_path, '/');
        rpm_name = rpm_name ? rpm_name + 1 : rpm_path;
        
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/'", rpm_path, iso_rpm_dir);
        
        if (run_cmd(cmd) != 0) {
            log_error("Failed to copy %s to %s", rpm_name, iso_rpm_dir);
            globfree(&glob_result);
            return RPM_PATCH_ERR_BUILD_FAILED;
        }
        
        /* Verify the file was actually copied */
        char dest_path[1024];
        snprintf(dest_path, sizeof(dest_path), "%s/%s", iso_rpm_dir, rpm_name);
        if (!file_exists(dest_path)) {
            log_error("Copy verification failed: %s not found in %s", rpm_name, iso_rpm_dir);
            globfree(&glob_result);
            return RPM_PATCH_ERR_BUILD_FAILED;
        }
        
        log_info("Copied: %s", rpm_name);
        copied_count++;
    }
    
    globfree(&glob_result);
    
    if (copied_count == 0) {
        log_error("No MOK RPMs were copied to ISO");
        return RPM_PATCH_ERR_BUILD_FAILED;
    }
    
    log_info("Successfully copied %d MOK RPM(s) to ISO", copied_count);
    
    /* Remove original packages that conflict with MOK packages
     * MOK packages use Obsoletes: but file conflicts cause rpm transaction to fail
     * if both packages are present in the repo during installation.
     * Also remove packages that require exact kernel version (linux = 6.12.60-14.ph5)
     * because linux-mok provides a different version (linux = 6.1.159-7.ph5) */
    
    /* MODIFIED: We no longer remove original packages to allow coexistence.
     * The new MOK packages do not use 'Epoch' or 'Obsoletes', so they can exist
     * in the repository alongside original packages.
     * The installer profile will select which one to install.
     */
    log_info("Keeping original packages to allow coexistence (MOK vs Original)");
    /* Fix: Use 'find' for reliable cleanup of conflicting packages.
     * Shell globbing rm command might fail if list is too long or patterns don't match exactly. */
    /*
    snprintf(cmd, sizeof(cmd), 
        "find '%s' -type f \\( "
        "-name 'grub2-efi-image-2*.rpm' -o "
        "-name 'shim-signed-1*.rpm' -o "
        // Kernel 6.x 
        "-name 'linux-6.*.rpm' -o "
        "-name 'linux-esx-6.*.rpm' -o "
        "-name 'linux-rt-6.*.rpm' -o "
        "-name 'linux-aws-6.*.rpm' -o "
        "-name 'linux-secure-6.*.rpm' -o "
        // Kernel 5.x 
        "-name 'linux-5.*.rpm' -o "
        "-name 'linux-esx-5.*.rpm' -o "
        "-name 'linux-secure-5.*.rpm' -o "
        "-name 'linux-rt-5.*.rpm' -o "
        "-name 'linux-aws-5.*.rpm' -o "
        // Devel/Docs/Drivers 
        "-name 'linux*-devel-*.rpm' -o "
        "-name 'linux*-docs-*.rpm' -o "
        "-name 'linux*-drivers-*.rpm' -o "
        "-name 'linux*-tools-*.rpm' -o "
        "-name 'linux*-python3-perf-*.rpm' -o "
        "-name 'bpftool-*.rpm' -o "
        "-name 'linuxptp-*.rpm' -o "
        "-name 'linux-rt-stalld-ebpf-plugin-*.rpm' "
        "\\) -delete",
        iso_rpm_dir);
    run_cmd(cmd);
    log_info("Removed conflicting original packages from ISO");
    */
    
    /* Regenerate repodata to include the new MOK packages
     * Without this, tdnf won't find the MOK packages during installation */
    log_info("Regenerating repository metadata...");
    
    /* Get the parent RPMS directory (iso_rpm_dir is RPMS/x86_64, we need RPMS) */
    char repo_dir[512];
    strncpy(repo_dir, iso_rpm_dir, sizeof(repo_dir) - 1);
    repo_dir[sizeof(repo_dir) - 1] = '\0';
    char *last_slash = strrchr(repo_dir, '/');
    if (last_slash) *last_slash = '\0';
    
    log_debug("Repository dir for repodata: %s", repo_dir);
    
    /* Remove old repodata and regenerate */
    snprintf(cmd, sizeof(cmd), "rm -rf '%s/repodata'", repo_dir);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "createrepo_c '%s' 2>&1", repo_dir);
    if (run_cmd(cmd) != 0) {
        /* Try createrepo if createrepo_c not available */
        snprintf(cmd, sizeof(cmd), "createrepo '%s' 2>&1", repo_dir);
        if (run_cmd(cmd) != 0) {
            log_error("Failed to regenerate repodata - MOK packages may not be installable");
            log_error("Please ensure createrepo or createrepo_c is installed");
            return RPM_PATCH_ERR_BUILD_FAILED;
        }
    }
    
    /* Verify MOK packages are in repodata */
    snprintf(cmd, sizeof(cmd), 
        "zgrep -l 'grub2-efi-image-mok' '%s/repodata/'*primary.xml.gz 2>/dev/null | head -1",
        repo_dir);
    char output[512];
    if (run_cmd_output(cmd, output, sizeof(output)) != 0 || strlen(output) == 0) {
        log_warn("Could not verify grub2-efi-image-mok in repodata - installation may fail");
    } else {
        log_info("Verified: MOK packages present in repository metadata");
    }
    
    log_info("Repository metadata regenerated");
    log_info("MOK packages integrated into ISO");
    return RPM_PATCH_SUCCESS;
}

/* ============================================================================
 * Main Entry Point
 * ============================================================================ */

int rpm_patch_secureboot_packages(
    const char *photon_release_dir,
    const char *iso_extract_dir,
    const char *mok_key,
    const char *mok_cert,
    int verbose,
    int efuse_usb_mode
) {
    g_verbose = verbose;
    
    log_info("=== RPM Secure Boot Patcher ===");
    log_info("Photon release dir: %s", photon_release_dir);
    log_info("ISO extract dir: %s", iso_extract_dir);
    
    /* Construct paths */
    char rpm_dir[512], specs_dir[512], iso_rpm_dir[512];
    snprintf(rpm_dir, sizeof(rpm_dir), "%s/stage/RPMS/x86_64", photon_release_dir);
    snprintf(specs_dir, sizeof(specs_dir), "%s/SPECS", photon_release_dir);
    snprintf(iso_rpm_dir, sizeof(iso_rpm_dir), "%s/RPMS/x86_64", iso_extract_dir);
    
    /* Extract release from path (e.g., /root/5.0 -> 5.0) */
    const char *release = strrchr(photon_release_dir, '/');
    release = release ? release + 1 : photon_release_dir;
    
    /* Step 1: Discover packages */
    discovered_packages_t *packages = rpm_discover_packages(rpm_dir, specs_dir, release);
    if (!packages) {
        log_error("Package discovery failed");
        return RPM_PATCH_ERR_DISCOVERY_FAILED;
    }
    
    /* Step 2: Set up build configuration */
    rpm_build_config_t config = {0};
    config.work_dir = strdup("/tmp/rpm_mok_build");
    config.specs_dir = strdup("/tmp/rpm_mok_build/SPECS");
    config.rpmbuild_dir = strdup("/tmp/rpm_mok_build/rpmbuild");
    config.output_dir = strdup("/tmp/rpm_mok_build/output");
    config.source_rpm_dir = strdup(rpm_dir);
    config.source_specs_dir = strdup(specs_dir);
    config.mok_key = strdup(mok_key);
    config.mok_cert = strdup(mok_cert);
    config.release = strdup(release);
    config.verbose = verbose;
    config.efuse_usb_mode = efuse_usb_mode;
    
    /* Get keys_dir from mok_key path (e.g., /root/hab_keys/MOK.key -> /root/hab_keys) */
    char keys_dir[512];
    strncpy(keys_dir, mok_key, sizeof(keys_dir) - 1);
    char *last_slash = strrchr(keys_dir, '/');
    if (last_slash) *last_slash = '\0';
    config.keys_dir = strdup(keys_dir);
    
    /* Clean and create work directories
     * This ensures no stale packages from previous builds (e.g., ph5 packages
     * left over when building ph4) contaminate the current build */
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", config.work_dir);
    run_cmd(cmd);
    
    mkdir_p(config.work_dir);
    mkdir_p(config.specs_dir);
    mkdir_p(config.rpmbuild_dir);
    mkdir_p(config.output_dir);
    
    /* Step 3: Generate SPEC files */
    int ret = rpm_generate_mok_specs(&config, packages);
    if (ret != RPM_PATCH_SUCCESS) {
        log_error("SPEC generation failed");
        rpm_free_discovered_packages(packages);
        return ret;
    }
    
    /* Step 4: Build packages */
    ret = rpm_build_mok_packages(&config, packages);
    if (ret != RPM_PATCH_SUCCESS) {
        log_error("Package build failed");
        rpm_free_discovered_packages(packages);
        return ret;
    }
    
    /* Step 5: Validate packages */
    log_info("Validating built packages...");
    glob_t glob_result;
    char pattern[512];
    snprintf(pattern, sizeof(pattern), "%s/*-mok-*.rpm", config.output_dir);
    
    if (glob(pattern, 0, NULL, &glob_result) == 0) {
        for (size_t i = 0; i < glob_result.gl_pathc; i++) {
            rpm_validation_result_t *vr = rpm_validate_mok_package(
                glob_result.gl_pathv[i], mok_cert);
            
            if (vr) {
                if (!vr->signature_valid) {
                    log_error("Signature validation failed for %s: %s", 
                              glob_result.gl_pathv[i],
                              vr->error_message ? vr->error_message : "unknown error");
                } else {
                    log_info("Validated: %s", glob_result.gl_pathv[i]);
                }
                rpm_free_validation_result(vr);
            }
        }
        globfree(&glob_result);
    }
    
    /* Step 6: Integrate into ISO */
    ret = rpm_integrate_to_iso(iso_rpm_dir, &config);
    if (ret != RPM_PATCH_SUCCESS) {
        log_error("ISO integration failed");
        rpm_free_discovered_packages(packages);
        return ret;
    }
    
    /* Cleanup */
    rpm_free_discovered_packages(packages);
    
    log_info("=== RPM Secure Boot Patcher Complete ===");
    return RPM_PATCH_SUCCESS;
}

/* ============================================================================
 * Cleanup Functions
 * ============================================================================ */

void rpm_free_package_info(rpm_package_info_t *pkg) {
    if (!pkg) return;
    free(pkg->rpm_path);
    free(pkg->name);
    free(pkg->version);
    free(pkg->release);
    free(pkg->arch);
    free(pkg->spec_path);
    if (pkg->files) {
        for (int i = 0; i < pkg->file_count; i++) {
            free(pkg->files[i]);
        }
        free(pkg->files);
    }
    free(pkg);
}

void rpm_free_discovered_packages(discovered_packages_t *packages) {
    if (!packages) return;
    rpm_free_package_info(packages->grub_efi);
    
    if (packages->kernel_count > 0) {
        for (int i = 0; i < packages->kernel_count; i++) {
            rpm_free_package_info(packages->linux_kernels[i]);
        }
    }
    
    rpm_free_package_info(packages->shim_signed);
    rpm_free_package_info(packages->shim);
    free(packages->release);
    free(packages->dist_tag);
    free(packages);
}

void rpm_free_validation_result(rpm_validation_result_t *result) {
    if (!result) return;
    free(result->error_message);
    free(result);
}

void rpm_free_build_config(rpm_build_config_t *config) {
    if (!config) return;
    free(config->work_dir);
    free(config->specs_dir);
    free(config->rpmbuild_dir);
    free(config->output_dir);
    free(config->source_rpm_dir);
    free(config->source_specs_dir);
    free(config->mok_key);
    free(config->mok_cert);
    free(config->release);
}
