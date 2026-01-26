---
name: photonos-secureboot-iso
description: |
  Create UEFI Secure Boot enabled Photon OS ISOs for physical hardware.
  Handles MOK enrollment, custom GRUB stub, RPM signing, and kickstart installation.
  Use when building bootable ISOs for laptops/servers with Secure Boot enabled.
---

# PhotonOS HABv4 Secure Boot ISO Creation Skill

## Overview

This skill covers creating Secure Boot enabled ISOs for Photon OS that work on consumer laptops and servers with UEFI Secure Boot enabled. The tool creates modified ISOs using:

- **SUSE shim** (Microsoft-signed, SBAT compliant)
- **Custom GRUB stub** (MOK-signed, without `shim_lock`)
- **MOK-signed kernel and packages**
- **Kickstart-based installation** for reliable package selection

## The Problem We Solve

**Original Photon OS ISOs fail on Secure Boot enabled hardware** because:
1. VMware's shim has `shim_lock` that rejects custom/unsigned kernels
2. The kernel isn't signed with a key in MokList
3. Installed packages use VMware's signing, not user-controlled keys

**Our solution:**
1. Replace VMware shim with Microsoft-signed SUSE shim
2. Build custom GRUB stub without `shim_lock`, sign with MOK
3. Sign kernel with MOK
4. Create `-mok` variant RPM packages for installed system

## Quick Reference

### Build Commands

```bash
# Build Secure Boot ISO (simplest - does everything)
./PhotonOS-HABv4Emulation-ISOCreator -b

# Build for specific release
./PhotonOS-HABv4Emulation-ISOCreator --release 6.0 --build-iso

# Build with RPM signing (compliance: NIST 800-53, FedRAMP, EU CRA)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# Build with eFuse USB verification
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --efuse-usb --create-efuse-usb=/dev/sdX -y

# Diagnose existing ISO
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-b`, `--build-iso` | Build Secure Boot ISO |
| `-r`, `--release=VERSION` | Photon OS version: 4.0, 5.0, 6.0 (default: 5.0) |
| `-D`, `--diagnose=ISO` | Diagnose existing ISO |
| `-E`, `--efuse-usb` | Enable eFuse USB verification |
| `-u`, `--create-efuse-usb=DEV` | Create eFuse USB dongle |
| `-R`, `--rpm-signing` | Enable GPG signing of MOK RPMs |
| `-F`, `--full-kernel-build` | Build kernel from source |
| `-c`, `--clean` | Clean all artifacts |
| `-v`, `--verbose` | Verbose output |
| `-y`, `--yes` | Auto-confirm destructive operations |

## Architecture

### Boot Chain (ISO Boot)

```
UEFI Firmware (Microsoft UEFI CA in db)
    ↓ verifies Microsoft signature
BOOTX64.EFI (SUSE shim, SBAT=shim,4)
    ↓ verifies against MokList
grub.efi (Custom GRUB stub, MOK-signed, NO shim_lock)
    ↓ loads grub.cfg with themed menu (5 sec timeout)
    │
    └─→ "Install" → launches interactive installer
        │
        ↓ Package Selection Screen (modified build_install_options_all.json)
        │
        ├─→ "1. Photon MOK Secure Boot" → packages_mok.json
        │   → Installs: linux-mok, grub2-efi-image-mok, shim-signed-mok
        │
        ├─→ "2. Photon Minimal" → packages_minimal.json (original)
        │   → Installs: linux, grub2-efi-image, shim-signed
        │
        └─→ "3-5. Developer/OSTree/RT" → respective package files
```

### Boot Chain (Installed System - MOK Path)

```
UEFI Firmware → shim-signed-mok (SUSE shim + MokManager)
             → grub2-efi-image-mok (Custom GRUB stub, MOK-signed)
             → linux-mok (vmlinuz, MOK-signed)
             ✓ Works on physical hardware with Secure Boot
```

### Why Custom GRUB Stub Without shim_lock

VMware's GRUB includes the `shim_lock` verifier module which calls shim's `Verify()` for kernel loading. While MOK-signed kernels should be accepted (certificate in MokList), we build a custom stub without `shim_lock` to ensure compatibility and provide predictable behavior.

The custom stub:
1. Is verified by shim via MOK signature (chain maintained)
2. Excludes `shim_lock` (no unpredictable kernel verification)
3. Contains SBAT metadata (passes shim policy check)
4. Includes modules for theming: `probe`, `gfxmenu`, `png`, `jpeg`, `tga`

## RPM Secure Boot Patcher

The tool includes an integrated RPM patcher that creates MOK-signed variant packages:

