# HABv4 Secure Boot Simulation Environment

## The Compliance Gap in Open-Source Edge Computing

Modern cybersecurity regulations increasingly mandate **cryptographic verification of boot integrity** and **signed software packages**:

| Regulation | Requirement | Effective |
|------------|-------------|-----------|
| **NIST SP 800-53** | SI-7 (Software Integrity), CM-14 (Signed Components) | US Federal |
| **FedRAMP** | Requires NIST 800-53 controls for cloud services | US Federal |
| **EU Cyber Resilience Act** | Article 10: Software integrity verification | Dec 2024 |
| **NIS2 Directive** | Supply chain security, software integrity | EU Critical Infrastructure |
| **DISA STIGs** | Mandatory Secure Boot for DoD systems | US Defense |

**The problem**: While these regulations are well-supported in enterprise cloud environments, **there is no turnkey solution for deploying compliant open-source Linux on edge hardware**.

VMware Photon OS is a leading cloud-native container host, but its ISOs **fail to boot on physical hardware with UEFI Secure Boot enabled** - making it non-compliant for edge deployments in regulated environments.

---

## Why Cloud-Native Operating Systems Fail at the Edge

### The Cloud-to-Edge Security Gap

Cloud-native operating systems like Photon OS are optimized for **virtualized environments** where:
- The hypervisor provides hardware abstraction
- Secure Boot is either disabled or handled by the VM platform
- Hardware diversity is hidden behind virtual devices
- Kernel configurations target generic x86_64 virtualization

Edge deployments face fundamentally different challenges:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CLOUD ENVIRONMENT                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                      │
│  │   VM 1      │  │   VM 2      │  │   VM 3      │                      │
│  │  Photon OS  │  │  Photon OS  │  │  Photon OS  │                      │
│  └─────────────┘  └─────────────┘  └─────────────┘                      │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │              Hypervisor (ESXi, KVM, Hyper-V)                    │    │
│  │         Provides: Virtual hardware, No real Secure Boot        │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                    Physical Server                               │    │
│  │              Secure Boot: Often disabled for VMs                │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                     EDGE ENVIRONMENT                                     │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                      Photon OS                                   │    │
│  │            Runs directly on hardware (no hypervisor)            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                  Diverse Physical Hardware                       │    │
│  │     • Industrial PCs, Gateways, Embedded Systems                │    │
│  │     • ARM SoCs, x86 Mini-PCs, Rugged Laptops                    │    │
│  │     • UEFI Secure Boot: MANDATORY for compliance                │    │
│  │     • Custom peripherals requiring kernel modifications         │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Three Levels of Kernel Customization

Edge deployments often require kernel modifications at three distinct levels, each presenting unique challenges for Secure Boot compliance:

#### Level 1: Device Tree (ARM/Embedded)

Device Tree Blobs (DTBs) describe hardware topology for ARM and embedded systems:

```
/dts-v1/;
/ {
    model = "Custom Industrial Gateway";
    compatible = "vendor,gateway-v2";
    
    gpio-controller {
        compatible = "custom,gpio-expander";
        reg = <0x20>;
    };
    
    industrial-io {
        compatible = "custom,adc-16bit";
        spi-max-frequency = <1000000>;
    };
};
```

**Challenge**: Device trees are typically unsigned and loaded by the bootloader. Custom hardware requires custom DTBs, which breaks the signed boot chain.

**HABv4 Solution**: MOK-signed DTB overlays loaded through signed GRUB configuration.

#### Level 2: Out-of-Tree Kernel Modules

Edge devices often require drivers not included in mainline Linux:

| Use Case | Module Type | Example |
|----------|-------------|---------|
| Industrial I/O | ADC/DAC drivers | Custom FPGA interfaces |
| Networking | CAN bus, Industrial Ethernet | EtherCAT, PROFINET |
| Security | HSM, TPM extensions | Custom crypto accelerators |
| Sensors | Specialized protocols | Modbus RTU, BACnet |

**Challenge**: Out-of-tree modules must be signed with the same key used to build the kernel. Standard Photon OS kernels don't include the signing key.

