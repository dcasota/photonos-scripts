# ADR-0003: Single-Graph Dual-Pass Architecture for Version Analysis

**Date**: 2026-03-12
**Status**: Accepted

## Context

The upstream-source-code-dependency-scanner must analyze both the **current release** specs (from `SPECS/`) and the **latest upstream version** specs (from `SPECS_NEW/`) to detect API constellation conflicts. For example, Docker SDK v28.5.1 (current) may require API 1.52, while Docker SDK v29.1.0 (latest) requires API 1.53 -- introducing an upper-bound conflict if the engine only supports up to 1.52.

The dual-version analysis must:
- Parse both spec sets into a single dependency graph
- Distinguish current vs. latest nodes for cross-version comparison
- Detect new dependencies introduced in the latest version
- Detect API version constellation conflicts across versions
- Deduplicate common dependencies that appear in both versions

## Decision Drivers

- **Memory efficiency**: 7 branches × 2 versions × 2000+ packages = significant memory pressure
- **Query simplicity**: Conflict detection algorithms should traverse a single graph, not join across two
- **Deduplication**: Common dependencies between current and latest must not produce duplicate patches
- **Clarity**: The distinction between current and latest must be unambiguous throughout the pipeline
- **Extensibility**: Future addition of more version channels (e.g., "previous release") should be straightforward

## Considered Options

### Option 1: Single graph with node tagging (bIsLatest flag)

Parse both spec sets into the same `DepGraph`. Nodes from `SPECS_NEW/` are tagged with `bIsLatest = 1`. Edges reference nodes by index. Conflict detection traverses one graph and filters by the `bIsLatest` flag.

```c
/* In graph.h */
typedef struct {
    ...
    uint32_t bIsLatest;  /* 1 if from SPECS_NEW */
} GraphNode;

/* In main.c */
for (uint32_t i = dwLatestNodesStart; i < graph.dwNodeCount; i++)
    graph.pNodes[i].bIsLatest = 1;
```

**Pros**:
- Single graph traversal for all queries (no joins)
- Deduplication is natural: same target node for both current and latest edges
- Memory-efficient: one allocation for all nodes and edges
- Recording `dwLatestNodesStart` enables efficient current/latest partitioning
- Conflict detection compares edges from the same graph

**Cons**:
- Node names may collide (e.g., `docker-compose` exists in both SPECS/ and SPECS_NEW/)
- Must handle name collisions carefully during node lookup
- All graph algorithms must be aware of the `bIsLatest` flag

### Option 2: Separate graphs with cross-references

Maintain two independent `DepGraph` instances (current and latest). Cross-version analysis joins them by package name.

```c
DepGraph graphCurrent;
DepGraph graphLatest;
/* Cross-reference by name matching */
```

**Pros**:
- Clean separation: no name collision issues
- Each graph is independently consistent
- Simpler graph algorithms (no bIsLatest filtering needed)

**Cons**:
- Double memory usage for shared packages (most packages exist in both)
- Cross-version queries require O(n²) name-based joins
- Deduplication requires comparing across two graphs
- Edge indices are not comparable across graphs
- More complex API: every function needs `(graphCurrent, graphLatest)` parameters

### Option 3: Separate node ID spaces within one graph

Use a single graph but assign distinct ID ranges: nodes 0..N-1 for current, nodes N..M-1 for latest. No `bIsLatest` flag; the ID range determines version.

```c
#define LATEST_NODE_OFFSET 100000
/* Current: 0..99999, Latest: 100000..199999 */
```

**Pros**:
- Single graph traversal
- Clear partitioning by ID range
- No flag to check on every query

**Cons**:
- Wastes address space if ID ranges are oversized
- Magic constants in code (LATEST_NODE_OFFSET)
- Hard to extend to more than 2 version channels
- Breaks if node count exceeds the offset (fragile)
- Array-based storage would waste memory for sparse ID ranges

## Decision Outcome

**Chosen**: Option 1 -- Single graph with node tagging (`bIsLatest` flag).

The node tagging approach provides the best balance of memory efficiency, query simplicity, and extensibility. The `bIsLatest` flag adds only 4 bytes per node and enables O(1) version discrimination. The `dwLatestNodesStart` index enables efficient iteration over just current or just latest nodes.

Name collisions are handled naturally: `graph_find_node()` returns the first match, and cross-version comparison iterates from `dwLatestNodesStart` to find the latest counterpart by name. This is the approach already implemented in `main.c`.

## Consequences

### Positive

- Single graph allocation reduces memory pressure for large branch scans
- Conflict detection traverses one data structure with simple flag checks
- Deduplication is natural: edges from both versions target the same graph namespace
- `dwLatestNodesStart` enables efficient partitioning without flag scanning
- Adding a third version channel requires only a new flag (`bIsPrevious`) and start index

### Negative

- `graph_find_node()` must be aware of potential name duplicates
- Package name `foo` from SPECS/ and `foo` from SPECS_NEW/ create separate nodes
- All downstream consumers of the graph must understand the `bIsLatest` semantics
- Cross-version comparison requires matching nodes by name (not by index)

## References

- PRD: `specs/prd.md` -- REQ-4: Dual-Version Analysis
- PRD: `specs/prd.md` -- REQ-5: API Version Constellation Detection
- `src/graph.h` -- `GraphNode.bIsLatest` field definition
- `src/main.c` -- Phase 1b: Latest version node tagging logic
