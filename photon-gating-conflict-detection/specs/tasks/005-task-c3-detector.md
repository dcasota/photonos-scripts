# Task 005: C3 and C3+ Constellation Detectors

**Dependencies**: Task 004
**Complexity**: High
**Status**: Complete

---

## Description

Implement detection for C3 (subrelease boundary mismatch) and C3+ (tdnf upgrade conflict when snapshot is bypassed).

## Requirements

### C3 (Boundary)

- Flag branches where `uses_snapshot=true` and specs have threshold exactly at subrelease
- Severity: HIGH

### C3+ (Upgrade Conflict)

- When `mainline == subrelease` (snapshot bypassed):
  - Find gated spec pairs where old is active and versions differ
  - Find all ungated specs that depend on the gated package
  - Each such ungated spec is CRITICAL (tdnf upgrade will pull new version)

## Acceptance Criteria

- [ ] Detects 86 C3 CRITICAL findings for branch 5.0 with mainline=91
- [ ] Root-cause packages identified: Linux-PAM (32), dbus (21), libcap (18), gawk (11), docker (3), containerd (1)
- [ ] systemd flagged as CRITICAL for both Linux-PAM and libcap dependencies
- [ ] No findings for 6.0 (subrelease=92, mainline=92 -- no gated pairs in SPECS/)
- [ ] No findings for 4.0 (no build_if gating)

## Implementation

Functions: `detect_c3_snapshot_boundary()`, `detect_c3_upgrade_conflict()`, `detect_ungated_deps_on_gated_packages()`

## Validation

Run against local build tree and verify systemd is flagged:
```
[C3] CRITICAL: systemd (5.0)
  remote repo contains Linux-PAM-1.7.2 (newer than locally-built Linux-PAM-1.5.3)
```
