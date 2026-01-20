# HABv4 Simulation Environment for Photon OS

## Overview

This project provides a simulation environment for NXP's High Assurance Boot version 4 (HABv4) secure boot mechanism, adapted for VMware Photon OS. It enables development, testing, and demonstration of secure boot concepts on both x86_64 and aarch64 architectures without requiring actual NXP i.MX hardware with burned eFuses.

## Goals

### Primary Objectives

1. **Educational Platform**: Provide a safe environment to understand HABv4 secure boot concepts, key hierarchies, and chain-of-trust mechanisms without risking permanent hardware changes (eFuse burning).

2. **Development Environment**: Enable firmware and bootloader developers to test signed boot images and secure boot workflows before deploying to production hardware.

3. **Cross-Architecture Support**: Demonstrate secure boot concepts across both ARM64 (using HABv4 paradigm) and x86_64 (using UEFI Secure Boot paradigm) architectures.

4. **Photon OS Integration**: Integrate HAB-like security features into VMware Photon OS ISO builds for creating security-hardened deployments.

### What This Simulation Provides

- File-based eFuse simulation (no permanent hardware changes)
- HABv4-compatible key generation and management
- Code Signing Tool (CST) for image signing
- Trusted Firmware-A (TF-A) and OP-TEE integration for ARM64
- UEFI Secure Boot key generation for x86_64
- QEMU-based testing environment

## HABv4 vs. This Simulation

### NXP HABv4 on Real Hardware

| Aspect | NXP i.MX Hardware | This Simulation |
|--------|-------------------|-----------------|
| **eFuses** | One-time programmable (OTP) silicon fuses | File-based simulation (`/root/efuse_sim/`) |
| **SRK Hash** | Permanently burned into silicon | Stored in `srk_fuse.bin` file |
| **SEC_CONFIG** | Hardware register, irreversible | Simulated in `sec_config.bin` |
| **Boot ROM** | Silicon-based, immutable | Simulated via boot scripts/GRUB |
| **Key Revocation** | SRK revocation fuses (permanent) | Editable configuration files |
| **Secure World** | Hardware-isolated TrustZone | OP-TEE in QEMU or hypervisor |
| **Tamper Detection** | Hardware sensors | Not simulated |

### Key Differences

#### 1. eFuse Simulation
Real HABv4 uses One-Time Programmable (OTP) fuses in silicon:
- Once burned, cannot be changed
- SRK hash verification is hardware-enforced
- Security configuration (open/closed) is permanent

This simulation uses files:
```
/root/efuse_sim/
├── efuse_config.json    # Human-readable configuration
├── sec_config.bin       # Security configuration (simulates OCOTP)
├── sec_config.txt       # "Open" or "Closed" mode indicator
└── srk_fuse.bin         # SRK hash (simulates SRK_HASH fuses)
```

#### 2. Boot Chain Verification
| Stage | NXP Hardware | Simulation |
|-------|--------------|------------|
| Boot ROM | Hardcoded in silicon | N/A (starts at bootloader) |
| SPL/U-Boot | HAB API verifies signatures | CST-signed, verified by scripts |
| Kernel | Authenticated by bootloader | Signed with DB key (x86) or IMG key (ARM) |
| Root FS | dm-verity or IMA | Standard Photon OS |

#### 3. Trusted Execution Environment (TEE)
- **ARM64 (i.MX)**: Hardware TrustZone with OP-TEE as BL32
- **ARM64 (Simulation)**: OP-TEE in QEMU or hypervisor-assisted isolation
- **x86_64 (Hardware)**: Intel SGX or AMD SEV enclaves
- **x86_64 (Simulation)**: SGX SDK for development (if CPU supports)

#### 4. Key Hierarchy Comparison

**NXP HABv4 Key Hierarchy:**
```
Super Root Keys (SRK1-4)     <- Hash burned in eFuses
        │
        ▼
Command Sequence File Key (CSF)
        │
        ▼
Image Signing Key (IMG)      <- Signs bootloader/kernel
```

