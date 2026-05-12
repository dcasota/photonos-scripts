# ADR-0001: Cycle Detection in Python Post-Process Step

**Date**: 2026-05-13
**Status**: Accepted

## Context

The *Dependency Graph Scan* workflow emits one JSON artifact per Photon branch from a custom `tdnf depgraph` C extension that walks libsolv's `Pool`. The PRD ([../prd.md](../prd.md)) requires this artifact to carry cycle information so that incidents like the 2026-05-12 `libselinux ↔ python3` build-time loop are flagged in the run summary instead of being silently encoded in raw edge data.

Cycle detection logically belongs *somewhere* in the pipeline; the question is whether it runs inside the C extension as part of `tdnf depgraph --json`, or as a separate post-processing step against the existing JSON.

## Decision Drivers

- **Iteration speed.** Cycle algorithms, tie-breaking rules, and schema field choices will likely change as we learn from real artifacts. Workflow YAML / Python is cheap to iterate; C requires rebuilding the patched `tdnf-src` for every run.
- **Risk of regression.** The existing C extension is shared with downstream consumers; modifying it risks breaking the v1 JSON contract or the in-memory libsolv walk.
- **Data sufficiency.** The artifact JSON already contains all `nodes` and typed `edges`; no information is lost in serialization. Cycle detection does not need libsolv state.
- **Performance budget.** Graph sizes are ~1,500–2,000 nodes / ~10,000 edges per branch. Tarjan SCC is O(V+E) — trivially under a second in Python.
- **Deployment.** Python 3 is already required on the workflow runner (used elsewhere in the same job).

## Considered Options

### Option 1: Extend the C `tdnf depgraph` extension

Add a cycle pass to `src/solv_tdnfdepgraph.c` that runs after graph construction and emits `sccs`/`cycles` directly in the JSON.

**Pros:**
- Single binary, single JSON write.
- Could share data structures with the existing graph build.

**Cons:**
- Every iteration of the algorithm requires patching `tdnf-src` and rebuilding inside the workflow.
- Higher risk: a bug in the cycle pass can crash `tdnf depgraph` and fail the whole scan, not just the cycle field.
- Forks the C code further from upstream `vmware/tdnf`, raising the maintenance cost when tdnf bumps.
- C is the wrong language for prototyping schema field names; the JSON shape is still being shaped.

### Option 2: Standalone offline analyzer (separate CLI tool)

Ship a `cycle-analyzer` binary or Python script that runs out-of-band against checked-in `scans/*.json`.

**Pros:**
- Zero risk to the existing pipeline.
- Can be re-run against historical artifacts without re-scanning.

**Cons:**
- Splits the artifact: consumers must run two tools to get the full picture.
- The GitHub Actions step summary cannot report cycles inline.
- `fail_on_buildrequires_cycle` (G3 in the PRD) requires inline detection.

### Option 3 (Chosen): Python post-step in the workflow

Add a single Python script under `tdnf-depgraph/tools/depgraph_cycles.py` that runs inside the same workflow job, immediately after `tdnf depgraph --json`. It loads the v1 JSON, computes cycles, and rewrites the same file as v2.

**Pros:**
- The C extension remains untouched. v1 → v2 schema bump is the Python step's responsibility alone.
- Algorithm and schema can iterate without rebuilding tdnf.
- The same Python step can populate the step summary table (G5) and decide the job exit code (G3).
- Trivially testable in isolation (unit tests on a hand-built graph dict — see AC-2).
- Python stdlib alone is sufficient; no new runner dependencies.

**Cons:**
- Two languages in the pipeline (C for extraction, Python for analysis).
- Re-parses JSON the C extension just wrote (negligible cost at our graph sizes).

## Decision

Implement cycle detection as a Python post-step **(Option 3)**.

- File: `tdnf-depgraph/tools/depgraph_cycles.py`, Python 3 stdlib only.
- Invocation: one process per produced JSON, file rewritten in place.
- Schema bump from v1 to v2 happens here; the C extension continues to emit v1.

## Consequences

- The C source under `tdnf-depgraph/src/` stays at the v1 contract. Any future port of the algorithm to C is a separate ADR; until then, the Python step is canonical.
- The workflow YAML grows a new `Detect cycles` step that runs `depgraph_cycles.py` per output file, plus a step-summary writer (see [ADR-0004](0004-schema-v2-additive.md), [ADR-0006](0006-fail-on-buildrequires-cycle-input.md)).
- Unit tests live under `tdnf-depgraph/tests/` and exercise the Python step in isolation; no tdnf install required.
- If runtime ever exceeds budget (current expectation: under a second per branch), the Python implementation is a reference for a future C port — no algorithm decisions are locked in language.
