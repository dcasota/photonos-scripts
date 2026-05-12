# Task 015: `fail_on_buildrequires_cycle` Workflow Input

**Complexity**: Low
**Dependencies**: [014](014-task-workflow-cycle-integration.md)
**Status**: Pending
**Requirement**: PRD G3 (AC-6)
**ADR**: [ADR-0006](../adr/0006-fail-on-buildrequires-cycle-input.md)

---

## Description

Add a workflow_dispatch input to the *Dependency Graph Scan* workflow that, when enabled, fails the job if any unresolved buildrequires cycle is found across all scanned (branch, flavor) pairs. Default is `false` (observational mode) so the scheduled scan is not disrupted.

## Scope

- Modify `.github/workflows/depgraph-scan.yml`.
- Add to `on.workflow_dispatch.inputs`:
  ```yaml
  fail_on_buildrequires_cycle:
    description: 'Fail the run if any unresolved buildrequires cycle is detected'
    type: boolean
    default: false
  ```
- After the per-flavor loop completes and the step summary is fully written, evaluate:
  ```bash
  if [ "${{ github.event.inputs.fail_on_buildrequires_cycle }}" = "true" ]; then
    UNRESOLVED_BR=$(jq -s '
      [ .[] | .cycles[] |
        select(.category == "buildrequires" and .bootstrap_resolved == false) ]
      | length' /tmp/depgraph-scans/*.json)
    if [ "${UNRESOLVED_BR:-0}" -gt 0 ]; then
      echo "::error::Found ${UNRESOLVED_BR} unresolved buildrequires cycle(s); failing per fail_on_buildrequires_cycle=true"
      exit 1
    fi
  fi
  ```
- The check aggregates across every emitted JSON: one unresolved cycle on any one (branch, flavor) fails the job.
- `category: "mixed"`, `requires`, and `self-loop` cycles do **not** trip the gate.
- The scheduled `cron` trigger never sets this input — it inherits the default `false`.

## Implementation Notes

- The exit-code logic must run **after** the artifact upload + scans-commit steps. Otherwise a failed run skips committing the very evidence that motivated the failure.
- A `::error::` annotation precedes `exit 1` so the reviewer sees the cause in the Actions UI without opening the summary.
- The shell aggregation uses `jq -s` for slurp mode; verified deterministic across runs because every input file is itself byte-deterministic (per task 012 acceptance criterion).

## Acceptance Criteria

- [ ] **AC-6.** With `fail_on_buildrequires_cycle=true` and at least one unresolved buildrequires cycle present, the job exits non-zero. With the same input and only `bootstrap_resolved: true` cycles present, the job exits zero.
- [ ] With `fail_on_buildrequires_cycle=false` (default), the job exits zero regardless of cycle status.
- [ ] `category: "mixed"` cycles never fail the gate, even when `bootstrap_resolved: false`.
- [ ] `category: "requires"` and `category: "self-loop"` cycles never fail the gate.
- [ ] Artifact and scans commit happen before the exit-code check.

## Testing Requirements

- [ ] Workflow_dispatch with `fail_on_buildrequires_cycle=true` on a branch known to have only bootstrap-resolved cycles — expect green.
- [ ] Workflow_dispatch with `fail_on_buildrequires_cycle=true` on the 2026-05-11 fixture seeded into a test branch — expect red, with the libselinux ↔ python3 cycle cited in the `::error::` line.
- [ ] Workflow_dispatch with `fail_on_buildrequires_cycle=false` on the same fixture — expect green.

## Out of Scope

- PR-trigger automation. The input is operator-driven only.
- Per-branch gating granularity. Aggregation is across all scanned (branch, flavor) pairs.