**HABv4 Solution**: 
- **Built-in custom kernel build**: Tool always builds kernel from source with embedded signing key
- `CONFIG_MODULE_SIG_KEY` points to user-controlled key
- All modules signed during build, custom modules can be signed post-build

#### Level 3: Kernel Configuration Options

Edge use cases require kernel configs that differ from cloud-optimized defaults:

| Config Category | Cloud Default | Edge Requirement |
|-----------------|---------------|------------------|
| **Real-time** | `PREEMPT_VOLUNTARY` | `PREEMPT_RT` for deterministic latency |
| **Security** | `LOCKDOWN_LSM=n` | `LOCKDOWN_LSM=y` for integrity |
| **Hardware** | Minimal drivers | Full GPIO, SPI, I2C, CAN support |
| **Debug** | Disabled | `KGDB`, `FTRACE` for field debugging |
| **Watchdog** | Generic | Hardware-specific watchdog drivers |

**Critical Secure Boot Configs:**
```kconfig
# Required for Secure Boot compliance
CONFIG_MODULE_SIG=y                        # Require signed modules
CONFIG_MODULE_SIG_FORCE=y                  # Reject unsigned modules
CONFIG_MODULE_SIG_ALL=y                    # Sign all modules during build
CONFIG_MODULE_SIG_SHA512=y                 # Strong hash algorithm
CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY=y  # Kernel lockdown mode
CONFIG_EFI_STUB=y                          # EFI boot support
CONFIG_KEXEC_SIG=y                         # Signed kexec images
```

**HABv4 Solution**: The tool automatically:
1. Starts from Photon OS kernel source
2. Applies user-specified config modifications
3. Enables all Secure Boot options
4. Embeds MOK-compatible signing key
5. Signs resulting kernel with MOK

---

## What This Tool Provides

The HABv4 Secure Boot Simulation Environment bridges the cloud-to-edge gap by providing:

### 1. Compliant Boot Chain

Creates ISOs with a verified boot chain that satisfies regulatory requirements:

```
UEFI Firmware (Microsoft CA) ──verified──▶ SUSE Shim (Microsoft-signed)
                                                    │
                                          ──verified (MokList)──▶ Custom GRUB (MOK-signed)
                                                                          │
                                                               ──loads──▶ Kernel (MOK-signed)
```

### 2. Signed Package Infrastructure

Generates MOK-signed RPM packages that maintain Secure Boot after installation:

| Package | Contents | Compliance |
|---------|----------|------------|
| `shim-signed-mok` | SUSE shim + MokManager | UEFI Secure Boot |
| `grub2-efi-image-mok` | Custom GRUB (no shim_lock) | MOK verification |
| `linux-mok` | MOK-signed kernel | Boot integrity |

### 3. Optional RPM Signing

GPG-signed packages for supply chain integrity (NIST SI-7, EU CRA Article 10):

```bash
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing
```

### 4. Custom Kernel Support

Full kernel build with Secure Boot configuration is now **standard and automatic**.

Supports the Photon OS kernel source directory structure:
- Release 4.0: `/root/4.0/SPECS/linux/`
- Release 5.0: `/root/5.0/SPECS/linux/` + `/root/common/SPECS/linux/v6.1/`
- Release 6.0: `/root/common/SPECS/linux/v6.12/`

---

## Quick Start

### 1. Build the Tool

```bash
cd photonos-scripts/HABv4SimulationEnvironment/src
make
```

### 2. Create a Compliant ISO

```bash
# Basic Secure Boot ISO (includes custom kernel build)
./PhotonOS-HABv4Emulation-ISOCreator -b

# Full compliance build (Secure Boot + RPM signing)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing
```

### 3. Deploy

```bash
# Write to USB
sudo dd if=photon-5.0-*-secureboot.iso of=/dev/sdX bs=4M status=progress
sync

# Boot with Secure Boot enabled
# 1. First boot: Enroll MOK certificate
# 2. Second boot: Install Photon OS
```

---

## Compliance Summary

