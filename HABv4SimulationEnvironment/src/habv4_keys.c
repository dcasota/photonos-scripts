/*
 * habv4_keys.c
 *
 * Key generation functions for PhotonOS-HABv4Emulation-ISOCreator
 * Includes MOK, SRK, GPG, and other cryptographic key generation.
 *
 * Copyright 2024 HABv4 Project
 * SPDX-License-Identifier: GPL-3.0+
 */

#include "habv4_common.h"

/* ============================================================================
 * Key Pair Generation
 * ============================================================================ */

int generate_key_pair(const char *name, const char *subject, int bits, int days) {
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

/* ============================================================================
 * MOK Key Generation (Machine Owner Key for Secure Boot)
 * ============================================================================ */

int generate_mok_key(void) {
    char cmd[2048];
    char key_path[512], crt_path[512], der_path[512], cnf_path[512];
    
    snprintf(key_path, sizeof(key_path), "%s/MOK.key", cfg.keys_dir);
    snprintf(crt_path, sizeof(crt_path), "%s/MOK.crt", cfg.keys_dir);
    snprintf(der_path, sizeof(der_path), "%s/MOK.der", cfg.keys_dir);
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

/* ============================================================================
 * SRK Key Generation (Super Root Key for HAB)
 * ============================================================================ */

int generate_srk_key(void) {
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

/* ============================================================================
 * Simple Key Generation (CSF, IMG keys)
 * ============================================================================ */

int generate_simple_key(const char *name, int bits) {
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

/* ============================================================================
 * Generate All Keys
 * ============================================================================ */

int generate_all_keys(void) {
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
    
    /* Generate kernel module signing key */
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

int generate_gpg_keys(void) {
    char gpg_pub[512], gpg_home[512], gpg_batch[512];
    char cmd[2048];
    
    snprintf(gpg_pub, sizeof(gpg_pub), "%s/%s", cfg.keys_dir, GPG_KEY_FILE);
    snprintf(gpg_home, sizeof(gpg_home), "%s/.gnupg", cfg.keys_dir);
    
    if (file_exists(gpg_pub)) {
        log_info("GPG key already exists: %s", gpg_pub);
        return 0;
    }
    
    log_step("Generating GPG key pair for RPM signing...");
    
    mkdir_p(gpg_home);
    snprintf(cmd, sizeof(cmd), "chmod 700 '%s'", gpg_home);
    run_cmd(cmd);
    
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
    
    snprintf(cmd, sizeof(cmd), 
        "GNUPGHOME='%s' gpg --batch --gen-key '%s' 2>/dev/null",
        gpg_home, gpg_batch);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate GPG key");
        unlink(gpg_batch);
        return -1;
    }
    
    snprintf(cmd, sizeof(cmd),
        "GNUPGHOME='%s' gpg --export --armor '%s' > '%s' 2>/dev/null",
        gpg_home, GPG_KEY_NAME, gpg_pub);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to export GPG public key");
        unlink(gpg_batch);
        return -1;
    }
    
    unlink(gpg_batch);
    
    log_info("GPG key pair generated: %s", GPG_KEY_NAME);
    log_info("Public key exported to: %s", gpg_pub);
    return 0;
}
