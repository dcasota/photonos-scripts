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
- `--full-kernel-build` option builds kernel with embedded signing key
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

**HABv4 Solution**: The `--full-kernel-build` option:
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

Full kernel build with Secure Boot configuration:

```bash
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --full-kernel-build
```

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
# Basic Secure Boot ISO
./PhotonOS-HABv4Emulation-ISOCreator -b

# Full compliance build (Secure Boot + RPM signing)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# Edge deployment (custom kernel + full signing)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing --full-kernel-build
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
| Kernel module signing | NIST SI-7 | `--full-kernel-build` with MODULE_SIG |
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
    ├── Install (Custom MOK) - For Physical Hardware
    │   └── Installs: linux-mok, grub2-efi-image-mok, shim-signed-mok
    └── Install (VMware Original) - For VMware VMs
        └── Installs: linux, grub2-efi-image, shim-signed
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
| `-F`, `--full-kernel-build` | Build kernel with Secure Boot config |
| `-E`, `--efuse-usb` | Require eFuse USB dongle for boot |
| `-u`, `--create-efuse-usb=DEV` | Create eFuse USB dongle |
| `-D`, `--diagnose=ISO` | Diagnose existing ISO |
| `-c`, `--clean` | Clean all artifacts |
| `-v`, `--verbose` | Verbose output |
| `-y`, `--yes` | Auto-confirm destructive operations |

### Examples

```bash
# Standard compliance build
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# Edge deployment with custom kernel
./PhotonOS-HABv4Emulation-ISOCreator --release 5.0 --build-iso --full-kernel-build --rpm-signing

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

1. Select **"Install (Custom MOK) - For Physical Hardware"**
2. Complete interactive installation
3. Reboot into compliant Photon OS

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
| "bad shim signature" | Using VMware Original on hardware | Select "Custom MOK" option |
| Laptop security dialog | CSM/Legacy enabled | Disable CSM in BIOS |
| Enrollment doesn't persist | Wrong MokManager | Rebuild with latest version |
| "Policy Violation" | SBAT version issue | Update to latest version |
| Module loading fails | Unsigned module | Sign with kernel module key |

---

## Version History

- **v1.5.0** - Kickstart-based installation, RPM signing, full kernel build support
- **v1.4.0** - Kickstart configuration, RPM patcher fixes
- **v1.3.0** - Initrd patching (deprecated)
- **v1.2.0** - Integrated RPM Secure Boot Patcher
- **v1.1.0** - Custom GRUB stub with SBAT
- **v1.0.0** - Initial implementation

## License

GPL-3.0+
