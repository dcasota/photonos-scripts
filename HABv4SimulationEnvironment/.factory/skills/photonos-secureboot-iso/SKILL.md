---
name: photonos-secureboot-iso
description: |
  Create UEFI Secure Boot enabled Photon OS ISOs compatible with consumer laptops.
  Handles Ventoy shim components, MOK enrollment, MBR/UEFI hybrid boot, and eFuse USB dongles.
  Use when building bootable ISOs for physical hardware with Secure Boot enabled.
---

# PhotonOS HABv4 Secure Boot ISO Creation Skill

## Overview

This skill covers creating Secure Boot enabled ISOs for Photon OS that work on consumer laptops with UEFI Secure Boot enabled. It uses Ventoy's SUSE shim components (SBAT=shim,4 compliant).

## Prerequisites

- Photon OS build environment
- Required packages: `xorriso`, `sbsigntools`, `dosfstools`, `wget`
- Ventoy 1.1.10+ components (auto-downloaded by the tool)

## Architecture

### Boot Modes Supported

| Mode | Bootloader | Secure Boot | Notes |
|------|------------|-------------|-------|
| UEFI x64 | BOOTX64.EFI (shim) | Yes | Primary target |
| UEFI IA32 | BOOTIA32.EFI (shim) | Yes | Rare 32-bit UEFI |
| BIOS/Legacy | isolinux | No | MBR fallback |

### UEFI Secure Boot Chain (Cascade Architecture)

```
UEFI Firmware (Microsoft UEFI CA in db)
    ↓ verifies Microsoft signature
BOOTX64.EFI (SUSE shim from Ventoy, SBAT=shim,4)
    ↓ verifies against MokList (after MOK enrollment)
grub.efi (Ventoy stub, 64KB, signed CN=grub)
    ↓ chainloads (EFI LoadImage)
grubx64_real.efi (Ventoy full GRUB, 1.9MB)
    ↓ reads /grub/grub.cfg
vmlinuz (kernel)
```

**The cascade architecture (shim → stub → full GRUB) is the CORRECT design.**

## CRITICAL: Ventoy's grub.cfg Path Requirements

### The Problem: Config Path Mismatch

