# Orphan Image Plugin

## Overview

The Orphan Image Plugin detects broken or missing images in documentation pages by validating image source URLs.

**Plugin ID:** None (detection only)  
**Requires LLM:** No  
**Auto-fixable:** No  
**Version:** 1.0.0

## Features

- Validate image sources (src attributes)
- Check markdown image syntax
- Report missing images with context
- Cache check results for efficiency

## What It Detects

- Images returning 404 (Not Found)
- Images with incorrect paths
- Relative path errors
- Missing image files

## Usage

Image validation is part of the standard analysis:

```bash
python3 photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5
```

## Supported Formats

- Markdown images: `![alt](path)`
- HTML images: `<img src="path">`
- Common extensions: .png, .jpg, .jpeg, .gif, .svg, .webp

## Log File

```
/var/log/photonos-docs-lecturer-orphan_image.log
```

## Report Format

```csv
Page URL,Issue Category,Issue Location Description,Fix Suggestion
https://example.com/page/,orphan_image,"Image: screenshot.png",Fix image path or remove reference (status: 404)
```

## Manual Resolution

1. **Fix path:** Correct the image path
2. **Add image:** Upload missing image file
3. **Remove reference:** Delete broken image reference
4. **Update alt text:** If image moved to new location
