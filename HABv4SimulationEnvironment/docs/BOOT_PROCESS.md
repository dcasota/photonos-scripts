# UEFI Secure Boot Process

This document explains the complete boot process from UEFI firmware to running Photon OS.

## Table of Contents

1. [Overview](#overview)
2. [UEFI Firmware Phase](#uefi-firmware-phase)
3. [Shim Bootloader Phase](#shim-bootloader-phase)
4. [GRUB Bootloader Phase](#grub-bootloader-phase)
5. [Kernel Loading Phase](#kernel-loading-phase)
6. [Installation Phase](#installation-phase)
7. [Post-Installation Boot](#post-installation-boot)
8. [Trust Chain Summary](#trust-chain-summary)

---

## Overview

UEFI Secure Boot ensures only cryptographically signed code runs during boot. Each stage verifies the signature of the next before executing it:

```
UEFI Firmware → Shim → GRUB → Kernel → OS
```

Our modified boot chain maintains security while enabling custom kernels:

```
UEFI Firmware (Microsoft CA)
    ↓ verifies Microsoft signature ✓
SUSE Shim (Microsoft-signed)
    ↓ verifies MOK signature ✓
Custom GRUB (MOK-signed)
    ↓ loads kernel
Kernel (MOK-signed)
    ↓
Photon OS
```

---

## UEFI Firmware Phase

### What Happens

1. System powers on, UEFI firmware initializes
2. Firmware locates boot device (USB, disk)
3. Firmware finds `/EFI/BOOT/BOOTX64.EFI`
4. Firmware checks signature against key databases
5. If valid, firmware executes shim

### Key Databases

UEFI firmware maintains these key databases in NVRAM:

| Database | Contents | Purpose |
|----------|----------|---------|
| **PK** | Platform Key | Root of trust (OEM controlled) |
| **KEK** | Key Exchange Keys | Authorizes db/dbx updates |
| **db** | Allowed signatures | Trusted certificates/hashes |
| **dbx** | Forbidden signatures | Revoked certificates/hashes |

**Important**: Consumer systems have Microsoft's certificates in db:
- Microsoft Windows Production PCA 2011
- Microsoft Corporation UEFI CA 2011

Our SUSE shim is signed by "Microsoft Corporation UEFI CA 2011", so it passes verification on virtually all UEFI systems.

### SBAT (Secure Boot Advanced Targeting)

Microsoft uses SBAT to revoke vulnerable bootloaders without revoking their certificate. Current requirement:

```
Minimum SBAT: shim,4
Our shim: shim,4 ✓ (compliant)
```

If shim SBAT version is below the minimum, you get: "SBAT self-check failed: Security Policy Violation"

---

## Shim Bootloader Phase

### What is Shim?

Shim is a first-stage bootloader that:
1. Is signed by Microsoft (trusted by UEFI)
2. Maintains its own trust database (MokList)
3. Loads and verifies the next-stage loader (GRUB)
4. Provides MOK enrollment UI (MokManager)

### Our Shim: SUSE from Ventoy

| Property | Value |
|----------|-------|
| Source | Ventoy 1.1.10 |
| Signer | Microsoft Corporation UEFI CA 2011 |
| SBAT | shim,4 (compliant) |
| Embedded CA | SUSE Linux Enterprise Secure Boot CA |

### What Shim Verifies

Shim checks the next-stage loader (GRUB) against:

1. **Embedded vendor certificate** (SUSE CA) - we don't use this
2. **MokList** (Machine Owner Keys) - **this is what we use**
3. **UEFI db** (optional fallback)

Since our GRUB is signed with MOK, and the user enrolls our MOK certificate, shim accepts it.

### MokList Enrollment

On first boot, shim sees an unknown GRUB signature and:

1. Displays "Verification failed: Security Violation"
2. Offers to launch MokManager
3. User enrolls our MOK certificate
4. Certificate is stored in MokList (NVRAM)
5. Subsequent boots: shim verifies GRUB against MokList ✓

### MokManager Locations

SUSE shim looks for MokManager at these paths (in order):
1. `\MokManager.efi` (root of EFI partition) - **primary**
2. `\EFI\BOOT\MokManager.efi` - fallback

We place MokManager at both locations for reliability.

---

## GRUB Bootloader Phase

### Why Custom GRUB?

VMware's GRUB includes the `shim_lock` module which:
1. Registers with shim as a verification protocol
2. Calls shim's `Verify()` for every binary loaded
3. Rejects kernels not signed with shim-trusted keys

Our custom GRUB:
1. Is built without `shim_lock` module
2. Doesn't call shim's `Verify()` for kernel
3. Loads any kernel (we sign ours with MOK for integrity)

### GRUB Build

```bash
grub2-mkimage \
    --format=x86_64-efi \
    --output=grub.efi \
    --prefix=/boot/grub2 \
    --sbat=sbat.csv \
    --disable-shim-lock \
    <modules>
```

Key flag: `--disable-shim-lock` excludes the shim_lock verifier.

### GRUB Signing

```bash
sbsign --key MOK.key --cert MOK.crt \
    --output grub-signed.efi grub.efi
```

Shim verifies this signature against MokList before executing.

### Boot Menu

Our GRUB displays a themed menu with 6 options:

```
╔══════════════════════════════════════════════════════════════╗
║              VMware Photon OS 5.0 Installer                  ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  1. Install (Custom MOK) - For Physical Hardware   [default] ║
║  2. Install (VMware Original) - For VMware VMs               ║
║  3. MokManager - Enroll/Delete MOK Keys                      ║
║  4. Reboot into UEFI Firmware Settings                       ║
║  5. Reboot                                                   ║
║  6. Shutdown                                                 ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

### Menu Option Details

**Option 1: Install (Custom MOK)**
```
linux ($root)/isolinux/vmlinuz \
    photon.media=LABEL=$isolabel \
    ks=cdrom:/mok_ks.cfg
initrd ($root)/isolinux/initrd.img
```
- Uses MOK-signed kernel
- Kickstart installs MOK packages
- For physical hardware with Secure Boot

**Option 2: Install (VMware Original)**
```
chainloader /EFI/BOOT/grubx64_real.efi
```
- Chainloads VMware's original GRUB
- Kickstart installs standard packages
- For VMware VMs (no Secure Boot verification)

**Option 3: MokManager**
```
chainloader /EFI/BOOT/MokManager.efi
```
- Launches SUSE MokManager
- Enroll/delete MOK certificates
- Manage MOK database

**Option 4: UEFI Firmware Settings**
```
fwsetup
```
- Reboots into UEFI/BIOS setup

**Option 5/6: Reboot/Shutdown**
```
reboot / halt
```

---

## Kernel Loading Phase

### What GRUB Does

1. Loads vmlinuz into memory
2. Loads initrd.img
3. Passes kernel command line
4. Transfers control to kernel

### Kernel Command Line

```
photon.media=LABEL=PHOTON_20250125 ks=cdrom:/mok_ks.cfg
```

- `photon.media`: How installer finds ISO filesystem
- `ks`: Kickstart configuration file location

### Kernel Signature

Our kernel is signed with MOK:
```bash
sbsign --key MOK.key --cert MOK.crt \
    --output vmlinuz-signed vmlinuz
```

Note: Since our GRUB doesn't have `shim_lock`, the kernel signature isn't verified at boot time. However:
- The signature provides integrity verification
- Can be verified manually with `sbverify`
- Matches the MOK certificate enrolled by user

---

## Installation Phase

### Kickstart Processing

The Photon OS installer reads the kickstart file and:

1. Parses JSON configuration
2. Sets `linux_flavor` (which kernel to install)
3. Sets `packages` (which packages to install)
4. Sets `bootmode` (efi)
5. Sets `ui` to true (interactive mode)

### Package Installation

**MOK Kickstart (`mok_ks.cfg`):**
```json
{
    "linux_flavor": "linux-mok",
    "packages": ["minimal", "initramfs", "linux-mok", 
                 "grub2-efi-image-mok", "shim-signed-mok"]
}
```

Installs:
- `linux-mok`: MOK-signed kernel
- `grub2-efi-image-mok`: Custom GRUB stub
- `shim-signed-mok`: SUSE shim + MokManager

**Standard Kickstart (`standard_ks.cfg`):**
```json
{
    "linux_flavor": "linux",
    "packages": ["minimal", "initramfs", "linux", 
                 "grub2-efi-image", "shim-signed"]
}
```

Installs original VMware packages.

### Interactive Installation

Despite using kickstart, installation is interactive (`"ui": true`):
- User selects disk
- User sets hostname
- User sets root password
- Package selection is enforced by kickstart

---

## Post-Installation Boot

### MOK Installation Path

After installing with "Custom MOK" option:

```
UEFI Firmware
    ↓ verifies (Microsoft CA) ✓
/boot/efi/EFI/BOOT/bootx64.efi (SUSE shim from shim-signed-mok)
    ↓ verifies (MokList) ✓
/boot/efi/EFI/BOOT/grubx64.efi (Custom GRUB from grub2-efi-image-mok)
    ↓
/boot/vmlinuz-* (MOK-signed from linux-mok)
    ↓
Photon OS running ✓
```

### Standard Installation Path

After installing with "VMware Original" option:

```
UEFI Firmware
    ↓ verifies (Microsoft CA) ✓
/boot/efi/EFI/BOOT/bootx64.efi (VMware shim from shim-signed)
    ↓ shim_lock verification
/boot/efi/EFI/BOOT/grubx64.efi (VMware GRUB from grub2-efi-image)
    ↓ shim_lock calls Verify()
/boot/vmlinuz-* (unsigned from linux)
    ↓
⚠ On physical hardware with Secure Boot: "bad shim signature" ERROR
✓ In VMware VMs: Works (no real Secure Boot)
```

---

## Trust Chain Summary

### ISO Boot (First Time)

| Stage | Binary | Signer | Verified By |
|-------|--------|--------|-------------|
| 1 | BOOTX64.EFI (SUSE shim) | Microsoft | UEFI Firmware (db) |
| 2 | grub.efi (Custom GRUB) | Photon OS MOK | Shim (MokList) |
| 3 | vmlinuz | Photon OS MOK | Not verified (no shim_lock) |

### Installed System Boot (MOK Path)

| Stage | Binary | Signer | Verified By |
|-------|--------|--------|-------------|
| 1 | bootx64.efi (SUSE shim) | Microsoft | UEFI Firmware (db) |
| 2 | grubx64.efi (Custom GRUB) | Photon OS MOK | Shim (MokList) |
| 3 | vmlinuz-* | Photon OS MOK | Not verified (no shim_lock) |

### Security Properties

| Property | Status |
|----------|--------|
| Firmware to shim verification | ✓ Microsoft signature |
| Shim to GRUB verification | ✓ MOK signature |
| GRUB to kernel verification | ✗ Disabled (no shim_lock) |
| Kernel integrity | ✓ Signed with MOK (verifiable) |
| Physical presence for MOK enrollment | ✓ Required |

### Comparison to Other Distributions

| Distribution | Shim Signer | GRUB Verification | Kernel Verification |
|--------------|-------------|-------------------|---------------------|
| Ubuntu | Microsoft | MOK | Disabled (by default) |
| Fedora | Microsoft | Fedora CA | shim_lock |
| RHEL | Microsoft | Red Hat CA | shim_lock |
| **Our Photon** | Microsoft | MOK | Disabled |

Most distributions disable kernel verification for practical reasons. We follow the same model as Ubuntu.
