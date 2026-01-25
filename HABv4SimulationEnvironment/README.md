# HABv4 Secure Boot Simulation Environment

**Create bootable Photon OS ISOs that work on real hardware with UEFI Secure Boot enabled.**

## What is This?

This tool solves a common problem: **Photon OS ISOs don't boot on consumer laptops with Secure Boot enabled** because VMware's bootloaders require their shim's `shim_lock` verification, which rejects custom or unsigned kernels.

The HABv4 Simulation Environment creates modified ISOs that:
- **Boot on physical hardware** with UEFI Secure Boot enabled
- **Use a Microsoft-signed SUSE shim** (SBAT compliant, passes firmware verification)
- **Include a custom GRUB stub** (MOK-signed, without `shim_lock` restrictions)
- **Install MOK-signed packages** to the target system for continued Secure Boot support

### Before vs After

| Scenario | Original Photon OS ISO | HABv4 Modified ISO |
|----------|----------------------|-------------------|
| VMware VMs | Works | Works |
| Physical hardware (Secure Boot OFF) | Works | Works |
| Physical hardware (Secure Boot ON) | **Fails** ("bad shim signature") | **Works** |
| Consumer laptops | **Fails** | **Works** |

## Quick Start

### 1. Build the Tool

```bash
cd photonos-scripts/HABv4SimulationEnvironment/src
make
```

### 2. Create a Secure Boot ISO

```bash
# Simplest usage - does everything automatically:
./PhotonOS-HABv4Emulation-ISOCreator -b
```

This will:
1. Download the Photon OS 5.0 ISO (if not present)
2. Generate MOK signing keys
3. Build MOK-signed RPM packages
4. Create a Secure Boot compatible ISO

### 3. Write to USB and Boot

```bash
# Write to USB drive
sudo dd if=photon-5.0-*-secureboot.iso of=/dev/sdX bs=4M status=progress
sync

# Boot from USB with Secure Boot enabled
# First boot: Enroll MOK certificate when prompted
# Second boot: Install Photon OS normally
```

## How It Works

### Boot Chain Comparison

**Original Photon OS (fails on Secure Boot):**
```
UEFI Firmware → VMware shim → VMware GRUB (shim_lock) → Kernel
                                    ↓
                         "bad shim signature" ✗
```

**HABv4 Modified ISO (works on Secure Boot):**
```
UEFI Firmware → SUSE shim (Microsoft-signed) → Custom GRUB (MOK-signed) → Kernel
       ↓                    ↓                            ↓
   Passes ✓           Passes (MokList) ✓         Boots successfully ✓
```

### What Gets Modified

| Component | Original | Modified |
|-----------|----------|----------|
| `BOOTX64.EFI` | VMware shim | SUSE shim (Microsoft-signed, SBAT=shim,4) |
| `grubx64.efi` | VMware GRUB (has `shim_lock`) | Custom GRUB stub (no `shim_lock`, MOK-signed) |
| `vmlinuz` | Unsigned | MOK-signed |
| RPM packages | `shim-signed`, `grub2-efi-image`, `linux` | `shim-signed-mok`, `grub2-efi-image-mok`, `linux-mok` |

### Installation Menu

The modified ISO presents a menu with two installation options:

```
1. Install (Custom MOK) - For Physical Hardware    [Recommended for laptops]
2. Install (VMware Original) - For VMware VMs      [Use in VMs without Secure Boot]
3. MokManager - Enroll/Delete MOK Keys
4. Reboot into UEFI Firmware Settings
5. Reboot
6. Shutdown
```

Both options use **interactive installation** - you choose disk, hostname, and password as usual. The difference is which RPM packages get installed.

## First Boot Guide

### Step 1: Prepare

1. Write ISO to USB drive
2. Enable Secure Boot in BIOS/UEFI settings
3. Disable CSM/Legacy Boot (important!)
4. Boot from USB in UEFI mode

### Step 2: Enroll MOK Certificate

