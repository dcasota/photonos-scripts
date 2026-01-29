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

- **v1.9.11** - Fix installer failure due to missing packages:
  - **Root cause**: `wireless-regdb` and `iw` packages do not exist in Photon OS 5.0 repositories
  - **Result**: Installer failed with "No matching packages not found or not installed" (Error 1011)
  - **Fix**: Removed `wireless-regdb` and `iw` from `packages_mok.json`
  - **Note**: WiFi regulatory domain will use kernel defaults (restrictive); users needing 80MHz/DFS channels can build custom packages or set regulatory domain via kernel parameter (`cfg80211.ieee80211_regdom=XX`)
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
