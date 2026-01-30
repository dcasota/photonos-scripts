/*
 * habv4_common.h
 *
 * Common definitions, types, and function declarations for
 * PhotonOS-HABv4Emulation-ISOCreator
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#ifndef HABV4_COMMON_H
#define HABV4_COMMON_H

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

/* ============================================================================
 * Version and Program Info
 * ============================================================================ */
#define VERSION "1.9.14"
#define PROGRAM_NAME "PhotonOS-HABv4Emulation-ISOCreator"

/* ============================================================================
 * Default Configuration
 * ============================================================================ */
#define DEFAULT_RELEASE "5.0"
#define DEFAULT_MOK_DAYS 180
#define DEFAULT_MOK_KEY_BITS 2048
#define DEFAULT_CERT_WARN_DAYS 30
#define DEFAULT_KEYS_DIR "/root/hab_keys"
#define DEFAULT_EFUSE_DIR "/root/efuse_sim"
#define DEFAULT_EFIBOOT_SIZE_MB 16
#define DEFAULT_DRIVERS_DIR "drivers/RPM"

/* ============================================================================
 * Valid Key Sizes (whitelist)
 * ============================================================================ */
extern const int VALID_KEY_SIZES[];

/* ============================================================================
 * Ventoy Configuration
 * ============================================================================ */
#define VENTOY_VERSION "1.1.10"
#define VENTOY_URL "https://github.com/ventoy/Ventoy/releases/download/v" VENTOY_VERSION "/ventoy-" VENTOY_VERSION "-linux.tar.gz"

/* SHA3-256 checksums for download integrity verification */
#define VENTOY_SHA3_256 "9ef8f77e05e5a0f8231e196cef5759ce1a0ffd31abeac4c1a92f76b9c9a8d620"
#define SUSE_SHIM_SHA3_256 "7856a4588396b9bc1392af09885beef8833fa86381cf1a2a0f0ac5e6e7411ba5"
#define SUSE_MOKMANAGER_SHA3_256 "00a3b4653c4098c8d6557b8a2b61c0f7d05b20ee619ec786940d0b28970ee104"

/* ============================================================================
 * ANSI Colors for Terminal Output
 * ============================================================================ */
#define RED     "\x1b[31m"
#define GREEN   "\x1b[32m"
#define YELLOW  "\x1b[33m"
#define BLUE    "\x1b[34m"
#define CYAN    "\x1b[36m"
#define RESET   "\x1b[0m"

/* ============================================================================
 * GPG Key Configuration for RPM Signing
 * ============================================================================ */
#define GPG_KEY_NAME "HABv4 RPM Signing Key"
#define GPG_KEY_EMAIL "habv4-rpm@local"
#define GPG_KEY_FILE "RPM-GPG-KEY-habv4"

/* ============================================================================
 * Configuration Structure
 * ============================================================================ */
typedef struct {
    char release[16];
    char keys_dir[512];
    char efuse_dir[512];
    char photon_dir[512];
    char input_iso[512];
    char output_iso[512];
    char efuse_usb_device[128];
    char diagnose_iso_path[512];
    char drivers_dir[512];
    int mok_days;
    int mok_key_bits;
    int cert_warn_days;
    int build_iso;
    int generate_keys;
    int setup_efuse;
    int efuse_usb_mode;
    int rpm_signing;
    int check_certs;
    int include_drivers;
    int cleanup;
    int verbose;
    int yes_to_all;
} config_t;

/* Global configuration instance */
extern config_t cfg;

/* Valid release versions (whitelist) */
extern const char *VALID_RELEASES[];

/* ============================================================================
 * Driver-to-Kernel-Config Mapping
 * ============================================================================ */
typedef struct {
    const char *driver_prefix;
    const char *description;
    const char *kernel_configs;
} driver_kernel_map_t;

extern const driver_kernel_map_t DRIVER_KERNEL_MAP[];

/* ============================================================================
 * Logging Functions (habv4_common.c)
 * ============================================================================ */
void log_info(const char *fmt, ...);
void log_step(const char *fmt, ...);
void log_warn(const char *fmt, ...);
void log_error(const char *fmt, ...);

/* ============================================================================
 * Utility Functions (habv4_common.c)
 * ============================================================================ */
int run_cmd(const char *cmd);
int file_exists(const char *path);
int dir_exists(const char *path);
int mkdir_p(const char *path);
long get_file_size(const char *path);
const char *get_host_arch(void);

/* ============================================================================
 * Security/Validation Functions (habv4_common.c)
 * ============================================================================ */
int validate_path_safe(const char *path);
int validate_release(const char *release);
char* create_secure_tempdir(const char *prefix);
const char* sanitize_cmd_for_log(const char *cmd);
int validate_key_size(int bits);
int verify_sha3_256(const char *file_path, const char *expected_hash);

/* ============================================================================
 * Certificate Functions (habv4_common.c)
 * ============================================================================ */
int check_certificate_expiry(const char *cert_path);
int check_all_certificates(const char *keys_dir, int warn_days);

/* ============================================================================
 * Key Generation Functions (habv4_keys.c)
 * ============================================================================ */
int generate_key_pair(const char *name, const char *subject, int bits, int days);
int generate_mok_key(void);
int generate_srk_key(void);
int generate_simple_key(const char *name, int bits);
int generate_all_keys(void);
int generate_gpg_keys(void);

/* ============================================================================
 * eFuse Functions (habv4_efuse.c)
 * ============================================================================ */
int setup_efuse_simulation(void);
int create_efuse_usb(const char *device);

/* ============================================================================
 * Shim/Ventoy Download Functions (habv4_shim.c)
 * ============================================================================ */
void get_executable_dir(char *dir, size_t size);
int extract_embedded_shim_components(void);
int download_ventoy_components_fallback(void);

/* ============================================================================
 * Kernel Build Functions (habv4_kernel.c)
 * ============================================================================ */
int get_kernel_version_from_spec(char *version, size_t ver_size);
int find_kernel_tarball(char *tarball_path, size_t path_size, char *version, size_t ver_size);
int find_kernel_config(char *config_path, size_t path_size, const char *arch, const char *flavor);
int build_linux_kernel(void);

/* ============================================================================
 * Driver Integration Functions (habv4_drivers.c)
 * ============================================================================ */
int scan_driver_rpms(const char *drivers_dir, char driver_rpms[][512], int max_rpms);
void extract_rpm_base_name(const char *rpm_path, char *base_name, size_t size);
const char* get_kernel_configs_for_driver(const char *rpm_base_name);
int apply_driver_kernel_configs(const char *kernel_src, const char *drivers_dir);
int integrate_driver_rpms(const char *drivers_dir, const char *iso_extract, 
                          const char *initrd_extract);

/* ============================================================================
 * ISO Creation Functions (habv4_iso.c)
 * ============================================================================ */
int find_base_iso(char *iso_path, size_t path_size);
int create_secure_boot_iso(void);

/* ============================================================================
 * Diagnostic/Utility Functions (habv4_diag.c)
 * ============================================================================ */
int do_cleanup(void);
int diagnose_iso(const char *iso_path);
int verify_installation(void);
void show_help(void);

#endif /* HABV4_COMMON_H */
