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

- Runs **weekly** (Monday 03:00 UTC) or on-demand via `workflow_dispatch`.
- Inputs:
  - `branches` (default: `3.0,4.0,5.0,6.0,common,master,dev`).
  - `fail_on_buildrequires_cycle` (default: `false`). When `true`, the run fails if any unresolved `buildrequires` cycle is detected across all emitted artifacts. The scheduled cron trigger never sets this, so the weekly scan stays observational.
- Uses a **self-hosted runner** on Photon OS (requires `tdnf`, `cmake`, `gcc`, `jq`).
- Builds tdnf with depgraph + specparse C extensions.
- Clones each `vmware/photon` branch (sparse checkout, `SPECS/` only).
- Discovers per-branch sub-release flavors dynamically (`SPECS/[0-9]+/`) and runs the C extension once per (branch, flavor) overlay.
- Runs the Python cycle pass ([`tools/depgraph_cycles.py`](tools/depgraph_cycles.py)) over every emitted JSON, rewriting it in place to schema v2 (`sccs` / `cycles` / `cycle_summary` / `metadata.flavor` / `metadata.cycles_engine`).
- Uploads all JSON files as a GitHub Actions artifact (90-day retention).
- Commits and pushes to `scans/`.

See [`specs/features/cycle-detection.md`](specs/features/cycle-detection.md) and [`specs/features/subrelease-flavors.md`](specs/features/subrelease-flavors.md) for the full functional specs, [`specs/adr/`](specs/adr/) for the design decisions, and [`specs/findings/`](specs/findings/) for empirical findings that re-anchored the acceptance criteria during implementation.

## Schema v2 (cycle detection)

PR #79 / #80 added a Python cycle pass that rewrites every emitted JSON to **schema v2**. v1 keys are preserved unchanged; v2 only adds new top-level keys. See [`specs/features/cycle-detection.md` §2.1](specs/features/cycle-detection.md) and [`specs/adr/0004-schema-v2-additive.md`](specs/adr/0004-schema-v2-additive.md) for the full reference.

Top-level additions:

| Key | Type | Notes |
|---|---|---|
| `metadata.schema_version` | int | `1` (v1) or `2` (post-cycle-pass). |
| `metadata.flavor` | string | `""` for base; numeric token for `SPECS/[0-9]+/` overlays. |
| `metadata.specsdir` | string | `"SPECS"` for base; `"SPECS+SPECS/<F>"` for overlays. |
| `metadata.cycles_engine` | string | Engine version tag, e.g. `"tarjan-py-v1"`. |
| `sccs[]` | list | One entry per non-trivial strongly-connected component: `{id, size, members, names, edge_types_present, bootstrap_resolved}`. |
| `cycles[]` | list | One **shortest representative** cycle per SCC: `{id, scc_id, category, length, path_ids, path_names, edge_types, bootstrap_resolved, representative, scc_size}`. |
| `cycle_summary{}` | dict | Aggregate counters: `{total, buildrequires, requires, mixed, self_loops, bootstrap_resolved, unresolved}`. |

Minimal v2 example (truncated):

```json
{
  "metadata": {
    "generator": "tdnf depgraph",
    "timestamp": "2026-05-13T11:58:09Z",
    "branch": "5.0",
    "schema_version": 2,
    "flavor": "91",
    "specsdir": "SPECS+SPECS/91",
    "cycles_engine": "tarjan-py-v1"
  },
  "node_count": 1822,
  "edge_count": 11240,
  "nodes": [...],
  "edges": [...],
  "sccs": [
    {"id": "scc-012", "size": 2,
     "members": [1043, 1057], "names": ["python3-py", "python3-pytest"],
     "edge_types_present": ["buildrequires"], "bootstrap_resolved": false}
  ],
  "cycles": [
    {"id": "cyc-012", "scc_id": "scc-012", "category": "buildrequires",
     "length": 2, "path_ids": [1043, 1057, 1043],
     "path_names": ["python3-py", "python3-pytest", "python3-py"],
     "edge_types": ["buildrequires", "buildrequires"],
     "bootstrap_resolved": false, "representative": true, "scc_size": 2}
  ],
  "cycle_summary": {
    "total": 14, "buildrequires": 1, "requires": 11, "mixed": 2,
    "self_loops": 0, "bootstrap_resolved": 0, "unresolved": 14
  }
}
```

