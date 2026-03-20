# ADR-0004: Broadcom KB 326316 as Authoritative vCenter Release Source

**Date:** 2026-03-21

**Status:** Accepted

## Context

The vCenter CVE drift analyzer tracks security patching drift for VMware vCenter
Server releases by mapping each release to Photon OS security advisories. Currently,
the analyzer only covers releases for which a Photon OS security patch wiki table
exists on the VMware wiki. This creates a coverage problem:

- **Incomplete tracking:** If a vCenter release has no corresponding Photon advisory
  wiki page, it is invisible to the drift analyzer.
- **No authoritative release list:** There is no single, maintained inventory of all
  vCenter 7.0, 8.0, and 9.0 releases in the analyzer's data sources.
- **Gap detection is manual:** Identifying which releases are missing from coverage
  requires a human to cross-reference multiple sources.

The drift analyzer needs a canonical, machine-readable source of all vCenter releases
across all major versions (7.0, 8.0, 9.0) to enable automated gap detection.

## Decision

Use **Broadcom Knowledge Base article 326316** ("VMware vCenter Server versions and
build numbers") as the single authoritative source for vCenter release inventory.

This KB article provides a structured HTML table for each major version containing:

| Field          | Example                    |
|----------------|----------------------------|
| Release name   | vCenter Server 8.0 Update 3d |
| Version number | 8.0.3.00400               |
| Release date   | 2025-02-25                |
| Build number   | 24322831                  |

The analyzer fetches this page, parses the HTML tables, and builds a complete release
inventory. This inventory is then compared against the set of releases for which
Photon advisory wiki pages exist, producing a coverage gap report.

## Alternatives Considered

### Alternative 1: Broadcom Techdocs TOC Pages

Use the Broadcom technical documentation table-of-contents pages that list release
notes for each vCenter major version.

- **Rejected because:** These pages only list links to individual release note
  documents. Extracting release dates and version numbers requires scraping each
  linked page individually — potentially 40+ HTTP requests. The TOC structure
  is less stable than the KB article and has changed format multiple times.

### Alternative 2: VMware Lifecycle Matrix

Use the VMware Product Lifecycle Matrix to enumerate supported releases.

- **Rejected because:** The lifecycle matrix only tracks major version milestones
  (General Availability, End of General Support, End of Technical Guidance). It
  does not list individual patch releases (e.g., 8.0 Update 3a, 3b, 3c, 3d).
  Patch-level granularity is essential for CVE drift analysis.

### Alternative 3: Manual Maintenance

Maintain a hand-curated JSON or YAML file listing all vCenter releases.

- **Rejected because:** There are 40+ releases across three major versions, with
  new releases added quarterly. Manual updates are error-prone and create a
  maintenance burden. Every missed release silently degrades drift analysis
  coverage. Automated fetching from a canonical source eliminates this risk.

## Consequences

- **Single HTTP fetch:** One request to KB 326316 provides the complete release
  inventory across all major versions. No pagination or multi-page scraping.
- **Machine-parseable format:** The KB article uses consistent HTML table markup
  that can be parsed with standard libraries (BeautifulSoup, lxml).
- **Automated gap detection:** By comparing the KB 326316 release list against
  Photon advisory wiki pages, the analyzer can automatically identify coverage
  gaps. Initial analysis found that only 12 of 40+ releases are currently tracked.
- **External dependency:** The analyzer depends on Broadcom maintaining KB 326316.
  If the article is moved or restructured, the parser will need updating. The
  article has been stable since its original publication and is widely referenced.
- **Cache-friendly:** The release inventory changes infrequently (quarterly at
  most). Results can be cached locally to avoid redundant fetches during
  development and testing.
- **Coverage visibility:** Gap reports make it immediately clear which vCenter
  releases lack Photon security advisory analysis, enabling prioritized backfill.
