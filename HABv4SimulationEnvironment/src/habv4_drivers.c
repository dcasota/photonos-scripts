/*
 * habv4_drivers.c
 *
 * Driver integration and kernel build functions for
 * PhotonOS-HABv4Emulation-ISOCreator
 *
 * This module handles:
 * - Driver RPM scanning and integration
 * - Kernel configuration for drivers
 * - Linux kernel build process
 * - Shim/Ventoy component extraction
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include "habv4_common.h"
#include "rpm_secureboot_patcher.h"

/* ============================================================================
 * Driver RPM Scanning
 * ============================================================================ */

int scan_driver_rpms(const char *drivers_dir, char driver_rpms[][512], int max_rpms) {
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
        const char *ext = strstr(entry->d_name, ".rpm");
        if (ext && ext[4] == '\0') {
            snprintf(driver_rpms[count], 512, "%s/%s", drivers_dir, entry->d_name);
            count++;
        }
    }
    closedir(dir);
    
    return count;
}

/* ============================================================================
 * RPM Base Name Extraction
 * ============================================================================ */

void extract_rpm_base_name(const char *rpm_path, char *base_name, size_t size) {
    const char *filename = strrchr(rpm_path, '/');
    filename = filename ? filename + 1 : rpm_path;
    
    char temp[256];
    strncpy(temp, filename, sizeof(temp) - 1);
    temp[sizeof(temp) - 1] = '\0';
    
    char *ext = strstr(temp, ".rpm");
    if (ext) *ext = '\0';
    
    char *arch_suffixes[] = {".noarch", ".x86_64", ".aarch64", ".i686", NULL};
    for (int i = 0; arch_suffixes[i]; i++) {
        char *arch = strstr(temp, arch_suffixes[i]);
        if (arch) {
            *arch = '\0';
            break;
        }
    }
    
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

/* ============================================================================
 * Driver Kernel Config Lookup
 * ============================================================================ */

const char* get_kernel_configs_for_driver(const char *rpm_base_name) {
    for (int i = 0; DRIVER_KERNEL_MAP[i].driver_prefix != NULL; i++) {
        if (strncmp(rpm_base_name, DRIVER_KERNEL_MAP[i].driver_prefix, 
                    strlen(DRIVER_KERNEL_MAP[i].driver_prefix)) == 0) {
            return DRIVER_KERNEL_MAP[i].kernel_configs;
        }
    }
    return NULL;
}

/* ============================================================================
 * Apply Driver Kernel Configurations
 * ============================================================================ */

int apply_driver_kernel_configs(const char *kernel_src, const char *drivers_dir) {
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
            
            char configs_copy[1024];
            strncpy(configs_copy, kernel_configs, sizeof(configs_copy) - 1);
            configs_copy[sizeof(configs_copy) - 1] = '\0';
            
            char *config = strtok(configs_copy, " ");
            while (config) {
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

/* ============================================================================
 * Driver RPM Integration
 * ============================================================================ */

int integrate_driver_rpms(const char *drivers_dir, const char *iso_extract, 
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
    
    char gpg_home[512];
    snprintf(gpg_home, sizeof(gpg_home), "%s/.gnupg", cfg.keys_dir);
    int sign_rpms = cfg.rpm_signing && dir_exists(gpg_home);
    
    for (int i = 0; i < rpm_count; i++) {
        const char *rpm_path = driver_rpms[i];
        const char *filename = strrchr(rpm_path, '/');
        filename = filename ? filename + 1 : rpm_path;
        
        char target_rpm[512];
        if (strstr(filename, ".noarch.rpm")) {
            snprintf(target_rpm, sizeof(target_rpm), "%s/RPMS/noarch/%s", iso_extract, filename);
        } else {
            snprintf(target_rpm, sizeof(target_rpm), "%s/RPMS/x86_64/%s", iso_extract, filename);
        }
        
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", rpm_path, target_rpm);
        run_cmd(cmd);
        
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
    
    /* Update packages_mok.json */
    char packages_json[512];
    snprintf(packages_json, sizeof(packages_json), "%s/installer/packages_mok.json", initrd_extract);
    
    if (file_exists(packages_json)) {
        log_info("Updating packages_mok.json with driver packages...");
        
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
            
            char pkg_args[2048] = "";
            for (int i = 0; i < rpm_count; i++) {
                char base_name[256];
                extract_rpm_base_name(driver_rpms[i], base_name, sizeof(base_name));
                
                const char *filename = strrchr(driver_rpms[i], '/');
                filename = filename ? filename + 1 : driver_rpms[i];
                char pkg_name[256];
                strncpy(pkg_name, filename, sizeof(pkg_name) - 1);
                char *ext = strstr(pkg_name, ".rpm");
                if (ext) *ext = '\0';
                char *arch = strstr(pkg_name, ".noarch");
                if (!arch) arch = strstr(pkg_name, ".x86_64");
                if (arch) *arch = '\0';
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

/* ============================================================================
 * Kernel Config Discovery
 * ============================================================================ */

int find_kernel_config(char *config_path, size_t path_size, const char *arch, const char *flavor) {
    char path[512];
    
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
        if (strcmp(arch, "aarch64") == 0) {
            config_name = "config_aarch64";
        } else {
            config_name = "config";
        }
    }
    
    snprintf(path, sizeof(path), "%s/SPECS/linux/%s", cfg.photon_dir, config_name);
    if (file_exists(path)) {
        strncpy(config_path, path, path_size - 1);
        return 0;
    }
    
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

/* ============================================================================
 * Kernel Version Discovery
 * ============================================================================ */

int get_kernel_version_from_spec(char *version, size_t ver_size) {
    char spec_path[512];
    snprintf(spec_path, sizeof(spec_path), "%s/SPECS/linux/linux-esx.spec", cfg.photon_dir);
    
    if (!file_exists(spec_path)) {
        snprintf(spec_path, sizeof(spec_path), "%s/SPECS/linux/linux.spec", cfg.photon_dir);
    }
    
    if (!file_exists(spec_path)) {
        return -1;
    }
    
    FILE *f = fopen(spec_path, "r");
    if (!f) return -1;
    
    char line[256];
    char ver[64] = "", rel[64] = "";
    
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "Version:", 8) == 0) {
            sscanf(line, "Version: %63s", ver);
        } else if (strncmp(line, "Release:", 8) == 0) {
            sscanf(line, "Release: %63s", rel);
        }
        if (ver[0] && rel[0]) break;
    }
    fclose(f);
    
    if (ver[0] && rel[0]) {
        char *pct = strchr(rel, '%');
        if (pct) *pct = '\0';
        snprintf(version, ver_size, "%s-%s.ph5-esx", ver, rel);
        return 0;
    }
    
    return -1;
}

/* ============================================================================
 * Kernel Tarball Discovery
 * ============================================================================ */

int find_kernel_tarball(char *tarball_path, size_t path_size, char *version, size_t ver_size) {
    char sources_dir[512];
    snprintf(sources_dir, sizeof(sources_dir), "%s/SOURCES/linux", cfg.photon_dir);
    
    DIR *dir = opendir(sources_dir);
    if (!dir) {
        const char *alt_dirs[] = {
            "/root/5.0/SOURCES",
            "/root/photon/SOURCES/linux",
            "/usr/src/photon/SOURCES/linux",
            NULL
        };
        
        for (int i = 0; alt_dirs[i]; i++) {
            dir = opendir(alt_dirs[i]);
            if (dir) {
                strncpy(sources_dir, alt_dirs[i], sizeof(sources_dir) - 1);
                break;
            }
        }
        
        if (!dir) {
            return -1;
        }
    }
    
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "linux-", 6) == 0 &&
            strstr(entry->d_name, ".tar")) {
            
            snprintf(tarball_path, path_size, "%s/%s", sources_dir, entry->d_name);
            
            char ver_str[64];
            if (sscanf(entry->d_name, "linux-%63[^.].tar", ver_str) == 1) {
                strncpy(version, ver_str, ver_size - 1);
                version[ver_size - 1] = '\0';
            }
            
            closedir(dir);
            return 0;
        }
    }
    
    closedir(dir);
    return -1;
}

/* ============================================================================
 * Shim Component Extraction
 * ============================================================================ */

void get_executable_dir(char *dir, size_t size) {
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
    dir[size - 1] = '\0';
}

int extract_embedded_shim_components(void) {
    char shim_dest[512], mokm_dest[512];
    snprintf(shim_dest, sizeof(shim_dest), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mokm_dest, sizeof(mokm_dest), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    if (file_exists(shim_dest) && file_exists(mokm_dest)) {
        log_info("SUSE shim components already present");
        return 0;
    }
    
    char exe_dir[512];
    get_executable_dir(exe_dir, sizeof(exe_dir));
    
    char data_shim[512], data_mokm[512];
    snprintf(data_shim, sizeof(data_shim), "%s/../data/shim-suse.efi", exe_dir);
    snprintf(data_mokm, sizeof(data_mokm), "%s/../data/MokManager-suse.efi", exe_dir);
    
    if (file_exists(data_shim) && file_exists(data_mokm)) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", data_shim, shim_dest);
        run_cmd(cmd);
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", data_mokm, mokm_dest);
        run_cmd(cmd);
        log_info("Copied SUSE shim components from data directory");
        return 0;
    }
    
    log_info("SUSE shim components not found locally, downloading...");
    return download_ventoy_components_fallback();
}

/* ============================================================================
 * Ventoy Download Fallback
 * ============================================================================ */

int download_ventoy_components_fallback(void) {
    log_info("Downloading Ventoy %s for SUSE shim extraction...", VENTOY_VERSION);
    
    char *work_dir = create_secure_tempdir("habventoy");
    if (!work_dir) {
        log_error("Failed to create temp directory");
        return -1;
    }
    
    char tarball[512], extract_dir[512];
    snprintf(tarball, sizeof(tarball), "%s/ventoy.tar.gz", work_dir);
    snprintf(extract_dir, sizeof(extract_dir), "%s/ventoy", work_dir);
    
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "wget -q --show-progress -O '%s' '%s'",
        tarball, VENTOY_URL);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to download Ventoy");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    
    log_info("Verifying SHA3-256 checksum...");
    if (!verify_sha3_256(tarball, VENTOY_SHA3_256)) {
        log_error("Ventoy checksum verification failed!");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    log_info("Checksum verified");
    
    mkdir_p(extract_dir);
    snprintf(cmd, sizeof(cmd), "tar -xzf '%s' -C '%s' --strip-components=1", tarball, extract_dir);
    if (run_cmd(cmd) != 0) {
        log_error("Failed to extract Ventoy");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    
    char disk_img[512], mount_point[512];
    snprintf(disk_img, sizeof(disk_img), "%s/ventoy/ventoy.disk.img.xz", work_dir);
    
    char decompressed_img[512];
    snprintf(decompressed_img, sizeof(decompressed_img), "%s/ventoy.disk.img", work_dir);
    
    if (file_exists(disk_img)) {
        snprintf(cmd, sizeof(cmd), "xz -d -k '%s' -c > '%s'", disk_img, decompressed_img);
        run_cmd(cmd);
    } else {
        snprintf(decompressed_img, sizeof(decompressed_img), "%s/ventoy/ventoy.disk.img", work_dir);
    }
    
    if (!file_exists(decompressed_img)) {
        log_error("ventoy.disk.img not found");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    
    char *mount_temp = create_secure_tempdir("habmount");
    if (!mount_temp) {
        log_error("Failed to create mount directory");
        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
        run_cmd(cmd);
        free(work_dir);
        return -1;
    }
    strncpy(mount_point, mount_temp, sizeof(mount_point) - 1);
    free(mount_temp);
    
    snprintf(cmd, sizeof(cmd), 
        "losetup -P -f '%s' 2>/dev/null && sleep 1", decompressed_img);
    run_cmd(cmd);
    
    FILE *fp = popen("losetup -j /dev/loop* 2>/dev/null | grep ventoy | head -1 | cut -d: -f1", "r");
    char loop_dev[64] = "";
    if (fp) {
        if (fgets(loop_dev, sizeof(loop_dev), fp)) {
            loop_dev[strcspn(loop_dev, "\n")] = '\0';
        }
        pclose(fp);
    }
    
    if (loop_dev[0] == '\0') {
        snprintf(cmd, sizeof(cmd), "mount -o loop,offset=1048576 '%s' '%s' 2>/dev/null", 
                 decompressed_img, mount_point);
    } else {
        snprintf(cmd, sizeof(cmd), "mount '%sp1' '%s' 2>/dev/null || mount '%s' '%s' 2>/dev/null", 
                 loop_dev, mount_point, loop_dev, mount_point);
    }
    
    if (run_cmd(cmd) != 0) {
        log_warn("Direct mount failed, trying offset-based mount...");
        snprintf(cmd, sizeof(cmd), "mount -o loop,offset=1048576 '%s' '%s'", 
                 decompressed_img, mount_point);
        if (run_cmd(cmd) != 0) {
            log_error("Failed to mount ventoy.disk.img");
            if (loop_dev[0]) {
                snprintf(cmd, sizeof(cmd), "losetup -d '%s' 2>/dev/null", loop_dev);
                run_cmd(cmd);
            }
            rmdir(mount_point);
            snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
            run_cmd(cmd);
            free(work_dir);
            return -1;
        }
    }
    
    char shim_src[512], mokm_src[512];
    char shim_dest[512], mokm_dest[512];
    
    snprintf(shim_src, sizeof(shim_src), "%s/EFI/BOOT/BOOTX64.EFI", mount_point);
    snprintf(mokm_src, sizeof(mokm_src), "%s/EFI/BOOT/MokManager.efi", mount_point);
    snprintf(shim_dest, sizeof(shim_dest), "%s/shim-suse.efi", cfg.keys_dir);
    snprintf(mokm_dest, sizeof(mokm_dest), "%s/MokManager-suse.efi", cfg.keys_dir);
    
    if (file_exists(shim_src)) {
        log_info("Verifying SUSE shim checksum...");
        if (verify_sha3_256(shim_src, SUSE_SHIM_SHA3_256)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", shim_src, shim_dest);
            run_cmd(cmd);
            log_info("Extracted and verified: shim-suse.efi (Microsoft-signed)");
        } else {
            log_error("SUSE shim checksum verification failed!");
        }
    }
    
    if (file_exists(mokm_src)) {
        log_info("Verifying MokManager checksum...");
        if (verify_sha3_256(mokm_src, SUSE_MOKMANAGER_SHA3_256)) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", mokm_src, mokm_dest);
            run_cmd(cmd);
            log_info("Extracted and verified: MokManager-suse.efi");
        } else {
            log_error("MokManager checksum verification failed!");
        }
    }
    
    snprintf(cmd, sizeof(cmd), "umount '%s' 2>/dev/null", mount_point);
    run_cmd(cmd);
    
    if (loop_dev[0]) {
        snprintf(cmd, sizeof(cmd), "losetup -d '%s' 2>/dev/null", loop_dev);
        run_cmd(cmd);
    }
    
    rmdir(mount_point);
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work_dir);
    run_cmd(cmd);
    free(work_dir);
    
    if (file_exists(shim_dest) && file_exists(mokm_dest)) {
        return 0;
    }
    
    return -1;
}

/* ============================================================================
 * Linux Kernel Build
 * ============================================================================ */

int build_linux_kernel(void) {
    const char *arch = get_host_arch();
    char cmd[4096];
    
    log_step("Linux %s kernel build...", arch);
    
    log_warn("Kernel build will take a long time (1-4 hours depending on CPU)!");
    printf("\n");
    printf("The full kernel build process includes:\n");
    printf("  1. Extracting kernel source tarball\n");
    printf("  2. Applying Photon OS kernel config\n");
    printf("  3. Enabling USB boot drivers (xhci_pci, ehci_pci, usb_storage)\n");
    printf("  4. Compiling kernel and modules\n");
    printf("  5. Signing vmlinuz with MOK key for Secure Boot\n");
    printf("  6. Signing all modules with MOK key\n");
    printf("\n");
    
    char build_dir[512], kernel_src[512], modules_dir[512];
    snprintf(build_dir, sizeof(build_dir), "%s/kernel-build", cfg.photon_dir);
    snprintf(modules_dir, sizeof(modules_dir), "%s/modules", build_dir);
    
    char vmlinuz_path[512];
    snprintf(vmlinuz_path, sizeof(vmlinuz_path), "%s/vmlinuz-mok", cfg.keys_dir);
    
    if (file_exists(vmlinuz_path) && dir_exists(modules_dir)) {
        log_info("Found existing signed kernel: %s", vmlinuz_path);
        log_info("Skipping kernel build (use --force-rebuild to rebuild)");
        return 0;
    }
    
    mkdir_p(build_dir);
    
    char tarball[512], version[64];
    if (find_kernel_tarball(tarball, sizeof(tarball), version, sizeof(version)) != 0) {
        char expected_tarball[512];
        snprintf(expected_tarball, sizeof(expected_tarball), 
            "%s/SOURCES/linux/linux-6.1.159.tar.xz", cfg.photon_dir);
        
        if (!file_exists(expected_tarball)) {
            log_info("Downloading kernel source...");
            mkdir_p(cfg.photon_dir);
            char sources_dir[512];
            snprintf(sources_dir, sizeof(sources_dir), "%s/SOURCES/linux", cfg.photon_dir);
            mkdir_p(sources_dir);
            
            snprintf(cmd, sizeof(cmd),
                "wget -q --show-progress -O '%s' "
                "'https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.159.tar.xz'",
                expected_tarball);
            
            if (run_cmd(cmd) != 0) {
                log_error("Failed to download kernel source");
                log_info("Please download linux-6.1.x tarball manually to:");
                log_info("  %s/SOURCES/linux/", cfg.photon_dir);
                return -1;
            }
        }
        
        strncpy(tarball, expected_tarball, sizeof(tarball) - 1);
        strncpy(version, "6.1.159", sizeof(version) - 1);
    }
    
    log_info("Using kernel source: %s", tarball);
    log_info("Kernel version: %s", version);
    
    snprintf(kernel_src, sizeof(kernel_src), "%s/linux-%s", build_dir, version);
    
    if (!dir_exists(kernel_src)) {
        log_info("Extracting kernel source...");
        snprintf(cmd, sizeof(cmd), "tar -xf '%s' -C '%s'", tarball, build_dir);
        if (run_cmd(cmd) != 0) {
            log_error("Failed to extract kernel source");
            return -1;
        }
    }
    
    char config_src[512];
    if (find_kernel_config(config_src, sizeof(config_src), arch, "esx") != 0) {
        log_warn("Photon kernel config not found, using default config");
        snprintf(cmd, sizeof(cmd), "cd '%s' && make defconfig", kernel_src);
        run_cmd(cmd);
    } else {
        log_info("Using Photon kernel config: %s", config_src);
        snprintf(cmd, sizeof(cmd), "cp '%s' '%s/.config'", config_src, kernel_src);
        run_cmd(cmd);
    }
    
    /* Enable USB drivers as built-in */
    log_info("Enabling USB boot drivers as built-in...");
    const char *usb_configs[] = {
        "CONFIG_USB_SUPPORT", "CONFIG_USB", "CONFIG_USB_PCI",
        "CONFIG_USB_XHCI_HCD", "CONFIG_USB_XHCI_PCI",
        "CONFIG_USB_EHCI_HCD", "CONFIG_USB_EHCI_PCI",
        "CONFIG_USB_UHCI_HCD", "CONFIG_USB_OHCI_HCD", "CONFIG_USB_OHCI_PCI",
        "CONFIG_USB_STORAGE", "CONFIG_USB_UAS",
        "CONFIG_BLK_DEV_SD", "CONFIG_SCSI", "CONFIG_SCSI_MOD",
        NULL
    };
    
    for (int i = 0; usb_configs[i]; i++) {
        snprintf(cmd, sizeof(cmd), "cd '%s' && scripts/config --enable %s", 
                 kernel_src, usb_configs[i]);
        run_cmd(cmd);
    }
    
    /* Apply driver-specific kernel configs if --drivers specified */
    if (cfg.include_drivers && cfg.drivers_dir[0] != '\0') {
        log_info("Applying driver-specific kernel configurations...");
        apply_driver_kernel_configs(kernel_src, cfg.drivers_dir);
    }
    
    /* Enable module signing */
    log_info("Enabling module signing for Secure Boot...");
    char mok_key[512], mok_crt[512];
    snprintf(mok_key, sizeof(mok_key), "%s/MOK.key", cfg.keys_dir);
    snprintf(mok_crt, sizeof(mok_crt), "%s/MOK.crt", cfg.keys_dir);
    
    snprintf(cmd, sizeof(cmd), "cd '%s' && scripts/config --enable MODULE_SIG", kernel_src);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cd '%s' && scripts/config --enable MODULE_SIG_ALL", kernel_src);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cd '%s' && scripts/config --set-str MODULE_SIG_KEY '%s'", 
             kernel_src, mok_key);
    run_cmd(cmd);
    snprintf(cmd, sizeof(cmd), "cd '%s' && scripts/config --set-str MODULE_SIG_HASH sha256", kernel_src);
    run_cmd(cmd);
    
    snprintf(cmd, sizeof(cmd), "cd '%s' && make olddefconfig", kernel_src);
    run_cmd(cmd);
    
    /* Build kernel */
    int nproc = 4;
    FILE *fp = popen("nproc 2>/dev/null", "r");
    if (fp) {
        if (fscanf(fp, "%d", &nproc) != 1) nproc = 4;
        pclose(fp);
    }
    
    log_info("Building kernel with %d parallel jobs...", nproc);
    snprintf(cmd, sizeof(cmd), "cd '%s' && make -j%d 2>&1 | tail -20", kernel_src, nproc);
    if (run_cmd(cmd) != 0) {
        log_error("Kernel build failed");
        return -1;
    }
    
    /* Build modules */
    log_info("Building modules...");
    snprintf(cmd, sizeof(cmd), "cd '%s' && make modules -j%d 2>&1 | tail -10", kernel_src, nproc);
    run_cmd(cmd);
    
    /* Install modules */
    log_info("Installing modules...");
    mkdir_p(modules_dir);
    snprintf(cmd, sizeof(cmd), "cd '%s' && make INSTALL_MOD_PATH='%s' modules_install 2>&1 | tail -5",
             kernel_src, modules_dir);
    run_cmd(cmd);
    
    /* Sign kernel with MOK key */
    char kernel_image[512];
    snprintf(kernel_image, sizeof(kernel_image), "%s/arch/%s/boot/bzImage", 
             kernel_src, strcmp(arch, "aarch64") == 0 ? "arm64" : "x86");
    
    if (file_exists(kernel_image)) {
        log_info("Signing kernel with MOK key...");
        snprintf(cmd, sizeof(cmd), 
            "sbsign --key '%s' --cert '%s' --output '%s' '%s' 2>/dev/null",
            mok_key, mok_crt, vmlinuz_path, kernel_image);
        
        if (run_cmd(cmd) != 0) {
            log_warn("sbsign failed, copying unsigned kernel");
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", kernel_image, vmlinuz_path);
            run_cmd(cmd);
        } else {
            log_info("Kernel signed successfully: %s", vmlinuz_path);
        }
    } else {
        log_error("Kernel image not found: %s", kernel_image);
        return -1;
    }
    
    log_info("Kernel build complete!");
    log_info("  Signed kernel: %s", vmlinuz_path);
    log_info("  Modules: %s", modules_dir);
    
    return 0;
}
