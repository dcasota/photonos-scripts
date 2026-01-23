---
name: photonos-secureboot-iso
description: |
  Create UEFI Secure Boot enabled Photon OS ISOs compatible with consumer laptops.
  Handles custom GRUB stub (without shim_lock), MOK enrollment, and MBR/UEFI hybrid boot.
  Use when building bootable ISOs for physical hardware with Secure Boot enabled.
---

# PhotonOS HABv4 Secure Boot ISO Creation Skill

## Overview

This skill covers creating Secure Boot enabled ISOs for Photon OS that work on consumer laptops with UEFI Secure Boot enabled. It uses a **custom GRUB stub** built with `grub2-mkimage` that excludes the `shim_lock` module, combined with a MOK-signed kernel.

## Prerequisites

- Photon OS build environment
- Required packages: `xorriso`, `sbsigntools`, `dosfstools`, `grub2-efi`, `sfdisk`
- SUSE shim components (embedded in repository, auto-extracted)

## Quick Start

```bash
# Build Secure Boot ISO (simplest - does everything automatically)
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build ISO with eFuse USB dongle (auto-confirm with -y)
./PhotonOS-HABv4Emulation-ISOCreator --release 5.0 --build-iso --setup-efuse --create-efuse-usb=/dev/sdX -y

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

## Architecture

### Boot Modes Supported

| Mode | Bootloader | Secure Boot | Notes |
|------|------------|-------------|-------|
| UEFI x64 | BOOTX64.EFI (shim) | Yes | Primary target |
| UEFI IA32 | BOOTIA32.EFI (shim) | Yes | Rare 32-bit UEFI |
| BIOS/Legacy | isolinux | No | MBR fallback |

### UEFI Secure Boot Chain

```
UEFI Firmware (Microsoft UEFI CA in db)
    ↓ verifies Microsoft signature
BOOTX64.EFI (SUSE shim, SBAT=shim,4)
    ↓ verifies MOK signature
grub.efi (Custom GRUB stub, MOK-signed, NO shim_lock)
    ↓ loads modified /boot/grub2/grub.cfg
    ↓ presents 6-option themed menu (5 sec timeout)
    │
    ├─→ "Install (Custom MOK)" path:
    │   linux vmlinuz (MOK-signed) + initrd + photon.secureboot=mok
    │   → Installs MOK-signed RPM packages to target system
    │
    └─→ "Install (VMware Original)" path:
        chainloader grubx64_real.efi
        → VMware's GRUB → original unsigned RPMs installed
```

### Installed System Boot (Post-Installation)

For "Install (Custom MOK)":
```
UEFI Firmware → shim-signed-mok (bootx64.efi + mmx64.efi)
             → grub2-efi-image-mok (grubx64.efi, MOK-signed)
             → linux-mok (vmlinuz, MOK-signed)
```

For "Install (VMware Original)":
```
UEFI Firmware → shim-signed (bootx64.efi, VMware vendor cert)
             → grub2-efi-image (grubx64.efi, unsigned)
             → linux (vmlinuz, unsigned)
             ⚠ Will fail on Secure Boot enabled systems
```

## GRUB Modules

The custom GRUB stub includes these modules for proper theming and functionality:
- `probe` - Required for UUID detection (`photon.media=UUID=$photondisk`)
- `gfxmenu` - Required for themed menus
- `png`, `jpeg`, `tga` - Required for background images  
- `gfxterm_background` - Graphics terminal background support

## Why Custom GRUB Stub Without shim_lock

VMware's GRUB includes the `shim_lock` verifier module which calls shim's `Verify()` for kernel loading. While our MOK-signed kernel should be accepted (the certificate is in MokList), we build a custom stub without `shim_lock` to ensure compatibility across different firmware implementations and to provide a fallback path.

The custom stub is still verified by shim via MOK signature, maintaining the secure boot chain up to GRUB.

## Menu Options (Themed, 5 Second Timeout)

The modified `/boot/grub2/grub.cfg` displays a themed menu with Photon OS background:

```
1. Install (Custom MOK)                                      [default]
   → linux vmlinuz (MOK-signed) + initrd
   → Boots the installer with MOK-signed kernel
   
2. Install (VMware Original) - Will fail without VMware signature
   → chainloader /EFI/BOOT/grubx64_real.efi
   → VMware's GRUB with shim_lock (kernel verification fails)
   
3. MokManager - Enroll/Delete MOK Keys
   → chainloader /EFI/BOOT/MokManager.efi
   
4. Reboot into UEFI Firmware Settings
   → fwsetup
   
5. Reboot
   → reboot
   
6. Shutdown
   → halt
```

## eFuse USB Mode

When built with `-E` flag, the ISO requires an eFuse USB dongle (label: `EFUSE_SIM`) to boot:

```bash
# Build ISO with eFuse verification
PhotonOS-HABv4Emulation-ISOCreator -E -b

