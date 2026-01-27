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

**Cause**: The shim has an SBAT version that is revoked by Microsoft. Old shims with `shim,3` or lower are REVOKED.

**Solutions**:
1. Use SUSE shim from Ventoy 1.1.10 (SBAT=shim,4 compliant)
2. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator which downloads Ventoy's SUSE shim
3. Verify shim SBAT version:
   ```bash
   objcopy -O binary --only-section=.sbat BOOTX64.EFI /dev/stdout | head -3
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
2. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.7.0+ installs both names)

### "error: ../../grub-core/commands/search.c:NNN: no such device"

**Cause**: The installed system's GRUB was built for ISO boot (searches for `/isolinux/isolinux.cfg`) instead of the installed system (should search for `/boot/grub2/grub.cfg`).

**Impact**: GRUB cannot find the root partition because it's looking for a file that only exists on the ISO.

**Solutions**:
1. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.7.0+)
2. The fix builds GRUB with an embedded config that searches for `/boot/grub2/grub.cfg`

### Installation takes 2000+ seconds (instead of ~75 seconds)

**Cause**: USB autosuspend causing severe performance degradation on USB 3.x devices.

**Solutions**:
1. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.7.0+ adds `usbcore.autosuspend=-1`)
2. Or manually add `usbcore.autosuspend=-1` to kernel command line in GRUB

### "rpm transaction failed" during installation

**Cause**: Package conflicts between MOK packages and original packages.

**Common issues**:
- `Obsoletes` with version constraint fails when original has higher version
- File conflicts between `linux-mok` and `grub2-efi-image-mok`
- MOK packages not indexed in repodata

**Solutions**:
1. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.7.0+ fixes all these)
2. Specific fixes applied:
   - `Obsoletes: package` without version constraint
   - `linux-mok` only includes kernel files (not `/boot/efi`)
   - Repodata regenerated after adding MOK packages

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

**CRITICAL**: This is often caused by using the **wrong GRUB binary**.

#### Cause 1: Using Ventoy's Stub Instead of Full GRUB

Ventoy's `grub.efi` is a **64KB minimal stub**, NOT a full GRUB. It lacks essential commands like `search`, `configfile`, `linux`, and `chainloader`.

**Diagnosis**:
```bash
# Check the GRUB binary size
stat -c%s /path/to/grub.efi
# ~64 KB = Ventoy stub (WRONG for custom ISOs)
# ~1-2 MB = Full GRUB (CORRECT)

# Check if commands exist
strings /path/to/grub.efi | grep -c "configfile"
# 0 = stub (missing commands)
# >0 = full GRUB
```

**Solution**: Use VMware's GRUB from the original Photon ISO, sign it with your MOK key:
```bash
# Extract VMware's GRUB
xorriso -osirrox on -indev photon.iso -extract /boot/efi/EFI/BOOT/grubx64.efi ./grubx64.efi

# Sign with MOK key
sbsign --key MOK.key --cert MOK.crt --output grubx64-signed.efi grubx64.efi

# Use grubx64-signed.efi in your ISO as EFI/BOOT/grubx64.efi
```

#### Cause 2: Missing grub.cfg (if using full GRUB)

**Cause**: Full GRUB can't find its configuration file.

**Solutions**:
1. Ensure `grub.cfg` exists in efiboot.img `/EFI/BOOT/`
2. Bootstrap grub.cfg should search for ISO filesystem:
   ```bash
   search --no-floppy --file --set=root /isolinux/vmlinuz-vmware
   configfile ($root)/boot/grub2/grub.cfg
   ```
3. Check the search file exists on ISO

### Understanding Ventoy Components (CRITICAL)

When using Ventoy components for Secure Boot, understand their limitations:

| Component | Size | Type | Can Use for Custom ISO? |
|-----------|------|------|-------------------------|
| `BOOTX64.EFI` | ~965 KB | SUSE shim | YES - Microsoft signed |
| `grub.efi` | ~64 KB | Minimal stub | NO - lacks commands |
| `grubx64_real.efi` | ~1.9 MB | Full GRUB (Ventoy) | MAYBE - needs Ventoy paths |
| `MokManager.efi` | ~852 KB | MOK manager | YES |

**Key Insight**: Ventoy's `grub.efi` is designed for Ventoy's specific ecosystem. It expects:
- `/grub/grub.cfg` at partition root (Ventoy-specific path)
- Ventoy's directory structure (`/ventoy/`, `/grub/themes/`, etc.)

For Photon OS ISOs, use VMware's full GRUB binary and sign it with your own MOK key.

---

## eFuse USB Dongle Issues

### "BOOT BLOCKED" - No "Continue" option available

**Cause**: ISO was built with `--efuse-usb` flag but eFuse USB dongle is not inserted or invalid.

**Solutions**:
1. Insert the eFuse USB dongle (labeled `EFUSE_SIM`) before booting
2. Select "Retry - Search for eFuse USB" after inserting
3. If you don't have an eFuse USB, rebuild ISO without eFuse requirement:
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -r 5.0 -b
   ```

