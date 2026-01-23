# RPM Signing Implementation Plan for HABv4

## Overview

This document outlines the complete implementation plan to add RPM signing capability to the PhotonOS-HABv4Emulation-ISOCreator tool via a new `--rpm-signing` option.

## Goals

1. Generate GPG keys for RPM signing alongside MOK keys
2. Sign MOK-variant RPM packages after building
3. Include GPG public key on both ISO and eFuse USB stick
4. Configure kickstart to import GPG key during installation
5. Maintain backward compatibility (signing is optional)

## Architecture

### Key Storage Locations

```
/root/hab_keys/                    # Main keys directory
├── MOK.key                        # Secure Boot - MOK private key
├── MOK.crt                        # Secure Boot - MOK certificate  
├── MOK.der                        # Secure Boot - MOK cert (DER format)
├── RPM-GPG-KEY-habv4.pub          # RPM Signing - GPG public key (NEW)
├── RPM-GPG-KEY-habv4.sec          # RPM Signing - GPG private key (NEW)
└── ...

/root/efuse_sim/                   # eFuse simulation directory
├── efuse_sim/
│   ├── srk_fuse.bin
│   └── ...
└── RPM-GPG-KEY-habv4.pub          # GPG public key copy (NEW)

ISO root:
├── RPM-GPG-KEY-habv4              # GPG public key for import (NEW)
├── mok_ks.cfg                     # Kickstart - updated to import key
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer
└── ...

eFuse USB (/dev/sdX - EFUSE_SIM):
├── efuse_sim/
│   ├── srk_fuse.bin
│   └── ...
└── RPM-GPG-KEY-habv4              # GPG public key (NEW)
```

### Signing Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    --rpm-signing enabled                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Generate GPG Key Pair (if not exists)                       │
│     gpg --batch --gen-key (RSA 4096, no passphrase)            │
│     Export: RPM-GPG-KEY-habv4.pub, RPM-GPG-KEY-habv4.sec       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Build MOK RPM Packages (existing flow)                      │
│     - shim-signed-mok                                           │
│     - grub2-efi-image-mok                                       │
│     - linux-mok                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Sign MOK RPMs with GPG Key                                  │
│     rpmsign --define "_gpg_name HABv4" --addsign *.rpm         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Integrate into ISO                                          │
│     - Copy RPM-GPG-KEY-habv4 to ISO root                       │
│     - Update mok_ks.cfg with postinstall script                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. Copy GPG Key to eFuse USB (if --create-efuse-usb)          │
│     cp RPM-GPG-KEY-habv4 /mnt/efuse_usb/                       │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Details

### Phase 1: Configuration Structure Updates

**File: `PhotonOS-HABv4Emulation-ISOCreator.c`**

```c
// Add to config_t structure
typedef struct {
    // ... existing fields ...
    int rpm_signing;              // NEW: Enable RPM signing
    char gpg_key_id[256];         // NEW: GPG key identifier
} config_t;

// Add to defaults
#define DEFAULT_GPG_KEY_ID "HABv4 RPM Signing Key"
#define GPG_KEY_FILE "RPM-GPG-KEY-habv4"
```

### Phase 2: GPG Key Generation

**New function: `generate_gpg_keys()`**

```c
static int generate_gpg_keys(void) {
    char gpg_pub[512], gpg_sec[512], gpg_batch[512];
    
    snprintf(gpg_pub, sizeof(gpg_pub), "%s/%s.pub", cfg.keys_dir, GPG_KEY_FILE);
    snprintf(gpg_sec, sizeof(gpg_sec), "%s/%s.sec", cfg.keys_dir, GPG_KEY_FILE);
    
    // Check if keys already exist
    if (access(gpg_pub, F_OK) == 0 && access(gpg_sec, F_OK) == 0) {
        log_info("GPG keys already exist, skipping generation");
        return 0;
    }
    
    log_step("Generating GPG key pair for RPM signing...");
    
    // Create batch file for unattended key generation
    snprintf(gpg_batch, sizeof(gpg_batch), "%s/gpg_batch.txt", cfg.keys_dir);
    FILE *f = fopen(gpg_batch, "w");
    if (!f) {
        log_error("Failed to create GPG batch file");
        return -1;
    }
    
    fprintf(f,
        "%%echo Generating HABv4 RPM Signing Key\n"
        "Key-Type: RSA\n"
        "Key-Length: 4096\n"
        "Key-Usage: sign\n"
        "Name-Real: %s\n"
        "Name-Email: habv4-rpm@local\n"
        "Expire-Date: 0\n"
        "%%no-protection\n"
        "%%commit\n"
        "%%echo Done\n",
        DEFAULT_GPG_KEY_ID
    );
    fclose(f);
    
    // Generate key
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), 
        "GNUPGHOME='%s/.gnupg' gpg --batch --gen-key '%s'",
        cfg.keys_dir, gpg_batch);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to generate GPG key");
        return -1;
    }
    
    // Export public key (ASCII armored)
    snprintf(cmd, sizeof(cmd),
        "GNUPGHOME='%s/.gnupg' gpg --export --armor '%s' > '%s'",
        cfg.keys_dir, DEFAULT_GPG_KEY_ID, gpg_pub);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to export GPG public key");
        return -1;
    }
    
    // Export secret key (for backup)
    snprintf(cmd, sizeof(cmd),
        "GNUPGHOME='%s/.gnupg' gpg --export-secret-keys --armor '%s' > '%s'",
        cfg.keys_dir, DEFAULT_GPG_KEY_ID, gpg_sec);
    
    if (run_cmd(cmd) != 0) {
        log_error("Failed to export GPG secret key");
        return -1;
    }
    
    // Set restrictive permissions on secret key
    chmod(gpg_sec, 0600);
    
    // Cleanup batch file
    unlink(gpg_batch);
    
    log_info("GPG key pair generated: %s", DEFAULT_GPG_KEY_ID);
    return 0;
}
```

