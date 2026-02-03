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

### "rpm transaction failed" during installation (Error 1525)

**Cause**: Package conflicts between MOK packages and original packages.

**Common issues**:
- `Obsoletes` with version constraint fails when original has higher version
- File conflicts between `grub2-efi-image` and `grub2-efi-image-mok` (both install `/boot/efi/EFI/BOOT/grubx64.efi`)
- MOK packages not indexed in repodata
- `minimal` meta-package pulls in original packages that conflict with MOK packages

**Root Cause (v1.9.18 fix)**:
The `minimal` meta-package requires `grub2-efi-image >= 2.06-15`. When installing MOK packages alongside `minimal`, tdnf may select BOTH `grub2-efi-image` (to satisfy minimal's dependency) AND `grub2-efi-image-mok` (explicitly requested). Both packages install `/boot/efi/EFI/BOOT/grubx64.efi`, causing a file conflict.

Even with Epoch:1 on MOK packages, tdnf may not recognize that the explicitly requested MOK package satisfies the meta-package dependency, resulting in both packages being selected for the transaction.

**Root Cause (v1.9.16 fix)**:
The MOK packages used `Obsoletes: linux < %{version}-%{release}` but when building a custom kernel (e.g., 6.1.159), this doesn't obsolete the original ISO's newer kernel (e.g., 6.12.60). RPM sees both packages as valid and fails the transaction.

**Solutions**:
1. Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.9.18+)
2. v1.9.18 introduces dynamic meta-package expansion:
   - `packages_mok.json` no longer contains `minimal` meta-package
   - Instead, all `minimal` dependencies are listed directly
   - `grub2-efi-image` is replaced with `grub2-efi-image-mok`
   - This prevents tdnf from selecting conflicting packages
3. MOK packages now have Epoch in Provides lines (e.g., `grub2-efi-image = 1:2.12-1.ph5`)
4. Previous fixes still applied:
   - `Conflicts` prevents both packages from being installed
   - `linux-mok` only includes kernel files (not `/boot/efi`)
   - Repodata regenerated after adding MOK packages

**Manual verification**:
```bash
# Check packages_mok.json doesn't contain 'minimal'
mount -o loop /path/to/secureboot.iso /mnt
zcat /mnt/isolinux/initrd.img | cpio -idm
cat installer/packages_mok.json | grep -q '"minimal"' && echo "ERROR: minimal present" || echo "OK: minimal expanded"
```

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
2. Select "Retry - Rescan USB devices and check for eFuse" after inserting
3. If you don't have an eFuse USB, rebuild ISO without eFuse requirement:
   ```bash
   ./PhotonOS-HABv4Emulation-ISOCreator -r 5.0 -b
   ```

### eFuse USB plugged in after boot not detected (v1.9.34 Fix)

**Cause**: GRUB caches USB devices at startup. The old `configfile` reload only reloads the config without rescanning USB devices.

**Symptoms**:
- You plug in eFuse USB dongle AFTER GRUB has started
- Select "Retry" menu option
- GRUB still shows "eFuse USB Required" even though USB is now inserted

**Solution (v1.9.34+)**: Fixed by using `chainloader` instead of `configfile` to reload GRUB:
- `chainloader /EFI/BOOT/grubx64.efi` loads and executes a new GRUB EFI binary
- The new GRUB instance reinitializes all modules including USB
- USB devices plugged in after initial boot are now detected

**User experience**: Plug in eFuse USB at the prompt, then select "Retry - Rescan USB devices" - the newly inserted USB will be detected.

### eFuse USB not detected even when inserted (v1.9.17 Fix)

**Cause**: GRUB stub was missing modules required for USB device detection and label-based search.

**Symptoms**:
- eFuse USB dongle is properly formatted with label `EFUSE_SIM`
- Contains valid `/efuse_sim/srk_fuse.bin` file
- GRUB still shows "HABv4 SECURITY: eFuse USB Required" message
- Selecting "Retry" doesn't detect the USB

