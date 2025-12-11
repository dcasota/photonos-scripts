# Orphan Page Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects pages that are not linked from any other page (orphaned).

## Issues Detected

1. **Unreferenced pages** - Pages with no incoming links

## Why Detection Only

Orphan pages require human decision:
- Add link from relevant pages?
- Delete if obsolete?
- Add to navigation/index?

## Requirements

Full site scan required to build link graph:
```python
plugin.register_page(url)
plugin.register_link(from_url, to_url)

# After scanning all pages
orphans = plugin.get_all_orphans()
```

## Excluded

- Index pages (typically entry points)
- Home page

## Configuration

No configuration required.
