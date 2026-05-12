# ADR-0003: Tarjan SCC + Shortest Representative Cycle per SCC

**Date**: 2026-05-13
**Status**: Accepted

## Context

The cycle pass must produce, for each emitted JSON, both a structural view of cyclic dependencies (which packages are entangled) and a concrete actionable view (a specific chain of edges illustrating the cycle). Two algorithmic families dominate:

- **Strongly-connected-component (SCC) decomposition** — Tarjan or Kosaraju — finds every set of mutually-reachable nodes in O(V+E). Any SCC of size ≥ 2 contains at least one cycle. A self-loop edge `(v, v)` is a cycle on a singleton SCC.
- **Elementary cycle enumeration** — Johnson's algorithm — enumerates *every* simple cycle in time bounded by O((V+E) · (C+1)) where C is the number of elementary cycles. C can be exponential in V even for modest graphs.

Photon graphs run ~1,500–2,000 nodes / ~10,000 edges per (branch, flavor). Worst-case Johnson on a densely-cyclic SCC would be unacceptable; on the typical Photon graph it would be fine, but we cannot guarantee bounds without per-graph profiling.

## Decision Drivers

- **Bounded runtime.** The detection step must complete deterministically in well under a second per graph, regardless of graph topology.
- **Actionable output.** A maintainer reading the Actions summary needs at least one concrete cycle path per problematic component — not just a set of node names.
- **Determinism.** AC-2 in the PRD requires byte-identical `cycles[]` / `sccs[]` output across two runs of the same input. This rules out algorithms whose output depends on hash iteration order.
- **No external dependencies.** Python stdlib only ([ADR-0001](0001-cycle-detection-in-python-postprocess.md)).

## Considered Options

### Option 1: Johnson's algorithm — enumerate every elementary cycle

**Pros:** Complete view of every distinct cycle.
**Cons:** Exponential worst case. Output size unbounded. Reviewer drowns in cycles when SCCs are large. Determinism requires careful node ordering. Not justified at Photon scale, where one cycle per problematic component is enough to motivate a fix.

### Option 2: Tarjan SCC only — no cycle paths

Report SCCs as `{size, members}` without producing any concrete cycle.

**Pros:** Cheapest. Deterministic.
**Cons:** Reviewer cannot read the Actions summary and immediately see *which* dependency edges form the cycle. The PRD G5 success metric ("a reviewer can determine whether any unresolved buildrequires cycle exists by reading the Actions run summary alone") is unmet.

### Option 3 (Chosen): Tarjan SCC + one shortest representative cycle per non-trivial SCC

Run Tarjan to find SCCs. For every SCC of size ≥ 2 (and every self-loop), compute the shortest cycle through any node of that SCC via BFS restricted to the SCC's induced subgraph. Emit:

- One entry per SCC in `sccs[]` (size, members, edge types observed, bootstrap-resolved flag).
- One entry per representative cycle in `cycles[]` (ordered node path, edge types, length, category, bootstrap-resolved, `scc_id`, `representative: true`).
- `scc_size` field tells the consumer how many additional non-representative cycles exist in the same SCC — without us enumerating them.

**Pros:**
- Bounded runtime: Tarjan O(V+E), BFS O(V'+E') per SCC where V'/E' are SCC-local.
- Actionable: every cyclic SCC contributes one concrete cycle path.
- Deterministic with explicit tie-breaks (below).

**Cons:**
- A reviewer who wants to see *every* cycle in a large SCC has to either trace edges manually or run a separate tool. Acceptable: such SCCs are rare in package graphs and indicate a much larger structural problem that one cycle path will already motivate.

## Decision

Use **Tarjan SCC + shortest representative cycle per SCC via BFS**. Specifically:

1. **SCC pass.** Iterative Tarjan over the directed graph filtered by edge category (`buildrequires`, `requires`, `mixed`). Tarjan is iterative — recursion depth can exceed Python's default limit on degenerate inputs.
2. **Representative selection.** For each SCC of size ≥ 2:
   - Sort SCC members lexicographically by node *name* (not id).
   - Starting from the lexicographically smallest member `v0`, BFS within the SCC to find the shortest path that returns to `v0`. Tie-break BFS frontier expansion by node name (sorted) so the BFS itself is deterministic.
   - The returned path is the representative cycle for that SCC.
3. **Self-loops.** Treated as singleton SCCs in their own right; the cycle is `[v, v]`, length 1.
4. **Categorization.** A cycle is `buildrequires` if every edge in its representative path is `buildrequires`; `requires` if every edge is `requires`; `mixed` otherwise; `self-loop` for length-1 cycles. SCCs whose induced subgraph has more than one edge type are summarized in `sccs[i].edge_types_present`.
5. **Bootstrap classification.** Deferred to [ADR-0005](0005-bootstrap-resolved-classification.md).
6. **Determinism.** Members in `sccs[].members`, `sccs[].names`, and `cycles[]` ordering are all sorted by name (then id as final tie-break). Two runs of the same input must produce byte-identical JSON.

## Consequences

- Output size is bounded: at most one cycle entry per SCC + one per self-loop. Typical Photon scans produce 0 cycles; pathological branches produce O(SCC count) entries, not O(elementary-cycle count).
- A future enhancement could emit additional non-representative cycles per SCC behind a workflow input, without changing the schema's existing fields.
- The `representative: true` boolean and `scc_size` integer together let downstream tooling distinguish "this is *the* cycle" from "this is one of N cycles in a big SCC, look closer".
- Algorithm pseudocode is captured in [`../features/cycle-detection.md`](../features/cycle-detection.md) for implementers.
