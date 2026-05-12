# ADR-0006: `fail_on_buildrequires_cycle` Workflow Input

**Date**: 2026-05-13
**Status**: Accepted

## Context

The cycle pass produces structured cycle output regardless of whether any cycle was found. The remaining question is: *when should the existence of cycles cause the workflow run itself to fail?*

Two extremes:

- Always fail when any cycle is found. Disruptive when scans run on schedule against the entire history of branches; would have failed every run between the workflow's deployment and the 2026-05-12 amendment, because `libselinux ↔ python3` was a real cycle and an intentional one (resolved by curated pre-staging — see [ADR-0005](0005-bootstrap-resolved-classification.md)).
- Never fail. The cycle report stays informational; consumers must read the step summary or parse the artifact to act.

The repo owner pre-locked the policy on 2026-05-13: the gate exists, defaults off, and `bootstrap_resolved: true` cycles never trip it. The point of this ADR is to specify the exact semantics so the implementer of T5 has no room to interpret.

## Decision Drivers

- **No surprise failures on the scheduled scan.** The existing weekly scan must continue to pass green for branches with curated, bootstrap-resolved cycles.
- **Opt-in gating at PR-review time.** When the workflow is dispatched against a PR-style scenario, the operator wants the option of failing fast on a newly-introduced unresolved cycle.
- **Bootstrap-resolved cycles do not fail.** Pre-locked decision. The point of `data/builder-pkg-preq.json` is that those cycles are accepted.
- **Single, deterministic predicate.** No "warning" tier; no mixed pass/fail outcomes.

## Considered Options

### Option 1: Always fail on any cycle

**Cons:** Breaks the scheduled scan against branches with curated `builder-pkg-preq.json` entries. Rejected.

### Option 2: Always fail only on unresolved `buildrequires` cycles, no input

**Pros:** Strong signal.
**Cons:** Same scheduled-scan disruption when a transient cycle appears between a spec change and a `builder-pkg-preq.json` update. Removes the operator's ability to silence the gate during a known-broken window. Rejected.

### Option 3 (Chosen): Workflow input, default `false`, applies only to unresolved buildrequires cycles

A new boolean input `fail_on_buildrequires_cycle` is added to the workflow. When `true`, the job exits non-zero iff at least one cycle has both `category == "buildrequires"` and `bootstrap_resolved == false`. When `false` (default), the job always exits zero on completion — cycle status is reported but not enforced.

**Pros:**
- Defaults off — zero behaviour change for existing consumers.
- Operator can flip the gate per-dispatch via the GitHub Actions UI without a code change.
- Strictly aligned with the pre-locked rule.

**Cons:**
- A long-lived `fail_on_buildrequires_cycle: true` cron run would be disrupted by transient cycles. Mitigation: do not enable it on the scheduled trigger; reserve it for explicit dispatches.

## Decision

- Add to `.github/workflows/depgraph-scan.yml` under `workflow_dispatch.inputs`:
  ```yaml
  fail_on_buildrequires_cycle:
    description: 'Fail the run if any unresolved buildrequires cycle is detected'
    type: boolean
    default: false
  ```
- After all artifacts are produced and the step summary is written, evaluate:
  ```python
  unresolved_br = [
      c for c in all_cycles_across_files
      if c["category"] == "buildrequires"
      and not c["bootstrap_resolved"]
  ]
  if fail_on_buildrequires_cycle and unresolved_br:
      sys.exit(1)
  ```
- The check explicitly *aggregates across (branch, flavor)*: a single unresolved cycle on any one scanned flavor fails the job.
- `category: "mixed"` cycles are out of scope for this gate. A mixed cycle by definition contains at least one runtime edge in addition to buildrequires; the buildrequires-only portion is not necessarily a build-order problem and the gate stays conservative. A future ADR may revisit this if mixed cycles prove actionable.
- `category: "requires"` and `category: "self-loop"` cycles never fail the gate.
- The scheduled (`cron`) trigger does not set `fail_on_buildrequires_cycle`; it inherits the default `false`. Operators must explicitly opt in via `workflow_dispatch`.

## Consequences

- T5 (in the Phase 5 task breakdown) implements this input plus the exit-code logic.
- The `cycle_summary` object emitted per file (per [ADR-0004](0004-schema-v2-additive.md)) includes both `bootstrap_resolved` and `unresolved` counters; consumers can replicate the gate's logic if they need to.
- A maintainer who genuinely wants the gate on the scheduled scan would either flip the cron-triggered default or open a follow-up ADR — neither is in scope here.
- If `category: "mixed"` cycles turn out to be a frequent actionable class, this ADR is superseded by a follow-up that broadens the gate predicate.
