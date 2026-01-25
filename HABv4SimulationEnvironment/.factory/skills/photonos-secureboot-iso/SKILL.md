---
name: photonos-secureboot-iso
description: |
  Create UEFI Secure Boot enabled Photon OS ISOs for physical hardware.
  Handles MOK enrollment, custom GRUB stub, RPM signing, and kickstart installation.
  Use when building bootable ISOs for laptops/servers with Secure Boot enabled.
---

# PhotonOS HABv4 Secure Boot ISO Creation Skill

## Overview

This skill covers creating Secure Boot enabled ISOs for Photon OS that work on consumer laptops and servers with UEFI Secure Boot enabled. The tool creates modified ISOs using:

- **SUSE shim** (Microsoft-signed, SBAT compliant)
- **Custom GRUB stub** (MOK-signed, without `shim_lock`)
- **MOK-signed kernel and packages**
- **Kickstart-based installation** for reliable package selection

## The Problem We Solve

**Original Photon OS ISOs fail on Secure Boot enabled hardware** because:
1. VMware's shim has `shim_lock` that rejects custom/unsigned kernels
2. The kernel isn't signed with a key in MokList
3. Installed packages use VMware's signing, not user-controlled keys

**Our solution:**
1. Replace VMware shim with Microsoft-signed SUSE shim
2. Build custom GRUB stub without `shim_lock`, sign with MOK
3. Sign kernel with MOK
4. Create `-mok` variant RPM packages for installed system

## Quick Reference

### Build Commands

```bash
# Build Secure Boot ISO (simplest - does everything)
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build for specific release
./PhotonOS-HABv4Emulation-ISOCreator --release 6.0 --build-iso

# Build with RPM signing (compliance: NIST 800-53, FedRAMP, EU CRA)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# Build with eFuse USB verification
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --efuse-usb --create-efuse-usb=/dev/sdX -y

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-b`, `--build-iso` | Build Secure Boot ISO |
| `-r`, `--release=VERSION` | Photon OS version: 4.0, 5.0, 6.0 (default: 5.0) |
| `-D`, `--diagnose=ISO` | Diagnose existing ISO |
| `-E`, `--efuse-usb` | Enable eFuse USB verification |
| `-u`, `--create-efuse-usb=DEV` | Create eFuse USB dongle |
| `-R`, `--rpm-signing` | Enable GPG signing of MOK RPMs |
| `-F`, `--full-kernel-build` | Build kernel from source |
| `-c`, `--clean` | Clean all artifacts |
| `-v`, `--verbose` | Verbose output |
| `-y`, `--yes` | Auto-confirm destructive operations |

## Architecture

### Boot Chain (ISO Boot)

```
UEFI Firmware (Microsoft UEFI CA in db)
    ↓ verifies Microsoft signature
BOOTX64.EFI (SUSE shim, SBAT=shim,4)
    ↓ verifies against MokList
grub.efi (Custom GRUB stub, MOK-signed, NO shim_lock)
    ↓ loads grub.cfg with themed menu (5 sec timeout)
    │
    ├─→ "Install (Custom MOK)" → ks=cdrom:/mok_ks.cfg
    │   → Installs: linux-mok, grub2-efi-image-mok, shim-signed-mok
    │
    └─→ "Install (VMware Original)" → ks=cdrom:/standard_ks.cfg
        → Installs: linux, grub2-efi-image, shim-signed
```

### Boot Chain (Installed System - MOK Path)

```
UEFI Firmware → shim-signed-mok (SUSE shim + MokManager)
             → grub2-efi-image-mok (Custom GRUB stub, MOK-signed)
             → linux-mok (vmlinuz, MOK-signed)
             ✓ Works on physical hardware with Secure Boot
```

### Why Custom GRUB Stub Without shim_lock

VMware's GRUB includes the `shim_lock` verifier module which calls shim's `Verify()` for kernel loading. While MOK-signed kernels should be accepted (certificate in MokList), we build a custom stub without `shim_lock` to ensure compatibility and provide predictable behavior.

The custom stub:
1. Is verified by shim via MOK signature (chain maintained)
2. Excludes `shim_lock` (no unpredictable kernel verification)
3. Contains SBAT metadata (passes shim policy check)
4. Includes modules for theming: `probe`, `gfxmenu`, `png`, `jpeg`, `tga`

## RPM Secure Boot Patcher

The tool includes an integrated RPM patcher that creates MOK-signed variant packages:

| Original Package | MOK Package | Contents |
|-----------------|-------------|----------|
| `shim-signed` | `shim-signed-mok` | SUSE shim (Microsoft-signed) + MokManager |
| `grub2-efi-image` | `grub2-efi-image-mok` | Custom GRUB stub (MOK-signed, no shim_lock) |
| `linux` / `linux-esx` | `linux-mok` | MOK-signed vmlinuz + boot files |

### Package Discovery (Version-Agnostic)

