# Epoch Safety Analysis: All GRUB Menu / Wizard Dialog Permutations

## GRUB Menu Options

1. **Install (Custom MOK)** → Uses `packages_mok.json`
2. **Install (VMware Original)** → Uses wizard to select from other package lists

## Wizard Dialog Package Selection Options

When using "Install (VMware Original)", user can choose:
1. **Photon Minimal** → `packages_minimal.json`
2. **Photon Developer** → `packages_developer.json`
3. **Photon OSTree Host** → `packages_ostree_host.json`
4. **Photon Real Time** → `packages_rt.json`

---

## Package Files Analysis

### packages_mok.json (Custom MOK Installation)
```json
{
    "packages": [
        "minimal",              ← Requires grub2-efi-image >= 2.06-15
        "linux-mok",            ← Provides linux = 1:6.1.159 (with Epoch)
        "initramfs",
        "grub2-efi-image-mok",  ← Provides grub2-efi-image = 1:2.12-1 (with Epoch)
        "grub2-theme",
        "shim-signed-mok",      ← Provides shim-signed = 1:15.8-5 (with Epoch)
        ...
    ]
}
```

### packages_minimal.json (VMware Original - Minimal)
```json
{
    "packages": [
        "minimal",    ← Requires grub2-efi-image >= 2.06-15
        "linux",      ← Original: linux = 6.12.60
        "linux-esx",  ← Original: linux-esx = 6.12.60
        ...
    ]
}
```

### packages_developer.json (VMware Original - Developer)
```json
{
    "packages": [
        "minimal",
        "linux",
        "linux-esx",
        "grub2",
        "grub2-efi",   ← Note: grub2-efi, NOT grub2-efi-image
        ...
    ]
}
```

### packages_rt.json (VMware Original - Real Time)
```json
{
    "packages": [
        "minimal",
        "linux-rt",     ← NOT in ISO! Will fail if selected
        "linux-rt-devel",
        ...
    ]
}
```

### packages_ostree_host.json (OSTree)
```json
{
    "packages": []   ← Empty, special handling
}
```

---

## Epoch Safety Matrix

### Critical Packages with Epoch Concerns

| Package | Original Version | MOK Version | Epoch Safe? |
|---------|-----------------|-------------|-------------|
| grub2-efi-image | 0:2.12-2.ph5 | 1:2.12-1.ph5 | ✅ YES |
| linux | 0:6.12.60-14.ph5 | 1:6.1.159-7.ph5 | ✅ YES |
| linux-esx | 0:6.12.60-10.ph5 | 1:6.1.159-7.ph5 | ✅ YES |
| shim-signed | 0:15.8-5.ph5 | 1:15.8-5.ph5 | ✅ YES |
| **linux-esx-mok** | N/A | **0:6.12.60-10.ph5** | ⚠️ **NO EPOCH!** |

---

## Permutation Analysis

### Permutation 1: Custom MOK Installation
**GRUB**: Install (Custom MOK)  
**Wizard**: N/A (packages preset)

**Package Resolution**:
- `minimal` requires `grub2-efi-image >= 2.06-15`
- Available: `grub2-efi-image` (0:2.12-2) vs `grub2-efi-image-mok` (1:2.12-1)
- Epoch comparison: 1:2.12-1 > 0:2.12-2 → **MOK wins** ✅
- `linux-mok` explicitly requested, provides `linux = 1:6.1.159`
- Original `linux` is 0:6.12.60, MOK provides wins
- **Status**: ✅ **EPOCH SAFE**

### Permutation 2: VMware Original → Photon Minimal
**GRUB**: Install (VMware Original)  
**Wizard**: Photon Minimal

**Package Resolution**:
- `minimal` requires `grub2-efi-image >= 2.06-15`
- Explicitly requests: `linux`, `linux-esx`
- NO MOK packages requested
- Uses: `grub2-efi-image` (0:2.12-2), `linux` (0:6.12.60), `linux-esx` (0:6.12.60)
- **Status**: ✅ **EPOCH SAFE** (no MOK packages involved)

### Permutation 3: VMware Original → Photon Developer
**GRUB**: Install (VMware Original)  
**Wizard**: Photon Developer

**Package Resolution**:
- `minimal` requires `grub2-efi-image >= 2.06-15`
- Explicitly requests: `linux`, `linux-esx`, `grub2`, `grub2-efi`
- Note: `grub2-efi` is different from `grub2-efi-image`!
- Uses original packages only
- **Status**: ✅ **EPOCH SAFE** (no MOK packages involved)

### Permutation 4: VMware Original → Photon Real Time
**GRUB**: Install (VMware Original)  
**Wizard**: Photon Real Time

**Package Resolution**:
- Requests: `linux-rt`, `linux-rt-devel`
- **Problem**: `linux-rt` NOT in ISO!
- **Status**: ❌ **WILL FAIL** (missing package, not Epoch issue)

### Permutation 5: VMware Original → Photon OSTree Host
**GRUB**: Install (VMware Original)  
**Wizard**: Photon OSTree Host

**Package Resolution**:
- Empty package list, special OSTree handling
- **Status**: ✅ **EPOCH SAFE** (special installation type)

