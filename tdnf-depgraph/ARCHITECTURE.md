# Architecture

## Overview

`tdnf-depgraph` exports the RPM dependency graph that libsolv materializes in memory after `pool_createwhatprovides()`. The exporter is implemented as a small C extension to [vmware/tdnf](https://github.com/vmware/tdnf), patched on top of the system-installed tdnf version at workflow time. The resulting `tdnf depgraph --json` command emits a graph of `Requires` / `BuildRequires` / `Conflicts` edges over every spec/binary node, which the [Dependency Graph Scan](../.github/workflows/depgraph-scan.yml) workflow runs once per Photon branch (and, going forward, once per branch *flavor* — see [ADR-0002](specs/adr/0002-subrelease-overlay-flavors.md)).

```
                ┌──────────────────────────────────────────────────────────┐
                │              Dependency Graph Scan workflow              │
                │                                                          │
  vmware/photon │  ┌────────────────┐    ┌────────────────┐                │
  SPECS/**      ├─▶│ tdnf-src clone │───▶│ depgraph C ext │                │─▶ tdnf-depgraph/scans/
  per branch    │  │ + patch (src/) │    │ (libsolv walk) │                │   dependency-graph-
  (+flavor)     │  └────────────────┘    └───────┬────────┘                │   <branch>[-<flavor>]-
                │                                ▼                         │   <datetime>.json
                │  builder-pkg-preq.json   ┌────────────────┐               │
                │  (bootstrap pre-stages)─▶│ cycle pass     │ (planned)     │─▶ GitHub Actions
                │                          │ Tarjan SCC +   │               │   artifact
                │                          │ representative │               │
                │                          │ cycle per SCC  │               │
                │                          └───────┬────────┘               │
                │                                  ▼                        │
                │                          schema v2 JSON                   │
                └──────────────────────────────────────────────────────────┘
```

## Components

### `src/` — depgraph C extension

A ~500-line drop-in for vmware/tdnf, applied at workflow time after cloning tdnf at the runner's installed version (`tdnf --version`). The split mirrors tdnf's three-layer architecture:

| File | Layer | Responsibility |
|------|-------|----------------|
| `solv_tdnfdepgraph.c`, `solv_prototypes_depgraph.h` | solv  | Walk the libsolv `Pool`, resolve every dependency via `FOR_PROVIDES`, build the in-memory graph. |
| `client_depgraph.c`, `client_specparse.c`, `tdnf_depgraph_api.h` | client | Public API (`TDNFDepGraph`, `TDNFBuildDepGraphFromSpecs`), spec-tree mode used by the workflow. |
| `cli_depgraph.c`, `tdnfcli_depgraph.h` | CLI | `tdnf depgraph` subcommand and `--json` formatter. |
| `tdnftypes_depgraph.h` | types | `PTDNF_DEP_GRAPH` and friends, appended to `tdnftypes.h` at build time. |
| `INTEGRATION.md` | docs | How the workflow patches tdnf-src. |

Background and design rationale live in [plan-rpm-dependency-graph-via-tdnf.md](plan-rpm-dependency-graph-via-tdnf.md) and [plan-tdnf-depgraph-c-extension.md](plan-tdnf-depgraph-c-extension.md).

### `.github/workflows/depgraph-scan.yml` — orchestration

The active workflow at the repo root (`/.github/workflows/depgraph-scan.yml`) is the one GitHub Actions runs; the copy under `tdnf-depgraph/.github/workflows/` tracks the same content in-tree for review alongside the source it depends on. Per-branch (and, in the planned v2, per-flavor) the workflow:

1. Sparse-checks-out `SPECS/` from `vmware/photon` at the target branch.
2. Discovers sub-release directories (`SPECS/[0-9]+`, e.g. 5.0's `90 / 91 / 92`) and assembles an overlay tree per flavor.
3. Runs `tdnf depgraph --json --setopt specsdir=<overlay>` to produce one JSON per (branch, flavor).
4. (Planned — see [specs/](specs/)) Runs a Python cycle-detection post-step that rewrites each JSON with `sccs[]`, `cycles[]`, `cycle_summary{}`.
5. Uploads the result as the `dependency-graphs` artifact and commits it to `scans/`.

### `scans/` — accumulated artifacts

Append-only history of the workflow's output JSONs, one filename per (branch, flavor, timestamp). Consumers downstream (Snyk classifier, package report, gating-conflict detector) read from here. File naming is contractual; see [specs/features/subrelease-flavors.md](specs/features/subrelease-flavors.md) when it lands.

## Cycle Detection Pipeline

The cycle pass runs as a Python post-step after the C `tdnf depgraph` extension emits its v1 JSON. The pass rewrites each file in place as schema v2, with `sccs[]`, `cycles[]`, and `cycle_summary{}` populated. Architectural decisions are captured in the following ADRs:

| ADR | Decision |
|-----|----------|
| [ADR-0001](specs/adr/0001-cycle-detection-in-python-postprocess.md) | Detect cycles in a Python post-step, not in the C extension. |
| [ADR-0002](specs/adr/0002-subrelease-overlay-flavors.md) | Scan each `SPECS/[0-9]+/` as an overlay flavor (`SPECS/` + `SPECS/<N>/`, same-name wins). |
| [ADR-0003](specs/adr/0003-tarjan-scc-plus-representative.md) | Tarjan SCC + one shortest representative cycle per SCC via BFS. Deterministic tie-breaks on node name. |
| [ADR-0004](specs/adr/0004-schema-v2-additive.md) | Bump `metadata.schema_version` 1 → 2. Purely additive; every v1 key preserved. |
| [ADR-0005](specs/adr/0005-bootstrap-resolved-classification.md) | Classify each SCC against `data/builder-pkg-preq.json`; `bootstrap_resolved: true` iff every member is pre-staged. |
| [ADR-0006](specs/adr/0006-fail-on-buildrequires-cycle-input.md) | New workflow input `fail_on_buildrequires_cycle` (default `false`); only `bootstrap_resolved: false` buildrequires cycles trip the gate. |

## Spec-Driven Development

This subproject follows the same SDD methodology as the other initiatives in this repo (`upstream-source-code-dependency-scanner`, `vCenter-CVE-drift-analyzer`, `photon-gating-conflict-detection`, `photonos-package-report`, `docsystem`). All design changes flow through `specs/`:

- `specs/prd.md` — what we want and why.
- `specs/adr/NNNN-*.md` — irreversible architectural decisions, one per file.
- `specs/features/*.md` — feature-level reference docs (schemas, algorithms, contracts).
- `specs/tasks/NNN-task-*.md` — implementation breakdown with acceptance tests.

New work begins by writing the spec, gating implementation behind a merged spec PR. The first such work stream is **cycle detection in the dependency-graph artifact** — see `specs/prd.md` once Phase 1 lands.

## Open Initiatives

| Initiative | Phase | Spec | Status |
|---|---|---|---|
| Cycle detection (libselinux ↔ python3 class of bugs) | 0 — SDD scaffolding | this file + `specs/README.md` | complete |
| Cycle detection — PRD | 1 | `specs/prd.md` | complete |
| Cycle detection — ADRs 0001–0006 | 3 | `specs/adr/` | complete |
| Cycle detection — feature specs | 4 | `specs/features/` | pending |
| Cycle detection — task breakdown | 5 | `specs/tasks/0001-task-cycles-post-step.md` | pending |
| Cycle detection — implementation | 6 | per-task PRs | pending |
