# Markdown Plugin

**Version:** 2.0.0  
**FIX_ID:** 10  
**Requires LLM:** Yes (for complex issues)

## Description

Fixes markdown formatting issues like missing header spacing and broken links.

## Issues Detected

1. **Missing heading space** - `##Title` should be `## Title`
2. **Broken links** - `[text] (url)` should be `[text](url)`
3. **Unrendered formatting** - Bold/italic not rendering

## Code Block Protection

Detection excludes code blocks:
```python
safe_content = strip_code_blocks(content)
```

Fixes protect code blocks:
```python
protected, blocks = protect_code_blocks(content)
result = apply_fixes(protected)
final = restore_code_blocks(result, blocks)
```

## Example Fixes

**Before:**
```markdown
##Installation Guide

[Download here] (https://example.com)
```

**After:**
```markdown
## Installation Guide

[Download here](https://example.com)
```

## Configuration

No configuration required.
