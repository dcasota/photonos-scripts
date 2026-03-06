# Feature Requirement Document: C5 -- FIPS Canister Version Coupling

**Feature ID**: FRD-C5
**Related PRD Requirements**: REQ-5, REQ-8, REQ-9
**Status**: Implemented
**Last Updated**: 2026-03-06

---

## 1. Feature Overview

Detect kernel specs with FIPS canister BuildRequires and verify that the canister RPM version matches the kernel version it will be linked into.

### Success Criteria

- Identifies `linux` and `linux-esx` kernel specs with `linux-fips-canister` dependency
- Flags for manual verification of canister RPM availability

---

## 2. Functional Requirements

### 2.1 FIPS Dependency Scan

For each active kernel spec, check BuildRequires for `fips` + `canister` pattern.

### 2.2 Severity

WARNING -- requires manual verification against base repo RPM availability.

---

## 3. Reference Findings

From scan 2026-03-06, branch 6.0:

- `linux` (common/SPECS/linux/v6.12/linux.spec): BuildRequires `linux-fips-canister`
- `linux-esx` (common/SPECS/linux/v6.12/linux-esx.spec): BuildRequires `linux-fips-canister`

---

## 4. Dependencies

**Depends On**: REQ-7 (inventory), kernel spec parsing

**Enhancement**: Future versions could probe the base repo for the exact canister RPM version.
