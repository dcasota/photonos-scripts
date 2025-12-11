# Deprecated URL Plugin

## Overview

The Deprecated URL Plugin detects and replaces deprecated URLs with their current equivalents. Handles VMware, VDDK, OVFTOOL, AWS, bosh-stemcell, and Bintray URLs.

**Plugin ID:** 3  
**Requires LLM:** No  
**Version:** 1.0.0

## Features

- Automatic URL replacement
- Handle multiple deprecated domains
- Preserve URL structure where possible

## Usage

```bash
# Apply deprecated URL fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 3
```

## URL Replacements

| Old URL | New URL | Reason |
|---------|---------|--------|
| `packages.vmware.com/*` | `packages.broadcom.com/` | VMware acquisition |
| `my.vmware.com/...VDDK670...` | `developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7` | URL restructure |
| `developercenter.vmware.com/web/sdk/60/vddk` | `developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7` | URL restructure |
| `my.vmware.com/...OVFTOOL410...` | `developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest` | URL restructure |
| `docs.aws.amazon.com/.../set-up-ec2-cli-linux.html` | `docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html` | URL changed |
| `github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md` | `github.com/cloudfoundry/bosh/blob/main/README.md` | Branch renamed |
| `bintray.com/*` | `github.com/vmware/photon/wiki/downloading-photon-os` | Service discontinued (2021) |

## Log File

```
/var/log/photonos-docs-lecturer-deprecated_url.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [deprecated_url] Detected: VMware packages URL deprecated
2025-12-11 10:00:01 - INFO - [deprecated_url] Fixed: Replaced 3 VMware packages URL deprecated
```

## Adding New URL Replacements

To add new deprecated URL patterns, modify the `URL_REPLACEMENTS` list in `plugins/deprecated_url.py`:

```python
URL_REPLACEMENTS = [
    (
        re.compile(r'old-pattern'),
        'new-url',
        'Description'
    ),
    # ... existing patterns
]
```
