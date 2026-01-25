# ISO Creation Guide

This guide explains how to create Secure Boot enabled ISOs using the PhotonOS-HABv4Emulation-ISOCreator tool.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Build Process Overview](#build-process-overview)
4. [Detailed Steps](#detailed-steps)
5. [Customization Options](#customization-options)
6. [Verification](#verification)
7. [Writing to USB](#writing-to-usb)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Packages

Install on Photon OS:
```bash
tdnf install -y gcc make sbsigntools xorriso dosfstools grub2-efi
```

### Build the Tool

```bash
cd photonos-scripts/HABv4SimulationEnvironment/src
make
```

### Directory Structure

Ensure you have the Photon OS build environment:
```
/root/
├── 5.0/                    # Or 4.0, 6.0
│   └── stage/
│       └── RPMS/x86_64/    # RPM packages
└── photon-5.0-*.iso        # Source ISO (downloaded automatically)
```

---

## Quick Start

### One Command Build

```bash
# Build everything automatically
./PhotonOS-HABv4Emulation-ISOCreator -b
```

This will:
1. Download Photon OS ISO (if not present)
2. Generate MOK signing keys
3. Extract SUSE shim components
4. Build custom GRUB stub
5. Create MOK-signed RPM packages
6. Assemble Secure Boot ISO

### Common Build Variations

```bash
# Build for Photon OS 6.0
./PhotonOS-HABv4Emulation-ISOCreator --release 6.0 --build-iso

# Build with RPM signing (for compliance)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# Build with eFuse USB requirement
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --efuse-usb

# Build kernel from source (takes hours)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --full-kernel-build
```

---

## Build Process Overview

```
Input ISO
    ↓
Extract ISO contents
    ↓
Generate MOK keys (if needed)
    ↓
Extract SUSE shim from embedded data
    ↓
Build custom GRUB stub (grub2-mkimage)
    ↓
Sign GRUB stub with MOK key
    ↓
Discover original RPM packages
    ↓
Generate MOK variant SPEC files
    ↓
Build MOK RPM packages
    ↓
Sign kernel with MOK key
    ↓
Create kickstart configuration files
    ↓
Patch installer in initrd (progress_bar fix)
    ↓
Update grub.cfg with boot menu
    ↓
Rebuild efiboot.img
    ↓
Assemble final ISO (xorriso)
    ↓
Output: photon-X.X-secureboot.iso
```

---

## Detailed Steps

### Step 1: Key Generation

If keys don't exist, the tool generates them:

```bash
# MOK key pair (RSA 2048, 180 days validity)
openssl req -new -x509 -newkey rsa:2048 \
    -keyout MOK.key -out MOK.crt \
    -nodes -days 180 \
    -subj "/CN=Photon OS Secure Boot MOK"

# Convert to DER for enrollment
openssl x509 -in MOK.crt -outform DER -out MOK.der
```

### Step 2: SUSE Shim Extraction

Embedded components are extracted from `data/`:
```
data/shim-suse.efi.gz → /root/hab_keys/shim-suse.efi
data/MokManager-suse.efi.gz → /root/hab_keys/MokManager-suse.efi
```

### Step 3: Custom GRUB Stub Build

```bash
grub2-mkimage \
    --format=x86_64-efi \
    --output=grub-photon-stub.efi \
    --prefix=/boot/grub2 \
    --sbat=sbat.csv \
    --disable-shim-lock \
    # Module list:
    part_gpt part_msdos fat iso9660 ext2 \
    search search_fs_uuid search_fs_file search_label \
    configfile linux initrd chain \
    echo reboot halt test true \
    gfxterm gfxmenu png jpeg tga gfxterm_background \
    probe efi_gop efi_uga
```

### Step 4: Signing

```bash
# Sign GRUB stub
sbsign --key MOK.key --cert MOK.crt \
    --output grub-photon-stub-signed.efi \
    grub-photon-stub.efi

# Sign kernel
sbsign --key MOK.key --cert MOK.crt \
    --output vmlinuz-signed \
    vmlinuz
```

### Step 5: RPM Package Discovery

The tool finds packages by file paths (version-agnostic):

```
/root/5.0/stage/RPMS/x86_64/
├── grub2-efi-image-*.rpm  → provides /boot/efi/EFI/BOOT/grubx64.efi
├── linux-*.rpm            → provides /boot/vmlinuz-*
├── linux-esx-*.rpm        → provides /boot/vmlinuz-* (alternate)
└── shim-signed-*.rpm      → provides /boot/efi/EFI/BOOT/bootx64.efi
```

### Step 6: MOK SPEC Generation

For each package, a `-mok` variant SPEC is generated:

```spec
Name:           grub2-efi-image-mok
Version:        %{original_version}
Release:        1.mok%{?dist}
Summary:        GRUB EFI image with MOK Secure Boot support
License:        GPLv3+
Provides:       grub2-efi-image = %{version}
Conflicts:      grub2-efi-image

%install
install -D -m 0644 %{SOURCE0} %{buildroot}/boot/efi/EFI/BOOT/grubx64.efi
```

### Step 7: RPM Build

```bash
rpmbuild -bb \
    --define "_topdir /root/5.0/stage" \
    --define "dist .ph5" \
    grub2-efi-image-mok.spec
```

### Step 8: Kickstart Creation

Two kickstart files are placed at ISO root:

**mok_ks.cfg:**
```json
{
    "linux_flavor": "linux-mok",
    "packages": ["minimal", "initramfs", "linux-mok", 
                 "grub2-efi-image-mok", "shim-signed-mok"],
    "bootmode": "efi",
    "ui": true
}
```

**standard_ks.cfg:**
```json
{
    "linux_flavor": "linux",
    "packages": ["minimal", "initramfs", "linux", 
                 "grub2-efi-image", "shim-signed"],
    "bootmode": "efi",
    "ui": true
}
```

### Step 9: Initrd Patching

The installer in initrd has a bug with `progress_bar`. We apply a surgical fix:

```python
# In installer.py __init__():
self.progress_bar = None
self.window = None

# In exit_gracefully():
if self.progress_bar:
    self.progress_bar.hide()
```

### Step 10: grub.cfg Update

Boot menu with 6 options:
```
1. Install (Custom MOK) - For Physical Hardware
2. Install (VMware Original) - For VMware VMs
3. MokManager - Enroll/Delete MOK Keys
4. Reboot into UEFI Firmware Settings
5. Reboot
6. Shutdown
```

### Step 11: efiboot.img Rebuild

```bash
# Create 16MB FAT image
dd if=/dev/zero of=efiboot.img bs=1M count=16
mkfs.vfat -F 12 -n EFIBOOT efiboot.img

# Populate with boot files
mount -o loop efiboot.img /mnt
cp BOOTX64.EFI grub.efi MokManager.efi /mnt/EFI/BOOT/
cp MokManager.efi MOK.der /mnt/
umount /mnt
```

### Step 12: ISO Assembly

```bash
xorriso -as mkisofs \
    -o photon-5.0-secureboot.iso \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub2/efiboot.img \
    -no-emul-boot -isohybrid-gpt-basdat \
    -V "PHOTON_$(date +%Y%m%d)" \
    /tmp/iso_work/
```

---

## Customization Options

### Different Photon OS Versions

```bash
./PhotonOS-HABv4Emulation-ISOCreator --release 4.0 --build-iso
./PhotonOS-HABv4Emulation-ISOCreator --release 5.0 --build-iso
./PhotonOS-HABv4Emulation-ISOCreator --release 6.0 --build-iso
```

### Custom Keys Directory

```bash
./PhotonOS-HABv4Emulation-ISOCreator \
    --keys-dir=/path/to/keys \
    --build-iso
```

### Custom Input/Output ISO

```bash
./PhotonOS-HABv4Emulation-ISOCreator \
    --input=/path/to/photon.iso \
    --output=/path/to/output.iso \
    --build-iso
```

### MOK Certificate Validity

```bash
# 365 days instead of default 180
./PhotonOS-HABv4Emulation-ISOCreator \
    --mok-days=365 \
    --build-iso
```

### RPM Signing (Compliance)

```bash
./PhotonOS-HABv4Emulation-ISOCreator \
    --build-iso \
    --rpm-signing
```

This adds:
- GPG key generation
- Package signing with rpmsign
- GPG key import in kickstart postinstall

### eFuse USB Requirement

```bash
# Build ISO that requires eFuse USB dongle
./PhotonOS-HABv4Emulation-ISOCreator \
    --build-iso \
    --efuse-usb

# Create the eFuse USB dongle
./PhotonOS-HABv4Emulation-ISOCreator \
    --create-efuse-usb=/dev/sdX \
    --yes
```

### Full Kernel Build

Build kernel from source with Secure Boot options:

```bash
./PhotonOS-HABv4Emulation-ISOCreator \
    --build-iso \
    --full-kernel-build
```

Requires kernel source in:
- `/root/{release}/stage/SOURCES/linux-*.tar.xz`
- Config in `/root/{release}/SPECS/linux/` or `/root/common/SPECS/linux/`

---

## Verification

### Check ISO Structure

```bash
# List EFI boot files
xorriso -indev photon-secureboot.iso -ls /EFI/BOOT/

# List root files
xorriso -indev photon-secureboot.iso -ls /

# Check kickstart files
xorriso -osirrox on -indev photon-secureboot.iso \
    -extract /mok_ks.cfg /tmp/mok_ks.cfg
cat /tmp/mok_ks.cfg
```

### Verify Signatures

```bash
# Extract and verify
mkdir /tmp/verify
xorriso -osirrox on -indev photon-secureboot.iso \
    -extract /EFI/BOOT /tmp/verify

# Check shim (should show Microsoft)
sbverify --list /tmp/verify/BOOTX64.EFI

# Check GRUB stub (should show MOK)
sbverify --list /tmp/verify/grub.efi

# Verify GRUB against MOK certificate
sbverify --cert /root/hab_keys/MOK.crt /tmp/verify/grub.efi
```

### Use Built-in Diagnose

```bash
./PhotonOS-HABv4Emulation-ISOCreator -D photon-secureboot.iso
```

This checks:
- EFI boot files present
- Signatures valid
- SBAT metadata correct
- Kickstart files present
- MOK certificate present

---

## Writing to USB

### Using dd (Linux)

```bash
# Find USB device
lsblk

# Write ISO (DESTRUCTIVE!)
sudo dd if=photon-secureboot.iso of=/dev/sdX bs=4M status=progress conv=fsync
sudo sync
```

### Using Rufus (Windows)

1. Select ISO file
2. **Important**: Use DD mode, not ISO mode
3. Write to USB

### Using Ventoy

The ISO works with Ventoy out of the box:
1. Copy ISO to Ventoy USB
2. Boot from Ventoy
3. Select the ISO

---

## Troubleshooting

### Build Fails: "rpmbuild: command not found"

```bash
tdnf install -y rpm-build
```

### Build Fails: "sbsign: command not found"

```bash
tdnf install -y sbsigntools
```

### Build Fails: "xorriso: command not found"

```bash
tdnf install -y xorriso
```

### Build Fails: "grub2-mkimage: command not found"

```bash
tdnf install -y grub2-efi
```

### Build Fails: "Cannot find RPM packages"

Ensure the RPM directory exists:
```bash
ls /root/5.0/stage/RPMS/x86_64/*.rpm
```

If empty, you need to build Photon OS packages first or download them.

### Build Fails: "mkfs.vfat: command not found"

```bash
tdnf install -y dosfstools
```

### ISO Won't Boot: "SBAT self-check failed"

The shim SBAT version is revoked. Use latest tool version with SUSE shim (SBAT=shim,4).

### ISO Won't Boot: "Security Violation"

Normal on first boot. Enroll MOK certificate via MokManager.

### USB Won't Boot

1. Check Secure Boot is enabled
2. Check CSM/Legacy is disabled
3. Try different USB port (USB 2.0 vs 3.0)
4. Verify ISO was written correctly: `dd if=/dev/sdX bs=512 count=1 | hexdump -C`

---

## Output Files

After successful build:

```
/root/
├── photon-5.0-*-secureboot.iso     # Final ISO
├── hab_keys/
│   ├── MOK.key                      # Private key (keep secure!)
│   ├── MOK.crt                      # Certificate (PEM)
│   ├── MOK.der                      # Certificate (DER)
│   ├── grub-photon-stub.efi         # Signed GRUB stub
│   └── vmlinuz-mok                  # Signed kernel
└── 5.0/stage/RPMS/x86_64/
    ├── shim-signed-mok-*.rpm
    ├── grub2-efi-image-mok-*.rpm
    └── linux-mok-*.rpm
```
