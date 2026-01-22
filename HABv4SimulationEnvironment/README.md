# HABv4 Secure Boot Simulation Environment

UEFI Secure Boot implementation for Photon OS with SBAT enforcement support.

## Overview

This environment provides tools to create Secure Boot enabled ISOs that work on modern UEFI systems with SBAT (Secure Boot Advanced Targeting) enforcement. The solution uses:

- **SUSE shim** (Microsoft-signed, SBAT compliant)
- **HAB PreLoader** (based on efitools library, installs permissive security policy)
- **VMware GRUB** (official signed bootloader)
- **MOK (Machine Owner Key)** for custom signing

## Quick Start

### Clone and Build

```bash
git clone https://github.com/dcasota/photonos-scripts.git
cd photonos-scripts/HABv4SimulationEnvironment/src
make

# Default setup (no parameters): generates keys, eFuse, downloads Ventoy
./PhotonOS-HABv4Emulation-ISOCreator

# Build Secure Boot ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Full setup + build ISO
./PhotonOS-HABv4Emulation-ISOCreator -g -s -d -b
```

## Command Line Options

### All Parameters

| Option | Long Form | Default | Required | Description |
|--------|-----------|---------|----------|-------------|
| `-r` | `--release=VERSION` | `5.0` | No | Photon OS version: 4.0, 5.0, 6.0 |
| `-i` | `--input=ISO` | Auto-detect | No | Input ISO file path |
| `-o` | `--output=ISO` | `<input>-secureboot.iso` | No | Output ISO file path |
| `-k` | `--keys-dir=DIR` | `/root/hab_keys` | No | Keys directory |
| `-e` | `--efuse-dir=DIR` | `/root/efuse_sim` | No | eFuse simulation directory |
| `-m` | `--mok-days=DAYS` | `180` | No | MOK certificate validity (1-3650 days) |
| `-b` | `--build-iso` | Off | No | Build Secure Boot ISO |
| `-g` | `--generate-keys` | Auto* | No | Generate cryptographic keys |
| `-s` | `--setup-efuse` | Auto* | No | Setup eFuse simulation |
| `-d` | `--download-ventoy` | Auto* | No | Download Ventoy components |
| `-u` | `--create-efuse-usb=DEV` | — | No | Create eFuse USB dongle on device |
| `-E` | `--efuse-usb` | Off | No | Enable eFuse USB verification in GRUB |
| `-F` | `--full-kernel-build` | Off | No | Build kernel from source (hours) |
| `-V` | `--use-ventoy` | Off | No | Use Ventoy PreLoader instead of HAB |
| `-S` | `--skip-build` | Off | No | Skip HAB PreLoader build |
| `-c` | `--clean` | Off | No | Clean up all artifacts |
| `-v` | `--verbose` | Off | No | Verbose output |
| `-h` | `--help` | — | No | Show help |

*Auto = When no action flags are specified, `-g -s -d` are enabled by default.

### Default Behavior (No Parameters)

Running the tool without any parameters is equivalent to:
```bash
./PhotonOS-HABv4Emulation-ISOCreator -g -s -d
```

This performs:
1. Generate all cryptographic keys (PK, KEK, DB, MOK, SRK, CSF, IMG)
2. Setup eFuse simulation files
3. Download SUSE shim and MokManager from Ventoy

**Note:** ISO is NOT built by default. Use `-b` to build an ISO.

## Examples

```bash
# Default setup (keys + eFuse + Ventoy download)
./PhotonOS-HABv4Emulation-ISOCreator

# Build Secure Boot ISO for Photon OS 5.0
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build for Photon OS 4.0
./PhotonOS-HABv4Emulation-ISOCreator -r 4.0 -b

# Specify input/output ISO
./PhotonOS-HABv4Emulation-ISOCreator -i photon.iso -o photon-sb.iso -b

# Build ISO with eFuse USB dongle verification
./PhotonOS-HABv4Emulation-ISOCreator -E -b

# Create eFuse USB dongle
./PhotonOS-HABv4Emulation-ISOCreator -u /dev/sdb

# Full kernel build (takes hours)
./PhotonOS-HABv4Emulation-ISOCreator -F

# Custom MOK validity (365 days)
./PhotonOS-HABv4Emulation-ISOCreator -m 365 -g

# Cleanup all artifacts
./PhotonOS-HABv4Emulation-ISOCreator -c

# Verbose output
./PhotonOS-HABv4Emulation-ISOCreator -v -b
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

## eFuse USB Mode

When built with `-E` flag, the ISO requires an eFuse USB dongle to boot:

1. Create the dongle: `./PhotonOS-HABv4Emulation-ISOCreator -u /dev/sdb`
2. Build ISO with eFuse mode: `./PhotonOS-HABv4Emulation-ISOCreator -E -b`
3. Insert USB dongle (label: `EFUSE_SIM`) before booting
4. Without dongle, boot is blocked with "Retry" option

## Full Kernel Build

The `-F` flag enables building the Linux kernel from source:

```bash
./PhotonOS-HABv4Emulation-ISOCreator -F
```

**Warning:** This takes several hours and includes:
- Downloading kernel source
- Configuring with Secure Boot options
- Building kernel and modules
- Signing with MOK key

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
cd photonos-scripts/HABv4SimulationEnvironment/src
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
| MOK.* | Machine Owner Key (for signing, default 180 days) |
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

## Version History

- **v1.1.0** - Restored `--efuse-usb` and `--full-kernel-build`, fixed MOK default to 180 days
- **v1.0.0** - Initial C implementation replacing bash script

## License

- PhotonOS-HABv4Emulation-ISOCreator: GPL-3.0+
- HAB PreLoader: GPL-3.0+ (based on efitools)
- efitools: GPL-2.0+
