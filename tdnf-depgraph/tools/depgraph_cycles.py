#!/usr/bin/env python3
"""Cycle detection post-step for tdnf-depgraph artifacts.

Reads a v1 dependency-graph JSON, augments it with ``sccs[]``, ``cycles[]``,
and ``cycle_summary{}``, and rewrites it as schema v2.

Algorithm: iterative Tarjan SCC over the union of ``requires`` and
``buildrequires`` edges (``conflicts`` excluded), followed by a shortest
representative cycle per SCC via BFS within the SCC's induced subgraph.
Determinism: every collection is sorted by node name (with id as tie-break)
before emission, so two runs over the same input produce byte-identical
output.

Reference: ``tdnf-depgraph/specs/features/cycle-detection.md``.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import sys
from typing import Dict, List, Optional, Set, Tuple

SCHEMA_VERSION = 2
CYCLES_ENGINE = "tarjan-py-v1"
# Edge types considered for cycle detection. "conflicts" is excluded per
# ADR-0003. Any unrecognised type is ignored.
CYCLE_EDGE_TYPES = ("buildrequires", "requires")


# ----- I/O helpers ---------------------------------------------------------

def load_input(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_preq(path: Optional[str]) -> Set[str]:
    """Return the set of pre-staged package names from data/builder-pkg-preq.json.

    The file's schema is undocumented and may vary across branches, so we
    walk the JSON and collect every string-typed leaf into the set. Missing
    files, parse errors, or non-JSON content cause a warning to stderr and
    return an empty set (every cycle then classifies as ``bootstrap_resolved
    = False``, the conservative default per ADR-0005).
    """
    if not path:
        return set()
    if not os.path.exists(path):
        print(f"WARN: preq file not found: {path}", file=sys.stderr)
        return set()
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"WARN: failed to parse preq file {path}: {exc}", file=sys.stderr)
        return set()
    out: Set[str] = set()

    def walk(x):
        if isinstance(x, str):
            out.add(x)
        elif isinstance(x, dict):
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)

    walk(data)
    return out


def write_output(path: str, d: dict) -> None:
    """Write JSON in the same compact style the C extension produces."""
    with open(path, "w", encoding="utf-8") as f:
        json.dump(d, f, separators=(",", ":"), ensure_ascii=False, sort_keys=False)


# ----- Graph construction --------------------------------------------------

def _basename_no_spec(repo: str) -> str:
    if not repo:
        return ""
    b = os.path.basename(repo)
    if b.endswith(".spec"):
        b = b[: -len(".spec")]
    return b


def build_adjacency(
    d: dict,
) -> Tuple[
    Dict[int, List[int]],
    Dict[Tuple[int, int], Set[str]],
    Dict[int, dict],
    Dict[int, str],
]:
    """Build the cycle-detection adjacency over (requires, buildrequires).

    Returns ``(adj_union, typed_edges, nodes_by_id, name_by_id)``:

    * ``adj_union[v]`` is the sorted list of successor ids reachable via at
      least one cycle-relevant edge type. Each successor appears at most
      once even if multiple edge types connect ``v`` to it.
    * ``typed_edges[(a, b)]`` is the set of edge types observed for that
      ordered pair (may contain both ``"buildrequires"`` and ``"requires"``).
    * ``nodes_by_id`` and ``name_by_id`` index the node list.

    Neighbour lists are sorted by (name, id) so that downstream BFS and SCC
    iteration are deterministic.
    """
    nodes_by_id: Dict[int, dict] = {n["id"]: n for n in d.get("nodes", [])}
    name_by_id: Dict[int, str] = {
        nid: (n.get("name") or "") for nid, n in nodes_by_id.items()
    }

    typed_edges: Dict[Tuple[int, int], Set[str]] = collections.defaultdict(set)
    adj_set: Dict[int, Set[int]] = collections.defaultdict(set)

    for e in d.get("edges", []):
        etype = e.get("type")
        if etype not in CYCLE_EDGE_TYPES:
            continue
        a, b = e["from"], e["to"]
        typed_edges[(a, b)].add(etype)
        adj_set[a].add(b)

    def sort_key(nid: int) -> Tuple[str, int]:
        return (name_by_id.get(nid, ""), nid)

    adj_union: Dict[int, List[int]] = {
        v: sorted(succs, key=sort_key) for v, succs in adj_set.items()
    }
    for nid in nodes_by_id:
        adj_union.setdefault(nid, [])

    return adj_union, dict(typed_edges), nodes_by_id, name_by_id


# ----- Tarjan SCC (iterative) ---------------------------------------------

def tarjan_scc_iterative(
    adj: Dict[int, List[int]], node_ids: List[int]
) -> List[List[int]]:
    """Iterative Tarjan SCC.

    ``node_ids`` is the ordered list of ids from which to start DFS roots.
    Returns one list per SCC in DFS finish order. Singleton SCCs are
    included; callers filter self-loop singletons via the typed-edges map.

    The implementation is iterative so that deep dependency chains do not
    exceed Python's default recursion limit (sys.getrecursionlimit() == 1000).
    """
    index_of: Dict[int, int] = {}
    lowlink: Dict[int, int] = {}
    on_stack: Set[int] = set()
    stack: List[int] = []
    sccs: List[List[int]] = []
    counter = 0

    for start in node_ids:
        if start in index_of:
            continue
        # Call frame = (v, iterator over adj[v]).
        index_of[start] = counter
        lowlink[start] = counter
        counter += 1
        stack.append(start)
        on_stack.add(start)
        call_stack: List[Tuple[int, "collections.abc.Iterator[int]"]] = [
            (start, iter(adj.get(start, [])))
        ]

        while call_stack:
            v, it = call_stack[-1]
            advanced = False
            for w in it:
                if w not in index_of:
                    index_of[w] = counter
                    lowlink[w] = counter
                    counter += 1
                    stack.append(w)
                    on_stack.add(w)
                    call_stack.append((w, iter(adj.get(w, []))))
                    advanced = True
                    break
                if w in on_stack and index_of[w] < lowlink[v]:
                    lowlink[v] = index_of[w]
            if advanced:
                continue
            # No more successors of v -- finalize.
            if lowlink[v] == index_of[v]:
                comp: List[int] = []
                while True:
                    w = stack.pop()
                    on_stack.discard(w)
                    comp.append(w)
                    if w == v:
                        break
                sccs.append(comp)
            call_stack.pop()
            if call_stack:
                parent_v = call_stack[-1][0]
                if lowlink[v] < lowlink[parent_v]:
                    lowlink[parent_v] = lowlink[v]
    return sccs


# ----- Representative-cycle BFS -------------------------------------------

def shortest_cycle_through(
    v0: int,
    scc_set: Set[int],
    adj: Dict[int, List[int]],
    name_by_id: Dict[int, str],
) -> Optional[List[int]]:
    """Shortest cycle starting and ending at ``v0`` within ``scc_set``.

    Returns the cycle as ``[v0, s, ..., u, v0]`` (first node repeated at end)
    or ``None`` if no such cycle exists (only possible if the caller passes a
    singleton SCC without a self-loop, which they should not).

    Tie-break for equal-length candidates: lexicographic order of the
    name-tuple along the path.
    """
    best: Optional[List[int]] = None

    for s in adj.get(v0, []):
        if s not in scc_set:
            continue
        if s == v0:
            cand = [v0, v0]
        else:
            parent: Dict[int, Optional[int]] = {s: None}
            found_u: Optional[int] = None
            queue = collections.deque([s])
            while queue and found_u is None:
                u = queue.popleft()
                for w in adj.get(u, []):
                    if w not in scc_set:
                        continue
                    if w == v0:
                        found_u = u
                        break
                    if w not in parent:
                        parent[w] = u
                        queue.append(w)
            if found_u is None:
                continue
            path_su: List[int] = []
            cur: Optional[int] = found_u
            while cur is not None:
                path_su.append(cur)
                cur = parent[cur]
            path_su.reverse()
            cand = [v0] + path_su + [v0]

        if best is None or len(cand) < len(best):
            best = cand
        elif len(cand) == len(best):
            cand_key = tuple(name_by_id.get(i, "") for i in cand)
            best_key = tuple(name_by_id.get(i, "") for i in best)
            if cand_key < best_key:
                best = cand

    return best


# ----- Edge-type classification -------------------------------------------

def classify_cycle_edge_types(
    path: List[int], typed_edges: Dict[Tuple[int, int], Set[str]]
) -> List[str]:
    """Return one edge-type label per hop of the cycle path.

    When both ``buildrequires`` and ``requires`` connect two consecutive
    nodes, ``buildrequires`` is preferred (more restrictive constraint).
    """
    out: List[str] = []
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        types = typed_edges.get((a, b), set())
        if "buildrequires" in types:
            out.append("buildrequires")
        elif "requires" in types:
            out.append("requires")
        else:
            # Should not happen given CYCLE_EDGE_TYPES filter in build_adjacency.
            out.append("unknown")
    return out


def cycle_category(edge_types: List[str], length: int) -> str:
    if length == 1:
        return "self-loop"
    if all(t == "buildrequires" for t in edge_types):
        return "buildrequires"
    if all(t == "requires" for t in edge_types):
        return "requires"
    return "mixed"


# ----- Bootstrap-resolved classification ----------------------------------

def is_bootstrap_resolved(
    member_ids: List[int],
    nodes_by_id: Dict[int, dict],
    preq: Set[str],
) -> bool:
    """An SCC is bootstrap-resolved iff every member's name OR base-package
    (basename of ``repo`` with ``.spec`` stripped) is in the pre-stage set.
    """
    if not preq:
        return False
    for nid in member_ids:
        n = nodes_by_id.get(nid, {})
        name = n.get("name") or ""
        base = _basename_no_spec(n.get("repo") or "")
        if name not in preq and base not in preq:
            return False
    return True


# ----- Top-level cycle computation ----------------------------------------

def compute_sccs_and_cycles(
    adj: Dict[int, List[int]],
    typed_edges: Dict[Tuple[int, int], Set[str]],
    nodes_by_id: Dict[int, dict],
    name_by_id: Dict[int, str],
    preq: Set[str],
) -> Tuple[List[dict], List[dict]]:
    """Run Tarjan + representative-cycle BFS over the cycle-relevant subgraph.

    SCC iteration and ``cycles[]`` emission are sorted by the
    lexicographically-smallest member name (then size) for determinism.
    """

    def sort_key(nid: int) -> Tuple[str, int]:
        return (name_by_id.get(nid, ""), nid)

    sorted_ids = sorted(nodes_by_id.keys(), key=sort_key)
    raw_sccs = tarjan_scc_iterative(adj, sorted_ids)

    # Self-loops on singleton SCCs are detected via the typed-edges map.
    self_loops: Set[int] = {a for (a, b) in typed_edges if a == b}

    eligible: List[List[int]] = []
    for scc in raw_sccs:
        if len(scc) >= 2:
            eligible.append(scc)
        elif len(scc) == 1 and scc[0] in self_loops:
            eligible.append(scc)

    def scc_sort_key(scc: List[int]) -> Tuple[str, int]:
        sm = sorted(scc, key=sort_key)
        return (name_by_id.get(sm[0], ""), len(scc))

    eligible.sort(key=scc_sort_key)

    sccs_out: List[dict] = []
    cycles_out: List[dict] = []

    for idx, scc in enumerate(eligible, start=1):
        sorted_members = sorted(scc, key=sort_key)
        scc_set = set(scc)
        scc_id = f"scc-{idx:03d}"

        types_present: Set[str] = set()
        for (a, b), tset in typed_edges.items():
            if a in scc_set and b in scc_set:
                types_present.update(t for t in tset if t in CYCLE_EDGE_TYPES)

        bootstrap = is_bootstrap_resolved(sorted_members, nodes_by_id, preq)

        sccs_out.append(
            {
                "id": scc_id,
                "size": len(scc),
                "members": sorted_members,
                "names": [name_by_id.get(i, "") for i in sorted_members],
                "edge_types_present": sorted(types_present),
                "bootstrap_resolved": bootstrap,
            }
        )

        v0 = sorted_members[0]
        if len(scc) == 1 and scc[0] in self_loops:
            path: Optional[List[int]] = [v0, v0]
        else:
            path = shortest_cycle_through(v0, scc_set, adj, name_by_id)
        if path is None:
            continue

        edge_types = classify_cycle_edge_types(path, typed_edges)
        length = len(path) - 1
        cycles_out.append(
            {
                "id": f"cyc-{idx:03d}",
                "scc_id": scc_id,
                "category": cycle_category(edge_types, length),
                "length": length,
                "path_ids": path,
                "path_names": [name_by_id.get(i, "") for i in path],
                "edge_types": edge_types,
                "bootstrap_resolved": bootstrap,
                "representative": True,
                "scc_size": len(scc),
            }
        )

    return sccs_out, cycles_out


def make_summary(cycles: List[dict]) -> dict:
    return {
        "total": len(cycles),
        "buildrequires": sum(1 for c in cycles if c["category"] == "buildrequires"),
        "requires": sum(1 for c in cycles if c["category"] == "requires"),
        "mixed": sum(1 for c in cycles if c["category"] == "mixed"),
        "self_loops": sum(1 for c in cycles if c["category"] == "self-loop"),
        "bootstrap_resolved": sum(1 for c in cycles if c["bootstrap_resolved"]),
        "unresolved": sum(1 for c in cycles if not c["bootstrap_resolved"]),
    }


# ----- Schema v2 augmentation ---------------------------------------------

def augment_v2(
    d: dict,
    sccs: List[dict],
    cycles: List[dict],
    flavor: str,
    specsdir_meta: str,
) -> dict:
    """Mutate ``d`` in place into v2: bump metadata.schema_version, add new
    metadata fields, append top-level sccs / cycles / cycle_summary.

    v1 keys retain their position and value (Python dicts preserve insertion
    order, so assigning to an existing key keeps it where it is).
    """
    md = d.get("metadata") or {}
    md["schema_version"] = SCHEMA_VERSION
    md["flavor"] = flavor
    md["specsdir"] = specsdir_meta
    md["cycles_engine"] = CYCLES_ENGINE
    d["metadata"] = md
    d["sccs"] = sccs
    d["cycles"] = cycles
    d["cycle_summary"] = make_summary(cycles)
    return d


# ----- CLI -----------------------------------------------------------------

def run(
    input_path: str,
    preq_path: Optional[str],
    flavor: str,
    specsdir_meta: str,
) -> dict:
    """Pure-data entry point used by tests; does not write to disk."""
    d = load_input(input_path)
    preq = load_preq(preq_path)
    adj, typed_edges, nodes_by_id, name_by_id = build_adjacency(d)
    sccs, cycles = compute_sccs_and_cycles(
        adj, typed_edges, nodes_by_id, name_by_id, preq
    )
    augment_v2(d, sccs, cycles, flavor, specsdir_meta)
    return d


def emit_summary_line(d: dict) -> str:
    md = d.get("metadata", {})
    cs = d.get("cycle_summary", {})
    return (
        f"cyc-engine: branch={md.get('branch', '')} "
        f"flavor={md.get('flavor', '')} "
        f"sccs={len(d.get('sccs', []))} "
        f"cycles={cs.get('total', 0)} "
        f"br={cs.get('buildrequires', 0)} "
        f"self={cs.get('self_loops', 0)} "
        f"unresolved={cs.get('unresolved', 0)} "
        f"bootstrap={cs.get('bootstrap_resolved', 0)}"
    )


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(
        description="Cycle detection post-step for tdnf-depgraph artifacts."
    )
    p.add_argument(
        "--input",
        required=True,
        help="Path to v1 dependency-graph JSON; rewritten in place as v2.",
    )
    p.add_argument(
        "--preq",
        default=None,
        help="Path to data/builder-pkg-preq.json from the same branch (optional).",
    )
    p.add_argument(
        "--flavor",
        default="",
        help="Flavor token; empty string for the base scan.",
    )
    p.add_argument(
        "--specsdir-meta",
        default="SPECS",
        help="Human-readable overlay descriptor for metadata.specsdir.",
    )
    args = p.parse_args(argv)

    d = run(args.input, args.preq, args.flavor, args.specsdir_meta)
    write_output(args.input, d)
    print(emit_summary_line(d), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