### Phase 3: RPM Signing Function

**New function in `rpm_secureboot_patcher.c`**

```c
int rpm_sign_packages(rpm_build_config_t *config) {
    char cmd[2048];
    char gpg_pub[512];
    
    snprintf(gpg_pub, sizeof(gpg_pub), "%s/RPM-GPG-KEY-habv4.pub", config->keys_dir);
    
    // Check if GPG key exists
    if (access(gpg_pub, F_OK) != 0) {
        log_error("GPG public key not found: %s", gpg_pub);
        return -1;
    }
    
    log_info("Signing MOK RPM packages with GPG key...");
    
    // Import public key into RPM database (for verification)
    snprintf(cmd, sizeof(cmd), "rpm --import '%s'", gpg_pub);
    if (run_cmd(cmd) != 0) {
        log_warn("Failed to import GPG key into RPM database");
    }
    
    // Find all MOK RPMs in output directory
    char rpm_pattern[512];
    snprintf(rpm_pattern, sizeof(rpm_pattern), "%s/*-mok-*.rpm", config->output_dir);
    
    glob_t globbuf;
    if (glob(rpm_pattern, 0, NULL, &globbuf) != 0) {
        log_warn("No MOK RPMs found to sign");
        return 0;
    }
    
    // Sign each RPM
    for (size_t i = 0; i < globbuf.gl_pathc; i++) {
        const char *rpm_path = globbuf.gl_pathv[i];
        
        log_debug("Signing: %s", rpm_path);
        
        snprintf(cmd, sizeof(cmd),
            "GNUPGHOME='%s/.gnupg' rpmsign "
            "--define '_gpg_name %s' "
            "--addsign '%s'",
            config->keys_dir,
            DEFAULT_GPG_KEY_ID,
            rpm_path);
        
        if (run_cmd(cmd) != 0) {
            log_error("Failed to sign: %s", rpm_path);
            globfree(&globbuf);
            return -1;
        }
        
        log_info("Signed: %s", basename((char*)rpm_path));
    }
    
    globfree(&globbuf);
    
    // Verify signatures
    log_info("Verifying RPM signatures...");
    snprintf(cmd, sizeof(cmd), "rpm --checksig %s/*-mok-*.rpm", config->output_dir);
    run_cmd(cmd);
    
    return 0;
}
```

### Phase 4: Kickstart Update

**Updated `mok_ks.cfg` generation:**

```c
// In create_secure_boot_iso() or similar function
static int create_mok_kickstart(const char *iso_extract, int rpm_signing) {
    char mok_ks_path[512];
    snprintf(mok_ks_path, sizeof(mok_ks_path), "%s/mok_ks.cfg", iso_extract);
    
    FILE *f = fopen(mok_ks_path, "w");
    if (!f) return -1;
    
    fprintf(f,
        "{\n"
        "    \"hostname\": \"photon-mok\",\n"
        "    \"password\": {\"crypted\": false, \"text\": \"changeme\"},\n"
        "    \"disk\": \"/dev/sda\",\n"
        "    \"bootmode\": \"efi\",\n"
        "    \"linux_flavor\": \"linux-mok\",\n"
        "    \"packages\": [\n"
        "        \"minimal\",\n"
        "        \"initramfs\",\n"
        "        \"linux-mok\",\n"
        "        \"grub2-efi-image-mok\",\n"
        "        \"shim-signed-mok\"\n"
        "    ],\n"
    );
    
    if (rpm_signing) {
        fprintf(f,
            "    \"postinstall\": [\n"
            "        \"rpm --import /cdrom/RPM-GPG-KEY-habv4\",\n"
            "        \"echo 'gpgcheck=1' >> /etc/yum.repos.d/photon.repo\",\n"
            "        \"echo 'repo_gpgcheck=1' >> /etc/yum.repos.d/photon.repo\"\n"
            "    ],\n"
        );
    }
    
    fprintf(f,
        "    \"eula_accepted\": true,\n"
        "    \"install_linux_esx\": false\n"
        "}\n"
    );
    
    fclose(f);
    return 0;
}
```