| Requirement | Standard | HABv4 Implementation |
|-------------|----------|---------------------|
| Boot integrity verification | NIST SI-7, DISA STIG | UEFI Secure Boot chain |
| Signed bootloaders | NIST CM-14 | Microsoft-signed shim, MOK-signed GRUB |
| Signed kernel | EU CRA Art. 10 | MOK-signed vmlinuz |
| Signed packages | FedRAMP, NIS2 | `--rpm-signing` option |
| Kernel module signing | NIST SI-7 | Built-in kernel build with MODULE_SIG |
| Physical presence for key enrollment | Best practice | MokManager requires physical access |

---

## Architecture Overview

### Boot Chain (Secure Boot Enabled)

```
UEFI Firmware
    ↓ verifies (Microsoft CA in db) ✓
SUSE Shim (BOOTX64.EFI)
    ↓ verifies (MokList) ✓
Custom GRUB Stub (grub.efi)
    ↓ loads configuration
Boot Menu
    └── Install
        ↓ launches interactive installer
        Package Selection Screen:
          1. Photon MOK Secure Boot    ← For physical hardware
          2. Photon Minimal            ← Original VMware packages
          3. Photon Developer
          4. Photon OSTree Host
          5. Photon Real Time
```

### Why Original Photon OS Fails

VMware's bootloader chain includes `shim_lock` verification:

```
VMware Shim → VMware GRUB (has shim_lock) → Kernel
                    ↓
         shim_lock calls Verify()
                    ↓
         Kernel signature not in MokList
                    ↓
         "bad shim signature" ERROR ✗
```

Our solution removes `shim_lock` from GRUB while maintaining the MOK signature chain:

```
SUSE Shim → Custom GRUB (no shim_lock, MOK-signed) → Kernel (MOK-signed)
    ↓                      ↓                              ↓
 Verified ✓           Verified ✓                    Boots ✓
```

---

## Command Line Reference

| Option | Description |
|--------|-------------|
| `-b`, `--build-iso` | Build Secure Boot ISO |
| `-r`, `--release=VERSION` | Photon OS version: 4.0, 5.0, 6.0 (default: 5.0) |
| `-R`, `--rpm-signing` | Enable GPG signing (NIST 800-53, FedRAMP, EU CRA) |
| `-E`, `--efuse-usb` | Require eFuse USB dongle for boot |
| `-u`, `--create-efuse-usb=DEV` | Create eFuse USB dongle |
| `-D`, `--diagnose=ISO` | Diagnose existing ISO |
| `-d`, `--drivers[=DIR]` | Include driver RPMs from directory (default: drivers/RPM) |
| `-c`, `--clean` | Clean all artifacts |
| `-v`, `--verbose` | Verbose output |
| `-y`, `--yes` | Auto-confirm destructive operations |

### Examples

```bash
# Standard compliance build (includes custom kernel)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# High-security build with hardware token
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing --efuse-usb --create-efuse-usb=/dev/sdd -y

# Diagnose boot issues
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/photon.iso
```

---

## First Boot Procedure

### 1. Prepare Hardware

- Enable UEFI Secure Boot in BIOS
- Disable CSM/Legacy Boot
- Boot from USB in UEFI mode

### 2. Enroll MOK Certificate

On first boot, the **blue MokManager screen** appears:

1. Select **"Enroll key from disk"**
2. Navigate to root `/`
3. Select **`ENROLL_THIS_KEY_IN_MOKMANAGER.cer`**
4. Confirm and **Reboot**

### 3. Install

1. Select **"Install"** from the GRUB menu
2. Accept EULA, select disk, configure partitions
3. At **Package Selection**, choose **"1. Photon MOK Secure Boot"**
4. Configure hostname and root password
5. Complete installation and reboot

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boot chain and component details |
| [docs/BOOT_PROCESS.md](docs/BOOT_PROCESS.md) | Step-by-step boot sequence |
| [docs/KEY_MANAGEMENT.md](docs/KEY_MANAGEMENT.md) | Key generation and MOK enrollment |
| [docs/ISO_CREATION.md](docs/ISO_CREATION.md) | ISO build process |
| [docs/SIGNING_OVERVIEW.md](docs/SIGNING_OVERVIEW.md) | Secure Boot vs RPM signing |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |
| [docs/DROID_SKILL_GUIDE.md](docs/DROID_SKILL_GUIDE.md) | AI-assisted development |

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| "bad shim signature" | Selected Photon Minimal on hardware | Select "Photon MOK Secure Boot" |
| Laptop security dialog | CSM/Legacy enabled | Disable CSM in BIOS |
| Enrollment doesn't persist | Wrong MokManager | Rebuild with latest version |
| "Policy Violation" | SBAT version issue | Update to latest version |
| Module loading fails | Unsigned module | Sign with kernel module key |

