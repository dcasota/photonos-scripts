# Feature Requirement Document: Go Module Analysis

**Feature ID**: FRD-gomod-analysis
**Related PRD Requirements**: REQ-2
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Analyze `go.mod` files from upstream git clones to discover actual Go module dependencies, map them to Photon package names, and infer missing `Requires:` edges in the dependency graph.

### Value Proposition

Go packages declare their imports in `go.mod`, but Photon spec files manually list `Requires:` directives that often omit transitive or newly-added dependencies. In Photon 5.0, 44 spec files have 145+ undeclared runtime dependencies. Automated go.mod analysis closes this gap.

### Success Criteria

- Correctly parses `require` blocks from go.mod files, including both direct and indirect dependencies
- Maps Go module paths (e.g., `github.com/docker/docker`) to Photon package names (e.g., `docker`) via `gomod-package-map.csv`
- Uses version-matched analysis (`git show v{version}:go.mod`) to read the go.mod at the exact tagged version
- Resolves clone directories via PRN (Package Report) mapping when clone name differs from package name
- All inferred edges carry `nSource = EDGE_SRC_GOMOD`

---

## 2. Functional Requirements

### 2.1 Clone Directory Enumeration

**Description**: Scan `photon-upstreams/{branch}/clones/` for git repositories and match each clone to a Photon package.

**Inputs**:
- `pszClonesDir`: path to the clones directory
- `pPrnMap`: optional PRN-derived package-to-clone mapping

**Outputs**: List of (clone_dir, package_name, version) tuples ready for go.mod extraction.

**Acceptance Criteria**:
- Enumerates all subdirectories under the clones directory
- Uses `prn_map_find_package()` to resolve clone directory name → Photon package name
- Falls back to clone directory name as package name when PRN lookup returns NULL
- Skips clones that have no corresponding node in the graph (not a Photon package)

### 2.2 Version-Matched go.mod Extraction

**Description**: For each matched clone, extract the `go.mod` at the version tag matching the spec's `Version:` field, using `git show v{version}:go.mod`.

**Mechanism**:
1. Look up the graph node for the package to obtain `szVersion`
2. Construct git ref: try `v{version}` first, then `{version}` as fallback
3. Execute `git -C {clone_dir} show {ref}:go.mod` via `fork()/execlp()` (no shell)
4. Write output to a `mkstemp()` temp file for parsing
5. Parse the temp file, then `unlink()` it

**Acceptance Criteria**:
- `git show v1.6.36:go.mod` extracts the go.mod for containerd 1.6.36
- Falls back to `git show 1.6.36:go.mod` if the `v`-prefixed tag doesn't exist
- Returns gracefully if neither tag exists (no go.mod available from clone)
- Uses `fork()/execlp()` to avoid shell injection (see FRD-security)
- Temp files created with `mkstemp()` (see FRD-security)

### 2.3 go.mod Parsing

**Description**: Parse `require` directives from a go.mod file to extract module paths and versions.

**go.mod format**:
```
require (
    github.com/docker/docker v28.5.1+incompatible
    github.com/containerd/containerd v1.7.24
)
```

**Acceptance Criteria**:
- Parses both block `require ( ... )` and single-line `require github.com/foo v1.0` syntax
- Strips `+incompatible` suffix from version strings
- Handles `// indirect` comments (captures both direct and indirect dependencies)
- Strips `v` prefix from version for constraint comparison (e.g., `v28.5.1` → `28.5.1`)

### 2.4 Module-to-Package Mapping

**Description**: Map Go module paths to Photon package names using `gomod-package-map.csv`.

**CSV format**: `module_path,photon_package` (e.g., `github.com/docker/docker,docker`)

**Mapping rules**:
1. Exact match: `github.com/docker/docker` → `docker`
2. Prefix match: `github.com/docker/docker/pkg/foo` → `docker` (longest prefix wins)
3. SKIP entry: `github.com/moby/moby/client,SKIP` → edge is not created. Used for Go sub-modules with independent version schemes that do not correspond to the parent package version (e.g., `moby/moby/client v0.2.2` is NOT docker v0.2).
4. No match: module is not a Photon package → skip (no edge created)

**SKIP entries** (sub-modules with independent versioning):

| Module Path | Reason |
|-------------|--------|
| `github.com/moby/moby/client` | Sub-module v0.2.2; version does not correspond to docker engine |
| `github.com/moby/moby/api` | API definition sub-module v1.53.0; not a runtime package version |
| `github.com/containerd/containerd/api` | API definition sub-module; independent version from containerd |