### "eFuse USB found but missing srk_fuse.bin"

**Cause**: USB has label `EFUSE_SIM` but doesn't contain required files.

**Solutions**:
1. Recreate the eFuse USB dongle:
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -u /dev/sdX
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

### "error: can't find command `probe`"

**Cause**: GRUB stub was built without the `probe` module. The `probe` command is required to detect the UUID of the ISO filesystem for proper kernel boot parameters.

**Impact**: Without `probe`, the kernel boot parameter `photon.media=UUID=$photondisk` will be empty, causing the installer to fail to find the installation media.

**Solution**: Rebuild the ISO with a GRUB stub that includes the `probe` module:
```bash
./PhotonOS-HABv4Emulation-ISOCreator -b
```

The current version includes `probe` in the grub2-mkimage command.

### "error: module `gfxmenu' isn't loaded"

**Cause**: GRUB stub was built without the `gfxmenu` module. This module is required for themed menus with background images.

**Impact**: The menu will display without theming/background. May show garbled characters.

**Solution**: Rebuild the ISO with a GRUB stub that includes `gfxmenu`, `png`, `jpeg`, `tga`, and `gfxterm_background` modules:
```bash
./PhotonOS-HABv4Emulation-ISOCreator -b
```

### "photon.media=UUID=" (Empty UUID)

**Cause**: The `probe` command failed or wasn't executed. The kernel command line shows `photon.media=UUID=` without an actual UUID.

**Impact**: The installer cannot locate the installation media (ISO filesystem).

