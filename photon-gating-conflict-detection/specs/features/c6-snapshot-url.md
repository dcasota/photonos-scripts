# Feature Requirement Document: C6 -- Snapshot URL Availability

**Feature ID**: FRD-C6
**Related PRD Requirements**: REQ-6, REQ-8, REQ-9
**Status**: Implemented
**Last Updated**: 2026-03-06

---

## 1. Feature Overview

Validate that snapshot files referenced in `build-config.json` are actually available on Broadcom Artifactory via HTTP HEAD requests.

### Success Criteria

- Detects HTTP 404 for unavailable snapshots (e.g., snapshot-100)
- Probes nearby snapshot numbers and reports available alternatives
- Correctly skips branches where snapshot is bypassed (mainline == subrelease)

---

## 2. Functional Requirements

### 2.1 URL Construction

Expand the `package-repo-snapshot-file-url` template from `common/build-config.json` with each branch's release version, architecture, and subrelease.

### 2.2 HTTP Probe

Send HEAD request to the constructed URL. If 404, probe `subrelease - 5` through `subrelease + 5`.

### 2.3 Severity Classification

| HTTP Status | Severity |
|-------------|----------|
| 404 | BLOCKING (build cannot start) |
| Other non-200 | HIGH |
| Connection error | HIGH |
| 200 | No finding |
| Snapshot bypassed | No finding |

### 2.4 Bypass Detection

If `photon-mainline == photon-subrelease`, the build system skips the snapshot entirely. No C6 finding is emitted.

---

## 3. Edge Cases

- **No `--check-urls` flag**: Agent emits WARNING noting URL was not validated
- **Network unreachable**: Agent emits HIGH with connection error details
- **Template variables**: Agent must substitute `$releasever`, `$basearch`, `SUBRELEASE` correctly

---

## 4. Dependencies

**Depends On**: REQ-7 (inventory), `requests` library, network access to `packages.broadcom.com`
