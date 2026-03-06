# Feature Requirement Document: C1 -- Package Split/Merge Detection

**Feature ID**: FRD-C1
**Related PRD Requirements**: REQ-1, REQ-8, REQ-9, REQ-10
**Status**: Implemented
**Last Updated**: 2026-03-06

---

## 1. Feature Overview

### Purpose

Detect when a gated spec pair produces different subpackage sets, and consumers depend on subpackages only available in the inactive spec variant.

### Value Proposition

Package splits (e.g., libcap -> libcap + libcap-libs + libcap-minimal) are the highest-impact gating change because they introduce new package names that no prior snapshot contains.

### Success Criteria

- Detects libcap v2.66->v2.77 split as CRITICAL with `libcap-libs`, `libcap-minimal`, `libcap-doc` listed
- Identifies `rpm` as a consumer of `libcap-libs`
- Zero false positives on spec pairs with identical subpackage sets

---

## 2. Functional Requirements

### 2.1 Spec Pair Identification

**Description**: For each package with both a main SPECS/ entry (gated `>= N`) and a SPECS/N/ entry (gated `<= N`), extract the full subpackage list from both.

**Inputs**: All `.spec` files in branch SPECS/ and SPECS/<N>/ directories.

**Outputs**: List of spec pairs with their subpackage sets.

**Acceptance Criteria**:
- Parses `%package` directives correctly, expanding `%{name}` macros
- Handles `-n` syntax in `%package -n <explicit-name>`
- Identifies relocated specs in any SPECS/<N>/ subdirectory

### 2.2 Subpackage Diff

**Description**: Compute the symmetric difference between old and new subpackage sets.

**Outputs**: Sets of added and removed subpackage names.

**Acceptance Criteria**:
- Added packages: exist in new spec but not old
- Removed packages: exist in old spec but not new
- Main package name is always included in both sets

### 2.3 Consumer Detection

**Description**: For each added/removed subpackage, scan all specs (branch + common) for Requires or BuildRequires on that subpackage name.

**Acceptance Criteria**:
- Matches exact package name (before version operators)
- Includes both `Requires:` and `BuildRequires:` lines
- Reports consuming spec name and path

### 2.4 Severity Classification

| Condition | Severity |
|-----------|----------|
| New subpackages with active consumers, old spec active | CRITICAL |
| New subpackages with no consumers found | WARNING |
| Removed subpackages with active consumers, new spec active | HIGH |

---

## 3. Data Model

### Finding Fields (C1-specific)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `missing_subpackages` | string[] | Yes | Subpackage names not in active spec |
| `consumers` | string[] | Yes (if CRITICAL) | Spec names that depend on missing subpackages |
| `spec_paths` | string[] | Yes | Paths to new spec, old spec |

---

## 4. Edge Cases

- **Self-referencing subpackages**: libcap's new spec requires `libcap-libs` from itself -- this is NOT a consumer conflict (it's internal). Agent should still flag it because the subpackage doesn't exist in snapshot.
- **Transitive dependencies**: If A requires B-new (gated), and C requires A, C is affected transitively. Current implementation flags direct consumers only.
- **Architecture-gated specs**: `%global build_if "%{_arch}" == "aarch64"` should be treated as non-subrelease gating and excluded from C1 checks.

---

## 5. Reference Finding

From scan 2026-03-06T20:48:03Z, branch 5.0, subrelease 91:

```
[C1] CRITICAL: libcap (5.0)
  Missing subpackages: libcap-doc, libcap-libs, libcap-minimal
  Consumers: libcap, rpm
  Spec paths: 5.0/SPECS/libcap/libcap.spec, 5.0/SPECS/91/libcap/libcap.spec
  Remediation: Set photon-mainline = photon-subrelease to bypass snapshot
```

---

## 6. Dependencies

**Depends On**: REQ-7 (inventory), spec parser

**Depended On By**: FRD-C3 (boundary mismatch uses C1 subpackage data)