**Simulation Key Hierarchy:**
```
/root/hab_keys/
├── srk.pem / srk_pub.pem    # Super Root Key (4096-bit RSA)
├── srk_hash.bin             # SHA-256 hash for "eFuse" simulation
├── csf.pem / csf_pub.pem    # CSF Key (2048-bit RSA)
├── img.pem / img_pub.pem    # Image signing key (2048-bit RSA)
├── PK.key / PK.crt          # UEFI Platform Key (x86_64)
├── KEK.key / KEK.crt        # Key Exchange Key (x86_64)
├── DB.key / DB.crt          # Signature Database Key (x86_64)
├── MOK.key / MOK.crt        # Machine Owner Key for Secure Boot
├── shim-suse.efi            # SUSE shim 15.8 from Ventoy (SBAT=shim,4)
├── MokManager-suse.efi      # SUSE MokManager from Ventoy
└── grub-photon-stub.efi     # Custom GRUB stub (MOK-signed)
```

## Script Functionality

### Installation Script: `HABv4-installer.sh`

The main installer script automates the complete HAB simulation environment setup and can build Secure Boot compatible Photon OS ISOs.

#### Usage

```bash
# Basic installation (recommended for most users)
sudo ./HABv4-installer.sh

# Specify Photon OS release version
sudo ./HABv4-installer.sh --release=5.0

# Build Photon ISO after setup (takes several hours)
sudo ./HABv4-installer.sh --release=5.0 --build-iso

# Build ISO with eFuse USB dongle verification enabled
sudo ./HABv4-installer.sh --release=5.0 --build-iso --efuse-usb

# Create eFuse USB dongle (requires existing keys)
sudo ./HABv4-installer.sh --create-efuse-usb=/dev/sdb

# With full kernel builds (takes 30+ minutes per architecture)
sudo ./HABv4-installer.sh --full-kernel-build

# Full build with all options
sudo ./HABv4-installer.sh --release=5.0 --build-iso --full-kernel-build

# Show help
sudo ./HABv4-installer.sh --help

# Cleanup all build artifacts
sudo ./HABv4-installer.sh clean
```

#### Command Line Options

| Option | Description |
|--------|-------------|
| `--release=VERSION` | Specify Photon OS release (4.0, 5.0, 6.0). Default: 5.0 |
| `--build-iso` | Build Photon OS ISO after setup |
| `--full-kernel-build` | Build Linux kernel from source (takes hours) |
| `--efuse-usb` | Enable eFuse USB dongle verification in GRUB stub |
| `--create-efuse-usb=DEV` | Create eFuse USB dongle on device (e.g., /dev/sdb) |
| `--help, -h` | Show help message |
| `clean` | Remove all build artifacts |

#### Script Functions

| Function | Description |
|----------|-------------|
| `check_prerequisites()` | Verifies host architecture (x86_64/aarch64) and OS |
| `install_dependencies()` | Installs required packages via tdnf/apt/dnf/yum |
| `install_toolchain()` | Downloads ARM GNU Toolchain for cross-compilation |
| `build_qemu()` | Sets up QEMU for aarch64/x86_64 emulation |
| `build_cst()` | Builds NXP Code Signing Tool (or creates simulator) |
| `generate_hab_keys()` | Generates HABv4 and UEFI Secure Boot keys |
| `simulate_efuses()` | Creates file-based eFuse simulation |
| `build_optee_aarch64()` | Builds OP-TEE for ARM64 secure world |
| `build_tfa_aarch64()` | Builds Trusted Firmware-A for ARM64 |
| `enable_tee_x86_64()` | Checks/enables Intel SGX or AMD SEV |
| `build_uboot_aarch64()` | Builds U-Boot bootloader for ARM64 |
| `build_grub_x86_64()` | Installs and optionally signs GRUB2 |
| `setup_shim_secureboot()` | Sets up Microsoft-compatible Secure Boot chain |
| `integrate_tfa_uboot_aarch64()` | Creates signed boot image with imx-mkimage |
| `build_linux_aarch64()` | Builds linux-imx kernel (optional) |
| `build_linux_x86_64()` | Builds mainline Linux with TEE support (optional) |
| `verify_installations()` | Validates all components are properly installed |
| `prepare_photon_env()` | Prepares Photon OS build environment |
| `build_photon_installer_image()` | Builds photon/installer Docker image |
| `customize_photon_hab()` | Injects HAB components into Photon build |
| `build_photon_iso()` | Builds custom Photon ISO with HAB |
| `fix_iso_secureboot()` | **Fixes ISO for Secure Boot by replacing unsigned components** |
| `cleanup()` | Removes all build artifacts |

