# Architecture

## Overview

upstream-source-code-dependency-scanner is a standalone C program (~4400 LOC across 13 source files) that builds an enriched dependency graph for Photon OS packages. Unlike the existing [tdnf-depgraph](../tdnf-depgraph/) scanner (which patches tdnf itself and only sees spec-declared dependencies), this scanner also analyzes upstream source code to discover implicit API-level dependencies that specs fail to declare.

```
                ┌─────────────────────────────────────────────────────┐
                │        upstream-source-code-dependency-scanner       │
                │                                                     │
  SPECS/*.spec ─┤  Phase 1          Phase 2            Phase 3        │
                │  ┌──────────┐    ┌──────────────┐   ┌────────────┐  │─▶ SPECS_DEPFIX/
                │  │ spec     │    │ gomod        │   │ conflict   │  │   (patched specs)
                │  │ parser   │───▶│ analyzer     │──▶│ detector   │  │
                │  │          │    │ pyproject    │   │            │  │─▶ depfix-manifest.json
                │  │          │    │ analyzer     │   │ spec       │  │
                │  │          │    │ api_version  │   │ patcher    │  │─▶ dependency-graph.json
                │  └──────────┘    │ extractor    │   └────────────┘  │
                │                  └──────────────┘                   │
  clones/      ─┤      ▲                 ▲                            │
  (photon-      │      │                 │                            │
   upstreams)   │   graph.c         virtual_provides.c                │
                │   (shared data     (version comparison,             │
                │    structures)      edge resolution)                │
                └─────────────────────────────────────────────────────┘
```

## The Constellation Problem

A **constellation** is a group of packages that are tightly coupled through API contracts in their source code, but whose RPM spec files do not declare these relationships.

### Docker Constellation

The Docker ecosystem on Photon OS consists of:

```
┌────────────────┐     ┌────────────────┐     ┌────────────────┐
│ docker-compose │     │ docker (engine)│     │ containerd     │
│                │     │                │     │                │
│ go.mod:        │     │ config.go:     │     │ version.go:    │
│  docker v28.5  │────▶│  MinAPI=1.44   │     │  Version=2.0   │
│  (API 1.47)    │     │  MaxAPI=1.54   │     │                │
│                │     │                │     │                │
│ spec: 0 Req.   │     │ spec: Req:     │     │ spec: Req:     │
│ (MISSING!)     │     │  containerd    │     │  runc          │
└────────────────┘     │  systemd       │     └────────────────┘
                       └────────────────┘
```

When Docker Engine was upgraded from 24.x to 29.x, it raised `defaultMinAPIVersion` from `1.24` to `1.44`. The compose binary (compiled against docker client v24.0.5, speaking API 1.43) was rejected by the new engine. Since `docker-compose.spec` had zero `Requires:` lines, neither `tdnf` nor `rpm` could detect the incompatibility.

**What was needed in the spec files:**

```spec
# docker-compose.spec
Requires:  docker-engine >= 25.0    # from go.mod analysis

# docker.spec (%package engine)
Provides:  docker-api = 1.54        # from MaxAPIVersion constant
Provides:  docker-api-min = 1.44    # from defaultMinAPIVersion constant
```

The scanner detects this gap by tracing the dependency chain through the Go module graph and source constants.

## Source Modules

### Core Data Layer

| File | Purpose |
|------|---------|
| `graph.h` | All shared type definitions: `GraphNode`, `GraphEdge`, `VirtualProvide`, `SpecPatch`, `SpecPatchSet`, `ConflictRecord`, `DepGraph` |
| `graph.c` | Dynamic array management for nodes/edges/virtuals, linked-list management for patches/conflicts, name lookup, string conversion helpers |

The graph uses a flat array model (not adjacency lists) for cache-friendly iteration during the conflict detection pass:

```c
typedef struct {
    GraphNode      *pNodes;       // Dynamic array, grows by doubling
    uint32_t        dwNodeCount;
    GraphEdge      *pEdges;       // Dynamic array, grows by doubling
    uint32_t        dwEdgeCount;
    VirtualProvide *pVirtuals;    // Dynamic array
    uint32_t        dwVirtualCount;
    ConflictRecord *pConflicts;   // Linked list (append order)
    SpecPatchSet   *pPatchSets;   // Linked list (append order)
} DepGraph;
```

Each edge carries full provenance:

```c
typedef struct {
    uint32_t    dwFromIdx;        // Source node index
    uint32_t    dwToIdx;          // Target node index (UINT32_MAX if unresolved)
    EdgeType    nType;            // REQUIRES, BUILDREQUIRES, PROVIDES, ...
    EdgeSource  nSource;          // SPEC, GOMOD, PYPROJECT, API_CONSTANT
    ConstraintOp nConstraintOp;   // NONE, EQ, GE, GT, LE, LT
    char        szConstraintVer[64];
    char        szEvidence[512];  // Human-readable origin
    char        szTargetName[256];// Raw name before resolution
} GraphEdge;
```

