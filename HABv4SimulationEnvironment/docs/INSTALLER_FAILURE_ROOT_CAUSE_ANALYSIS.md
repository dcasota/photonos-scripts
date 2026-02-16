# Root Cause Analysis: Installer Failure Investigation

## Critical Finding

After thorough investigation, I discovered that **v1.9.10 (commit a5ee5ec) does NOT successfully install with "Photon MOK Secure Boot" option.**

### Evidence from v1.9.10 ISO Analysis:

1. **MOK Package Build Failure**:
   - `linux-mok.spec` failed to build (exit code: 1)
   - ISO contains NO MOK packages (grub2-efi-image-mok, shim-signed-mok, linux-mok)
   - Only `mokutil` RPM exists

2. **Missing Packages**:
   - `packages_mok.json` references `wireless-regdb` and `iw`
   - These packages do NOT exist in the ISO
   - Only `iwpmd` exists (different package)

3. **What Actually Works in v1.9.10**:
   - ✅ Original linux packages exist (`linux-6.1.158`, `linux-6.12.60`)
   - ✅ Original grub2-efi-image, shim-signed packages exist
   - ✅ "2. Photon Minimal" option works (uses original VMware packages)
   - ❌ "1. Photon MOK Secure Boot" option would FAIL (missing packages)

## Conclusion

**The user successfully installed using "2. Photon Minimal" (VMware Original packages), NOT "1. Photon MOK Secure Boot" (MOK packages).**

This means:
- The "Photon MOK Secure Boot" installation has NEVER worked properly on Photon 6.0
- v1.9.10 is NOT a valid "last working version" for MOK installation
- The issue exists from v1.6.0 (when MOK option was introduced) through v1.9.32

## Timeline of "Photon MOK Secure Boot" Feature

- **v1.6.0** (commit 9d769d0, ~Jan 25, 2026): First version to introduce "Photon MOK Secure Boot" as separate installer option
- **v1.9.10** (commit a5ee5ec, ~Jan 30, 2026): User's "last working version" - but MOK installation DOESN'T work
- **v1.9.11 → v1.9.32**: Numerous attempts to fix MOK installation, all unsuccessful

## Real Problem

The installer fails with "Error(1525) : rpm transaction failed" because:

### Primary Issue: Package Selection Logic
The installer's `_adjust_packages_based_on_selected_flavor()` function and package dependency resolution has multiple problems:

1. **packages_mok.json includes packages that may not exist** (wireless-regdb, iw, wifi-config, etc.)
2. **packages_mok.json includes BOTH linux-mok and linux-esx-mok** but user selects only ONE
3. **MOK packages provide/obsolete originals but dependency resolution may fail**
4. **Original packages removed from ISO (v1.9.19)** creating dependency gaps

### Why "Photon Minimal" Works
- Uses `packages_minimal.json` with standard packages
- All packages exist in ISO
- No complex flavor filtering needed
- Original VMware-signed packages, no MOK complications

## Recommended Next Steps

### Option 1: Test "Photon Minimal" Installation (Quick Verification)
Boot the current v1.9.32 ISO and select "2. Photon Minimal" to verify that non-MOK installation works. This confirms the issue is specific to MOK packages.

### Option 2: Deep Debug Session
Since the problem has existed since v1.6.0, we need to:
1. Boot ISO in VM
2. Drop to shell during installation
3. Manually run tdnf commands with verbose output
4. Identify exact package causing failure

### Option 3: Simplify packages_mok.json
Remove potentially problematic packages:
```json
{
  "packages": [
    "minimal",
    "linux-mok",
    "initramfs",
    "grub2-efi-image-mok",
    "shim-signed-mok",
    "lvm2",
    "less",
    "sudo"
  ]
}
```

Remove: wireless-regdb, iw, wifi-config, linux-firmware-iwlwifi-ax211, linux-esx-mok, grub2-theme

### Option 4: Keep Original Packages in ISO
Revert v1.9.19's removal of original packages. Allow both original and MOK packages to coexist in the repository.

## Questions for User

1. **Can you confirm**: Did you successfully install using "2. Photon Minimal" option in v1.9.10, not "1. Photon MOK Secure Boot"?

2. **What is your actual goal**:
   - Install with MOK Secure Boot on physical hardware?
   - Install on VMware vSphere VM (VMware Original is better)?
   - Just boot the ISO live (no installation needed)?

3. **Can you test**: Boot current v1.9.32 ISO and try "2. Photon Minimal" to see if that works?

## Next Investigation Steps

If we want to fix "Photon MOK Secure Boot" installation:

1. **Create minimal test case**: Build ISO with absolute minimum packages_mok.json
2. **Add verbose logging**: Capture exact tdnf command and output
3. **Manual package resolution**: Run tdnf commands manually to see exact failure
4. **Dependency tree analysis**: Check if all dependencies can be satisfied
5. **Compare with Photon 5.0**: Check if MOK installation works there

The key is understanding that this isn't a regression from v1.9.10 - it's a feature that has never fully worked on Photon 6.0.
