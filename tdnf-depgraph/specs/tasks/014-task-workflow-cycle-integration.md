# Task 014: Workflow Cycle Integration + Step Summary

**Complexity**: Medium
**Dependencies**: [012](012-task-cycle-engine.md), [013](013-task-workflow-flavor-matrix.md)
**Status**: Pending
**Requirement**: PRD G1, G4, G5 (AC-5, AC-7)
**Feature**: [FRD-cycle-detection §2.6](../features/cycle-detection.md)
**ADR**: [ADR-0001](../adr/0001-cycle-detection-in-python-postprocess.md), [ADR-0004](../adr/0004-schema-v2-additive.md)

---

## Description

Wire the cycle engine (`tools/depgraph_cycles.py` from task 012) into the workflow so every produced JSON is rewritten as schema v2 before artifact upload. Extend the GitHub Actions step summary to surface cycle counts and representative paths per (branch, flavor).

## Scope

- Modify `.github/workflows/depgraph-scan.yml`.
- After the existing `tdnf depgraph --json` invocation inside the per-flavor loop, add a `Detect cycles` invocation:
  ```bash
  PREQ_PATH="${CLONE_DIR}/data/builder-pkg-preq.json"
  python3 tdnf-depgraph/tools/depgraph_cycles.py \
    --input "$OUTPATH" \
    --preq  "$PREQ_PATH" \
    --flavor "$FLAVOR" \
    --specsdir-meta "$SPECSDIR_META" \
    2>>"$CYCLES_LOG"
  ```
- Parse the one-line `cyc-engine:` stderr summary into shell variables for the table.
- Extend the existing `$GITHUB_STEP_SUMMARY` table header to:
  ```
  | Branch | Flavor | Specs | Nodes | Edges | Cycles | BR-Cycles | Self-loops | Unresolved | Bootstrap-Resolved | File |
  ```
- After all branches/flavors complete, append a per-(branch, flavor) fenced block listing up to the first 10 cycles in `cycles[]` order, formatted as `cyc-NNN (category, [un]resolved): pkg-a → pkg-b → ... → pkg-a`. Paths longer than 8 hops are truncated to first-3 / ellipsis / last-2 per [FRD-cycle-detection §2.6](../features/cycle-detection.md).
- If `data/builder-pkg-preq.json` is missing from the branch checkout, the cycle pass emits a stderr warning; surface that warning in the step summary as a `::warning::` annotation.

## Implementation Notes

- The artifact upload step (`uses: actions/upload-artifact@v7`) must run **after** the cycle pass completes for every file. The existing step's `if: steps.generate.outputs.file_count != '0'` guard is unchanged.
- The "Commit to scans directory" step picks up the rewritten v2 files (no separate write).
- Use `jq` to extract cycle paths for the summary block, not Python — keeps the YAML reviewable in a single shell idiom and avoids re-loading huge JSONs.
- Handle the case where the cycle pass itself fails (e.g. malformed JSON from a broken tdnf run): log `::error::` but do not fail the job. The fail gate (task 015) operates only on successful cycle-pass output.

## Acceptance Criteria

- [ ] **AC-5.** Every JSON in the `dependency-graphs` artifact has `metadata.schema_version == 2` and the new `sccs[]` / `cycles[]` / `cycle_summary{}` keys.
- [ ] **AC-7.** The Actions run page step summary shows the extended table and per-(branch, flavor) cycle blocks. Layout matches [FRD-cycle-detection §2.6](../features/cycle-detection.md).
- [ ] Empty case: a scan of an acyclic branch shows `Cycles: 0` in the table and no cycle block.
- [ ] Truncation: a cycle with `length > 8` is rendered as `a → b → c → ... → y → z`.
- [ ] Missing pre-stage file produces a single `::warning::` annotation per affected (branch, flavor), not a job failure.

## Testing Requirements

- [ ] Workflow_dispatch on a single branch (e.g. master) — verify table row + (empty or populated) cycle block.
- [ ] Workflow_dispatch on a synthetic scenario with the 2026-05-11 master fixture seeded into `scans/` — verify the libselinux ↔ python3 cycle is rendered in the summary.

## Out of Scope

- Fail-on-cycle exit code logic (task 015).
- Regression fixture check-in (task 016).
