# Full Secure Build Example

This document shows a complete example of building a Photon OS Secure Boot ISO with all security features enabled.

## Command

```bash
./PhotonOS-HABv4Emulation-ISOCreator \
    --release 5.0 \
    --build-iso \
    --setup-efuse \
    --create-efuse-usb=/dev/sdd \
    --efuse-usb \
    --rpm-signing \
    --yes
```

## Options Explained

| Option | Description |
|--------|-------------|
| `--release 5.0` | Target Photon OS 5.0 |
| `--build-iso` | Build the Secure Boot ISO |
| `--setup-efuse` | Create eFuse simulation directory |
| `--create-efuse-usb=/dev/sdd` | Format USB drive as eFuse dongle |
| `--efuse-usb` | Enable eFuse USB verification in GRUB |
| `--rpm-signing` | Enable GPG signing of MOK RPM packages |
| `--yes` | Auto-confirm destructive operations |

*(Note: Custom kernel build with Secure Boot options is now automatic)*

## What Gets Created

### Keys (`/root/hab_keys/`)
- `PK.key`, `PK.crt` - Platform Key
- `KEK.key`, `KEK.crt` - Key Exchange Key
- `DB.key`, `DB.crt` - Signature Database Key
- `MOK.key`, `MOK.crt`, `MOK.der` - Machine Owner Key
- `srk.pem`, `srk_hash.bin` - Super Root Key (HABv4)
- `csf.pem`, `img.pem` - CSF/IMG signing keys
- `kernel_module_signing.pem` - Kernel module signing key
- `.gnupg/` - GPG keyring for RPM signing
- `RPM-GPG-KEY-habv4` - GPG public key for RPM verification

### eFuse Simulation (`/root/efuse_sim/`)
- `srk_fuse.bin` - SRK hash (simulates eFuse)
- `sec_config.bin`, `sec_config.txt` - Security configuration
- `efuse_map.txt` - eFuse memory map

### eFuse USB Dongle (`/dev/sdd` with label `EFUSE_SIM`)
- `efuse_sim/` - Copy of eFuse simulation data
- `RPM-GPG-KEY-habv4` - GPG public key (when --rpm-signing)

### Secure Boot ISO
- `photon-5.0-*.x86_64-secureboot.iso`

#### ISO Contents
```
/
├── ENROLL_THIS_KEY_IN_MOKMANAGER.cer    # MOK certificate for enrollment
├── RPM-GPG-KEY-habv4                     # GPG public key (when --rpm-signing)
├── mok_ks.cfg                            # Kickstart for MOK installation
├── standard_ks.cfg                       # Kickstart for standard installation
├── isolinux/
│   ├── vmlinuz                           # MOK-signed kernel
│   └── initrd.img
├── boot/
│   └── grub2/
│       └── grub.cfg                      # 6-option menu with eFuse check
├── EFI/
│   └── BOOT/
│       ├── BOOTX64.EFI                   # SUSE shim (Microsoft-signed)
│       ├── grub.efi                      # Custom GRUB stub (MOK-signed)
│       ├── grubx64_real.efi              # VMware's original GRUB
│       ├── MokManager.efi                # MOK Manager
│       └── BOOTIA32.EFI                  # 32-bit UEFI support
└── RPMS/
    └── x86_64/
        ├── linux-mok-*.rpm               # MOK-signed kernel package
        ├── grub2-efi-image-mok-*.rpm     # MOK-signed GRUB package
        ├── shim-signed-mok-*.rpm         # MOK shim package
        └── (original packages)
```

## Boot Chain

```
UEFI Firmware (Secure Boot ON)
    │
    ▼
BOOTX64.EFI (SUSE shim - Microsoft-signed)
    │
    ▼
grub.efi (Custom GRUB stub - MOK-signed)
    │
    ├── [eFuse USB Check if --efuse-usb]
    │   Verifies EFUSE_SIM USB is present
    │
    ▼
Stub Menu (5 second timeout):
    1. Custom MOK (Physical HW)  → ks=mok_ks.cfg → MOK packages
    2. VMware Original (VMware)  → ks=standard_ks.cfg → VMware packages
    3. MokManager                → Key enrollment
    4. Reboot
    5. Shutdown
```

