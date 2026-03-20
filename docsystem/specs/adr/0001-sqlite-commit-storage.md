# ADR-0001: SQLite for Commit and Summary Storage

**Date:** 2026-03-21

**Status:** Accepted

## Context

The Photon OS documentation system needs to store approximately 50,000+ git commits
harvested from 6 major branches (1.0 through 5.0 and dev), along with generated
monthly summaries that are produced by an LLM-based summarizer. The storage solution
must satisfy these constraints:

- **Offline operation:** The tool runs on developer workstations and CI runners
  without guaranteed network access to external database servers.
- **Single-user:** Only one operator runs the importer or summarizer at a time;
  there is no concurrent multi-user access pattern.
- **No server dependency:** Installing and maintaining a database server (even
  containerized) is unacceptable overhead for a CLI documentation tool.
- **Queryable:** Both the importer and the summarizer need to query commits by
  branch, date range, and presence/absence of an existing summary.

## Decision

Use a **SQLite single-file database** (`photon_commits.db`) with two primary tables:

| Table       | Purpose                                         |
|-------------|-------------------------------------------------|
| `commits`   | Raw git commit metadata (hash, author, date, message, branch) |
| `summaries` | Generated monthly summaries (branch, year, month, markdown, model, timestamp) |

The database schema is defined in a shared module (`db_schema.py`) that both the
commit importer (`commit-importer.py`) and the blog summarizer (`blog-summarizer.py`)
import. The schema module handles table creation with `CREATE TABLE IF NOT EXISTS`,
so either tool can safely run first without manual setup.

Indexes are created on `(branch, date)` for commits and `(branch, year, month)` for
summaries to support the primary query patterns efficiently.

## Alternatives Considered

### Alternative 1: JSON Files Per Branch

Store commits as one JSON file per branch (e.g., `commits-4.0.json`).

- **Rejected because:** No query capability — filtering by date range requires
  loading and parsing the entire file. File sizes grow to 10+ MB per branch,
  making edits and diffs impractical. No transactional writes; crash during
  write corrupts the file.

### Alternative 2: PostgreSQL

Use a PostgreSQL instance (local or containerized) for full relational storage.

- **Rejected because:** Requires a running server process, which violates the
  no-server-dependency constraint. Overkill for a single-user CLI tool that
  processes data in batch. Adds Docker or system-package dependencies that
  complicate installation on minimal Photon OS build hosts.

### Alternative 3: Parquet / DuckDB

Use columnar storage (Parquet files) or DuckDB for analytical queries.

- **Rejected because:** Less portable — DuckDB binaries are not available on all
  target platforms. Parquet requires pyarrow or fastparquet, adding heavy native
  dependencies. The schema is simple (two flat tables) and does not benefit from
  columnar storage or analytical query optimizations.

## Consequences

- **Zero configuration:** SQLite requires no server, no credentials, no ports.
  The database file is created on first run.
- **Portable single file:** `photon_commits.db` can be copied, backed up, or
  committed to a data repository trivially.
- **Python stdlib support:** The `sqlite3` module ships with Python; no additional
  packages are needed for database access.
- **Shared schema module:** `db_schema.py` ensures both tools agree on the table
  structure and avoids schema drift.
- **Single-writer limitation:** SQLite supports only one concurrent writer. This
  is acceptable given the single-user design but would become a bottleneck if
  the tool were ever extended to parallel ingest.
