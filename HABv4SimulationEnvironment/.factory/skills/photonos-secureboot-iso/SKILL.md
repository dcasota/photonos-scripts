---
name: photonos-secureboot-iso
description: |
  Create UEFI Secure Boot enabled Photon OS ISOs compatible with consumer laptops.
  Handles custom GRUB stub (without shim_lock), MOK enrollment, MBR/UEFI hybrid boot, and eFuse USB dongles.
  Use when building bootable ISOs for physical hardware with Secure Boot enabled.
---

# PhotonOS HABv4 Secure Boot ISO Creation Skill

## Overview

This skill covers creating Secure Boot enabled ISOs for Photon OS that work on consumer laptops with UEFI Secure Boot enabled. It uses a **custom GRUB stub** built with `grub2-mkimage` that excludes the `shim_lock` module, allowing unsigned kernels to load.

## Prerequisites

- Photon OS build environment
- Required packages: `xorriso`, `sbsigntools`, `dosfstools`, `wget`, `grub2-efi`
- Ventoy 1.1.10+ components (auto-downloaded for SUSE shim and MokManager)

## Architecture

### Boot Modes Supported

| Mode | Bootloader | Secure Boot | Notes |
|------|------------|-------------|-------|
| UEFI x64 | BOOTX64.EFI (shim) | Yes | Primary target |
| UEFI IA32 | BOOTIA32.EFI (shim) | Yes | Rare 32-bit UEFI |
| BIOS/Legacy | isolinux | No | MBR fallback |

### UEFI Secure Boot Chain (Dual-Boot Architecture)

```
UEFI Firmware (Microsoft UEFI CA in db)
    ↓ verifies Microsoft signature
BOOTX64.EFI (SUSE shim from Ventoy, SBAT=shim,4)
    ↓ verifies MOK signature
grub.efi (Custom GRUB stub, MOK-signed, NO shim_lock)
    ↓ presents Stub Menu (5 sec timeout)
    │
    ├─→ "Custom MOK" path:
    │   configfile /boot/grub2/grub-custom.cfg
    │   → "Install (Custom MOK)" → linux vmlinuz (loads WITHOUT signature check)
    │
    └─→ "VMware Original" path:
        chainloader grubx64_real.efi
        → VMware's GRUB (has shim_lock) → FAILS: unsigned kernel rejected
```

**IMPORTANT: We build a CUSTOM GRUB stub without `shim_lock` module**

## CRITICAL: Why Custom GRUB Stub is Necessary

### The Problem: VMware's GRUB Has shim_lock Module

VMware's GRUB (`grubx64.efi`) includes the `shim_lock` verifier:
1. Detects it was loaded via shim (Secure Boot chain)
2. Intercepts all file loading operations (kernel, initrd, modules)
3. Calls shim's `Verify()` protocol to check signatures
4. Rejects any file that shim doesn't trust

**Trust sources for shim's Verify()**:
- Microsoft UEFI CA (in firmware db)
- Shim's embedded vendor certificate (SUSE's cert, not VMware's)
- MokList (user-enrolled certificates)

**Result**: `shim_lock` calls `Verify(vmlinuz)` → unsigned kernel → **"bad shim signature"**

### The Solution: Custom GRUB Stub Without shim_lock

We build our own GRUB stub using `grub2-mkimage`:
```bash
grub2-mkimage -O x86_64-efi -o grub-stub.efi -c stub-menu.cfg -p /EFI/BOOT \
    normal search configfile linux chain fat part_gpt part_msdos iso9660 \
    boot echo reboot halt test true loadenv read all_video gfxterm font efi_gop
```

**Key Point**: `shim_lock` is NOT in the module list = NOT included = NO kernel verification

### Security Implications

| Component | Verified By | Status |
|-----------|-------------|--------|
| BOOTX64.EFI (shim) | UEFI firmware (Microsoft CA) | ✓ Secure |
| grub.efi (custom stub) | Shim (MOK signature) | ✓ Secure |
| vmlinuz (kernel) | NOT verified (no shim_lock) | ⚠ Unverified |

This is acceptable for an **installer ISO** context where the goal is to boot and install.

## Stub Menu (5 Second Timeout)

```
1. Continue to Photon OS Installer (Custom MOK)     [default]
   → configfile /boot/grub2/grub-custom.cfg
   → Main menu: "Install (Custom MOK)"
   
2. Continue to Photon OS Installer (VMware Original)
   → chainloader /EFI/BOOT/grubx64_real.efi
   → Note: Will fail with "bad shim signature" on consumer laptops
   
3. MokManager - Enroll/Delete MOK Keys
   → chainloader /MokManager.efi
   
4. Reboot into UEFI Firmware Settings
   → fwsetup
   
5. Reboot
   → reboot
   
6. Shutdown
   → halt
```

## File Purposes

| File | Size | Type | Purpose |
|------|------|------|---------|
| `BOOTX64.EFI` | ~965 KB | SUSE shim | First stage, Microsoft-signed |
| `grub.efi` | ~900 KB | Custom GRUB stub | MOK-signed, NO shim_lock, dual-boot menu |
| `grubx64_real.efi` | ~1.3 MB | VMware's GRUB | For "VMware Original" option (has shim_lock) |
| `MokManager.efi` | ~852 KB | MOK manager | Certificate enrollment UI |
| `grub-custom.cfg` | ~500 B | GRUB config | "Install (Custom MOK)" menu |

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
    ├── vmlinuz
    └── initrd.img
```

## Tool Usage

### PhotonOS-HABv4Emulation-ISOCreator

```bash
# Default setup (generates keys, downloads Ventoy components)
./PhotonOS-HABv4Emulation-ISOCreator

# Build Secure Boot ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
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
   - If laptop's dialog appears → check BIOS settings (disable CSM)
3. Select **"Enroll key from disk"**
4. Navigate to USB root
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm and select **"Reboot"** (NOT Continue)

### Step 4: Boot to Installer

After reboot:
1. Stub menu appears (5 second timeout)
2. Select **"Continue to Photon OS Installer (Custom MOK)"** (default)
3. Main menu appears: **"Install (Custom MOK)"**
4. Installation proceeds normally

## Troubleshooting

### "bad shim signature" Error

**Symptom**: Selecting "Install" shows `bad shim signature` error.

**Cause**: You selected "VMware Original" which uses VMware's GRUB with shim_lock.

**Solution**: Reboot and select **"Custom MOK"** option instead.

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
| "SBAT self-check failed" | Old shim | Use latest Ventoy (1.1.10+) |

## Related Documentation

- [BOOT_PROCESS.md](../../../docs/BOOT_PROCESS.md) - Detailed boot chain
- [TROUBLESHOOTING.md](../../../docs/TROUBLESHOOTING.md) - Complete troubleshooting
- [Ventoy Secure Boot](https://www.ventoy.net/en/doc_secure.html) - Ventoy docs
