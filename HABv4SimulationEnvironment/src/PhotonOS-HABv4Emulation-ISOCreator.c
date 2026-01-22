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

#define VERSION "1.1.0"
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
#define RESET   "\x1b[0m"

/* Configuration structure */
typedef struct {
    char release[16];
    char keys_dir[512];
    char efuse_dir[512];
    char photon_dir[512];
    char input_iso[512];
    char output_iso[512];
    char efuse_usb_device[128];
    int mok_days;
    int build_iso;
    int generate_keys;
    int setup_efuse;
    int download_ventoy;
    int use_ventoy_preloader;
    int skip_preloader_build;
    int full_kernel_build;
    int efuse_usb_mode;
    int cleanup;
    int verbose;
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
    printf("Continue? [y/N] ");
    fflush(stdout);
    
    char confirm[8];
    if (fgets(confirm, sizeof(confirm), stdin) == NULL || 
        (confirm[0] != 'y' && confirm[0] != 'Y')) {
        log_info("Aborted");
        return 0;
    }
    
    char cmd[1024];
    
    snprintf(cmd, sizeof(cmd), "parted -s '%s' mklabel gpt", device);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to create partition table");
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd), "parted -s '%s' mkpart primary fat32 1MiB 100%%", device);
    run_cmd(cmd);
    
    char partition[256];
    if (strstr(device, "nvme") != NULL) {
        snprintf(partition, sizeof(partition), "%sp1", device);
    } else {
        snprintf(partition, sizeof(partition), "%s1", device);
    }
    
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
    
    snprintf(cmd, sizeof(cmd), "umount '%s'", mount_point);
    run_cmd(cmd);
    rmdir(mount_point);
    
    log_info("eFuse USB dongle created on %s (label: EFUSE_SIM)", device);
    return 0;
}

/* ============================================================================
 * Ventoy Components
 * ============================================================================ */

