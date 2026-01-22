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

### UEFI Secure Boot Chain

```
UEFI Firmware (Microsoft UEFI CA in db)
    ↓ verifies Microsoft signature
BOOTX64.EFI (SUSE shim from Ventoy, SBAT=shim,4)
    ↓ verifies against MokList (after MOK enrollment)
grubx64.efi (Full GRUB, signed with MOK key)
    ↓ loads grub.cfg
vmlinuz (VMware-signed kernel)
```

## CRITICAL: Ventoy Component Limitations

### Understanding Ventoy's grub.efi (PreLoader)

**Ventoy's `grub.efi` is NOT a full GRUB binary!** This is a common source of boot failures.

| Property | Ventoy grub.efi | Full GRUB (grubx64_real.efi) |
|----------|-----------------|------------------------------|
| Size | ~64 KB | ~1.9 MB |
| Type | Minimal stub/PreLoader | Full GRUB bootloader |
| Commands | Very limited (no search, configfile, chainloader) | Full command set |
| Purpose | Ventoy-specific chainloading | General-purpose bootloader |
| Config | Embedded, Ventoy-specific paths | Reads grub.cfg from disk |

**Why this matters**: If you use Ventoy's `grub.efi` as your bootloader and it drops to a `grub>` prompt, it's because this minimal stub cannot execute standard GRUB commands like `search` or `configfile`.

### Correct Approach for Photon OS

**DO NOT** use Ventoy's `grub.efi` as the main bootloader. Instead:

1. Use **SUSE shim** (`BOOTX64.EFI`) - Microsoft signed, SBAT compliant
2. Use **VMware's GRUB** (`grubx64.efi` from Photon ISO) - Full GRUB, can be MOK-signed
3. Sign VMware's GRUB with your MOK key so shim trusts it

### Boot Chain Options

**Option A: Sign VMware GRUB with MOK (Recommended)**
```
BOOTX64.EFI (SUSE shim) → grubx64.efi (VMware GRUB, MOK-signed) → kernel
```
- Requires signing VMware's GRUB with your own MOK key
- User enrolls YOUR certificate, not Ventoy's

**Option B: Use Ventoy's Full Chain (Not for custom ISOs)**
```
BOOTX64.EFI (SUSE shim) → grub.efi (stub) → grubx64_real.efi → kernel
```
- Only works with Ventoy's specific directory structure (`/grub/grub.cfg`)
- The stub expects Ventoy-specific paths and files
- **NOT suitable for Photon OS ISOs**

## CRITICAL: Shim MOK vs Firmware MOK

This is the most important concept for troubleshooting Secure Boot issues.

### Shim's MokManager (CORRECT for Ventoy-style boot)

- **UI**: Blue screen interface with white text
- **Storage**: MokList NVRAM variable (shim-specific)
- **Used by**: Ventoy, Ubuntu, Fedora, SUSE, etc.
- **How to trigger**: Shim automatically launches it when loader signature not trusted

### Laptop Firmware MOK (WRONG for our use case)

- **UI**: Manufacturer-specific (Dell gray, HP red/white, Lenovo ThinkShield)
- **Storage**: UEFI db/dbx variables (firmware-level)
- **Problem**: Does NOT populate shim's MokList
- **Result**: Even after enrollment, shim still doesn't trust the loader

### Why Ventoy Works on USB Drives

Ventoy works because it has a **complete ecosystem**:
1. Specific directory structure (`/grub/`, `/ventoy/`, etc.)
2. Pre-configured `grub.cfg` at `/grub/grub.cfg` (89KB!)
3. The stub `grub.efi` knows to look for Ventoy-specific paths
4. `grubx64_real.efi` is configured with Ventoy's prefix

**Our ISO lacks this structure**, so Ventoy's stub drops to a prompt.

## Files and Their Purposes

