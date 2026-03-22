# Feature: PRN Import Pipeline

**PRD refs**: REQ-01, REQ-02, REQ-03, REQ-04, REQ-15
**Status**: Approved

## Description

Import `photonos-urlhealth-<branch>_<YYYYMMDDHHmm>.prn` files into SQLite, handling multiple encodings and schema versions, with deduplication and integrity hashing.

## Functional Requirements

1. **Filename parsing**: Extract `branch` and `scan_datetime` from filename pattern `photonos-urlhealth-<branch>_<datetime>.prn`. Branches: 3.0, 4.0, 5.0, 6.0, common, master, dev.
2. **Deduplication**: Before importing, check if `filename` (basename only) already exists in `scan_files` table. If so, skip.
3. **Encoding auto-detect**: Check first 2 bytes for UTF-16LE BOM (FF FE). If present, convert entire buffer to UTF-8 in-memory. Otherwise assume UTF-8 (skip UTF-8 BOM EF BB BF if present).
4. **Schema detection**: Count commas in header row. >=10 commas = 12-column (new). <10 = 5-column (old). Old schema maps to: Spec, Source0_original, Modified_Source0, UrlHealth, UpdateAvailable. New adds: UpdateURL, HealthUpdateURL, Name, SHAName, UpdateDownloadName, warning, ArchivationDate.
5. **Integrity**: Compute SHA-256 of raw file bytes, store in `scan_files.file_sha256`.
6. **Transaction**: All package rows for one file inserted in a single SQLite transaction (all-or-nothing).
7. **Empty files**: Skip files with 0 bytes (several exist in the scan archive).

## Acceptance Criteria

- All 178 existing .prn files process without crash
- UTF-16LE files from 2023 import correctly (verified by row count)
- Duplicate re-import returns skip status, no new rows
- SHA-256 stored matches `sha256sum` on the original file

## Edge Cases

- Files with only a header row (no data rows) — import with 0 packages
- Files with commas inside quoted CSV fields
- Files with trailing whitespace or \r\n line endings
