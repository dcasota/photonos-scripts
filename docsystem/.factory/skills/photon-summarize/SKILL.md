---
name: photon-summarize
description: >
  Generate monthly AI-powered development summaries from photon_commits.db
  for all Photon OS branches. Produces Hugo-compatible Markdown blog posts
  at content/blog/YYYY/MM/photon-[branch]-monthly-YYYY-MM.md. Requires
  XAI_API_KEY environment variable. Use this skill after photon-import has
  populated the database.
---

# Photon OS Monthly Summarizer

## Purpose

Read commit data from `photon_commits.db` and generate structured,
Hugo-compatible monthly blog posts for each branch using the xAI/Grok API.

## Prerequisites

- `photon_commits.db` must exist (run `/photon-import` first)
- `XAI_API_KEY` environment variable set with a valid xAI API key
- Python 3.9+ with `requests` and `tqdm` (auto-installed)

## Instructions

### 1. Verify the database is populated

```bash
python3 "$FACTORY_PROJECT_DIR/.factory/skills/photon-import/importer.py" \
  --db-path "$FACTORY_PROJECT_DIR/photon_commits.db" \
  --check
```

All branches should show non-zero counts.

### 2. Run the summarizer

To generate all missing summaries from 2021 onward:

```bash
XAI_API_KEY="$XAI_API_KEY" python3 \
  "$FACTORY_PROJECT_DIR/.factory/skills/photon-summarize/summarizer.py" \
  --db-path "$FACTORY_PROJECT_DIR/photon_commits.db" \
  --output-dir "$FACTORY_PROJECT_DIR/content/blog" \
  --branches 3.0 4.0 5.0 6.0 common master \
  --since-year 2021
```

To generate a specific month range:

```bash
XAI_API_KEY="$XAI_API_KEY" python3 \
  "$FACTORY_PROJECT_DIR/.factory/skills/photon-summarize/summarizer.py" \
  --db-path "$FACTORY_PROJECT_DIR/photon_commits.db" \
  --output-dir "$FACTORY_PROJECT_DIR/content/blog" \
  --months 2024-06:2024-12
```

### 3. Verify output

The script prints a JSON manifest to stdout listing all generated files,
skipped branches, and any errors:

```json
{
  "generated": [
    "content/blog/2024/06/photon-5.0-monthly-2024-06.md",
    "content/blog/2024/07/photon-5.0-monthly-2024-07.md"
  ],
  "skipped": [],
  "errors": []
}
```

Confirm `errors` is empty and all expected files appear in `generated`.

## Arguments Reference

| Flag | Default | Description |
|------|---------|-------------|
| `--db-path` | `photon_commits.db` | Path to the SQLite database |
| `--output-dir` | `content/blog` | Root output directory for blog posts |
| `--branches` | all 6 branches | Space-separated branch list |
| `--since-year` | `2021` | Start year for summaries |
| `--months` | none (all) | Optional range `YYYY-MM:YYYY-MM` |
| `--model` | `grok-4-0709` | xAI model identifier |

## Blog Post Structure

Each generated post follows the mandatory template from `blogger.md`:

- Hugo front matter: `title`, `date`, `author`, `tags`, `categories`, `summary`
- Sections: Overview, Infrastructure & Build Changes, Core System Updates,
  Security & Vulnerability Fixes, Container & Runtime Updates, Package
  Management, Network & Storage Updates, Pull Request Analysis, User
  Impact Assessment, Looking Ahead