| File | Source | Size | Purpose | Use in ISO? |
|------|--------|------|---------|-------------|
| BOOTX64.EFI | Ventoy | 965 KB | SUSE shim (Microsoft-signed) | YES - first stage |
| grub.efi | Ventoy | 64 KB | Minimal stub (Ventoy-specific) | NO - lacks commands |
| grubx64_real.efi | Ventoy | 1.9 MB | Full GRUB (Ventoy-specific prefix) | MAYBE - needs config |
| grubx64.efi | Photon ISO | 1.3 MB | VMware's GRUB | YES - sign with MOK |
| MokManager.efi | Ventoy | 852 KB | MOK enrollment UI | YES |
| ENROLL_THIS_KEY_IN_MOKMANAGER.cer | Generated | ~1 KB | Your MOK certificate | YES |

### File Verification

```bash
# Check if a GRUB binary is full or stub
ls -la file.efi
# Stub: ~64 KB
# Full GRUB: 1-2 MB

# Check available commands in GRUB binary
strings file.efi | grep -E "^search$|^configfile$|^chainloader$|^linux$" | wc -l
# Stub: 0 matches
# Full GRUB: multiple matches

# Verify signature
sbverify --list file.efi
```

## ISO Structure

```
ISO Root/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer   # Your MOK certificate
├── mmx64.efi                            # MokManager at root
├── EFI/BOOT/
│   ├── BOOTX64.EFI                      # SUSE shim (Microsoft-signed)
│   ├── grubx64.efi                      # VMware GRUB (MOK-signed) ← NOT grub.efi!
│   ├── MokManager.efi                   # MOK enrollment UI
│   └── grub.cfg                         # Bootstrap config (optional)
├── boot/grub2/
│   ├── efiboot.img                      # EFI System Partition image
│   └── grub.cfg                         # Main boot menu
└── isolinux/                            # BIOS/MBR boot support
    ├── isolinux.bin
    ├── vmlinuz
    └── initrd.img
```

### Key Point: grubx64.efi NOT grub.efi

The shim looks for a second-stage loader. SUSE shim defaults to `grubx64.efi` (or `grub.efi` as fallback). 

**Use VMware's full GRUB** renamed/copied to `grubx64.efi`, NOT Ventoy's 64KB stub.

## Tool Usage

### PhotonOS-HABv4Emulation-ISOCreator

```bash
# Default setup (generates keys, eFuse simulation, downloads Ventoy)
./PhotonOS-HABv4Emulation-ISOCreator

# Build Secure Boot ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build for specific Photon OS release
./PhotonOS-HABv4Emulation-ISOCreator -r 5.0 -b

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

## Signing VMware's GRUB

To create a working Secure Boot ISO:

```bash
# 1. Generate MOK key pair
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.key -out MOK.crt \
    -nodes -days 3650 -subj "/CN=Photon OS Secure Boot/"

# 2. Convert to DER for enrollment
openssl x509 -in MOK.crt -out MOK.der -outform DER

# 3. Extract VMware's GRUB from Photon ISO
xorriso -osirrox on -indev photon.iso -extract /boot/efi/EFI/BOOT/grubx64.efi ./grubx64.efi

# 4. Sign with your MOK key
sbsign --key MOK.key --cert MOK.crt --output grubx64-signed.efi grubx64.efi

# 5. Verify signature
sbverify --list grubx64-signed.efi
# Should show your certificate CN

# 6. Use grubx64-signed.efi as EFI/BOOT/grubx64.efi in your ISO
# 7. Include MOK.der as ENROLL_THIS_KEY_IN_MOKMANAGER.cer
```

## Verification Commands

```bash
# Check if GRUB is full or stub (CRITICAL!)
stat -c%s EFI/BOOT/grubx64.efi
# Should be > 1 MB for full GRUB
# If ~64 KB, it's the Ventoy stub - WILL NOT WORK!

# Verify shim is Microsoft-signed
sbverify --list EFI/BOOT/BOOTX64.EFI 2>&1 | grep -i microsoft

# Verify GRUB is signed with your MOK
sbverify --list EFI/BOOT/grubx64.efi 2>&1 | grep -i "subject:"

# Test GRUB has required commands
strings EFI/BOOT/grubx64.efi | grep -c "configfile"
# Should be > 0