Only one cycle per SCC is emitted (the BFS-shortest representative); `scc_size` and `members[]` tell consumers how many alternative cycles the SCC contains. Determinism is guaranteed across runs of the same input — see [`specs/features/cycle-detection.md` §2.5](specs/features/cycle-detection.md).

## Sub-release flavors

Photon 5.0 ships `SPECS/[0-9]+/` overlay directories (today: `SPECS/90`, `SPECS/91`; flavor `92` is hypothetical — see [`specs/findings/2026-05-13-upstream-no-spec92.md`](specs/findings/2026-05-13-upstream-no-spec92.md)). The workflow scans each overlay as a first-class flavor, emitting one JSON per (branch, flavor). Discovery is dynamic — adding `SPECS/92/` (or a `SPECS/N/` on any other branch) is picked up automatically with no code change. Full spec: [`specs/features/subrelease-flavors.md`](specs/features/subrelease-flavors.md).

**Filename convention.** Unflavored branches keep the v1 filename; numeric flavors gain a `-<flavor>-` suffix:

| Branch | Flavor | Filename |
|---|---|---|
| 5.0 | `""` (base) | `dependency-graph-5.0-<datetime>.json` |
| 5.0 | `90` | `dependency-graph-5.0-90-<datetime>.json` |
| 5.0 | `91` | `dependency-graph-5.0-91-<datetime>.json` |
| 5.0 | `92` *(when upstream adds it)* | `dependency-graph-5.0-92-<datetime>.json` |
| master / 3.0 / 4.0 / 6.0 / common / dev | `""` (base) | `dependency-graph-<branch>-<datetime>.json` (unchanged) |

Each emitted file carries `metadata.flavor` matching its overlay (`""` for base, numeric string otherwise) and `metadata.specsdir` describing the merged spec source (`"SPECS"` vs `"SPECS+SPECS/<F>"`).

## Consumer compatibility

Schema v2 is **additive**: every v1 key is preserved in name, position, and semantics. v1 readers continue to work without modification. v2-aware readers branch on `metadata.schema_version`.

Existing in-repo consumers (`gating-conflict-detection`, `package-classifier`, `snyk-analysis`, `upstream-source-code-dependency-scanner`, `photonos-package-report`) all iterate `tdnf-depgraph/scans/dependency-graph-<branch>-*.json` and parse the v1 fields they need; none require migration. The full migration table — including the snippet for base-only consumers that don't want to ingest per-flavor scans — lives at [`specs/features/subrelease-flavors.md` §2.5](specs/features/subrelease-flavors.md).

For a base-only consumer (drop every per-flavor scan):

```python
for path in glob("tdnf-depgraph/scans/dependency-graph-*.json"):
    with open(path) as f:
        d = json.load(f)
    # Base-only filter (v2-aware):
    if d.get("metadata", {}).get("flavor", "") != "":
        continue
    # ... existing logic ...
```

A consumer that wants every flavor needs no change; the existing glob naturally picks them up.

## Plans

| File | Description |
|---|---|
| [plan-tdnf-depgraph-c-extension.md](plan-tdnf-depgraph-c-extension.md) | Complete design for the native `tdnf depgraph` C extension |
| [plan-rpm-dependency-graph-via-tdnf.md](plan-rpm-dependency-graph-via-tdnf.md) | Analysis of tdnf's existing repoquery/solv capabilities and the external-script fallback plan |

## Related

- [vmware/tdnf](https://github.com/vmware/tdnf) - Tiny Dandified Yum, the Photon OS package manager
- [photon-gating-conflict-detection/](../photon-gating-conflict-detection/) - Supply chain gating agent and QUBO migration specs
- [Implementation Plan: QUBO-Formulated PQC Migration with Autoresearch](../photon-gating-conflict-detection/specs/) - The broader migration plan that consumes the dependency graph
