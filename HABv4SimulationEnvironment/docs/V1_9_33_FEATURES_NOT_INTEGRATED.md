# v1.9.33 Features Not Yet Integrated

**Base**: v1.9.17 (commit 74ad9a0)  
**Applied Fixes**:
1. v1.9.24: Multiple vmlinuz file handling (`| head -1`)
2. v1.9.18: Epoch + Obsoletes (replaces Conflicts)

---

## Features NOT Integrated (v1.9.19 to v1.9.32)

### Build-Time Features (Safe to Add Later)

| Version | Feature | Status | Risk | Priority |
|---------|---------|--------|------|----------|
| v1.9.12 | MOK RPM re-copy after GPG signing | ❌ Not integrated | LOW | Medium |
| v1.9.12 | Custom wireless-regdb/iw builds | ❌ Not integrated | LOW | Low |
| v1.9.12 | Driver RPM signing fix | ❌ Not integrated | LOW | Low |
| v1.9.13 | wifi-config package | ❌ Not integrated | LOW | Low |
| v1.9.14 | Multi-key GPG support in initrd | ❌ Not integrated | LOW | **HIGH** |
| v1.9.15 | Modular codebase (habv4_*.c) | ❌ Not integrated | LOW | Low |
| v1.9.20 | eFuse USB hot-plug chainloader | ❌ Not integrated | LOW | Low |
| v1.9.21 | Correct chainloader path | ❌ Not integrated | LOW | Low |
| v1.9.24 | Clean MOK build directory | ❌ Not integrated | LOW | Low |
| v1.9.24 | Photon 4.0 support | ❌ Not integrated | LOW | Low |
| v1.9.25 | Fixed RPM macro in %postun | ❌ Not integrated | LOW | Medium |
| v1.9.26 | Verbose tdnf logging | ❌ Not integrated | LOW | Medium |
| v1.9.28 | Kernel version auto-detection | ❌ Not integrated | LOW | Medium |
| v1.9.30 | Clean BUILD/ before kernel build | ❌ Not integrated | LOW | Low |
| v1.9.31 | Flavor-aware module selection | ❌ Not integrated | LOW | Low |

### Package/Dependency Features (Risky - May Cause Issues)

| Version | Feature | Status | Risk | Reason to Avoid |
|---------|---------|--------|------|-----------------|
| v1.9.19 | Remove original packages from ISO | ❌ **INTENTIONALLY AVOIDED** | HIGH | Creates dependency gaps |
| v1.9.22 | Full repodata rebuild (no --update) | ❌ Not integrated | MEDIUM | May affect package resolution |
| v1.9.23 | Remove kernel-dependent packages | ❌ Not integrated | MEDIUM | May break linux-devel users |
| v1.9.27 | Universal ISO (remove Epoch/Obsoletes) | ❌ **INTENTIONALLY AVOIDED** | HIGH | Breaks MOK replacement |
| v1.9.29 | Dual kernel packages (linux-esx-mok) | ❌ Not integrated | MEDIUM | Requires filtering logic |
| v1.9.32 | linux-mok in all_linux_flavors | ❌ Not integrated | MEDIUM | Complex installer patching |

---

## High Priority Features to Add

### 1. v1.9.14: Multi-key GPG Support (HIGH PRIORITY)

**Why Important**: Without this, `--rpm-signing` causes installer GPG verification failures.

**Current Issue**:
```
[WARN] HABv4 GPG key not found at /root/tmp_iso_*/iso/RPM-GPG-KEY-habv4
```

**What It Does**:
- Extract VMware GPG keys from photon-repos RPM
- Install both VMware + HABv4 keys in initrd
- Update photon-iso.repo with multiple keys

**Impact if Missing**: Installer may fail to verify HABv4-signed MOK packages

### 2. v1.9.26: Verbose TDNF Logging (MEDIUM PRIORITY)

**Why Important**: Debugging Error(1525) requires seeing actual TDNF errors.

**What It Does**:
- Patches tdnf.py to log full JSON error output
- Errors visible in /var/log/installer.log

**Impact if Missing**: Difficult to debug installation failures

### 3. v1.9.25: Fixed RPM Macro in %postun (MEDIUM PRIORITY)

**Why Important**: RPM uninstallation may fail with literal `%{...}` in path.