**Solutions**:
1. Ensure the GRUB stub includes the `probe` module
2. Verify the grub.cfg contains: `probe -s photondisk -u ($root)`
3. Rebuild the ISO:
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -b
   ```

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

### CRITICAL: Laptop Firmware MOK vs Shim's MokManager

This is the most important distinction for troubleshooting Secure Boot issues on consumer laptops.

**Two Different MOK Systems**:

| Aspect | Laptop Firmware MOK | Shim's MokManager |
|--------|---------------------|-------------------|
| **Where** | Built into UEFI firmware | Loaded from USB by shim |
| **UI** | Manufacturer-specific (Dell gray, HP red, Lenovo ThinkShield) | **Standard blue screen** with white text |
| **Storage** | Firmware's PK/KEK/db variables | Shim's MokList NVRAM variable |
| **What it trusts** | Only entries in UEFI db | Entries in MokList |
| **Works with Ventoy-style boot** | **NO** | **YES** |

**How to Tell Which One You're Using**:

- **Shim's MokManager (CORRECT)**: Blue screen with white text, options include:
  - "Enroll key from disk"
  - "Enroll hash from disk"
  - "Delete key"
  - "Delete hash"
  - "Reboot" / "Power off"

- **Laptop's Firmware MOK (WRONG)**: Manufacturer-branded dialog:
  - Dell: Gray/white "Secure Boot Violation" or "Security Alert"
  - HP: Red/white security warning dialog
  - Lenovo: ThinkShield or gray security dialog
  - Other: Usually branded with manufacturer logo

**Why This Matters**:

When you enroll a certificate in the laptop's firmware MOK:
1. The certificate goes into the firmware's db (UEFI Secure Boot database)
2. Shim does NOT check this database for MOK certificates
3. Shim only checks its own MokList variable
4. **Result**: Enrollment appears to succeed but shim still rejects the loader

**If You See Laptop's Firmware Dialog Instead of Blue MokManager**:

1. **Disable CSM/Legacy boot** in BIOS setup
2. **Enable pure UEFI mode** (not hybrid)
3. Verify **Secure Boot is enabled** (not in setup mode)
4. Ensure booting from USB in UEFI mode (look for "UEFI: USB" in boot menu)
5. Reboot and try again

**Use the Diagnose Feature**:

```bash
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/your.iso
```

This will verify the ISO structure and show first-boot checklist.

### "Failed to open \EFI\BOOT\MokManager.efi - Not Found"

**Cause**: MokManager installed with wrong filename (mmx64.efi instead of MokManager.efi).

**Solutions**:
1. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (fixed)
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
4. If missing, rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator

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

**Cause**: Multiple possible causes:

1. **Wrong MokManager loaded** (most common): Shim looks for `\mmx64.efi` at the ROOT of the EFI partition, not in `\EFI\BOOT\`. If it's missing from ROOT, shim falls back to the laptop's built-in or previously-installed MokManager, which writes to a different MOK database.

2. **NVRAM write issues**: Some firmwares have issues with certificate enrollment or limited NVRAM.

**Solutions**:

1. **Verify you're using the correct MokManager** (most important):
   - The MokManager from your USB should have "Enroll key from disk", "Enroll hash from disk", "Delete key", etc.
   - If you only see minimal options, you're using the laptop's built-in MokManager
   - **Fix**: Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator which places `mmx64.efi` at ROOT level

2. Try **hash enrollment** instead of certificate enrollment:
   - Select "Enroll hash from disk" in MokManager
   - Navigate to `EFI/BOOT/` and select `grub.efi`
   - This enrolls the binary hash which some firmwares handle better

3. Always select **Reboot** from MokManager menu (don't power off)

4. Some firmwares require BIOS/UEFI setup password to be set before MOK can write to NVRAM

5. Try enrolling `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` to get both VMware and MOK in one operation

### MOK enrollment silently fails (no confirmation after "Continue")

**Cause**: The MokManager being used is NOT from your USB - it's the laptop's built-in or a previously-installed one.

**Symptoms**:
- After selecting "Continue" to enroll, no confirmation dialog appears
- MokManager has limited options (no "Delete key", "Reset MOK", etc.)
- Hash/certificate enrollment appears to succeed but doesn't persist

**Root Cause**: SUSE shim looks for MokManager at `\MokManager.efi` (ROOT of EFI partition).
If MokManager is only in `\EFI\BOOT\`, shim can't find it and falls back to another MokManager (from NVRAM or internal drive).

**Solution**: Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator which places SUSE MokManager at:
- `\MokManager.efi` (ROOT) - **Primary path** for SUSE shim
- `\EFI\BOOT\MokManager.efi` - fallback

**How to verify you have the correct MokManager**:
- SUSE MokManager shows: "Enroll key from disk", "Enroll hash from disk", **"Delete key"**, "Delete hash", "Reboot", "Power off"
- If "Delete key" option is missing, you're using the wrong (built-in) MokManager

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
2. Use latest PhotonOS-HABv4Emulation-ISOCreator (auto-resizes)

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

### Black screen after "UEFI Secure Boot is enabled" message (Installed System)

**Cause**: The ESX kernel has USB drivers compiled as **modules** (not built-in), but the initrd generated during installation doesn't include them.

**Explanation**:
- The **ISO installer** boots fine because VMware's installer initrd includes all necessary drivers
- The **installed system** generates a new initrd via dracut during package installation
- Dracut doesn't detect USB boot requirement and omits USB drivers
- Result: Kernel loads but cannot access root filesystem on USB device

**Key drivers needed for USB boot** (all are modules in ESX kernel):
- `usbcore`, `usb-common` - USB core subsystem
- `xhci_hcd`, `xhci_pci` - USB 3.x host controller
- `ehci_hcd`, `ehci_pci` - USB 2.0 host controller
- `uhci_hcd` - USB 1.x host controller
- `usb_storage` - USB mass storage

**Manual Fix for Existing Installation**:
```bash
# Mount installed system
mount /dev/sdX3 /mnt/sdd_root
mount --bind /dev /mnt/sdd_root/dev
mount --bind /sys /mnt/sdd_root/sys
mount --bind /proc /mnt/sdd_root/proc

