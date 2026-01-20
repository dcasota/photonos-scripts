# UEFI Secure Boot Process

This document explains the complete boot process from UEFI firmware to running kernel.

## Table of Contents

1. [Overview](#overview)
2. [UEFI Firmware Phase](#uefi-firmware-phase)
3. [Shim Bootloader Phase](#shim-bootloader-phase)
4. [GRUB Bootloader Phase](#grub-bootloader-phase)
5. [Kernel Loading Phase](#kernel-loading-phase)
6. [Module Loading Phase](#module-loading-phase)
7. [Trust Chain Diagram](#trust-chain-diagram)
8. [Why Fedora Shim](#why-fedora-shim)

---

## Overview

Secure Boot ensures only cryptographically signed code runs during boot. The chain of trust flows:

```
UEFI Firmware → Shim → GRUB Stub → GRUB Real → Kernel → Modules
```

Each stage verifies the signature of the next before executing it.

---

## UEFI Firmware Phase

### Key Databases

UEFI firmware maintains several key databases stored in NVRAM:

| Database | Full Name | Purpose |
|----------|-----------|---------|
| **PK** | Platform Key | Single key that controls all other keys |
| **KEK** | Key Exchange Key | Keys authorized to update db/dbx |
| **db** | Signature Database | Trusted certificates and hashes |
| **dbx** | Forbidden Database | Revoked/blocked certificates and hashes |

### Consumer Laptop Configuration

Most consumer laptops ship with:
- **PK**: OEM's Platform Key (Dell, HP, Lenovo, etc.)
- **KEK**: Microsoft's Key Exchange Key
- **db**: Microsoft UEFI CA 2011 certificate
- **dbx**: Known-bad bootloader hashes

### Boot Process

1. UEFI firmware initializes hardware
2. Checks if Secure Boot is enabled
3. Locates bootloader at `\EFI\BOOT\BOOTX64.EFI`
4. Verifies bootloader signature against `db` certificates
5. If valid, executes bootloader; if invalid, refuses to boot

### The Microsoft Signing Requirement

Since consumer laptops only have Microsoft's certificate in `db`, the first-stage bootloader **must** be signed by Microsoft. This is why we use **shim** - a minimal bootloader that Microsoft will sign.

---

## Shim Bootloader Phase

### What is Shim?

Shim is a minimal UEFI bootloader that:
1. Is signed by Microsoft (so UEFI trusts it)
2. Contains an embedded vendor certificate
3. Maintains its own key database (MOK - Machine Owner Key)
4. Loads and verifies the next boot stage

### Shim Files

| File | Description |
|------|-------------|
| `BOOTX64.EFI` or `shimx64.efi` | Fedora shim 15.8 (SBAT=shim,4 compliant) |
| `MokManager.efi` | Fedora MOK enrollment utility |
| `grub.efi` or `grubx64.efi` | Photon OS GRUB stub (MOK-signed) |
| `grubx64_real.efi` | VMware-signed GRUB real binary |

### Shim Verification Process

```
Shim receives control from UEFI
         │
         ▼
    Load grub.efi
         │
         ▼
┌────────────────────────────────┐
│  Check signature against:      │
│  1. Embedded vendor cert       │
│  2. MOK database               │
│  3. UEFI db (via shim protocol)│
└────────────────────────────────┘
         │
    ┌────┴────┐
    ▼         ▼
 Valid     Invalid
    │         │
    ▼         ▼
 Execute   Reject
  GRUB    (error)
```

### Why Fedora Shim + Photon OS GRUB Stub

We use **Fedora's shim** for SBAT compliance and a **custom Photon OS GRUB stub** for a clean trust chain:

| Aspect | Ventoy SUSE Shim | Fedora Shim 15.8 |
|--------|------------------|------------------|
| Signed by | Microsoft | Microsoft |
| SBAT Version | shim,3 (REVOKED) | shim,4 (compliant) |
| Boot Result | "SBAT self-check failed" | Boots successfully |
| Embedded cert | SUSE | Fedora CA |
| MokManager | SUSE-signed | Fedora-signed |

**Key insight**: Microsoft's SBAT (Secure Boot Advanced Targeting) revocation requires `shim,4` or higher. Ventoy's SUSE shim has `shim,3` and is blocked by modern firmwares.

We build a **custom Photon OS GRUB stub** signed with `CN=Photon OS Secure Boot MOK` instead of using third-party (Ventoy) binaries.

### Shim's Fallback Loader Names

Fedora shim looks for second-stage bootloader in this order:
1. `grubx64.efi` (standard name)
2. `grub.efi` (fallback)

**Important**: We provide both for maximum compatibility.

---

## GRUB Bootloader Phase

### GRUB's Role

GRUB has two stages in this ISO:
1. **GRUB Stub** (MOK-signed) - minimal chainloader to GRUB real
2. **GRUB Real** (VMware-signed) - provides boot menu and loads kernel/initrd

### GRUB Configuration

**Stub Menu** (embedded in grub.efi stub):

```bash
# 5 second timeout, MokManager accessible here
menuentry "Continue to Photon OS Installer" {
    chainloader /EFI/BOOT/grubx64_real.efi
}

menuentry "MokManager - Enroll/Delete MOK Keys" {
    chainloader /EFI/BOOT/MokManager.efi
}
```

**Main Boot Menu** (in `/boot/grub2/grub.cfg`):

```bash
menuentry "Install Photon OS (Custom)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3
    initrd /isolinux/initrd.img
}

menuentry "Install Photon OS (VMware original)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=7
    initrd /isolinux/initrd.img
}
```

### Bootstrap grub.cfg for ISO Boot

When booting from ISO, GRUB needs to find the ISO filesystem. The `efiboot.img` contains a bootstrap config:

```bash
# Search for ISO filesystem
search --no-floppy --file --set=root /isolinux/vmlinuz

# Load real config from ISO
if [ -n "$root" ]; then
    configfile ($root)/boot/grub2/grub.cfg
fi
```

### GRUB Signature Verification

GRUB signature verification occurs in two hops:
1. Shim verifies the MOK-signed **GRUB stub** (`grub.efi`/`grubx64.efi`)
2. The stub chainloads **GRUB real** (`grubx64_real.efi`) which retains VMware signature

---

## Kernel Loading Phase

### Kernel Signature Verification

When GRUB loads the kernel:
1. GRUB calls shim's verification protocol
2. Shim checks kernel signature against:
   - Embedded vendor certificate
   - MOK database
   - UEFI db

### Single Kernel

Our ISO includes one VMware-signed kernel:

| Kernel | Signed By | Use Case |
|--------|-----------|----------|
| `vmlinuz` | VMware | All systems (VMs and physical laptops) |

### Kernel Lockdown

When Secure Boot is active, the kernel enables **lockdown mode**:
- Restricts `/dev/mem` access
- Blocks unsigned module loading
- Prevents hibernation to unsigned images
- Restricts kexec to signed kernels

---

## Module Loading Phase

### Module Signature Verification

The kernel verifies module signatures using its built-in keyring:

```
Module load request
        │
        ▼
┌───────────────────────────┐
│ Check signature against   │
│ kernel's trusted keyring  │
│ (.builtin_trusted_keys)   │
└───────────────────────────┘
        │
   ┌────┴────┐
   ▼         ▼
 Valid    Invalid
   │         │
   ▼         ▼
 Load    Reject
module   (error)
```

### Module Signing Configuration

Kernel config options:

```kconfig
CONFIG_MODULE_SIG=y              # Enable signature checking
CONFIG_MODULE_SIG_FORCE=y        # Reject unsigned modules
CONFIG_MODULE_SIG_ALL=y          # Sign all modules at build time
CONFIG_MODULE_SIG_SHA512=y       # Use SHA-512 for signatures
CONFIG_MODULE_SIG_KEY="certs/signing_key.pem"
```

### Key Embedding

The signing key's **public** portion is embedded in the kernel at build time:
1. Private key signs modules during `make modules_install`
2. Public key embedded in kernel's `.builtin_trusted_keys` keyring
3. At runtime, kernel uses embedded public key to verify modules

---

## Trust Chain Diagram

### Complete Boot Chain

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              UEFI FIRMWARE                                   │
│                         Microsoft UEFI CA 2011                              │
│                              in db database                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Verifies Microsoft signature
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FEDORA SHIM 15.8 (BOOTX64.EFI)                         │
│                                                                              │
│  Signed by:  Microsoft UEFI CA 2011                                        │
│  SBAT:       shim,4 (compliant with Microsoft revocation)                  │
│  Embedded:   Fedora Secure Boot CA                                         │
│  Trusts:     Fedora-signed binaries + MOK database                         │
└─────────────────────────────────────────────────────────────────────────────┘
                          │                              │
                          │ Verifies Photon MOK          │ Verifies Fedora CA
                          ▼                              ▼
         ┌────────────────────────────┐    ┌────────────────────────────┐
         │  Photon OS GRUB Stub       │    │   Fedora MokManager        │
         │  (grub.efi/grubx64.efi)    │    │   (MokManager.efi)         │
         │                            │    │                            │
         │  Signed by: Photon OS MOK  │    │  Signed by: Fedora CA      │
         │  Trusted via: MOK          │    │  For: MOK enrollment       │
         └────────────────────────────┘    └────────────────────────────┘
                          │
                          ▼
         ┌────────────────────────────┐
         │   VMware GRUB Real         │
         │   (grubx64_real.efi)       │
         │   Signed by: VMware        │
         └────────────────────────────┘
                          │
                          │ Verifies via shim protocol
                          ▼
         ┌────────────────────────────────────────────────────────────────┐
         │                     LINUX KERNEL                                │
         │                                                                 │
         │  vmlinuz: Signed by VMware (works on all systems)              │
         └────────────────────────────────────────────────────────────────┘
                          │
                          │ Verifies with built-in keyring
                          ▼
         ┌────────────────────────────────────────────────────────────────┐
         │                    KERNEL MODULES (*.ko)                        │
         │                                                                 │
         │  Signed with: Kernel build-time signing key                    │
         │  Verified by: Kernel's .builtin_trusted_keys keyring           │
         └────────────────────────────────────────────────────────────────┘
```

### Signature Verification Points

| Stage | Verifier | Signature | Certificate Source |
|-------|----------|-----------|-------------------|
| Shim | UEFI | Microsoft | UEFI db |
| GRUB Stub | Shim | Photon OS MOK | Shim MOK database |
| GRUB Real | Stub | VMware | Stub chainload |
| MokManager | Shim | Fedora CA | Shim embedded |
| Kernel | Shim | VMware | Shim embedded |
| Modules | Kernel | Build key | Kernel keyring |

---

## Why Fedora Shim + Photon OS GRUB Stub

### The SBAT Problem

Microsoft introduced **SBAT (Secure Boot Advanced Targeting)** to revoke vulnerable shims without blocking all shims. The SBAT revocation list requires `shim,4` or higher.

**Ventoy's SUSE shim has `shim,3`** which is REVOKED - it fails with "SBAT self-check failed: Security Policy Violation".

### Our Solution

We use Fedora shim for SBAT compliance and build a custom Photon OS GRUB stub:

1. **Fedora shim 15.8** (Microsoft-signed, SBAT=shim,4) - passes SBAT check
2. **Fedora MokManager** (signed by Fedora CA) - matches Fedora shim
3. **Custom Photon OS GRUB stub** (signed with Photon OS MOK) - clean trust chain

### Our Implementation

```
/root/hab_keys/
├── shim-fedora.efi       # Fedora's Microsoft-signed shim (SBAT=shim,4)
├── mmx64-fedora.efi      # Fedora's MokManager
├── grub-photon-stub.efi  # Custom GRUB stub signed with Photon OS MOK
├── MOK.key               # Photon OS MOK private key
├── MOK.crt               # Photon OS MOK certificate (PEM)
└── MOK.der               # Photon OS MOK certificate (DER for enrollment)

ISO: /EFI/BOOT/
├── BOOTX64.EFI           # Fedora shim 15.8
├── grub.efi              # Photon OS GRUB stub (MOK-signed)
├── grubx64.efi           # Same as grub.efi
├── grubx64_real.efi      # VMware-signed GRUB real
├── MokManager.efi        # Fedora MokManager
└── ENROLL_THIS_KEY_IN_MOKMANAGER.cer  # Photon OS MOK certificate
```

### Resulting Trust Chain

```
Microsoft UEFI CA 2011
         │
         ▼
    Fedora Shim 15.8 (Microsoft-signed, SBAT=shim,4)
    ┌────┴────┬─────────────┐
    │         │             │
    ▼         ▼             ▼
Photon OS  Fedora's      User's
GRUB Stub  MokManager   MOK keys
(MOK-signed)                │
    │                       ▼
    ▼               Custom binaries
VMware GRUB Real
    │
    ▼
VMware Kernel
```

This enables:
- Direct MOK enrollment from boot menu (blue MokManager screen)
- No need for existing Linux installation
- Works on modern laptops with SBAT-updated firmware
- Passes Microsoft's SBAT revocation checks
- **Clean trust chain using Photon OS certificate (no third-party dependencies)**

### First Boot Process

On first boot with Fedora shim + Photon OS GRUB stub:

1. UEFI loads Fedora shim (Microsoft-signed, SBAT=shim,4) ✓
2. Fedora shim tries to load grub.efi (Photon OS MOK-signed stub)
3. Fedora shim doesn't trust Photon OS MOK cert yet → **Security Violation**
4. Shim automatically loads MokManager.efi (Fedora MokManager)
5. User selects "Enroll key from disk"
6. Navigate to root `/` → select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
7. Confirm enrollment and select **Reboot**
8. Fedora shim now trusts Photon OS GRUB stub via MOK signature ✓
9. Stub chainloads VMware GRUB real, then GRUB loads kernel

**Important**: 
- The certificate file contains the Photon OS MOK certificate (`CN=Photon OS Secure Boot MOK`)
- If certificate enrollment doesn't persist, try **"Enroll hash from disk"** instead

### Two-Stage Boot Menu

The boot process uses a two-stage menu system:

**Stage 1: Stub Menu (5 second timeout)**
This menu appears first, while shim's protocol is still available:
- **Continue to Photon OS Installer** (default) - Proceeds to main menu
- **MokManager - Enroll/Delete MOK Keys** - Access MOK management
- **Reboot** / **Shutdown**

**Stage 2: Main Boot Menu**
This menu appears after the stub timeout or when "Continue" is selected:
- **Install Photon OS (Custom)** - Standard installation
- **Install Photon OS (VMware original)** - Installation with verbose logging
- **Reboot** / **Shutdown**

**Why Two Stages?**
MokManager can only be chainloaded from the stub menu because:
1. At stub level, shim's `shim_lock` protocol is still available
2. After chainloading to VMware's GRUB, shim's protocol is no longer accessible
3. VMware's GRUB requires `shim_lock` to verify binaries before chainloading

### MokManager Menu Options

MokManager provides these built-in options:
- **Enroll key from disk** - Add certificate to MOK database
- **Enroll hash from disk** - Add binary hash to trusted list
- **Delete key** - Remove enrolled certificate
- **Delete hash** - Remove enrolled hash
- **Reboot** / **Power off**

### Rescue Shell for MOK Management

The ISO includes a rescue shell with `mokutil` pre-installed in the initrd:

1. Select **"MOK Management >"** → **"Rescue Shell"** from GRUB
2. System boots to bash prompt
3. Run mokutil commands:
   ```bash
   mokutil --list-enrolled    # List currently enrolled keys
   mokutil --export           # Export enrolled keys to files
   mokutil --delete key.der   # Schedule key for deletion
   reboot                     # Reboot to confirm in MokManager
   ```
