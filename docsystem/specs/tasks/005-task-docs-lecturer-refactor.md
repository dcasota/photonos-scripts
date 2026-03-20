# Task 005 — Docs Lecturer Refactor

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 2 — Existing Tool Formalization |
| **Dependencies** | 001 |
| **PRD Refs** | PRD §9 (Docs Lecturer), §2 (Project Structure) |

## Description

Relocate `photonos-docs-lecturer` from its current `tools/` location into the
`src/docsystem/` package hierarchy. Refactor its plugin loading mechanism to
use Python entry points, making plugins discoverable and independently
testable.

## Acceptance Criteria

- [ ] `photonos-docs-lecturer` code moved to `src/docsystem/lecturer/`
- [ ] Plugin interface defined as an abstract base class (`BasePlugin`)
- [ ] Plugins registered via `[project.entry-points."docsystem.lecturer.plugins"]` in pyproject.toml
- [ ] Plugin discovery uses `importlib.metadata.entry_points()` at runtime
- [ ] Existing plugins refactored to implement `BasePlugin` interface
- [ ] CLI entry point preserved: `docsystem-lecturer` command works after install
- [ ] Unit tests for each plugin in isolation (mocked dependencies)
- [ ] Integration test: full lecturer run with all plugins enabled

## Implementation Notes

- Entry points allow third-party plugins in the future.
- `BasePlugin` should define: `name`, `description`, `run(context) -> Result`.
- Keep backward compatibility: old import paths should emit deprecation warnings.
- Test fixtures should provide a minimal `context` object for plugin testing.
