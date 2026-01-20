# Secure Boot Architecture Overview

This is the main architecture document for the HABv4 Secure Boot project. For detailed information, see the documents in the `docs/` directory.

## Quick Links

| Document | Description |
|----------|-------------|
| [BOOT_PROCESS.md](BOOT_PROCESS.md) | Complete boot chain explanation |
| [KEY_MANAGEMENT.md](KEY_MANAGEMENT.md) | Key generation and management |
| [ISO_CREATION.md](ISO_CREATION.md) | ISO creation and USB boot |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions |

---

## Boot Chain Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        UEFI Firmware                                 │
│                   (Microsoft UEFI CA 2011)                          │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│               SUSE Shim 15.8 from Ventoy (BOOTX64.EFI)              │
│          Signed by: Microsoft    SBAT: shim,4 (compliant)           │
│          Embedded: SUSE Linux Enterprise Secure Boot CA             │
└─────────────────────────────────────────────────────────────────────┘
                    │                           │
                    ▼                           ▼
    ┌───────────────────────────┐   ┌───────────────────────────┐
    │   Photon OS GRUB Stub     │   │   SUSE MokManager         │
    │   (grub.efi/grubx64.efi)  │   │   (MokManager.efi)        │
    │   Signed: Photon OS MOK   │   │   Signed: SUSE CA         │
    └───────────────────────────┘   └───────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────┐
    │   VMware GRUB Real        │
    │   (grubx64_real.efi)      │
    │   Signed: VMware, Inc.    │
    └───────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────┐
    │   vmlinuz                 │
    │   (VMware-signed kernel)  │
    └───────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Kernel Modules (*.ko)                           │
│              Signed with build-time signing key                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Note on SBAT Compliance**: Microsoft's SBAT (Secure Boot Advanced Targeting) revocation 
requires `shim,4` or higher. We use SUSE shim from Ventoy 1.1.10 which has SBAT version 
`shim,4` (compliant). The shim looks for MokManager at `\MokManager.efi` (ROOT level).

---

## Key Components

### SUSE Shim from Ventoy

We use **SUSE shim from Ventoy 1.1.10** because:

