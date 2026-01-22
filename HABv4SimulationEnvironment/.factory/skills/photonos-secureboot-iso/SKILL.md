---
name: photonos-secureboot-iso
description: |
  Create UEFI Secure Boot enabled Photon OS ISOs compatible with consumer laptops.
  Handles custom GRUB stub (without shim_lock), MOK enrollment, and MBR/UEFI hybrid boot.
  Use when building bootable ISOs for physical hardware with Secure Boot enabled.
---

# PhotonOS HABv4 Secure Boot ISO Creation Skill

## Overview

This skill covers creating Secure Boot enabled ISOs for Photon OS that work on consumer laptops with UEFI Secure Boot enabled. It uses a **custom GRUB stub** built with `grub2-mkimage` that excludes the `shim_lock` module, allowing the MOK-signed kernel to load.

## Prerequisites

- Photon OS build environment
- Required packages: `xorriso`, `sbsigntools`, `dosfstools`, `grub2-efi`
- SUSE shim components (embedded in repository, auto-extracted)

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
    ↓ presents Stub Menu (5 sec timeout)
    │
    ├─→ "1. Custom MOK" path:
    │   configfile /boot/grub2/grub-custom.cfg
    │   → "Install (Custom MOK)" → linux vmlinuz (MOK-signed)
    │
    └─→ "2. VMware Original" path:
        chainloader grubx64_real.efi
        → VMware's GRUB (has shim_lock) → FAILS: unsigned kernel rejected
```

## CRITICAL: Why Custom GRUB Stub is Necessary

### The Problem: VMware's GRUB Has shim_lock Module

VMware's GRUB (`grubx64.efi`) includes the `shim_lock` verifier:
1. Detects it was loaded via shim (Secure Boot chain)
2. Intercepts all file loading operations (kernel, initrd, modules)
3. Calls shim's `Verify()` protocol to check signatures
4. Rejects any file that shim doesn't trust

**Result**: `shim_lock` calls `Verify(vmlinuz)` → unsigned kernel → **"bad shim signature"**

### The Solution: Custom GRUB Stub + MOK-Signed Kernel

1. Build custom GRUB stub with `grub2-mkimage` **without shim_lock**
2. Sign the custom stub with MOK key
3. Sign the kernel with MOK key
4. User enrolls ONE certificate (our MOK)

## Stub Menu (5 Second Timeout)

```
1. Continue to Photon OS Installer (Custom MOK)     [default]
   → configfile /boot/grub2/grub-custom.cfg
   → Main menu: "Install (Custom MOK)"
   
2. Continue to Photon OS Installer (VMware Original)
   → chainloader /EFI/BOOT/grubx64_real.efi
   → Note: Will fail with "bad shim signature" on consumer laptops
   
3. MokManager - Enroll/Delete MOK Keys
   → chainloader /EFI/BOOT/MokManager.efi
   
4. Reboot into UEFI Firmware Settings
   → fwsetup
   
5. Reboot
   → reboot
   
6. Shutdown
   → halt
```

## File Purposes

| File | Type | Purpose |
|------|------|---------|
| `BOOTX64.EFI` | SUSE shim | First stage, Microsoft-signed |
| `grub.efi` | Custom GRUB stub | MOK-signed, NO shim_lock, 6-option menu |
| `grubx64_real.efi` | VMware's GRUB | For "VMware Original" option (has shim_lock) |
| `MokManager.efi` | MOK manager | Certificate enrollment UI |
| `grub-custom.cfg` | GRUB config | "Install (Custom MOK)" menu |
| `vmlinuz` | Kernel | MOK-signed for Custom MOK path |

## Required ISO Structure

```
ISO Root/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer    # MOK certificate for enrollment
├── MokManager.efi                        # SUSE MokManager at root
├── mmx64.efi                             # MokManager (alternate name)
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
    ├── isolinux.bin
    ├── isolinux.cfg
    ├── vmlinuz                           # MOK-signed kernel
    └── initrd.img
```

## Tool Usage

### PhotonOS-HABv4Emulation-ISOCreator

```bash
# Default setup (generates keys only)
./PhotonOS-HABv4Emulation-ISOCreator

# Build Secure Boot ISO (auto-extracts embedded SUSE shim components)
./PhotonOS-HABv4Emulation-ISOCreator -b

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

### Embedded Components

SUSE shim components are embedded in the repository at `data/`:
- `shim-suse.efi.gz` - SUSE shim (Microsoft-signed)
- `MokManager-suse.efi.gz` - MOK Manager

These are automatically extracted when building an ISO. No manual download required.

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
   - If laptop's dialog appears → check BIOS settings (disable CSM)
3. Select **"Enroll key from disk"**
4. Navigate to USB root
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm and select **"Reboot"** (NOT Continue)

### Step 4: Boot to Installer

After reboot:
1. Stub menu appears (5 second timeout)
2. Select **"1. Continue to Photon OS Installer (Custom MOK)"** (default)
3. Main menu appears: **"Install (Custom MOK)"**
4. Installation proceeds normally

## Troubleshooting

### "bad shim signature" Error

**Symptom**: Selecting "Install" shows `bad shim signature` error.

**Cause**: You selected "VMware Original" which uses VMware's GRUB with shim_lock.

**Solution**: Reboot and select **"1. Custom MOK"** option instead.

### Drops to grub> Prompt

**Symptom**: After MOK enrollment, boots to bare `grub>` prompt.

**Cause**: GRUB can't find its config file.

**Manual boot** (at grub> prompt):
```
grub> search --no-floppy --file --set=root /isolinux/isolinux.cfg
grub> configfile ($root)/boot/grub2/grub-custom.cfg
```

### Laptop Shows Security Dialog Instead of Blue MokManager

**Cause**: CSM/Legacy boot is enabled, or booting in non-UEFI mode.

**Solution**:
1. Enter BIOS setup
2. Disable CSM/Legacy completely
3. Enable pure UEFI mode
4. Ensure Secure Boot is enabled

## Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| "bad shim signature" | Selected VMware Original | Select Custom MOK instead |
| Laptop security dialog | CSM enabled | Disable CSM in BIOS |
| grub> prompt | Config not found | Manual boot or rebuild ISO |
| "SBAT self-check failed" | Old shim | Rebuild with latest embedded shim |

## Related Documentation

- [BOOT_PROCESS.md](../../../docs/BOOT_PROCESS.md) - Detailed boot chain
- [TROUBLESHOOTING.md](../../../docs/TROUBLESHOOTING.md) - Complete troubleshooting
