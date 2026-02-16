# Photon OS Installer Failure Analysis - Error 1525

## Problem Statement
Installation from the secureboot ISO fails with "Error(1525) : rpm transaction failed" during package installation phase.

## Root Cause Analysis

### Primary Issue: File Conflicts Between linux-mok and linux-esx-mok

The RPM transaction failed because both `linux-mok` and `linux-esx-mok` packages contained **the same ESX kernel files**, causing file conflicts:

**Conflicting files:**
- `/boot/config-6.12.60-10.ph5-esx`
- `/boot/initrd.img-6.12.60-10.ph5-esx`
- `/boot/linux-6.12.60-10.ph5-esx.cfg`
- `/boot/System.map-6.12.60-10.ph5-esx`
- `/boot/vmlinuz-6.12.60-10.ph5-esx`

### Why Did This Happen?

#### Issue 1: rpmbuild Directory Contamination
1. **rpmbuild reuses BUILD directory** across package builds without cleaning
2. When building `linux-mok` followed by `linux-esx-mok`:
   - `linux-mok` extracts files to `BUILD/boot/` (e.g., `vmlinuz-6.12.60-14.ph5`)
   - `linux-esx-mok` extracts files to **same** `BUILD/boot/` (e.g., `vmlinuz-6.12.60-10.ph5-esx`)
   - Files accumulate in BUILD directory
3. The `%install` section used **wildcards** that captured ALL files:
   ```bash
   install -m 0644 ./boot/vmlinuz-* %%{buildroot}/boot/
   ```
4. Result: Both packages ended up with files from both kernels

**Fix Applied:** 
- Added BUILD directory cleanup before each kernel build
- Modified `%install` to use specific file patterns instead of wildcards

#### Issue 2: Custom Kernel Module Mismatch
1. The build system creates **ONE custom kernel** with ESX config (`config-esx_x86_64`)
2. This produces modules directory named `6.12.60-esx`
3. Both `linux-mok` and `linux-esx-mok` specs look for custom kernel at `/root/hab_keys/vmlinuz-mok`
4. The custom kernel injection code takes the **FIRST** module directory found without checking flavor
5. Result: `linux-mok` incorrectly used ESX modules (`6.12.60-esx`) instead of standard modules

**Expected behavior:**
- `linux-mok` should contain: `vmlinuz-6.12.60-14.ph5` + modules `6.12.60-14.ph5` (or similar standard naming)
- `linux-esx-mok` should contain: `vmlinuz-6.12.60-10.ph5-esx` + modules `6.12.60-esx`

**Fix Applied:**
- Made custom kernel injection flavor-aware
- Added KERNEL_FLAVOR variable to match modules to package flavor
- For non-standard flavors (esx, rt, etc.), only use modules with matching suffix
- If no matching custom modules found, keep original RPM modules

## Technical Details

### Version Comparisons

**Before Fix (v1.9.29):**
```
linux-mok-6.12.60-14.ph5.x86_64.rpm contains:
  /boot/vmlinuz-6.12.60-14.ph5          ✓ Correct
  /boot/vmlinuz-6.12.60-10.ph5-esx      ✗ WRONG - ESX file
  /boot/System.map-6.12.60-14.ph5       ✓ Correct
  /boot/System.map-6.12.60-10.ph5-esx   ✗ WRONG - ESX file
  /lib/modules/6.12.60-esx              ✗ WRONG - ESX modules

linux-esx-mok-6.12.60-10.ph5.x86_64.rpm contains:
  /boot/vmlinuz-6.12.60-10.ph5-esx      ✓ Correct
  /boot/System.map-6.12.60-10.ph5-esx   ✓ Correct
  /lib/modules/6.12.60-esx              ✓ Correct
```

**FILE CONFLICTS:** Both packages have `/boot/*-10.ph5-esx` files → Error 1525

**After Fix (v1.9.30):**
```
linux-mok-6.12.60-14.ph5.x86_64.rpm contains:
  /boot/vmlinuz-6.12.60-14.ph5          ✓ Correct
  /boot/System.map-6.12.60-14.ph5       ✓ Correct
  /boot/config-6.12.60-14.ph5           ✓ Correct
  /lib/modules/6.12.60-14.ph5           ✓ Correct (from original RPM)

linux-esx-mok-6.12.60-10.ph5.x86_64.rpm contains:
  /boot/vmlinuz-6.12.60-10.ph5-esx      ✓ Correct
  /boot/System.map-6.12.60-10.ph5-esx   ✓ Correct
  /boot/config-6.12.60-10.ph5-esx       ✓ Correct
  /lib/modules/6.12.60-esx              ✓ Correct (from custom build)
```

