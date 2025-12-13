# Spelling Plugin

**Version:** 2.0.0  
**FIX_ID:** 7  
**Requires LLM:** No

## Description

Fixes incorrect VMware and Photon OS spelling variants.

## Issues Detected

1. **VMware variants** - `Vmware`, `vmware`, `VMWare`, `VMWARE`
2. **Photon OS variants** - `photon os`, `Photon os`, `photon OS`

## Correct Spellings

- `VMware` (not Vmware, vmware, VMWare)
- `Photon OS` (not photon os, Photon os)

## Code Block Protection

Spelling fixes exclude code blocks:
```python
safe_content = strip_code_blocks(content)
# Detection on safe_content

protected, blocks = protect_code_blocks(content)
result = apply_fixes(protected)
final = restore_code_blocks(result, blocks)
```

## Example Fixes

**Before:**
```markdown
Install vmware tools on your Photon os machine.
```

**After:**
```markdown
Install VMware tools on your Photon OS machine.
```

## Special Cases

- `vmware.com` is NOT changed (domain names are lowercase)
- Code blocks are never modified

## Configuration

No configuration required.