# Create eFuse USB dongle
PhotonOS-HABv4Emulation-ISOCreator -u /dev/sdX
```

Without the eFuse USB dongle present, the boot will show:
```
=========================================
  HABv4 SECURITY: eFuse USB Required
=========================================

Insert eFuse USB dongle (label: EFUSE_SIM)
and select 'Retry' to continue.
```

## RPM Secure Boot Patcher

The ISO creator includes an integrated **RPM Secure Boot Patcher** that automatically:

1. **Discovers** relevant boot packages (version-agnostic, by file paths):
   - `grub2-efi-image` (provides `/boot/efi/EFI/BOOT/grubx64.efi`)
   - `linux` (provides `/boot/vmlinuz-*`)
   - `shim-signed` (provides `/boot/efi/EFI/BOOT/bootx64.efi`)
   - `shim` (provides MokManager source)

2. **Generates** MOK-signed variant SPEC files:
   - `grub2-efi-image-mok.spec`
   - `linux-mok.spec`
   - `shim-signed-mok.spec`

3. **Builds** MOK-signed RPMs that:
   - Have `-mok` suffix (e.g., `grub2-efi-image-mok`)
   - Provide same capabilities as originals (`Provides: grub2-efi-image`)
   - Conflict with originals (`Conflicts: grub2-efi-image`)
   - Include MokManager (`mmx64.efi`) in `shim-signed-mok`

4. **Integrates** both original and MOK-signed RPMs into the ISO

### MOK Package Contents

| Package | Files | Signed With |
|---------|-------|-------------|
| `grub2-efi-image-mok` | `/boot/efi/EFI/BOOT/grubx64.efi` | MOK key |
| `linux-mok` | `/boot/vmlinuz-*`, `/boot/*` | MOK key |
| `shim-signed-mok` | `bootx64.efi`, `revocations.efi`, `mmx64.efi` | MOK key (mmx64 only) |

### How Installation Selection Works

The kernel command line parameter `photon.secureboot=mok` tells the installer which package set to use:

- **"Install (Custom MOK)"**: Passes `photon.secureboot=mok` → MOK-signed packages installed
- **"Install (VMware Original)"**: No parameter → Original unsigned packages installed

### Initrd Patching

The ISO creator automatically patches the installer in the initrd to:

1. **Add `mok_patch.py`** module to the photon_installer package
2. **Patch `installer.py`** to import and call `apply_mok_substitution()`
3. **Repack the initrd** with the patched installer

The patch:
```python
# Added after 'import tdnf'
try:
    from mok_patch import apply_mok_substitution
except ImportError:
    apply_mok_substitution = lambda p, l=None: p

# Modified package assignment
install_config['packages'] = apply_mok_substitution(packages_pruned, logger)
```

When `photon.secureboot=mok` is detected in `/proc/cmdline`, the function automatically substitutes:
- `linux` → `linux-mok`
- `grub2-efi-image` → `grub2-efi-image-mok`
- `shim-signed` → `shim-signed-mok`

## Tool Usage

### Command Line Options

```
Usage: PhotonOS-HABv4Emulation-ISOCreator [OPTIONS]

Options:
  -r, --release=VERSION      Photon OS release: 4.0, 5.0, 6.0 (default: 5.0)
  -i, --input=ISO            Input ISO file (default: auto-detect)
  -o, --output=ISO           Output ISO file (default: <input>-secureboot.iso)
  -k, --keys-dir=DIR         Keys directory (default: /root/hab_keys)
  -e, --efuse-dir=DIR        eFuse directory (default: /root/efuse_sim)
  -m, --mok-days=DAYS        MOK certificate validity in days (default: 180)
  -b, --build-iso            Build Secure Boot ISO
  -g, --generate-keys        Generate cryptographic keys
  -s, --setup-efuse          Setup eFuse simulation
  -u, --create-efuse-usb=DEV Create eFuse USB dongle on device
  -E, --efuse-usb            Enable eFuse USB verification in GRUB
  -F, --full-kernel-build    Build kernel from source (takes hours)
  -D, --diagnose=ISO         Diagnose an existing ISO for Secure Boot issues
  -c, --clean                Clean up all artifacts
  -v, --verbose              Verbose output
  -y, --yes                  Auto-confirm destructive operations (e.g., erase USB)
  -h, --help                 Show help
```

### Examples

```bash
# Generate keys and build ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build ISO for Photon OS 4.0
./PhotonOS-HABv4Emulation-ISOCreator --release 4.0 --build-iso

# Build ISO with eFuse USB dongle (auto-confirm)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --setup-efuse --create-efuse-usb=/dev/sdd -y

# Build ISO with eFuse verification enabled
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --efuse-usb

# Diagnose why an ISO isn't booting
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/photon.iso

# Clean up all generated artifacts
./PhotonOS-HABv4Emulation-ISOCreator -c
```

### Embedded Components

SUSE shim components are embedded in the repository at `data/`:
- `shim-suse.efi.gz` - SUSE shim (Microsoft-signed)
- `MokManager-suse.efi.gz` - MOK Manager

These are automatically extracted when building an ISO. No manual download required.

## Required ISO Structure

```
ISO Root/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer    # MOK certificate for enrollment
├── MokManager.efi                        # SUSE MokManager at root
├── EFI/BOOT/
│   ├── BOOTX64.EFI                       # SUSE shim (Microsoft-signed)
│   ├── grub.efi                          # Custom GRUB stub (MOK-signed)
│   ├── grubx64.efi                       # Same as grub.efi
│   ├── grubx64_real.efi                  # VMware's GRUB (for Original option)
│   └── MokManager.efi                    # MOK enrollment UI
├── boot/grub2/
│   ├── efiboot.img                       # EFI System Partition image
│   ├── grub.cfg                          # VMware's original menu
│   └── grub-custom.cfg                   # Custom MOK menu
└── isolinux/                             # BIOS/MBR boot support
    ├── vmlinuz                           # MOK-signed kernel
    └── initrd.img
```

## First Boot Procedure

### Step 1: Prepare USB

```bash
dd if=photon-5.0-secureboot.iso of=/dev/sdX bs=4M status=progress
sync
```

### Step 2: Configure Laptop BIOS

1. Enter BIOS setup (F2, F12, Del, Esc during boot)
2. **Disable CSM/Legacy boot completely**
3. **Enable Secure Boot**
4. Set USB as first boot device
5. Save and exit

### Step 3: Boot and Enroll MOK

1. Boot from USB
2. **EXPECT**: Blue MokManager screen (shim's Security Violation)
   - If laptop's dialog appears → disable CSM in BIOS
3. Select **"Enroll key from disk"**
4. Navigate to USB root
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm and select **"Reboot"** (NOT Continue)

### Step 4: Boot to Installer

After reboot:
1. Themed Photon OS menu appears (5 second timeout) with background picture
2. 6 menu options are displayed:
   - Install (Custom MOK) [default]
   - Install (VMware Original) - Will fail
   - MokManager - Enroll/Delete MOK Keys
   - Reboot into UEFI Firmware Settings
   - Reboot
   - Shutdown
3. Select **"Install (Custom MOK)"** to begin installation with MOK-signed kernel

## Troubleshooting

### Installed System: "Policy Violation" then "bad shim signature"

**Cause**: The installed Photon OS uses original VMware RPMs which are unsigned:
- `grub2-efi-image` provides unsigned `grubx64.efi` → Policy Violation
- `linux` provides unsigned `vmlinuz` → bad shim signature

**Solution**: 
1. Reinstall using **"Install (Custom MOK)"** menu option
2. This installs MOK-signed packages: `grub2-efi-image-mok`, `linux-mok`, `shim-signed-mok`

### Installed System: Missing MokManager

**Cause**: Original `shim-signed` package doesn't include MokManager (`mmx64.efi`).

**Solution**: Use `shim-signed-mok` which includes MokManager.

### "bad shim signature" Error During Live Boot

**Cause**: Selected "VMware Original" which uses VMware's GRUB with shim_lock.

**Solution**: Reboot and select **"Install (Custom MOK)"** option instead.

### Drops to grub> Prompt

**Manual boot** at grub> prompt:
```
grub> search --no-floppy --file --set=root /isolinux/isolinux.cfg
grub> configfile ($root)/boot/grub2/grub.cfg
```

### Laptop Shows Security Dialog Instead of Blue MokManager

**Cause**: CSM/Legacy boot is enabled.

**Solution**: Disable CSM/Legacy completely in BIOS, enable pure UEFI mode.

### RPM Build Fails During ISO Creation

**Cause**: Missing build dependencies or incorrect SPECS directory.

**Check**:
1. Verify `/root/<release>/SPECS` directory exists
2. Verify `/root/<release>/stage/RPMS/x86_64` contains the required RPMs
3. Check that `rpmbuild` and `sbsigntools` are installed

### MOK-Signed Packages Not Being Installed

**Cause**: The installer doesn't see the `photon.secureboot=mok` kernel parameter.

**Check**:
1. Verify you selected **"Install (Custom MOK)"** from the boot menu
2. Check `/proc/cmdline` contains `photon.secureboot=mok`
3. Verify MOK RPMs exist in `/RPMS/x86_64/` directory on ISO

### "parted: command not found" (Fixed)

The tool now uses `sfdisk` instead of `parted` for eFuse USB creation.

## Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| "bad shim signature" | Selected VMware Original | Select Custom MOK instead |
| Laptop security dialog | CSM enabled | Disable CSM in BIOS |
| grub> prompt | Config not found | Manual boot or rebuild ISO |
| ISO not built with --create-efuse-usb | Old bug (fixed) | Update to latest version |
| Stub menu not showing (jumps to installer) | grub.cfg missing in ISO root | Update to v1.5.0+ |