On first boot, you'll see the **blue MokManager screen** (not your laptop's security dialog):

1. Select **"Enroll key from disk"**
2. Navigate to the root `/` folder
3. Select **`ENROLL_THIS_KEY_IN_MOKMANAGER.cer`**
4. Confirm and select **"Reboot"**

> **Note**: If you see your laptop manufacturer's security dialog (gray/red), not the blue MokManager, you need to disable CSM/Legacy boot in BIOS.

### Step 3: Install Photon OS

After reboot:
1. The themed Photon OS menu appears
2. Select **"Install (Custom MOK) - For Physical Hardware"**
3. Complete the interactive installation (disk, hostname, password)
4. Reboot into your installed system

## Command Line Options

| Option | Description |
|--------|-------------|
| `-b`, `--build-iso` | Build Secure Boot ISO |
| `-r VERSION`, `--release=VERSION` | Photon OS version: 4.0, 5.0, 6.0 (default: 5.0) |
| `-D ISO`, `--diagnose=ISO` | Diagnose an existing ISO for Secure Boot issues |
| `-E`, `--efuse-usb` | Enable eFuse USB verification (optional hardware security) |
| `-u DEV`, `--create-efuse-usb=DEV` | Create eFuse USB dongle on device |
| `-R`, `--rpm-signing` | Enable GPG signing of RPM packages (for compliance) |
| `-F`, `--full-kernel-build` | Build kernel from source with Secure Boot options |
| `-c`, `--clean` | Clean up all generated artifacts |
| `-v`, `--verbose` | Verbose output |
| `-y`, `--yes` | Auto-confirm destructive operations |
| `-h`, `--help` | Show help |

### Examples

```bash
# Build ISO for Photon OS 6.0
./PhotonOS-HABv4Emulation-ISOCreator --release 6.0 --build-iso

# Build with RPM signing (for NIST 800-53, FedRAMP, EU CRA compliance)
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --rpm-signing

# Build with eFuse USB hardware verification
./PhotonOS-HABv4Emulation-ISOCreator --build-iso --efuse-usb --create-efuse-usb=/dev/sdd -y

# Diagnose why an existing ISO won't boot
./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/photon.iso
```

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| "bad shim signature" | Selected VMware Original on hardware | Select "Install (Custom MOK)" instead |
| Laptop security dialog instead of blue MokManager | CSM/Legacy enabled | Disable CSM in BIOS, enable pure UEFI |
| Enrollment doesn't persist | Wrong MokManager used | Rebuild ISO with latest version |
| "Policy Violation" | GRUB SBAT issue | Use latest version (fixed) |
| Installed system won't boot | Installed standard packages | Reinstall using "Install (Custom MOK)" |

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for complete guide.

## Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boot chain and component overview |
| [docs/BOOT_PROCESS.md](docs/BOOT_PROCESS.md) | Detailed boot sequence explanation |
| [docs/KEY_MANAGEMENT.md](docs/KEY_MANAGEMENT.md) | Key generation and MOK enrollment |
| [docs/ISO_CREATION.md](docs/ISO_CREATION.md) | ISO creation process |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |
| [docs/SIGNING_OVERVIEW.md](docs/SIGNING_OVERVIEW.md) | Secure Boot vs RPM signing comparison |

## Using the Droid Skill

This project includes a Factory Droid skill for AI-assisted development. See [docs/DROID_SKILL_GUIDE.md](docs/DROID_SKILL_GUIDE.md) for how to use it.

## Version History

- **v1.5.0** - Kickstart-based installation, RPM signing, kernel build support
- **v1.4.0** - Kickstart configuration files, RPM patcher fixes
- **v1.3.0** - Initrd patching for MOK packages (deprecated)
- **v1.2.0** - Integrated RPM Secure Boot Patcher
- **v1.1.0** - Custom GRUB stub with SBAT support
- **v1.0.0** - Initial C implementation

## License

GPL-3.0+
