# Feature Requirement Document: C3 -- Subrelease Threshold Boundary Mismatch

**Feature ID**: FRD-C3
**Related PRD Requirements**: REQ-3, REQ-8, REQ-9, REQ-10
**Status**: Implemented
**Last Updated**: 2026-03-06

---

## 1. Feature Overview

Detect two distinct failure modes at the subrelease boundary:

1. **Snapshot staleness**: Branch uses a snapshot whose number matches the gating threshold, but the snapshot was captured before the gating commit landed.
2. **Upgrade conflict (C3+)**: When snapshot is bypassed via `photon-mainline`, the remote repo contains newer gated packages. The build system's `tdnf upgrade` step pulls these newer versions, then locally-built packages pinning old versions fail dependency resolution.

### Value Proposition

This is the highest-impact constellation by volume. The C3+ pattern alone affected 86 packages in the 5.0 branch scan, including critical infrastructure packages (systemd, openssh, sudo, shadow).

### Success Criteria

- Detects snapshot boundary risk when `uses_snapshot=true` and specs have threshold == subrelease
- Detects the `tdnf upgrade` conflict for all ungated specs depending on gated packages
- Identifies the 6 root-cause gated packages: Linux-PAM (32 consumers), dbus (21), libcap (18), gawk (11), docker (3), containerd (1)

---

## 2. Functional Requirements

### 2.1 Snapshot Boundary Detection

**Condition**: `uses_snapshot=true` AND specs exist with `gate_threshold == subrelease`.

**Severity**: HIGH (snapshot may predate gating commit).

### 2.2 Upgrade Conflict Detection (C3+)

**Condition**: `mainline == subrelease` (snapshot bypassed) AND gated spec pair exists where old is active AND new version exists in remote repo (version differs).

**Algorithm**:
1. For each gated package where old spec is active: compare old version vs new version
2. If versions differ, find all ungated specs that Require or BuildRequire the package
3. Each such ungated spec is a CRITICAL finding (tdnf upgrade will pull new version, breaking pinned deps)

**Severity**: CRITICAL (build will fail with Solv error).

### 2.3 Root Cause Grouping

Findings should be traceable to the root-cause gated package. Summary should show:

| Gated Package | Old Version | New Version | Consumer Count |
|--------------|-------------|-------------|----------------|
| Linux-PAM | 1.5.3 | 1.7.2 | 32 |
| dbus | 1.15.4 | 1.16.2 | 21 |
| libcap | 2.66 | 2.77 | 18 |
| gawk | 5.1.1 | 5.3.2 | 11 |
| docker | 28.2.2 | 29.2.1 | 3 |
| containerd | 2.1.5 | 2.2.1 | 1 |

---

## 3. Edge Cases

- **Self-consuming gated specs**: gawk depends on gawk -- this is an internal subpackage reference, still flagged because tdnf will pull gawk-5.3.2 from remote
- **Transitive chains**: systemd depends on Linux-PAM-devel AND libcap-devel AND dbus-devel -- all three are gated. Any one of them causes the failure.
- **Remote repo contents may change**: The detection depends on the remote repo having the new version. Without `--check-urls`, the agent infers from spec version differences.

---

## 4. Reference Findings

From scan 2026-03-06, branch 5.0, subrelease 91, mainline 91:

```
[C3] CRITICAL: systemd (5.0)
  Snapshot bypassed (mainline=91), but remote repo contains Linux-PAM-1.7.2
  (newer than locally-built Linux-PAM-1.5.3). The 'tdnf upgrade' step before
  install will pull Linux-PAM-1.7.2 from remote, then systemd's dependency on
  Linux-PAM-devel (pinned to old version) cannot be satisfied.
```

Total C3 findings: 86 (all CRITICAL)

---

## 5. Remediation

**Option A**: Use a valid snapshot containing only old package versions (requires snapshot to exist).

**Option B**: Upgrade to subrelease 92 to activate new specs consistently.

**Option C**: Modify the build system to exclude gated packages from the `tdnf upgrade` step.

See ADR-0002 for full analysis.

---

## 6. Dependencies

**Depends On**: REQ-7 (inventory), C1 (subpackage data), remote repo metadata (for C3+)

**Depended On By**: Remediation pipeline