| Original Package | MOK Package | Contents |
|-----------------|-------------|----------|
| `shim-signed` | `shim-signed-mok` | SUSE shim (Microsoft-signed) + MokManager |
| `grub2-efi-image` | `grub2-efi-image-mok` | Custom GRUB stub (MOK-signed, no shim_lock) |
| `linux` / `linux-esx` | `linux-mok` | MOK-signed vmlinuz + boot files |

### Package Discovery (Version-Agnostic)

The patcher discovers packages by file paths, not version numbers:
- `grub2-efi-image`: provides `/boot/efi/EFI/BOOT/grubx64.efi`
- `linux`: provides `/boot/vmlinuz-*`
- `shim-signed`: provides `/boot/efi/EFI/BOOT/bootx64.efi`

### SPEC File Generation

Generated specs include:
- Proper `Provides:` (same capability as original)
- `Conflicts:` (prevents installing both)
- MOK-signed binaries
- MokManager in `shim-signed-mok`

## Interactive Installation with MOK Package Option (v1.6.0)

The ISO uses a **fully interactive installer** with MOK packages added to the package selection menu. This is **Option C** from the architecture decision record (see ADR-001 in DROID_SKILL_GUIDE.md).

### How It Works

1. **Single GRUB menu entry**: "Install" launches the interactive installer
2. **No kickstart files**: Full interactive experience (EULA, disk, hostname, password)
3. **Modified `build_install_options_all.json`**: Adds "Photon MOK Secure Boot" as first option
4. **New `packages_mok.json`**: Contains MOK-signed packages

### Initrd Modifications

The tool modifies the initrd to:

1. **Create `packages_mok.json`** in `/installer/`:
```json
{
    "packages": [
        "minimal", "linux-mok", "initramfs",
        "grub2-efi-image-mok", "shim-signed-mok",
        "lvm2", "less", "sudo"
    ]
}
```

2. **Modify `build_install_options_all.json`** to add MOK option first:
```json
{
    "mok": {
        "title": "1. Photon MOK Secure Boot",
        "packagelist_file": "packages_mok.json",
        "visible": true
    },
    "minimal": {
        "title": "2. Photon Minimal",
        ...
    }
}
```

3. **Patch `linuxselector.py`** to recognize `linux-mok` kernel:
```python
linux_flavors = {"linux-mok":"MOK Secure Boot", "linux":"Generic", ...}
```

### Why Interactive Instead of Kickstart

Previous versions (v1.5.0) used kickstart files with `"ui": true`. This failed because:
- **Photon installer architecture**: Interactive UI only runs when NO kickstart is provided
- **`ui: true` misconception**: Only controls progress bars, not the configuration wizard
- **Missing required fields**: Kickstart without disk/hostname caused crashes

The interactive approach (Option C):
- **Full user control**: EULA, disk selection, partitioning, hostname, password
- **Explicit MOK choice**: Users see "Photon MOK Secure Boot" in package selection
- **Preserves options**: All original package options remain available
- **Follows installer patterns**: Uses official `build_install_options_all.json` mechanism

## Kernel Build Support

The `--full-kernel-build` option builds kernels from Photon OS sources:

### Directory Structure Supported

| Release | Kernel Source | Config Location |
|---------|--------------|-----------------|
| 4.0 | `/root/4.0/stage/SOURCES/linux-*.tar.xz` | `/root/4.0/SPECS/linux/` |
| 5.0 | `/root/5.0/stage/SOURCES/linux-6.1.*.tar.xz` | `/root/5.0/SPECS/linux/` or `/root/common/SPECS/linux/v6.1/` |
| 6.0 | `/root/6.0/stage/SOURCES/linux-6.12.*.tar.xz` | `/root/common/SPECS/linux/v6.12/` |

### Build Process

1. Auto-detect kernel tarball from `SOURCES/`
2. Extract to `{photon_dir}/kernel-build/linux-{version}/`
3. Apply Photon config (`config-esx_{arch}` preferred for VMs)
4. Configure Secure Boot options:
   - `CONFIG_MODULE_SIG=y`
   - `CONFIG_MODULE_SIG_ALL=y`
   - `CONFIG_MODULE_SIG_SHA512=y`
   - `CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y`
5. Build kernel and modules
6. Sign kernel with MOK key
7. Output to `{keys_dir}/vmlinuz-mok`

## RPM Signing (Optional)

The `--rpm-signing` option enables GPG signing for compliance:

### Compliance Standards Supported

- **NIST SP 800-53**: SI-7 (Software Integrity), CM-14 (Signed Components)
- **FedRAMP**: Requires NIST 800-53 controls
- **EU Cyber Resilience Act**: Article 10 (Software integrity verification)

