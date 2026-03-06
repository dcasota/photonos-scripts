# Task 006: C4, C5, and C6 Constellation Detectors

**Dependencies**: Task 001
**Complexity**: Medium
**Status**: Complete

---

## Description

Implement detection for C4 (cross-branch contamination), C5 (FIPS canister coupling), and C6 (snapshot URL availability).

## Requirements

### C4

- Compare common/ gated spec activation across branch pairs with different subreleases
- Severity: WARNING

### C5

- Scan active kernel specs for `fips` + `canister` in BuildRequires
- Severity: WARNING

### C6

- Construct snapshot URL from template + branch config
- HTTP HEAD probe (with `--check-urls` flag)
- Probe nearby snapshots on 404
- Severity: BLOCKING (404), HIGH (other errors), WARNING (URL not checked)

## Acceptance Criteria

- [ ] C4: Detects 5.0+6.0 Intel driver spec divergence at thresholds 91 and 92
- [ ] C5: Detects linux and linux-esx FIPS canister deps in 6.0
- [ ] C6: Correctly skips 5.0 and 6.0 (mainline == subrelease, snapshot bypassed)
- [ ] C6 with --check-urls: Probes Broadcom Artifactory successfully

## Implementation

Functions: `detect_c4_cross_branch()`, `detect_c5_fips_canister()`, `detect_c6_snapshot_url()`
