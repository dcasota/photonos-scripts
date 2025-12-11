# Indentation Plugin

## Overview

The Indentation Plugin detects and fixes indentation issues in markdown lists and code blocks. Requires LLM for intelligent indentation adjustments.

**Plugin ID:** 11  
**Requires LLM:** Yes  
**Version:** 1.0.0

## Features

- Detect improper list nesting
- Fix inconsistent indentation
- Align code blocks inside lists
- Handle nested content

## Usage

```bash
# Apply indentation fixes (requires LLM)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 11 \
  --llm xai --XAI_API_KEY your_key
```

## What It Detects

### Inconsistent List Indentation

```markdown
# Wrong
1. First item
   - Nested with 3 spaces
    - Nested with 4 spaces
  - Nested with 2 spaces

# Should be consistent (2 or 4 spaces)
1. First item
    - Nested with 4 spaces
    - Nested with 4 spaces
    - Nested with 4 spaces
```

### Insufficient Code Block Indentation

```markdown
# Wrong (inside list item)
1. Run this command:
  code here  # Only 2 spaces

# Fixed
1. Run this command:
    code here  # 4 spaces for proper nesting
```

## What It Preserves

- Content inside code blocks
- Product names and paths
- URLs and placeholders
- Domain names

## Log File

```
/var/log/photonos-docs-lecturer-indentation.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [indentation] Detected: Inconsistent list indentation (3 spaces)
2025-12-11 10:00:01 - INFO - [indentation] Fixed: Applied indentation fixes for 2 issues
```

## Why LLM Required

Indentation fixes require understanding context:
- What belongs under which list item
- Whether content is code or prose
- Preserving meaning while fixing structure
