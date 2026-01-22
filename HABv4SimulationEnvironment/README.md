# HABv4 Secure Boot Simulation Environment

UEFI Secure Boot implementation for Photon OS with SBAT enforcement support.

## Overview

This environment provides tools to create Secure Boot enabled ISOs that work on modern UEFI systems with SBAT (Secure Boot Advanced Targeting) enforcement. The solution uses:

- **SUSE shim** (Microsoft-signed, SBAT compliant)
- **HAB PreLoader** (based on efitools library, installs permissive security policy)
- **VMware GRUB** (official signed bootloader)
- **MOK (Machine Owner Key)** for custom signing

## Quick Start

### 1. Install Dependencies
```bash
# Photon OS
tdnf install -y gnu-efi-devel sbsigntools xorriso syslinux dosfstools gcc make git

# Clone efitools (required for building)
mkdir -p /root/src/kernel.org
cd /root/src/kernel.org
git clone git://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git
```

### 2. Generate MOK Key
```bash
mkdir -p /root/hab_keys
cd /root/hab_keys

# Generate key pair
openssl genrsa -out MOK.key 2048
openssl req -new -x509 -sha256 -key MOK.key -out MOK.crt -days 3650 \
    -subj "/CN=HABv4 Secure Boot MOK/O=Organization/C=US"
openssl x509 -in MOK.crt -outform DER -out MOK.der
```

### 3. Download Ventoy Binaries
```bash
cd /tmp
wget https://github.com/ventoy/Ventoy/releases/download/v1.1.10/ventoy-1.1.10-linux.tar.gz
tar xzf ventoy-1.1.10-linux.tar.gz
cp ventoy-1.1.10/tool/x86_64/BOOTX64.EFI /root/hab_keys/shim-suse.efi
cp ventoy-1.1.10/tool/x86_64/MokManager.efi /root/hab_keys/MokManager-suse.efi
```

### 4. Build HAB PreLoader
```bash
cd /path/to/HABv4SimulationEnvironment/src/hab
./build.sh all      # Build efitools library + HAB PreLoader
./build.sh sign     # Sign with MOK
```

### 5. Create Secure Boot ISO
```bash
cd /path/to/HABv4SimulationEnvironment/src/hab/iso
make
./hab_iso /path/to/photon.iso /path/to/photon-secureboot.iso
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
    └── hab/                       # HABv4 source code
        ├── BUILD.md               # Build instructions
        ├── build.sh               # Build script
        ├── preloader/             # HAB PreLoader
        │   ├── HabPreLoader.c     # Main source (uses efitools)
        │   ├── hashlist.h         # Hash list header
        │   └── Makefile
        └── iso/                   # ISO builder
            ├── hab_iso.c          # C-based ISO builder
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

## Requirements

| Package | Purpose |
|---------|---------|
| gnu-efi-devel | EFI development headers |
| sbsigntools | Binary signing (sbsign, sbverify) |
| xorriso | ISO manipulation |
| syslinux | Hybrid ISO creation |
| dosfstools | FAT filesystem tools |
| gcc, make | Compilation |
| git | Clone efitools source |

## External Dependencies

The build requires these external sources:
- **efitools**: `git://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git`
- **Ventoy binaries**: SUSE shim and MokManager from Ventoy release

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System design
- [Boot Process](docs/BOOT_PROCESS.md) - Detailed boot flow
- [ISO Creation](docs/ISO_CREATION.md) - Creating Secure Boot ISOs
- [Key Management](docs/KEY_MANAGEMENT.md) - Key generation
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues

## License

- HAB PreLoader: GPL-3.0+ (based on efitools)
- efitools: GPL-2.0+
