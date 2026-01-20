# Troubleshooting Guide

This document covers common issues and their solutions.

## Table of Contents

1. [Boot Errors](#boot-errors)
2. [eFuse USB Dongle Issues](#efuse-usb-dongle-issues)
3. [Signature Errors](#signature-errors)
4. [MOK Enrollment Issues](#mok-enrollment-issues)
5. [Module Loading Issues](#module-loading-issues)
6. [ISO Creation Issues](#iso-creation-issues)
7. [USB Boot Issues](#usb-boot-issues)
8. [Diagnostic Commands](#diagnostic-commands)

---

## Boot Errors

### "SBAT self-check failed: Security Policy Violation"

**Cause**: The shim has an SBAT version that is revoked by Microsoft. Ventoy's SUSE shim has `shim,3` which is REVOKED.

**Solutions**:
1. Use Fedora shim 15.8 (SBAT=shim,4) instead of Ventoy's SUSE shim
2. Rebuild ISO with latest HABv4-installer.sh which uses Fedora shim
3. Verify shim SBAT version:
   ```bash
   strings BOOTX64.EFI | grep -A5 "^sbat,"
   # Should show shim,4 or higher
   ```

### "shim_lock protocol not found" when chainloading MokManager

**Cause**: Trying to chainload MokManager.efi from the main boot menu (VMware's GRUB) instead of the stub menu.

**Explanation**: 
- VMware's GRUB has Secure Boot verification that requires shim's `shim_lock` protocol
- This protocol is only available when running directly under shim's context
- After the stub chainloads grubx64_real.efi, shim's protocol is no longer accessible

**Solution**: Access MokManager from the stub menu (Stage 1), not the main menu (Stage 2):
1. Reboot the system
2. During the 5-second stub menu timeout, press any key
3. Select "MokManager - Enroll/Delete MOK Keys"

### "EFI USB Device (SB) boot failed"

**Cause**: Secure Boot signature verification failed at UEFI level.

**Solutions**:
1. Verify shim is Microsoft-signed:
   ```bash
   sbverify --list /path/to/BOOTX64.EFI | grep Microsoft
   ```
2. Check if shim file is corrupted (compare hash)
3. Ensure using Fedora shim (has Microsoft signature and SBAT=shim,4)

### "EFI USB Device (USB) boot failed"

**Cause**: ISO is not properly hybrid for USB boot.

**Solutions**:
1. Rebuild ISO with xorriso:
   ```bash
   xorriso -as mkisofs ... -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin -isohybrid-gpt-basdat
   ```
2. Verify ISO has partition table:
   ```bash
   fdisk -l image.iso
   # Should show partition type "ef" (EFI)
   ```
3. Use Rufus **DD mode**, not ISO mode

### "Failed to open \EFI\BOOT\grub.efi - Not Found"

**Cause**: SUSE shim looks for `grub.efi`, but only `grubx64.efi` exists.

**Solutions**:
1. Copy GRUB to both names:
   ```bash
   cp grubx64.efi grub.efi
   ```
2. Rebuild ISO with latest HABv4-installer.sh (fixed)

### "start_image() returned Not Found"

**Cause**: Shim couldn't find or load GRUB.

**Solutions**:
1. Ensure `grub.efi` exists in efiboot.img
2. Check efiboot.img isn't corrupted:
   ```bash
   mount -o loop efiboot.img /mnt
   ls -la /mnt/EFI/BOOT/
   ```

### GRUB drops to command prompt (grub>)

**Cause**: GRUB can't find its configuration file.

**Solutions**:
1. Ensure `grub.cfg` exists in efiboot.img `/EFI/BOOT/`
2. Bootstrap grub.cfg should search for ISO filesystem:
   ```bash
   search --no-floppy --file --set=root /isolinux/vmlinuz-vmware
   configfile ($root)/boot/grub2/grub.cfg
   ```
3. Check the search file exists on ISO

---

## eFuse USB Dongle Issues

### "BOOT BLOCKED" - No "Continue" option available

**Cause**: ISO was built with `--efuse-usb` flag but eFuse USB dongle is not inserted or invalid.

**Solutions**:
1. Insert the eFuse USB dongle (labeled `EFUSE_SIM`) before booting
2. Select "Retry - Search for eFuse USB" after inserting
3. If you don't have an eFuse USB, rebuild ISO without `--efuse-usb`:
   ```bash
   ./HABv4-installer.sh --release=5.0 --build-iso
   ```

### "eFuse USB found but missing srk_fuse.bin"

**Cause**: USB has label `EFUSE_SIM` but doesn't contain required files.

**Solutions**:
1. Recreate the eFuse USB dongle:
   ```bash
   ./HABv4-installer.sh --create-efuse-usb=/dev/sdX
   ```
2. Verify USB contents:
   ```
   /efuse_sim/srk_fuse.bin      (required)
   /efuse_sim/sec_config.bin    (required)
   /efuse_sim/efuse_config.json (optional)
   ```

### eFuse USB not detected

**Cause**: USB not mounted or wrong filesystem label.

**Solutions**:
1. Verify USB label is exactly `EFUSE_SIM`:
   ```bash
   lsblk -o NAME,LABEL
   ```
2. Relabel if needed:
   ```bash
   fatlabel /dev/sdX1 EFUSE_SIM
   ```
3. Ensure USB is FAT32 formatted

---

## Signature Errors

### "bad shim signature" (sb.c:193)

**Cause**: Shim doesn't trust the binary it's trying to load.

**Solutions**:
1. For GRUB: Ensure GRUB stub is signed with Photon OS MOK and certificate is enrolled
2. For MokManager: Use Fedora shim + Fedora MokManager (same trust chain)
3. Check signature:
   ```bash
   sbverify --list grubx64.efi
   ```

### "Security Policy Violation"

**Cause**: UEFI firmware rejected unsigned bootloader.

**Solutions**:
1. Use Microsoft-signed shim as first bootloader
2. Don't try to boot unsigned EFI binaries directly
3. Check Secure Boot is actually enabled (some UEFI show this error even when disabled)

### "Verification failed: (0x1A) Security Violation"

**Cause**: Binary signature doesn't match any trusted certificate.

**For GRUB (first boot)**:
This is **expected** on first boot! Fedora shim doesn't trust the Photon OS GRUB stub yet.

**Solutions** (Photon OS approach):
1. Press any key when Security Violation appears
2. Fedora MokManager loads automatically
3. Select "Enroll key from disk"
4. Navigate to root `/`
5. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` (Photon OS MOK certificate)
6. Confirm enrollment and select **Reboot**
7. Photon OS GRUB stub now loads (trusted via MOK signature), then chainloads VMware GRUB real

**If enrollment doesn't persist after reboot:**
Try hash enrollment instead:
1. In MokManager, select "Enroll hash from disk"
2. Navigate to `EFI/BOOT/`
3. Select `grub.efi`
4. Confirm and reboot

**MokManager Menu Options:**
- Enroll key from disk / Enroll hash from disk
- Delete key / Delete hash
- Reboot / Power off

**For other binaries**:
1. Enroll the signing certificate via MOK
2. Verify certificate matches the key used for signing:
   ```bash
   # Check certificate
   openssl x509 -in MOK.crt -noout -subject
   
   # Check signature on binary
   sbverify --list binary.efi
   ```

---

## MOK Enrollment Issues

### "Failed to open \EFI\BOOT\MokManager.efi - Not Found"

**Cause**: MokManager installed with wrong filename (mmx64.efi instead of MokManager.efi).

**Solutions**:
1. Rebuild ISO with latest HABv4-installer.sh (fixed)
2. Manually rename: `mmx64.efi` → `MokManager.efi` in both:
   - `/EFI/BOOT/` on ISO root
   - Inside `efiboot.img`

### MokManager doesn't appear at boot

**Cause**: No pending MOK enrollment request.

**Solutions**:
1. Import MOK first:
   ```bash
   mokutil --import MOK.der
   # Set password, then reboot
   ```
2. Or select "Enroll MOK Certificate" from boot menu (chainloads MokManager)

### Certificate not visible in MokManager

**Cause**: MokManager browses the EFI partition (efiboot.img), not the ISO filesystem.

**Solutions**:
1. When using "Enroll key from disk", navigate to root `/`
2. You should see `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
3. The filename matches Ventoy's naming convention for maximum compatibility
4. If missing, rebuild ISO with latest HABv4-installer.sh

### Certificate enrolled but still "Security Violation" after reboot

**Cause**: Certificate doesn't match GRUB stub's signing key.

**Solution**: Verify the certificate matches the GRUB signature:
```bash
# Check certificate subject
openssl x509 -inform DER -in ENROLL_THIS_KEY_IN_MOKMANAGER.cer -noout -subject

# Check GRUB stub signature (should match)
sbverify --list grub.efi | grep subject
```

The certificate subject must match the GRUB stub signature issuer. With the Photon OS approach, both should show `CN=Photon OS Secure Boot MOK`.

### Need to delete enrolled MOK keys

**Options**:

1. **From Boot Menu Rescue Shell** (Recommended):
   - Select **"MOK Management >"** → **"Rescue Shell"**
   - Run: `mokutil --list-enrolled` to see keys
   - Run: `mokutil --delete key.der` to schedule deletion
   - Run: `reboot` to confirm in MokManager

2. **From MokManager directly**:
   - Select **"MOK Management >"** → **"MokManager"**
   - Use "Delete key" option (if keys are enrolled)

3. **From installed Photon OS**:
   ```bash
   mokutil --list-enrolled
   mokutil --delete /path/to/key.der
   # Reboot and confirm in MokManager
   ```

### MOK enrollment doesn't persist after reboot

**Cause**: Some firmwares have issues with certificate enrollment or limited NVRAM.

**Solutions**:
1. Try **hash enrollment** instead of certificate enrollment:
   - Select "Enroll hash from disk" in MokManager
   - Navigate to `EFI/BOOT/` and select `grub.efi`
   - This enrolls the binary hash which some firmwares handle better
2. Always select **Reboot** from MokManager menu (don't power off)
3. Some firmwares require BIOS/UEFI setup password to be set before MOK can write to NVRAM
4. Try enrolling `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` to get both VMware and MOK in one operation

### MOK enrollment password prompt loops

**Cause**: Entering wrong password.

**Solutions**:
1. Remember the password set during `mokutil --import`
2. Password is case-sensitive
3. If forgotten, reset and try again:
   ```bash
   mokutil --reset
   # Reboot, confirm reset
   mokutil --import MOK.der
   # Set new password
   ```

### "You need to load the kernel first"

**Cause**: GRUB trying to boot before kernel is loaded.

**Solutions**:
1. Check GRUB menu entries have valid `linux` and `initrd` commands
2. Verify kernel path exists on ISO:
   ```bash
   ls -la /isolinux/vmlinuz*
   ```

---

## Module Loading Issues

### "Lockdown: unsigned module loading is restricted"

**Cause**: Kernel lockdown prevents unsigned module loading.

**Solutions**:
1. Use kernel with matching signed modules
2. Don't mix kernels from different builds
3. Verify modules are signed:
   ```bash
   modinfo module.ko | grep sig
   ```

### "module verification failed: signature and/or required key missing"

**Cause**: Module isn't signed or key isn't trusted.

**Solutions**:
1. Rebuild kernel with module signing enabled:
   ```kconfig
   CONFIG_MODULE_SIG=y
   CONFIG_MODULE_SIG_ALL=y
   ```
2. Use the same key that was used when building the kernel
3. Keep kernel and modules from the same build together

### Modules load but functionality broken

**Cause**: Module version mismatch.

**Solutions**:
1. Verify module matches kernel version:
   ```bash
   modinfo module.ko | grep vermagic
   uname -r
   ```
2. Rebuild modules for current kernel

---

## ISO Creation Issues

### "No space left on device" when updating efiboot.img

**Cause**: efiboot.img is too small (default 3MB).

**Solutions**:
1. Resize efiboot.img to 6MB:
   ```bash
   dd if=/dev/zero of=efiboot_new.img bs=1M count=6
   mkfs.vfat -F 12 efiboot_new.img
   # Mount and copy contents from old one
   ```
2. Use latest HABv4-installer.sh (auto-resizes)

### xorriso: "Failed to find suitable boot image"

**Cause**: El Torito boot specification not met.

**Solutions**:
1. Ensure isolinux.bin exists and is valid
2. Check boot catalog path is correct
3. Use exact xorriso options:
   ```bash
   -c isolinux/boot.cat
   -b isolinux/isolinux.bin
   -no-emul-boot -boot-load-size 4 -boot-info-table
   ```

### mkisofs vs genisoimage confusion

**Cause**: Different distributions use different names.

**Solutions**:
1. Check which is installed:
   ```bash
   which mkisofs genisoimage xorriso
   ```
2. They're usually compatible, prefer xorriso
3. Install xorriso: `tdnf install xorriso`

---

## USB Boot Issues

### USB boots on some machines but not others

**Cause**: Different UEFI implementations.

**Solutions**:
1. Try both USB ports (USB 2.0 vs 3.0)
2. Disable Fast Boot in UEFI
3. Disable CSM/Legacy Boot
4. Try creating USB with different method (dd vs Rufus)

### "No bootable device" after writing USB

**Cause**: ISO not written correctly or not hybrid.

**Solutions**:
1. Verify ISO is hybrid:
   ```bash
   fdisk -l image.iso
   ```
2. Write with dd directly to device (not partition):
   ```bash
   dd if=image.iso of=/dev/sdb  # NOT /dev/sdb1
   ```
3. Sync before removing:
   ```bash
   sync
   ```

### USB boots BIOS but not UEFI

**Cause**: Missing or incorrect EFI partition.

**Solutions**:
1. Check for EFI partition (type ef):
   ```bash
   fdisk -l image.iso
   ```
2. Rebuild with `-isohybrid-gpt-basdat`
3. Verify efiboot.img contains bootloader

---

## Diagnostic Commands

### Check Secure Boot Status

```bash
mokutil --sb-state
# SecureBoot enabled/disabled

# From UEFI (dmesg)
dmesg | grep -i secure
```

### List Enrolled Keys

```bash
# MOK keys
mokutil --list-enrolled

# UEFI db keys (requires root)
efi-readvar -v db
```

### Verify Signatures

```bash
# EFI binary
sbverify --list /path/to/file.efi

# Kernel module
modinfo module.ko | grep -E "sig|signer"

# RPM package
rpm -Kv package.rpm
```

### Check Boot Chain

```bash
# View boot entries
efibootmgr -v

# Check what booted
cat /sys/firmware/efi/efivars/SecureBoot-*
```

### ISO Analysis

```bash
# Mount and explore
mount -o loop image.iso /mnt
find /mnt -name "*.efi" -exec sbverify --list {} \;

# El Torito catalog
xorriso -indev image.iso -report_el_torito plain

# Partition table
fdisk -l image.iso
```

### Log Analysis

```bash
# Boot messages
journalctl -b | grep -iE "secure|shim|grub|uefi|efi"

# Module loading
dmesg | grep -iE "module|signature|lockdown"
```

---

## Quick Reference

### Error → Likely Cause → Fix

| Error Message | Likely Cause | Quick Fix |
|--------------|--------------|-----------|
| SBAT self-check failed | Shim SBAT version revoked | Use Fedora shim (SBAT=shim,4) |
| shim_lock protocol not found | Chainloading from wrong menu | Access MokManager from stub menu (Stage 1) |
| EFI USB Device (SB) boot failed | Bad shim signature | Use Fedora shim |
| EFI USB Device (USB) boot failed | Not hybrid | Rebuild with xorriso |
| grub.efi Not Found | Missing file | Copy grubx64.efi to grub.efi |
| bad shim signature | Wrong trust chain | Use Fedora shim + Fedora MokManager |
| MokManager.efi Not Found | Wrong filename or missing from efiboot.img | Rebuild with latest script |
| Security Violation (first boot) | Photon OS MOK certificate not enrolled | Enroll certificate from root `/` |
| Certificate not visible | File missing | Rebuild ISO with latest script |
| Enrollment doesn't persist | Firmware issue | Try "Enroll hash from disk" instead |
| Security Violation | Unsigned binary | Enroll Photon OS MOK certificate |
| Lockdown: unsigned module | Unsigned .ko | Use matching kernel+modules |
| No space left (efiboot.img) | Image too small | Resize to 16MB |
| Need to delete MOK keys | Keys enrolled | Use mokutil --delete |
| GRUB drops to prompt | Missing grub.cfg | Add bootstrap grub.cfg |
| can't find command 'reboot' | VMware GRUB missing module | Use "UEFI Firmware Settings" or Ctrl+Alt+Del |
| grubx64_real.efi not found | GRUB stub search failed | Rebuild with latest script (includes search module) |
| BOOT BLOCKED (no Continue) | eFuse USB missing/invalid | Insert eFuse USB labeled `EFUSE_SIM` or rebuild ISO without `--efuse-usb` |
| eFuse USB not detected | Wrong label or not FAT32 | Recreate with `--create-efuse-usb=/dev/sdX` |
