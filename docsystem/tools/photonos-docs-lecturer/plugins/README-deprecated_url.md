# Deprecated URL Plugin

**Version:** 2.1.0  
**FIX_ID:** 2  
**Requires LLM:** No

## Description

Detects and replaces deprecated URLs like Bintray (discontinued in 2021).

## Issues Detected

1. **Bintray URLs** - `dl.bintray.com/vmware/photon` and variants

## Replacement

All Bintray URLs are replaced with:
```
https://github.com/vmware/photon/wiki/downloading-photon-os
```

## Code Block Protection

URL replacement protects code blocks:
```python
protected, blocks = protect_code_blocks(content)
result = BINTRAY_PATTERN.sub(replacement, protected)
final = restore_code_blocks(result, blocks)
```

## Example Fixes

**Before:**
```markdown
Download from https://dl.bintray.com/vmware/photon/3.0/latest
```

**After:**
```markdown
Download from https://github.com/vmware/photon/wiki/downloading-photon-os
```

## Configuration

No configuration required.