### Process

1. Generate GPG key pair (`RPM-GPG-KEY-habv4`)
2. Sign all MOK RPMs with `rpmsign`
3. Copy public key to ISO and eFuse USB
4. Import key in kickstart postinstall

### Verification

```bash
rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
rpm -qa *-mok* --qf '%{NAME}\t%{SIGPGP:pgpsig}\n'
```

## eFuse USB Mode

When built with `-E`, boot requires an eFuse USB dongle (label: `EFUSE_SIM`):

```
GRUB Stub
    ↓
Search for USB with LABEL=EFUSE_SIM
    ↓
Check for /efuse_sim/srk_fuse.bin
    ├─→ Valid: Show boot menu
    └─→ Invalid: "BOOT BLOCKED" (only Retry/Reboot)
```

### USB Contents

```
USB (FAT32, LABEL=EFUSE_SIM)
└── efuse_sim/
    ├── srk_fuse.bin          # SRK hash (32 bytes)
    ├── sec_config.bin        # Security mode
    └── efuse_config.json     # Configuration
```

## First Boot Procedure

### Step 1: Write USB
```bash
dd if=photon-5.0-secureboot.iso of=/dev/sdX bs=4M status=progress
sync
```

### Step 2: BIOS Configuration
1. Disable CSM/Legacy boot completely
2. Enable Secure Boot
3. Set USB as first boot device

