# Backtick Errors Plugin

**Version:** 2.0.0  
**FIX_ID:** 8  
**Requires LLM:** No

## Description

Fixes spaces inside inline code backticks.

## Issues Detected

1. **Space after opening backtick** - `` ` code` `` should be `` `code` ``
2. **Space before closing backtick** - `` `code ` `` should be `` `code` ``
3. **Spaces on both sides** - `` ` code ` `` should be `` `code` ``

## Code Block Protection

This plugin uses `protect_code_blocks()` to ensure fenced code blocks are never modified.

## Example Fixes

**Before:**
```
Run the ` docker ps ` command.
The ` kubectl` tool is required.
```

**After:**
```
Run the `docker ps` command.
The `kubectl` tool is required.
```

## Configuration

No configuration required.
