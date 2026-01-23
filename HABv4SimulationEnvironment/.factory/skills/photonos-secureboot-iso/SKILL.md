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
    │   linux vmlinuz (MOK-signed) + initrd
    │
    └─→ "Install (VMware Original)" path:
        chainloader grubx64_real.efi
        → VMware's GRUB (has shim_lock) → unsigned kernel rejected
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

### "bad shim signature" Error

**Cause**: Selected "VMware Original" which uses VMware's GRUB with shim_lock.

**Solution**: Reboot and select **"1. Custom MOK"** option instead.

### Drops to grub> Prompt

**Manual boot** at grub> prompt:
```
grub> search --no-floppy --file --set=root /isolinux/isolinux.cfg
grub> configfile ($root)/boot/grub2/grub-custom.cfg
```

### Laptop Shows Security Dialog Instead of Blue MokManager

**Cause**: CSM/Legacy boot is enabled.

**Solution**: Disable CSM/Legacy completely in BIOS, enable pure UEFI mode.

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
