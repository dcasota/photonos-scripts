# Hardcoded Replaces Plugin

**Version:** 1.0.0  
**FIX_ID:** 3  
**Requires LLM:** No

## Description

Fixes known typos and errors using a static list of hardcoded replacements.

## Issues Detected

Common typos and errors including:
- `setttings` -> `settings`
- `the the` -> `the`
- `followng` -> `following`
- `on a init.d-based` -> `on an init.d-based`
- And 18 more specific replacements

## Code Block Protection

This plugin uses `protect_code_blocks()` to ensure fenced code blocks are never modified:

```python
protected_content, code_blocks = protect_code_blocks(content)
# Apply replacements to protected_content
final_content = restore_code_blocks(result, code_blocks)
```

## Example Fixes

**Before:**
```markdown
Check the setttings page for the the configuration.
```

**After:**
```markdown
Check the settings page for the configuration.
```

## Adding New Replacements

Edit the `REPLACEMENTS` list in `hardcoded_replaces.py`:

```python
REPLACEMENTS = [
    ("original text", "fixed text"),
    # Add new entries here
]
```

## Configuration

No configuration required.
