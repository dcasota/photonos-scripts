# Task 006 — vCenter Release Scraper

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 3 — New Capabilities |
| **Dependencies** | 001 |
| **PRD Refs** | PRD §10 (vCenter Coverage), §11 (Reporting) |

## Description

Build a scraper that extracts all vCenter Server 7.0, 8.0, and 9.0 release
records from Broadcom KB article 326316. Correlate scraped releases with
existing Photon OS advisory wiki pages to produce a coverage gap report
showing which vCenter releases have associated Photon patch tracking data
and which do not.

## Acceptance Criteria

- [ ] Scraper fetches and parses Broadcom KB 326316 for vCenter 7.0, 8.0, 9.0 releases
- [ ] Each release record includes: version, build number, release date, update name
- [ ] Correlation logic matches releases against existing Photon OS advisory wiki pages
- [ ] Coverage gap report generated as markdown table and JSON
- [ ] Report flags: currently 10 of 24 vCenter 8.0 releases tracked, 2 of 3 vCenter 9.0
- [ ] Yearly release count observations included in report output
- [ ] `--output-dir` flag for report destination
- [ ] Unit tests with cached/mocked KB page responses

## Implementation Notes

- Use `requests` + `beautifulsoup4` for scraping (already pinned in 001).
- KB 326316 structure may change; make CSS selectors configurable.
- Cache raw HTML responses locally to avoid repeated fetches during dev.
- The correlation step should be fuzzy: version strings may not match exactly.
- Yearly release counts help identify VMware's release cadence shifts.
