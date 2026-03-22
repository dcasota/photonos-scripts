# Feature: SQLite Schema

**PRD refs**: REQ-01, REQ-10
**Status**: Approved

## Description

Define the SQLite database schema for storing scan metadata and package rows, optimized for the report queries.

## Schema

```sql
CREATE TABLE scan_files (
    id              INTEGER PRIMARY KEY,
    filename        TEXT UNIQUE NOT NULL,
    branch          TEXT NOT NULL,
    scan_datetime   TEXT NOT NULL,
    file_sha256     TEXT NOT NULL,
    schema_version  INTEGER NOT NULL,
    imported_at     TEXT DEFAULT (datetime('now'))
);

CREATE TABLE packages (
    id                   INTEGER PRIMARY KEY,
    scan_file_id         INTEGER NOT NULL REFERENCES scan_files(id),
    spec                 TEXT,
    source0_original     TEXT,
    modified_source0     TEXT,
    url_health           TEXT,
    update_available     TEXT,
    update_url           TEXT,
    health_update_url    TEXT,
    name                 TEXT,
    sha_name             TEXT,
    update_download_name TEXT,
    warning              TEXT,
    archivation_date     TEXT
);

CREATE INDEX idx_packages_scan ON packages(scan_file_id);
CREATE INDEX idx_packages_name ON packages(name);
CREATE INDEX idx_scan_files_branch ON scan_files(branch);
```

## Design Decisions

- `filename` is UNIQUE — this is the dedup key
- `scan_datetime` stored as text in `YYYYMMDDHHmm` format (sortable)
- `schema_version` records whether the source was 5-col or 12-col
- All package fields are TEXT (no numeric conversion) to preserve original data faithfully
- PRAGMAs: `journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`