#### Kernel Module Signing

The script configures the Photon kernel build to sign all modules with a custom key:

1. **Generates signing key**: Creates `kernel_module_signing.pem` in `/root/hab_keys/`
2. **Configures kernel**: Sets `CONFIG_MODULE_SIG_ALL=y` and `CONFIG_MODULE_SIG_KEY`
3. **Patches linux.spec**: Copies signing key to kernel `certs/` directory before build
4. **Signs modules**: All `.ko` files are signed during `make modules_install`

The module signing key is embedded in the kernel's trusted keyring, so modules signed with it will load without issues.

#### Modular Scripts

The project includes modular helper scripts in `/root/hab_scripts/`:

| Script | Purpose |
|--------|---------|
| `hab_lib.sh` | Common library functions (logging, signatures, utilities) |
| `hab_keys.sh` | Key generation and management |
| `hab_iso.sh` | ISO fixing, verification, and USB writing |

**Usage Examples:**
```bash
# Fix an existing ISO for Secure Boot
./hab_scripts/hab_iso.sh fix /path/to/photon.iso

# Verify ISO structure and signatures
./hab_scripts/hab_iso.sh verify /path/to/photon-secureboot.iso

# Write ISO to USB device (use with caution!)
./hab_scripts/hab_iso.sh write /path/to/photon-secureboot.iso /dev/sdX

# Generate all keys
./hab_scripts/hab_keys.sh generate

# List existing keys
./hab_scripts/hab_keys.sh list

# Verify key pairs match
./hab_scripts/hab_keys.sh verify
```

#### Output Directories

```
/root/
├── hab_scripts/            # Modular helper scripts
├── hab_build/              # Build artifacts
│   ├── cst/                # Code Signing Tool
│   ├── imx-atf/            # Trusted Firmware-A
│   ├── optee_os/           # OP-TEE OS
│   ├── u-boot-aarch64/     # U-Boot bootloader
│   ├── imx-mkimage/        # Boot image creation tool
│   ├── secureboot/         # Secure Boot files (shim, GRUB)
│   ├── photon-os-installer/# Photon installer (for Docker builds)
│   └── integrated/         # Final signed boot images
├── hab_keys/               # Cryptographic keys
│   ├── srk.pem             # Super Root Key
│   ├── csf.pem             # CSF Key
│   ├── img.pem             # Image Signing Key
│   ├── PK.*, KEK.*, DB.*   # UEFI Secure Boot keys
│   ├── MOK.*               # Machine Owner Key for shim
│   └── kernel_module_signing.pem  # Kernel module signing key
├── efuse_sim/              # eFuse simulation files
├── arm-toolchain/          # ARM cross-compiler
├── linux-aarch64/          # ARM64 kernel (if built)
├── linux-x86_64/           # x86_64 kernel (if built)
└── {4.0,5.0,6.0}/          # Photon OS build directories
    └── stage/
        ├── photon-*.iso           # Original built ISO
        └── photon-*-secureboot.iso # Secure Boot compatible ISO
```

## Testing the Simulation

### Verify eFuse Simulation

```bash
# Check simulated security configuration
cat /root/efuse_sim/sec_config.txt
# Output: Closed

# View eFuse configuration
cat /root/efuse_sim/efuse_config.json

# Compare SRK hash
xxd /root/efuse_sim/srk_fuse.bin
xxd /root/hab_keys/srk_hash.bin
```

### Test with QEMU (ARM64)

```bash
# Boot with eFuse simulation (conceptual)
qemu-system-aarch64 \
  -M virt,secure=on \
  -cpu cortex-a53 \
  -m 1G \
  -drive file=/root/efuse_sim/srk_fuse.bin,if=pflash,format=raw \
  -bios /root/hab_build/integrated/flash_evk \
  -nographic
```

### Verify Keys

