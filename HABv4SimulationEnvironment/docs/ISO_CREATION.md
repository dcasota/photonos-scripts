# HABv4 ISO Creation Guide

## Overview

This guide explains how to create Secure Boot enabled ISOs using the PhotonOS-HABv4Emulation-ISOCreator tool.

## Prerequisites

### Required Packages
```bash
tdnf install -y gcc make gnu-efi-devel sbsigntools xorriso syslinux dosfstools wget
```

### Build the Tool
```bash
cd src
make
```

## Quick Start

### Full Setup + ISO Creation
```bash
# Setup environment and build ISO in one command
./PhotonOS-HABv4Emulation-ISOCreator -g -s -d -b

# Or step by step:
./PhotonOS-HABv4Emulation-ISOCreator -g    # Generate keys
./PhotonOS-HABv4Emulation-ISOCreator -s    # Setup eFuse simulation
./PhotonOS-HABv4Emulation-ISOCreator -d    # Download Ventoy components
./PhotonOS-HABv4Emulation-ISOCreator -b    # Build ISO
```

### Specify Input/Output ISO
```bash
./PhotonOS-HABv4Emulation-ISOCreator -i /path/to/photon.iso -o /path/to/output.iso -b
```

### Build for Different Photon OS Versions
```bash
./PhotonOS-HABv4Emulation-ISOCreator -r 4.0 -b    # Photon OS 4.0
./PhotonOS-HABv4Emulation-ISOCreator -r 5.0 -b    # Photon OS 5.0
./PhotonOS-HABv4Emulation-ISOCreator -r 6.0 -b    # Photon OS 6.0
```

## ISO Structure

### Required Components

```
ISO Root/
├── mmx64.efi                              # SUSE MokManager (ROOT - required!)
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer      # MOK certificate for enrollment
├── EFI/
│   └── BOOT/
│       ├── BOOTX64.EFI                    # SUSE shim (Microsoft-signed)
│       ├── grub.efi                       # HAB PreLoader (MOK-signed)
│       ├── grubx64_real.efi               # VMware GRUB
│       └── MokManager.efi                 # SUSE MokManager (backup)
│
├── boot/
│   └── grub2/
│       ├── efiboot.img                    # EFI boot image (16MB FAT)
│       └── grub.cfg                       # Boot menu configuration
│
└── isolinux/
    ├── isolinux.bin                       # BIOS boot loader
    ├── isolinux.cfg                       # BIOS boot config
    ├── vmlinuz                            # Linux kernel
    └── initrd.img                         # Initial ramdisk
```

### efiboot.img Contents

```
efiboot.img (FAT12, 16MB)/
├── mmx64.efi                              # MokManager at ROOT
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer      # MOK certificate
└── EFI/
    └── BOOT/
        ├── BOOTX64.EFI                    # SUSE shim
        ├── grub.efi                       # HAB PreLoader
        ├── grubx64_real.efi               # VMware GRUB
        ├── MokManager.efi                 # MokManager backup
        └── grub.cfg                       # Bootstrap config
```

**CRITICAL**: SUSE shim looks for MokManager at `\mmx64.efi` (root level), not in EFI/BOOT/.

## Boot Chain

```
UEFI Firmware
    ↓ verifies against Microsoft CA (db)
BOOTX64.EFI (SUSE shim 15.8)
    ↓ verifies against MokList
grub.efi (HAB PreLoader)
    ↓ installs permissive security policy
grubx64_real.efi (VMware GRUB)
    ↓
Linux Kernel
```

## Using hab_iso Tool (Alternative)

The `hab_iso` tool in `src/hab/iso/` can also create ISOs:

```bash
cd src/hab/iso
make
./hab_iso /path/to/input.iso /path/to/output.iso
```

## Manual ISO Creation

### Step 1: Extract ISO
```bash
mkdir -p /tmp/iso_work
xorriso -osirrox on -indev input.iso -extract / /tmp/iso_work
```

