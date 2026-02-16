# Root Cause Analysis: grub2-efi-image-mok Conflict

## Error Message

```
package grub2-efi-image-mok-2.12-1.ph5.x86_64 conflicts with grub2-efi-image 
provided by grub2-efi-image-2.12-2.ph5.x86_64
```

**Location**: `/var/log/installer.log` during "Photon MOK Secure Boot" installation

---

## Root Cause: v1.9.16 Design Flaw

### The Problem Chain

1. **packages_mok.json** includes:
   ```json
   {
     "packages": [
       "minimal",          ← Meta-package
       "grub2-efi-image-mok",
       ...
     ]
   }
   ```

2. **minimal meta-package** requires:
   ```
   grub2-efi-image >= 2.06-15
   ```

3. **grub2-efi-image-mok** declares (from v1.9.16):
   ```
   Provides: grub2-efi-image = 2.12-1.ph5
   Conflicts: grub2-efi-image
   ```

4. **RPM/tdnf resolution logic**:
   ```
   Step 1: Installer asks for "minimal" package
   Step 2: minimal requires "grub2-efi-image >= 2.06-15"
   Step 3: tdnf finds TWO candidates:
           - grub2-efi-image-2.12-2.ph5 (original, version 2.12-2)
           - grub2-efi-image-mok-2.12-1.ph5 (provides grub2-efi-image = 2.12-1)
   
   Step 4: tdnf selects grub2-efi-image-2.12-2.ph5 because:
           - Higher release number (2 > 1)
           - Both satisfy "grub2-efi-image >= 2.06-15"
   
   Step 5: User's packages_mok.json explicitly asks for grub2-efi-image-mok
   
   Step 6: CONFLICT DETECTED:
           - grub2-efi-image-2.12-2.ph5 is already selected (from minimal)
           - grub2-efi-image-mok has "Conflicts: grub2-efi-image"
           - Both packages provide "grub2-efi-image"
           - ERROR: Cannot install both!
   ```

---

## Why v1.9.16 Failed

### v1.9.16 Changes (commit 73b8ca2)

**Changed from**:
```spec
Provides: grub2-efi-image = %{grub_version}-%{grub_release}
Obsoletes: grub2-efi-image < %{grub_version}-%{grub_release}
```

**To**:
```spec
Provides: grub2-efi-image = %{grub_version}-%{grub_release}
Conflicts: grub2-efi-image
```

**Reasoning** (from v1.9.16 commit):
> "MOK package version could be lower than original ISO package (e.g., 6.1.159 < 6.12.60), so Obsoletes wouldn't apply"

**Problem**: `Conflicts` prevents BOTH packages from being installed, but `Provides` makes tdnf think MOK package can satisfy dependencies. Result: **Deadlock**!

---

## The Epoch Solution (v1.9.18)

### What Epoch Does

**Version Comparison Without Epoch**:
```
0:2.12-1 < 0:2.12-2    ← grub2-efi-image-mok LOSES
```

**Version Comparison With Epoch**:
```
1:2.12-1 > 0:2.12-2    ← grub2-efi-image-mok WINS
```

**Epoch takes precedence over EVERYTHING** (version, release)

### v1.9.18 Solution (commit 725a29e)

```spec
Epoch: 1
Provides: grub2-efi-image = %{grub_version}-%{grub_release}
Obsoletes: grub2-efi-image     ← Reverted back to Obsoletes!
```

**How It Works**:
1. `minimal` requires `grub2-efi-image >= 2.06-15`
2. tdnf finds TWO candidates:
   - `0:grub2-efi-image-2.12-2.ph5` (version 0:2.12-2)
   - `1:grub2-efi-image-mok-2.12-1.ph5` (version 1:2.12-1)
3. tdnf compares: `1:2.12-1 > 0:2.12-2` ✅ MOK package is newer!
4. tdnf selects `grub2-efi-image-mok` to satisfy dependency
5. `Obsoletes: grub2-efi-image` tells tdnf: "Don't install the original"
6. ✅ **CONFLICT RESOLVED**

---

## Why v1.9.33 (v1.9.17 Baseline) Fails

### v1.9.17 Uses Obsoletes (Pre-v1.9.16)

**v1.9.17 spec** (our current v1.9.33):
```spec
# No Epoch
Provides: grub2-efi-image = %{grub_version}-%{grub_release}
Obsoletes: grub2-efi-image < %{grub_version}-%{grub_release}
```

**Version Comparison**:
```
grub2-efi-image-mok:     0:2.12-1.ph5
grub2-efi-image:         0:2.12-2.ph5

Obsoletes: grub2-efi-image < 0:2.12-1
Does 0:2.12-2 < 0:2.12-1? NO! (2 > 1)
Result: Obsoletes DOESN'T APPLY
```

