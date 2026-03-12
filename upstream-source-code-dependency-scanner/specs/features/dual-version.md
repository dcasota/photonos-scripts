# Feature Requirement Document: Dual-Version Analysis

**Feature ID**: FRD-dual-version
**Related PRD Requirements**: REQ-4
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Analyze both the current release spec files (from branch `SPECS/`) and the latest upstream version spec files (from `SPECS_NEW/`), tagging nodes by provenance and merging inferred dependencies with deduplication. This enables detection of dependency changes between the currently-shipped version and the next planned upgrade.

### Value Proposition

Dependency gaps often emerge during version bumps. A package that currently has all its `Requires:` correct may acquire new Go module dependencies in its latest version. Dual-version analysis catches these gaps before the new version is shipped.

### Success Criteria

- Phase 1a parses all current SPECS/ and Phase 1b parses all SPECS_NEW/ spec files
- Nodes from SPECS_NEW are tagged with `bIsLatest = 1`
- Source resolution cascade: clone-based analysis → tarball-based analysis → skip
- Both current and latest nodes participate in conflict detection
- Same package appearing in both SPECS and SPECS_NEW produces two distinct graph nodes

---

## 2. Functional Requirements

### 2.1 Phase 1a: Current Release Spec Parsing

**Description**: Parse all `.spec` files in the branch `SPECS/` directory to populate the graph with current release nodes and edges.

**Invocation**: `spec_parse_directory(&graph, pszSpecsDir)` in `main.c`.

**Acceptance Criteria**:
- All nodes created in Phase 1a have `bIsLatest = 0` (default)
- Node count and edge count are recorded for summary reporting (`dwSpecsScanned`, `dwPhase1Edges`)
- Errors are logged but parsing continues

### 2.2 Phase 1b: Latest Version Spec Parsing

**Description**: Parse all `.spec` files in the `SPECS_NEW/` directory. These represent the latest upstream versions that will replace current versions in a future release.

**Invocation**: `spec_parse_directory(&graph, pszSpecsNewDir)` followed by tagging loop.

**Tagging**: All nodes with index `>= dwLatestNodesStart` are tagged with `bIsLatest = 1`.

**Acceptance Criteria**:
- Phase 1b only runs if `--specs-new-dir` is provided and the directory exists
- Nodes from SPECS_NEW have `bIsLatest = 1` set
- Both current and latest versions of the same package coexist in the graph as separate nodes
- Summary output distinguishes current vs. latest node counts

### 2.3 Source Resolution Cascade

**Description**: For each package node, upstream source dependencies are resolved using a cascade of sources, in priority order:

1. **Clone analysis** (Phase 2a): `git show v{version}:go.mod` from the upstream git clone
2. **Tarball analysis** (Phase 2d/2e): Extract `go.mod` from `SOURCES_NEW/` or `photon_sources/`
3. **Skip**: No upstream source available; only spec-declared edges exist

**Cascade logic**:
- Clone analysis runs first for all packages (Phase 2a)
- Tarball analysis (Phase 2d: SOURCES_NEW, Phase 2e: photon_sources) only runs for packages that have `BuildRequires: go` AND no existing gomod/tarball edges
- The `node_has_gomod_edges()` check enforces the cascade: once a package has source-inferred edges from any source, it's not re-analyzed

**Acceptance Criteria**:
- A package with a successful clone analysis is NOT re-analyzed from tarballs
- A Go package without a clone IS analyzed from SOURCES_NEW tarballs
- A Go package analyzed from SOURCES_NEW is NOT re-analyzed from photon_sources
- Non-Go packages are never tarball-analyzed

### 2.4 bIsLatest Tagging

**Description**: The `bIsLatest` flag on `GraphNode` distinguishes current release nodes from latest version nodes.

**Usage downstream**:
- Conflict detection can report whether a missing dependency exists only in the latest version (new gap) vs. the current version (existing gap)
- Output manifests distinguish current vs. latest findings
- API version extraction covers both current and latest nodes

**Acceptance Criteria**:
- `bIsLatest = 0` for all Phase 1a nodes
- `bIsLatest = 1` for all Phase 1b nodes
- The flag is preserved through all downstream phases
- Summary output: `"current: N"` and `"latest: M"` counts

### 2.5 Dual-Phase Execution Order

**Description**: The scanner executes in a strict phase order:

| Phase | Operation | Input |
|-------|-----------|-------|
| 1a | Parse current specs | `--specs-dir` |
| 1b | Parse latest specs | `--specs-new-dir` |
| 2a | Go module clone analysis | `{upstreams}/clones/` |
| 2b | Python project analysis | `{upstreams}/clones/` |
| 2c | API version extraction | `{upstreams}/clones/` |
| 2d | Tarball analysis (SOURCES_NEW) | `{upstreams}/SOURCES_NEW/` |
| 2e | Tarball analysis (current sources) | `--sources-dir` |
| 3 | Conflict detection + patching | Graph |

**Acceptance Criteria**:
- Phases execute in the order listed above
- Each phase logs its start and completion with node/edge counts
- Optional phases (1b, 2a-2e) are skipped gracefully when their inputs are not provided
- Phase 3 operates on the complete merged graph from all prior phases

---

## 3. Data Model

### Node Fields (dual-version-specific)

| Field | Type | Description |
|-------|------|-------------|
| `bIsLatest` | uint32_t | `1` if from SPECS_NEW, `0` if from current SPECS |

### Phase Tracking Variables

| Variable | Type | Description |
|----------|------|-------------|
| `dwLatestNodesStart` | uint32_t | Index of first SPECS_NEW node |
| `dwSpecsScanned` | uint32_t | Total node count after Phase 1a+1b |
| `dwPhase1Edges` | uint32_t | Edge count after Phase 1a+1b |

---

## 4. Edge Cases

- **No SPECS_NEW provided**: Phase 1b is skipped entirely; all analysis proceeds on current specs only. The `bIsLatest` flag is never set.
- **Package only in SPECS_NEW**: A package that exists in SPECS_NEW but not in current SPECS creates nodes with `bIsLatest = 1` only. Clone analysis still works if a matching clone exists.
- **Version unchanged**: If a package has the same version in both SPECS and SPECS_NEW, two nodes are created with identical metadata except `bIsLatest`. Clone analysis may produce identical edges for both (handled by deduplication).
- **SPECS_NEW directory empty**: Phase 1b runs but adds zero nodes. Not an error.
- **Mixed source provenance**: A current-version node may get edges from clone analysis, while the latest-version node for the same package gets edges from tarball analysis (different versions may have different clone availability).

---

## 5. Dependencies

**Depends On**: FRD-spec-parsing (Phase 1a and 1b use the spec parser), FRD-gomod-analysis (Phase 2a), FRD-tarball-analysis (Phase 2d/2e)

**Depended On By**: FRD-api-constellation (operates on the merged dual-version graph), FRD-deduplication (deduplicates across current + latest edges), FRD-output (manifests include dual-version metadata)
