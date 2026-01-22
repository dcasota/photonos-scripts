# HABv4 Build Instructions

## Quick Start

```bash
cd /root/src/hab
./build.sh all      # Build everything
./build.sh sign     # Sign with MOK
./build.sh ventoy   # Copy Ventoy binaries
```

## Prerequisites

```bash
# Photon OS
tdnf install -y gnu-efi-devel sbsigntools xorriso syslinux dosfstools gcc make

# Check dependencies
./build.sh deps
```

## Build Targets

| Target | Description |
|--------|-------------|
| `all` | Build efitools library + HAB PreLoader |
| `clean` | Remove all build artifacts |
| `deps` | Check build dependencies |
| `efitools` | Build efitools library only |
| `preloader` | Build HAB PreLoader only |
| `install` | Copy PreLoader to /root/hab_keys/ |
| `sign` | Sign PreLoader with MOK |
| `ventoy` | Copy Ventoy binaries (shim, MokManager) |

## Manual Build

### Build efitools Library
```bash
cd /root/src/kernel.org/efitools
make lib/lib-efi.a ARCH=x86_64
```

### Build HAB PreLoader
```bash
cd /root/src/hab/preloader
make clean
make all
```

### Sign with MOK
```bash
sbsign --key /root/hab_keys/MOK.key \
       --cert /root/hab_keys/MOK.crt \
       --output /root/hab_keys/hab-preloader-signed.efi \
       HabPreLoader-sbat.efi
```

## Build ISO Tool

```bash
cd /root/src/hab/iso
make
./hab_iso -h
```

## Output Files

```
/root/hab_keys/
├── hab-preloader.efi        # Unsigned PreLoader
├── hab-preloader-signed.efi # Signed PreLoader (use this)
├── shim-suse.efi            # SUSE shim
└── MokManager-suse.efi      # MOK Manager
```

## Verify Build

```bash
# Check PreLoader has security_policy functions
objdump -t /root/hab_keys/hab-preloader-signed.efi | grep security_policy

# Check signature
sbverify --list /root/hab_keys/hab-preloader-signed.efi
```
