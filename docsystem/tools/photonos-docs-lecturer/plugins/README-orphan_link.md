# Orphan Link Plugin

## Overview

The Orphan Link Plugin detects broken hyperlinks within documentation pages by validating internal links via HTTP HEAD requests.

**Plugin ID:** None (detection only)  
**Requires LLM:** No  
**Auto-fixable:** No  
**Version:** 1.0.0

## Features

- Validate internal hyperlinks
- Cache link check results for efficiency
- Report broken links with context

## What It Detects

- Links returning 404 (Not Found)
- Links returning 5xx (Server Error)
- Links timing out
- Links to external pages (optional)

## Usage

Link validation is part of the standard analysis:

```bash
python3 photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5
```

## Log File

```
/var/log/photonos-docs-lecturer-orphan_link.log
```

## Report Format

```csv
Page URL,Issue Category,Issue Location Description,Fix Suggestion
https://example.com/page/,orphan_link,"Link text: 'Old Guide', URL: /old/path",Remove or update link (status: 404)
```

## Manual Resolution

1. **Update link target:** Change URL to correct path
2. **Remove link:** If content no longer exists
3. **Update link text:** If pointing to renamed page
4. **Add redirect:** Configure server redirect for old URLs