The patcher discovers packages by file paths, not version numbers:
- `grub2-efi-image`: provides `/boot/efi/EFI/BOOT/grubx64.efi`
- `linux`: provides `/boot/vmlinuz-*`
- `shim-signed`: provides `/boot/efi/EFI/BOOT/bootx64.efi`

### SPEC File Generation

Generated specs include:
- Proper `Provides:` (same capability as original)
- `Conflicts:` (prevents installing both)
- MOK-signed binaries
- MokManager in `shim-signed-mok`

## Kickstart-Based Installation

The ISO uses **kickstart configuration files** instead of initrd patching:

### `/mok_ks.cfg` (MOK Installation)
```json
{
    "linux_flavor": "linux-mok",
    "packages": ["minimal", "initramfs", "linux-mok", "grub2-efi-image-mok", "shim-signed-mok"],
    "bootmode": "efi",
    "ui": true
}
```

### `/standard_ks.cfg` (VMware Installation)
```json
{
    "linux_flavor": "linux",
    "packages": ["minimal", "initramfs", "linux", "grub2-efi-image", "shim-signed"],
    "bootmode": "efi",
    "ui": true
}
```

The `"ui": true` makes the installer **interactive** while **enforcing package selection**.

### Why Kickstart Instead of Initrd Patching

Previous versions patched the installer in initrd. This had risks:
- **Version fragility**: sed patterns could break with updates
- **Python path hardcoding**: `/usr/lib/python3.11/` may change
- **Maintenance burden**: each version needed testing

Kickstart approach is:
- **Version-independent**: works with any photon-os-installer
- **VMware-supported**: uses official mechanism
- **Robust**: no fragile patching

## Kernel Build Support

The `--full-kernel-build` option builds kernels from Photon OS sources:

### Directory Structure Supported

| Release | Kernel Source | Config Location |
|---------|--------------|-----------------|
| 4.0 | `/root/4.0/stage/SOURCES/linux-*.tar.xz` | `/root/4.0/SPECS/linux/` |
| 5.0 | `/root/5.0/stage/SOURCES/linux-6.1.*.tar.xz` | `/root/5.0/SPECS/linux/` or `/root/common/SPECS/linux/v6.1/` |
| 6.0 | `/root/6.0/stage/SOURCES/linux-6.12.*.tar.xz` | `/root/common/SPECS/linux/v6.12/` |

### Build Process

1. Auto-detect kernel tarball from `SOURCES/`
2. Extract to `{photon_dir}/kernel-build/linux-{version}/`
3. Apply Photon config (`config-esx_{arch}` preferred for VMs)
4. Configure Secure Boot options:
   - `CONFIG_MODULE_SIG=y`
   - `CONFIG_MODULE_SIG_ALL=y`
   - `CONFIG_MODULE_SIG_SHA512=y`
   - `CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y`
5. Build kernel and modules
6. Sign kernel with MOK key
7. Output to `{keys_dir}/vmlinuz-mok`

## RPM Signing (Optional)

The `--rpm-signing` option enables GPG signing for compliance:

### Compliance Standards Supported

- **NIST SP 800-53**: SI-7 (Software Integrity), CM-14 (Signed Components)
- **FedRAMP**: Requires NIST 800-53 controls
- **EU Cyber Resilience Act**: Article 10 (Software integrity verification)

### Process

1. Generate GPG key pair (`RPM-GPG-KEY-habv4`)
2. Sign all MOK RPMs with `rpmsign`
3. Copy public key to ISO and eFuse USB
4. Import key in kickstart postinstall

### Verification

```bash
rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
rpm -qa *-mok* --qf '%{NAME}\t%{SIGPGP:pgpsig}\n'
```

## eFuse USB Mode

When built with `-E`, boot requires an eFuse USB dongle (label: `EFUSE_SIM`):

```
GRUB Stub
    ↓
Search for USB with LABEL=EFUSE_SIM
    ↓
Check for /efuse_sim/srk_fuse.bin
    ├─→ Valid: Show boot menu
    └─→ Invalid: "BOOT BLOCKED" (only Retry/Reboot)
```

### USB Contents

```
USB (FAT32, LABEL=EFUSE_SIM)
└── efuse_sim/
    ├── srk_fuse.bin          # SRK hash (32 bytes)
    ├── sec_config.bin        # Security mode
    └── efuse_config.json     # Configuration
```

## First Boot Procedure

### Step 1: Write USB
```bash
dd if=photon-5.0-secureboot.iso of=/dev/sdX bs=4M status=progress
sync
```

### Step 2: BIOS Configuration
1. Disable CSM/Legacy boot completely
2. Enable Secure Boot
3. Set USB as first boot device

