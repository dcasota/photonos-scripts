# Deprecated URL Plugin

**Version:** 2.2.0  
**FIX_ID:** 2  
**Requires LLM:** No

## Description

Detects and replaces deprecated URLs (VMware, VDDK, OVFTOOL, AWS, Bintray, etc.).
Uses two replacement mechanisms:
1. **URL_REPLACEMENTS** - Simple string-based URL replacements
2. **REGEX_REPLACEMENTS** - Pattern-based replacements with optional custom logic

## Issues Detected

### Simple URL Replacements
- **VDDK URLs** - `my.vmware.com/...VDDK...` -> `developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7`
- **OVFTOOL URL** - `my.vmware.com/...OVFTOOL...` -> `developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest`
- **CloudFoundry bosh-stemcell** - Old GitHub URL -> New stemcell builder URL
- **Malformed URLs** - URLs with `./` typos in paths

### Regex-Based Replacements
- **VMware Packages** - `packages.vmware.com/*` -> `packages.broadcom.com/*` (preserves path)
- **AWS EC2 CLI** - Old AWS CLI docs -> New installation guide
- **Bintray URLs** - `dl.bintray.com/*` -> GitHub wiki (service discontinued 2021)

## Path Preservation

VMware packages URLs preserve the original path:
```python
# Before
https://packages.vmware.com/photon/4.0/photon_release_4.0_x86_64/

# After (path preserved)
https://packages.broadcom.com/photon/4.0/photon_release_4.0_x86_64/
```

## Code Block Protection

All URL replacements protect code blocks:
```python
protected, blocks = protect_code_blocks(content)
# Apply URL_REPLACEMENTS and REGEX_REPLACEMENTS
final = restore_code_blocks(result, blocks)
```

## Example Fixes

**Bintray URL:**
```markdown
# Before
Download from https://dl.bintray.com/vmware/photon/3.0/latest

# After
Download from https://github.com/vmware/photon/wiki/downloading-photon-os
```

**VMware Packages URL:**
```markdown
# Before
[Broadcom Photon OS Packages](https://packages.vmware.com/photon)

# After
[Broadcom Photon OS Packages](https://packages.broadcom.com/photon)
```

**VDDK URL:**
```markdown
# Before
[VDDK 6.0](https://developercenter.vmware.com/web/sdk/60/vddk)

# After
[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)
```

## Configuration

No configuration required.

## Changes History

### Version 2.2.0
- Refactored to use unified URL_REPLACEMENTS and REGEX_REPLACEMENTS lists
- Added path preservation for VMware packages URLs
- Added `_replace_url()` helper method
- Simplified detect() and fix() methods to iterate over consolidated data structures

### Version 2.1.0
- Added VDDK, OVFTOOL, and AWS EC2 CLI URL replacements
- Added malformed URL detection and fixing

### Version 2.0.0
- Added VMware packages URL migration to Broadcom

### Version 1.0.0
- Initial release with Bintray URL replacement
