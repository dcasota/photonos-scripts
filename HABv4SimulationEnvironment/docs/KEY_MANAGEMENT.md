# Key Management Guide

This document covers key generation, storage, and usage for Secure Boot.

## Table of Contents

1. [Key Types Overview](#key-types-overview)
2. [UEFI Secure Boot Keys](#uefi-secure-boot-keys)
3. [Machine Owner Key (MOK)](#machine-owner-key-mok)
4. [Kernel Module Signing Key](#kernel-module-signing-key)
5. [HABv4 Simulation Keys](#habv4-simulation-keys)
6. [Key Storage and Security](#key-storage-and-security)
7. [Key Generation Commands](#key-generation-commands)
8. [MOK Enrollment](#mok-enrollment)

---

## Key Types Overview

### Key Hierarchy

```
/root/hab_keys/
│
├── UEFI Secure Boot Keys
│   ├── PK.key / PK.crt / PK.der       # Platform Key
│   ├── KEK.key / KEK.crt / KEK.der    # Key Exchange Key
│   └── DB.key / DB.crt / DB.der       # Signature Database Key
│
├── Machine Owner Key
│   ├── MOK.key                         # Private key
│   ├── MOK.crt                         # Certificate (PEM)
│   └── MOK.der                         # Certificate (DER for enrollment)
│
├── Kernel Module Signing
│   └── kernel_module_signing.pem       # Private key + certificate
│
├── HABv4 Simulation Keys
│   ├── srk.pem / srk_pub.pem          # Super Root Key
│   ├── srk_hash.bin                    # SRK hash for eFuse simulation
│   ├── csf.pem / csf_pub.pem          # Command Sequence File Key
│   └── img.pem / img_pub.pem          # Image Signing Key
│
├── Fedora Shim Components (SBAT Compliant)
│   ├── shim-fedora.efi                 # Fedora shim 15.8 (SBAT=shim,4)
│   └── mmx64-fedora.efi                # Fedora MokManager
│
└── Photon OS GRUB Stub
    └── grub-photon-stub.efi            # Custom GRUB stub (MOK-signed)
```

### Key Purposes

| Key | Size | Purpose | Used By |
|-----|------|---------|---------|
| PK | 2048-bit RSA | Control UEFI key database | Custom firmware |
| KEK | 2048-bit RSA | Authorize db/dbx updates | Custom firmware |
| DB | 2048-bit RSA | Sign bootloaders/kernels | UEFI verification |
| MOK | 2048-bit RSA | Sign custom binaries | Shim verification |
| Module Key | 4096-bit RSA | Sign kernel modules | Kernel verification |
| SRK | 4096-bit RSA | HABv4 root of trust | ARM boot simulation |
| CSF | 2048-bit RSA | HABv4 command signing | ARM boot simulation |
| IMG | 2048-bit RSA | HABv4 image signing | ARM boot simulation |

---

## UEFI Secure Boot Keys

### Platform Key (PK)

The Platform Key is the root of trust for UEFI Secure Boot:

- Only ONE PK can be installed
- PK owner can modify KEK
- Typically owned by hardware OEM

```bash
# Generate PK
openssl req -new -x509 -newkey rsa:2048 \
    -keyout PK.key -out PK.crt \
    -nodes -days 3650 \
    -subj "/CN=Photon OS Platform Key"

# Convert to DER (for UEFI enrollment)
openssl x509 -in PK.crt -outform DER -out PK.der
```

### Key Exchange Key (KEK)

KEK authorizes updates to db and dbx:

- Multiple KEKs can be installed
- KEK holders can add/remove entries from db/dbx
- Microsoft's KEK is on most consumer systems

```bash
# Generate KEK
openssl req -new -x509 -newkey rsa:2048 \
    -keyout KEK.key -out KEK.crt \
    -nodes -days 3650 \
    -subj "/CN=Photon OS Key Exchange Key"

openssl x509 -in KEK.crt -outform DER -out KEK.der
```

### Signature Database Key (DB)

DB key signs bootloaders and kernels:

- Multiple DB entries allowed
- Trusted binaries signed with DB key will boot
- Microsoft UEFI CA 2011 is in most systems' db

```bash
# Generate DB key
openssl req -new -x509 -newkey rsa:2048 \
    -keyout DB.key -out DB.crt \
    -nodes -days 3650 \
    -subj "/CN=Photon OS Signature Database Key"

openssl x509 -in DB.crt -outform DER -out DB.der
```

### Enrolling Custom UEFI Keys

For custom firmware or VMs where you control UEFI:

```bash
# Using efi-updatevar (requires UEFI shell access)
efi-updatevar -f PK.auth PK
efi-updatevar -a -f KEK.auth KEK
efi-updatevar -a -f DB.auth db
```

---

## Machine Owner Key (MOK)

### What is MOK?

MOK (Machine Owner Key) is a shim-specific mechanism:

- Stored in UEFI NVRAM (separate from db)
- Managed by shim, not UEFI firmware
- Allows users to add trusted keys without modifying db
- Requires physical presence to enroll

### MOK Generation

```bash
# Generate MOK key pair
openssl req -new -x509 -newkey rsa:2048 \
    -keyout MOK.key -out MOK.crt \
    -nodes -days 3650 \
    -subj "/CN=Photon OS Machine Owner Key"

# Convert to DER (required for enrollment)
openssl x509 -in MOK.crt -outform DER -out MOK.der
```

### Signing with MOK

```bash
# Sign an EFI binary
sbsign --key MOK.key --cert MOK.crt \
    --output signed.efi unsigned.efi

# Verify signature
sbverify --cert MOK.crt signed.efi

# List signatures
sbverify --list signed.efi
```

---

## Kernel Module Signing Key

### Purpose

The kernel module signing key:
- Signs all `.ko` modules during kernel build
- Public portion embedded in kernel
- Enables `CONFIG_MODULE_SIG_FORCE`

### Key Generation

```bash
# Generate long-lived key (100 years)
openssl req -new -x509 -newkey rsa:4096 \
    -keyout kernel_module_signing.pem \
    -out kernel_module_signing.pem \
    -nodes -days 36500 \
    -subj "/O=Photon OS Custom Build/CN=Kernel Module Signing Key/emailAddress=kernel@localhost"
```

### Kernel Configuration

In kernel `.config`:

```kconfig
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_SHA512=y
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
```

### Build Process Integration

The key must be in `certs/signing_key.pem` relative to kernel source:

```bash
# In linux.spec or build script
cp /root/hab_keys/kernel_module_signing.pem \
   $KERNEL_SOURCE/certs/signing_key.pem
```

### Verifying Module Signatures

```bash
# Check module signature info
modinfo module.ko | grep -E "sig|signer"

# Example output:
# sig_id:         PKCS#7
# signer:         Kernel Module Signing Key
# sig_key:        XX:XX:XX:XX:...
# sig_hashalgo:   sha512
```

---

## HABv4 Simulation Keys

### Super Root Key (SRK)

Root of trust for HABv4 (ARM secure boot simulation):

```bash
# Generate SRK (4096-bit for maximum security)
openssl genrsa -out srk.pem 4096
openssl rsa -in srk.pem -pubout -out srk_pub.pem

# Generate hash for eFuse simulation
openssl dgst -sha256 -binary srk_pub.pem > srk_hash.bin
```

### CSF and IMG Keys

```bash
# CSF Key (Command Sequence File)
openssl genrsa -out csf.pem 2048
openssl rsa -in csf.pem -pubout -out csf_pub.pem

# IMG Key (Image Signing)
openssl genrsa -out img.pem 2048
openssl rsa -in img.pem -pubout -out img_pub.pem
```

---

## Key Storage and Security

### Security Best Practices

| Key Type | Sensitivity | Recommended Storage |
|----------|-------------|---------------------|
| PK | Critical | HSM or offline |
| KEK | Critical | HSM or offline |
| DB | High | HSM or secure server |
| MOK | High | Secure server |
| Module Key | Medium | Build server (protected) |

### File Permissions

```bash
# Private keys: owner read only
chmod 400 *.key *.pem

# Certificates: readable
chmod 644 *.crt *.der

# Directory
chmod 700 /root/hab_keys
```

### Backup Strategy

1. **Never commit private keys to git**
2. Keep encrypted backups of key directory
3. Document key passphrases separately
4. Consider key escrow for critical keys

### Key Rotation

| Key | Typical Lifetime | Rotation Trigger |
|-----|------------------|------------------|
| PK | Hardware lifetime | Hardware compromise |
| KEK | 5-10 years | Policy change |
| DB | 3-5 years | Key compromise |
| MOK | 1-3 years | Periodic rotation |
| Module Key | Kernel version | Each kernel build |

---

## Key Generation Commands

### Quick Reference

```bash
# All-in-one key generation script
./hab_scripts/hab_keys.sh generate

# Individual commands:

# RSA key pair
openssl genrsa -out key.pem 2048

# Self-signed certificate
openssl req -new -x509 -key key.pem -out cert.crt \
    -days 3650 -subj "/CN=My Key"

# Combined key+cert in one file
openssl req -new -x509 -newkey rsa:2048 \
    -keyout combined.pem -out combined.pem \
    -nodes -days 3650 -subj "/CN=My Key"

# Extract public key
openssl rsa -in key.pem -pubout -out key_pub.pem

# Convert PEM to DER
openssl x509 -in cert.crt -outform DER -out cert.der

# View certificate
openssl x509 -in cert.crt -text -noout
```

---

## MOK Enrollment (Photon OS Approach)

### How It Works

We use **Fedora shim** (SBAT compliant) + **custom Photon OS GRUB stub** (MOK-signed). The Photon OS GRUB stub chainloads the VMware-signed GRUB real binary. User enrolls the Photon OS MOK certificate, which allows Fedora shim to trust the stub.

### First Boot: Enroll Photon OS MOK Certificate

On first boot, Fedora shim doesn't trust the Photon OS MOK signature yet, so MokManager appears automatically:

1. **Security Violation** error appears → Press any key
2. MokManager blue screen appears automatically (Fedora MokManager)
3. Select **"Enroll key from disk"**
4. Navigate to root `/`
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm enrollment and select **Reboot**
7. Photon OS GRUB stub now loads successfully (trusted via MOK signature)
8. Stub chainloads VMware GRUB real → kernel boots

**Note**: The certificate contains `CN=Photon OS Secure Boot MOK` which is our custom signing key.

### MokManager Built-in Options

MokManager provides all management functions (no separate GRUB menu entries needed):
- **Enroll key from disk** - Add certificate to MOK database
- **Enroll hash from disk** - Add binary hash (fallback if certs don't work)
- **Delete key** - Remove enrolled certificate
- **Delete hash** - Remove enrolled hash
- **Reboot** / **Power off**

### Alternative: Hash Enrollment

If certificate enrollment doesn't persist after reboot, try hash enrollment:

1. In MokManager, select **"Enroll hash from disk"**
2. Navigate to `EFI/BOOT/`
3. Select `grub.efi` (or `grubx64.efi`)
4. Confirm enrollment and reboot

This enrolls the binary hash instead of trusting a certificate, which works better on some firmwares.

### After Enrollment

After enrolling the Photon OS MOK certificate:
1. On reboot, the stub menu appears (5 second timeout)
2. Wait for timeout or select "Continue to Photon OS Installer"
3. Main menu appears with:
   - **"Install Photon OS (Custom)"** - VMware-signed kernel
   - **"Install Photon OS (VMware original)"** - VMware-signed kernel with verbose logging

**To Access MokManager After Enrollment**:
1. Reboot the system
2. During the 5-second stub menu, press any key
3. Select "MokManager - Enroll/Delete MOK Keys"

### Method 2: From Running Linux

```bash
# Import MOK (requires reboot)
sudo mokutil --import /path/to/MOK.der

# Enter one-time password when prompted
# Reboot - MokManager will appear
# Enter same password to confirm enrollment
```

### Method 3: From Boot Menu Rescue Shell

The ISO includes a rescue shell with mokutil pre-installed:

1. Boot from USB
2. Select **"MOK Management >"** → **"Rescue Shell"**
3. Run mokutil commands at the bash prompt:
   ```bash
   mokutil --list-enrolled    # List enrolled keys
   mokutil --export           # Export keys to files
   mokutil --delete key.der   # Schedule deletion
   reboot                     # Confirm in MokManager
   ```

### Method 4: Check and Manage MOK

```bash
# Check Secure Boot status
mokutil --sb-state

# List enrolled MOK keys
mokutil --list-enrolled

# List keys pending enrollment
mokutil --list-new

# Delete a MOK key (requires reboot)
mokutil --delete /path/to/MOK.der

# Reset all MOK keys
mokutil --reset
```

### MOK Enrollment Flow

```
mokutil --import MOK.der
         │
         ▼
    Set password
         │
         ▼
      Reboot
         │
         ▼
┌────────────────────────┐
│   MokManager appears   │
│   (blue screen)        │
└────────────────────────┘
         │
         ▼
  "Enroll MOK" option
         │
         ▼
    Enter password
         │
         ▼
   Confirm enrollment
         │
         ▼
      Reboot
         │
         ▼
  MOK key now trusted
```
