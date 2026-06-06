# Version Table: v1.9.0 to v1.9.56

> Latest summarised in detail: see Version History in `README.md`. The table
> below is a quick reference; the README has the full narrative.

| Version | MOK Option | Summary |
|---------|------------|---------|
| v1.9.56 | ✅ YES | **Bug A** mok_quickstart whitelist robust monkey-patch (replaces fragile `'manifest_file',` anchor that broke against installer 2.2); **Bug B** drop dead "Photon MOK Secure Boot" PackageSelector entry (made obsolete by v1.9.41 MokQuickstart); **Bug C** back-navigation deferred to v1.9.57 |
| v1.9.55 | ✅ YES | Disable Linux floppy driver (`CONFIG_BLK_DEV_FD=n`) — 128MB efuse-img attached as virtual floppy caused 28s timeout + dracut emergency on first boot of installed system |
| v1.9.54 | ✅ YES | Explicit `scripts/config --disable` for FIPS configs (v1.9.53 was no-op against kbuild cache — removing `--enable` doesn't undo prior enable; olddefconfig retains the cached =y) |
| v1.9.53 | ✅ YES | M27 FIPS rolled back to deferred-v1.10b: Photon installer template hardcodes `fips=1 ima_hash=sha256` in installed grub.cfg cmdline; with v1.9.49's CRYPTO_FIPS=y, fips=1 engaged real FIPS mode without userland → first boot emergency |
| v1.9.52 | ✅ YES | M25 placeholder fix: GNU tar refuses empty archives (`--files-from /dev/null`). Tar a tiny placeholder file instead |
| v1.9.51 | ✅ YES | M25 `/ostree-repo.tar.gz` skeleton OSTree repo — FEB-2026 PHOTON_SB_6.0 audit marker. Graceful degradation if ostree CLI absent |
| v1.9.50 | ✅ YES | M24 `/RPMS_MOK/` parallel audit tree — mirror MOK RPMs + mokutil into separate repo (chain-of-trust audit boundary) |
| v1.9.49 | ❌ ROLLED BACK | M27 FIPS 140-3 (CONFIG_CRYPTO_FIPS=y + built-in `fips=1`) — broke first boot, rolled back in v1.9.53 |
| v1.9.48 | ✅ YES | M32 verbose `loglevel=7` in MOK grub.cfg install entry (matches FEB-2026 PHOTON_SB_6.0 build) |
| v1.9.47 | ✅ YES | Full hypervisor coverage: `--enable` (not `--module`) for FUSION_*/HYPERV/ATA_SFF parents; add CONFIG_HYPERV_NET; extend dracut pre-filter with hv_vmbus/hv_storvsc/hv_netvsc/virtio_net. Also: fixed shadow `#define VERSION` in PhotonOS-HABv4Emulation-ISOCreator.c:40 |
| v1.9.46 | ✅ YES | Enable VMware/SATA/NVMe/VirtIO storage drivers in MOK kernel build (partial — see v1.9.47 for FUSION/HYPERV/ATA_PIIX fix) |
| v1.9.45 | ✅ YES | Pre-filter dracut `--add-drivers` to only include drivers whose .ko exists; **cadastre Rec #1 LANDED** — fail-fast on MOK RPM build failure (was log_warn → log_error + return 1) |
| v1.9.44 | ⚠️ BROKEN | Initial expanded dracut --add-drivers; squashed into v1.9.45 narrative (dracut bailed on missing ata_piix; tool reported rc=0 anyway) |
| v1.9.43 | ✅ YES | Whitelist `mok_quickstart` in `Installer.known_keys` (anchor: `'manifest_file',` — see v1.9.56 for robust replacement) |
| v1.9.42 | ✅ YES | PackageSelector display() guard + `_apply_yes` ostree pop (the v1.9.41 `__init__` guard was DEAD CODE — all screens instantiated upfront at startup) |
| v1.9.41 | ✅ YES | "Apply MOK Secure Boot" pre-question UI cascade (`No / Yes-Generic / Yes-ESX`); embedded `mok_quickstart.py` + 4 installer patches per ADR-0027 |
| v1.9.40 | ✅ YES | Complete linuxselector menu/window/set_action_panel guard; `exit_gracefully(cause=inst)` exception cause-chaining (`raise InstallerError(f"...{cause!r}") from cause`) |
| v1.9.39 | ✅ YES | Real `linux-esx-mok.spec` generator + installer hardening |
| v1.9.38 | ✅ YES | Fix python3.11 hardcoded paths (Photon 5.0 ships python3.14); regex-tolerant patches; plug 3 missing patch implementations (all_linux_flavors, linuxselector dict, exit_gracefully cause-chain) |
| v1.9.37 | ✅ YES | `--create-efuse-img=PATH[:SIZE]` — eFuse USB as `.img` file (loop-backed); byte-equivalent to `--create-efuse-usb`; QEMU-attachable, CI-friendly |
| v1.9.36 | ✅ YES | Remove conflicting packages from ISO to unblock MOK installation (Error 1525) |
| v1.9.35 | ✅ YES | Chainloader path, repodata full rebuild, kernel-dependent package removal, RPM macro fix, GPG key path fix, header struct fix, dynamic meta-package expansion |
| v1.9.34 | ✅ YES | Selective feature integration: eFuse USB hot-plug detection, common kernel spec for 6.0+, vmlinuz selection fix |
| v1.9.33 | ✅ YES | Dynamic meta-package expansion (replaces conflicting deps with MOK versions) |

---

## v1.9.0 to v1.9.32 (original table)

| Version | Commit | MOK Option | Summary |
|---------|--------|------------|---------|
| v1.9.0 | a86ebf8 | ✅ YES | Kernel build mandatory, USB drivers built-in, pre-generated initrd |
| v1.9.1 | aa9aab4 | ✅ YES | linux-mok RPM contains custom built kernel+modules (not re-signed standard) |
| v1.9.2 | a5f1f09 | ✅ YES | RPM patcher improvements, better error handling, removed .mok1 suffix |
| v1.9.3 | c96ae93 | ✅ YES | Fixed photon.cfg and initrd symlinks for version mismatch |
| v1.9.4 | 27d1c19 | ✅ YES | Disabled RPM strip to preserve module signatures |
| v1.9.5 | c645563 | ✅ YES | Added --drivers parameter for firmware RPMs, automatic kernel config |
| v1.9.6 | c744599 | ✅ YES | Fixed double .ph5 dist tag, added WiFi subsystem prerequisites |
| v1.9.7 | 54380ba | ✅ YES | Include custom kernel .config in linux-mok RPM |
| v1.9.8 | c4cba99 | ✅ YES | Added WPA2/WPA3 crypto algorithm configs (CCM, GCM, CMAC, AES, etc.) |
| v1.9.9 | d83dc41 | ✅ YES | Inject eFuse verification into mk-setup-grub.sh template |
| v1.9.10 | 015e71c | ✅ YES | ⚠️ Added wireless-regdb, iw to packages_mok.json (don't exist in repos!) |
| v1.9.11 | 68f6fed | ✅ YES | Removed wireless-regdb, iw (unavailable packages) |
| v1.9.12 | 0e22953 | ✅ YES | Re-added wireless-regdb, iw as custom builds, fixed RPM signing |
| v1.9.13 | 003099d | ✅ YES | Added wifi-config package for automatic WiFi setup |
| v1.9.14 | 475a7c5 | ✅ YES | Install multiple GPG keys in initrd (VMware + HABv4) |
| v1.9.15 | 197eb98 | ✅ YES | Refactored code into modular structure (habv4_*.c files) |
| v1.9.16 | 73b8ca2 | ✅ YES | Changed Obsoletes to Conflicts, fixed package naming |
| v1.9.17 | 74ad9a0 | ✅ YES | Added missing GRUB modules for eFuse USB detection |
| v1.9.18 | 725a29e | ✅ YES | Added Epoch: 1 to MOK packages, reverted to Obsoletes |
| v1.9.19 | bcbc98e | ✅ YES | ⚠️ REMOVED original packages from ISO (grub2, shim, linux*) |
| v1.9.20 | c2bdd51 | ✅ YES | Use chainloader instead of configfile for USB rescan |
| v1.9.21 | 6292b77 | ✅ YES | Fixed chainloader path in ISO grub.cfg |
| v1.9.22 | 1b2c068 | ✅ YES | ⚠️ Full repodata rebuild (no --update) |
| v1.9.23 | 84d4124 | ✅ YES | Removed kernel-dependent packages (linux-devel, linux-docs, etc.) |
| v1.9.24 | a47f86b | ✅ YES | Added Photon OS 4.0 support, clean MOK build directory |
| v1.9.25 | 505f5ed | ✅ YES | Fixed unexpanded RPM macro in %postun script |
| v1.9.26 | df9a59e | ✅ YES | Fixed Photon 6.0 kernel selection, added verbose tdnf logging |
| v1.9.27 | bf15b9e | ✅ YES | ⚠️ Universal ISO: REMOVED Epoch and Obsoletes from MOK packages |
| v1.9.28 | d2547db | ✅ YES | Auto-detect highest kernel version for Photon 6.0+ |
| v1.9.29 | 7b07dbb | ✅ YES | ⚠️ Added linux-esx-mok to packages_mok.json (dual kernels) |
| v1.9.30 | 0c077a3 | ✅ YES | Clean BUILD/ before kernel build, specific file patterns |
| v1.9.31 | e8c298b | ✅ YES | Flavor-aware module selection (linux-mok uses standard modules) |
| v1.9.32 | aaeb0b5 | ✅ YES | ⚠️ Added linux-mok to all_linux_flavors in installer.py |

---

## Legend

- ✅ **YES** = "Photon MOK Secure Boot" option present in installer
- ⚠️ = Critical change affecting package installation

---

## Critical Installer-Affecting Changes

| Version | Change | Installer Impact |
|---------|--------|------------------|
| v1.9.10 | Added wireless-regdb, iw (don't exist!) | HIGH - Packages not in repos |
| v1.9.19 | Removed original packages from ISO | CRITICAL - Dependency gaps |
| v1.9.22 | Full repodata rebuild instead of update | HIGH - Package indexing |
| v1.9.27 | Removed Epoch/Obsoletes | CRITICAL - RPM resolution |
| v1.9.29 | Added linux-esx-mok (dual kernels) | HIGH - Requires filtering |
| v1.9.32 | Updated all_linux_flavors | HIGH - Package filtering |

---

## Key Finding

**ALL versions from v1.9.0 onwards include "Photon MOK Secure Boot" as the first installer option.**

This means:
- The MOK installation option has been present throughout the entire v1.9 series
- The feature was introduced earlier (v1.6.0 - commit b4eb9ac, January 25, 2026)
- None of the v1.9.x changes removed or disabled the MOK option
- The issue is not about the option's presence, but about it failing during installation

---

## Most Suspicious Changes (for installation failure)

Based on impact analysis:

1. **v1.9.27** [Probability: 85%]
   - Removed Epoch and Obsoletes from MOK packages
   - RPM may not know MOK packages replace originals
   - Dependency resolution could fail

2. **v1.9.19** [Probability: 80%]
   - Removed original grub2-efi-image, shim-signed, linux packages
   - Creates asymmetry: MOK provides/obsoletes originals, but originals missing
   - `minimal` meta-package may expect exact package names

3. **v1.9.29** [Probability: 75%]
   - Added linux-esx-mok to packages_mok.json
   - User selects ONE kernel, but list has TWO
   - Filtering logic must work correctly (fixed in v1.9.32?)

4. **v1.9.10** [Probability: 70%]
   - Added packages that don't exist in repos
   - Even though v1.9.11 removed and v1.9.12 re-added as custom builds
   - May have left inconsistencies

5. **v1.9.22** [Probability: 60%]
   - Changed repodata regeneration from update to full rebuild
   - May affect how packages are indexed/discovered
