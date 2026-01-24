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

### Boot Chain (ISO Boot)

```
UEFI Firmware
    ↓ (verifies against Microsoft CA in db)
BOOTX64.EFI (SUSE shim, SBAT=shim,4)
    ↓ (verifies against MokList)
grub.efi (Custom GRUB stub, MOK-signed, SBAT=grub,3)
    ↓ (Loads modified grub.cfg with theme)
    ↓ (Presents themed menu, 5 sec timeout)
    ├── 1. Install (Custom MOK) - For Physical Hardware → ks=cdrom:/mok_ks.cfg
    ├── 2. Install (VMware Original) - For VMware VMs  → ks=cdrom:/standard_ks.cfg
    ├── 3. MokManager                                  → Enroll/Delete MOK keys
    ├── 4. Reboot
    └── 5. Shutdown
```

### Boot Chain (Installed System with MOK)

```
UEFI Firmware
    ↓ (verifies against Microsoft CA in db)
shim-signed-mok (SUSE shim bootx64.efi, Microsoft-signed)
    ↓ (verifies against MokList)
grub2-efi-image-mok (Custom GRUB stub grubx64.efi, MOK-signed, NO shim_lock)
    ↓
linux-mok (vmlinuz, MOK-signed)
```

**Important**: The MOK packages install the same SUSE shim and custom GRUB stub used on the ISO, ensuring the installed system boots without policy violations.

### GRUB Modules

The custom GRUB stub includes these modules for proper theming and UUID detection:
- `probe` - Required for UUID detection (`photon.media=UUID=$photondisk`)
- `gfxmenu` - Required for themed menus
- `png`, `jpeg`, `tga` - Required for background images
- `gfxterm_background` - Graphics terminal background support

### Why Custom GRUB Stub?
VMware's original GRUB includes the `shim_lock` verifier module, which enforces strict kernel signature verification via shim. To support custom kernels or installers without replacing the Microsoft-signed shim, we build a custom GRUB stub that:
1. Is signed with our MOK.
2. Contains proper SBAT metadata to satisfy shim policy.
3. Excludes `shim_lock` (or relies on MOK signature).
4. Provides a menu to choose between the custom path and the original VMware path.

### RPM Secure Boot Patcher

The tool includes an integrated RPM patcher that automatically creates MOK-signed variants of boot packages:

| Original Package | MOK Package | Contents |
|-----------------|-------------|----------|
| `shim-signed` | `shim-signed-mok` | SUSE shim (Microsoft-signed) + MokManager |
| `grub2-efi-image` | `grub2-efi-image-mok` | Custom GRUB stub (MOK-signed, no shim_lock) |
| `linux` / `linux-esx` | `linux-mok` | MOK-signed vmlinuz + boot files |

The patcher:
- Discovers packages by file paths (version-agnostic)
- Generates SPEC files with proper Provides/Conflicts
- Handles both `linux` and `linux-esx` kernel flavors
- Integrates built RPMs into the ISO repository

### Kickstart-Based Installation

The ISO uses **kickstart configuration files** instead of initrd patching for robustness:

**`/mok_ks.cfg`** - MOK installation (interactive with enforced packages):
```json
{
    "linux_flavor": "linux-mok",
    "packages": ["minimal", "initramfs", "linux-mok", "grub2-efi-image-mok", "shim-signed-mok"],
    "bootmode": "efi",
    "ui": true
}
```

**`/standard_ks.cfg`** - VMware installation (for VMware VMs):
```json
{
    "linux_flavor": "linux",
    "packages": ["minimal", "initramfs", "linux", "grub2-efi-image", "shim-signed"],
    "bootmode": "efi",
    "ui": true
}
```

Both kickstarts have `"ui": true` which makes the installer **interactive** while still **enforcing the package selection**. This approach is:
- **Version-independent** - Works with any photon-os-installer version
- **More robust** - No fragile sed-based patching
- **VMware-supported** - Uses official kickstart mechanism

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
5.  **Themed Menu**: After reboot, the Photon OS installer menu appears with background picture.
6.  **Install**: Select "Install (Custom MOK)" to begin installation with MOK-signed kernel.

## Troubleshooting

-   **"Policy Violation"**: Means the GRUB stub lacks valid SBAT data. This version fixes this by embedding `sbat.csv`.
-   **"bad shim signature"**: Occurs if you select "VMware Original" with an unsigned kernel. Use "Custom MOK" option.
-   **Laptop Security Dialog**: If your laptop shows a security warning instead of the blue MokManager, disable CSM/Legacy Boot in BIOS.

## Version History

-   **v1.5.0** - RPM signing, SUSE shim in installed system, interactive kickstart:
    - Added `--rpm-signing` option for GPG signing of MOK RPM packages (compliance: NIST 800-53, FedRAMP, EU CRA)
    - Fixed installed system boot: MOK packages now use SUSE shim and custom GRUB stub (no shim_lock)
    - Both install options now use kickstart with `ui:true` for interactive installation with enforced packages
    - Menu renamed: "Install (Custom MOK) - For Physical Hardware" and "Install (VMware Original) - For VMware VMs"
    - Fixed gpg2 symlink creation for rpmsign compatibility on Photon OS
-   **v1.4.0** - Kickstart-based installation, RPM patcher fixes:
    - Replaced initrd patching with kickstart configuration files
    - Fixed RPM SPEC file generation (date format, dist tag, kernel flavor)
    - Added support for linux-esx kernel flavor
-   **v1.3.0** - Added initrd patching for MOK package substitution (deprecated).
-   **v1.2.0** - Integrated RPM Secure Boot Patcher for installed system support.
-   **v1.1.0** - Custom GRUB stub with MOK-signed kernel, SBAT support.
-   **v1.0.0** - Initial C implementation.

## License

GPL-3.0+