### Phase 5: eFuse USB Integration

**Update `create_efuse_usb()` function:**

```c
static int create_efuse_usb(const char *device) {
    // ... existing code ...
    
    // After copying eFuse files, also copy GPG key if rpm_signing enabled
    if (cfg.rpm_signing) {
        char gpg_src[512], gpg_dst[512];
        snprintf(gpg_src, sizeof(gpg_src), "%s/RPM-GPG-KEY-habv4.pub", cfg.keys_dir);
        snprintf(gpg_dst, sizeof(gpg_dst), "%s/RPM-GPG-KEY-habv4", mount_point);
        
        if (access(gpg_src, F_OK) == 0) {
            snprintf(cmd, sizeof(cmd), "cp '%s' '%s'", gpg_src, gpg_dst);
            run_cmd(cmd);
            log_info("GPG public key copied to eFuse USB");
        }
    }
    
    // ... rest of function ...
}
```

### Phase 6: Command Line Integration

**Add new option:**

```c
// In print_usage()
printf("  -R, --rpm-signing          Enable GPG signing of MOK RPM packages\n");

// In long_options[]
{"rpm-signing",       no_argument,       0, 'R'},

// In getopt_long() switch
case 'R':
    cfg.rpm_signing = 1;
    break;

// In main(), after RPM building
if (cfg.rpm_signing) {
    if (generate_gpg_keys() != 0) return 1;
    if (rpm_sign_packages(&rpm_config) != 0) {
        log_warn("RPM signing failed, continuing without signatures");
    }
}
```

## File Changes Summary

| File | Changes |
|------|---------|
| `PhotonOS-HABv4Emulation-ISOCreator.c` | Add `--rpm-signing` option, GPG key generation, eFuse USB update |
| `rpm_secureboot_patcher.c` | Add `rpm_sign_packages()` function |
| `rpm_secureboot_patcher.h` | Add function declaration |

## Testing Plan

### Unit Tests

1. **GPG Key Generation**
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -g -R
   ls -la /root/hab_keys/RPM-GPG-KEY-habv4.*
   ```

2. **RPM Signing**
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -b -R
   rpm --checksig /tmp/rpm_mok_build/output/*-mok-*.rpm
   ```

3. **eFuse USB with GPG Key**
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -b -R -u /dev/sdd -E -y
   mount /dev/sdd1 /mnt && ls -la /mnt/RPM-GPG-KEY-habv4
   ```

### Integration Tests

1. **Full ISO Build with Signing**
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator --release 5.0 --build-iso --rpm-signing -y
   ```

2. **Verify ISO Contents**
   ```bash
   mkdir /tmp/iso_check && mount -o loop output.iso /tmp/iso_check
   ls /tmp/iso_check/RPM-GPG-KEY-habv4
   cat /tmp/iso_check/mok_ks.cfg | grep postinstall
   rpm --checksig /tmp/iso_check/RPMS/x86_64/*-mok-*.rpm
   ```

3. **Installation Test**
   - Boot ISO in VM with Secure Boot enabled
   - Select "Install (Custom MOK) - Automated"
   - Verify installation completes
   - After reboot, verify: `rpm -qa gpg-pubkey*`

## Verification Commands

After installation, on the target system:

```bash
# Verify GPG key is imported
rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'

# Verify packages are signed
rpm -qa *-mok* --qf '%{NAME}\t%{SIGPGP:pgpsig}\n'

# Verify GPG check is enabled
grep gpgcheck /etc/yum.repos.d/*.repo
```

## Security Considerations

1. **Key Protection**: GPG private key stored in `keys_dir` with 0600 permissions
2. **Key Backup**: Secret key exported for disaster recovery
3. **No Passphrase**: Keys generated without passphrase for automation (acceptable for simulation)
4. **Production Recommendation**: Use HSM for production deployments

## Backward Compatibility

- `--rpm-signing` is optional; default behavior unchanged
- Existing ISOs continue to work without GPG signatures
- eFuse USB works with or without GPG key

## Dependencies

Required packages on build host:
- `gnupg2` (for gpg)
- `rpm-sign` (for rpmsign)

Both are typically pre-installed on Photon OS.

## Estimated Implementation Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Configuration updates | 1 hour | Low |
| GPG key generation | 2 hours | Low |
| RPM signing function | 2 hours | Medium |
| Kickstart updates | 1 hour | Low |
| eFuse USB integration | 1 hour | Low |
| Testing | 3 hours | Medium |
| **Total** | **10 hours** | **Low-Medium** |