Ventoy's `grubx64_real.efi` has an **embedded prefix** that looks for config files at:
1. `/grub/grub.cfg` (primary - Ventoy's location)
2. `/boot/grub/grub.cfg` (fallback)

**Photon OS uses `/boot/grub2/grub.cfg`** - this path is NOT in Ventoy's search list!

### The Solution: Create /grub/grub.cfg Redirect

Create a `/grub/grub.cfg` file at the ISO root that redirects to Photon's actual config:

```bash
# /grub/grub.cfg - Redirect to Photon OS config
search --no-floppy --file --set=root /isolinux/isolinux.cfg
set prefix=($root)/boot/grub2
configfile $prefix/grub.cfg
```

This file must exist at the **root of the ISO** in a `/grub/` directory.

### Why the Stub Drops to grub> Prompt

When Ventoy's cascade boots:
1. Shim loads `grub.efi` (stub) ✓
2. Stub chainloads `grubx64_real.efi` ✓
3. `grubx64_real.efi` looks for `/grub/grub.cfg` ✗ NOT FOUND
4. Falls back to `/boot/grub/grub.cfg` ✗ NOT FOUND (Photon uses grub2)
5. **Drops to `grub>` prompt**

## Ventoy Component Details

### File Purposes

| File | Size | Type | Purpose |
|------|------|------|---------|
| `BOOTX64.EFI` | ~965 KB | SUSE shim | First stage, Microsoft-signed |
| `grub.efi` | ~64 KB | Stub/PreLoader | Chainloads grubx64_real.efi |
| `grubx64_real.efi` | ~1.9 MB | Full GRUB | Actual bootloader, reads config |
| `MokManager.efi` | ~852 KB | MOK manager | Certificate enrollment UI |

### The 64KB Stub is NOT Broken

The stub `grub.efi` is designed to:
1. Be verified by shim (signed with CN=grub, Ventoy's MOK)
2. Chainload `grubx64_real.efi` using EFI LoadImage
3. **It does NOT read grub.cfg itself** - that's the real GRUB's job

The stub successfully chainloads the real GRUB. The problem is the real GRUB can't find its config file.

### Verifying the Cascade Works

At the `grub>` prompt, test if you're in the real GRUB:
```
grub> search --file /isolinux/isolinux.cfg
```
If this command works, you're in `grubx64_real.efi` (the stub doesn't have `search`).

## Required ISO Structure

```
ISO Root/
├── grub/                                # REQUIRED for Ventoy GRUB
│   └── grub.cfg                         # Redirect to Photon config
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer    # Ventoy MOK certificate (CN=grub)
├── mmx64.efi                            # MokManager at root
├── EFI/BOOT/
│   ├── BOOTX64.EFI                      # SUSE shim (Microsoft-signed)
│   ├── grub.efi                         # Ventoy stub (64KB, CN=grub signed)
│   ├── grubx64_real.efi                 # Ventoy full GRUB (1.9MB)
│   ├── MokManager.efi                   # MOK enrollment UI
│   └── grub.cfg                         # Bootstrap (optional backup)
├── boot/grub2/
│   ├── efiboot.img                      # EFI System Partition image
│   └── grub.cfg                         # Photon OS main boot menu
└── isolinux/                            # BIOS/MBR boot support
    ├── isolinux.bin
    ├── isolinux.cfg                     # Search marker file
    ├── vmlinuz
    └── initrd.img
```

### The Critical /grub/grub.cfg

**Content of `/grub/grub.cfg`:**
```bash
# Ventoy GRUB redirect to Photon OS config
# grubx64_real.efi looks here first (prefix=/grub)

search --no-floppy --file --set=root /isolinux/isolinux.cfg
set prefix=($root)/boot/grub2
configfile $prefix/grub.cfg
```

### efiboot.img Structure

The embedded EFI boot image must also have `/grub/grub.cfg`:
```
efiboot.img/
├── grub/
│   └── grub.cfg                         # Redirect config
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer
├── mmx64.efi
└── EFI/BOOT/
    ├── BOOTX64.EFI
    ├── grub.efi
    ├── grubx64_real.efi
    ├── MokManager.efi
    └── grub.cfg                         # Backup redirect
```

## CRITICAL: Shim MOK vs Firmware MOK

### Shim's MokManager (CORRECT)

- **UI**: Blue screen interface with white text
- **Storage**: MokList NVRAM variable (shim-specific)
- **Certificate to enroll**: `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` (CN=grub)

### Laptop Firmware MOK (WRONG)

- **UI**: Manufacturer-specific (Dell gray, HP red, Lenovo ThinkShield)
- **Storage**: UEFI db/dbx variables
- **Problem**: Does NOT populate shim's MokList

If you see the laptop's security dialog instead of the blue MokManager:
1. Disable CSM/Legacy boot in BIOS
2. Enable pure UEFI mode
3. Ensure Secure Boot is enabled

## Tool Usage

### PhotonOS-HABv4Emulation-ISOCreator

```bash
# Default setup (generates keys, eFuse simulation, downloads Ventoy)
./PhotonOS-HABv4Emulation-ISOCreator

# Build Secure Boot ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

## Verification Commands

```bash
# Verify /grub/grub.cfg exists in ISO (CRITICAL!)
xorriso -osirrox on -indev <iso> -extract /grub/grub.cfg /tmp/grub.cfg
cat /tmp/grub.cfg
# Should show: search/configfile redirect to /boot/grub2/

# Verify cascade components
xorriso -osirrox on -indev <iso> -ls /EFI/BOOT/
# Must have: BOOTX64.EFI, grub.efi (64KB), grubx64_real.efi (1.9MB)

# Check stub size (should be ~64KB)
xorriso -osirrox on -indev <iso> -extract /EFI/BOOT/grub.efi /tmp/stub.efi
stat -c%s /tmp/stub.efi
# Expected: ~64000 bytes

# Check real GRUB size (should be ~1.9MB)  
xorriso -osirrox on -indev <iso> -extract /EFI/BOOT/grubx64_real.efi /tmp/real.efi
stat -c%s /tmp/real.efi
# Expected: ~1900000 bytes
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
2. **EXPECT**: Blue MokManager screen (shim's)
   - If laptop's dialog appears → check BIOS settings
   - If `grub>` prompt appears → /grub/grub.cfg is missing
3. Select **"Enroll key from disk"**
4. Navigate to USB root
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm and select **"Reboot"** (NOT Continue)

### Step 4: Verify Boot

After reboot, Photon OS GRUB menu should appear.

## Troubleshooting

### Drops to `grub>` Prompt After MOK Enrollment

**Symptom**: After successful MOK enrollment, boots to bare `grub>` prompt.

**Cause**: `/grub/grub.cfg` is missing or incorrect.

**Diagnosis** (at grub> prompt):
```
grub> ls
# Should show partitions like (hd0), (hd0,msdos1), etc.

grub> ls (hd0,msdos2)/
# Look for grub/ directory

grub> cat (hd0,msdos2)/grub/grub.cfg
# If "file not found" - that's the problem!
```

**Manual boot** (at grub> prompt):
```
grub> search --no-floppy --file --set=root /isolinux/isolinux.cfg
grub> set prefix=($root)/boot/grub2
grub> configfile $prefix/grub.cfg
```

**Fix**: Rebuild ISO with `/grub/grub.cfg` redirect file.

### "Policy Violation" - Laptop's Security Dialog

**Cause**: CSM/Legacy boot enabled.

**Solution**:
1. Enter BIOS setup
2. Disable CSM/Legacy completely
3. Enable UEFI-only mode

### Commands Don't Work at grub> Prompt

**If `search` command not found**: You're in the stub, not real GRUB. The stub failed to chainload `grubx64_real.efi`.

**Check**: Is `grubx64_real.efi` present in `/EFI/BOOT/`?

**If `search` works but config not found**: You're in real GRUB but `/grub/grub.cfg` is missing.

## Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| `grub>` prompt, `search` works | Missing /grub/grub.cfg | Add redirect config |
| `grub>` prompt, `search` fails | Stub didn't chainload | Check grubx64_real.efi exists |
| Laptop security dialog | CSM enabled | Disable CSM in BIOS |
| Blue MokManager, enrollment fails | Wrong cert or NVRAM issue | Try hash enrollment |

| File | Expected Size | Purpose |
|------|---------------|---------|
| grub.efi | ~64 KB | Stub (chainloads real GRUB) |
| grubx64_real.efi | ~1.9 MB | Real GRUB (reads config) |
| /grub/grub.cfg | ~150 bytes | Redirect to Photon config |

## Implementation Checklist

When creating a Secure Boot ISO:

- [ ] SUSE shim (`BOOTX64.EFI`) is Microsoft-signed
- [ ] Stub (`grub.efi`) is ~64KB and signed CN=grub
- [ ] Real GRUB (`grubx64_real.efi`) is ~1.9MB
- [ ] `/grub/grub.cfg` exists with redirect to `/boot/grub2/grub.cfg`
- [ ] `/grub/grub.cfg` also exists inside efiboot.img
- [ ] `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` at ISO root
- [ ] MokManager.efi in `/EFI/BOOT/` and at root as `mmx64.efi`

## Related Documentation

- [BOOT_PROCESS.md](../../../docs/BOOT_PROCESS.md) - Detailed boot chain
- [TROUBLESHOOTING.md](../../../docs/TROUBLESHOOTING.md) - Complete troubleshooting
- [Ventoy Secure Boot](https://www.ventoy.net/en/doc_secure.html) - Ventoy docs