**NO CONFLICTS:** Each package has its own distinct files

### Code Changes

#### Change 1: BUILD Directory Cleanup (rpm_secureboot_patcher.c)
```c
static int build_single_rpm(...) {
    // NEW: Clean BUILD directory before each kernel build
    if (strstr(spec_name, "linux") != NULL) {
        snprintf(cmd, sizeof(cmd), "rm -rf '%s/BUILD/'*", config->rpmbuild_dir);
        log_debug("Cleaning BUILD directory before kernel build");
        run_cmd(cmd);
    }
    
    // Build the RPM...
}
```

#### Change 2: Specific File Installation (rpm_secureboot_patcher.c)
```bash
# OLD (wildcards captured everything):
install -m 0644 ./boot/vmlinuz-* %%{buildroot}/boot/
install -m 0644 ./boot/System.map-* %%{buildroot}/boot/

# NEW (specific patterns):
KERNEL_VER_REL=$(echo '%%{kernel_file}' | sed 's/vmlinuz-//')
install -m 0644 ./boot/%%{kernel_file} %%{buildroot}/boot/
install -m 0644 ./boot/System.map-${KERNEL_VER_REL} %%{buildroot}/boot/
```

#### Change 3: Flavor-Aware Module Selection (rpm_secureboot_patcher.c)
```bash
# NEW: Match modules to kernel flavor
KERNEL_FLAVOR="esx"  # or "rt", "aws", etc. (empty for standard)

for mod_path in "$KERNEL_BUILD_DIR"/modules/lib/modules/*; do
    MOD_VER=$(basename "$mod_path")
    
    # For non-standard flavors, only use modules matching that flavor
    if [ -n "$KERNEL_FLAVOR" ] && [ "$KERNEL_FLAVOR" != "linux" ]; then
        if ! echo "$MOD_VER" | grep -q -- "-${KERNEL_FLAVOR}$"; then
            continue  # Skip non-matching modules
        fi
    fi
    
    # Use this module directory
    cp -a "$mod_path" ./lib/modules/
    break
done
```

## Verification

### How to Verify the Fix

1. **Mount the secureboot ISO:**
   ```bash
   mount -o loop /path/to/photon-secureboot.iso /mnt
   ```

2. **Check linux-mok package contents:**
   ```bash
   rpm -qlp /mnt/RPMS/x86_64/linux-mok-*.rpm | grep "^/boot/"
   ```
   **Expected:** Only files with `-14.ph5` (or standard version pattern), NO `-esx` files

3. **Check linux-esx-mok package contents:**
   ```bash
   rpm -qlp /mnt/RPMS/x86_64/linux-esx-mok-*.rpm | grep "^/boot/"
   ```
   **Expected:** Only files with `-10.ph5-esx` (or ESX version pattern)

4. **Check for conflicts:**
   ```bash
   comm -12 <(rpm -qlp linux-mok-*.rpm | sort) <(rpm -qlp linux-esx-mok-*.rpm | sort)
   ```
   **Expected:** No output (no common files)

### Test Installation

1. Boot from the fixed secureboot ISO
2. Select "Photon MOK Secure Boot" installation option
3. Complete the installer wizard
4. Installer should complete successfully without Error 1525

## Timeline

- **Before v1.9.10:** Installation worked (only linux-mok in packages_mok.json)
- **v1.9.29:** Added linux-esx-mok to match original Photon pattern → Exposed file conflict bug
- **v1.9.30 (Feb 1):** Fixed file conflicts and module mismatch

## Lessons Learned

1. **rpmbuild BUILD directory is persistent** - must be cleaned between builds of related packages
2. **Wildcard patterns in %install are dangerous** - can pick up unintended files from previous builds
3. **Custom kernel injection needs flavor awareness** - different kernel variants need different modules
4. **Test with both packages installed** - file conflicts only appear when installing multiple related packages

## References

- Git commits: 0c077a3, e8c298b
- Repository: https://github.com/dcasota/photonos-scripts/tree/master/HABv4SimulationEnvironment
- Error code 1525: RPM transaction failure (file conflicts or dependency issues)
