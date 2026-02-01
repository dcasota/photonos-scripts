# HABv4 Persistent Memory

## Session Summary (Updated Live)
- Current goal: Maintain and improve Photon OS Secure Boot ISO creation tool
- Last update: v1.9.28 - Auto-detect highest kernel version for Photon 6.0+
- Key decisions made:
  - Use `/root/common/SPECS/linux/vX.Y/` for release 6.0+ (auto-detect highest)
  - Preserve legacy `/root/{release}/SPECS/linux/` for 4.0/5.0

## Recent Changes (v1.9.28)
- Implemented `find_common_kernel_spec()` to scan version directories
- Refactored `parse_spec_version()` for reuse
- Updated `get_kernel_version_from_spec()` with release-based logic
- Result: Photon 6.0 now correctly uses kernel 6.12.60 instead of 6.1.158

## Architecture Notes
- Secure boot chain priority: shim → grub → kernel
- Patch application order is critical
- Kernel spec lookup: release >= 6.0 uses common path, others use legacy