**What It Does**:
- Changes `%{kernel_file#vmlinuz-}` to shell parameter expansion
- Fixes scriptlet execution

**Impact if Missing**: Kernel uninstallation may fail

### 4. v1.9.28: Kernel Version Auto-Detection (MEDIUM PRIORITY)

**Why Important**: Photon 6.0 support requires dynamic kernel version selection.

**What It Does**:
- Scans `/root/common/SPECS/linux/` for highest kernel version
- Auto-selects v6.12 over v6.1 for Photon 6.0

**Impact if Missing**: May select wrong kernel for Photon 6.0

---

## Medium Priority Features

### 5. v1.9.12: MOK RPM Re-copy After Signing

**What It Does**: Copies signed MOK RPMs to ISO after GPG signing (currently copies before)

**Impact if Missing**: ISO may contain unsigned MOK RPMs even with `--rpm-signing`

### 6. v1.9.30/v1.9.31: Build Cleanups

**What They Do**:
- v1.9.30: Clean BUILD/ directory before each kernel build
- v1.9.31: Flavor-aware module selection

**Impact if Missing**: Potential file conflicts between linux-mok and linux-esx-mok

---

## Low Priority / Optional Features

| Version | Feature | Notes |
|---------|---------|-------|
| v1.9.12 | wireless-regdb, iw custom builds | WiFi regulatory support |
| v1.9.13 | wifi-config package | Automatic WiFi configuration |
| v1.9.15 | Modular codebase | Code organization only |
| v1.9.20 | eFuse USB hot-plug | Chainloader reload for USB rescan |
| v1.9.21 | Correct chainloader path | ISO boot fix |
| v1.9.24 | Photon 4.0 support | Legacy version support |
| v1.9.24 | Clean MOK build directory | Prevents stale packages |

---

## Features Intentionally NOT Integrated

### v1.9.19: Remove Original Packages

**Reason**: Creates asymmetry where MOK packages provide/obsolete originals, but originals don't exist. May break dependencies.

**Status**: ❌ **AVOIDED** - Keep original packages in ISO

### v1.9.27: Universal ISO (Remove Epoch/Obsoletes)

**Reason**: Without Epoch, MOK packages can't win version comparison against higher-versioned originals.

**Status**: ❌ **AVOIDED** - Keep Epoch for proper package replacement

---

## Current v1.9.33 Status

### What Works

✅ Kernel build with USB drivers built-in  
✅ Custom kernel injection into linux-mok RPM  
✅ Module signature preservation (RPM strip disabled)  
✅ Driver integration (`--drivers` parameter)  
✅ WiFi subsystem support (CFG80211, MAC80211)  
✅ WPA2/WPA3 crypto algorithms  
✅ Custom kernel .config in RPM  
✅ eFuse USB detection (GRUB modules)  
✅ Multiple vmlinuz handling (from v1.9.24)  
✅ **Epoch + Obsoletes** (from v1.9.18) - Fixes Conflicts deadlock  

### What May Not Work

⚠️ GPG verification (v1.9.14 multi-key not integrated)  
⚠️ MOK RPM signing (v1.9.12 re-copy not integrated)  
⚠️ Verbose error logging (v1.9.26 not integrated)  
⚠️ Photon 6.0 kernel auto-detection (v1.9.28 not integrated)  

---

## Recommended Integration Order

If installation testing succeeds, add features in this order:

1. **v1.9.14**: Multi-key GPG support (fixes `--rpm-signing`)
2. **v1.9.26**: Verbose tdnf logging (debugging)
3. **v1.9.25**: Fixed RPM macro (scriptlet fix)
4. **v1.9.28**: Kernel auto-detection (Photon 6.0)
5. **v1.9.12**: MOK RPM re-copy after signing
6. **v1.9.30/v1.9.31**: Build cleanups

Test after each addition to ensure stability.

---

## Summary

**v1.9.33 = v1.9.17 + v1.9.24 (vmlinuz fix) + v1.9.18 (Epoch)**

**Total Features Not Integrated**: 16 from v1.9.19-v1.9.32

**Intentionally Avoided**: 2 (v1.9.19, v1.9.27)

**High Priority Missing**: 1 (v1.9.14 multi-key GPG)

**Next Step**: Test installation. If successful, incrementally add high-priority features.
