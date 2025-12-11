# Orphan Link Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects broken hyperlinks that return 404 or connection errors.

## Issues Detected

1. **HTTP 404** - Link target not found
2. **Connection errors** - Server unreachable
3. **Timeout** - Server not responding

## Why Detection Only

Broken links require human decision:
- Remove the link?
- Update to new URL?
- Replace with archived version?

## URL Validation

- Relative URLs resolved against page URL
- Redirects followed
- HEAD requests used (faster than GET)
- Results cached per session

## Configuration

```python
config = {
    'timeout': 10,  # seconds
    'skip_external': False  # Check only internal links
}
```
