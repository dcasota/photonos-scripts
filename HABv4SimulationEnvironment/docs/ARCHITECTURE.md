# Secure Boot Architecture Overview

This document explains the architecture of the HABv4 Secure Boot Simulation Environment.

## Table of Contents

1. [The Problem](#the-problem)
2. [Our Solution](#our-solution)
3. [Boot Chain Overview](#boot-chain-overview)
4. [Key Components](#key-components)
5. [Package Structure](#package-structure)
6. [Directory Layout](#directory-layout)
7. [Related Documentation](#related-documentation)

---

## The Problem

**Photon OS ISOs don't boot on physical hardware with Secure Boot enabled.**

Here's why:

1. **UEFI Secure Boot** requires all boot code to be cryptographically signed
2. **VMware's shim** (first-stage bootloader) includes `shim_lock` verification
3. **`shim_lock`** calls shim's `Verify()` function for every binary loaded
4. **Custom or unsigned kernels** fail this verification
5. **Result**: "bad shim signature" error on consumer laptops

```
Original Photon OS Boot (FAILS on Secure Boot):

UEFI Firmware
    ↓ verifies (Microsoft CA in db) ✓
VMware shim (bootx64.efi)
    ↓ has shim_lock module
VMware GRUB (grubx64.efi)
    ↓ calls shim_lock Verify()
Kernel (vmlinuz)
    ↓ signature check fails ✗
"bad shim signature" ERROR
```

---

## Our Solution

We replace the boot chain with components that work together:

1. **SUSE shim**: Microsoft-signed, SBAT compliant, no `shim_lock` enforcement
2. **Custom GRUB stub**: MOK-signed, built without `shim_lock` module
3. **MOK-signed kernel**: Signed with our Machine Owner Key
4. **MOK packages**: Install these components to the target system

```
HABv4 Modified Boot (WORKS on Secure Boot):

UEFI Firmware
    ↓ verifies (Microsoft CA in db) ✓
SUSE shim (BOOTX64.EFI)
    ↓ verifies (MokList) ✓
Custom GRUB stub (grub.efi)
    ↓ MOK-signed, no shim_lock ✓
Kernel (vmlinuz)
    ↓ boots successfully ✓
Photon OS Installer
```

---

## Boot Chain Overview

### ISO Boot (Installation)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        UEFI Firmware                                 │
│                   (Microsoft UEFI CA 2011 in db)                    │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼ verifies Microsoft signature
┌─────────────────────────────────────────────────────────────────────┐
│                     SUSE Shim (BOOTX64.EFI)                         │
│          Signed by: Microsoft    SBAT: shim,4 (compliant)           │
│          Source: Embedded in tool (from Ventoy 1.1.10)              │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼ verifies MOK signature (MokList)
┌─────────────────────────────────────────────────────────────────────┐
│                  Custom GRUB Stub (grub.efi)                        │
│          Signed by: Photon OS MOK    SBAT: grub,3                   │
│          Built with: grub2-mkimage (no shim_lock module)            │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼ loads grub.cfg, presents menu
┌─────────────────────────────────────────────────────────────────────┐
│                         Boot Menu                                    │
│  1. Install (Custom MOK) - For Physical Hardware   [default]        │
│  2. Install (VMware Original) - For VMware VMs                      │
│  3. MokManager - Enroll/Delete MOK Keys                             │
│  4. Reboot into UEFI Firmware Settings                              │
│  5. Reboot                                                          │
│  6. Shutdown                                                        │
└─────────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
          Custom MOK Path           VMware Original Path
          (Physical HW)             (VMware VMs)
                    │                       │
                    ▼                       ▼
            MOK-signed vmlinuz      Chainload grubx64_real.efi
            + initrd                (VMware's GRUB)
            + ks=cdrom:/mok_ks.cfg  + ks=cdrom:/standard_ks.cfg
```

### Installed System Boot (Post-Installation)

**MOK Path (Physical Hardware):**
```
UEFI Firmware
    ↓
shim-signed-mok (SUSE shim + MokManager)
    ↓
grub2-efi-image-mok (Custom GRUB stub, MOK-signed)
    ↓
linux-mok (MOK-signed vmlinuz)
    ↓
Photon OS (running)
```

**Standard Path (VMware VMs):**
```
UEFI Firmware
    ↓
shim-signed (VMware shim)
    ↓
grub2-efi-image (VMware GRUB with shim_lock)
    ↓
linux (unsigned vmlinuz)
    ↓
Photon OS (running)
⚠ Will fail on physical hardware with Secure Boot
```

---

## Key Components

### SUSE Shim

| Property | Value |
|----------|-------|
| Source | Ventoy 1.1.10 |
| Signer | Microsoft Corporation UEFI CA 2011 |
| SBAT Version | shim,4 (compliant with current revocation) |
| Size | ~965 KB |
| Embedded Cert | SUSE Linux Enterprise Secure Boot CA |
| MokManager Path | Looks for `\MokManager.efi` at root |

**Why SUSE shim?**
- Microsoft-signed (trusted by all UEFI firmware)
- SBAT version 4 (passes Microsoft's revocation checks)
- Doesn't enforce `shim_lock` on next-stage loader
- Well-tested (used by Ventoy for years)

### Custom GRUB Stub

| Property | Value |
|----------|-------|
| Source | Built with grub2-mkimage |
| Signer | Photon OS MOK |
| Size | ~2 MB |
| shim_lock | **Not included** |
| SBAT | grub,3 (embedded in binary) |

**Modules included:**
- Core: `search`, `configfile`, `linux`, `initrd`, `chain`
- Filesystem: `fat`, `iso9660`, `ext2`, `part_gpt`, `part_msdos`
- Graphics: `gfxterm`, `gfxmenu`, `png`, `jpeg`, `tga`, `gfxterm_background`
- Detection: `probe` (for UUID), `efi_gop`, `efi_uga`
- Commands: `echo`, `reboot`, `halt`, `test`, `true`

**Why custom GRUB?**
- VMware's GRUB has `shim_lock` module compiled in
- `shim_lock` enforces strict signature verification
- Custom GRUB skips this, relying on MOK signature alone
- Still verified by shim (MOK signature), maintaining security

### MokManager

| Property | Value |
|----------|-------|
| Source | SUSE (from Ventoy) |
| Signer | SUSE Linux Enterprise Secure Boot CA |
| Size | ~852 KB |
| Location | Root of ISO (`\MokManager.efi`) |

**Functions:**
- Enroll key from disk
- Enroll hash from disk
- Delete key/hash
- Reset MOK
- Reboot / Power off

### Machine Owner Key (MOK)

| Property | Value |
|----------|-------|
| Algorithm | RSA 2048-bit |
| Validity | 180 days (configurable) |
| Subject | CN=Photon OS Secure Boot MOK |
| Storage | `/root/hab_keys/MOK.key`, `MOK.crt`, `MOK.der` |

**What we sign with MOK:**
- Custom GRUB stub (`grub.efi`)
- Kernel (`vmlinuz`)
- MokManager (if building custom)

---

## Package Structure

### Original vs MOK Packages

| Original | MOK Variant | Difference |
|----------|-------------|------------|
| `shim-signed` | `shim-signed-mok` | SUSE shim + MokManager (not VMware shim) |
| `grub2-efi-image` | `grub2-efi-image-mok` | Custom GRUB stub (no shim_lock) |
| `linux` | `linux-mok` | MOK-signed vmlinuz |
| `linux-esx` | `linux-mok` | MOK-signed vmlinuz (ESX flavor) |

### Package Relationships

```
shim-signed-mok:
  Provides: shim-signed
  Conflicts: shim-signed
  Contains: bootx64.efi (SUSE), mmx64.efi (MokManager)

grub2-efi-image-mok:
  Provides: grub2-efi-image
  Conflicts: grub2-efi-image
  Contains: grubx64.efi (Custom GRUB stub, MOK-signed)

linux-mok:
  Provides: linux
  Conflicts: linux, linux-esx
  Contains: vmlinuz-* (MOK-signed), config-*, System.map-*
```

### Kickstart Package Selection

**MOK Installation (`mok_ks.cfg`):**
```json
{
    "linux_flavor": "linux-mok",
    "packages": ["minimal", "initramfs", "linux-mok", 
                 "grub2-efi-image-mok", "shim-signed-mok"],
    "bootmode": "efi",
    "ui": true
}
```

**Standard Installation (`standard_ks.cfg`):**
```json
{
    "linux_flavor": "linux",
    "packages": ["minimal", "initramfs", "linux", 
                 "grub2-efi-image", "shim-signed"],
    "bootmode": "efi",
    "ui": true
}
```

---

## Directory Layout

### Build Environment

```
/root/
├── hab_keys/                    # Signing keys
│   ├── MOK.key                  # MOK private key
│   ├── MOK.crt                  # MOK certificate (PEM)
│   ├── MOK.der                  # MOK certificate (DER)
│   ├── kernel_module_signing.pem # Kernel module signing
│   ├── shim-suse.efi            # Extracted SUSE shim
│   ├── MokManager-suse.efi      # Extracted MokManager
│   └── grub-photon-stub.efi     # Built GRUB stub (MOK-signed)
│
├── efuse_sim/                   # eFuse simulation (optional)
│   ├── srk_fuse.bin             # SRK hash
│   └── sec_config.bin           # Security mode
│
├── 5.0/                         # Photon OS build tree
│   ├── stage/
│   │   ├── RPMS/x86_64/         # Built RPMs
│   │   └── SOURCES/             # Kernel source tarballs
│   └── SPECS/
│       └── linux/               # Kernel config files
│
└── photon-5.0-xxx.iso           # Input ISO (downloaded)
```

### ISO Structure

```
photon-5.0-xxx-secureboot.iso
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer  # MOK certificate for enrollment
├── MokManager.efi                      # SUSE MokManager (root)
├── mok_ks.cfg                         # MOK kickstart
├── standard_ks.cfg                    # Standard kickstart
│
├── EFI/BOOT/
│   ├── BOOTX64.EFI                    # SUSE shim
│   ├── grub.efi                       # Custom GRUB stub
│   ├── grubx64.efi                    # Same as grub.efi
│   ├── grubx64_real.efi               # VMware GRUB (for standard path)
│   └── MokManager.efi                 # Backup location
│
├── boot/grub2/
│   ├── efiboot.img                    # EFI System Partition (16MB FAT)
│   ├── grub.cfg                       # Boot menu configuration
│   └── themes/                        # Photon OS theme
│
├── RPMS/x86_64/                       # All RPMs (original + MOK)
│   ├── shim-signed-mok-*.rpm
│   ├── grub2-efi-image-mok-*.rpm
│   ├── linux-mok-*.rpm
│   └── ... (original packages)
│
└── isolinux/                          # BIOS/Legacy boot
    ├── isolinux.bin
    ├── vmlinuz                        # MOK-signed kernel
    └── initrd.img                     # Patched initrd
```

### efiboot.img Contents

```
efiboot.img (FAT12, 16MB)
├── MokManager.efi                     # SUSE MokManager (root)
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer  # MOK certificate
│
└── EFI/BOOT/
    ├── BOOTX64.EFI                    # SUSE shim
    ├── grub.efi                       # Custom GRUB stub
    ├── grubx64.efi                    # Same as grub.efi
    ├── grubx64_real.efi               # VMware GRUB
    ├── MokManager.efi                 # Backup
    └── grub.cfg                       # Bootstrap config
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [BOOT_PROCESS.md](BOOT_PROCESS.md) | Detailed boot sequence |
| [KEY_MANAGEMENT.md](KEY_MANAGEMENT.md) | Key generation and MOK enrollment |
| [ISO_CREATION.md](ISO_CREATION.md) | ISO creation process |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions |
| [SIGNING_OVERVIEW.md](SIGNING_OVERVIEW.md) | Secure Boot vs RPM signing |
| [DROID_SKILL_GUIDE.md](DROID_SKILL_GUIDE.md) | Using the Droid AI skill |

---

## Security Considerations

### What's Verified

| Stage | Verifier | Key Source |
|-------|----------|------------|
| Shim | UEFI Firmware | Microsoft CA (in db) |
| GRUB | Shim | MokList (user-enrolled) |
| Kernel | None (shim_lock disabled) | N/A |

### Trade-offs

**Security**: The kernel is NOT verified by shim after our modification. However:
- The kernel IS signed with MOK (can be verified manually)
- The kernel came from our ISO (chain of custody)
- This is the same trust model as most Linux distributions

**Compatibility**: Works on any UEFI system with:
- Microsoft UEFI CA 2011 in db (nearly universal)
- MokList support (requires shim)
- No additional firmware configuration required

### Recommendations

1. **Keep MOK keys secure**: Private key should not be distributed
2. **Short validity period**: Default 180 days reduces exposure window
3. **Use RPM signing**: Enable `--rpm-signing` for package integrity
4. **Physical security**: First boot requires physical presence for MOK enrollment
