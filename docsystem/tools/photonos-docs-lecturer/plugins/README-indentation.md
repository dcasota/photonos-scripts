# Indentation Plugin

**Version:** 2.0.0  
**FIX_ID:** 11  
**Requires LLM:** Yes (for complex issues)

## Description

Fixes list and content indentation issues.

## Issues Detected

1. **Mixed tabs and spaces** - Inconsistent indentation
2. **Inconsistent list indentation** - Nested lists not aligned

## Code Block Protection

Indentation fixes NEVER modify code blocks (4+ space indentation):
```python
protected, blocks = protect_code_blocks(content)
# Code blocks with 4+ space indentation are protected
result = apply_fixes(protected)
final = restore_code_blocks(result, blocks)
```

## Example Fixes

**Before:**
```markdown
- Item 1
	- Nested with tab
   - Nested with 3 spaces
```

**After:**
```markdown
- Item 1
    - Nested with 4 spaces
    - Nested with 4 spaces
```

## Configuration

No configuration required.
