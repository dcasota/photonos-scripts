# Finding 2026-05-13c: `vmware/photon@5.0` has no `SPECS/92/` overlay

**Status**: Addressed — PRD v1.2, ADR-0002, FRD-subrelease-flavors, and task 013 amended on 2026-05-13.
**Discovered while verifying**: AC-3 of [task 013](../tasks/013-task-workflow-flavor-matrix.md) on workflow run [`25795445195`](https://github.com/dcasota/photonos-scripts/actions/runs/25795445195) (2026-05-13, the first run after [finding 2026-05-13b](2026-05-13-find-regex-portability.md) fixed the portable flavor discovery).
**Affects**: [prd.md](../prd.md) §1 / G2 / AC-3, [adr/0002-subrelease-overlay-flavors.md](../adr/0002-subrelease-overlay-flavors.md), [features/subrelease-flavors.md](../features/subrelease-flavors.md), [tasks/013-task-workflow-flavor-matrix.md](../tasks/013-task-workflow-flavor-matrix.md).

## Summary

PRD v1.0/v1.1 anchored AC-3 on a hardcoded enumeration: workflow_dispatch on Photon 5.0 must produce **four** artifact files — base + `90` + `91` + `92`. After fixing the portable flavor discovery in PR #76, run `25795445195` produced only **three** artifacts:

```
Flavors: [ 90 91]  (3 total)
  - Flavor -:  1622 specs -> dependency-graph-5.0-20260513_111151.json
  - Flavor 90: 1642 specs -> dependency-graph-5.0-90-20260513_111151.json
  - Flavor 91: 1671 specs -> dependency-graph-5.0-91-20260513_111151.json
```

Cross-checking with the GitHub Contents API:

```
$ gh api repos/vmware/photon/contents/SPECS?ref=5.0 \
    --jq '.[] | select(.type=="dir") | .name' | grep -E '^[0-9]+$' | sort
90
91
```

`SPECS/92` does not exist on `vmware/photon@5.0`. The PRD's "5.0: 90, 91, 92" enumeration was speculative — there is no historical commit on `vmware/photon@5.0` introducing `SPECS/92`, and no upstream announcement of a 5.0.92 sub-release.

The engine and workflow are correct per ADR-0002 (dynamic discovery; no hardcoded flavor list). Only the acceptance criteria — which baked in the wrong upstream-state assumption — needed amendment.

## Resolution

Phase-1c PR amended the following specs in lockstep:

1. **PRD §1 Purpose** — replaced the `"SPECS/90, SPECS/91, SPECS/92"` enumeration with a parenthetical noting today's state (`90`, `91`) and pointing at this finding.
2. **PRD G2 success metric** — re-anchored on dynamic `N+1` (`N` = count of `SPECS/[0-9]+/` at run time).
3. **PRD AC-3** — re-anchored on dynamic `N+1`; explicitly recorded today's state (`N=2`, three files) and the verifying run ID. The hardcoded `{90,91,92}` is gone.
4. **PRD §7 Pre-locked Design Knob #2** — updated the discovery recipe to match the portable bash glob actually used after PR #76, with a cross-reference to [finding 2026-05-13b](2026-05-13-find-regex-portability.md).
5. **PRD Changelog** — new v1.2 entry.
6. **ADR-0002 Context** — replaced the `"SPECS/90, SPECS/91, SPECS/92"` enumeration with a description of what's actually present.
7. **ADR-0002 Decision step 2** — recipe replaced (portable glob).
8. **ADR-0002 Consequences** — "four files" → "`N+1` files (today: 3)".
9. **FRD-subrelease-flavors §1 Purpose + §1 Success Criteria** — same dynamic framing.
10. **FRD-subrelease-flavors §2.1 result table** — today's verified state; `92` listed only as a hypothetical row (annotated as such).
11. **Task 013 AC-3** — re-anchored on dynamic `N+1`; checked off; cross-referenced this finding.

## Why this approach over alternatives

- **Alternative A: wait for `SPECS/92/` to appear upstream.** Rejected — `vmware/photon` has no announced 5.0.92 milestone; AC-3 could remain red indefinitely with no actionable work.
- **Alternative B: keep AC-3 as written but mark it "deferred".** Rejected — accepting AC drift conflicts with SDD discipline.
- **Alternative C (chosen): re-anchor AC-3 on dynamic state.** Aligns AC with the actual design intent of ADR-0002 (dynamic discovery). Re-verifying after upstream changes requires zero spec edits.

## Re-verification

Re-running `workflow_dispatch branches=5.0` after this amendment lands should continue to satisfy the amended AC-3:

```
gh workflow run depgraph-scan.yml --repo dcasota/photonos-scripts --field branches=5.0
```

Expected: `N+1` files at run time, with one base file plus one file per `SPECS/[0-9]+/` overlay present on the cloned upstream HEAD. As of 2026-05-13 that is three files.
