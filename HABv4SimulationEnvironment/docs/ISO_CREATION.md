# ISO Creation and USB Boot Guide

This document covers creating Secure Boot compatible ISOs and writing them to USB drives.

## Table of Contents

1. [ISO Structure](#iso-structure)
2. [Creating Secure Boot ISO](#creating-secure-boot-iso)
3. [ISO Hybrid Structure](#iso-hybrid-structure)
4. [Writing to USB](#writing-to-usb)
5. [xorriso vs mkisofs](#xorriso-vs-mkisofs)
6. [efiboot.img Details](#efibootimg-details)
7. [Verifying ISO](#verifying-iso)

---

## ISO Structure

### Required Components

A Secure Boot compatible ISO needs:

```
ISO Root/
├── EFI/
│   └── BOOT/
│       ├── BOOTX64.EFI                        # Fedora shim 15.8 (SBAT=shim,4)
│       ├── grub.efi                           # Photon OS GRUB stub (MOK-signed)
│       ├── grubx64.efi                        # Same as grub.efi
│       ├── grubx64_real.efi                   # VMware-signed GRUB real
│       ├── MokManager.efi                     # Fedora MokManager
│       └── ENROLL_THIS_KEY_IN_MOKMANAGER.cer  # CN=grub certificate
│
├── boot/
│   └── grub2/
│       ├── efiboot.img      # EFI System Partition image (16MB)
│       ├── grub.cfg         # Boot menu configuration
│       └── themes/          # GRUB themes
│
├── isolinux/
│   ├── isolinux.bin         # BIOS boot loader
│   ├── isolinux.cfg         # BIOS boot config
│   ├── vmlinuz              # VMware-signed kernel
│   ├── initrd.img           # Initial ramdisk
│   └── boot.cat             # El Torito boot catalog
│
└── ... (other files)
```

### efiboot.img Contents

The `efiboot.img` is a FAT filesystem image containing EFI boot files:

```
efiboot.img (FAT32, 16MB)/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer   # Photon OS MOK certificate
├── grub/
│   └── grub.cfg                        # Bootstrap config (fallback)
└── EFI/
    └── BOOT/
        ├── BOOTX64.EFI      # Fedora shim 15.8 (SBAT=shim,4)
        ├── grub.efi         # Photon OS GRUB stub (MOK-signed)
        ├── grubx64.efi      # Same as grub.efi
        ├── grubx64_real.efi # VMware GRUB real
        ├── grub.cfg         # Bootstrap config for grubx64_real
        ├── MokManager.efi   # Fedora MokManager
        ├── mmx64.efi        # Same as MokManager.efi
        └── revocations.efi  # Revocation list
```

**Photon OS Secure Boot**: Uses Fedora shim (SBAT compliant) + custom Photon OS GRUB stub (MOK-signed). User enrolls the Photon OS MOK certificate, which allows shim to trust the stub.

**Two-Stage Boot Menu**:
- Stage 1 (Stub, 5 sec timeout): Continue / MokManager / Reboot / Shutdown
- Stage 2 (Main): Install Photon OS (Custom) / Install Photon OS (VMware original) / Reboot / Shutdown

MokManager is only accessible from Stage 1 (stub menu) because shim's protocol is still available there.

---

## Creating Secure Boot ISO

### Using HABv4-installer.sh

```bash
# Build complete Secure Boot ISO
./HABv4-installer.sh --release=5.0 --build-iso

# Fix existing ISO for Secure Boot
source ./HABv4-installer.sh
fix_iso_secureboot /path/to/photon.iso
```

### Using hab_iso.sh (Modular)

```bash
# Fix existing ISO
./hab_scripts/hab_iso.sh fix /path/to/photon.iso

# Output: /path/to/photon-secureboot.iso
```

### Manual Process

1. **Extract original ISO**
   ```bash
   mkdir /tmp/iso_extract
   mount -o loop original.iso /mnt
   cp -a /mnt/* /tmp/iso_extract/
   umount /mnt
   ```

2. **Add Secure Boot components**
   ```bash
   # Copy Fedora shim and MokManager
   cp shim-fedora.efi /tmp/iso_extract/EFI/BOOT/BOOTX64.EFI
   cp mmx64-fedora.efi /tmp/iso_extract/EFI/BOOT/MokManager.efi
   
   # Copy Photon OS GRUB stub + VMware GRUB real
   cp grub-photon-stub.efi /tmp/iso_extract/EFI/BOOT/grubx64.efi
   cp grub-photon-stub.efi /tmp/iso_extract/EFI/BOOT/grub.efi
   cp grubx64_real.efi /tmp/iso_extract/EFI/BOOT/grubx64_real.efi
   
   # Copy Photon OS MOK certificate for enrollment
   cp MOK.der /tmp/iso_extract/EFI/BOOT/ENROLL_THIS_KEY_IN_MOKMANAGER.cer
   ```

3. **Update efiboot.img** (resize if needed)
   ```bash
   # Create larger efiboot.img (16MB)
   dd if=/dev/zero of=efiboot_new.img bs=1M count=16
   mkfs.vfat -F 32 efiboot_new.img
   
   # Mount and copy files
   mount -o loop efiboot_new.img /mnt
   mkdir -p /mnt/EFI/BOOT /mnt/grub
   cp BOOTX64.EFI grub.efi grubx64.efi grubx64_real.efi grub.cfg MokManager.efi /mnt/EFI/BOOT/
   cp ENROLL_THIS_KEY_IN_MOKMANAGER.cer /mnt/
   umount /mnt
   
   cp efiboot_new.img /tmp/iso_extract/boot/grub2/efiboot.img
   ```

4. **Create ISO with xorriso**
   ```bash
   xorriso -as mkisofs \
       -R -l -D \
       -o output.iso \
       -V "PHOTON_SB" \
       -c isolinux/boot.cat \
       -b isolinux/isolinux.bin \
       -no-emul-boot -boot-load-size 4 -boot-info-table \
       -eltorito-alt-boot \
       -e boot/grub2/efiboot.img \
       -no-emul-boot \
       -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
       -isohybrid-gpt-basdat \
       /tmp/iso_extract
   ```

---

## ISO Hybrid Structure

### What is Hybrid ISO?

A hybrid ISO can boot from:
- CD/DVD (via El Torito)
- USB drive (via MBR/GPT)

### Required Components

| Component | Purpose |
|-----------|---------|
| El Torito boot catalog | CD/DVD boot |
| MBR boot code | Legacy BIOS USB boot |
| GPT partition table | UEFI USB boot |
| EFI System Partition | UEFI boot files |

### Partition Layout

```
Hybrid ISO:
┌────────────────────────────────────────────────────┐
│ MBR (512 bytes)                                    │
│   - Boot code from isohdpfx.bin                   │
│   - Partition table                                │
├────────────────────────────────────────────────────┤
│ GPT Header (if present)                            │
├────────────────────────────────────────────────────┤
│ ISO 9660 Filesystem                                │
│   - El Torito boot catalog                        │
│   - All ISO files                                  │
│   - efiboot.img embedded                          │
├────────────────────────────────────────────────────┤
│ EFI System Partition (from efiboot.img)           │
│   Type: 0xEF (EFI)                                │
└────────────────────────────────────────────────────┘
```

### Verifying Hybrid Structure

```bash
# Check partition table
fdisk -l image.iso

# Expected output:
# Device     Boot Start     End Sectors Size Id Type
# image.iso1 *        0 8399159 8399160   4G  0 Empty
# image.iso2        840    6983    6144   3M ef EFI

# Check El Torito
xorriso -indev image.iso -report_el_torito plain
```

---

## Writing to USB

### Using dd (Linux)

```bash
# Find your USB device
lsblk

# Write ISO (DESTRUCTIVE!)
sudo dd if=photon-secureboot.iso of=/dev/sdX bs=4M status=progress conv=fsync
sudo sync
```

### Using Rufus (Windows)

1. Download Rufus from https://rufus.ie/
2. Select USB device
3. Select ISO file
4. **IMPORTANT**: Choose **DD Image** mode (not ISO mode)
5. Click Start

### Using hab_iso.sh

```bash
# Write with confirmation
./hab_scripts/hab_iso.sh write photon-secureboot.iso /dev/sdX
```

### Common Mistakes

| Mistake | Result | Solution |
|---------|--------|----------|
| Rufus ISO mode | May not boot | Use DD mode |
| Copying files to FAT32 USB | Won't boot | Use dd or Rufus DD |
| Writing to partition (sda1) | Corrupted USB | Write to disk (sda) |
| Not syncing | Incomplete write | Run `sync` after dd |

### Creating eFuse USB Dongle

If building with `--efuse-usb` flag, you'll need to create a separate USB dongle with eFuse simulation files:

```bash
# Create eFuse USB dongle (after keys are generated)
sudo ./HABv4-installer.sh --create-efuse-usb=/dev/sdb
```

This formats the USB with:
- Label: `EFUSE_SIM`
- Filesystem: FAT32
- Contents: `efuse_sim/` directory with SRK hash and security config

The GRUB stub will search for this USB at boot time and display security mode status.

---

## xorriso vs mkisofs

### Recommended: xorriso

```bash
xorriso -as mkisofs \
    -R -l -D \
    -o output.iso \
    -V "VOLUME_LABEL" \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub2/efiboot.img \
    -no-emul-boot \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -isohybrid-gpt-basdat \
    /path/to/contents
```

Key options:
- `-isohybrid-mbr`: Add MBR boot code
- `-isohybrid-gpt-basdat`: Create GPT partition for EFI

### Legacy: mkisofs + isohybrid

```bash
# Create ISO
mkisofs -R -l -L -D \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub2/efiboot.img -no-emul-boot \
    -o output.iso \
    /path/to/contents

# Make hybrid
isohybrid --uefi output.iso
```

### Comparison

| Aspect | xorriso | mkisofs + isohybrid |
|--------|---------|---------------------|
| Single command | Yes | No (two steps) |
| GPT support | Native | Post-processing |
| UEFI compatibility | Better | May have issues |
| Installed on | xorriso package | genisoimage + syslinux |

---

## efiboot.img Details

### Size Requirements

| Original | With Fedora shim | Recommended |
|----------|------------------|-------------|
| 3 MB | Too small | 8 MB |

Contents require ~4.5 MB:
- Fedora shim: ~950 KB
- Fedora MokManager: ~850 KB
- Photon OS GRUB stub (grub.efi): ~2.5 MB (includes embedded modules)
- VMware GRUB real (grubx64_real.efi): ~1.3 MB
- grub.cfg: ~1 KB
- Certificate: ~1 KB

### Creating efiboot.img

```bash
# Create 16MB FAT32 image
dd if=/dev/zero of=efiboot.img bs=1M count=16
mkfs.vfat -F 32 -n "EFIBOOT" efiboot.img

# Mount and populate
mkdir /tmp/efi_mount
mount -o loop efiboot.img /tmp/efi_mount

mkdir -p /tmp/efi_mount/EFI/BOOT
cp bootx64.efi /tmp/efi_mount/EFI/BOOT/
cp grubx64_stub.efi /tmp/efi_mount/EFI/BOOT/grubx64.efi
cp grubx64_stub.efi /tmp/efi_mount/EFI/BOOT/grub.efi  # CRITICAL!
cp grubx64_real.efi /tmp/efi_mount/EFI/BOOT/
cp grub.cfg /tmp/efi_mount/EFI/BOOT/

sync
umount /tmp/efi_mount
```

### Bootstrap grub.cfg

The grub.cfg in efiboot.img is a bootstrap that finds the ISO:

```bash
# Bootstrap grub.cfg
set timeout=3

# Search for ISO filesystem
search --no-floppy --file --set=root /isolinux/vmlinuz

# Load real config from ISO
if [ -n "$root" ]; then
    set prefix=($root)/boot/grub2
    configfile ($root)/boot/grub2/grub.cfg
fi

# Fallback
menuentry "Photon OS Install (fallback)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3
    initrd /isolinux/initrd.img
}
```

---

## Verifying ISO

### Check Structure

```bash
# Mount and inspect
mkdir /tmp/iso_check
mount -o loop image.iso /tmp/iso_check

# Check EFI files
ls -la /tmp/iso_check/EFI/BOOT/

# Check signatures
sbverify --list /tmp/iso_check/EFI/BOOT/BOOTX64.EFI

# Check kernels
ls -la /tmp/iso_check/isolinux/vmlinuz*

umount /tmp/iso_check
```

### Check Hybrid

```bash
# Partition table
fdisk -l image.iso

# El Torito catalog
xorriso -indev image.iso -report_el_torito plain
```

### Using hab_iso.sh

```bash
./hab_scripts/hab_iso.sh verify /path/to/image.iso
```

### Expected Output

```
=== Partition Structure ===
Device     Boot Start     End Sectors Size Id Type
image.iso1 *        0 8399159 8399160   4G  0 Empty
image.iso2        840    8887    8048   4M ef EFI

=== EFI/BOOT Contents ===
BOOTX64.EFI       949424  (Fedora shim 15.8 SBAT=shim,4)
grub.efi         2500000  (Photon OS GRUB stub, MOK-signed)
grubx64.efi      2500000  (Photon OS GRUB stub, MOK-signed)
grubx64_real.efi 1297712  (VMware GRUB real)
MokManager.efi    848080  (Fedora MokManager)
ENROLL_THIS_KEY_IN_MOKMANAGER.cer  (Photon OS MOK certificate)

=== Shim Signature ===
signature 1: Microsoft Windows UEFI Driver Publisher

=== Shim SBAT ===
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
shim,4,UEFI shim,shim,1,https://github.com/rhboot/shim

=== Kernel ===
vmlinuz  (VMware signed)
```
