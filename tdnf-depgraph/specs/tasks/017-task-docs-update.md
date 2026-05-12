# Task 017: Update `tdnf-depgraph/README.md`

**Complexity**: Low
**Dependencies**: [012](012-task-cycle-engine.md), [013](013-task-workflow-flavor-matrix.md), [014](014-task-workflow-cycle-integration.md), [015](015-task-fail-on-cycle-input.md)
**Status**: Pending
**Requirement**: PRD AC-8 (consumer compatibility documentation)
**Feature**: [FRD-cycle-detection](../features/cycle-detection.md), [FRD-subrelease-flavors §2.5](../features/subrelease-flavors.md)

---

## Description

Update `tdnf-depgraph/README.md` with three new sections: schema v2 reference, cycle detection workflow behaviour, and a consumer migration note. Keep the existing problem-statement and C-extension sections unchanged; the cycle pass is layered on top, not a replacement.

## Scope

- Modify `tdnf-depgraph/README.md`. Append three sections after the existing content:
  1. **Schema v2 (cycle detection).** Short reference linking to [FRD-cycle-detection §2.1](specs/features/cycle-detection.md). Show the new metadata fields (`schema_version`, `flavor`, `cycles_engine`) and the three new top-level keys (`sccs`, `cycles`, `cycle_summary`). One small JSON example.
  2. **Sub-release flavors.** Brief overview linking to [FRD-subrelease-flavors](specs/features/subrelease-flavors.md). Document the filename rule (base = unchanged v1 name; numeric flavor = `-<F>-` suffix). Photon 5.0 example with four filenames.
  3. **Consumer compatibility.** Note that v1 readers continue to work; v2-aware readers should branch on `metadata.schema_version`. Link to the migration table at [FRD-subrelease-flavors §2.5](specs/features/subrelease-flavors.md). Include the recommended `if d["metadata"].get("flavor", "") != "": continue` snippet for base-only consumers.
- Open coordination issues (or note existing ones) against the five downstream consumers listed in [FRD-subrelease-flavors §2.5](specs/features/subrelease-flavors.md). The README cites the issue numbers if they exist by merge time.

## Acceptance Criteria

- [ ] `tdnf-depgraph/README.md` references each feature spec by relative path; links resolve on github.com.
- [ ] Schema v2 example matches the field set documented in ADR-0004 / FRD-cycle-detection §2.1.
- [ ] Filename example covers the four 5.0 outputs plus the unchanged master output.
- [ ] Consumer migration note states explicitly that v1 readers continue to work.
- [ ] **AC-8 hook.** The five existing downstream workflows are confirmed to parse v2 JSONs without modification. (Manual verification on the first v2-emitting workflow_dispatch.)

## Testing Requirements

- [ ] Render `tdnf-depgraph/README.md` on github.com after merge; verify all links.
- [ ] Run each downstream workflow on the first v2-emitting scan and verify no parse failures.

## Out of Scope

- Modifying the downstream workflows themselves. Migration is opt-in; this task only documents the contract.
- A separate migration guide. The README + feature spec table are sufficient.
