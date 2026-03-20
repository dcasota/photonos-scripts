# Task 003 — Import Pipeline

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 2 — Existing Tool Formalization |
| **Dependencies** | 002 |
| **PRD Refs** | PRD §6 (Import Pipeline), §3 (Data Layer) |

## Description

Formalize `importer.py` into a robust data-ingestion pipeline. Replace
print-based output with Python's `logging` module, add structured error
handling for network and git failures, and integrate `tqdm` for progress
reporting during long-running imports.

## Acceptance Criteria

- [ ] `importer.py` uses `logging` module with configurable log level (--verbose / --quiet)
- [ ] All network calls wrapped in retry logic (3 retries, exponential backoff)
- [ ] Git subprocess errors caught and logged with context (repo, branch, command)
- [ ] `tqdm` progress bar shown for commit iteration and page fetching
- [ ] Graceful degradation: partial imports saved on Ctrl-C (SIGINT handler)
- [ ] `--dry-run` flag prints actions without writing to DB
- [ ] Unit tests for error handling paths (mocked network failures)

## Implementation Notes

- Use `logging.getLogger("docsystem.importer")` for namespaced logging.
- Retry decorator can use `tenacity` or a simple hand-rolled wrapper.
- `tqdm` should be wired to stderr so stdout remains clean for piping.
- SIGINT handler should commit the current transaction before exiting.
