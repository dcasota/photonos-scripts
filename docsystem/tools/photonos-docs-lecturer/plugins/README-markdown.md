# Markdown Plugin

## Overview

The Markdown Plugin detects and fixes markdown rendering artifacts in documentation. It handles both deterministic fixes (header spacing) and LLM-assisted complex fixes.

**Plugin ID:** 10  
**Requires LLM:** Yes (for complex fixes)  
**Version:** 1.0.0

## Features

- Detect unrendered markdown syntax
- Fix header spacing issues (deterministic)
- Fix complex markdown artifacts (LLM)
- Handle unclosed code blocks

## Usage

### Enable Markdown Fixes

```bash
# Apply markdown fixes (LLM recommended)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 10 \
  --llm xai --XAI_API_KEY your_key
```

### Header Spacing Only (No LLM)

```bash
# Fix header spacing without LLM
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 7
```

## What It Detects

### Unrendered Markdown Artifacts

| Pattern | Description |
|---------|-------------|
| `## Header` | Unrendered header |
| `* item` | Unrendered bullet |
| `[text](url)` | Unrendered link |
| `` `code` `` | Unrendered inline code |
| `**bold**` | Unrendered bold |
| `_italic_` | Unrendered italic |

### Header Spacing Issues

```markdown
# Wrong
####Title

# Correct
#### Title
```

### Unclosed Code Blocks

```markdown
# Wrong
```bash
command
(missing closing ```)
```

## What It Preserves

- YAML front matter (--- ... ---)
- All URLs and paths
- Product names
- Existing code block content

## Deterministic Fixes (ID 7)

These fixes are applied automatically without LLM:

1. **Header spacing:** `####Title` → `#### Title`

## LLM-Assisted Fixes (ID 10)

Complex issues require LLM:

1. Converting inline triple backticks to single backticks
2. Closing unclosed code blocks
3. Fixing mixed inline/fenced code usage

## Log File

```
/var/log/photonos-docs-lecturer-markdown.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [markdown] Detected: Unrendered header
2025-12-11 10:00:01 - INFO - [markdown] Fixed: Fixed 3 header spacing issues
```

## Related Plugins

- **Malformed Code Block Plugin (ID 12):** Handles code block structure issues
- **Backtick Errors Plugin (ID 5):** Handles inline code spacing
