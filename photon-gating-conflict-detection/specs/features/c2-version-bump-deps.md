# Feature Requirement Document: C2 -- Version Bump with New Dependencies

**Feature ID**: FRD-C2
**Related PRD Requirements**: REQ-2, REQ-8, REQ-9, REQ-10
**Status**: Implemented
**Last Updated**: 2026-03-06

---

## 1. Feature Overview

Detect when a gated spec pair's new version adds Requires or BuildRequires on packages produced by other inactive gated specs.

### Success Criteria

- Detects rpm (new) adding `libcap-libs` dependency from inactive libcap (>= 92) spec
- Detects pgbackrest/python3-psycopg2/apr-util adding `postgresql18-devel` dependency
- Only flags when the dependency provider is also gated and inactive

---

## 2. Functional Requirements

### 2.1 Dependency Diff

Compare Requires and BuildRequires between old and new gated spec variants. Identify added dependencies.

### 2.2 Cross-Gating Check

For each added dependency, check if the providing spec is also gated and inactive at the branch's subrelease.

### 2.3 Severity Classification

| Condition | Severity |
|-----------|----------|
| Added dep provided by inactive gated spec | HIGH |
| Added dep provided by active or ungated spec | Not flagged |

---

## 3. Reference Findings

From scan 2026-03-06, branch 5.0, subrelease 91:

- `rpm` new version adds `libcap-libs` from `libcap` (gated >= 92, inactive) -- HIGH
- `pgbackrest` adds `postgresql18-devel` from `postgresql18` (gated >= 92) -- HIGH
- `python3-psycopg2` adds `postgresql18-devel` from `postgresql18` (gated >= 92) -- HIGH
- `apr-util` adds `postgresql18-devel` from `postgresql18` (gated >= 92) -- HIGH

---

## 4. Dependencies

**Depends On**: REQ-7 (inventory), C1 spec pair identification

**Depended On By**: C3 (boundary mismatch)
