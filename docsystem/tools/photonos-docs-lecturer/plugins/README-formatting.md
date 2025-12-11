# Formatting Plugin

**Version:** 2.0.0  
**FIX_ID:** 4  
**Requires LLM:** No

## Description

Fixes missing spaces around inline code backticks and related formatting issues.

## Issues Detected

1. **Missing space before backtick** - `word`code`` should be `word `code``
2. **Missing space after backtick** - `` `code`word`` should be `` `code` word``
3. **Stray backtick typo** - `Clone`the` should be `Clone the`
4. **URLs in backticks** - `` `https://...` `` should be `https://...`

## Code Block Protection

This plugin uses `protect_code_blocks()` to ensure fenced code blocks are never modified:

```python
protected_content, code_blocks = protect_code_blocks(content)
# Apply fixes to protected_content
final_content = restore_code_blocks(result, code_blocks)
```

## Example Fixes

**Before:**
```
Run the`docker ps`command to list containers.
Visit`https://example.com`for more info.
```

**After:**
```
Run the `docker ps` command to list containers.
Visit https://example.com for more info.
```

## Configuration

No configuration required.
