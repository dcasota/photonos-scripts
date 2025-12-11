# Orphan Image Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects missing or broken images.

## Issues Detected

1. **HTTP 404** - Image not found
2. **Connection errors** - Image server unreachable
3. **Broken HTML images** - `<img src="...">` with invalid src

## Image Formats

Checks both markdown and HTML image syntax:
- `![alt](url)`
- `<img src="url">`

## Why Detection Only

Missing images require human decision:
- Find correct image?
- Remove image reference?
- Update path?

## Configuration

```python
config = {
    'timeout': 10,  # seconds
    'skip_data_urls': True  # Skip data: URLs
}
```