**Root Cause**: The GRUB stub included the `search` module but NOT:
- `search_label` - Required for `search --label` command
- `usb`, `usbms`, `scsi`, `disk` - Required for USB device detection

**Solution (v1.9.17+)**: Fixed by adding all required modules to grub2-mkimage:
- `search_label`, `search_fs_uuid`, `search_fs_file` - All search variants
- `usb`, `usbms`, `scsi`, `disk` - USB and storage device support

**If using older ISO (pre-v1.9.17)**: Rebuild ISO with PhotonOS-HABv4Emulation-ISOCreator v1.9.17+

---

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

### "Loading of unsigned module is rejected" (Installed System Boot)

**Cause**: The installed system's kernel modules had their signatures stripped during RPM build.

**Background**: RPM's `brp-strip` automatically strips ELF binaries during package creation. The `strip` command removes the PKCS#7 signatures appended to kernel modules by the kernel build process. The kernel built with `CONFIG_MODULE_SIG_FORCE=y` then rejects all unsigned modules.

**Symptoms**:
- System boots past GRUB, shows kernel messages
- Errors like: `Loading of unsigned module is rejected` for loop, dm_mod, drm, fuse, etc.
- System enters emergency mode
- `[FAILED] Failed to mount /boot/efi`

**Diagnosis**:
```bash
# Check if modules are signed (should show "~Module signature appended~")
tail -c 50 /lib/modules/*/kernel/drivers/block/loop.ko | hexdump -C

# Signed module shows:
# ...7e 4d 6f 64 75 6c 65 20 73 69 67 6e 61 74 75 72 65 20 61 70 70 65 6e 64 65 64 7e 0a
# (~Module signature appended~)

# Unsigned/stripped module shows only zeros at the end
```

**Solution (v1.9.4+)**: Fixed in v1.9.4 by adding to linux-mok.spec:
```spec
%define __strip /bin/true
%define __brp_strip /bin/true
```

This prevents RPM from stripping module signatures during package build.

**If using older ISO (pre-v1.9.4)**: Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator.

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

**Root Cause (Fixed in v1.9.1)**: The custom kernel build was not being packaged into the `linux-mok` RPM. The installed system received the standard kernel (modules as external files) instead of the custom-built kernel (USB drivers as built-in).

**Historical Issue (v1.9.0)**:
- Tool built custom kernel with `CONFIG_USB=y` (USB drivers built into kernel image)
- But `rpm_secureboot_patcher` only re-signed the standard kernel from original RPM
- Installed system got standard kernel with USB as modules (not built-in)
- Without proper module loading, system froze at boot

**Permanent Fix (v1.9.1+)**: The `linux-mok` RPM now correctly contains the custom-built kernel and modules:
- Custom kernel binary injected during RPM build (replaces standard kernel)
- Custom modules directory injected (replaces standard modules)
- `%post` script detects correct kernel version even if filename differs
- Result: Installed system has USB drivers built into kernel, boots reliably

**If Using Older ISO (v1.8.0-v1.9.0 - Module-Based Approach)**:

The ESX kernel has USB drivers compiled as **modules** (not built-in), and the initrd must include them.

**Manual Fix for v1.8.0-v1.9.0 Installation**:
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

**Recommended**: Rebuild ISO with latest PhotonOS-HABv4Emulation-ISOCreator (v1.9.1+) for the built-in USB driver approach.