### Phase 1: Spec Parsing

| File | Purpose |
|------|---------|
| `spec_parser.c/h` | RPM `.spec` file parser with macro expansion |

Walks the `SPECS/` directory tree, parsing each `.spec` file line by line with a section state machine. Extracts:

- **Name/Version/Release/Epoch** from the preamble
- **Subpackages** from `%package` directives (`%package engine` -> `docker-engine`, `%package -n foo` -> `foo`)
- **Dependencies** with version constraints: `Requires: containerd >= 1.5` -> edge with `CONSTRAINT_GE`, version `1.5`
- **Virtual provides**: `Provides: bundled(golang) = 1.21` -> `VirtualProvide` record
- **Macros**: `%define`, `%global` (up to 64 definitions), `%{name}`, `%{version}`, `%{?dist}` expansion

Sections like `%prep`, `%build`, `%install`, `%check`, `%files`, `%changelog` are skipped (they don't contain dependency metadata).

### Phase 2: Upstream Source Analysis

#### 2a. Go Module Analyzer

| File | Purpose |
|------|---------|
| `gomod_analyzer.c/h` | Parse `go.mod` files from upstream clones |
| `gomod_to_package_map.c/h` | Map Go module paths to Photon package names |
| `prn_parser.c/h` | Parse PRN package report files for package-to-clone mapping |

For each clone in `photon-upstreams/{branch}/clones/` that contains a `go.mod`:

1. **Identify the Photon package**: Try direct directory name match, then read the `module` line from `go.mod` and look up in the package map, then try `docker-{dirname}` prefix
2. **Parse require directives**: Both `require ( ... )` blocks and single-line `require` statements
3. **Map modules to packages**: `github.com/docker/docker v28.5.2` -> Photon package `docker` (via `gomod-package-map.csv`, longest-prefix match)
4. **Create inferred edges**: `docker-compose --[GOMOD_REQUIRES]--> docker (>= 28.0)`

The major version is extracted from the Go module version for the constraint (e.g., `v28.5.1` -> `>= 28.0`).

#### 2b. Python Dependency Analyzer

| File | Purpose |
|------|---------|
| `pyproject_analyzer.c/h` | Parse Python packaging metadata |

Checks each clone for `setup.cfg`, `setup.py`, or `pyproject.toml` (in priority order):

- **setup.cfg**: Looks for `[options]` section, extracts `install_requires` with continuation lines
- **setup.py**: Scans for `install_requires=[...]` and extracts quoted package names
- **pyproject.toml**: Looks for `dependencies = [...]` in `[project]` section

Python dependency names are resolved to Photon packages by trying: exact name, `python3-{name}`, `python-{name}`, and underscore-to-hyphen variants.

#### 2c. API Version Extractor

| File | Purpose |
|------|---------|
| `api_version_extractor.c/h` | Extract version constants from source files |

Uses declarative rules from `data/api-version-patterns.csv`:

```csv
docker,daemon/config/config.go,MaxAPIVersion = ",provides,docker-api
docker,daemon/config/config.go,defaultMinAPIVersion = ",provides,docker-api-min
```

For each rule: locate the file in the clone, search for the literal pattern prefix, extract the value between the following double quotes. Creates `VirtualProvide` records that enable API-level conflict detection.

#### Virtual Provides Resolution

| File | Purpose |
|------|---------|
| `virtual_provides.c/h` | Resolve unresolved edges, version comparison |

After Phase 2, some edges have `dwToIdx == UINT32_MAX` (target not found as a concrete node). `virtual_resolve_edges()` walks these and matches `szTargetName` against virtual provides, resolving them to the provider's node index.

The `version_compare()` function splits versions on `.` and `-`, comparing each component numerically when both sides are digits, lexicographically otherwise. Handles `v`-prefixed versions.

### Phase 3: Conflict Detection & Spec Patching

#### Conflict Detector

| File | Purpose |
|------|---------|
| `conflict_detector.c/h` | Compare declared vs. inferred dependencies |

Three detection passes:

1. **Missing dependency detection**: For each `EDGE_SRC_GOMOD` or `EDGE_SRC_PYPROJECT` edge, check if a corresponding `EDGE_SRC_SPEC` edge already exists from the same source node. If not, create a `SpecPatch` with `severity = CRITICAL`.

2. **Missing virtual provides**: For each `VirtualProvide`, check if the provider's spec already has a matching `PROVIDES` edge. If not, create a `SpecPatch` with `severity = IMPORTANT`.

3. **API version conflicts**: For virtual provides containing "api" in the name, check whether consumer edges have version constraints satisfied by the provided range. Creates `ConflictRecord` entries with status `ok` or `BROKEN`.

#### Spec Patcher

| File | Purpose |
|------|---------|
| `spec_patcher.c/h` | Generate modified spec files |

For each `SpecPatchSet`:

1. Copy the original spec to `SPECS_DEPFIX/{branch}/{package}/{specname}`
2. Read into a line array, identify the correct insertion point:
   - `Requires:` -> after the last existing `Requires:` in the matching section
   - `Provides:` -> after the last existing `Provides:` in the matching section
   - Fallback: after `%description` of the target section
3. Insert a marked block:
   ```spec
   # --- begin upstream-dep-scanner additions (auto-generated) ---
   # Source: go.mod: github.com/docker/docker v28.5.1
   Requires:       docker >= 28.0
   # --- end upstream-dep-scanner additions ---
   ```
4. Prepend a `%changelog` entry documenting each addition

### Output Layer

| File | Purpose |
|------|---------|
| `json_output.c/h` | Write the enriched dependency graph as JSON |
| `manifest_writer.c/h` | Write the depfix manifest JSON |

Both use `libjson-c` for pretty-printed JSON output.

The **dependency graph JSON** includes all nodes, edges (with provenance), virtual provides, and detected conflicts. Compatible with the existing `tdnf-depgraph` JSON format but extended with `source`, `constraint_op`, `constraint_ver`, and `evidence` fields on edges.

The **depfix manifest JSON** is the actionable output: lists every patched spec with its original path, patched path, additions with evidence, and a severity summary.

## Data Flow

```
vmware/photon SPECS/                  photon-upstreams/{branch}/clones/
       │                                       │
       ▼                                       ▼
  ┌─────────────┐                    ┌───────────────────┐
  │ spec_parser │                    │ gomod_analyzer    │
  │             │                    │ pyproject_analyzer│
  │ 2011 nodes  │                    │ api_version_ext.  │
  │ 9923 edges  │                    │                   │
  │ (SPEC src)  │                    │ +190 edges (GOMOD)│
  └──────┬──────┘                    │ +262 virtuals     │
         │                           └────────┬──────────┘
         │                                    │
         ▼                                    ▼
  ┌──────────────────────────────────────────────┐
  │              DepGraph (merged)                │
  │  2011 nodes, 10113 edges, 262 virtuals       │
  └──────────────────┬───────────────────────────┘
                     │
                     ▼
           ┌─────────────────┐
           │ virtual_provides │  resolve UINT32_MAX edges
           │ (362 resolved)   │
           └────────┬────────┘
                    │
                    ▼
           ┌─────────────────┐
           │ conflict_detector│  compare SPEC vs GOMOD/PYPROJECT
           │ (120 issues)     │
           └────────┬────────┘
                    │
            ┌───────┴───────┐
            ▼               ▼
    ┌──────────────┐  ┌──────────────┐
    │ spec_patcher │  │manifest_writer│
    │ 41 specs     │  │ + json_output │
    └──────────────┘  └──────────────┘
            │               │
            ▼               ▼
      SPECS_DEPFIX/    depfix-manifest.json
                       dependency-graph.json
```

## Build System

CMake-based, single target, minimal dependencies:

- **C11 standard** with `-Wall -Wextra -D_GNU_SOURCE -Wno-format-truncation`
- **libjson-c** (found via `pkg-config`) -- the only external dependency
- No libsolv, no tdnf, no PCRE -- fully standalone

## CI Integration

The scanner is designed to run **after** `package-report.yml` (which produces the `photon-upstreams/{branch}/clones/` directory). The workflow:

1. Builds from source (~5 seconds)
2. Sparse-clones `vmware/photon` SPECS per branch
3. Runs all three phases
4. Uploads JSON files and `SPECS_DEPFIX/` as artifacts

It can also run standalone (Phase 1 only) when upstream clones are not available.

## Extending

### Adding Go module mappings

Edit `data/gomod-package-map.csv`:

```csv
github.com/new/module,photon-package-name
```

Longest-prefix match is used, so `github.com/docker/docker` matches both `github.com/docker/docker` and `github.com/docker/docker/pkg/archive`.

### Adding API version patterns

Edit `data/api-version-patterns.csv`:

```csv
package-name,relative/path/to/file.go,LiteralPrefixToSearch = ",provides,virtual-name
```

The extractor finds the literal string prefix in the file, then extracts the value between the next pair of double quotes.

### Adding new language analyzers

Follow the pattern of `gomod_analyzer.c` or `pyproject_analyzer.c`:

1. Create `{lang}_analyzer.c/h` with an `{lang}_analyze_clones()` function
2. Iterate clones, detect the language's dependency file (e.g., `Cargo.toml`, `package.json`)
3. Parse dependencies and map to Photon packages
4. Add edges with `EDGE_SRC_{LANG}` (extend the `EdgeSource` enum in `graph.h`)
5. Wire into `main.c` between Phase 2b and Phase 2c