```bash
# Check SRK public key
openssl rsa -in /root/hab_keys/srk_pub.pem -pubin -text -noout

# Verify SRK hash matches eFuse simulation
openssl dgst -sha256 -binary /root/hab_keys/srk_pub.pem | xxd
xxd /root/efuse_sim/srk_fuse.bin
```

### eFuse USB Dongle (Optional)

For a more realistic simulation, you can move eFuse files to a USB stick. The system will only boot in "Closed" (secure) mode when the USB is present:

```bash
# Create eFuse USB dongle (after running installer once to generate keys)
sudo ./HABv4-installer.sh --create-efuse-usb=/dev/sdb

# Build ISO with eFuse USB verification
sudo ./HABv4-installer.sh --release=5.0 --build-iso --efuse-usb
```

**Boot behavior with `--efuse-usb` enabled (ENFORCED):**

| USB Present | srk_fuse.bin Valid | Boot Behavior |
|-------------|-------------------|---------------|
| Yes | Yes | "Security Mode: CLOSED" - Normal boot proceeds |
| Yes | No/Missing | "BOOT BLOCKED" - Only Retry/Reboot available |
| No | N/A | "BOOT BLOCKED" - Only Retry/Reboot available |

**Note**: When `--efuse-usb` is used, the "Continue to Photon OS Installer" option is **only shown** when a valid eFuse USB dongle is detected. Without it, boot is blocked.

**USB dongle contents:**
```
USB (LABEL=EFUSE_SIM, FAT32)
└── efuse_sim/
    ├── srk_fuse.bin          # SRK hash (32 bytes)
    ├── sec_config.bin        # Security configuration
    ├── efuse_config.json     # Complete config
    └── srk_pub.pem           # Public key (optional)
```

**Note**: This is a simulation. Real eFuses are burned into silicon and cannot be copied. The USB dongle can be cloned.

## Booting on Laptops with Microsoft Secure Boot

Consumer laptops ship with Microsoft's UEFI certificates pre-enrolled. The script automatically creates **dual-mode** Secure Boot compatible ISOs that work on both VMware VMs and physical laptops.

### Two-Stage Boot Menu

The generated Secure Boot ISO uses a two-stage boot menu:

**Stage 1: GRUB Stub Menu (5 second timeout)**
- **Continue to Photon OS Installer** (default) - Proceeds to main menu
- **MokManager - Enroll/Delete MOK Keys** - Access MOK management
- **Reboot** / **Shutdown**

**Stage 2: Main Boot Menu (VMware GRUB)**
- **Install Photon OS (Custom)** - Standard installation
- **Install Photon OS (VMware original)** - Installation with verbose logging
- **UEFI Firmware Settings** - Enter UEFI setup

**Note**: MokManager is only accessible from Stage 1 (stub menu) because shim's protocol is still available there.

### Boot Chain (Fedora Shim - SBAT Compliant)

```
UEFI Firmware (Microsoft UEFI CA 2011)
    → BOOTX64.EFI (SUSE shim 15.8 from Ventoy, SBAT=shim,4)
        ├→ grubx64.efi (Photon OS GRUB stub, MOK-signed)
        │      → grubx64_real.efi (VMware-signed GRUB)
        │             → vmlinuz (VMware-signed kernel)
        │                     → *.ko modules (build-key-signed)
        │
        └→ MokManager.efi (SUSE-signed) [MOK enrollment]
```

