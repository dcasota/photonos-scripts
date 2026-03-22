# Product Requirements Document (PRD) — package-report-database-tool

**Version**: 1.0
**Date**: 2026-03-22
**Status**: Approved
**Author**: PM Agent (SDD pipeline)

## Overview

The package-report-database-tool is a C command-line tool that imports PhotonOS URL health scan files (`.prn`) into a local SQLite database — deduplicating on filename — and generates a Word `.docx` report with embedded OOXML charts analysing package health, update velocity, and source-category distribution across Photon OS branches 3.0, 4.0, 5.0, 6.0, common, master, and dev.

The tool is the first concrete deliverable of the migration path described in `SPEC_Migration_to_C.md`.

## Context

The existing `photonos-package-report.ps1` PowerShell script (v0.64, ~5,300 lines) runs weekly via GitHub Actions (`package-report.yml`). Each run produces per-branch `photonos-urlhealth-<branch>_<datetime>.prn` files stored in `scans/`. Over 178 `.prn` files exist spanning 2023-02 to 2026-03. No structured database or trend analysis exists today.

## Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-01 | Accept `--db <path>` parameter for a local SQLite database file (create if absent) | Critical |
| REQ-02 | Accept `--import <dir>` to import all `photonos-urlhealth-*.prn` files from a directory | Critical |
| REQ-03 | Skip duplicate imports: if a filename already exists in the DB, skip it | Critical |
| REQ-04 | Auto-detect file encoding: UTF-16LE (BOM FF FE) vs UTF-8, and column schema: 5-column (2023) vs 12-column (2026+) | Critical |
| REQ-05 | Accept `--report <output.docx>` to generate a Word document report | Critical |
| REQ-06 | Report Section 1: Timeline line chart — Y-axis = count of packages with UrlHealth=200 AND UpdateAvailable is a version AND UpdateDownloadName matches `name-version.tar.*`; X-axis = scan datetime; one dotted series per branch | Critical |
| REQ-07 | Report Section 2: Top 10 most-changed 5.0 packages from 2023-current, each year shown separately | Critical |
| REQ-08 | Report Section 3: List of packages with lowest changes from 2023-current across all branches, excluding VMware-internal packages (warning contains "VMware internal" or Source0 URL contains vmware.com/broadcom.com) and archived packages (non-empty ArchivationDate) | Critical |
| REQ-09 | Report Section 4: Pie chart categorizing packages by source domain — github.com, kernel.org, freedesktop.org, gnu.org, rubygems.org, sourceforge.net, *cpan.org, paguire.io, Other — with count and percentage | Critical |
| REQ-10 | All SQL queries must use parameterized statements (sqlite3_bind_*), never string concatenation | Critical |
| REQ-11 | Path traversal prevention: validate all paths with realpath(), reject `..` in filenames | Critical |
| REQ-12 | Buffer overflow prevention: no sprintf/gets/strcpy; use snprintf only; fixed-size buffers with explicit length checks | Critical |
| REQ-13 | Reject files >50 MB, max 10,000 files per import, max 100,000 rows per file | High |
| REQ-14 | Compile with hardening flags: -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pie -fPIE | High |
| REQ-15 | Compute SHA-256 of each file for integrity tracking | High |
| REQ-16 | Use only SQLite3 and zlib as external dependencies (both pre-installed on Photon OS) | High |

## Success Criteria

| ID | Criterion |
|----|-----------|
| SC-1 | All 178 existing .prn files import without error, duplicates correctly skipped |
| SC-2 | Generated .docx opens in Microsoft Word and LibreOffice with all 4 report sections |
| SC-3 | Timeline chart shows 7 branch series across all scan dates |
| SC-4 | Zero compiler warnings with -Wall -Wextra -Werror |
| SC-5 | No memory leaks detected by valgrind on a full import+report cycle |
| SC-6 | All unit tests pass |

## Scope Exclusions

- Does not perform live URL health checks (that is the PowerShell script's job)
- Does not modify the .prn scan files
- Does not replace or integrate into the GitHub Actions workflow (runs standalone)
