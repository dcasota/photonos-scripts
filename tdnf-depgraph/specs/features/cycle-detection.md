# Feature Requirement Document: Cycle Detection

**Feature ID**: FRD-cycle-detection
**Related PRD Requirements**: G1, G3, G4, G5, AC-1, AC-2, AC-5, AC-6, AC-7
**Status**: Specified — Phase 4
**Last Updated**: 2026-05-13

---

## 1. Feature Overview

### Purpose

Detect strongly-connected components and circular dependencies in every dependency-graph JSON the workflow produces. Distinguish actionable cycles from cycles that the Photon bootstrap pre-stages (and therefore tolerates). Surface the result inline in the GitHub Actions step summary and optionally fail the run on unresolved buildrequires cycles.

### Value Proposition

The 2026-05-12 `libselinux ↔ python3` incident demonstrated that cycle-causing edges live in the artifact today but are invisible without a detection step. This feature converts the raw graph into an actionable report: a maintainer reading the Actions summary sees the cycle, its category, and whether the bootstrap already resolves it.

### Success Criteria

See PRD acceptance criteria AC-1, AC-2, AC-5, AC-6, AC-7. In brief:

- Regression run on the 2026-05-11 master snapshot produces a `libselinux`/`python3-*` cycle entry with `category: "buildrequires"`, `bootstrap_resolved: false`.
- Two runs of the detector over the same input JSON produce byte-identical `sccs[]` / `cycles[]` arrays.
- `metadata.schema_version == 2` on every emitted file; v1 keys unchanged.
- `fail_on_buildrequires_cycle=true` causes non-zero exit iff at least one unresolved buildrequires cycle exists.
- Step summary surfaces cycle counts and up to ten representative cycle paths per (branch, flavor).

---

## 2. Functional Requirements

### 2.1 Schema v2 reference

Per [ADR-0004](../adr/0004-schema-v2-additive.md). The cycle pass is the sole writer of these fields and emits them on **every** produced JSON, even when no cycles exist (empty arrays, zero counters).

```jsonc
{
  "metadata": {
    "schema_version": 2,                         // bumped from 1
    "branch": "5.0",                             // v1, unchanged
    "specsdir": "SPECS+SPECS/91",                // v1 key, semantics extended to describe overlays
    "generated_at": "2026-05-18T03:00:00Z",      // v1, unchanged
    "flavor": "91",                              // v2, "" for base scans
    "cycles_engine": "tarjan-py-v1"              // v2, algorithm identifier
  },

  "node_count": 1820,                            // v1
  "edge_count": 9412,                            // v1
  "nodes":  [ /* unchanged from v1 */ ],
  "edges":  [ /* unchanged from v1 */ ],

  "sccs": [                                      // v2
    {
      "id": "scc-001",                           // stable per file, "scc-NNN" zero-padded to 3 digits
      "size": 4,
      "members": [1155, 1158, 247, 466],         // sorted by member name then id
      "names":   ["libselinux", "libselinux-python3",
                  "python3-pip", "selinux-python"],
      "edge_types_present": ["buildrequires", "requires"],
      "bootstrap_resolved": false
    }
  ],

  "cycles": [                                    // v2
    {
      "id": "cyc-001",                           // stable per file, "cyc-NNN" zero-padded
      "scc_id": "scc-001",
      "category": "buildrequires",               // "buildrequires" | "requires" | "mixed" | "self-loop"
      "length": 3,
      "path_ids":   [1155, 458, 1158, 1155],     // first node repeats at end
      "path_names": ["libselinux", "python3-devel",
                     "libselinux-python3", "libselinux"],
      "edge_types": ["buildrequires", "requires", "requires"],
      "bootstrap_resolved": false,
      "representative": true,                    // always true in v2 (one per SCC)
      "scc_size": 4                              // mirrors sccs[scc_id].size for convenience
    }
  ],

  "cycle_summary": {                             // v2
    "total":              3,
    "buildrequires":      1,
    "requires":           2,
    "mixed":              0,
    "self_loops":         0,
    "bootstrap_resolved": 1,
    "unresolved":         2
  }
}
```

**Field types and invariants:**