### Step 3: Enroll MOK (First Boot)
1. **Blue MokManager screen** appears (not laptop's security dialog)
2. Select "Enroll key from disk"
3. Navigate to root `/`
4. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
5. Confirm and select "Reboot"

### Step 4: Install (Second Boot)
1. Themed menu appears
2. Select "Install (Custom MOK) - For Physical Hardware"
3. Complete interactive installation
4. Reboot into installed system

## Troubleshooting Quick Reference

| Error | Cause | Fix |
|-------|-------|-----|
| "bad shim signature" | Selected VMware Original | Select Custom MOK |
| Laptop security dialog (not blue MokManager) | CSM enabled | Disable CSM in BIOS |
| Enrollment doesn't persist | Wrong MokManager | Rebuild ISO |
| "Policy Violation" | GRUB SBAT issue | Use latest version |
| grub> prompt | Config not found | Rebuild ISO |
| BOOT BLOCKED | eFuse USB missing | Insert eFuse USB or rebuild without `-E` |
| Installed system fails | Standard packages installed | Reinstall with "Custom MOK" |

### Detailed Troubleshooting

**Laptop shows gray/red security dialog instead of blue MokManager:**
- This means CSM/Legacy boot is enabled
- The laptop's firmware is handling the violation, not shim's MokManager
- Fix: Disable CSM completely, enable pure UEFI mode

**MOK enrollment appears to succeed but doesn't persist:**
- The wrong MokManager is being used (laptop's built-in)
- SUSE shim looks for MokManager at `\MokManager.efi` (root)
- Fix: Rebuild ISO with latest version (places MokManager correctly)

**Installed system gets "bad shim signature":**
- Standard VMware packages were installed (have shim_lock)
- Fix: Reinstall using "Install (Custom MOK)" menu option

## ISO Structure

```
ISO Root/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer    # MOK certificate
├── MokManager.efi                        # SUSE MokManager
├── mok_ks.cfg                           # MOK kickstart
├── standard_ks.cfg                      # Standard kickstart
├── EFI/BOOT/
│   ├── BOOTX64.EFI                      # SUSE shim
│   ├── grub.efi                         # Custom GRUB stub
│   ├── grubx64.efi                      # Same as grub.efi
│   ├── grubx64_real.efi                 # VMware GRUB (for standard path)
│   └── MokManager.efi                   # Backup
├── boot/grub2/
│   ├── efiboot.img                      # EFI System Partition
│   └── grub.cfg                         # Boot menu
├── RPMS/x86_64/                         # Original + MOK RPMs
└── isolinux/                            # BIOS boot (legacy)
    ├── vmlinuz                          # MOK-signed kernel
    └── initrd.img
```

## Key Locations

```
/root/hab_keys/
├── MOK.key / MOK.crt / MOK.der          # Machine Owner Key
├── kernel_module_signing.pem             # Kernel module signing key
├── shim-suse.efi                        # SUSE shim (embedded)
├── MokManager-suse.efi                  # SUSE MokManager (embedded)
├── grub-photon-stub.efi                 # Custom GRUB stub (MOK-signed)
├── vmlinuz-mok                          # MOK-signed kernel
└── RPM-GPG-KEY-habv4                    # GPG public key (if --rpm-signing)
```

## GRUB Modules Included

Essential modules in custom GRUB stub:
- `probe` - UUID detection for `photon.media=UUID=$photondisk`
- `gfxmenu` - Themed menus
- `png`, `jpeg`, `tga` - Background images
- `gfxterm_background` - Graphics background
- `search`, `configfile`, `linux`, `initrd` - Core boot
- `chain`, `fat`, `iso9660`, `part_gpt` - Filesystem/chainload

## Embedded Components

SUSE shim components are embedded in `data/`:
- `shim-suse.efi.gz` - SUSE shim (Microsoft-signed, SBAT=shim,4)
- `MokManager-suse.efi.gz` - SUSE MokManager

Extracted automatically during build. No internet required.

## Installer Patch (Progress Bar Fix)

The photon-os-installer has a bug where `exit_gracefully()` assumes `progress_bar` exists. When kickstart uses `"ui": true`, this can cause `AttributeError` if curses init fails.

The tool applies a surgical fix to `installer.py` in the initrd:
1. Initialize `self.progress_bar = None` in `__init__()`
2. Check for None in `exit_gracefully()` before accessing

This fix has been submitted upstream as PR #39.

## For Developers Using This Skill

### What I Can Help With

1. **Building ISOs**: Run build commands, diagnose failures
2. **Understanding architecture**: Explain boot chains, signing, verification
3. **Modifying code**: Add features, fix bugs, update documentation
4. **Troubleshooting**: Analyze errors, identify root causes
5. **Compliance**: Explain requirements, implement signing

### Example Interactions

**Build an ISO:**
```
User: Build a Secure Boot ISO for Photon OS 5.0
[I'll run the build command and report results]
```

**Diagnose issues:**
```
User: My ISO gets "bad shim signature" on my laptop
[I'll explain the cause and provide step-by-step fix]
```

**Modify the tool:**
```
User: Add support for custom GRUB themes
[I'll analyze the code, propose changes, implement and test]
```

**Understand the code:**
```
User: How does the RPM patcher work?
[I'll explain the architecture with code references]
```

See [docs/DROID_SKILL_GUIDE.md](../../../docs/DROID_SKILL_GUIDE.md) for complete developer guide.
