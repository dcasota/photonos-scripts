# HABv4 Persistent Memory

## Session Summary (Updated Live)
- Current goal: Maintain and improve Photon OS Secure Boot ISO creation tool
- Last update: v1.9.38 - Security hardening, installer fixes, debug logging
- Key decisions made:
  - Two-repository architecture: `RPMS/` (VMware Original) + `RPMS_MOK/` (hardlinked, only grub2-efi-image removed)
  - Root cause: installer.py hardcodes `packages.append('grub2-efi-image')` (upstream v2.8 still has it)
  - Installer patches: packageselector.py (pass repo_path) + installer.py (override repo_paths, replace grub2-efi-image with MOK variant)
  - RPMS_MOK keeps ALL original packages except grub2-efi-image (required by minimal meta-package dependency chain)
  - Mirror menu entries: 4 MOK + 5 Original options in build_install_options_all.json
  - Driver packages added to ALL packages_*.json files (not just packages_mok.json)
  - wifi-config RPM removed: file conflict with wpa_supplicant on /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
  - Use `/root/common/SPECS/linux/vX.Y/` for release 6.0+ (auto-detect highest)
  - Preserve legacy `/root/{release}/SPECS/linux/` for 4.0/5.0

## Recent Changes (v1.9.38)
- Replaced system() with fork()/execl() in all 3 run_cmd() implementations
- Fixed Error(1525) installer failures (multiple root causes):
  - repo_paths override: handle /mnt/media (no /RPMS suffix) via base.rstrip("/") + strip /RPMS
  - Remove grub2-efi-image original from RPMS_MOK (Conflicts with MOK variant when minimal pulls it in)
  - Replace grub2-efi-image with grub2-efi-image-mok in package list when MOK selected
  - Keep ALL original packages in RPMS_MOK except grub2-efi-image
  - Remove wifi-config: file conflict with wpa_supplicant
  - Add mok_repo_path to known_keys whitelist
- Added comprehensive debug logging:
  - Kernel cmdline loglevel=7
  - /var/log/installer-debug.log with pre-install state dump
  - tdnf --verbose flag
  - Enhanced error logging (exit code, stderr, package list)
- Fixed Python f-string nested quote syntax errors (intermediate variables)
- Fixed Photon cert bundle generation for 6.0+
- Suppressed GPG_TTY, kernel config, and frame-size cosmetic warnings
- Removed unused strdup_safe() function and wifi-config RPM
- Build verified: zero warnings, 5115 MB ISO

## Previous Changes (v1.9.37)
- Two-repository architecture eliminates Error 1525 definitively
- rpm_integrate_to_iso() rewritten: creates RPMS_MOK/ with hardlinks, removes conflicting packages, adds MOK variants
- PhotonOS-HABv4Emulation-ISOCreator.c: mirror MOK entries, packageselector.py/installer.py patches
- Driver integration updated: adds drivers to all packages_*.json files

## Previous Changes (v1.9.31)
- Fixed module mismatch: linux-mok was using ESX modules instead of standard modules
- Root cause: Custom kernel injection didn't match module flavor to package flavor
- Implementation: Added KERNEL_FLAVOR variable and flavor-aware module selection logic
- Result: Each MOK package uses correct modules for its variant

## Previous Changes (v1.9.30)
- Fixed file conflicts between linux-mok and linux-esx-mok packages
- Root cause: rpmbuild reuses BUILD/ directory, wildcards captured all files
- Fix 1: Clean BUILD/ directory before each kernel build
- Fix 2: Use specific file patterns instead of wildcards in %install
- Result: Eliminated Error(1525) rpm transaction failed

## Previous Changes (v1.9.29)
- Fixed installer failure: Added linux-esx-mok to packages_mok.json
- Root cause: Original packages_minimal.json has both linux and linux-esx
- Analysis: ISO comparison revealed missing linux-esx-mok from install manifest
- Result: Installer now matches original two-kernel pattern

## Previous Changes (v1.9.28)
- Implemented `find_common_kernel_spec()` to scan version directories
- Refactored `parse_spec_version()` for reuse
- Updated `get_kernel_version_from_spec()` with release-based logic
- Result: Photon 6.0 now correctly uses kernel 6.12.60 instead of 6.1.158

## Architecture Notes
- Secure boot chain priority: shim → grub → kernel
- Patch application order is critical
- Kernel spec lookup: release >= 6.0 uses common path, others use legacy
- rpmbuild BUILD/ directory is persistent - must clean between related builds
- Custom kernel injection requires flavor matching for module directories
