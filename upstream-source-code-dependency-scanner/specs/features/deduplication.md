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
- Version-strength consolidation: when multiple edges yield `Requires: X >= A` and `Requires: X >= B`, only the stronger (higher version) is kept
- Conflicts consolidation: multiple `Conflicts: X < A` entries are reduced to the strongest (highest lower-bound); multiple `Conflicts: X > A` entries keep the most restrictive (lowest upper-bound)

---

## 2. Functional Requirements

### 2.1 Duplicate Detection and Version-Strength Consolidation in add_patch_to_set()

**Description**: The `add_patch_to_set()` function performs both exact-duplicate detection and version-strength consolidation. For the same `(directive, target, operator)` triple, only the strongest version is kept.

**Comparison fields**:
- `szDirective`: The RPM directive (e.g., `"Requires"`, `"Conflicts"`, `"Provides"`)
- `szValue`: Parsed into `(target, operator, version)` for consolidation

**Consolidation rules**:

| Directive + Operator | Rule | Example |
|---------------------|------|---------|
| `Requires: X >= A` | Higher version wins | `docker >= 29.0` subsumes `docker >= 28.0` |
| `Conflicts: X < A` | Higher version wins (subsumes lower) | `docker-engine < 29.2` subsumes `docker-engine < 28.3` |
| `Conflicts: X > A` | Lower version wins (more restrictive) | `docker-engine > 28` preferred over `docker-engine > 29` |
| Exact duplicate | Suppressed | `docker >= 28.0` + `docker >= 28.0` → one entry |

**Acceptance Criteria**:
- Returns `1` when a new unique patch is added (counted as an issue)
- Returns `0` when a duplicate or weaker version is suppressed (not counted)
- When a stronger version replaces a weaker one, the existing patch is updated in-place (evidence and source updated, no new node added)
- Freed memory of suppressed duplicate patch to prevent leaks
- Comparison is case-sensitive (RPM directives and package names are case-sensitive)
- Patches with unparseable values (no operator) fall through to exact-match dedup only

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

- **Same directive, different versions, same target and operator**: `Requires: docker >= 28.0` and `Requires: docker >= 29.0` are consolidated -- the stronger (`>= 29.0`) wins and the weaker is suppressed. The existing patch is updated in-place.
- **Same target, different directive types**: `Requires: docker >= 29.0` and `Conflicts: docker-engine < 29.2` are NOT duplicates (different `szDirective`). Both are emitted.
- **Same target, different operators**: `Conflicts: docker-engine < 29.2` and `Conflicts: docker-engine > 29` are NOT consolidated (different operators `<` vs `>`). Both are emitted as they express different constraint bounds.
- **Version comparison**: Uses `version_compare()` (segmented RPM-style) for semantic ordering, not raw string comparison.
- **Unparseable values**: Patches whose values cannot be decomposed into `(target, operator, version)` (e.g., bare package names) fall through to exact-match dedup only.
- **Empty patch set**: A spec with zero unique additions gets no `SpecPatchSet` entry.
- **All duplicates**: If every inferred edge for a spec produces a duplicate, `dwAdditionCount` stays at its previous value and no new issues are counted.
- **Replacement evidence**: When a stronger version replaces a weaker one, the evidence and source are updated to reflect the stronger edge's provenance.

---

## 5. Dependencies

**Depends On**: FRD-gomod-analysis, FRD-tarball-analysis, FRD-api-constellation (all produce patches that flow through deduplication)

**Depended On By**: FRD-output (patched specs contain only deduplicated entries), FRD-ci-integration (issue counts in CI summary reflect deduplicated totals)
