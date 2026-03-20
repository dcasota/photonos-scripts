# Feature Requirement Document (FRD): Commit Import Pipeline

**Feature ID**: FRD-001
**Feature Name**: Commit Import Pipeline
**Related PRD Requirements**: REQ-1
**Status**: Draft
**Last Updated**: 2026-03-21

---

## 1. Feature Overview

### Purpose

Import git commit history from the vmware/photon repository into a local SQLite database across all 6 active branches, enabling downstream analysis and blog generation.

### Value Proposition

Centralizes commit data from a multi-branch repository into a queryable store, providing the foundation for changelog generation, contributor tracking, and release analysis.

### Success Criteria

- All 6 branches (3.0, 4.0, 5.0, 6.0, common, master) imported successfully
- Commits from 2021-01-01 to present are captured
- Incremental updates append only new commits without duplicates
- JSON output reports per-branch commit counts

---

## 2. Functional Requirements

### 2.1 Branch Enumeration

**Description**: Iterate over the 6 target branches in the vmware/photon repository: 3.0, 4.0, 5.0, 6.0, common, and master.

**Acceptance Criteria**:
- All 6 branches are processed in each run
- Missing or inaccessible branches are logged as warnings without aborting

### 2.2 SQLite Storage

**Description**: Store imported commits in a `commits` table with full metadata.

**Schema**:

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `branch` | TEXT | Yes | Branch name (3.0, 4.0, 5.0, 6.0, common, master) |
| `commit_hash` | TEXT | Yes | Full SHA-1 hash (primary key with branch) |
| `change_id` | TEXT | No | Gerrit Change-Id if present in commit message |
| `message` | TEXT | Yes | Full commit message |
| `commit_datetime` | TEXT | Yes | ISO-8601 commit timestamp |
| `signed_off_by` | TEXT | No | Signed-off-by trailer value |
| `reviewed_on` | TEXT | No | Reviewed-on URL from Gerrit |
| `reviewed_by` | TEXT | No | Reviewed-by trailer value |
| `tested_by` | TEXT | No | Tested-by trailer value |
| `content` | TEXT | No | Diff content or patch body |

**Acceptance Criteria**:
- Composite primary key on (branch, commit_hash) prevents duplicates
- All trailer fields parsed from commit message body

### 2.3 Incremental Updates

**Description**: On subsequent runs, import only commits newer than the latest stored commit per branch.

**Acceptance Criteria**:
- Queries `MAX(commit_datetime)` per branch to determine the starting point
- First run imports full history back to 2021-01-01
- No duplicate rows created on repeated runs

### 2.4 Check Mode

**Description**: `--check` flag performs a dry run that reports how many new commits would be imported without writing to the database.

**Acceptance Criteria**:
- No database writes occur in check mode
- Output includes per-branch new commit counts

### 2.5 Date Filtering

**Description**: `--since-date YYYY-MM-DD` flag limits import to commits on or after the specified date.

**Acceptance Criteria**:
- Overrides the default 2021-01-01 start date
- Works in combination with incremental mode (uses the later of stored max date and --since-date)

### 2.6 JSON Output

**Description**: Upon completion, emit a JSON summary with per-branch commit counts.

**Acceptance Criteria**:
- JSON includes: `{ "branches": { "<name>": { "new": N, "total": M } }, "run_date": "..." }`
- Written to stdout or a specified output file

---

## 3. Edge Cases

- **Empty branch**: Branch exists but has no commits in range — report 0, do not error
- **Force-pushed history**: Detect commits that disappeared; log warning but do not delete stored data
- **Network failure mid-import**: Transaction rollback ensures partial branch data is not persisted
- **Corrupt commit message**: Store raw message; trailer parsing failures logged as warnings

---

## 4. Dependencies

### Depends On
- vmware/photon repository (remote git access)
- SQLite3

### Depended On By
- Blog Generation Pipeline (FRD-002)