**Acceptance Criteria**:
- `gomod_map_lookup()` returns the correct Photon package for known Go module paths
- `gomod_map_lookup()` returns `"SKIP"` for explicitly excluded sub-modules
- Edges are not created when the mapped package is `"SKIP"`
- Prefix matching handles sub-paths; longest prefix wins, so `moby/moby/client` (SKIP) takes priority over `moby/moby` (docker)
- Unknown modules (e.g., `golang.org/x/sys`) are silently skipped if not in the map
- Map supports up to `MAX_MAP_ENTRIES` (1024) entries

### 2.5 Edge Creation

**Description**: For each mapped module dependency, add an inferred `EDGE_REQUIRES` edge to the graph.

**Edge properties**:
- `nType = EDGE_REQUIRES`
- `nSource = EDGE_SRC_GOMOD`
- `szTargetName` = Photon package name from mapping
- `nConstraintOp = CONSTRAINT_GE`
- `szConstraintVer` = major version constraint extracted by `gomod_extract_major_constraint()`
- `szEvidence` = go.mod path and module path for traceability

**Version constraint extraction** (`gomod_extract_major_constraint`):

| Module version | Module path | Constraint | Rule |
|---------------|-------------|------------|------|
| `v28.5.1` | `github.com/docker/docker` | `28.0` | Standard: major.0 |
| `v0.32.3` | `k8s.io/api` | `1.32` | k8s.io convention: v0.X.Y → Kubernetes 1.X |
| `v0.29.1` | `github.com/docker/buildx` | `0.29` | v0.X.Y: preserve major.minor |
| `v2.1.4` | `github.com/containerd/containerd/v2` | `2.0` | Standard: major.0 |

**Acceptance Criteria**:
- docker-compose's go.mod `require github.com/docker/docker v28.5.1` → edge: docker-compose → docker `>= 28.0` (source: gomod)
- k8s.io modules use the Kubernetes versioning convention: `k8s.io/api v0.32.3` → `kubernetes >= 1.32`
- v0.X.Y modules preserve `major.minor`: `docker/buildx v0.29.1` → `docker-buildx >= 0.29`
- Edges reference the correct source node index (`dwFromIdx` matches the owning package)
- Target resolution (`dwToIdx`) is attempted; set to `UINT32_MAX` if target package not in graph

---

## 3. Data Model

### Edge Fields (gomod-analysis-specific)

| Field | Type | Description |
|-------|------|-------------|
| `nType` | EdgeType | `EDGE_REQUIRES` |
| `nSource` | EdgeSource | `EDGE_SRC_GOMOD` |
| `szTargetName` | char[256] | Photon package name from mapping |
| `nConstraintOp` | ConstraintOp | `CONSTRAINT_GE` (minimum version) |
| `szConstraintVer` | char[64] | Version from go.mod `require` |
| `szEvidence` | char[512] | `"go.mod: github.com/docker/docker v28.5.1"` |

---

## 4. Edge Cases

- **Replaced modules**: `replace` directives in go.mod redirect module paths. Current implementation does not follow replaces -- the original module path is used for mapping.
- **Retracted versions**: `retract` directives are ignored (not relevant to dependency mapping).
- **Multi-module repos**: A single clone may contain multiple `go.mod` files in subdirectories. Only the root `go.mod` is analyzed.
- **Missing go.mod**: Some Go packages predate Go modules and have no `go.mod`. These are silently skipped.
- **Vendored dependencies**: `vendor/` directories are not analyzed; only the root `go.mod` is authoritative.
- **Clone without matching tag**: If the git clone has no tag matching the spec version, the package is skipped for gomod analysis (tarball fallback may apply -- see FRD-tarball-analysis).
- **Indirect dependencies**: Both direct and indirect `require` entries are captured. Indirect entries may map to packages that are transitive-only; deduplication and conflict detection handle this downstream.

---

## 5. Dependencies

**Depends On**: FRD-spec-parsing (Phase 1 nodes must exist before Phase 2 can match clones to packages), `gomod-package-map.csv` (data file), `prn_parser.h` (PRN map for clone resolution)

**Depended On By**: FRD-tarball-analysis (tarball is the fallback when clone analysis fails), FRD-api-constellation (API version extraction uses the same clones), FRD-deduplication (multiple gomod edges may produce duplicates)