### Step 2: Update EFI Components
```bash
mkdir -p /tmp/iso_work/EFI/BOOT

# Copy SUSE shim
cp /root/hab_keys/shim-suse.efi /tmp/iso_work/EFI/BOOT/BOOTX64.EFI

# Copy HAB PreLoader (or Ventoy PreLoader)
cp /root/hab_keys/hab-preloader-signed.efi /tmp/iso_work/EFI/BOOT/grub.efi

# Keep existing GRUB as grubx64_real.efi
mv /tmp/iso_work/EFI/BOOT/grubx64.efi /tmp/iso_work/EFI/BOOT/grubx64_real.efi

# Copy MokManager
cp /root/hab_keys/MokManager-suse.efi /tmp/iso_work/EFI/BOOT/MokManager.efi
cp /root/hab_keys/MokManager-suse.efi /tmp/iso_work/mmx64.efi

# Copy MOK certificate
cp /root/hab_keys/MOK.der /tmp/iso_work/ENROLL_THIS_KEY_IN_MOKMANAGER.cer
```

### Step 3: Update efiboot.img
```bash
# Create new 16MB FAT image
dd if=/dev/zero of=/tmp/efiboot.img bs=1M count=16
mkfs.vfat -F 12 -n EFIBOOT /tmp/efiboot.img

# Mount and populate
mkdir -p /tmp/efi_mount
mount -o loop /tmp/efiboot.img /tmp/efi_mount
mkdir -p /tmp/efi_mount/EFI/BOOT

# Copy all components
cp /root/hab_keys/shim-suse.efi /tmp/efi_mount/EFI/BOOT/BOOTX64.EFI
cp /root/hab_keys/hab-preloader-signed.efi /tmp/efi_mount/EFI/BOOT/grub.efi
cp /tmp/iso_work/EFI/BOOT/grubx64_real.efi /tmp/efi_mount/EFI/BOOT/
cp /root/hab_keys/MokManager-suse.efi /tmp/efi_mount/EFI/BOOT/MokManager.efi
cp /root/hab_keys/MokManager-suse.efi /tmp/efi_mount/mmx64.efi
cp /root/hab_keys/MOK.der /tmp/efi_mount/ENROLL_THIS_KEY_IN_MOKMANAGER.cer

# Create bootstrap grub.cfg
cat > /tmp/efi_mount/EFI/BOOT/grub.cfg << 'EOF'
search --no-floppy --file --set=root /isolinux/isolinux.cfg
set prefix=($root)/boot/grub2
configfile $prefix/grub.cfg
EOF

sync
umount /tmp/efi_mount

# Replace original
cp /tmp/efiboot.img /tmp/iso_work/boot/grub2/efiboot.img
```

### Step 4: Build ISO
```bash
cd /tmp/iso_work
xorriso -as mkisofs \
    -o /path/to/output.iso \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub2/efiboot.img \
    -no-emul-boot -isohybrid-gpt-basdat \
    -V "PHOTON_SB" \
    .
```

## Verification

### Check ISO Structure
```bash
xorriso -indev output.iso -ls /EFI/BOOT/
xorriso -indev output.iso -ls /
```

### Verify Signatures
```bash
# Extract and check
mkdir /tmp/verify
xorriso -osirrox on -indev output.iso -extract /EFI/BOOT /tmp/verify

sbverify --list /tmp/verify/BOOTX64.EFI    # Should show Microsoft
sbverify --list /tmp/verify/grub.efi       # Should show MOK
```

### Check HAB PreLoader
```bash
objdump -t /tmp/verify/grub.efi | grep security_policy
# Should show: security_policy_mok_allow, security_policy_mok_deny, etc.
```

## Writing to USB

```bash
# Find USB device
lsblk

# Write ISO (DESTRUCTIVE!)
sudo dd if=output.iso of=/dev/sdX bs=4M status=progress conv=fsync
sudo sync
```

## Troubleshooting

### "MokManager not found"
- Ensure `mmx64.efi` exists at ISO root (not just in EFI/BOOT/)
- SUSE shim requires MokManager at `\mmx64.efi`

### "Security Violation"
- Normal on first boot before MOK enrollment
- Enroll the MOK certificate via MokManager

### ISO won't boot in UEFI
- Check efiboot.img is properly populated
- Verify `-isohybrid-gpt-basdat` flag was used with xorriso

### SBAT verification failed
- Use SUSE shim from Ventoy (SBAT version shim,4)
- Don't use older Fedora shim versions
