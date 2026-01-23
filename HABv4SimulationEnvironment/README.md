# HABv4 Secure Boot Simulation Environment

UEFI Secure Boot implementation for Photon OS with SBAT enforcement support.

## Overview

This environment provides tools to create Secure Boot enabled ISOs that work on modern UEFI systems with SBAT (Secure Boot Advanced Targeting) enforcement. The solution uses:

- **SUSE shim** (Microsoft-signed, SBAT compliant)
- **Custom GRUB Stub** (MOK-signed, SBAT compliant, with fallback menu)
- **MOK-signed Kernel** (bypasses shim_lock verification)
- **MOK (Machine Owner Key)** for custom signing

## Quick Start

### Build Environment

```bash
cd photonos-scripts/HABv4SimulationEnvironment/src
make
```

### Create Secure Boot ISO

```bash
# Simplest usage: Generate keys, setup eFuse, build ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build ISO and create eFuse USB dongle (with auto-confirm)
./PhotonOS-HABv4Emulation-ISOCreator --release 5.0 --build-iso --setup-efuse --create-efuse-usb=/dev/sdd -y

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

## Architecture

### Boot Chain

```
UEFI Firmware
    ↓ (verifies against Microsoft CA in db)
BOOTX64.EFI (SUSE shim, SBAT=shim,4)
    ↓ (verifies against MokList)
grub.efi (Custom GRUB stub, MOK-signed, SBAT=grub,3)
    ↓ (Presents 5-second stub menu)
    ├── 1. Custom MOK (Default) → Original grub.cfg (themed) → MOK-signed kernel
    └── 2. VMware Original      → Chains to VMware GRUB (shim_lock enabled)
```

### Why Custom GRUB Stub?
VMware's original GRUB includes the `shim_lock` verifier module, which enforces strict kernel signature verification via shim. To support custom kernels or installers without replacing the Microsoft-signed shim, we build a custom GRUB stub that:
1. Is signed with our MOK.
2. Contains proper SBAT metadata to satisfy shim policy.
3. Excludes `shim_lock` (or relies on MOK signature).
4. Provides a menu to choose between the custom path and the original VMware path.

## Command Line Options

### All Parameters

| Option | Long Form | Default | Description |
|--------|-----------|---------|-------------|
| `-r` | `--release=VERSION` | `5.0` | Photon OS version: 4.0, 5.0, 6.0 |
| `-b` | `--build-iso` | Off | Build Secure Boot ISO |
| `-g` | `--generate-keys` | Auto | Generate cryptographic keys |
| `-s` | `--setup-efuse` | Auto | Setup eFuse simulation |
| `-u` | `--create-efuse-usb=DEV` | — | Create eFuse USB dongle on device |
| `-E` | `--efuse-usb` | Off | Enable eFuse USB verification in GRUB |
| `-D` | `--diagnose=ISO` | — | Diagnose an existing ISO |
| `-c` | `--clean` | Off | Clean up all artifacts |
| `-v` | `--verbose` | Off | Verbose output |
| `-y` | `--yes` | Off | Auto-confirm destructive operations (e.g., erase USB) |
| `-h` | `--help` | — | Show help |

**Note:** The tool embeds required SUSE shim components (`shim-suse.efi`, `MokManager.efi`) and extracts them automatically. No internet connection is required.

## First Boot Procedure

1.  **Boot from ISO** with Secure Boot enabled.
2.  **Blue Screen**: You will see a blue "Shim UEFI key management" screen (MokManager).
3.  **Enroll Key**: Select "Enroll key from disk" -> Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`.
4.  **Reboot**: Confirm enrollment and reboot.
5.  **Stub Menu**: After reboot, a 6-option menu appears (5 sec timeout).
6.  **Install**: Select "1. Continue to Photon OS Installer (Custom MOK)".
7.  **Themed Menu**: The original Photon OS installer menu appears (with background).
8.  **Install**: Select "Install" to begin installation.

## Troubleshooting

-   **"Policy Violation"**: Means the GRUB stub lacks valid SBAT data. This version fixes this by embedding `sbat.csv`.
-   **"bad shim signature"**: Occurs if you select "VMware Original" with an unsigned kernel. Use "Custom MOK" option.
-   **Laptop Security Dialog**: If your laptop shows a security warning instead of the blue MokManager, disable CSM/Legacy Boot in BIOS.

## Version History

-   **v1.5.0** - Fixed USB boot menu display, added `-y` flag for auto-confirm.
-   **v1.4.0** - Embedded SUSE shim components, removed manual download, SBAT support added.
-   **v1.3.0** - Custom GRUB stub with MOK-signed kernel approach.
-   **v1.1.0** - Initial C implementation.

## License

GPL-3.0+