**Verification**:
```bash
# Check kernel config (v1.9.1+ should show =y)
zgrep CONFIG_USB /proc/config.gz

# For older versions, check if USB drivers are in initrd
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

## Driver Integration Issues (v1.9.5-v1.9.12)

### Installer fails with "No matching packages not found" (v1.9.11 Fix, v1.9.12 Permanent Fix)

**Cause**: packages_mok.json referenced packages not available in Photon OS 5.0 repositories.

**Symptoms**:
- Installer starts but fails during package installation
- `/var/log/installer.log` shows: "Error(1011) : No matching packages not found or not installed"
- Installation unmounts and shows exception traceback

**Root Cause (v1.9.10)**: Added `wireless-regdb` and `iw` to packages_mok.json but these packages don't exist in Photon OS 5.0 repos.

**Solution (v1.9.11)**: Temporarily removed packages from packages_mok.json.

**Permanent Solution (v1.9.12)**: Built `wireless-regdb` and `iw` packages from upstream sources:
- `wireless-regdb-2024.01.23-1.ph5.noarch.rpm` from kernel.org
- `iw-6.9-1.ph5.x86_64.rpm` from kernel.org
- Packages are in `drivers/RPM/` and integrated when using `--drivers` flag
- Build script `drivers/build-wireless-packages.sh` available for rebuilding

**Note**: For full WiFi regulatory support (80MHz channels, DFS):
1. Use `--drivers` flag when building ISO to include wireless packages
2. Or set regulatory domain via kernel parameter: `cfg80211.ieee80211_regdom=US`

### "80MHz not supported, disabling VHT" WiFi warning (v1.9.13 Fix)

**Cause**: Intel iwlwifi uses LAR (Location Aware Regulatory) which gets regulatory info from firmware, not system regulatory database.

**Symptoms**:
- WiFi connects but limited to 40MHz channel width
- dmesg shows: "80MHz not supported, disabling VHT"
- Lower than expected WiFi speeds on 5GHz band
- `iw reg get` shows restrictive regulatory domain

**Root Cause**: Intel WiFi adapters (iwlwifi) use LAR which overrides the system's wireless-regdb with firmware-based geo-location restrictions.

**Solution (v1.9.13+)**: The `wifi-config` package automatically:
- Creates `/etc/modprobe.d/iwlwifi-lar.conf` with `options iwlwifi lar_disable=1`
- This disables LAR and allows the system regulatory database to be used
- Requires reboot after installation to take effect

**Manual workaround for older ISOs**:
```bash
# Create modprobe config to disable LAR
echo "options iwlwifi lar_disable=1" > /etc/modprobe.d/iwlwifi-lar.conf

# Reboot to apply
reboot
```

### wpa_supplicant "group=GCCMP" typo causing connection failures (v1.9.13 Fix)

**Cause**: User-created wpa_supplicant.conf with typo `group=GCCMP` instead of `group=CCMP`.

**Symptoms**:
- WARNING in kernel: `ieee80211_add_key+0x221/0x2d0 [mac80211]`
- WiFi authenticates but immediately deauthenticates: "by local choice (Reason: 1=UNSPECIFIED)"
- WPA key installation fails

**Root Cause**: `GCCMP` is not a valid cipher - it should be `CCMP` for WPA2-AES.

**Solution (v1.9.13+)**: The `wifi-config` package creates a correct default `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` with:
```
group=CCMP
pairwise=CCMP
```

**Manual fix**:
```bash
sed -i 's/group=GCCMP/group=CCMP/' /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
systemctl restart wpa_supplicant@wlan0
```

### GRUB splash screen not showing on installed system (v1.9.10 Fix)

**Cause**: eFuse verification code switches to `terminal_output console` for the error message but never restores `terminal_output gfxterm` after successful verification.

**Symptoms**:
- Installed system built with `--efuse-usb` shows text-mode GRUB menu instead of themed splash
- Boot menu shows "Photon" in plain text instead of graphical theme
- eFuse verification works correctly (blocks boot without dongle)

**Root Cause**: The eFuse verification code injected into mk-setup-grub.sh template was missing `terminal_output gfxterm` after the verification block.

**Solution (v1.9.10+)**: Fixed by adding `terminal_output gfxterm` after the eFuse verification `fi` statement.

**If using older ISO with eFuse mode (v1.9.9)**: Rebuild ISO with PhotonOS-HABv4Emulation-ISOCreator v1.9.10+

### Malformed wpa_supplicant.conf causing WiFi failures

**Cause**: User-created wpa_supplicant.conf with incorrect cipher specifications.

**Symptoms**:
- wpa_supplicant reports "Failed to set GTK to the driver"
- WiFi authentication succeeds but key installation fails
- Configuration shows `group=GROUP5180 5200...` instead of cipher names

**Root Cause**: The `group=` parameter expects cipher names (CCMP, TKIP, etc.), not frequency values. Example malformed config:
```
group=GROUP5180 5200 5220...  # WRONG - these are frequencies
```

**Solution**: Fix wpa_supplicant.conf manually:
```bash
# For WPA2-only (recommended):
group=CCMP
pairwise=CCMP

