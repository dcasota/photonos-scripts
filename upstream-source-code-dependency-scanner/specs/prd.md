# Product Requirements Document (PRD)

## Upstream Source Code Dependency Scanner

**Version**: 1.0
**Last Updated**: 2026-03-12
**Status**: Implementation Complete -- Dual-Version Analysis

---

## 1. Purpose

Photon OS packages built from Go and Python sources declare runtime dependencies (`Requires:`, `Conflicts:`, `Provides:`) in RPM spec files. These declarations are maintained manually and frequently fall behind what the upstream source code actually imports. When a Go binary imports `github.com/docker/docker v28.5.1` but the spec file declares no `Requires: docker`, the resulting RPM can be installed on a system that lacks a compatible Docker engine, producing silent runtime failures.

This project delivers an automated dependency scanner that:
- Parses RPM spec files to build a dependency graph
- Analyzes upstream source code (Go modules, Python projects) to discover actual imports
- Compares declared vs. actual dependencies to detect gaps
- Generates patched spec files with the missing declarations
- Detects cross-version API constellation conflicts (Docker SDK/API version mismatches)

**Target Users**: Photon OS package maintainers, release engineers, and CI pipelines.

**Motivation**: In Photon 5.0, 44 spec files have 145+ undeclared runtime dependencies across packages like calico (15 missing), docker-compose (9 missing), and kubernetes-dns (9 missing). Docker SDK version mismatches can cause silent API incompatibilities that only surface at runtime.

---

## 2. Scope

### In Scope

