/*
 * rpm_secureboot_patcher.h
 *
 * RPM Secure Boot Patcher - Creates MOK-signed variants of boot packages
 *
 * This subcomponent:
 * 1. Discovers relevant RPM packages (version-agnostic)
 * 2. Generates SPEC files for MOK-signed variants
 * 3. Builds MOK-signed RPMs
 * 4. Integrates them into the ISO alongside originals
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#ifndef RPM_SECUREBOOT_PATCHER_H
#define RPM_SECUREBOOT_PATCHER_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Package information structure */
typedef struct {
    char *rpm_path;           /* Full path to RPM file */
    char *name;               /* Package name (e.g., "grub2-efi-image") */
    char *version;            /* Version (e.g., "2.12") */
    char *release;            /* Release (e.g., "1.ph5") */
    char *arch;               /* Architecture (e.g., "x86_64") */
    char *spec_path;          /* Path to SPEC file */
    char **files;             /* List of files in package */
    int file_count;
} rpm_package_info_t;

/* Discovered packages structure */
typedef struct {
    /* Original packages */
    rpm_package_info_t *grub_efi;       /* grub2-efi-image */
    rpm_package_info_t *linux_kernel;   /* linux */
    rpm_package_info_t *shim_signed;    /* shim-signed */
    rpm_package_info_t *shim;           /* shim (for MokManager source) */
    
    /* Photon OS release info */
    char *release;                      /* e.g., "5.0" */
    char *dist_tag;                     /* e.g., ".ph5" */
} discovered_packages_t;

/* Build configuration */
typedef struct {
    char *work_dir;           /* Temporary work directory */
    char *specs_dir;          /* Directory for generated SPEC files */
    char *rpmbuild_dir;       /* rpmbuild top directory */
    char *output_dir;         /* Output directory for built RPMs */
    char *source_rpm_dir;     /* Source RPMs directory */
    char *source_specs_dir;   /* Source SPECS directory (e.g., /root/5.0/SPECS) */
    char *mok_key;            /* MOK private key path */
    char *mok_cert;           /* MOK certificate path */
    char *release;            /* Photon OS release (e.g., "5.0") */
    char *keys_dir;           /* Keys directory (for pre-built EFI binaries) */
    int verbose;
} rpm_build_config_t;

/* Validation result */
typedef struct {
    int signature_valid;      /* sbverify passes */
    int rpm_valid;            /* rpm -K passes */
    int provides_correct;     /* Provides original package */
    int files_present;        /* Expected files exist */
    char *error_message;      /* Error details if any */
} rpm_validation_result_t;

/* Error codes */
typedef enum {
    RPM_PATCH_SUCCESS = 0,
    RPM_PATCH_ERR_DISCOVERY_FAILED = -1,
    RPM_PATCH_ERR_SPEC_NOT_FOUND = -2,
    RPM_PATCH_ERR_SPEC_GENERATION_FAILED = -3,
    RPM_PATCH_ERR_BUILD_FAILED = -4,
    RPM_PATCH_ERR_SIGN_FAILED = -5,
    RPM_PATCH_ERR_VALIDATION_FAILED = -6,
    RPM_PATCH_ERR_INTEGRATION_FAILED = -7,
    RPM_PATCH_ERR_MISSING_DEPENDENCY = -8,
    RPM_PATCH_ERR_OUT_OF_MEMORY = -9,
} rpm_patch_error_t;

/* ============================================================================
 * API Functions
 * ============================================================================ */

/**
 * Discover Secure Boot related packages
 * 
 * Finds packages by the files they provide, not by name patterns.
 * This makes the discovery version-agnostic.
 *
 * @param rpm_dir     Directory containing RPM packages
 * @param specs_dir   Directory containing SPEC files
 * @param release     Photon OS release (e.g., "5.0")
 * @return            Discovered packages structure, or NULL on error
 */
discovered_packages_t* rpm_discover_packages(
    const char *rpm_dir,
    const char *specs_dir,
    const char *release
);

/**
 * Generate MOK-signed SPEC files
 *
 * Creates new SPEC files for MOK variants of the packages.
 * The generated specs create packages that:
 * - Have "-mok" suffix in name
 * - Provide the same capabilities as originals
 * - Conflict with originals (can't install both)
 *
 * @param config      Build configuration
 * @param packages    Discovered packages
 * @return            0 on success, negative error code on failure
 */
int rpm_generate_mok_specs(
    rpm_build_config_t *config,
    discovered_packages_t *packages
);

/**
 * Build MOK-signed RPM packages
 *
 * Builds the MOK variant packages using rpmbuild.
 * Signs the EFI binaries and kernel with the MOK key.
 *
 * @param config      Build configuration
 * @param packages    Discovered packages
 * @return            0 on success, negative error code on failure
 */
int rpm_build_mok_packages(
    rpm_build_config_t *config,
    discovered_packages_t *packages
);

/**
 * Validate a rebuilt MOK RPM
 *
 * Checks that the RPM is valid and properly signed.
 *
 * @param rpm_path    Path to the rebuilt RPM
 * @param mok_cert    Path to MOK certificate for verification
 * @return            Validation result structure
 */
rpm_validation_result_t* rpm_validate_mok_package(
    const char *rpm_path,
    const char *mok_cert
);

/**
 * Integrate MOK packages into ISO
 *
 * Copies MOK-signed RPMs to the ISO alongside originals.
 * Both sets of packages will be available for installation.
 *
 * @param iso_rpm_dir   ISO's RPMS directory
 * @param config        Build configuration
 * @return              0 on success, negative error code on failure
 */
int rpm_integrate_to_iso(
    const char *iso_rpm_dir,
    rpm_build_config_t *config
);

/**
 * Sign MOK RPM packages with GPG key
 *
 * Signs all MOK-variant RPMs in the output directory using rpmsign.
 * Requires GPG key to be generated first.
 *
 * @param config        Build configuration
 * @param gpg_home      Path to GNUPGHOME directory containing GPG keys
 * @param gpg_key_name  GPG key identifier (Name-Real from key generation)
 * @return              0 on success, negative error code on failure
 */
int rpm_sign_mok_packages(
    rpm_build_config_t *config,
    const char *gpg_home,
    const char *gpg_key_name
);

/**
 * Main entry point - patch and build all Secure Boot RPMs
 *
 * This function:
 * 1. Discovers relevant packages
 * 2. Generates MOK SPEC files
 * 3. Builds MOK-signed RPMs
 * 4. Validates the built packages
 * 5. Integrates them into the ISO
 *
 * @param photon_release_dir   Photon OS release directory (e.g., /root/5.0)
 * @param iso_extract_dir      Extracted ISO directory
 * @param mok_key              Path to MOK private key
 * @param mok_cert             Path to MOK certificate
 * @param verbose              Enable verbose output
 * @return                     0 on success, negative error code on failure
 */
int rpm_patch_secureboot_packages(
    const char *photon_release_dir,
    const char *iso_extract_dir,
    const char *mok_key,
    const char *mok_cert,
    int verbose
);

/* ============================================================================
 * Cleanup Functions
 * ============================================================================ */

/**
 * Free discovered packages structure
 */
void rpm_free_discovered_packages(discovered_packages_t *packages);

/**
 * Free package info structure
 */
void rpm_free_package_info(rpm_package_info_t *pkg);

/**
 * Free validation result structure
 */
void rpm_free_validation_result(rpm_validation_result_t *result);

/**
 * Free build configuration
 */
void rpm_free_build_config(rpm_build_config_t *config);

#endif /* RPM_SECUREBOOT_PATCHER_H */
