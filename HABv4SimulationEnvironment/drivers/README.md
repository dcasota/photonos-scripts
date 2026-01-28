# Driver RPM Packages

This directory contains additional driver firmware and packages to be included in the Photon OS Secure Boot ISO.

## Directory Structure

```
drivers/
├── README.md           # This file
└── RPM/                # Place driver RPM packages here
    └── *.rpm
```

## Usage

To include driver packages in the ISO build:

```bash
# Use default drivers directory (drivers/RPM/)
./PhotonOS-HABv4Emulation-ISOCreator -b --drivers
./PhotonOS-HABv4Emulation-ISOCreator -b -d

# Use custom drivers directory
./PhotonOS-HABv4Emulation-ISOCreator -b --drivers=/path/to/custom/drivers
./PhotonOS-HABv4Emulation-ISOCreator -b -d /path/to/custom/drivers
```

## How It Works

1. **Scan**: The tool scans the drivers directory for `.rpm` files
2. **Detect**: RPM names are matched against known driver patterns
3. **Configure**: Kernel is configured with required modules for detected drivers
4. **Build**: Kernel is built with driver support enabled
5. **Package**: Driver RPMs are copied to ISO and added to `packages_mok.json`
6. **Install**: When selecting "Photon MOK Secure Boot", drivers are installed automatically

## Supported Driver Types

| Pattern | Kernel Modules | Description |
|---------|---------------|-------------|
| `iwlwifi` | iwlwifi, iwlmvm, cfg80211, mac80211 | Intel Wi-Fi 6/6E/7 |
| `rtw88` | rtw88, cfg80211, mac80211 | Realtek Wi-Fi (RTW88) |
| `rtw89` | rtw89, cfg80211, mac80211 | Realtek Wi-Fi (RTW89) |
| `brcmfmac` | brcmfmac, brcmutil, cfg80211 | Broadcom Wi-Fi |
| `ath11k` | ath11k, cfg80211, mac80211 | Qualcomm/Atheros Wi-Fi 6 |
| `e1000e` | e1000e | Intel Ethernet |
| `igb` | igb | Intel Gigabit Ethernet |
| `igc` | igc | Intel I225/I226 Ethernet |
| `nvidia` | DRM support | NVIDIA GPU (firmware only) |

## Adding New Drivers

1. **Obtain the firmware RPM** from linux-firmware or vendor
2. **Place it in** `drivers/RPM/`
3. **Rebuild the ISO** with `--drivers` flag

If the driver type is not in the supported list, you may need to:
1. Add a mapping entry in `PhotonOS-HABv4Emulation-ISOCreator.c`
2. Rebuild the tool with `make`

## Included Packages

### Intel Wi-Fi 6E AX211 Firmware

- **Package**: `linux-firmware-iwlwifi-ax211`
- **Version**: 20260128
- **Source**: linux-firmware git (kernel.org)
- **License**: Intel proprietary (redistributable)

Provides firmware for Intel Wi-Fi 6E AX211 160MHz adapter:
- PCI IDs: 8086:51f0, 8086:51f1
- Supports 2.4/5/6 GHz bands
- Wi-Fi 6E (802.11ax) with 160MHz channels

**Kernel requirement**: The kernel must have `CONFIG_IWLWIFI=m` enabled (done automatically by `--drivers`).

## Creating Driver RPMs

To create a firmware RPM package:

```bash
# Example: Create iwlwifi firmware RPM
mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy firmware files to SOURCES
cp iwlwifi-*.ucode rpmbuild/SOURCES/
cp LICENCE.iwlwifi_firmware rpmbuild/SOURCES/

# Create spec file (see linux-firmware-iwlwifi-ax211.spec as template)
# Build RPM
rpmbuild --define "_topdir $(pwd)/rpmbuild" -bb rpmbuild/SPECS/your-firmware.spec
```

## Troubleshooting

### Driver not loading after installation

1. Check if kernel module is available:
   ```bash
   modinfo iwlwifi
   ```

2. Check if firmware is installed:
   ```bash
   ls /lib/firmware/iwlwifi-*
   ```

3. Check dmesg for errors:
   ```bash
   dmesg | grep -i iwlwifi
   ```

### Firmware not found

The firmware files must match the kernel driver's expected filenames. Check:
```bash
dmesg | grep "firmware"
```

### Module not signed

If you see "module verification failed", the kernel was built with `CONFIG_MODULE_SIG_FORCE=y` but the module isn't signed. The `--drivers` flag ensures modules are built and signed during kernel compilation.
