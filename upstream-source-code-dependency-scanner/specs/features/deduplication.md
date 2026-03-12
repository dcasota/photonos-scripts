# Feature Requirement Document: Global Deduplication

**Feature ID**: FRD-deduplication
**Related PRD Requirements**: REQ-6
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Ensure that all patch directives emitted by the scanner are globally deduplicated by `(directive, value)` pair, so that no patched spec file contains duplicate `Requires:`, `Conflicts:`, or `Provides:` entries -- even when multiple source analysis edges converge on the same target.

### Value Proposition

Multiple analysis phases may independently discover the same dependency. For example, both `github.com/docker/docker` (from docker-compose's go.mod) and `github.com/docker/cli` (from docker-compose's go.mod) may both map to the Photon package `docker`, producing duplicate `Requires: docker >= 28.0` patches. Without deduplication, the patched spec would contain redundant entries and inflated issue counts.

### Success Criteria

- [SC-4] No duplicate `Requires:` or `Conflicts:` entries in any patched spec
- Issue count accuracy: `conflict_detect()` return value counts only non-duplicate additions
- `add_patch_to_set()` performs O(n) uniqueness check before insertion
- Deduplication operates at the `(szDirective, szValue)` level within each `SpecPatchSet`

---

## 2. Functional Requirements

### 2.1 Duplicate Detection in add_patch_to_set()

**Description**: The `add_patch_to_set()` function performs a uniqueness check before adding a new `SpecPatch` to a `SpecPatchSet`. Two patches are considered duplicates if they have the same directive type and target value.

**Comparison fields**:
- `szDirective`: The RPM directive (e.g., `"Requires"`, `"Conflicts"`, `"Provides"`)
- `szValue`: The full value string including version constraint (e.g., `"docker >= 28.0"`)

**Implementation**:
```c
static int add_patch_to_set(SpecPatchSet *pSet, SpecPatch *pPatch)
{
    for (SpecPatch *p = pSet->pAdditions; p; p = p->pNext)
    {
        if (strcmp(p->szDirective, pPatch->szDirective) == 0 &&
            strcmp(p->szValue, pPatch->szValue) == 0)
        {
            /* Duplicate -- suppress */
            free(pPatch);
            return 0;
        }
    }
    /* Unique -- insert */
    pPatch->pNext = pSet->pAdditions;
    pSet->pAdditions = pPatch;
    pSet->dwAdditionCount++;
    return 1;
}
```

**Acceptance Criteria**:
- Returns `1` when a new unique patch is added (counted as an issue)
- Returns `0` when a duplicate is suppressed (not counted as an issue)
- Freed memory of suppressed duplicate patch to prevent leaks
- Comparison is case-sensitive (RPM directives and package names are case-sensitive)

### 2.2 Issue Count Accuracy

**Description**: The `conflict_detect()` function's return value (`dwIssueCount`) must reflect only non-duplicate additions.

**Mechanism**: Every call site uses `dwIssueCount += add_patch_to_set(pSet, pPatch)`, so duplicates contribute `0` to the total.

**Acceptance Criteria**:
- If docker-compose has 3 gomod edges that all map to `Requires: docker >= 28.0`, the issue count increments by `1`, not `3`
- The `dwAdditionCount` in each `SpecPatchSet` matches the number of unique additions
- Summary output (`"Issues detected: N"`) accurately reflects non-duplicate findings

### 2.3 Per-Spec Scope

**Description**: Deduplication is scoped to each `SpecPatchSet` (i.e., per spec file). The same directive may legitimately appear in patches for different spec files.

**Acceptance Criteria**:
- `Requires: docker >= 28.0` in docker-compose's patch set AND in docker-buildx's patch set is allowed (two different specs)
- Within a single spec's patch set, only one instance of `Requires: docker >= 28.0` exists
- Each `SpecPatchSet` maintains its own linked list of patches

### 2.4 Cross-Source Deduplication

**Description**: Deduplication applies regardless of the source that produced the patch. A `Requires: docker >= 28.0` from gomod analysis and the same directive from tarball analysis are considered duplicates.

**Acceptance Criteria**:
- An edge from `EDGE_SRC_GOMOD` and an edge from `EDGE_SRC_TARBALL` producing identical `(directive, value)` pairs result in a single patch
- The first patch inserted wins (its evidence and severity are kept; the duplicate is discarded)
- Source provenance does not affect uniqueness comparison

---

## 3. Data Model

### SpecPatch Fields (deduplication-relevant)

| Field | Type | Used in Dedup | Description |
|-------|------|---------------|-------------|
| `szDirective` | char[32] | Yes | RPM directive name (e.g., `"Requires"`) |
| `szValue` | char[256] | Yes | Full value string (e.g., `"docker >= 28.0"`) |
| `nSource` | EdgeSource | No | Source provenance (not part of uniqueness key) |
| `szEvidence` | char[512] | No | Traceability (not part of uniqueness key) |
| `nSeverity` | PatchSeverity | No | Severity level (not part of uniqueness key) |

### SpecPatchSet Fields

| Field | Type | Description |
|-------|------|-------------|
| `dwAdditionCount` | uint32_t | Count of unique additions (post-dedup) |
| `pAdditions` | SpecPatch* | Linked list of unique patches |

---

## 4. Edge Cases

- **Same directive, different versions**: `Requires: docker >= 28.0` and `Requires: docker >= 28.5.1` are NOT duplicates (different `szValue`). Both are emitted.
- **Same target, different directive types**: `Requires: docker` and `Conflicts: docker < 25.0` are NOT duplicates (different `szDirective`). Both are emitted.
- **Version constraint normalization**: Version strings are compared as raw strings, not semantically. `>= 28.0` and `>= 28.0.0` are treated as different values.
- **Empty patch set**: A spec with zero unique additions gets no `SpecPatchSet` entry.
- **All duplicates**: If every inferred edge for a spec produces a duplicate, `dwAdditionCount` stays at its previous value and no new issues are counted.
- **Order dependence**: The first unique patch for a given `(directive, value)` is kept; subsequent duplicates are discarded. Evidence from the first source is preserved.

---

## 5. Dependencies

**Depends On**: FRD-gomod-analysis, FRD-tarball-analysis, FRD-api-constellation (all produce patches that flow through deduplication)

**Depended On By**: FRD-output (patched specs contain only deduplicated entries), FRD-ci-integration (issue counts in CI summary reflect deduplicated totals)
