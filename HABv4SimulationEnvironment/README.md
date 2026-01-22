# HABv4 Secure Boot Simulation Environment

UEFI Secure Boot implementation for Photon OS with SBAT enforcement support.

## Overview

This environment provides tools to create Secure Boot enabled ISOs that work on modern UEFI systems with SBAT (Secure Boot Advanced Targeting) enforcement. The solution uses:

- **SUSE shim** (Microsoft-signed, SBAT compliant)
- **HAB PreLoader** (based on efitools library, installs permissive security policy)
- **VMware GRUB** (official signed bootloader)
- **MOK (Machine Owner Key)** for custom signing

## Quick Start

### Build and Run

```bash
cd src
make

# Full setup (keys, eFuse, Ventoy components)
./PhotonOS-HABv4Emulation-ISOCreator -g -s -d

# Build Secure Boot ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Or combined
./PhotonOS-HABv4Emulation-ISOCreator -g -s -d -b
```

### Command Line Options

| Option | Long Form | Description |
|--------|-----------|-------------|
| `-r` | `--release=VERSION` | Photon OS version: 4.0, 5.0, 6.0 (default: 5.0) |
| `-i` | `--input=ISO` | Input ISO file |
| `-o` | `--output=ISO` | Output ISO file |
| `-k` | `--keys-dir=DIR` | Keys directory (default: /root/hab_keys) |
| `-e` | `--efuse-dir=DIR` | eFuse directory (default: /root/efuse_sim) |
| `-m` | `--mok-days=DAYS` | MOK certificate validity (default: 3650) |
| `-b` | `--build-iso` | Build Secure Boot ISO |
| `-g` | `--generate-keys` | Generate cryptographic keys |
| `-s` | `--setup-efuse` | Setup eFuse simulation |
| `-d` | `--download-ventoy` | Download Ventoy components |
| `-u` | `--create-efuse-usb=DEV` | Create eFuse USB dongle |
| `-V` | `--use-ventoy` | Use Ventoy PreLoader instead of HAB |
| `-S` | `--skip-build` | Skip HAB PreLoader build |
| `-c` | `--clean` | Clean up all artifacts |
| `-v` | `--verbose` | Verbose output |
| `-h` | `--help` | Show help |

### Examples

```bash
# Setup environment
./PhotonOS-HABv4Emulation-ISOCreator -g -s -d

# Build Secure Boot ISO for Photon OS 5.0
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build for Photon OS 4.0
./PhotonOS-HABv4Emulation-ISOCreator -r 4.0 -b

# Specify input/output ISO
./PhotonOS-HABv4Emulation-ISOCreator -i photon.iso -o photon-sb.iso -b

# Create eFuse USB dongle
./PhotonOS-HABv4Emulation-ISOCreator -u /dev/sdb

# Cleanup
./PhotonOS-HABv4Emulation-ISOCreator -c
```

## Directory Structure

```
HABv4SimulationEnvironment/
├── README.md                      # This file
├── docs/                          # Documentation
│   ├── ARCHITECTURE.md            # System architecture
│   ├── BOOT_PROCESS.md            # Boot flow explanation
│   ├── ISO_CREATION.md            # ISO creation guide
│   ├── KEY_MANAGEMENT.md          # Key generation & management
│   └── TROUBLESHOOTING.md         # Common issues & solutions
└── src/
    ├── Makefile                   # Main build file
    ├── PhotonOS-HABv4Emulation-ISOCreator.c  # Main tool source
    └── hab/                       # HABv4 components
        ├── BUILD.md               # Build instructions
        ├── build.sh               # HAB PreLoader build script
        ├── preloader/             # HAB PreLoader
        │   ├── HabPreLoader.c     # Main source (uses efitools)
        │   ├── hashlist.h         # Hash list header
        │   └── Makefile
        └── iso/                   # ISO builder
            ├── hab_iso.c          # ISO manipulation tool
            └── Makefile
```

## Boot Chain

```
UEFI Firmware
    ↓ (verifies against Microsoft CA in db)
BOOTX64.EFI (SUSE shim)
    ↓ (verifies against MokList)
grub.efi (HAB PreLoader)
    ↓ (installs permissive security policy)
grubx64_real.efi (VMware GRUB)
    ↓
Linux Kernel
```

## First Boot

1. Boot from ISO with Secure Boot enabled
2. Security violation occurs (MOK not enrolled)
3. MokManager launches automatically
4. Select "Enroll key from disk"
5. Navigate to `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm and reboot

## Building from Source

### Prerequisites

```bash
# Install dependencies (Photon OS)
tdnf install -y gcc make gnu-efi-devel sbsigntools xorriso syslinux dosfstools wget git

# For HAB PreLoader (optional)
mkdir -p /root/src/kernel.org
cd /root/src/kernel.org
git clone git://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git
```

### Compile

```bash
cd src
make              # Build main tool + hab_iso
make install      # Install to /usr/local/bin
make hab-preloader  # Build HAB PreLoader (requires efitools)
```

## Generated Keys

The tool generates these keys in the keys directory:

| Key | Purpose |
|-----|---------|
| PK.* | Platform Key |
| KEK.* | Key Exchange Key |
| DB.* | Signature Database Key |
| MOK.* | Machine Owner Key (for signing) |
| srk.* | Super Root Key (HAB simulation) |
| csf.* | Command Sequence File Key |
| img.* | Image Signing Key |
| kernel_module_signing.pem | Kernel module signing |

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System design
- [Boot Process](docs/BOOT_PROCESS.md) - Detailed boot flow
- [ISO Creation](docs/ISO_CREATION.md) - Creating Secure Boot ISOs
- [Key Management](docs/KEY_MANAGEMENT.md) - Key generation
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues

## License

- PhotonOS-HABv4Emulation-ISOCreator: GPL-3.0+
- HAB PreLoader: GPL-3.0+ (based on efitools)
- efitools: GPL-2.0+
