# Heading Hierarchy Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects heading level violations like skipped levels or incorrect first heading.

## Issues Detected

1. **Wrong first heading** - Document starts with h3 instead of h1/h2
2. **Skipped levels** - h2 followed by h4 (skipping h3)

## Why Detection Only

Heading hierarchy fixes require understanding document structure and content.
Automatic fixes could break navigation and SEO. Manual review is recommended.

## Example Issues

```markdown
### Getting Started    <- Issue: First heading is h3

## Introduction

#### Details           <- Issue: Skipped h3
```

## Configuration

No configuration required.
