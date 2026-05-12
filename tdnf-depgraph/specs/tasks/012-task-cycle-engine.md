# Task 012: Python Cycle Engine (`tools/depgraph_cycles.py`)

**Complexity**: High
**Dependencies**: None
**Status**: Pending
**Requirement**: PRD G1, G3, G4 (AC-1, AC-2, AC-5)
**Feature**: [FRD-cycle-detection](../features/cycle-detection.md)
**ADRs**: [0001](../adr/0001-cycle-detection-in-python-postprocess.md), [0003](../adr/0003-tarjan-scc-plus-representative.md), [0004](../adr/0004-schema-v2-additive.md), [0005](../adr/0005-bootstrap-resolved-classification.md)

---

## Description

Implement the Python post-step that reads a v1 dependency-graph JSON, computes cycles, and rewrites the same file as schema v2. Single file, Python 3 stdlib only.

## Scope

- New file: `tdnf-depgraph/tools/depgraph_cycles.py`.
- Reads one JSON path; writes the same path with v2 fields populated.
- Accepts these arguments:
  - `--input <path>` (required)
  - `--preq <path>` to `data/builder-pkg-preq.json` (optional; absence → warn, default every SCC `bootstrap_resolved: false`)
  - `--flavor <string>` (default `""`) used to populate `metadata.flavor`
  - `--specsdir-meta <string>` (default `"SPECS"`) used to populate `metadata.specsdir` overlay descriptor
- Implements:
  1. Iterative Tarjan SCC on the union of `requires` + `buildrequires` edges (`conflicts` excluded).
  2. Self-loop detection.
  3. Per-SCC representative cycle via BFS within the induced subgraph, starting from the lexicographically-smallest member name (ties: id).
  4. Edge-class categorization (`buildrequires` / `requires` / `mixed` / `self-loop`).
  5. Bootstrap-resolved classification with sub-package name resolution from `nodes[i].repo` basename.
  6. Schema v2 emission per [FRD-cycle-detection §2.1](../features/cycle-detection.md).
- Prints a one-line stderr summary the workflow captures for the step summary: `cyc-engine: <branch> <flavor> sccs=<N> cycles=<N> br=<N> self=<N> unresolved=<N> bootstrap=<N>`.

## Implementation Notes

- Determinism is non-negotiable. Sort every collection (adjacency neighbour lists, SCC members, BFS frontier, cycles output) before emission.
- Tarjan must be iterative — Photon graphs can have chains exceeding Python's default recursion limit.
- Edge lookup must distinguish edge type per `(from, to)` pair. Multiple edges of different types between the same pair are possible (rare); preserve the most-restrictive edge type per direction for the union-graph adjacency, but also keep a typed-edge index for categorization.
- Sub-package name resolution: extract base package name from `nodes[i].repo` as `os.path.basename(repo).removesuffix('.spec')`. Use this *plus* `nodes[i].name` when checking against the pre-stage set.

## Acceptance Criteria

- [ ] **AC-1 hook.** Running on the 2026-05-11 master fixture (task 016) produces at least one cycle with `category == "buildrequires"`, `bootstrap_resolved == false`, and `path_names` containing both `libselinux` and a `python3-*` node.
- [ ] **AC-2 (determinism).** Running twice on the same input produces byte-identical output (excluding the trailing newline / final whitespace if any). A unit test enforces this.
- [ ] **AC-5 (schema).** Output has `metadata.schema_version == 2`. Every v1 key from the input file is preserved unchanged in name, position, and value.
- [ ] Empty case: a hand-built acyclic graph produces `sccs == []`, `cycles == []`, all `cycle_summary` counters zero.
- [ ] Self-loop case: a graph with a `(v, v)` edge produces a length-1 cycle with `category: "self-loop"`.
- [ ] Mixed-edge case: an SCC with both `requires` and `buildrequires` edges produces `sccs[i].edge_types_present == ["buildrequires", "requires"]` (sorted) and a `category: "mixed"` cycle when the representative path crosses both types.
- [ ] Missing `--preq` argument: prints a warning to stderr, defaults `bootstrap_resolved` to `false` everywhere.

## Testing Requirements

Unit tests live in `tdnf-depgraph/tests/test_depgraph_cycles.py`. Run with `python3 -m unittest discover -s tdnf-depgraph/tests`. Required cases:

- [ ] `test_acyclic_graph` — empty `sccs[]`/`cycles[]`, zero summary.
- [ ] `test_simple_2cycle_buildrequires` — `A -[br]-> B -[br]-> A` produces `category: "buildrequires"`.
- [ ] `test_mixed_cycle` — `A -[br]-> B -[req]-> A` produces `category: "mixed"`.
- [ ] `test_self_loop` — `A -[req]-> A` produces `category: "self-loop"`, length 1.
- [ ] `test_deterministic_output` — two runs produce identical JSON.
- [ ] `test_bootstrap_resolved_all_members` — every SCC member in pre-stage set → `bootstrap_resolved: true`.
- [ ] `test_bootstrap_resolved_partial` — one SCC member NOT in pre-stage set → `bootstrap_resolved: false`.
- [ ] `test_subpackage_basename_resolution` — node `libselinux-python3` with `repo: "libselinux/libselinux-python3.spec"` checks against both `"libselinux-python3"` and `"libselinux"` (basename of repo dir is `libselinux`, but the rule is `.spec` basename; verify both name candidates are considered).
- [ ] `test_iterative_tarjan_deep` — chain of 5000 nodes does not blow Python's recursion limit.

## Out of Scope

- Workflow YAML integration (task 014).
- Step-summary writing (task 014).
- Exit-code logic (task 015).
- Test fixture check-in (task 016).
