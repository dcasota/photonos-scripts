# tdnf-depgraph — Implementation Tasks

## Cycle Detection Initiative — Phase 6 Implementation Tasks

| Task | Description | Complexity | Dependencies | Related Specs | Status |
|------|-------------|------------|--------------|---------------|--------|
| [012](012-task-cycle-engine.md) | Python cycle pass (`tools/depgraph_cycles.py`): Tarjan SCC + BFS representative + schema-v2 writer | High | None | [ADR-0001](../adr/0001-cycle-detection-in-python-postprocess.md), [ADR-0003](../adr/0003-tarjan-scc-plus-representative.md), [ADR-0004](../adr/0004-schema-v2-additive.md), [ADR-0005](../adr/0005-bootstrap-resolved-classification.md), [FRD-cycle-detection](../features/cycle-detection.md) | Pending |
| [013](013-task-workflow-flavor-matrix.md) | Workflow YAML: dynamic `SPECS/[0-9]+` discovery + overlay assembly + filename convention | Medium | 012 | [ADR-0002](../adr/0002-subrelease-overlay-flavors.md), [FRD-subrelease-flavors](../features/subrelease-flavors.md) | Complete |
| [014](014-task-workflow-cycle-integration.md) | Workflow YAML: invoke `depgraph_cycles.py` per output file + extend `$GITHUB_STEP_SUMMARY` | Medium | 012, 013 | [FRD-cycle-detection](../features/cycle-detection.md) §2.6 | Complete |
| [015](015-task-fail-on-cycle-input.md) | Workflow YAML: `fail_on_buildrequires_cycle` input + cross-file aggregation + exit-code logic | Low | 014 | [ADR-0006](../adr/0006-fail-on-buildrequires-cycle-input.md) | Complete |
| [016](016-task-regression-fixture.md) | Check in 2026-05-11 master JSON as `tests/fixtures/`; add unit test enforcing AC-1 | Low | 012 | [PRD §6 AC-1](../prd.md) | Complete |
| [017](017-task-docs-update.md) | Update `tdnf-depgraph/README.md` with schema v2 section + consumer migration note | Low | 012–016 | [FRD-subrelease-flavors](../features/subrelease-flavors.md) §2.5 | Pending |

## Quality Gates

Before marking any task complete:

- [ ] Code (Python or YAML) passes the workflow's existing lint/CI conventions.
- [ ] Acceptance criteria from the task file are each demonstrably met.
- [ ] Determinism contract from [FRD-cycle-detection §2.5](../features/cycle-detection.md) is verified by re-running and diffing the output.
- [ ] PRD acceptance criteria AC-1..AC-8 each map to at least one completed task.

## Dependency Graph

```
012 ──┬─▶ 013 ──▶ 014 ──▶ 015
      │
      └─▶ 016
      │
      └─▶ 017
```

Task 012 is the critical path; 016 and 017 can land in parallel with 013–015 once 012 merges.

## Branch & Commit Convention

- Branch: `sdd/depgraph-phase-6-taskNNN-<slug>` (e.g. `sdd/depgraph-phase-6-task012-cycle-engine`).
- Commit subject: `tdnf-depgraph phase-6 task NNN: <imperative summary>`.
- One PR per task; cite the task ID in the PR title and body; flip status in this README from `Pending` → `In Progress` → `Complete` as part of the same PR.
