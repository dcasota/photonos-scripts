# Task 004 — Summarizer Pipeline

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 2 — Existing Tool Formalization |
| **Dependencies** | 002 |
| **PRD Refs** | PRD §7 (Summarizer Pipeline), §8 (Hugo Integration) |

## Description

Harden `summarizer.py` with production-grade API interaction patterns. Add
retry and rate-limit logic for the xAI API, introduce operational modes
(`--force`, `--export`, `--sync-check`), and validate Hugo frontmatter
output via a PostToolUse hook.

## Acceptance Criteria

- [ ] xAI API calls use retry with exponential backoff (429 / 5xx handling)
- [ ] Rate-limit tracking: respect `Retry-After` headers, log wait times
- [ ] `--force` mode: re-summarize all commits regardless of existing summaries
- [ ] `--export` mode: write Hugo-compatible markdown files to output directory
- [ ] `--sync-check` mode: report commits missing summaries without making API calls
- [ ] Hugo frontmatter validated (required fields: title, date, slug, tags)
- [ ] PostToolUse hook validates generated markdown before writing to disk
- [ ] Unit tests for retry logic, frontmatter validation, each CLI mode

## Implementation Notes

- xAI API rate limits are generous but bursty workloads can hit them.
- `--sync-check` is a read-only operation useful for CI validation.
- Hugo frontmatter validation can use a simple regex or YAML parser.
- Consider `click` or `argparse` subcommands for mode selection.