## First Boot Instructions

1. **Write ISO to USB**: `dd if=photon-*.iso of=/dev/sdX bs=4M status=progress`
2. **Insert eFuse USB dongle** (labeled `EFUSE_SIM`)
3. **Boot with UEFI Secure Boot ENABLED**
4. **MokManager appears** (blue screen) - Select "Enroll key from disk"
5. **Navigate to**: USB root → `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
6. **Confirm and REBOOT** (not continue)
7. **After reboot**: Stub Menu appears (5 sec timeout)
8. **Select installation option**:
   - **"Install (Custom MOK) - For Physical Hardware"** for physical machines with Secure Boot
   - **"Install (VMware Original) - For VMware VMs"** for VMware virtual machines
9. **Follow the interactive installer** - disk selection, hostname, password, etc.
   (package selection is enforced by kickstart)

## MOK RPM Packages

The build creates three MOK-variant packages:

| Package | Provides | Description |
|---------|----------|-------------|
| `linux-mok-6.1.159-*.rpm` | linux, linux-esx, linux-secure | MOK-signed kernel |
| `grub2-efi-image-mok-2.12-*.rpm` | grub2-efi-image | MOK-signed GRUB |
| `shim-signed-mok-15.8-*.rpm` | shim-signed | Shim package |

These packages:
- Have `-mok` suffix in the name
- Provide the same capabilities as originals
- Conflict with originals (can't install both)
- Are GPG-signed when `--rpm-signing` is used

## RPM Signing (Compliance)

When `--rpm-signing` is enabled:

1. **GPG key pair generated**: RSA 4096-bit, no passphrase
2. **MOK RPMs signed**: Using `rpmsign` with the GPG key
3. **Public key distributed**:
   - ISO root: `/RPM-GPG-KEY-habv4`
   - eFuse USB: `/RPM-GPG-KEY-habv4`
4. **Kickstart imports key**: Automatically during installation

### Compliance Standards
- **NIST SP 800-53** (SI-7: Software Integrity, CM-14: Signed Components)
- **FedRAMP** (requires NIST 800-53 controls)
- **EU Cyber Resilience Act** (Article 10: Software integrity verification)

### Post-Installation Verification

```bash
# Verify GPG key is imported
rpm -qa gpg-pubkey* --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'

# Verify MOK packages are signed
rpm -qa '*-mok*' --qf '%{NAME}\t%{SIGPGP:pgpsig}\n'

# Verify specific package signature
rpm --checksig /path/to/linux-mok-*.rpm
```

## Troubleshooting

### "No MOK RPMs found to sign"
The RPM signing step looks in `/tmp/rpm_mok_build/output`. If this directory was cleaned, re-run the build.

### eFuse USB not detected
- Ensure USB is labeled `EFUSE_SIM`
- Check USB is inserted before boot
- Verify GRUB can see the USB: look for `EFUSE_SIM` in stub menu

### MokManager doesn't appear
- Ensure UEFI Secure Boot is ENABLED
- Disable CSM/Legacy boot in BIOS
- The shim will launch MokManager on first boot with unenrolled keys

### Kernel fails to boot
- Verify MOK key is enrolled: MokManager → "Enroll MOK" shows your key
- Check kernel signature: `sbverify --cert MOK.crt vmlinuz`

## See Also

- [SIGNING_OVERVIEW.md](SIGNING_OVERVIEW.md) - Secure Boot vs RPM signing comparison
- [RPM_SIGNING_IMPLEMENTATION.md](RPM_SIGNING_IMPLEMENTATION.md) - Implementation details
- [README.md](../README.md) - Project overview
