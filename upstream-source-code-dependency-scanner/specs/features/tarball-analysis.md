# Feature Requirement Document: Source Tarball Analysis

**Feature ID**: FRD-tarball-analysis
**Related PRD Requirements**: REQ-3
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Extract and analyze `go.mod` files from `.tar.gz` source tarballs when git clones are unavailable, providing a fallback source analysis path for Go packages whose upstream repositories are not cloned.

### Value Proposition

Not all Photon Go packages have upstream git clones available. Source tarballs in `photon_sources/1.0/` and `SOURCES_NEW/` are the authoritative build inputs. Tarball analysis ensures that even packages without clones have their Go module dependencies discovered.

### Success Criteria

- [SC-5] Tarball analysis finds `go.mod` in `SOURCES_NEW` packages without clones
- Secure extraction via `fork()/execlp()` -- no shell interpolation
- Tarball matching logic correctly identifies `{name}-{version}.tar.gz` (and variants)
- Only Go packages (`BuildRequires: go`) that lack clone-derived edges are analyzed (optimization)
- Extracted `go.mod` is parsed identically to clone-derived `go.mod`

---

## 2. Functional Requirements

### 2.1 Tarball Matching

**Description**: Given a package name and version, find the corresponding source tarball in a flat source directory.

**Matching patterns** (tried in order):
1. `{name}-{version}.tar.gz`
2. `{name}-{version}.tar.bz2`
3. `{name}-{version}.tar.xz`
4. `{name}-{version}.tgz`
5. `{name}-{version}.zip`

**Implementation**: `tarball_find_source()` in `tarball_analyzer.h`.

**Acceptance Criteria**:
- `tarball_find_source("/sources", "calico", "3.28.2", ...)` → `/sources/calico-3.28.2.tar.gz`
- Returns `-1` if no matching tarball exists
- Case-sensitive matching on package name
- Output path is bounds-checked against `MAX_PATH_LEN`

### 2.2 Optimization: Go-Only, Clone-Gap Packages

**Description**: Tarball analysis is an expensive I/O operation. Only packages that meet all three criteria are analyzed:

1. **Go package**: Node has a `BuildRequires: go` (or `golang`) edge from spec parsing
2. **Not already analyzed**: Node has no existing `EDGE_SRC_GOMOD` or `EDGE_SRC_TARBALL` edges
3. **Has version**: Node's `szVersion` is non-empty

**Implementation**: `analyze_tarball_sources()` in `main.c` uses `node_has_go_buildrequires()` and `node_has_gomod_edges()` helper functions.

**Acceptance Criteria**:
- A package with `BuildRequires: go` and existing gomod edges is skipped (counted in `dwSkippedClone`)
- A package without `BuildRequires: go` is never analyzed via tarball
- Subpackages (`bIsSubpackage = 1`) are skipped
- Packages without a version string are skipped

### 2.3 Secure Tarball Extraction

**Description**: Extract `go.mod` from the tarball using `fork()/execlp()` to invoke `tar` without shell interpolation.

**Extraction flow**:
1. Create a safe temp file via `mkstemp("/tmp/tarball-extract-XXXXXX")`
2. `fork()` a child process
3. In child: `execlp("tar", "tar", "-tzf", tarball, "--wildcards", "*/go.mod", NULL)` to list matching entries
4. Parse the listing to find the first `go.mod` entry
5. `fork()` again to extract: `execlp("tar", "tar", "-xzf", tarball, "-O", matched_entry, NULL)` writing to the temp file
6. Parse the temp file as go.mod
7. `unlink()` the temp file

**Acceptance Criteria**:
- No `system()` call or shell string interpolation anywhere in the extraction pipeline
- Temp file created with `mkstemp()` -- no predictable file names
- Child process stderr redirected to `/dev/null` to suppress tar warnings
- Parent waits for child with `waitpid()` and checks exit status
- Temp file is always unlinked, even on error paths

### 2.4 go.mod Parsing from Tarball

**Description**: Once extracted, the `go.mod` file is parsed identically to clone-derived files (same `gomod_parse_file()` function).

**Edge properties**:
- `nType = EDGE_REQUIRES`
- `nSource = EDGE_SRC_TARBALL`
- All other fields identical to FRD-gomod-analysis edges

**Acceptance Criteria**:
- Tarball-derived edges are distinguishable by `nSource = EDGE_SRC_TARBALL`
- Module-to-package mapping uses the same `GomodPackageMap` instance
- Edge evidence includes the tarball path for traceability

### 2.5 Dual Source Directory Support

**Description**: Tarball analysis runs against two source directories:
1. `photon_sources/1.0/` (current release tarballs) -- Phase 2e
2. `{upstreams}/SOURCES_NEW/` (latest version tarballs) -- Phase 2d

**Acceptance Criteria**:
- Phase 2d runs for `SOURCES_NEW` (latest tarballs) before Phase 2e (current tarballs)
- A package analyzed from `SOURCES_NEW` tarball won't be re-analyzed from `photon_sources` (the `node_has_gomod_edges` check prevents it)
- Both source directories are optional; analysis is skipped if directory doesn't exist

---

## 3. Data Model

### Edge Fields (tarball-analysis-specific)

| Field | Type | Description |
|-------|------|-------------|
| `nType` | EdgeType | `EDGE_REQUIRES` |
| `nSource` | EdgeSource | `EDGE_SRC_TARBALL` |
| `szTargetName` | char[256] | Photon package name from mapping |
| `nConstraintOp` | ConstraintOp | `CONSTRAINT_GE` |
| `szConstraintVer` | char[64] | Version from go.mod |
| `szEvidence` | char[512] | Tarball path + module path |

---

## 4. Edge Cases

- **Nested directory structure in tarball**: `go.mod` may be at `{name}-{version}/go.mod` or `{name}/go.mod`. The `--wildcards "*/go.mod"` pattern handles both.
- **Multiple go.mod files**: Some tarballs contain multiple `go.mod` (root + subdirectories). Only the first match (shortest path) is used.
- **Corrupted tarballs**: `tar` returns non-zero exit code; the package is skipped.
- **Very large tarballs**: Extraction reads only the go.mod entry, not the entire archive (streaming via `-O`).
- **Tarball with no go.mod**: The wildcard listing returns empty; the package is skipped gracefully.
- **Name collisions**: If `{name}-{version}.tar.gz` matches a different package's tarball (unlikely in practice), the `szPackageName` parameter ensures edges are attributed to the correct node.
- **Symlinks in tarball**: Not followed during extraction; only regular file entries are matched.

---

## 5. Dependencies

**Depends On**: FRD-spec-parsing (nodes with version info must exist), FRD-gomod-analysis (tarball is fallback for clone gaps; uses same `GomodPackageMap`), FRD-security (fork/execlp, mkstemp patterns)

**Depended On By**: FRD-dual-version (tarball analysis feeds into dual-version source resolution cascade), FRD-deduplication (tarball edges participate in global dedup)
