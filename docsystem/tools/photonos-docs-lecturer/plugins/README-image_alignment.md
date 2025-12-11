# Image Alignment Plugin

## Overview

The Image Alignment Plugin detects pages with multiple images that lack proper CSS alignment classes. Reports issues for manual review as alignment preferences vary by design.

**Plugin ID:** None (detection only)  
**Requires LLM:** No  
**Auto-fixable:** No  
**Version:** 1.0.0

## Features

- Detect unaligned multiple images
- Check for alignment CSS classes
- Check for container wrappers

## What It Detects

Pages with 2+ images lacking:
- Alignment classes (align-center, text-center, etc.)
- Container wrappers (figure, gallery, etc.)
- Float/flex/grid styling

## CSS Classes Checked

### Alignment Classes
- `align-center`, `align-left`, `align-right`
- `centered`, `center`
- `img-responsive`, `img-fluid`
- `text-center`, `text-left`, `text-right`
- `mx-auto`, `d-block`
- `float-left`, `float-right`

### Container Classes
- `image-container`, `figure`
- `gallery`, `img-gallery`
- `images-row`, `flex`, `grid`

## Usage

```bash
python3 photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5
```

## Log File

```
/var/log/photonos-docs-lecturer-image_alignment.log
```

## Manual Resolution

Add appropriate CSS to images:

```html
<!-- Center a single image -->
<img src="image.png" class="mx-auto d-block">

<!-- Multiple images in a row -->
<div class="image-container">
  <img src="img1.png" class="img-fluid">
  <img src="img2.png" class="img-fluid">
</div>
```