- Parse all RPM spec directives per [rpm.org/docs/4.20.x/manual/spec.html](https://rpm.org/docs/4.20.x/manual/spec.html)
- Analyze Go modules (`go.mod`) from git clones and source tarballs
- Analyze Python projects (`pyproject.toml`, `setup.cfg`)
- Extract API version constants from source code (Docker API, containerd API)
- Detect missing `Requires:`, `Conflicts:`, `Provides:` directives
- Detect Docker SDK-to-API version mismatches (lower-bound and upper-bound Conflicts)
- Dual-version analysis: current release specs + latest upstream version specs
- Source extraction from `.tar.gz` tarballs (photon_sources, SOURCES_NEW)
- Generate patched specs in `SPECS_DEPFIX/` with changelog entries
- Produce machine-readable JSON manifest and enriched dependency graph
- Run as GitHub Actions CI workflow and as standalone CLI tool
- Support all 7 Photon branches (3.0, 4.0, 5.0, 6.0, master, dev, common)

### Out of Scope

- Modifying original spec files in branch repositories
- Building or testing RPM packages
- Resolving transitive dependency chains beyond direct imports
- Non-Go/Python source analysis (C, Rust, Java)
- Repository mirroring or package download

---

## 3. Goals and Success Criteria

### Goals

1. **Completeness**: Detect all undeclared Go module and Python dependencies
2. **Accuracy**: Zero false positives on dependency detection -- every reported issue is a genuine gap
3. **Safety**: Generated patches never introduce regressions
4. **Deduplication**: No duplicate directives in output, even when multiple source edges converge
5. **Cross-version awareness**: Detect API constellation conflicts across current and latest versions
6. **Security**: All source analysis is hardened against injection, traversal, and TOCTOU attacks

### Success Criteria

- [SC-1] Scanner detects all known docker-compose dependencies (docker, containerd, kubernetes, docker-buildx)
- [SC-2] Docker API version extraction produces correct `docker-api = 1.52` virtual provide
- [SC-3] Cross-version detection generates both `Conflicts: docker-engine < 28.3` and `Conflicts: docker-engine > 29`
- [SC-4] No duplicate `Requires:` or `Conflicts:` entries in any patched spec
- [SC-5] Tarball analysis finds go.mod in SOURCES_NEW packages without clones
- [SC-6] Full 7-branch scan completes within CI timeout (120 minutes)
- [SC-7] JSON manifest validates against `depfix-manifest-schema.json`

---

## 4. Requirements

### [REQ-1] RPM Spec Parsing (Full Directive Coverage)

The scanner must parse all dependency-related RPM spec directives:
- `Requires:`, `Requires(qualifier):` (pre, post, preun, postun, pretrans, posttrans, verify, interp, meta)
- `BuildRequires:`, `Provides:`, `Conflicts:`, `Obsoletes:`
- `BuildConflicts:`, `Recommends:`, `Suggests:`, `Supplements:`, `Enhances:`
- `OrderWithRequires:`
- `ExcludeArch:`, `ExclusiveArch:`, `ExcludeOS:`, `ExclusiveOS:`, `BuildArch:`

**Related**: FRD-spec-parsing, ADR-0001, ADR-0005

### [REQ-2] Go Module Dependency Analysis

The scanner must extract `require` directives from `go.mod` files and map Go module paths to Photon package names using a configurable mapping table.

**Related**: FRD-gomod-analysis

### [REQ-3] Source Tarball Analysis

The scanner must extract and analyze `go.mod` from `.tar.gz` source tarballs when git clones are unavailable, using secure extraction (no shell interpolation).

**Related**: FRD-tarball-analysis, ADR-0002

### [REQ-4] Dual-Version Analysis

The scanner must analyze both the current release spec (from branch SPECS/) and the latest version spec (from SPECS_NEW/), detecting dependencies from both and merging results with deduplication.

**Related**: FRD-dual-version

### [REQ-5] API Version Constellation Detection

The scanner must extract Docker/containerd API version constants from source code, map SDK versions to API versions, and detect incompatibilities:
- Lower-bound: `Conflicts: docker-engine < X` (consumer requires newer engine)
- Upper-bound: `Conflicts: docker-engine > X` (latest version exceeds current engine's max API)

**Related**: FRD-api-constellation, ADR-0003

### [REQ-6] Global Deduplication

All patch directives must be globally deduplicated by `(directive, value)` pair. When multiple source edges produce identical directives (e.g., docker/docker and docker/cli both yield `Requires: docker >= 28.0`), only one is emitted.

**Related**: FRD-deduplication

### [REQ-7] Security Hardening

All external input handling must be hardened:
- No `system()` or shell interpolation -- use `fork()/execlp()`
- Temp files via `mkstemp()` (no predictable paths)
- Path traversal validation on all user-supplied names
- Integer overflow guards on all realloc operations
- Bounds-checked buffer operations

**Related**: FRD-security, specs/security/

### [REQ-8] Dual-Format Output

Every scan must produce:
- Machine-readable JSON manifest (`depfix-manifest-{branch}-{timestamp}.json`)
- Enriched dependency graph JSON
- Patched spec files in `SPECS_DEPFIX/{branch}/{package}/`

**Related**: FRD-output

### [REQ-9] CI Workflow Integration

The scanner must run as a GitHub Actions workflow with configurable parameters (branches, directories, patch generation), producing a structured summary.

**Related**: FRD-ci-integration

### [REQ-10] Virtual Provides Resolution

The scanner must detect and resolve virtual provides (e.g., `docker-api = 1.52` provided by the docker package), using them to validate API compatibility.

**Related**: FRD-virtual-provides

---

## 5. Traceability Matrix

| Requirement | Feature (FRD) | ADR | Task | Agent | Prompt |
|-------------|---------------|-----|------|-------|--------|
| REQ-1 | FRD-spec-parsing | ADR-0001, ADR-0005 | 001 | scanner-analyzer | analyze-specs |
| REQ-2 | FRD-gomod-analysis | -- | 002 | scanner-analyzer | analyze-upstream |
| REQ-3 | FRD-tarball-analysis | ADR-0002 | 003 | scanner-analyzer | analyze-upstream |
| REQ-4 | FRD-dual-version | ADR-0003 | 004 | scanner-orchestrator | scan-branch |
| REQ-5 | FRD-api-constellation | ADR-0003 | 005 | conflict-detector | detect-conflicts |
| REQ-6 | FRD-deduplication | -- | 006 | conflict-detector | detect-conflicts |
| REQ-7 | FRD-security | ADR-0004 | 007 | security-auditor | audit-security |
| REQ-8 | FRD-output | -- | 008 | scanner-orchestrator | -- |
| REQ-9 | FRD-ci-integration | -- | 009 | scanner-orchestrator | -- |
| REQ-10 | FRD-virtual-provides | -- | 005 | scanner-analyzer | analyze-upstream |

---

## 6. Assumptions and Constraints

### Assumptions

- Branch repositories (`photon-{branch}/SPECS`) are available on the local filesystem
- Upstream clones are in `photon-upstreams/photon-{branch}/clones/`
- PRN (Package Report) files provide authoritative package-to-clone mapping
- Source tarballs in `photon_sources/1.0/` and `SOURCES_NEW/` are trusted archives
- Go module paths can be mapped to Photon package names via `gomod-package-map.csv`
- Docker SDK-to-API version mapping is maintained in `docker-api-version-map.csv`

### Constraints

- **Language**: C11 with json-c (performance-critical, no runtime dependencies)
- **Security**: No shell interpolation, no predictable temp files, no unchecked allocations
- **Compatibility**: Must build on Photon OS with gcc, cmake, json-c-devel
- **Performance**: Full 7-branch scan must complete within CI timeout (120 minutes)
- **Read-only**: Scanner never modifies original spec files or branch repositories
- **Deterministic**: Same inputs produce same outputs (no randomness, no network calls)

---

**Document Version**: 1.0
**Status**: Ready for Implementation