| Field | Type | Notes |
|---|---|---|
| `metadata.schema_version` | integer | `2` for v2-emitted files. Absent → v1 (legacy). |
| `metadata.flavor` | string | `""` for base. Otherwise the numeric flavor token (e.g. `"91"`). |
| `metadata.specsdir` | string | Overlay descriptor: `"SPECS"` or `"SPECS+SPECS/<N>"`. Human-readable; not parsed by consumers. |
| `metadata.cycles_engine` | string | Algorithm identifier. Current value `"tarjan-py-v1"`. Bumped per [ADR-0004](../adr/0004-schema-v2-additive.md) when the algorithm itself evolves, separately from the schema version. |
| `sccs[i].id` | string | `"scc-001"` upward, zero-padded to 3 digits, in emission order. |
| `sccs[i].members` / `.names` | parallel arrays | Sorted by name (then id). Same length as `size`. |
| `sccs[i].edge_types_present` | string array | Sorted; deduplicated. |
| `cycles[i].path_ids` / `.path_names` | parallel arrays | First node repeats at end. `len == length + 1`. |
| `cycles[i].edge_types` | string array | `len == length`. `edge_types[i]` is the edge from `path[i]` to `path[i+1]`. |
| `cycles[i].representative` | boolean | Always `true` in v2. Reserved for future non-representative cycle enumeration. |
| `cycle_summary.total` | integer | Equals `len(cycles)`. |
| `cycle_summary.bootstrap_resolved + unresolved` | integer sum | Equals `total`. |

**Empty case:** when the graph is acyclic, `sccs == []`, `cycles == []`, and `cycle_summary` is `{total: 0, buildrequires: 0, requires: 0, mixed: 0, self_loops: 0, bootstrap_resolved: 0, unresolved: 0}`.

### 2.2 Algorithm — Tarjan SCC + BFS representative

Per [ADR-0003](../adr/0003-tarjan-scc-plus-representative.md). Pseudocode:

```
Input: graph G = (V, E), edge[e].type ∈ {requires, buildrequires, conflicts}

Step 1. Build adjacency lists for cycle detection.
  Exclude edges of type "conflicts" from cycle detection entirely.
  adj_all[v]    = { w : (v, w) in E, type ≠ conflicts }
  adj_br[v]     = { w : (v, w) in E, type == buildrequires }

Step 2. Run iterative Tarjan SCC on adj_all.
  Detect SCCs over the union graph (br + requires).
  Also detect self-loops: if w ∈ adj_all[v] and w == v, emit a singleton-SCC self-loop.

Step 3. For each SCC of size >= 2 (and each self-loop):
  Sort members lexicographically by node name (ties broken by id).
  Pick v0 = first member.
  BFS within the SCC-induced subgraph of adj_all from v0, seeking the shortest path
    that returns to v0. Tie-break frontier expansion by node name.
  The returned path is the representative cycle.

Step 4. Classify each representative cycle:
  edge_types[i] = type of edge (path[i] -> path[i+1])
  If all edge_types == "buildrequires": category = "buildrequires"
  Else if all edge_types == "requires": category = "requires"
  Else if length == 1: category = "self-loop"  (already detected at step 2)
  Else: category = "mixed"

Step 5. Bootstrap classification.
  See section 2.4.

Step 6. Emit:
  sccs[]   — one per non-trivial SCC + one per self-loop.
  cycles[] — one representative cycle per SCC.
  Sort sccs by id (= emission order = source-graph DFS order from Tarjan, stable).
  Sort cycles by scc_id.
```

**Complexity.** Step 2 is O(V + E). Step 3 totals O(sum-over-SCCs of (V_scc + E_scc)) ≤ O(V + E). Worst case: linear in graph size.

**Recursion safety.** Implement Tarjan iteratively. Python's default recursion limit (1000) is insufficient for ~1,800-node graphs with long dependency chains.

### 2.3 Edge-class semantics

| Edge type | Cycle detection input | Notes |
|---|---|---|
| `requires` | Yes | Runtime dependencies. Cycles here are usually tolerable (RPM resolves runtime cycles at install time) but reported as informational. |
| `buildrequires` | Yes | Build-time dependencies. Cycles here are the actionable class — they prevent the build from proceeding without bootstrap pre-staging. |
| `conflicts` | No | Excluded from cycle detection. A "cycle" of conflicts is not a dependency loop. |
| Any other type | No | Reserved. Treated as `conflicts` (excluded) until an ADR specifies otherwise. |

A cycle is classified `mixed` when its representative path crosses both `requires` and `buildrequires` edges. The buildrequires-only sub-portion of a mixed cycle is not necessarily a build-order problem, so [ADR-0006](../adr/0006-fail-on-buildrequires-cycle-input.md) excludes `mixed` from the fail gate.

### 2.4 Bootstrap-resolved classification