---

## Potential Issue Found: linux-esx-mok

**Package**: `linux-esx-mok-6.12.60-10.ph5.x86_64.rpm`

**Current Provides**:
```
kernel-mok = 6.12.60-10.ph5
linux-esx = 6.12.60-10.ph5        ← NO EPOCH!
linux-esx-mok = 6.12.60-10.ph5    ← NO EPOCH!
```

**Problem**: `linux-esx-mok` does NOT have Epoch in its Provides!

**However**: This is NOT currently a problem because:
1. `packages_mok.json` requests `linux-mok`, NOT `linux-esx-mok`
2. `linux-esx-mok` is not explicitly requested in any package list
3. The package is only in ISO for potential manual selection

**Risk Assessment**: LOW - but should be fixed for consistency.

---

## Cross-Contamination Analysis

### Can MOK packages interfere with VMware Original installation?

**Question**: When user selects "VMware Original → Photon Minimal", can MOK packages accidentally get installed?

**Analysis**:
1. `packages_minimal.json` explicitly requests: `linux`, `linux-esx`
2. These are package NAMES, not capabilities
3. `linux-mok` is a DIFFERENT package name
4. tdnf will install `linux` (the actual package), not `linux-mok`

**BUT**: The `minimal` meta-package requires `grub2-efi-image` (capability):
- Available: `grub2-efi-image` (0:2.12-2) and `grub2-efi-image-mok` (1:2.12-1)
- Without explicit request, tdnf might pick `grub2-efi-image-mok` due to higher Epoch!

### Critical Finding: VMware Original May Get MOK GRUB!

**Scenario**: User selects "VMware Original → Photon Minimal"

**Expected**: Original grub2-efi-image-2.12-2.ph5  
**Actual Risk**: grub2-efi-image-mok-1:2.12-1.ph5 might be selected!

**Why?**
1. `minimal` requires `grub2-efi-image >= 2.06-15`
2. Both packages satisfy this requirement
3. `grub2-efi-image-mok` has higher Epoch (1 > 0)
4. tdnf may prefer the higher-versioned package!

**Impact**: VMware VM installation gets MOK GRUB → Won't boot on VMware (needs VMware-signed GRUB)

---

## Critical Bug: Epoch May Break VMware Original Installation!

### The Problem

When `minimal` meta-package is resolved, tdnf sees:
- `grub2-efi-image` = 0:2.12-2.ph5
- `grub2-efi-image-mok` provides `grub2-efi-image` = 1:2.12-1.ph5

**Epoch 1 > Epoch 0**, so `grub2-efi-image-mok` may be selected even for VMware Original!

### Why This Matters

| Installation Type | Expected GRUB | May Get Instead |
|-------------------|---------------|-----------------|
| Custom MOK | grub2-efi-image-mok | ✅ Correct |
| VMware Minimal | grub2-efi-image | ⚠️ grub2-efi-image-mok? |
| VMware Developer | grub2-efi-image | ⚠️ grub2-efi-image-mok? |

### Testing Required

Need to verify actual tdnf behavior:
1. Does explicit package name (`linux`) override capability resolution?
2. When `minimal` requires capability, does tdnf prefer higher Epoch?

---

## Recommendations

### 1. Fix linux-esx-mok Epoch (Low Priority)

Add Epoch to `linux-esx-mok` Provides for consistency:
```spec
Provides: linux-esx = 1:%{version}-%{release}
```

### 2. Test VMware Original Installation (High Priority)

Verify that selecting "VMware Original → Photon Minimal" installs:
- `grub2-efi-image` (original, NOT mok)
- `linux` (original, NOT mok)
- `linux-esx` (original, NOT mok)

### 3. Consider Removing MOK Packages from "VMware Original" Path

If Epoch causes wrong package selection, options:
1. Use different repositories for MOK vs Original
2. Remove MOK packages from repo when "VMware Original" selected
3. Explicitly exclude MOK packages in installer logic

### 4. Verify packages_mok.json Explicitly Requests MOK Packages

Current `packages_mok.json` correctly includes:
- `linux-mok` (explicit package name)
- `grub2-efi-image-mok` (explicit package name)
- `shim-signed-mok` (explicit package name)

This should ensure MOK packages are installed for "Custom MOK" path.

---

## Summary

| Permutation | GRUB Choice | Wizard Choice | Epoch Safe? | Notes |
|-------------|-------------|---------------|-------------|-------|
| 1 | Custom MOK | N/A | ✅ YES | MOK packages explicitly requested |
| 2 | VMware Original | Minimal | ⚠️ **NEEDS TESTING** | May get MOK GRUB due to Epoch |
| 3 | VMware Original | Developer | ⚠️ **NEEDS TESTING** | May get MOK GRUB due to Epoch |
| 4 | VMware Original | Real Time | ❌ FAIL | linux-rt not in ISO |
| 5 | VMware Original | OSTree | ✅ YES | Special handling |

### Key Risk

**The Epoch fix may cause VMware Original installation to accidentally install MOK packages!**

This needs immediate testing to verify.
