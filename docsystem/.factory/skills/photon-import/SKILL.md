---
name: photon-import
description: >
  Clone or update the vmware/photon repository and import commit history
  for all branches (3.0, 4.0, 5.0, 6.0, common, master) into a local
  SQLite database (photon_commits.db). Use this skill when the blogger
  droid needs fresh commit data, when the database is missing or stale,
  or when the user requests a data refresh.
---

# Photon OS Commit Importer

## Purpose

Populate or update the `photon_commits.db` SQLite database with commit
history from `https://github.com/vmware/photon`. This database is the
data source for the `photon-summarize` skill.

## Prerequisites

- `git` available on PATH
- Python 3.9+ with `sqlite3` (stdlib) and `tqdm` (auto-installed)
- Network access to github.com (for initial clone / fetch)

## Instructions

### 1. Check current database status

```bash
python3 "$FACTORY_PROJECT_DIR/.factory/skills/photon-import/importer.py" \
  --db-path "$FACTORY_PROJECT_DIR/photon_commits.db" \
  --check
```

Review the JSON output. If `exists` is `false` or any branch `count` is 0,
proceed to step 2.

### 2. Run the import

```bash
python3 "$FACTORY_PROJECT_DIR/.factory/skills/photon-import/importer.py" \
  --db-path "$FACTORY_PROJECT_DIR/photon_commits.db" \
  --repo-dir "$FACTORY_PROJECT_DIR/photon" \
  --branches 3.0 4.0 5.0 6.0 common master \
  --since-date "2021-01-01"
```

The script prints progress to stderr and outputs a JSON summary to stdout
with the number of new commits per branch.

### 3. Verify

Confirm the JSON output shows `total_new >= 0` and no errors. If
`total_new` is 0 on a fresh run, investigate network or git issues.

## Arguments Reference

| Flag | Default | Description |
|------|---------|-------------|
| `--db-path` | `photon_commits.db` | Path to the SQLite database |
| `--repo-dir` | `photon` | Path to the local git clone |
| `--branches` | all 6 branches | Space-separated branch list |
| `--since-date` | none (all history) | Only import commits after this date |
| `--check` | off | Report DB status without importing |

## Database Schema

The importer creates the full database schema (shared with `summarizer.py`
via `db_schema.py`), including both the `commits` and `summaries` tables.
This means either script can run first on a fresh database.

## Output

JSON object to stdout. The `--check` mode also reports summaries status:
```json
{
  "branches": {
    "3.0": {"commits": 1500, "latest": "2025-01-15T..."},
    "5.0": {"commits": 800, "latest": "2025-01-20T..."}
  },
  "summaries": {
    "3.0": {"count": 12},
    "5.0": {"count": 8}
  },
  "total_new": 52
}
```