Per [ADR-0005](../adr/0005-bootstrap-resolved-classification.md). Operationally:

1. Read `data/builder-pkg-preq.json` from the branch's sparse checkout. Parse as a JSON document; collect every string-typed leaf into a set `S` of pre-staged package names.
2. For each SCC, build the set of relevant names:
   - The node's `name` field, AND
   - The base package name derived from `nodes[i].repo`. The current `repo` value is the `.spec` relative path (e.g. `"libselinux/libselinux.spec"`). The base package name is the basename without `.spec` extension — for the example, `"libselinux"`.
3. The SCC is `bootstrap_resolved: true` iff, for every member, at least one of `{name, base_package}` ∈ S. Otherwise `false`.
4. Each cycle inherits `bootstrap_resolved` from its containing SCC.
5. If `data/builder-pkg-preq.json` is missing, unparseable, or empty, S = ∅; the pass logs a warning to `$GITHUB_STEP_SUMMARY` and every SCC is `bootstrap_resolved: false`.

**Sub-package example.** Node `libselinux-python3` (`repo: "libselinux/libselinux-python3.spec"`) — after the 2026-05-12 fix — has base package `libselinux-python3`. If `data/builder-pkg-preq.json` contains `"libselinux"` but not `"libselinux-python3"`, the node is **not** pre-staged. Conversely, the node `libselinux` itself is pre-staged. This matters: the post-fix scan finds the libselinux SCC `bootstrap_resolved: false` only if `libselinux-python3` participates and is unlisted; if the SCC after the fix has no members outside `{libselinux, libsepol, ...}`, it is `bootstrap_resolved: true`.

### 2.5 Determinism

AC-2 in the PRD requires byte-identical output across two runs of the same input.

- `sccs[].members`, `sccs[].names`, `sccs[].edge_types_present`: sorted by name (then id), then deduplicated.
- `sccs[]`: emitted in Tarjan finish order (stable for a fixed input adjacency).
- `cycles[]`: sorted by `scc_id`.
- BFS within an SCC: frontier expansion sorted by neighbour name; ties broken by id.
- `cycle_summary` counters: computed from `cycles[]`; deterministic by construction.

Adjacency-list construction MUST sort neighbour lists before the algorithm begins. The implementer of T1 in the Phase 5 task breakdown is responsible for unit tests covering AC-2.

### 2.6 Step-summary contribution

For each (branch, flavor) processed by the workflow, append to `$GITHUB_STEP_SUMMARY`:

1. A row in the cycle summary table:
   ```
   | Branch | Flavor | Specs | Nodes | Edges | Cycles | BR-Cycles | Self-loops | Unresolved | Bootstrap-Resolved |
   |--------|--------|-------|-------|-------|--------|-----------|------------|------------|--------------------|
   | 5.0    | 91     | 1820  | 1820  | 9412  | 3      | 1         | 0          | 2          | 1                  |
   ```
2. A fenced block listing up to the first **10** cycles, in `cycles[]` order:
   ```
   ### 5.0 / 91 — representative cycles (3 found, showing 3)
   - cyc-001 (buildrequires, unresolved): libselinux → python3-devel → libselinux-python3 → libselinux
   - cyc-002 (requires, bootstrap-resolved): libsepol → libselinux → libsepol
   - cyc-003 (mixed, unresolved): … (truncated paths longer than 8 hops are shown as "a → b → … → z")
   ```

Paths longer than 8 hops are truncated to first-3 / ellipsis / last-2 to keep the summary readable.

---

## 3. Out of Scope

- Enumeration of all elementary cycles per SCC (Johnson's). One representative per SCC only; `scc_size` flags the truncation.
- Visualization (Graphviz, mermaid).
- Cycle detection on the `conflicts` edge subset.
- Auto-suggest of fixes (e.g. recommending additions to `data/builder-pkg-preq.json`).

---

## 4. Implementation Pointers

- Cycle pass lives at `tdnf-depgraph/tools/depgraph_cycles.py` (per [ADR-0001](../adr/0001-cycle-detection-in-python-postprocess.md)). Python 3 stdlib only.
- Workflow integration: `.github/workflows/depgraph-scan.yml` gains a `Detect cycles` step after graph generation, before artifact upload. See task T1 in `specs/tasks/0001-task-cycles-post-step.md`.
- Fixture for AC-1 regression: `tdnf-depgraph/tests/fixtures/dependency-graph-master-20260511_091039.v1.json` (committed) — see Phase 1 PRD open question Q1.
