# tdnf-depgraph: RPM Dependency Graph Export for Photon OS

## Problem Statement

The Sovereign Supply Chain Safety initiative for VMware Photon OS requires a complete RPM dependency graph to formulate a QUBO-optimized post-quantum cryptography (PQC) migration plan. The QUBO objective function depends on three inputs:

1. **A cryptographic vulnerability inventory** per package (from Snyk Code scans)
2. **A cost vector** per package (LOC, crypto call density, reverse dependency fan-out)
3. **A directed dependency graph** encoding which packages depend on which others, including `Requires`, `BuildRequires`, `Conflicts`, `Obsoletes`, `Recommends`, and other RPM relationship types

Without the dependency graph, the QUBO formulation cannot enforce its constraint term - penalizing migration of a package before its dependencies are migrated - and cannot compute the minimum simultaneous migration set (SC-1) or the bootstrap signing ordering (SC-3).

## Initial Approach: External Scripts Parsing .spec Files

The initial plan was to write external Python/Shell scripts that:

- Parse `BuildRequires` and `Requires` fields from `.spec` files in the Photon OS build tree
- Construct a directed acyclic graph stored as `dependency-graph.json`
- Use `tdnf repoquery --json` to supplement with runtime dependency data

This approach works but has significant limitations:

- **Macro expansion**: `.spec` files contain RPM macros (`%{_libdir}`, `%{version}`, conditional `%if` blocks) that are not expanded without running `rpmbuild`. Raw string parsing produces incorrect or incomplete dependencies.
- **Virtual provides**: A `.spec` file may declare `Provides: libssl.so.3()(64bit)` but the consuming package's `Requires` uses the virtual name. Resolving these requires rebuilding the provides-to-package index that libsolv already maintains.
- **Sub-packages**: A single `.spec` file may produce multiple binary RPMs via `%package` directives. Each sub-package has its own `Requires`/`Provides`. Parsing these correctly requires reimplementing RPM's sub-package logic.
- **Consistency**: The parsed graph may diverge from what `tdnf install/update` actually resolves, because the solver uses the binary repodata (from `primary.xml.gz`), not the `.spec` source.

See [plan-rpm-dependency-graph-via-tdnf.md](plan-rpm-dependency-graph-via-tdnf.md) for the full analysis of tdnf's existing query capabilities.

## Preferred Approach: Native C Extension in tdnf

