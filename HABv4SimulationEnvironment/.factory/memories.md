# HABv4 Persistent Memory

## Session Summary (Updated Live)
- Current goal: Maintain and improve Photon OS Secure Boot ISO creation tool
- Last update: v1.9.37 - Two-repository architecture (Error 1525 definitive fix)
- Key decisions made:
  - Two-repository architecture: `RPMS/` (VMware Original) + `RPMS_MOK/` (hardlinked, MOK replacements)
  - Root cause: installer.py hardcodes `packages.append('grub2-efi-image')` (upstream v2.8 still has it)
  - Installer patches: packageselector.py (pass repo_path) + installer.py (override repo_paths)
  - Mirror menu entries: 4 MOK + 5 Original options in build_install_options_all.json
  - Driver packages added to ALL packages_*.json files (not just packages_mok.json)
  - No more packages_mok.json - all options reuse original package list files
  - Use `/root/common/SPECS/linux/vX.Y/` for release 6.0+ (auto-detect highest)
  - Preserve legacy `/root/{release}/SPECS/linux/` for 4.0/5.0

## Recent Changes (v1.9.37)
- Two-repository architecture eliminates Error 1525 definitively
- rpm_integrate_to_iso() rewritten: creates RPMS_MOK/ with hardlinks, removes conflicting packages, adds MOK variants
- PhotonOS-HABv4Emulation-ISOCreator.c: mirror MOK entries, packageselector.py/installer.py patches
- Driver integration updated: adds drivers to all packages_*.json files
- Build verified: 5.0 GB ISO with eFuse + RPM signing + drivers

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