---

## Version History

- **v1.9.26** - Fix Photon 6.0 kernel selection and enable verbose installer logging:
  - **Photon 6.0 Fix**: Specifically detect and select kernel 6.12+ (was picking 6.1 randomly due to glob behavior)
  - **Installer Debugging**: Added automatic patching of `tdnf.py` in initrd to log full JSON output on errors
  - **Why needed**: `Error(1525) : rpm transaction failed` gives no details; verbose logging reveals the actual conflict/dependency error in `/var/log/installer.log`
  - **Implementation**: Patches `tdnf.py` using `sed` during ISO creation to intercept and log error responses
- **v1.9.25** - Fix unexpanded RPM macro in linux-mok %postun script:
  - **Bug**: `%{kernel_file#vmlinuz-}` was not expanded during RPM build
  - **Impact**: Scriptlet tried to access files with literal `%{kernel_file#vmlinuz-}` in path
  - **Symptom**: `Error(1525) : rpm transaction failed` during installation
  - **Fix**: Use shell parameter expansion on expanded `%{kernel_file}` variable
- **v1.9.24** - Photon OS 4.0 support and build system fixes:
  - **Fix**: Add support for Photon OS 4.0 Rev2 ISO download (correct URL and filename)
  - **Fix**: Clean MOK build directory at start to prevent stale packages from previous builds
  - **Fix**: Handle multiple vmlinuz files in linux-mok spec (use `head -1` instead of all matches)
  - **Fix**: Support both 4.0 (5.x kernel) and 5.0 (6.x kernel) package removal patterns
  - **Packages removed for 4.0**: `linux-5.*`, `linux-secure-5.*`, `linux-rt-5.*`, `linux-aws-5.*`, `linux-secure-devel-*`, `linux-secure-docs-*`
  - **Tested**: Both Photon OS 4.0 and 5.0 ISOs build successfully with signed MOK packages
- **v1.9.23** - Remove kernel-dependent packages that require exact version:
  - **Bug**: Packages like `linux-devel`, `linux-drivers-*` require `linux = 6.12.60-14.ph5` (exact)
  - **Impact**: `linux-mok` provides `linux = 6.1.159-7.ph5`, causing unsatisfiable dependencies
  - **Fix**: Remove all packages with exact kernel version dependencies from ISO
  - **Packages removed**: `linux-devel-*`, `linux-docs-*`, `linux-drivers-*`, `linux-tools-*`, `linux-python3-perf-*`, `linux-esx-devel-*`, `linux-esx-docs-*`, `linux-esx-drivers-*`
- **v1.9.22** - Fix repodata to exclude removed original packages:
  - **Bug**: `createrepo_c --update` only adds new packages, doesn't remove deleted ones
  - **Impact**: Repodata still referenced removed packages (linux-6.*, grub2-efi-image-2.*, etc.)
  - **Symptom**: "Failed to install some packages" during installation
  - **Fix**: Remove old repodata and run `createrepo_c` without `--update` for full rebuild
