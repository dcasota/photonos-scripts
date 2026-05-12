"""Unit tests for tdnf-depgraph/tools/depgraph_cycles.py.

Run from the repository root::

    python3 -m unittest discover -s tdnf-depgraph/tests
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent / "tools"
sys.path.insert(0, str(TOOLS))

import depgraph_cycles as dc  # noqa: E402


# ----- Test helpers --------------------------------------------------------

def make_v1(nodes, edges, branch="test"):
    return {
        "metadata": {
            "generator": "tdnf depgraph",
            "timestamp": "2026-05-13T00:00:00Z",
            "branch": branch,
        },
        "node_count": len(nodes),
        "edge_count": len(edges),
        "nodes": nodes,
        "edges": edges,
    }


def node(nid, name, repo=None):
    return {
        "id": nid,
        "name": name,
        "nevra": name,
        "arch": "x86_64",
        "evr": "",
        "repo": repo if repo is not None else f"{name}/{name}.spec",
        "reverse_dep_count": 0,
    }


def edge(a, b, t):
    return {"from": a, "to": b, "type": t}


def run_inmem(d, preq=None):
    adj, typed, nodes_by_id, name_by_id = dc.build_adjacency(d)
    sccs, cycles = dc.compute_sccs_and_cycles(
        adj, typed, nodes_by_id, name_by_id, preq or set()
    )
    return dc.augment_v2(
        dict(d), sccs, cycles, flavor="", specsdir_meta="SPECS"
    )


# ----- Tests ---------------------------------------------------------------

class TestAcyclic(unittest.TestCase):
    def test_acyclic_graph(self):
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B"), node(3, "C")],
            edges=[edge(1, 2, "requires"), edge(2, 3, "buildrequires")],
        )
        out = run_inmem(d)
        self.assertEqual(out["sccs"], [])
        self.assertEqual(out["cycles"], [])
        s = out["cycle_summary"]
        for k in (
            "total",
            "buildrequires",
            "requires",
            "mixed",
            "self_loops",
            "bootstrap_resolved",
            "unresolved",
        ):
            self.assertEqual(s[k], 0)


class TestSimpleCycle(unittest.TestCase):
    def test_simple_2cycle_buildrequires(self):
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B")],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 1, "buildrequires"),
            ],
        )
        out = run_inmem(d)
        self.assertEqual(len(out["cycles"]), 1)
        c = out["cycles"][0]
        self.assertEqual(c["category"], "buildrequires")
        self.assertEqual(c["path_names"], ["A", "B", "A"])
        self.assertEqual(c["length"], 2)
        self.assertEqual(c["edge_types"], ["buildrequires", "buildrequires"])
        self.assertTrue(c["representative"])
        self.assertEqual(c["scc_size"], 2)


class TestMixedCycle(unittest.TestCase):
    def test_mixed_cycle(self):
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B")],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 1, "requires"),
            ],
        )
        out = run_inmem(d)
        self.assertEqual(len(out["cycles"]), 1)
        c = out["cycles"][0]
        self.assertEqual(c["category"], "mixed")
        self.assertEqual(
            sorted(c["edge_types"]), ["buildrequires", "requires"]
        )
        scc = out["sccs"][0]
        self.assertEqual(
            scc["edge_types_present"], ["buildrequires", "requires"]
        )


class TestSelfLoop(unittest.TestCase):
    def test_self_loop(self):
        d = make_v1(
            nodes=[node(1, "A")],
            edges=[edge(1, 1, "requires")],
        )
        out = run_inmem(d)
        self.assertEqual(len(out["cycles"]), 1)
        c = out["cycles"][0]
        self.assertEqual(c["category"], "self-loop")
        self.assertEqual(c["length"], 1)
        self.assertEqual(c["path_ids"], [1, 1])
        self.assertEqual(out["sccs"][0]["size"], 1)


class TestDeterminism(unittest.TestCase):
    def test_deterministic_output(self):
        """Two runs over the same input produce identical sccs and cycles."""
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B"), node(3, "C"), node(4, "D")],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 3, "buildrequires"),
                edge(3, 1, "buildrequires"),
                edge(3, 4, "requires"),
                edge(4, 2, "requires"),
            ],
        )
        out1 = run_inmem(d)
        out2 = run_inmem(d)
        self.assertEqual(
            json.dumps(out1["sccs"], sort_keys=True),
            json.dumps(out2["sccs"], sort_keys=True),
        )
        self.assertEqual(
            json.dumps(out1["cycles"], sort_keys=True),
            json.dumps(out2["cycles"], sort_keys=True),
        )


class TestBootstrapResolved(unittest.TestCase):
    def test_bootstrap_resolved_all_members(self):
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B")],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 1, "buildrequires"),
            ],
        )
        out = run_inmem(d, preq={"A", "B"})
        self.assertTrue(out["cycles"][0]["bootstrap_resolved"])
        self.assertEqual(out["cycle_summary"]["bootstrap_resolved"], 1)
        self.assertEqual(out["cycle_summary"]["unresolved"], 0)

    def test_bootstrap_resolved_partial(self):
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B")],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 1, "buildrequires"),
            ],
        )
        out = run_inmem(d, preq={"A"})
        self.assertFalse(out["cycles"][0]["bootstrap_resolved"])
        self.assertEqual(out["cycle_summary"]["bootstrap_resolved"], 0)
        self.assertEqual(out["cycle_summary"]["unresolved"], 1)


class TestSubpackageResolution(unittest.TestCase):
    def test_subpackage_basename_resolution(self):
        """Pre-fix-style scenario: libselinux-python3 lives under
        libselinux.spec. With 'libselinux' (only) in preq, both nodes should
        be considered pre-staged via the base-package fallback."""
        d = make_v1(
            nodes=[
                node(1, "libselinux", repo="libselinux/libselinux.spec"),
                node(
                    2,
                    "libselinux-python3",
                    repo="libselinux/libselinux.spec",
                ),
            ],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 1, "requires"),
            ],
        )
        out = run_inmem(d, preq=set())
        self.assertFalse(out["cycles"][0]["bootstrap_resolved"])

        out = run_inmem(d, preq={"libselinux"})
        self.assertTrue(out["cycles"][0]["bootstrap_resolved"])


class TestIterativeTarjanDeep(unittest.TestCase):
    def test_iterative_tarjan_deep(self):
        """Chain of 2000 nodes -- exceeds Python's default recursion limit
        (1000), verifying the Tarjan implementation is iterative."""
        n = 2000
        nodes = [node(i, f"p{i:05d}") for i in range(n)]
        chain_edges = [edge(i, i + 1, "requires") for i in range(n - 1)]
        out_chain = run_inmem(make_v1(nodes=nodes, edges=chain_edges))
        self.assertEqual(out_chain["sccs"], [])

        cycle_edges = chain_edges + [edge(n - 1, 0, "requires")]
        out_cyc = run_inmem(make_v1(nodes=nodes, edges=cycle_edges))
        self.assertEqual(len(out_cyc["sccs"]), 1)
        self.assertEqual(out_cyc["sccs"][0]["size"], n)


class TestSchemaV2Preservation(unittest.TestCase):
    def test_v1_keys_preserved_and_v2_added(self):
        d = make_v1(nodes=[node(1, "A")], edges=[])
        out = run_inmem(d)
        md = out["metadata"]
        self.assertEqual(md["schema_version"], 2)
        self.assertEqual(md["cycles_engine"], "tarjan-py-v1")
        self.assertEqual(md["flavor"], "")
        self.assertEqual(md["specsdir"], "SPECS")
        # v1 keys preserved.
        self.assertEqual(md["generator"], "tdnf depgraph")
        self.assertEqual(md["timestamp"], "2026-05-13T00:00:00Z")
        self.assertEqual(md["branch"], "test")
        self.assertEqual(out["node_count"], 1)
        self.assertEqual(out["edge_count"], 0)
        self.assertEqual(len(out["nodes"]), 1)
        self.assertIn("sccs", out)
        self.assertIn("cycles", out)
        self.assertIn("cycle_summary", out)


class TestEndToEndIdempotent(unittest.TestCase):
    def test_byte_identical_after_two_runs(self):
        """First run rewrites v1 -> v2; second run on the v2 file produces
        the same bytes. Covers PRD AC-2."""
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B"), node(3, "C")],
            edges=[
                edge(1, 2, "buildrequires"),
                edge(2, 3, "buildrequires"),
                edge(3, 1, "buildrequires"),
            ],
        )
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "g.json"
            with open(p, "w", encoding="utf-8") as f:
                json.dump(d, f, separators=(",", ":"))

            dc.main(["--input", str(p)])
            content1 = p.read_bytes()

            dc.main(["--input", str(p)])
            content2 = p.read_bytes()

            self.assertEqual(content1, content2)


class TestConflictsExcluded(unittest.TestCase):
    def test_conflicts_edges_do_not_form_cycles(self):
        d = make_v1(
            nodes=[node(1, "A"), node(2, "B")],
            edges=[edge(1, 2, "conflicts"), edge(2, 1, "conflicts")],
        )
        out = run_inmem(d)
        self.assertEqual(out["sccs"], [])
        self.assertEqual(out["cycles"], [])


if __name__ == "__main__":
    unittest.main()
