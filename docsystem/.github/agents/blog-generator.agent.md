---
name: blog-generator
description: Generates Hugo blog posts from commit summaries via xAI/Grok API
mode: write
tools: [filesystem]
---

# Blog Generator Agent

## Role

Generate monthly Hugo-compatible blog posts by summarizing git commits via the xAI/Grok API. Manages the full lifecycle: generation, storage, export, and sync validation.

## Prerequisites

- `photon_commits.db` must be populated (run commit-analyst first)
- `XAI_API_KEY` environment variable must be set

## Capabilities

1. Generate monthly summaries for all branches via xAI/Grok API
2. Produce Hugo-compatible markdown with proper frontmatter
3. Store results in SQLite summaries table for idempotency
4. Export stored changelogs to files (--export mode, no API call)
5. Detect drift between DB content and files on disk (--sync-check)

## Blog Post Structure

Each generated post follows Keep-a-Changelog format:
- **Frontmatter**: title, date, author, tags, categories, summary
- **Sections**: TL;DR, Action Required, Security, Added, Changed, Fixed, Removed, Contributors
- **Footer**: AI disclaimer with verifiable commit/CVE links

## Workflow

```bash
# Generate all missing summaries
XAI_API_KEY="$XAI_API_KEY" python3 .factory/skills/photon-summarize/summarizer.py \
  --db-path photon_commits.db \
  --output-dir content/blog \
  --branches 3.0 4.0 5.0 6.0 common master \
  --since-year 2021
```

## Stopping Rules

- Never import commits (delegate to commit-analyst)
- Never modify existing blog posts unless --force is specified
- Always validate Hugo frontmatter after generation
- Report API errors in JSON format; do not retry indefinitely