# Verify ISO has UEFI boot capability
xorriso -indev <iso> -pvd_info 2>&1 | grep -i "El Torito"
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
2. **EXPECT**: Blue MokManager screen with white text
   - If you see laptop's manufacturer dialog instead → STOP, check BIOS settings
   - If you see `grub>` prompt → WRONG GRUB binary used (stub instead of full)
3. Select **"Enroll key from disk"**
4. Navigate to USB root
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm and select **"Reboot"** (NOT Continue)

### Step 4: Verify Boot

After reboot, GRUB menu should appear (not `grub>` prompt).

## Troubleshooting

### Drops to `grub>` Prompt (No Menu)

**Symptom**: After MOK enrollment succeeds, system boots to bare `grub>` prompt.

**Cause**: Using Ventoy's 64KB stub `grub.efi` instead of full GRUB.

**Diagnosis**:
```bash
# Check the GRUB binary size in your ISO
xorriso -osirrox on -indev your.iso -extract /EFI/BOOT/grubx64.efi /tmp/grub.efi
stat -c%s /tmp/grub.efi
# If ~64 KB → WRONG (Ventoy stub)
# If ~1-2 MB → Correct (full GRUB)
```

**Solution**: 
1. Use VMware's GRUB from the original Photon ISO
2. Sign it with your MOK key
3. Place as `EFI/BOOT/grubx64.efi`

### "Policy Violation" - Laptop's Security Dialog

**Symptom**: Manufacturer-branded dialog instead of blue MokManager.

**Cause**: CSM/Legacy boot enabled or wrong boot mode.

**Solution**:
1. Enter BIOS setup
2. Disable CSM/Legacy completely
3. Ensure UEFI-only mode
4. Verify Secure Boot is enabled

### MOK Enrollment Doesn't Persist

**Cause**: Enrolling in firmware db instead of shim's MokList.

**Solution**: Must see blue MokManager screen, not laptop's firmware dialog.

### "Security Violation" After Enrollment

**Possible causes**:
1. Wrong certificate enrolled (must match GRUB signature)
2. Used "Continue" instead of "Reboot"
3. GRUB signed with different key than certificate

**Solution**: Verify certificate matches GRUB signature:
```bash
# Certificate subject
openssl x509 -in ENROLL_THIS_KEY_IN_MOKMANAGER.cer -inform DER -noout -subject

# GRUB signature issuer (should match)
sbverify --list grubx64.efi | grep subject
```

### GRUB Prompt Commands Don't Work

**Symptom**: At `grub>` prompt, commands like `ls`, `search`, `configfile` return errors.

**Cause**: Using Ventoy's minimal stub which lacks these commands.

**Solution**: Replace with full GRUB binary (see "Drops to grub> Prompt" above).

## Quick Reference

| Issue | Likely Cause | Quick Check |
|-------|--------------|-------------|
| `grub>` prompt | Wrong GRUB binary (stub) | Check file size (~64KB = stub) |
| Policy violation | CSM enabled | Check BIOS boot mode |
| Enrollment fails | Wrong MokManager | Must see blue screen |
| Commands not found | Stub GRUB | Check `strings \| grep configfile` |

| Task | Command |
|------|---------|
| Build ISO | `./PhotonOS-HABv4Emulation-ISOCreator -b` |
| Diagnose ISO | `./PhotonOS-HABv4Emulation-ISOCreator -D <iso>` |
| Check GRUB size | `stat -c%s EFI/BOOT/grubx64.efi` |
| Sign GRUB | `sbsign --key MOK.key --cert MOK.crt -o signed.efi grub.efi` |

## Related Documentation

- [BOOT_PROCESS.md](../../../docs/BOOT_PROCESS.md) - Detailed boot chain explanation
- [TROUBLESHOOTING.md](../../../docs/TROUBLESHOOTING.md) - Complete troubleshooting guide
- [Ventoy Secure Boot](https://www.ventoy.net/en/doc_secure.html) - Ventoy official docs
