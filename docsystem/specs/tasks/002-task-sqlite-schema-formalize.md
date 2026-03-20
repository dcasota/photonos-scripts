# Task 002 — SQLite Schema Formalize

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 1 — Core Infrastructure |
| **Dependencies** | 001 |
| **PRD Refs** | PRD §3 (Data Layer), §4 (Schema Management) |

## Description

The shared SQLite database (`photon_commits.db`) currently has an implicit
schema spread across importer.py and summarizer.py. Extract this into a
dedicated `db_schema.py` module that owns table definitions, adds a
`schema_version` metadata table, and validates the schema on every open.

## Acceptance Criteria

- [ ] `src/docsystem/db_schema.py` module created with all CREATE TABLE statements
- [ ] `schema_version` table added (version integer, applied_at timestamp)
- [ ] Current schema tagged as version 1
- [ ] `open_db()` function validates schema version on connect and raises on mismatch
- [ ] Migration framework: ordered SQL scripts in `migrations/` directory
- [ ] `migrate_db()` applies pending migrations sequentially
- [ ] Unit tests cover: fresh DB creation, version validation, migration application
- [ ] Existing importer.py and summarizer.py refactored to use `open_db()`

## Implementation Notes

- Use `sqlite3` stdlib only — no ORM needed at this scale.
- Store migrations as `.sql` files named `NNN_description.sql` (e.g., `001_initial.sql`).
- `open_db()` should accept a `Path` argument defaulting to `photon_commits.db`.
- Consider `PRAGMA user_version` as an alternative to a metadata table for simplicity.