# For WPA/WPA2 mixed (legacy):
group=CCMP TKIP
pairwise=CCMP TKIP
```

**Note**: v1.9.10 removed TKIP crypto support (MICHAEL_MIC, ARC4) since modern WPA2-AES networks don't need it. If you specifically need TKIP for legacy networks, you'll need to rebuild the kernel with those configs manually.

### Wi-Fi kernel panic during WPA key installation (v1.9.8 Fix)

**Cause**: WiFi driver mappings enabled WiFi subsystem configs but not the crypto algorithms required by mac80211 for WPA2/WPA3 key management.

**Symptoms**:
- WiFi driver loads successfully
- Association and authentication start
- Kernel panic at `mac80211_new_key+0x138` during key installation
- System freezes or reboots during WiFi connection
- wpa_supplicant reports: "Failed to set GTK to the driver"

**Root Cause**: The mac80211 subsystem requires specific crypto algorithms for CCMP/GCMP encryption used in WPA2/WPA3:
- `CONFIG_CRYPTO_CCM=y` - Counter with CBC-MAC (for CCMP)
- `CONFIG_CRYPTO_GCM=y` - Galois/Counter Mode (for GCMP)
- `CONFIG_CRYPTO_CMAC=y` - Cipher-based MAC (for key management)
- `CONFIG_CRYPTO_AES=y` - AES cipher (core encryption)
- `CONFIG_CRYPTO_AEAD=y` - Authenticated Encryption
- `CONFIG_CRYPTO_SEQIV=y` - Sequence Number IV Generator
- `CONFIG_CRYPTO_CTR=y` - Counter Mode
- `CONFIG_CRYPTO_GHASH=y` - GHASH message digest (for GCM)

**Solution (v1.9.8+)**: Fixed by adding all 8 crypto configs to every WiFi driver mapping in `DRIVER_KERNEL_MAP[]`.

**If using older ISO (v1.9.5-v1.9.7)**: Rebuild ISO with PhotonOS-HABv4Emulation-ISOCreator v1.9.8+

**Verification**:
```bash
# Check crypto algorithm configs in kernel
zgrep -E "CONFIG_CRYPTO_(CCM|GCM|CMAC|AES|AEAD|SEQIV|CTR|GHASH)" /proc/config.gz
# All should show =y
```

### Wi-Fi not working - Kernel config mismatch (v1.9.7 Fix)

**Cause**: The `boot/config-*` file in the linux-mok RPM was from the original Photon kernel, not the rebuilt custom kernel. Even though the kernel itself was built with WiFi configs enabled, the installed system's config file showed `CONFIG_WIRELESS is not set`.

**Symptoms**:
- Modules load but wpa_supplicant reports: "Failed to set GTK to the driver"
- WiFi authentication succeeds but association fails
- `/boot/config-*` shows `CONFIG_WIRELESS is not set` despite modules being present
- `dmesg` shows WiFi driver loaded but key installation fails

**Root Cause**: The spec file extracted the config file from the original RPM but didn't replace it with the custom kernel's `.config` during custom kernel injection.

**Solution (v1.9.7+)**: Fixed by adding code to copy the kernel `.config` from the build directory to `boot/config-*` during custom kernel injection in the %prep section.

**If using older ISO (v1.9.5-v1.9.6)**: Rebuild ISO with PhotonOS-HABv4Emulation-ISOCreator v1.9.7+

### Wi-Fi not working - No kernel modules (v1.9.6 Fix)

**Cause**: Photon ESX kernel has `CONFIG_WIRELESS=n CONFIG_WLAN=n` by default, preventing all WiFi driver modules from being built - even when the driver-specific config is set (e.g., `CONFIG_IWLWIFI=m`).

**Symptoms**:
- Firmware files are present in `/lib/firmware/iwlwifi-*`
- `modprobe iwlwifi` fails with "module not found"
- `find /lib/modules -name "*iwl*"` returns nothing
- WiFi adapter not recognized (`ip link` shows no wlan interface)

**Root Cause**: WiFi drivers require these prerequisite kernel configs:
```kconfig
CONFIG_WIRELESS=y     # Enable wireless subsystem
CONFIG_WLAN=y         # Enable WLAN support
CONFIG_CFG80211=m     # 802.11 configuration API  
CONFIG_MAC80211=m     # IEEE 802.11 networking stack
```

**Solution (v1.9.6+)**: Fixed in v1.9.6 by adding prerequisite configs to all WiFi driver mappings. The `DRIVER_KERNEL_MAP` now includes:
- `CONFIG_WIRELESS=y CONFIG_WLAN=y CONFIG_CFG80211=m CONFIG_MAC80211=m` for all WiFi drivers

**If using older ISO (v1.9.5)**: Rebuild ISO with PhotonOS-HABv4Emulation-ISOCreator v1.9.6+

**Verification**:
```bash
# Check WiFi subsystem configs in built kernel
zgrep -E "CONFIG_(WIRELESS|WLAN|CFG80211|MAC80211)" /proc/config.gz
# Should show: =y or =m for all four