static int download_ventoy_components(void) {
    log_step("Downloading Ventoy components...");
    
    char shim_path[512], mok_path[512];
    snprintf(shim_path, sizeof(shim_path), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mok_path, sizeof(mok_path), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    if (file_exists(shim_path) && file_exists(mok_path)) {
        log_info("Ventoy components already exist");
        return 0;
    }
    
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
            
            snprintf(cmd, sizeof(cmd), "cp '%s/EFI/BOOT/grub.efi' '%s/ventoy-preloader.efi'",
                mount_point, cfg.keys_dir);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "cp '%s/EFI/BOOT/grubx64_real.efi' '%s/ventoy-grub-real.efi' 2>/dev/null || true",
                mount_point, cfg.keys_dir);
            run_cmd(cmd);
            
            snprintf(cmd, sizeof(cmd), "cp '%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer' '%s/ventoy-mok.cer' 2>/dev/null || true",
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
    
    char preloader[512], mok_cert[512];
    char hab_preloader[512];
    snprintf(hab_preloader, sizeof(hab_preloader), "%s/hab-preloader-signed.efi", cfg.keys_dir);
    
    if (cfg.use_ventoy_preloader || !file_exists(hab_preloader)) {
        snprintf(preloader, sizeof(preloader), "%s/ventoy-preloader.efi", cfg.keys_dir);
        snprintf(mok_cert, sizeof(mok_cert), "%s/ventoy-mok.cer", cfg.keys_dir);
        log_info("Using Ventoy PreLoader");
    } else {
        strncpy(preloader, hab_preloader, sizeof(preloader) - 1);
        snprintf(mok_cert, sizeof(mok_cert), "%s/MOK.der", cfg.keys_dir);
        log_info("Using HAB PreLoader");
    }
    
    char shim_path[512], mokm_path[512];
    snprintf(shim_path, sizeof(shim_path), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mokm_path, sizeof(mokm_path), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    if (!file_exists(shim_path) || !file_exists(mokm_path)) {
        log_error("Required Ventoy components missing. Run with --download-ventoy first.");
        return -1;
    }
    
    if (!file_exists(preloader)) {
        log_error("PreLoader not found: %s", preloader);
        return -1;
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
    
    char grub_real[512];
    snprintf(grub_real, sizeof(grub_real), "%s/EFI/BOOT/grubx64_real.efi", iso_extract);
    if (!file_exists(grub_real)) {
        snprintf(grub_real, sizeof(grub_real), "%s/EFI/BOOT/grubx64.efi", iso_extract);
    }
    if (!file_exists(grub_real)) {
        snprintf(grub_real, sizeof(grub_real), "%s/ventoy-grub-real.efi", cfg.keys_dir);
    }
    
    if (!file_exists(grub_real)) {
        log_error("GRUB not found");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        return -1;
    }
    
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
    
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/BOOTX64.EFI'", shim_path, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grub.efi'", preloader, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubx64_real.efi'", grub_real, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/MokManager.efi'", mokm_path, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/mmx64.efi'", mokm_path, efi_mount);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer'", mok_cert, efi_mount);
    run_cmd(cmd);
    
    /* Create grub.cfg - with eFuse USB mode support */
    char grub_cfg[512];
    snprintf(grub_cfg, sizeof(grub_cfg), "%s/EFI/BOOT/grub.cfg", efi_mount);
    FILE *f = fopen(grub_cfg, "w");
    if (f) {
        if (cfg.efuse_usb_mode) {
            /* eFuse USB verification mode - require dongle */
            fprintf(f,
                "# HABv4 eFuse USB Verification Mode\n"
                "set timeout=10\n"
                "set efuse_found=0\n"
                "\n"
                "# Search for eFuse USB dongle (label: EFUSE_SIM)\n"
                "search --no-floppy --label EFUSE_SIM --set=efuse_disk\n"
                "if [ -n \"$efuse_disk\" ]; then\n"
                "    if [ -f ($efuse_disk)/efuse_sim/srk_fuse.bin ]; then\n"
                "        set efuse_found=1\n"
                "        echo \"eFuse USB dongle found - Security Mode: CLOSED\"\n"
                "    fi\n"
                "fi\n"
                "\n"
                "if [ \"$efuse_found\" = \"0\" ]; then\n"
                "    echo \"\"\n"
                "    echo \"=========================================\"\n"
                "    echo \"BOOT BLOCKED - eFuse USB Dongle Required\"\n"
                "    echo \"=========================================\"\n"
                "    echo \"Insert eFuse USB dongle (label: EFUSE_SIM)\"\n"
                "    echo \"and select 'Retry' or reboot.\"\n"
                "    echo \"\"\n"
                "    menuentry \"Retry - Search for eFuse USB\" {\n"
                "        configfile /EFI/BOOT/grub.cfg\n"
                "    }\n"
                "    menuentry \"Reboot\" {\n"
                "        reboot\n"
                "    }\n"
                "    menuentry \"Power Off\" {\n"
                "        halt\n"
                "    }\n"
                "else\n"
                "    search --no-floppy --file --set=root /isolinux/isolinux.cfg\n"
                "    set prefix=($root)/boot/grub2\n"
                "    configfile $prefix/grub.cfg\n"
                "fi\n"
            );
            log_info("eFuse USB verification mode ENABLED");
        } else {
            /* Standard mode - no dongle required */
            fprintf(f,
                "search --no-floppy --file --set=root /isolinux/isolinux.cfg\n"
                "set prefix=($root)/boot/grub2\n"
                "configfile $prefix/grub.cfg\n"
            );
        }
        fclose(f);
    }
    
    snprintf(cmd, sizeof(cmd), "sync && umount '%s'", efi_mount);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", new_efiboot, efiboot_path);
    run_cmd(cmd);
    
    log_info("Updating ISO EFI directory...");
    snprintf(efi_boot_dir, sizeof(efi_boot_dir), "%s/EFI/BOOT", iso_extract);
    mkdir_p(efi_boot_dir);
    
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/BOOTX64.EFI'", shim_path, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grub.efi'", preloader, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/grubx64_real.efi'", grub_real, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/EFI/BOOT/MokManager.efi'", mokm_path, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/mmx64.efi'", mokm_path, iso_extract);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cp '%s' '%s/ENROLL_THIS_KEY_IN_MOKMANAGER.cer'", mok_cert, iso_extract);
    run_cmd(cmd);
    
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
        printf("  UEFI -> BOOTX64.EFI (SUSE shim)\n");
        printf("       -> grub.efi (PreLoader)\n");
        printf("       -> grubx64_real.efi (GRUB)\n");
        printf("       -> Linux kernel\n");
        printf("\n");
        printf("First Boot:\n");
        printf("  1. Security Violation -> MokManager\n");
        printf("  2. Enroll ENROLL_THIS_KEY_IN_MOKMANAGER.cer\n");
        printf("  3. Reboot\n");
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
            printf("  " YELLOW "[OK]" RESET " Ventoy PreLoader (fallback)\n");
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
    printf("  -d, --download-ventoy      Download Ventoy components (SUSE shim, MokManager)\n");
    printf("  -u, --create-efuse-usb=DEV Create eFuse USB dongle on device (e.g., /dev/sdb)\n");
    printf("  -E, --efuse-usb            Enable eFuse USB dongle verification in GRUB\n");
    printf("  -F, --full-kernel-build    Build kernel from source (takes hours)\n");
    printf("  -V, --use-ventoy           Use Ventoy PreLoader instead of HAB PreLoader\n");
    printf("  -S, --skip-build           Skip HAB PreLoader build\n");
    printf("  -c, --clean                Clean up all artifacts\n");
    printf("  -v, --verbose              Verbose output\n");
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
    printf("  %s -u /dev/sdb             # Create eFuse USB dongle\n", PROGRAM_NAME);
    printf("  %s -F                      # Full kernel build (hours)\n", PROGRAM_NAME);
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
        {"download-ventoy",   no_argument,       0, 'd'},
        {"create-efuse-usb",  required_argument, 0, 'u'},
        {"efuse-usb",         no_argument,       0, 'E'},
        {"full-kernel-build", no_argument,       0, 'F'},
        {"use-ventoy",        no_argument,       0, 'V'},
        {"skip-build",        no_argument,       0, 'S'},
        {"clean",             no_argument,       0, 'c'},
        {"verbose",           no_argument,       0, 'v'},
        {"help",              no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "r:i:o:k:e:m:bgsdEFVScu:vh", long_options, NULL)) != -1) {
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
            case 'd':
                cfg.download_ventoy = 1;
                break;
            case 'u':
                strncpy(cfg.efuse_usb_device, optarg, sizeof(cfg.efuse_usb_device) - 1);
                break;
            case 'E':
                cfg.efuse_usb_mode = 1;
                break;
            case 'F':
                cfg.full_kernel_build = 1;
                break;
            case 'V':
                cfg.use_ventoy_preloader = 1;
                break;
            case 'S':
                cfg.skip_preloader_build = 1;
                break;
            case 'c':
                cfg.cleanup = 1;
                break;
            case 'v':
                cfg.verbose = 1;
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
    
    if (strlen(cfg.efuse_usb_device) > 0) {
        if (!cfg.generate_keys) cfg.generate_keys = 1;
        if (!cfg.setup_efuse) cfg.setup_efuse = 1;
        
        if (cfg.generate_keys && generate_all_keys() != 0) return 1;
        if (cfg.setup_efuse && setup_efuse_simulation() != 0) return 1;
        return create_efuse_usb(cfg.efuse_usb_device);
    }
    
    /* If no specific action, default to full setup */
    if (!cfg.generate_keys && !cfg.setup_efuse && !cfg.download_ventoy && 
        !cfg.build_iso && !cfg.full_kernel_build) {
        cfg.generate_keys = 1;
        cfg.setup_efuse = 1;
        cfg.download_ventoy = 1;
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
    
    if (cfg.download_ventoy) {
        if (download_ventoy_components() != 0) return 1;
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
    printf("\nNext steps:\n");
    printf("  - Build ISO:        %s -b\n", PROGRAM_NAME);
    printf("  - With eFuse mode:  %s -E -b\n", PROGRAM_NAME);
    printf("  - Create USB:       %s -u /dev/sdX\n", PROGRAM_NAME);
    printf("  - Full kernel:      %s -F\n", PROGRAM_NAME);
    printf("  - Cleanup:          %s -c\n", PROGRAM_NAME);
    log_info("=========================================");
    
    return 0;
}
