# UEFI Secure Boot Process

This document explains the complete boot process from UEFI firmware to running kernel.

## Table of Contents

1. [Overview](#overview)
2. [UEFI Firmware Phase](#uefi-firmware-phase)
3. [Shim Bootloader Phase](#shim-bootloader-phase)
4. [GRUB Bootloader Phase](#grub-bootloader-phase)
5. [Kernel Loading Phase](#kernel-loading-phase)
6. [Trust Chain Diagram](#trust-chain-diagram)

---

## Overview

Secure Boot ensures only cryptographically signed code runs during boot. The chain of trust flows:

```
UEFI Firmware → Shim → Custom GRUB Stub → Kernel
```

Each stage verifies the signature of the next before executing it.

---

## UEFI Firmware Phase

### Key Databases

UEFI firmware maintains several key databases stored in NVRAM:

| Database | Purpose |
|----------|---------|
| **PK** | Platform Key (Root of trust) |
| **KEK** | Key Exchange Key (Updates db/dbx) |
| **db** | Allowed signatures (Microsoft UEFI CA) |
| **dbx** | Forbidden signatures (Revocation list) |

### Boot Process

1. UEFI firmware initializes.
2. Checks signature of `/EFI/BOOT/BOOTX64.EFI` (Shim).
3. Verifies against **Microsoft UEFI CA** in `db`.
4. Executes Shim.

---

## Shim Bootloader Phase

### Files
- **Shim**: `BOOTX64.EFI` (SUSE shim, Microsoft-signed).
- **MOK Manager**: `MokManager.efi` (SUSE MOK Manager).

### Verification
Shim verifies the next stage (GRUB stub) using:
1. **Embedded Vendor Cert** (SUSE).
2. **MOK List** (Machine Owner Keys enrolled by user).
3. **SBAT Policy** (Secure Boot Advanced Targeting).

**Critical**: Modern Shims enforce SBAT. If the next stage lacks valid SBAT metadata, it is rejected ("Policy Violation").

---

## GRUB Bootloader Phase

### Files
- **Stub**: `grub.efi` (Custom GRUB, MOK-signed, SBAT-compliant).
- **Config**: `/boot/grub2/grub-custom.cfg`.

### Custom Stub Features
We build a custom GRUB binary using `grub2-mkimage` that:
1.  **Includes SBAT metadata**: To satisfy Shim's policy check.
2.  **Is signed with MOK**: To pass Shim's signature check.
3.  **Excludes `shim_lock`**: To prevent strict validation of the kernel (relies on MOK signature instead).
4.  **Provides a Menu**:
    -   1. Custom MOK (Default)
    -   2. VMware Original (Fallback)
    -   3. MOK Management

---

## Kernel Loading Phase

### Path 1: Custom MOK (Default)
1.  Stub loads `vmlinuz`.
2.  Stub verifies kernel signature against **MOK**.
3.  Kernel loads.

### Path 2: VMware Original (Fallback)
1.  Stub chainloads `grubx64_real.efi` (VMware's original GRUB).
2.  VMware GRUB includes `shim_lock` module.
3.  VMware GRUB calls Shim's `Verify()` protocol.
4.  Shim verifies kernel against its allowlist.
    -   *Fails if kernel is unsigned.*
    -   *Succeeds if kernel is signed by VMware or MOK.*

---

## Trust Chain Diagram

```
┌───────────────────────────┐
│       UEFI FIRMWARE       │
│   (Microsoft UEFI CA)     │
└─────────────┬─────────────┘
              │ Verifies
              ▼
┌───────────────────────────┐
│   SUSE SHIM (BOOTX64.EFI) │
│   (Microsoft-signed)      │
└─────────────┬─────────────┘
              │ Verifies (via MOK + SBAT)
              ▼
┌───────────────────────────┐
│     CUSTOM GRUB STUB      │
│   (MOK-signed + SBAT)     │
└─────────────┬─────────────┘
              │
      ┌───────┴───────┐
      │ Verifies      │ Chainloads
      ▼               ▼
┌─────────────┐ ┌─────────────┐
│   KERNEL    │ │ VMWARE GRUB │
│ (MOK-signed)│ │ (Real EFI)  │
└─────────────┘ └─────────────┘
```
