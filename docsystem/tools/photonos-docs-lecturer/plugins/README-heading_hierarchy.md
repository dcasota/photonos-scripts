# Heading Hierarchy Plugin

## Overview

The Heading Hierarchy Plugin detects and fixes heading level violations in markdown documents. It ensures proper heading progression without skipped levels (e.g., H1 → H3 is invalid).

**Plugin ID:** 6  
**Requires LLM:** No  
**Version:** 1.0.0

## Features

- Detect skipped heading levels
- Automatic heading level adjustment
- Preserve heading text content

## Usage

### Enable Heading Hierarchy Fixes

```bash
# Apply heading hierarchy fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 6
```

### Combine with Other Fixes

```bash
# Apply heading hierarchy with markdown fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 6,7,10
```

## What It Detects

### Skipped Heading Levels

```markdown
# Wrong
# Main Title (H1)
### Subsection (H3) ← Skipped H2!

# Correct
# Main Title (H1)
## Section (H2)
### Subsection (H3)
```

### Examples of Violations

| Before | After | Issue |
|--------|-------|-------|
| H1 → H3 | H1 → H2 | Skipped 1 level |
| H2 → H4 | H2 → H3 | Skipped 1 level |
| H1 → H4 | H1 → H2 | Skipped 2 levels |

## How It Fixes

The plugin adjusts heading levels to ensure proper progression:

1. First heading keeps its level
2. Each subsequent heading can only increase by 1 level
3. Decreases in level are allowed (returning to parent section)

### Example

**Before:**
```markdown
# Overview
### Installation  ← H3 after H1 (skipped H2)
##### Step 1      ← H5 after H3 (skipped H4)
## Configuration  ← Valid decrease
#### Settings     ← H4 after H2 (skipped H3)
```

**After:**
```markdown
# Overview
## Installation   ← Fixed to H2
### Step 1        ← Fixed to H3
## Configuration  ← Unchanged (valid)
### Settings      ← Fixed to H3
```

## Log File

```
/var/log/photonos-docs-lecturer-heading_hierarchy.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [heading_hierarchy] Detected: Skipped 1 heading level(s): H1 -> H3
2025-12-11 10:00:01 - INFO - [heading_hierarchy] Fixed: Changed H3 to H2: Installation...
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| min_first_level | 2 | Minimum expected first heading level |

## Notes

- This fix is deterministic and does not require LLM
- Only ATX-style headings are supported (`#` syntax)
- Setext-style headings (`===` and `---`) are not detected
