# ADR-0004: Additive v1 → v2 Schema Bump

**Date**: 2026-05-13
**Status**: Accepted

## Context

The cycle pass adds new top-level keys (`sccs`, `cycles`, `cycle_summary`) and a new metadata field (`metadata.flavor`) to the artifact JSON. The artifact is consumed by multiple downstream workflows in this repository (`gating-conflict-detection`, `package-classifier`, `snyk-analysis`, `upstream-source-code-dependency-scanner`, `photonos-package-report`) and accumulates in `tdnf-depgraph/scans/` as a long-lived history. Any schema change must respect both the consumer base and the historical record.

PRD acceptance criterion AC-5 mandates a version bump; AC-8 mandates that v1 consumers continue to parse v2 files. These two together constrain the change to be *purely additive*.

## Decision Drivers

- **No silent breakage of downstream parsers.** Workflows that grep or `jq` on `nodes[]` / `edges[]` / `node_count` must continue to work after the bump.
- **Detectability.** A consumer must be able to detect v2 unambiguously when it wants to opt into the new fields.
- **Historical coherence.** `tdnf-depgraph/scans/*.json` files from before this change continue to be readable and identifiable as v1.

## Considered Options

### Option 1: No version field, structural detection

Consumers infer the schema from key presence (`if "cycles" in d: ...`).

**Pros:** Zero ceremony.
**Cons:** Fragile. A future v3 with different `cycles` semantics would force every consumer to add a second probe. No way to migrate historical scans without re-scanning.

### Option 2: Breaking rename of existing v1 fields

E.g. rename `node_count` → `metadata.counts.nodes`, `nodes` → `graph.nodes`, etc.

**Pros:** Cleaner long-term layout.
**Cons:** Breaks every consumer. Violates AC-8. Forces a coordinated rollout across five downstream workflows for no functional gain.

### Option 3 (Chosen): Bump `metadata.schema_version` from 1 to 2, additive-only changes

`metadata.schema_version: 2` is set on every emitted file. Every v1 key is preserved with identical name, position, and semantics. New keys are appended.

**Pros:**
- Existing consumers continue to work without modification.
- New consumers opt in by branching on `schema_version`.
- Historical v1 scans remain valid; they simply lack the new fields.

**Cons:**
- Cumulative schema growth over time. Acceptable at our pace of change (one ADR-driven bump per quarter, at most).

## Decision

The cycle pass (see [ADR-0001](0001-cycle-detection-in-python-postprocess.md)) is the sole writer of v2 fields. Specifically:

- Set `metadata.schema_version = 2`. Add `metadata.flavor` (string, `""` for base) and `metadata.specsdir` (string, e.g. `"SPECS+SPECS/91"`). Add `metadata.cycles_engine` (string identifier of the algorithm version, initially `"tarjan-py-v1"`).
- Add top-level `sccs[]`, `cycles[]`, `cycle_summary{}` arrays/objects. Empty arrays and zero counters are explicitly emitted (not omitted) for acyclic graphs.
- Do **not** rename, remove, reposition, or change the type of any v1 field. Specifically: `metadata.{branch, specsdir, generated_at}`, `node_count`, `edge_count`, `nodes`, `edges` are immutable.
- v1 consumers that never look at `schema_version` continue to function. v2-aware consumers check `metadata.schema_version >= 2` before reading the new fields.

The complete v2 schema is documented in [`../features/cycle-detection.md`](../features/cycle-detection.md).

## Consequences

- Historical scans under `tdnf-depgraph/scans/*.json` written before this change are valid v1; they lack `metadata.schema_version`. Consumers should treat absent `schema_version` as `1`.
- A future v3 must follow the same additive discipline unless the cost of breaking is explicitly weighed in a follow-up ADR.
- The `cycles_engine` string lets us evolve the algorithm (e.g. swap representative selection) without bumping the schema version, as long as the *shape* of the output is unchanged. A v3 bump is reserved for true structural changes.
- The cycle pass is the schema-version writer; the C `tdnf depgraph` extension continues to emit v1. The Python step is responsible for the bump on every output.
