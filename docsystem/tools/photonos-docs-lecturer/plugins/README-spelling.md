# Spelling Plugin

## Overview

The Spelling Plugin detects and fixes VMware spelling errors, broken email addresses, and HTML comments.

**Plugin ID:** 2 (VMware spelling)  
**Requires LLM:** No  
**Version:** 1.0.0

## Features

- Fix VMware spelling variations
- Fix broken email addresses (domain split)
- Handle HTML comments

## Usage

```bash
# Fix VMware spelling (ID 2)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 2

# Fix broken emails (ID 1)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 1

# Fix HTML comments (ID 8)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 8
```

## What It Fixes

### VMware Spelling (ID 2)

| Wrong | Correct |
|-------|---------|
| vmware | VMware |
| Vmware | VMware |
| VMWare | VMware |
| VMWARE | VMware |

**Excludes:** URLs, paths, email addresses, code blocks

### Broken Emails (ID 1)

```markdown
# Wrong
Contact: linux-packages@vmware.
                        com

# Fixed
Contact: linux-packages@vmware.com
```

### HTML Comments (ID 8)

```html
<!-- Content that should be visible -->
```

Becomes:

```markdown
Content that should be visible
```

## Log File

```
/var/log/photonos-docs-lecturer-spelling.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [spelling] Detected: Incorrect VMware spelling: vmware
2025-12-11 10:00:01 - INFO - [spelling] Fixed: Fixed VMware spelling
```

## Related Fix IDs

| ID | Description |
|----|-------------|
| 1 | Broken email addresses |
| 2 | VMware spelling |
| 8 | HTML comments |