1. **SUSE shim** (from Ventoy) is SBAT version `shim,4` (compliant with Microsoft's revocation)
2. **Ventoy** uses a well-tested, production-proven Secure Boot implementation
3. **SUSE's MokManager** is signed by SUSE CA and matches the embedded certificate in the shim
4. **SUSE shim looks for `\MokManager.efi`** at ROOT level (not `\mmx64.efi` like Fedora)
5. We build a **custom Photon OS GRUB stub** signed with our own MOK certificate

### Why This Approach?

| Component | Source | SBAT | Purpose |
|-----------|--------|------|---------|
| `BOOTX64.EFI` | SUSE (Ventoy) | shim,4 ✓ | First-stage bootloader (SBAT compliant) |
| `MokManager.efi` | SUSE (Ventoy) | N/A | MOK management (matches SUSE shim) |
| `grub.efi` | Photon OS | N/A | Custom GRUB stub (signed with Photon OS MOK) |
| `grubx64_real.efi` | VMware | N/A | Actual GRUB (chainloaded) |

### Single Kernel

The ISO includes one VMware-signed kernel:

| Kernel | Signer | Use Case |
|--------|--------|----------|
| `vmlinuz` | VMware | All systems (trusted by shim's embedded VMware cert) |

### Important: grub.efi vs grubx64.efi

SUSE shim looks for `grub.efi` or `grubx64.efi` as loader. We provide **both**:
- `grub.efi` - Photon OS stub (MOK-signed) - requires MOK enrollment
- `grubx64.efi` - Same as grub.efi (standard name)
- `grubx64_real.efi` - VMware-signed GRUB real (chainloaded by stub)

---

## Key Hierarchy

```
/root/hab_keys/
├── UEFI Keys (for custom firmware)
│   ├── PK.key/crt/der      # Platform Key
│   ├── KEK.key/crt/der     # Key Exchange Key
│   └── DB.key/crt/der      # Signature Database Key
│
├── MOK (Machine Owner Key)
│   ├── MOK.key             # Private key
│   ├── MOK.crt             # Certificate (PEM)
│   └── MOK.der             # Certificate (for enrollment)
│
├── Module Signing
│   └── kernel_module_signing.pem
│
├── SUSE Components (SBAT Compliant, from Ventoy)
│   ├── shim-suse.efi       # Microsoft-signed SUSE shim (SBAT=shim,4)
│   └── MokManager-suse.efi # SUSE-signed MokManager
│
└── Photon OS GRUB Stub
    └── grub-photon-stub.efi  # Custom GRUB stub (MOK-signed)
```

See [KEY_MANAGEMENT.md](KEY_MANAGEMENT.md) for details.

---

## ISO Structure

```
ISO/
├── mmx64.efi                              # Fedora MokManager (ROOT - for Fedora shim)
├── MokManager.efi                         # Fedora MokManager (ROOT - for SUSE shim)
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer      # Photon OS MOK certificate (ROOT)
├── EFI/BOOT/
│   ├── BOOTX64.EFI                        # Fedora shim (SBAT=shim,4)
│   ├── grub.efi                           # Photon OS GRUB stub (MOK-signed)
│   ├── grubx64.efi                        # Same as grub.efi
│   ├── grubx64_real.efi                   # VMware-signed GRUB
│   ├── MokManager.efi                     # Fedora MokManager (backup)
│   ├── mmx64.efi                          # Fedora MokManager (backup)
│   └── ENROLL_THIS_KEY_IN_MOKMANAGER.cer  # Photon OS MOK certificate
│
├── boot/grub2/
│   ├── efiboot.img     # 16MB EFI partition image
│   └── grub.cfg        # Boot menu
│
└── isolinux/
    ├── vmlinuz         # VMware-signed kernel
    └── initrd.img      # Initial ramdisk
```

**MokManager Placement**: SUSE shim looks for MokManager at `\MokManager.efi` (ROOT level):
- `\MokManager.efi` (ROOT) - **Primary path** for SUSE shim
- `\EFI\BOOT\MokManager.efi` - Fallback location

**efiboot.img contents:**
```
/
├── MokManager.efi                      # SUSE MokManager (ROOT - SUSE shim looks here)
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer   # Photon OS MOK certificate (ROOT)
├── grub/
│   └── grub.cfg                        # Bootstrap config (fallback)
└── EFI/BOOT/
    ├── BOOTX64.EFI                     # SUSE shim (SBAT=shim,4)
    ├── grub.efi                        # Photon OS GRUB stub
    ├── grubx64.efi                     # Same as grub.efi
    ├── grubx64_real.efi                # VMware GRUB
    ├── grub.cfg                        # Bootstrap for grubx64_real
    ├── MokManager.efi                  # SUSE MokManager (fallback)
    └── revocations.efi                 # UEFI revocation list
```

See [ISO_CREATION.md](ISO_CREATION.md) for details.

---

## eFuse USB Dongle (Optional)

For a more realistic HABv4 simulation, the GRUB stub can verify the presence of an eFuse USB dongle before proceeding to boot.

### How It Works

```
GRUB Stub (MOK-signed)
    │
    ├─→ Search for USB with LABEL=EFUSE_SIM
    │
    ├─→ If found: Check for /efuse_sim/srk_fuse.bin
    │       └─→ Valid: "Security Mode: CLOSED" - boot menu shown
    │       └─→ Invalid: "BOOT BLOCKED" - only Retry/Reboot
    │
    └─→ If not found: "BOOT BLOCKED" - only Retry/Reboot

Note: When --efuse-usb is used, boot is ENFORCED. The "Continue to
Photon OS Installer" option only appears when eFuse USB is valid.
```

### Creating eFuse USB Dongle

```bash
# Build keys first (if not already done)
sudo ./HABv4-installer.sh

# Create eFuse USB dongle
sudo ./HABv4-installer.sh --create-efuse-usb=/dev/sdb

# Build ISO with eFuse USB verification
sudo ./HABv4-installer.sh --release=5.0 --build-iso --efuse-usb
```

### USB Dongle Contents

```
USB (LABEL=EFUSE_SIM, FAT32)
└── efuse_sim/
    ├── srk_fuse.bin          # SRK hash (32 bytes)
    ├── sec_config.bin        # Security mode (0x02 = Closed)
    ├── efuse_config.json     # Complete eFuse configuration
    └── srk_pub.pem           # SRK public key (optional)
```

### Comparison to Real Hardware

| Aspect | Real NXP eFuses | USB Dongle Simulation |
|--------|-----------------|----------------------|
| Storage | OTP silicon fuses | FAT32 USB drive |
| Permanence | Burned forever | Can be copied/modified |
| Verification | Hardware Boot ROM | GRUB stub config |
| Cloning | Impossible | Trivially copied |
| Use Case | Production security | Development/demo |

---

## Modular Scripts

```
/root/
├── HABv4-installer.sh      # Main installer
└── hab_scripts/
    ├── hab_lib.sh          # Common library
    ├── hab_keys.sh         # Key management
    └── hab_iso.sh          # ISO operations
```

### Quick Usage

```bash
# Generate all keys
./hab_scripts/hab_keys.sh generate

# Fix existing ISO for Secure Boot
./hab_scripts/hab_iso.sh fix /path/to/photon.iso

# Verify ISO structure
./hab_scripts/hab_iso.sh verify /path/to/photon-secureboot.iso

# Write to USB
./hab_scripts/hab_iso.sh write /path/to/photon-secureboot.iso /dev/sdX
```

---

## Common Issues Quick Reference

| Error | Cause | Fix |
|-------|-------|-----|
| SBAT self-check failed | Shim SBAT version revoked | Use SUSE shim from Ventoy 1.1.10 (SBAT=shim,4) |
| Security Violation (first boot) | MOK not enrolled | Enroll `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` from root `/` |
| Enrollment doesn't persist | Firmware issue | Try "Enroll hash from disk" for `grub.efi` |
| Certificate mismatch | Wrong cert enrolled | Verify cert shows `CN=Photon OS Secure Boot MOK` |
| MokManager.efi Not Found | Missing from efiboot.img | Rebuild with latest script |
| Certificate not visible | File missing | Navigate to root `/` in MokManager |
| EFI USB boot failed | ISO not hybrid | Use xorriso with isohybrid options |
| bad shim signature | Shim/MokManager mismatch | Use matching pair (SUSE shim + SUSE MokManager from Ventoy) |
| can't find command 'reboot' | VMware GRUB missing module | Use "UEFI Firmware Settings" or Ctrl+Alt+Del |
| grubx64_real.efi not found | GRUB stub search failed | Rebuild with latest script (includes search module) |

**Two-Stage Boot Menu**:
- Stage 1 (Stub, 5 sec): Continue / MokManager / Reboot / Shutdown
- Stage 2 (Main): Install Photon OS (Custom/VMware original) / UEFI Firmware Settings

Note: MokManager only works from Stage 1 (shim_lock protocol available). VMware's GRUB doesn't have reboot/halt commands built-in.

**MokManager Menu Options** (built-in):
- Enroll key from disk / Enroll hash from disk
- Delete key / Delete hash  
- Reboot / Power off

**From Installed System** (mokutil):
```bash
mokutil --list-enrolled    # List enrolled keys
mokutil --delete key.der   # Schedule deletion (reboot required)
```

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for complete guide.

---

## Creating Secure Boot ISO

### One Command

```bash
./HABv4-installer.sh --release=5.0 --build-iso
```

### Manual Steps

1. Generate keys: `./hab_scripts/hab_keys.sh generate`
2. Fix ISO: `./hab_scripts/hab_iso.sh fix original.iso`
3. Write USB: `dd if=photon-secureboot.iso of=/dev/sdX bs=4M status=progress`

---

## External References

- [UEFI Secure Boot Specification](https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
- [Shim Bootloader](https://github.com/rhboot/shim)
- [Ventoy Secure Boot](https://www.ventoy.net/en/doc_secure.html)
- [NXP HABv4 Documentation](https://www.nxp.com/docs/en/application-note/AN4581.pdf)