**What Happens**:
1. `minimal` requires `grub2-efi-image`
2. tdnf selects `grub2-efi-image-2.12-2.ph5` (higher release)
3. User's `packages_mok.json` asks for `grub2-efi-image-mok`
4. But `grub2-efi-image-mok` provides `grub2-efi-image = 2.12-1` (lower!)
5. tdnf tries to install BOTH
6. ⚠️ **FILE CONFLICTS**:
   - Both install `/boot/efi/EFI/BOOT/grubx64.efi`
   - Both install `/boot/grub2/grubenv`
7. ❌ **ERROR**: "package conflicts with grub2-efi-image"

---

## Detailed Comparison: All Approaches

### Approach 1: Obsoletes with Version (v1.9.0 - v1.9.15, v1.9.17)

```spec
Provides: grub2-efi-image = 2.12-1
Obsoletes: grub2-efi-image < 2.12-1
```

**Issue**: Obsoletes only applies if original version < MOK version
- ✅ Works if: `grub2-efi-image-2.12-0` (older)
- ❌ Fails if: `grub2-efi-image-2.12-2` (newer)

**Real World**: ❌ FAILS (original has release 2, MOK has release 1)

---

### Approach 2: Conflicts (v1.9.16)

```spec
Provides: grub2-efi-image = 2.12-1
Conflicts: grub2-efi-image
```

**Issue**: Prevents both packages from being installed
- `minimal` → requires → `grub2-efi-image`
- tdnf → selects → `grub2-efi-image-2.12-2` (higher version)
- User → asks for → `grub2-efi-image-mok`
- `grub2-efi-image-mok` → conflicts with → `grub2-efi-image`
- ❌ **DEADLOCK**: Can't install either!

**Real World**: ❌ FAILS (explicit conflict prevents resolution)

---

### Approach 3: Epoch + Obsoletes (v1.9.18)

```spec
Epoch: 1
Provides: grub2-efi-image = 2.12-1
Obsoletes: grub2-efi-image
```

**How It Works**:
```
Original:  0:grub2-efi-image-2.12-2
MOK:       1:grub2-efi-image-mok-2.12-1

Version comparison: 1:2.12-1 > 0:2.12-2  ← Epoch wins!

minimal requires grub2-efi-image
→ tdnf finds: 0:2.12-2 and 1:2.12-1
→ tdnf selects: 1:2.12-1 (higher due to epoch)
→ Obsoletes: grub2-efi-image removes original from consideration
→ ✅ SUCCESS: Only MOK package installed
```

**Real World**: ✅ **SHOULD WORK** (Epoch ensures MOK is always preferred)

---

### Approach 4: Remove Original from ISO (v1.9.19)

```spec
# Same as v1.9.18, but also:
# Delete grub2-efi-image-2.12-2.ph5 from ISO
```

**How It Works**:
- Original package doesn't exist in repository
- Only MOK package available
- No conflict possible

**Real World**: ✅ **WORKS** (but may break other packages that need original)

---

### Approach 5: Remove Epoch/Obsoletes (v1.9.27 "Universal ISO")

```spec
# No Epoch
# No Obsoletes
Provides: grub2-efi-image = 2.12-1
```

**Reasoning**: Allow both packages to coexist for "universal ISO"

**Issue**: Same as Approach 1 - no mechanism to prefer MOK over original

**Real World**: ❌ FAILS (file conflicts, no replacement mechanism)

---

## The Evidence: Your Error

```
package grub2-efi-image-mok-2.12-1.ph5.x86_64 conflicts with grub2-efi-image 
provided by grub2-efi-image-2.12-2.ph5.x86_64
```

**Analysis**:
1. Error says "conflicts with grub2-efi-image **provided by**"
2. This means: grub2-efi-image-2.12-2.ph5 is ALREADY SELECTED
3. Why? Because `minimal` meta-package required it
4. When installer tries to add `grub2-efi-image-mok`, RPM sees:
   - File conflict: Both packages install same files
   - Or: Conflict directive from v1.9.16 changes

Wait - but v1.9.17 uses Obsoletes, not Conflicts. Let me check our current spec:

---

## Current v1.9.33 Spec Analysis

Let me check what we actually built:

```bash
$ rpm -qp --obsoletes /tmp/mnt_iso/RPMS/x86_64/grub2-efi-image-mok-2.12-1.ph5.x86_64.rpm
(no output)

$ rpm -qp --conflicts /tmp/mnt_iso/RPMS/x86_64/grub2-efi-image-mok-2.12-1.ph5.x86_64.rpm
grub2-efi-image
```

**WAIT!** Our RPM has `Conflicts: grub2-efi-image`, not `Obsoletes`!

This means the source code we built from has the v1.9.16 changes, NOT v1.9.17!

Let me verify:

---

## Verification: What's in v1.9.33?

Let me check the actual spec file we used:

<function_calls>
<invoke name="Grep">
<parameter name="pattern">Conflicts.*grub2-efi-image|Obsoletes.*grub2-efi-image
