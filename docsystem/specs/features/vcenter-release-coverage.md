# Feature Requirement Document (FRD): vCenter Release Coverage

**Feature ID**: FRD-005
**Feature Name**: vCenter Release Coverage Tracking
**Related PRD Requirements**: REQ-8
**Status**: Draft
**Last Updated**: 2026-03-21

---

## 1. Feature Overview

### Purpose

Correlate Broadcom KB article 326316 (vCenter Server build numbers and release dates) with Photon OS advisory wiki pages to identify which vCenter releases have security patch data and which represent coverage gaps in the drift analyzer.

### Value Proposition

Quantifies the gap between published vCenter releases and those tracked by the vCenter-CVE-drift-analyzer, enabling prioritized backfill of missing release data for comprehensive security posture reporting.

### Success Criteria

- All vCenter releases from KB 326316 are catalogued with build numbers and dates
- Coverage status determined for each release (tracked vs. missing)
- Coverage gap report identifies all missing releases by version train
- Yearly release count table matches known data

---

## 2. Functional Requirements

### 2.1 Data Source Ingestion

**Description**: Parse Broadcom KB article 326316 to extract all vCenter Server releases with build numbers and release dates.

**Acceptance Criteria**:
- Extracts releases for vCenter 7.0, 8.0, and 9.0 trains
- Each release record includes: version label, build number, release date
- Data refreshable on demand from the KB article

### 2.2 Photon Advisory Correlation

**Description**: Cross-reference extracted vCenter releases with Photon OS advisory wiki pages to determine which releases have corresponding security patch tables.

**Acceptance Criteria**:
- Matches vCenter release versions to Photon advisory page entries
- Identifies releases with full patch data vs. those with no advisory coverage
- Current coverage: 10 of 24 vCenter 8.0 releases tracked, 2 of 3 vCenter 9.0 releases

### 2.3 Coverage Gap Report

**Description**: Generate a report listing all vCenter releases and their coverage status.

**Missing vCenter 8.0 Releases** (not currently tracked):
- 8.0a, 8.0c, 8.0U1, 8.0U1a, 8.0U1b, 8.0U1d, 8.0U1e
- 8.0U2, 8.0U2a, 8.0U2c, 8.0U2d, 8.0U2e
- 8.0U3, 8.0U3a, 8.0U3c, 8.0U3d

**Missing vCenter 9.0 Releases**:
- 9.0.0.0

**Acceptance Criteria**:
- Report lists each missing release with version, build number, and release date
- Report groups missing releases by update train (8.0, 8.0U1, 8.0U2, 8.0U3, 9.0)
- Summary shows tracked vs. total count per version

### 2.4 Yearly Release Count Table

**Description**: Generate a summary table showing vCenter release counts per year and version train.

**Reference Data**:

| Year | vCenter 7.0 | vCenter 8.0 | vCenter 9.0 | Total |
|------|-------------|-------------|-------------|-------|
| 2023 | 6 | 9 | -- | 15 |
| 2024 | 4 | 10 | -- | 14 |
| 2025 | 3 | 3 | 2 | 8 |

**Acceptance Criteria**:
- Table generated dynamically from ingested KB data
- Matches reference counts above
- Includes totals per year and per version train

---

## 3. Edge Cases

- **KB article format changes**: Log warning if expected HTML structure is not found; fall back to cached data
- **New vCenter version train (e.g., 9.5)**: Schema supports arbitrary version strings
- **Release with no build number**: Store with NULL build number; flag in report
- **Advisory page restructured**: Correlation logic handles both old and new wiki page formats

---

## 4. Dependencies

### Depends On
- Broadcom KB article 326316 (external data source)
- Photon OS advisory wiki pages (external data source)
- vCenter-CVE-drift-analyzer database (for current coverage status)

### Depended On By
- Swarm Orchestration (FRD-004) — Coverage report informs maintenance priorities