Analysis of the [vmware/tdnf](https://github.com/vmware/tdnf) source code reveals that **the complete dependency graph is already materialized in memory** inside the libsolv `Pool` object after `TDNFOpenHandle()` calls `pool_createwhatprovides()`. The graph exists - it simply has no command to export it.

A native `tdnf depgraph` command, implemented as a ~505-line C extension following tdnf's existing three-layer architecture (solv / client / CLI), would:

- Walk the libsolv Pool in a single process with zero serialization overhead
- Resolve every `Requires` dependency via the `FOR_PROVIDES` macro - the identical resolution path used by `tdnf install`
- Include `BuildRequires` natively from source solvables when the source repo is enabled (no `.spec` parsing needed)
- Export the graph as JSON (for QUBO consumption), DOT (for Graphviz visualization), or adjacency list
- Compute reverse dependency counts per node (directly feeding the QUBO cost vector)

See [plan-tdnf-depgraph-c-extension.md](plan-tdnf-depgraph-c-extension.md) for the complete design, pseudocode, type definitions, and build integration details.

## Desired Outcome

A `tdnf depgraph` command that can be invoked as:

```bash
# Per-branch from vmware/photon spec files (authoritative source)
git clone --depth 1 --branch 5.0 https://github.com/vmware/photon.git /tmp/ph5
tdnf depgraph --json --setopt specsdir=/tmp/ph5/SPECS --setopt branch=5.0

git clone --depth 1 --branch 6.0 https://github.com/vmware/photon.git /tmp/ph6
tdnf depgraph --json --setopt specsdir=/tmp/ph6/SPECS --setopt branch=6.0

# All branches
for b in 3.0 4.0 5.0 6.0 common master dev; do
  git clone --depth 1 --branch $b https://github.com/vmware/photon.git /tmp/ph-$b
  tdnf depgraph --json --setopt specsdir=/tmp/ph-$b/SPECS --setopt branch=$b \
    > dependency-graph-$b-$(date -u +%Y%m%d_%H%M%S).json
done

# From binary repos via --releasever (3.0-5.0 have Broadcom repos)
tdnf depgraph --json --releasever=4.0 --setopt branch=4.0

# Graphviz visualization with branch label
tdnf depgraph dot --setopt specsdir=/tmp/ph5/SPECS --setopt branch=5.0 \
  | dot -Tsvg -o photon5-deps.svg
```

The JSON output feeds directly into the `qubo_builder.py` script from the [QUBO PQC migration implementation plan](../photon-gating-conflict-detection/specs/), replacing the need for any external dependency extraction tooling.

## Priority

| Priority | Approach | Status |
|---|---|---|
| **1 (preferred)** | Native C extension in vmware/tdnf | Design complete, ready for implementation |
| 2 (fallback) | `tdnf repoquery --json` via external scripts | Viable but limited (no BuildRequires, subprocess overhead) |
| 3 (deprecated) | `.spec` file parsing | Superseded by analysis showing tdnf already has the data |

## Implementation

The `src/` directory contains the complete, ready-to-integrate C source code:

| File | tdnf target path | Description |
|---|---|---|
| [src/solv_tdnfdepgraph.c](src/solv_tdnfdepgraph.c) | `solv/tdnfdepgraph.c` | Pool walk, edge resolution via `FOR_PROVIDES` (~250 LOC) |
| [src/client_depgraph.c](src/client_depgraph.c) | `client/depgraph.c` | API entry point, refresh, delegation (~50 LOC) |
| [src/client_specparse.c](src/client_specparse.c) | `client/specparse.c` | Spec file parser: walks SPECS/, expands macros, builds graph (~430 LOC) |
| [src/cli_depgraph.c](src/cli_depgraph.c) | `tools/cli/lib/depgraph.c` | CLI handler, JSON/DOT/adjacency output, `--setopt specsdir=` (~290 LOC) |
| [src/tdnftypes_depgraph.h](src/tdnftypes_depgraph.h) | append to `include/tdnftypes.h` | Struct and enum definitions |
| [src/tdnf_depgraph_api.h](src/tdnf_depgraph_api.h) | append to `include/tdnf.h` | Public API declaration |
| [src/tdnfcli_depgraph.h](src/tdnfcli_depgraph.h) | append to `include/tdnfcli.h` | CLI command declaration |
| [src/solv_prototypes_depgraph.h](src/solv_prototypes_depgraph.h) | append to `solv/prototypes.h` | Solv layer prototypes |
| [src/INTEGRATION.md](src/INTEGRATION.md) | - | Step-by-step integration guide for all existing file modifications |

## Scans

The `scans/` directory stores per-branch timestamped dependency graph JSON files.
Filename convention: `dependency-graph-<branch>-<YYYYMMDD_HHMMSS>.json`

```
scans/
  dependency-graph-3.0-20260310_153748.json   # 16656 nodes  (Photon OS 3.0)
  dependency-graph-4.0-20260310_153748.json   #  2418 nodes  (Photon OS 4.0)
  dependency-graph-5.0-20260310_153748.json   #  2564 nodes  (Photon OS 5.0)
  dependency-graph-6.0-20260310_153748.json   #  3111 nodes  (Photon OS 6.0, local build)
  dependency-graph-master-20260310_153748.json
  dependency-graph-dev-20260310_153748.json
  dependency-graph-common-20260310_153748.json
```

Each JSON file contains a `metadata.branch` field identifying the source branch.

### Data Source

All branches are parsed from `.spec` files in `vmware/photon` via `--setopt specsdir=`.
The spec parser recognizes: `Requires`, `BuildRequires`, `Conflicts`, `BuildConflicts`,
`Obsoletes`, `Recommends`, `Suggests`, `Supplements`, `Enhances`,
`Requires(pre)`, `Requires(post)`, `Requires(preun)`, `Requires(postun)`,
`Provides`, and `%package` subpackages with `%{name}`/`%{version}` macro expansion.

| Branch | Specs | Nodes | Edges |
|--------|-------|-------|-------|
| 3.0 | ~906 | ~1781 | ~7526 |
| 4.0 | ~1035 | ~1838 | ~8097 |
| 5.0 | ~1072 | ~2004 | ~9341 |
| 6.0 | ~1094 | ~1982 | ~9149 |
| common | ~6 | ~1 | ~0 |
| master | ~1091 | ~1961 | ~8967 |
| dev | ~1091 | ~1961 | ~8967 |

### GitHub Actions Workflow

The `.github/workflows/depgraph-scan.yml` workflow:

- Runs **weekly** (Monday 03:00 UTC) or on-demand via `workflow_dispatch`
- Accepts `branches` input (default: `3.0,4.0,5.0,6.0,common,master,dev`)
- Uses a **self-hosted runner** on Photon OS (requires `tdnf`, `cmake`, `gcc`)
- Builds tdnf with depgraph + specparse C extensions
- Clones each `vmware/photon` branch (sparse checkout, SPECS/ only)
- Generates `dependency-graph-<branch>-<datetime>.json` per branch
- Uploads all JSON files as a GitHub Actions artifact (90-day retention)
- Commits and pushes to `scans/`

## Plans

| File | Description |
|---|---|
| [plan-tdnf-depgraph-c-extension.md](plan-tdnf-depgraph-c-extension.md) | Complete design for the native `tdnf depgraph` C extension |
| [plan-rpm-dependency-graph-via-tdnf.md](plan-rpm-dependency-graph-via-tdnf.md) | Analysis of tdnf's existing repoquery/solv capabilities and the external-script fallback plan |

## Related

- [vmware/tdnf](https://github.com/vmware/tdnf) - Tiny Dandified Yum, the Photon OS package manager
- [photon-gating-conflict-detection/](../photon-gating-conflict-detection/) - Supply chain gating agent and QUBO migration specs
- [Implementation Plan: QUBO-Formulated PQC Migration with Autoresearch](../photon-gating-conflict-detection/specs/) - The broader migration plan that consumes the dependency graph
