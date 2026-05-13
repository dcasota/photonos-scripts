# ADR-0005: Bootstrap-Resolved Cycle Classification

**Date**: 2026-05-13
**Status**: Accepted (amended 2026-05-13 per [findings/2026-05-13-no-builder-pkg-preq-json.md](../findings/2026-05-13-no-builder-pkg-preq-json.md))

> **Note (amended 2026-05-13).** This ADR was drafted on the (incorrect) assumption that `data/builder-pkg-preq.json` exists in `vmware/photon`. Empirical verification on 2026-05-13 confirmed it does not — see [findings/2026-05-13-no-builder-pkg-preq-json.md](../findings/2026-05-13-no-builder-pkg-preq-json.md). The canonical pre-stage definition lives in `support/package-builder/constants.py` (three Python lists), and is partial w.r.t. the engine's 37-node toolchain SCC. The engine's `load_preq()` walks any JSON file with string leaves regardless of provenance, so the ADR's *mechanism* is correct; only the *source-of-truth* references in §Context, §Decision Drivers and §Decision below are aspirational until either upstream produces a comprehensive JSON pre-stage list, or operators / tests supply a synthesized one (which task 016 does, for testing only). The strict-membership rule (Option 3 below) remains in force — see PRD Q5 for the open question on whether to relax it.

## Context

Not every cycle in the dependency graph is a bug. The Photon build system maintains `data/builder-pkg-preq.json` — a list of packages that the bootstrap pre-stages before normal `BuildRequires` resolution begins. Packages in this list can participate in cycles without breaking the build, because the build never needs to *resolve* their `BuildRequires` from scratch: their binaries are already on disk when the dependent build starts.

The 2026-05-12 fix at `vmware/photon@8fb8549c` is the canonical example. It both:

1. Split `libselinux.spec` into `libselinux.spec` + `libselinux-python3.spec`, removing the most concrete edge in the cycle.
2. Added `libselinux` and `libsepol` to `data/builder-pkg-preq.json`, so any residual cyclicity is tolerated by the build sequencing.

A cycle-detection step that fails the workflow on every cycle would have flagged the post-fix state as broken — even though the maintainer's intent was exactly to leave the cycle resolved by pre-staging. The cycle pass must distinguish actionable cycles from intentionally-tolerated ones.

The PRD requires this as goal G3 and acceptance criterion AC-6, and the repo owner pre-locked the rule on 2026-05-13: `bootstrap_resolved: true` cycles never trip the failure gate (formalized in [ADR-0006](0006-fail-on-buildrequires-cycle-input.md)).

## Decision Drivers

- **Match the build system's effective view.** A cycle whose every node is pre-staged is, by construction, not a build-order problem.
- **Branch sensitivity.** `data/builder-pkg-preq.json` differs per branch. The check must use the same branch checkout that produced the graph.
- **Failure mode safety.** If the pre-stage list is missing or unparseable, default to the conservative classification (`bootstrap_resolved: false`) so that real cycles do not slip through.
- **No false negatives on partial overlap.** A cycle where *most* members are pre-staged but one is not is still actionable; classification must be strict ("every member").

## Considered Options

### Option 1: Ignore pre-staging entirely

Treat every cycle as equally actionable.

**Pros:** Simplest classification rule.
**Cons:** Floods the run summary with intentional cycles. A maintainer who adds an entry to `builder-pkg-preq.json` would see no behaviour change in the cycle report.

### Option 2: Heuristic — mark cycle bootstrap-resolved if *any* member is pre-staged

**Pros:** Catches more cycles as tolerated.
**Cons:** Wrong. A single pre-staged node does not break a cycle: the others still need each other built first. Produces false negatives.

### Option 3 (Chosen): Strict — bootstrap-resolved iff *every* SCC member is in `data/builder-pkg-preq.json`

For each non-trivial SCC, read `data/builder-pkg-preq.json` from the same branch checkout. If every node in the SCC (by package name match) appears in the pre-stage list, mark the SCC — and every representative cycle in it — `bootstrap_resolved: true`. Otherwise `false`.

**Pros:**
- Faithful to the build system's actual behaviour.
- Conservative: strictly fewer cycles are tolerated than would be by Option 2.
- Updates automatically as `builder-pkg-preq.json` evolves — exactly the feedback loop the 2026-05-12 maintainer's amendment depended on.

**Cons:**
- Requires resolving package names between the graph nodes (which carry `name` plus optional sub-package suffix like `libselinux-python3`) and the pre-stage list (which references binary RPM names). Sub-package handling is captured in the feature spec.

## Decision

- The cycle pass reads `data/builder-pkg-preq.json` from the branch's sparse checkout. The schema is currently a flat list of package names; the pass tolerates structural variation (treats missing keys or empty lists as "no pre-staged packages").
- An SCC is `bootstrap_resolved: true` iff *every* member's name (or its base-package name, for sub-packages of a pre-staged source) appears in the pre-stage set. Any member outside the set → `bootstrap_resolved: false`.
- A cycle inherits `bootstrap_resolved` from its containing SCC.
- `cycle_summary.bootstrap_resolved` and `cycle_summary.unresolved` count cycles, not SCCs, and partition the total.
- If `data/builder-pkg-preq.json` is missing, unreadable, or fails to parse, the pass logs a warning to the step summary and defaults every SCC to `bootstrap_resolved: false`.
- Sub-package name resolution: a graph node named `libselinux-python3` whose source RPM is `libselinux` is considered pre-staged if `libselinux` is in the list. Mapping is derived from `nodes[i].repo` (which already carries the `.spec` path).

## Consequences

- The 2026-05-12 amendment to `builder-pkg-preq.json` (libselinux/libsepol) immediately flips any residual libselinux ↔ python3 SCC from `unresolved` to `bootstrap_resolved` on the next scan — which is the intended end state for AC-1.
- A maintainer can shift the workflow's attention by editing `builder-pkg-preq.json`. The cycle pass is a passive reader: every classification decision lives upstream in that file.
- If a future Photon branch restructures the pre-stage list (e.g. moves it into a different file or adds nested structure), this ADR's defaulting rule keeps the workflow running while a follow-up ADR captures the new format.
- The feature spec ([`../features/cycle-detection.md`](../features/cycle-detection.md)) is the authoritative reference for the sub-package name-resolution logic.
