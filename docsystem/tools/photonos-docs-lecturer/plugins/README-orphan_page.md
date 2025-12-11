# Orphan Page Plugin

## Overview

The Orphan Page Plugin detects pages that return HTTP errors (404, 5xx) or are inaccessible. These issues require manual intervention to resolve.

**Plugin ID:** None (detection only)  
**Requires LLM:** No  
**Auto-fixable:** No  
**Version:** 1.0.0

## Features

- Detect HTTP 4xx errors (client errors)
- Detect HTTP 5xx errors (server errors)
- Detect connection timeouts
- Report pages requiring manual review

## Usage

Orphan page detection is always enabled during analysis:

```bash
python3 photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5
```

## What It Detects

| Status | Description | Suggested Action |
|--------|-------------|------------------|
| 404 | Page not found | Remove from sitemap or create page |
| 403 | Forbidden | Check permissions |
| 500 | Server error | Check server configuration |
| 502/503 | Service unavailable | Check server health |
| Timeout | Connection timeout | Check network/server |

## Why No Auto-fix

Orphan pages cannot be automatically fixed because:

1. The page might need to be created
2. The sitemap might need updating
3. Server configuration might need changes
4. Manual decision required on whether to keep/remove

## Log File

```
/var/log/photonos-docs-lecturer-orphan_page.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [orphan_page] Detected: Page returned HTTP 404
```

## Report Format

Issues appear in the CSV report as:

```csv
Page URL,Issue Category,Issue Location Description,Fix Suggestion
https://example.com/missing/,orphan_page,Page returned HTTP 404,Remove from sitemap or fix the page
```

## Manual Resolution

1. Check if the page was moved → Update sitemap
2. Check if page exists → Create the page
3. Check server logs → Fix server issues
