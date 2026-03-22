# Feature: Report Generation

**PRD refs**: REQ-05, REQ-06, REQ-07, REQ-08, REQ-09
**Status**: Approved

## Description

Generate four report sections from the SQLite database, to be rendered as a Word .docx.

## Section 1 — Timeline Chart

**Query logic**: For each `(branch, scan_datetime)`, count packages where:
- `url_health = '200'`
- `update_available` is not empty, not `(same version)`, not `pinned`
- `update_download_name` is non-empty and matches pattern `<name>-<version>.tar.*`

**Visualization**: Line chart with X = scan_datetime (chronological), Y = qualifying count. One dotted series per branch (3.0, 4.0, 5.0, 6.0, common, master, dev).

## Section 2 — Top 10 Most-Changed 5.0 Packages (2023–current)

**Query logic**: For branch 5.0, compare `update_available` between consecutive scans (ordered by `scan_datetime`). Count how many times it changed per package. Group changes by year (2023, 2024, 2025, 2026).

**Output**: Table with columns: Package | 2023 | 2024 | 2025 | 2026 | Total. Top 10 by total.

## Section 3 — Least-Changed Packages (all branches, 2023–current)

Same change-detection logic but across all branches.

**Exclusions**:
- `warning` contains "VMware internal"
- `source0_original` contains `vmware.com`, `broadcom.com`, `packages.vmware.com`, `packages.broadcom.com`
- `archivation_date` is non-empty

**Output**: Table with columns: Package | Branches | Total Changes. Sorted ascending by total, limit 50.

## Section 4 — Pie Chart: Source Categories

**Query logic**: From latest scan per branch, categorize each unique package by its source URL domain:
- `github.com`, `kernel.org`, `freedesktop.org`, `gnu.org`, `rubygems.org`, `sourceforge.net`, `*cpan.org`, `paguire.io`, `Other`

**Output**: Pie chart with labels showing category, count, and percentage.