# Rebuild module dependencies and regenerate initrd with USB drivers
chroot /mnt/sdd_root /sbin/depmod -a $(ls /mnt/sdd_root/lib/modules/)
chroot /mnt/sdd_root /usr/sbin/dracut -f \
    --add-drivers "usbcore usb-common xhci_hcd xhci_pci ehci_hcd ehci_pci uhci_hcd usb_storage" \
    /boot/initrd.img-$(ls /mnt/sdd_root/lib/modules/) \
    $(ls /mnt/sdd_root/lib/modules/)

# Cleanup
umount /mnt/sdd_root/{proc,sys,dev}
umount /mnt/sdd_root
```

**Permanent Fix**: Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.8.0+). The linux-mok package's `%post` script now includes USB drivers in dracut command.

**Verification**:
```bash
# Check if USB drivers are in initrd
lsinitrd /boot/initrd.img-* | grep -E "usbcore|xhci|ehci"
```

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
| grub.efi Not Found | Missing file | Rebuild ISO (v1.7.0+ installs both names) |
| search.c: no such device | GRUB searching for ISO path | Rebuild ISO (v1.7.0+ fixes embedded config) |
| Installation takes 2000+ seconds | USB autosuspend issue | Rebuild ISO (v1.7.0+ adds usbcore.autosuspend=-1) |
| rpm transaction failed | Package conflicts | Rebuild ISO (v1.7.0+ fixes Obsoletes) |
| bad shim signature | Wrong trust chain | Use Fedora shim + Fedora MokManager |
| MokManager.efi Not Found | Wrong filename or missing from efiboot.img | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Security Violation (first boot) | MOK certificate not enrolled | Enroll certificate from root `/` |
| Certificate not visible | File missing | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Enrollment doesn't persist | Wrong MokManager loaded | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Enrollment silently fails | Wrong MokManager (no confirmation) | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| MokManager missing "Delete key" | Using laptop's built-in MokManager | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Security Violation | Unsigned binary | Enroll Photon OS MOK certificate |
| Lockdown: unsigned module | Unsigned .ko | Use matching kernel+modules |
| No space left (efiboot.img) | Image too small | Resize to 16MB |
| Need to delete MOK keys | Keys enrolled | Use mokutil --delete |
| GRUB drops to prompt | Using Ventoy stub (64KB) instead of full GRUB | Use VMware's GRUB, sign with MOK key |
| GRUB drops to prompt | Missing grub.cfg (if full GRUB) | Add bootstrap grub.cfg |
| Commands not found at grub> | Ventoy stub lacks commands | Use full GRUB binary (>1MB) |
| can't find command 'reboot' | VMware GRUB missing module | Use "UEFI Firmware Settings" or Ctrl+Alt+Del |
| grubx64_real.efi not found | GRUB stub search failed | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| BOOT BLOCKED (no Continue) | eFuse USB missing/invalid | Insert eFuse USB or rebuild without eFuse requirement |
| eFuse USB not detected | Wrong label or not FAT32 | Recreate with `-u /dev/sdX` option |

### MokManager Path Reference

SUSE shim looks for MokManager at ROOT level:

| Location | Purpose |
|----------|---------|
| `\MokManager.efi` (ROOT) | **Primary path** - SUSE shim looks here first |
| `\EFI\BOOT\MokManager.efi` | Fallback location |

**Current ISO places SUSE MokManager at 4 locations** (ISO ROOT, ISO EFI/BOOT, efiboot ROOT, efiboot EFI/BOOT).