**Why SUSE Shim from Ventoy?** We use Ventoy's SUSE shim because:
- It has SBAT version `shim,4` (compliant with Microsoft's revocation)
- Ventoy uses a production-proven Secure Boot implementation
- SUSE's MokManager is signed by SUSE CA (matches SUSE shim)
- SUSE shim looks for `\MokManager.efi` at ROOT level
- See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed explanation

### Quick Start: First Boot with Secure Boot

1. **Write ISO to USB**: `dd if=photon-*-secureboot.iso of=/dev/sdX bs=4M status=progress`
2. **Boot from USB** with Secure Boot enabled
3. **"Security Violation" appears** - Press any key
4. **MokManager loads** → Select "Enroll key from disk"
5. **Navigate to root `/`** → Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. Confirm enrollment (View key → Continue → Yes → Reboot)
7. **After reboot**, stub menu appears (5 sec), then main menu
8. **Select "Install Photon OS (Custom)"** from main menu
9. Installation proceeds normally

### Quick Start: VMware Workstation (UEFI)

1. Boot from ISO with UEFI firmware in VM settings
2. **Stub menu appears** (5 seconds) - wait or press Enter
3. **Main menu appears** - Select "Install Photon OS (Custom)"
4. Installation proceeds (VMware GRUB and kernel are pre-signed)

### Automatic Secure Boot ISO Creation

When you build an ISO with `--build-iso`, the script automatically:

1. Builds the base Photon OS ISO with custom module signing key
2. Configures kernel to sign all modules during build (`CONFIG_MODULE_SIG_ALL=y`)
3. Downloads VMware-signed GRUB from the official Photon repository
4. Downloads SUSE shim 15.8 from Ventoy (SBAT=shim,4 compliant) and MokManager
5. Builds custom Photon OS GRUB stub with 5-second menu (for MokManager access)
6. Signs the GRUB stub with your MOK key
7. Includes MOK certificate as `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` in efiboot.img
8. Creates bootstrap `grub.cfg` that properly finds the ISO filesystem
9. Uses `xorriso` with `-isohybrid-mbr` and `-isohybrid-gpt-basdat` for proper USB boot support
10. Creates a new ISO with `-secureboot.iso` suffix

**Note**: The script uses SUSE shim from Ventoy 1.1.10 (SBAT=shim,4 compliant).

```bash
# Build Secure Boot compatible ISO
sudo ./HABv4-installer.sh --release=5.0 --build-iso

# Output:
# /root/5.0/stage/photon-5.0-*.iso              # Original (unsigned kernel)
# /root/5.0/stage/photon-5.0-*-secureboot.iso   # Secure Boot compatible (DB-signed kernel)
```

### MOK Enrollment

The GRUB stub requires MOK enrollment on first boot. There are multiple methods:

**Method 1: First Boot Enrollment (Recommended)**
1. Boot from USB - "Security Violation" appears (expected)
2. Press any key - MokManager loads automatically
3. Select "Enroll key from disk"
4. Navigate to root `/`, select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
5. Confirm enrollment and select **Reboot**
6. GRUB menu now loads - select "Install Photon OS"

**Method 2: Pre-enroll from Existing Linux**
```bash
sudo mokutil --import /root/hab_keys/MOK.der
# Set a one-time password
# Reboot, approve in MokManager using that password
```

**Method 3: Hash Enrollment (if certificate doesn't persist)**
1. In MokManager, select "Enroll hash from disk"
2. Navigate to `EFI/BOOT/`, select `grub.efi`
3. Confirm enrollment and reboot

### MOK Key Deletion (from Boot Menu)

The ISO includes a rescue shell with `mokutil` pre-installed:

1. Boot from USB
2. Select **"MOK Management >"** → **"Rescue Shell"**
3. At the bash prompt, run:
   ```bash
   mokutil --list-enrolled    # List enrolled keys
   mokutil --export           # Export keys to files
   mokutil --delete key.der   # Schedule key deletion
   reboot                     # Reboot to confirm in MokManager
   ```

### What Gets Signed

| Component | Signer | Location in ISO | Trust Chain |
|-----------|--------|-----------------|-------------|
| `BOOTX64.EFI` (shim) | Microsoft + Fedora | `/EFI/BOOT/` | UEFI → Shim |
| `MokManager.efi` / `mmx64.efi` | Fedora | ROOT + `/EFI/BOOT/` | Shim → MokManager |
| `grubx64.efi` | MOK | `efiboot.img:/EFI/BOOT/` | Shim → GRUB stub |
| `grubx64_real.efi` | VMware | `efiboot.img:/EFI/BOOT/` | Stub → GRUB real |
| `vmlinuz-vmware` | VMware | `/isolinux/` | Shim → Kernel |
| `vmlinuz-custom` | Custom (MOK) | `/isolinux/` | Shim+MOK → Kernel |
| `*.ko` modules | Kernel build key | Inside `initrd.img` | Kernel → Modules |
| `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` | N/A (certificate) | `efiboot.img:/` | For enrollment |

### Verifying Signatures

```bash
# Mount the Secure Boot ISO
mkdir -p /tmp/iso /tmp/efi
mount -o loop photon-*-secureboot.iso /tmp/iso
mount -o loop /tmp/iso/boot/grub2/efiboot.img /tmp/efi

# Verify shim (Microsoft signature)
sbverify --list /tmp/efi/EFI/BOOT/bootx64.efi

# Verify GRUB stub (MOK signature)
sbverify --list /tmp/efi/EFI/BOOT/grubx64.efi

# Verify GRUB real (VMware signature)
sbverify --list /tmp/efi/EFI/BOOT/grubx64_real.efi

# Verify kernel (VMware signature)
sbverify --list /tmp/iso/isolinux/vmlinuz

# Cleanup
umount /tmp/efi /tmp/iso
```

### Why This Works

VMware's signing certificate is embedded in the shim bootloader distributed with Photon OS. The shim trusts:
- Microsoft's UEFI CA (for its own signature)
- VMware's certificate (embedded, for GRUB and kernel)

This creates a complete chain of trust from UEFI firmware to the running kernel.

### Manual Secure Boot Fix

If you have an existing ISO that needs Secure Boot fixing:

```bash
# Source the script functions
source /root/HABv4-installer.sh

# Fix an existing ISO
fix_iso_secureboot /path/to/photon.iso

# Creates: /path/to/photon-secureboot.iso
```

### Custom MOK Signing (Advanced)

The script also generates a Machine Owner Key (MOK) for custom signing:

```
/root/hab_keys/
├── MOK.key   # Private key for signing
├── MOK.crt   # Certificate (PEM format)
└── MOK.der   # Certificate (DER format for mokutil)
```

To use your own MOK-signed components:

1. Sign your custom GRUB or kernel:
   ```bash
   sbsign --key /root/hab_keys/MOK.key --cert /root/hab_keys/MOK.crt \
       --output grubx64-stub-signed.efi grubx64_stub.efi
   ```

2. Enroll MOK on target machine:
   ```bash
   sudo mokutil --import /root/hab_keys/MOK.der
   # Set password, reboot, approve in MOK Manager
   ```

### Troubleshooting Secure Boot

**"Security Violation" on first boot (EXPECTED)**
- This is **normal** on first boot - SUSE shim doesn't trust GRUB yet
- Solution (Ventoy-style approach):
  1. Press any key, MokManager loads automatically
  2. Select "Enroll key from disk"
  3. Navigate to root `/`
  4. Select `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` (MOK certificate)
  5. Confirm enrollment and select **Reboot**
  6. GRUB will now load successfully (trusted via MOK signature)

**MOK enrollment doesn't persist after reboot**
- Some firmwares have issues with certificate enrollment
- Try **hash enrollment** instead:
  1. In MokManager, select "Enroll hash from disk"
  2. Navigate to `EFI/BOOT/` and select `grub.efi`
  3. Confirm and reboot

**MokManager Menu Options**
MokManager provides all these built-in (no separate GRUB menu entries needed):
- Enroll key from disk / Enroll hash from disk
- Delete key / Delete hash
- Reboot / Power off

**"Failed to open \EFI\BOOT\MokManager.efi - Not Found"**
- MokManager not present in efiboot.img (or wrong filename/location)
- Solution: Rebuild with latest HABv4-installer.sh (places MokManager at all known paths)

**MokManager shows limited options (no "Delete key")**
- You're using the laptop's built-in MokManager, not the one from USB
- Root cause: SUSE shim couldn't find MokManager at ROOT level
- Solution: Rebuild ISO with latest HABv4-installer.sh which places SUSE MokManager at:
  - `\MokManager.efi` (ROOT) - SUSE shim looks here
  - `\EFI\BOOT\MokManager.efi` - fallback

**Certificate not visible in MokManager "Enroll key from disk"**
- Navigate to root `/`
- You should see `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` in the EFI partition
- If missing, rebuild ISO with latest HABv4-installer.sh

**GRUB drops to command prompt (grub>) after loading bootx64.efi**
- GRUB cannot find its configuration file (`grub.cfg`)
- This happens when `grub.cfg` is missing from `/EFI/BOOT/` inside `efiboot.img`
- Solution: The `fix_iso_secureboot` function now copies `grub.cfg` into the EFI boot partition

**"bad shim signature" or "you need to load the kernel first"**
- The kernel is not signed or signature not trusted by shim
- Solution: Use the `-secureboot.iso` version and enroll `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` on first boot
- For custom kernel: After enrollment, use the custom kernel boot entry

**"Lockdown: unsigned module loading is restricted"**
- Kernel is in lockdown mode but modules aren't signed with a trusted key
- This happens if you replace the kernel with a different one (mismatched keys)
- Solution: Don't mix kernels - use the kernel that matches the initrd modules

**"EFI USB Device (SB) boot failed"** or **"EFI USB Device (USB) boot failed"**
- ISO is not properly hybrid (missing MBR/GPT partition table for USB boot)
- Solution: Rebuild ISO with `xorriso` using `-isohybrid-mbr` and `-isohybrid-gpt-basdat` options
- The script now uses `xorriso` for proper hybrid ISO creation
- If using Rufus, ensure you select **DD mode** (not ISO mode)

**"Failed to open \EFI\BOOT\grub.efi - Not Found"**
- SUSE shim looks for `grub.efi` (not `grubx64.efi`) as fallback loader
- Solution: The script now installs the MOK-signed stub as `grub.efi` and `grubx64.efi`
- Also resizes efiboot.img from 3MB to 6MB to fit additional files

**ISO boots but installation fails**
- Installer components may be unsigned
- Solution: Rebuild with `fix_iso_secureboot`

### Alternative: Disable Secure Boot

If you control the hardware and don't need Secure Boot:

1. Enter BIOS/UEFI setup (usually F2, F12, or Del during boot)
2. Navigate to Security → Secure Boot
3. Disable Secure Boot
4. Boot your custom ISO

**Note**: This reduces security as any unsigned code can boot.

## Security Considerations

### What This Simulation Does NOT Provide

1. **Hardware Root of Trust**: The simulation cannot replicate silicon-based trust anchors
2. **Tamper Resistance**: No physical tamper detection or response
3. **Side-Channel Protection**: Software simulation is vulnerable to side-channel attacks
4. **Secure Key Storage**: Keys are stored in filesystem (use HSM in production)
5. **Irreversibility**: eFuse simulation can be modified (unlike real fuses)

### Recommended Use Cases

- ✅ Development and testing of secure boot workflows
- ✅ Educational purposes and training
- ✅ CI/CD pipeline testing of signed images
- ✅ Proof-of-concept demonstrations
- ❌ Production security (use real hardware)
- ❌ Security certification testing
- ❌ Protecting high-value assets

## Documentation

### Architecture Documents (in `docs/`)

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Overview and quick reference |
| [docs/BOOT_PROCESS.md](docs/BOOT_PROCESS.md) | Detailed UEFI boot chain explanation |
| [docs/KEY_MANAGEMENT.md](docs/KEY_MANAGEMENT.md) | Key generation and management guide |
| [docs/ISO_CREATION.md](docs/ISO_CREATION.md) | ISO creation and USB boot setup |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |

## External References

- [NXP HABv4 Documentation](https://www.nxp.com/docs/en/application-note/AN4581.pdf)
- [Photon OS Build Wiki](https://github.com/dcasota/photonos-scripts/wiki)
- [OP-TEE Documentation](https://optee.readthedocs.io/)
- [Trusted Firmware-A](https://trustedfirmware-a.readthedocs.io/)
- [UEFI Secure Boot Specification](https://uefi.org/specs/UEFI/2.10/32_Secure_Boot_and_Driver_Signing.html)
- [Shim Bootloader](https://github.com/rhboot/shim)
- [Ventoy Secure Boot](https://www.ventoy.net/en/doc_secure.html)

## License

This simulation environment is provided for educational and development purposes. Refer to individual component licenses (U-Boot, OP-TEE, TF-A, Linux) for specific terms.

## Contributing

Contributions are welcome. Please ensure any modifications maintain compatibility with both x86_64 and aarch64 architectures and follow the existing code structure.