### Step 3: Enroll MOK (First Boot)
1. **Blue MokManager screen** appears (not laptop's security dialog)
2. Select "Enroll key from disk"
3. Navigate to root `/`
4. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
5. Confirm and select "Reboot"

### Step 4: Install (Second Boot)
1. Themed menu appears
2. Select "Install"
3. Accept EULA, select disk, configure partitions
4. At **Package Selection**, choose **"1. Photon MOK Secure Boot"**
5. Configure hostname and root password
6. Complete installation and reboot

## Troubleshooting Quick Reference

| Error | Cause | Fix |
|-------|-------|-----|
| "bad shim signature" | Selected Photon Minimal on hardware | Select "Photon MOK Secure Boot" |
| Laptop security dialog (not blue MokManager) | CSM enabled | Disable CSM in BIOS |
| Enrollment doesn't persist | Wrong MokManager | Rebuild ISO |
| "Policy Violation" | GRUB SBAT issue | Use latest version |
| grub> prompt | Config not found | Rebuild ISO |
| BOOT BLOCKED | eFuse USB missing | Insert eFuse USB or rebuild without `-E` |
| ZeroDivisionError in linuxselector | linux-mok not recognized | Rebuild ISO (v1.6.0+ fixes this) |
| Installed system fails | Standard packages installed | Reinstall with "Photon MOK Secure Boot" |
| "search.c: no such device" | GRUB searching for ISO path | Rebuild ISO (v1.7.0+ fixes embedded config) |
| Installation takes 2000+ seconds | USB autosuspend | Rebuild ISO (v1.7.0+ adds kernel param) |
| "grub.efi Not Found" | SUSE shim looks for grub.efi | Rebuild ISO (v1.7.0+ installs both names) |
| "rpm transaction failed" | Package conflicts | Rebuild ISO (v1.7.0+ fixes Obsoletes) |

### Detailed Troubleshooting

**Laptop shows gray/red security dialog instead of blue MokManager:**
- This means CSM/Legacy boot is enabled
- The laptop's firmware is handling the violation, not shim's MokManager
- Fix: Disable CSM completely, enable pure UEFI mode

**MOK enrollment appears to succeed but doesn't persist:**
- The wrong MokManager is being used (laptop's built-in)
- SUSE shim looks for MokManager at `\MokManager.efi` (root)
- Fix: Rebuild ISO with latest version (places MokManager correctly)

**Installed system gets "bad shim signature":**
- Standard VMware packages were installed (have shim_lock)
- Fix: Reinstall and select "1. Photon MOK Secure Boot" at package selection

## ISO Structure

```
ISO Root/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer    # MOK certificate
├── MokManager.efi                        # SUSE MokManager
├── EFI/BOOT/
│   ├── BOOTX64.EFI                      # SUSE shim
│   ├── grub.efi                         # Custom GRUB stub
│   ├── grubx64.efi                      # Same as grub.efi
│   ├── grubx64_real.efi                 # VMware GRUB (for standard path)
│   └── MokManager.efi                   # Backup
├── boot/grub2/
│   ├── efiboot.img                      # EFI System Partition
│   └── grub.cfg                         # Boot menu
├── RPMS/x86_64/                         # Original + MOK RPMs
└── isolinux/                            # BIOS boot (legacy)
    ├── vmlinuz                          # MOK-signed kernel
    └── initrd.img
```

## Key Locations

```
/root/hab_keys/
├── MOK.key / MOK.crt / MOK.der          # Machine Owner Key
├── kernel_module_signing.pem             # Kernel module signing key
├── shim-suse.efi                        # SUSE shim (embedded)
├── MokManager-suse.efi                  # SUSE MokManager (embedded)
├── grub-photon-stub.efi                 # Custom GRUB stub (MOK-signed)
├── vmlinuz-mok                          # MOK-signed kernel
└── RPM-GPG-KEY-habv4                    # GPG public key (if --rpm-signing)
```

## GRUB Modules Included

Essential modules in custom GRUB stub:
- `probe` - UUID detection for `photon.media=UUID=$photondisk`
- `gfxmenu` - Themed menus
- `png`, `jpeg`, `tga` - Background images
- `gfxterm_background` - Graphics background
- `search`, `configfile`, `linux`, `initrd` - Core boot
- `chain`, `fat`, `iso9660`, `part_gpt` - Filesystem/chainload

## Embedded Components

SUSE shim components are embedded in `data/`:
- `shim-suse.efi.gz` - SUSE shim (Microsoft-signed, SBAT=shim,4)
- `MokManager-suse.efi.gz` - SUSE MokManager

Extracted automatically during build. No internet required.

## Installer Patches

The tool applies several patches to the photon-os-installer in the initrd:

### 1. Progress Bar Fix (installer.py)
The installer assumes `progress_bar` exists in `exit_gracefully()`. Fix:
- Initialize `self.progress_bar = None` in `__init__()`
- Check for None before accessing in `exit_gracefully()` and `_execute_modules()`

Submitted upstream as PR #39.

### 2. Linux-MOK Recognition (linuxselector.py)
The `LinuxSelector` class has hardcoded kernel flavors. Without this patch, selecting packages with `linux-mok` causes `ZeroDivisionError` (no menu items created).

Fix: Add `"linux-mok": "MOK Secure Boot"` to `linux_flavors` dictionary.

## For Developers Using This Skill

### What I Can Help With

1. **Building ISOs**: Run build commands, diagnose failures
2. **Understanding architecture**: Explain boot chains, signing, verification
3. **Modifying code**: Add features, fix bugs, update documentation
4. **Troubleshooting**: Analyze errors, identify root causes
5. **Compliance**: Explain requirements, implement signing

### Example Interactions

**Build an ISO:**
```
User: Build a Secure Boot ISO for Photon OS 5.0
[I'll run the build command and report results]
```

**Diagnose issues:**
```
User: My ISO gets "bad shim signature" on my laptop
[I'll explain the cause and provide step-by-step fix]
```

**Modify the tool:**
```
User: Add support for custom GRUB themes
[I'll analyze the code, propose changes, implement and test]
```

**Understand the code:**
```
User: How does the RPM patcher work?
[I'll explain the architecture with code references]
```

See [docs/DROID_SKILL_GUIDE.md](../../../docs/DROID_SKILL_GUIDE.md) for complete developer guide.

## Security Measures (v1.8.0)

The tool implements several security measures:

### Input Validation
- **Path validation**: All user-provided paths are validated against shell metacharacters
- **Release whitelist**: Only valid releases (4.0, 5.0, 6.0) are accepted
- **Dangerous character rejection**: Paths containing `;|&$\`\"'` and `..` are rejected

### Secure Temporary Directories
- Uses `mkdtemp()` instead of predictable `/tmp/prefix_PID` patterns
- Temp directories created with random suffixes and 0700 permissions
- Prevents symlink attacks and race conditions (TOCTOU mitigation)

### Log Sanitization
- Private key paths are masked as `[PRIVATE_KEY]` in verbose output
- Prevents accidental disclosure of sensitive paths in logs

### Remaining Security Considerations

| Category | Status | Notes |
|----------|--------|-------|
| Command injection | **Mitigated** | Path validation, but still uses system() |
| Download integrity | **Not implemented** | Ventoy/ISO downloads not checksum verified |
| Key storage | **Plain text** | Keys stored unencrypted on filesystem |
| HSM support | **Not implemented** | No PKCS#11/HSM integration |
| Certificate expiration | **Not checked** | No warning for expired certificates |

For production deployments in regulated environments, consider:
1. Adding SHA256 checksum verification for downloads
2. Using hardware security modules (HSM) for key storage
3. Implementing certificate expiration monitoring