- **v1.9.21** - Fix chainloader path in installer ISO grub.cfg:
  - **Bug**: Installer ISO used wrong path `/boot/grub2/grubx64.efi` (doesn't exist)
  - **Fix**: Changed to `/EFI/BOOT/grubx64.efi` (correct location on ISO)
  - **Note**: Installed system path `/EFI/BOOT/grubx64.efi` was already correct
- **v1.9.20** - Fix eFuse USB hot-plug detection in GRUB:
  - **Problem**: GRUB caches USB devices at startup; `configfile` reload doesn't rescan
  - **Solution**: Use `chainloader` instead of `configfile` to reload GRUB EFI binary
  - **How it works**: `chainloader /EFI/BOOT/grubx64.efi` forces complete GRUB reinitialization including USB rescan
  - **Fixed in**: Installer ISO grub.cfg, installed system grub.cfg (via mk-setup-grub.sh and %posttrans)
  - **User experience**: Plugging in eFuse USB and pressing "Retry" now detects the newly inserted device
- **v1.9.19** - Remove conflicting original packages from ISO:
  - **Root cause**: Even with Epoch and Obsoletes, RPM fails with file conflicts if both original and MOK packages exist in repo
  - **Solution**: Remove `grub2-efi-image-2*.rpm`, `shim-signed-1*.rpm`, `linux-6.*.rpm`, `linux-esx-6.*.rpm` from ISO
  - **Where fixed**: Both `rpm_integrate_to_iso()` and post-signing copy in main ISO creator
  - **Result**: Only MOK packages in repo, no file conflicts during installation
- **v1.9.18** - Fix MOK package conflicts using RPM Epoch:
  - **Root cause**: MOK packages used `Conflicts:` which prevents installation when `minimal` meta-package requires original packages
  - **Solution**: Added `Epoch: 1` to all MOK packages (linux-mok, grub2-efi-image-mok, shim-signed-mok)
  - **How Epoch works**: `1:2.12-1.ph5` is always > `0:2.12-2.ph5` because epoch takes precedence over version/release
  - **Result**: MOK packages now properly replace originals via `Obsoletes:` while satisfying dependencies via `Provides:`
  - **RPM behavior**: When `minimal` requires `grub2-efi-image`, RPM sees `grub2-efi-image-mok` provides it and obsoletes the original
- **v1.9.17** - Fix eFuse USB detection in GRUB:
  - **Root cause**: GRUB stub was missing modules required for USB device and label detection
  - **Missing modules**: `search_label`, `search_fs_uuid`, `search_fs_file`, `usb`, `usbms`, `scsi`, `disk`
  - **Symptom**: eFuse USB dongle (label: EFUSE_SIM) not detected even when properly inserted
  - **Fix**: Added all required modules to grub2-mkimage command
  - **Note**: The `search` module alone doesn't include label search - `search_label` is required
- **v1.9.16** - Fix RPM transaction failures and package naming:
  - **RPM Conflicts fix**: Changed `Obsoletes: package < version` to `Conflicts: package` for MOK packages
  - **Root cause**: MOK package version (e.g., 6.1.159) could be lower than original ISO package (e.g., 6.12.60)
  - **Result**: `Obsoletes: linux < 6.1.159` wouldn't apply to `linux-6.12.60`, causing transaction failures
  - **Package naming fix**: Fixed `linux-firmware-iwlwifi-ax211` missing `.ph5` dist tag
  - **Spec file compliance**: All driver spec files now use hardcoded `.ph5` (since `%{?dist}` is empty outside Photon build env)
  - **Added spec file**: `drivers/linux-firmware-iwlwifi-ax211/linux-firmware-iwlwifi-ax211.spec`
- **v1.9.15** - Refactor codebase into modular structure:
  - **New modular source files** for improved code organization:
    - `habv4_common.h` - Shared types, defines, and function declarations (8.6KB)
    - `habv4_common.c` - Utility functions (logging, file ops, validation) (12KB)
    - `habv4_keys.c` - MOK, SRK, and GPG key generation (9.4KB)
    - `habv4_efuse.c` - eFuse simulation and USB dongle creation (5.3KB)
    - `habv4_drivers.c` - Driver integration and kernel build (29KB)
  - **Meets readability requirement**: `habv4_drivers.c` at 29KB exceeds 20KB threshold
  - **Prepared for future migration**: Modules ready for full modular build while current monolithic build remains functional
- **v1.9.14** - Fix installer GPG verification with multi-key support:
  - **Root cause**: When `--rpm-signing` enabled (v1.9.12+), installer couldn't verify signed MOK packages
  - **Problem**: `photon-iso.repo` references VMware's GPG key which doesn't exist in initrd until photon-repos installs
  - **Solution**: Install multiple GPG keys in initrd and update repo config:
    - Extract VMware's GPG keys from `photon-repos` package (VMWARE-RPM-GPG-KEY, VMWARE-RPM-GPG-KEY-4096)
    - Install HABv4 key as `RPM-GPG-KEY-habv4`
    - Update `photon-iso.repo` with all three keys (space-separated, tdnf-compatible)
  - **Also fixed**: Unversioned `Obsoletes` warnings in spec templates (now `< %{version}-%{release}`)
  - **Result**: Installer can verify both original VMware packages and HABv4-signed MOK packages
- **v1.9.13** - Add wifi-config package for automatic WiFi setup:
  - **New package `wifi-config-1.0.0-1.ph5.noarch.rpm`**:
    - Creates `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` with correct `group=CCMP` cipher
    - Creates `/etc/modprobe.d/iwlwifi-lar.conf` with `options iwlwifi lar_disable=1` to fix 80MHz support
    - Creates `/etc/systemd/network/50-wlan0-dhcp.network` for automatic DHCP
    - Enables `wpa_supplicant@wlan0.service` via systemd preset
  - **Fixes addressed**:
    - "80 MHz not supported, disabling VHT" - caused by Intel iwlwifi LAR (Location Aware Regulatory)
    - wpa_supplicant cipher typo `group=GCCMP` (should be `group=CCMP`)
    - Missing systemd-networkd DHCP configuration for wlan0
  - **Updated packages_mok.json**: Now includes `wifi-config` and `wpa_supplicant`
  - **Spec file**: `drivers/wifi-config/wifi-config.spec`
  - **Build script**: `drivers/wifi-config/build-wifi-config.sh`
- **v1.9.12** - Add wireless-regdb and iw packages for WiFi regulatory support:
  - **Built from upstream sources**: 
    - `wireless-regdb-2024.01.23` from kernel.org (regulatory database)
    - `iw-6.9` from kernel.org (nl80211 wireless configuration utility)
  - **New files in `drivers/RPM/`**:
    - `wireless-regdb-2024.01.23-1.ph5.noarch.rpm`
    - `iw-6.9-1.ph5.x86_64.rpm`
  - **Spec files added** for rebuilding: `drivers/wireless-regdb/` and `drivers/iw/`
  - **Build script**: `drivers/build-wireless-packages.sh` for rebuilding RPMs
  - **Updated packages_mok.json**: Now includes `libnl`, `wireless-regdb`, `iw`, `linux-firmware-iwlwifi-ax211`
  - **Driver RPM signing**: Fixed `integrate_driver_rpms()` to GPG sign driver RPMs when `--rpm-signing` enabled
  - **MOK RPM signing fix**: Re-copy signed MOK RPMs to ISO after signing (were copied before signing)
  - **Result**: All RPMs (MOK and driver) now GPG signed when using `--rpm-signing --drivers`
- **v1.9.11** - Fix installer failure due to missing packages:
  - **Root cause**: `wireless-regdb` and `iw` packages did not exist in Photon OS 5.0 repositories
  - **Result**: Installer failed with "No matching packages not found or not installed" (Error 1011)
  - **Fix**: Initially removed packages; now resolved in v1.9.12 by building from upstream sources
- **v1.9.10** - Wireless regulatory and GRUB splash fixes:
  - **Removed legacy TKIP crypto configs**: Removed `CONFIG_CRYPTO_MICHAEL_MIC`, `CONFIG_CRYPTO_ARC4`, `CONFIG_CRYPTO_ECB` from WiFi driver mappings - these are only needed for WPA1/TKIP which is legacy/insecure; modern WPA2/WPA3-AES doesn't require them
  - ~~**Added wireless-regdb package**~~: (Reverted in v1.9.11 - package not available in Photon OS 5.0)
  - **Fixed GRUB splash screen on installed systems**: eFuse verification code now restores `terminal_output gfxterm` after verification succeeds, enabling themed boot menu display
  - **Note**: Users with malformed wpa_supplicant.conf should fix `group=` cipher settings manually (use `group=CCMP` for WPA2-only)
- **v1.9.9** - Enforce eFuse USB verification on installed systems:
  - **Root cause**: Installer's `mk-setup-grub.sh` generates grub.cfg AFTER all RPM %posttrans scripts run
  - **Result**: eFuse verification code added by grub2-efi-image-mok %posttrans was overwritten
  - **Fix**: Inject eFuse verification code directly into mk-setup-grub.sh template (before `menuentry "Photon"`)
  - **Result**: Installed systems built with `--efuse-usb` now properly require eFuse USB dongle at boot
- **v1.9.8** - Add WPA2/WPA3 crypto algorithm requirements for WiFi:
  - **Root cause**: WiFi driver mappings only enabled subsystem configs but not crypto algorithms required by mac80211
  - **Result**: Kernel panic in `mac80211_new_key+0x138` during WPA key installation
  - **Fix**: Added 8 crypto configs to all WiFi driver mappings: `CONFIG_CRYPTO_CCM=y`, `CONFIG_CRYPTO_GCM=y`, `CONFIG_CRYPTO_CMAC=y`, `CONFIG_CRYPTO_AES=y`, `CONFIG_CRYPTO_AEAD=y`, `CONFIG_CRYPTO_SEQIV=y`, `CONFIG_CRYPTO_CTR=y`, `CONFIG_CRYPTO_GHASH=y`
  - **Result**: WiFi WPA2/WPA3 authentication now works correctly without kernel panics
- **v1.9.7** - Include custom kernel config in linux-mok RPM:
  - **Root cause**: Kernel `.config` file in RPM was from original Photon kernel, not the rebuilt one
  - **Result**: WiFi subsystem configs (`CONFIG_WIRELESS=y`, `CONFIG_WLAN=y`) were not present in installed system
  - **Fix**: Custom kernel injection now copies `.config` from build directory to `boot/config-*` in RPM
  - **Result**: Installed system now has correct kernel config with WiFi subsystem enabled
- **v1.9.6** - Fix double dist tag and WiFi subsystem prerequisites:
  - **Package naming fix**: Removed `%{?dist}` from Release lines in spec templates since original RPM release already contains `.ph5`
  - **Result**: Package names are now `linux-mok-6.1.159-7.ph5.x86_64.rpm` (single `.ph5`) instead of double `.ph5.ph5`
  - **WiFi subsystem fix**: Added prerequisite kernel configs to all WiFi driver mappings
  - **Added configs**: `CONFIG_WIRELESS=y`, `CONFIG_WLAN=y`, `CONFIG_CFG80211=m`, `CONFIG_MAC80211=m`
  - **Root cause**: Photon ESX kernel has `CONFIG_WIRELESS=n CONFIG_WLAN=n` by default, which prevented WiFi drivers from building
  - **Result**: Intel AX211 and other WiFi adapters now work correctly on installed systems
- **v1.9.5** - Driver integration with `--drivers` parameter:
  - **New feature**: Include additional driver firmware RPMs in the ISO
  - **Driver directory**: Place RPMs in `drivers/RPM/` (default) or custom path
  - **Automatic kernel config**: Detects driver types and enables required kernel modules
  - **Supported drivers**: Intel Wi-Fi (iwlwifi), Realtek Wi-Fi (rtw88/rtw89), Broadcom (brcmfmac), Qualcomm (ath11k), Intel Ethernet (e1000e, igb, igc), NVIDIA
  - **Included firmware**: `linux-firmware-iwlwifi-ax211` for Intel Wi-Fi 6E AX211
  - **Usage**: `./PhotonOS-HABv4Emulation-ISOCreator -b --drivers`
- **v1.9.4** - Fixed unsigned module rejection during boot:
  - **Root cause**: RPM's `brp-strip` was stripping module signatures during package build
  - **Fix**: Added `%define __strip /bin/true` and `%define __brp_strip /bin/true` to linux-mok.spec
  - **Result**: Kernel modules now retain their cryptographic signatures through the RPM build process
  - Modules are properly signed with the kernel's built-in signing key
  - System boots without "Loading of unsigned module is rejected" errors
- **v1.9.3** - Fixed installed system boot failure:
  - **%post script fix**: Properly handles kernel version mismatch between vmlinuz filename and modules directory
  - **photon.cfg symlink**: Now created using vmlinuz version (matches cfg filename) instead of modules version
  - **initrd symlink**: Automatically creates symlink when initrd filename doesn't match what cfg expects
  - **Robust detection**: Detects both KVER_MODULES and KVER_VMLINUZ separately to handle custom kernel injection
- **v1.9.2** - RPM patcher improvements:
  - **Clean package naming**: Removed redundant `.mok1` suffix from release tags (package name `-mok` suffix is sufficient)
  - **Better error handling**: `rpm_integrate_to_iso()` now verifies MOK RPMs exist before copying
  - **Copy verification**: Each RPM copy is verified after the operation
  - **Repodata verification**: Confirms MOK packages are present in repository metadata after regeneration
  - **Explicit failure**: Fails with diagnostic information if MOK packages are not found
- **v1.9.1** - Fix for installed system kernel/modules mismatch:
  - **Custom Kernel Injection**: `linux-mok` RPM now correctly contains the *custom built* kernel and modules instead of re-signed standard ones
  - **Module Path Correction**: Fixed logic to locate modules in build directory
  - **Robust Version Detection**: `%post` script now reliably detects kernel version even if filename differs from internal version (fixes `depmod`/`dracut` failures)
  - **Result**: Installed system now boots correctly with built-in USB drivers (fixes "black screen" hang)
- **v1.9.0** - Built-in kernel build and initrd pre-generation:
  - **Kernel build standard**: Custom kernel build is now mandatory and automatic (removed `--full-kernel-build` flag)
  - **USB drivers built-in**: Kernel configured with `CONFIG_USB=y` and related drivers as built-in (not modules) for reliable USB boot
  - **Pre-generated initrd**: Generic initrd generated at build time using `dracut --no-hostonly`, eliminating installation-time dependencies
  - **Correct module dependencies**: `depmod` run on build host to ensure correct module loading in initrd
  - **Dracut optimization**: Explicitly includes critical modules and excludes problematic ones (lvm, nbd, etc.)
- **v1.8.0** - Security hardening and USB boot reliability:
  - **USB driver support**: ESX kernel USB boot fixed - include USB drivers in initrd via dracut
  - **Installer template patching**: Patch `mk-setup-grub.sh` in initrd for reliable boot parameters
  - Input validation: Path sanitization against command injection
  - Release whitelist: Only valid versions (4.0, 5.0, 6.0) accepted
  - Secure temp directories: Using mkdtemp() instead of predictable paths
  - Log sanitization: Private key paths masked in verbose output
  - TOCTOU mitigation: Atomic temp directory creation
  - Added grub2-theme to packages_mok.json for proper font/theme support
- **v1.7.0** - Installed system boot fixes:
  - GRUB for installed system now searches for `/boot/grub2/grub.cfg` (not ISO-specific path)
  - eFuse verification conditional - only added when `--efuse-usb` flag is used
  - SUSE shim looks for `grub.efi` - now installed as both `grub.efi` and `grubx64.efi`
  - USB 3.x performance fix: `usbcore.autosuspend=-1` kernel parameter
  - Package conflicts fixed: `Obsoletes` without version constraint
  - linux-mok package now only includes kernel files (not /boot/efi)
  - Repodata regeneration after adding MOK packages
- **v1.6.0** - Interactive installer with MOK package option (Option C), linuxselector.py patch
- **v1.5.0** - Kickstart-based installation, RPM signing, full kernel build support
- **v1.4.0** - Kickstart configuration, RPM patcher fixes
- **v1.3.0** - Initrd patching (deprecated)
- **v1.2.0** - Integrated RPM Secure Boot Patcher
- **v1.1.0** - Custom GRUB stub with SBAT
- **v1.0.0** - Initial implementation

## License

GPL-3.0+
