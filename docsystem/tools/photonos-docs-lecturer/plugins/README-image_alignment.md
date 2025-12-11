# Image Alignment Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects improperly aligned or positioned images.

## Issues Detected

1. **Deprecated align attribute** - `<img align="left">` should use CSS
2. **Float without clear** - Floating images may break layout

## Why Detection Only

Image alignment is often intentional and context-dependent.
Automatic fixes could break carefully designed layouts.

## Example Issues

```html
<img src="logo.png" align="right">
```

Should be:
```html
<img src="logo.png" style="float: right;">
```

## Configuration

No configuration required.