# Check WiFi modules are present
find /lib/modules -name "cfg80211*" -o -name "mac80211*" -o -name "iwlwifi*"
```

### Wi-Fi not working - Firmware missing

**Cause**: Driver firmware not installed or kernel module not loaded.

**Solutions**:
1. Verify firmware package was installed:
   ```bash
   rpm -qa | grep -i firmware
   ```
2. Check if kernel module is available:
   ```bash
   modinfo iwlwifi
   ```
3. Check if firmware files are present:
   ```bash
   ls /lib/firmware/iwlwifi-*
   ```
4. Check dmesg for driver errors:
   ```bash
   dmesg | grep -i iwlwifi
   ```
5. Rebuild ISO with `--drivers` if firmware RPM was missing

### Driver not detected during kernel build

**Cause**: RPM filename doesn't match known driver patterns.

**Solutions**:
1. Check if RPM name contains a supported pattern (iwlwifi, rtw88, brcmfmac, etc.)
2. Add a new mapping entry in `PhotonOS-HABv4Emulation-ISOCreator.c` for unsupported driver types
3. Rebuild the tool with `make` and re-run ISO build

### "firmware failed to load" errors in dmesg

**Cause**: Firmware files don't match what the driver expects.

**Solutions**:
1. Check exact firmware filenames the driver is looking for:
   ```bash
   dmesg | grep "firmware"
   ```
2. Verify the firmware RPM contains the required files
3. Some drivers require specific firmware versions - check driver documentation

---

## Quick Reference

### Installer GPG Verification Failure (v1.9.14 Fix)

**Cause**: When using `--rpm-signing` (v1.9.12+), the installer can't verify GPG-signed MOK packages because the signing key is HABv4's key, not VMware's.

**Symptoms**:
- Installer fails during package verification
- Error: "package verification failed" or GPG signature errors
- `tdnf install` fails with signature verification errors

**Root Cause**: `photon-iso.repo` references `/etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY` which:
1. Doesn't exist in initrd until `photon-repos` package is installed
2. Even if it existed, it's VMware's key, not HABv4's signing key

**Solution (v1.9.14+)**: Fixed by installing multiple GPG keys in initrd:
- Extract VMware's GPG keys (VMWARE-RPM-GPG-KEY, VMWARE-RPM-GPG-KEY-4096) from `photon-repos` RPM
- Install HABv4 key as `RPM-GPG-KEY-habv4`
- Update `photon-iso.repo` to reference all three keys (space-separated for tdnf compatibility)

**If using older ISO (v1.9.12-v1.9.13)**: Rebuild ISO with PhotonOS-HABv4Emulation-ISOCreator v1.9.14+

---

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
| rpm transaction failed (Error 1525) | MOK version < original version | Rebuild ISO (v1.9.16+ uses Conflicts) |
| bad shim signature | Wrong trust chain | Use Fedora shim + Fedora MokManager |
| MokManager.efi Not Found | Wrong filename or missing from efiboot.img | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Security Violation (first boot) | MOK certificate not enrolled | Enroll certificate from root `/` |
| Certificate not visible | File missing | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Enrollment doesn't persist | Wrong MokManager loaded | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Enrollment silently fails | Wrong MokManager (no confirmation) | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| MokManager missing "Delete key" | Using laptop's built-in MokManager | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| Security Violation | Unsigned binary | Enroll Photon OS MOK certificate |
| Loading of unsigned module rejected | Module signatures stripped by RPM | Rebuild ISO (v1.9.4+ preserves signatures) |
| Lockdown: unsigned module | Unsigned .ko | Use matching kernel+modules |
| No space left (efiboot.img) | Image too small | Resize to 16MB |
| Need to delete MOK keys | Keys enrolled | Use mokutil --delete |
| GRUB drops to prompt | Using Ventoy stub (64KB) instead of full GRUB | Use VMware's GRUB, sign with MOK key |
| GRUB drops to prompt | Missing grub.cfg (if full GRUB) | Add bootstrap grub.cfg |
| Commands not found at grub> | Ventoy stub lacks commands | Use full GRUB binary (>1MB) |
| can't find command 'reboot' | VMware GRUB missing module | Use "UEFI Firmware Settings" or Ctrl+Alt+Del |
| grubx64_real.efi not found | GRUB stub search failed | Rebuild with PhotonOS-HABv4Emulation-ISOCreator |
| BOOT BLOCKED (no Continue) | eFuse USB missing/invalid | Insert eFuse USB or rebuild without eFuse requirement |
| eFuse USB not detected (label/format) | Wrong label or not FAT32 | Recreate with `-u /dev/sdX` option |
| eFuse USB not detected (GRUB) | Missing GRUB modules | Rebuild ISO (v1.9.17+ adds search_label, usb, usbms) |
| eFuse not enforced on installed system | mk-setup-grub.sh overwrites %posttrans | Rebuild ISO (v1.9.9+ injects into template) |
| Wi-Fi kernel panic during WPA connect | Missing crypto algorithms (CCM, GCM, etc.) | Rebuild ISO (v1.9.8+ adds crypto configs) |
| Package names have `.ph5.ph5` | `%{?dist}` in spec doubles dist tag | Rebuild ISO (v1.9.6+ removes `%{?dist}`) |
| Wi-Fi modules not found | Photon ESX has WIRELESS=n WLAN=n | Rebuild ISO (v1.9.6+ adds WiFi prerequisites) |
| "80MHz not supported, disabling VHT" | iwlwifi LAR overrides regulatory | Rebuild with `--drivers` (v1.9.13+ disables LAR) |
| Installer fails "packages not found" | wireless-regdb/iw not in Photon 5.0 | Rebuild ISO with `--drivers` (v1.9.12+ includes packages) |
| WiFi auth fails with ieee80211_add_key WARNING | group=GCCMP typo | Rebuild with `--drivers` (v1.9.13+ has correct config) |
| GRUB splash not showing (eFuse mode) | eFuse code doesn't restore gfxterm | Rebuild ISO (v1.9.10+ restores gfxterm) |
| Installer GPG verification fails | HABv4 key not in initrd | Rebuild ISO (v1.9.14+ installs multi-key) |

### MokManager Path Reference

SUSE shim looks for MokManager at ROOT level:

| Location | Purpose |
|----------|---------|
| `\MokManager.efi` (ROOT) | **Primary path** - SUSE shim looks here first |
| `\EFI\BOOT\MokManager.efi` | Fallback location |

**Current ISO places SUSE MokManager at 4 locations** (ISO ROOT, ISO EFI/BOOT, efiboot ROOT, efiboot EFI/BOOT).
