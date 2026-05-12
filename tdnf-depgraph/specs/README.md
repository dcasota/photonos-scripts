# tdnf-depgraph — Specifications

This directory holds the Spec-Driven Development artifacts for `tdnf-depgraph`. Layout follows the convention used by the other SDD-tracked subprojects in this repository (`upstream-source-code-dependency-scanner`, `vCenter-CVE-drift-analyzer`, etc.).

## Layout

| Path | Purpose |
|------|---------|
| `prd.md` | Product Requirements Document — problem, stakeholders, goals/non-goals, acceptance criteria. One per active initiative; superseded PRDs move under `archive/`. |
| `adr/NNNN-<slug>.md` | Architecture Decision Records. Numbered globally across this subproject, never renumbered. Each ADR captures one irreversible decision with context, alternatives considered, and consequences. |
| `features/<slug>.md` | Feature-level reference docs — schemas, algorithms, contracts, file-format specifications. Linked from PRD and ADRs. |
| `tasks/NNN-task-<slug>.md` | Implementation task breakdown with acceptance tests. Numbered within an initiative; one task per pull request where practical. |

## SDD Workflow

Each initiative progresses through phases, with each phase gating the next via a merged pull request:

1. **Phase 0 — Scaffolding.** Create or refresh `ARCHITECTURE.md` and this README; ensure the subproject is ready to receive specs.
2. **Phase 1 — PRD.** Author `prd.md`. Implementation is blocked until the PRD merges.
3. **Phase 2 — Dev Lead review.** Feasibility check on the PRD PR (no separate file; recorded as a PR review).
4. **Phase 3 — ADRs.** One PR (or one per ADR) covering all architectural decisions implied by the PRD.
5. **Phase 4 — Feature specs.** Concrete schemas, pseudocode, and contracts.
6. **Phase 5 — Task breakdown.** `specs/tasks/0001-task-*.md` with one row per implementation step and its acceptance test.
7. **Phase 6 — Implementation.** One PR per task. Each PR cites the task ID and updates the task status.

Branch naming follows the repo's existing convention: `sdd/<initiative>-phase-N-<slug>` (e.g. `sdd/depgraph-phase-0-init`).

Commit subjects follow the existing pattern: `<subproject> phase-N task NNN[-NNN]: <imperative summary>`.

## Active Initiative — Cycle Detection

The first initiative to flow through `tdnf-depgraph/specs/` adds **cycle detection** to the dependency-graph artifact. Motivation: the 2026-05-12 fix on `vmware/photon@8fb8549c` resolved a `libselinux ↔ python3` build-time dependency loop that the Dependency Graph Scan workflow had captured in its raw edge data but never flagged. Two design knobs are pre-locked in [`../ARCHITECTURE.md`](../ARCHITECTURE.md):

- **Filename compatibility.** Unflavored branches keep `dependency-graph-<branch>-<datetime>.json`; only Photon 5.0's non-base flavors gain a `-<flavor>` suffix.
- **Fail-policy.** When `fail_on_buildrequires_cycle=true` lands, only `bootstrap_resolved: false` cycles trip a job failure; cycles whose every member appears in `data/builder-pkg-preq.json` are observational.

Phase-by-phase deliverables for this initiative are tracked in the Open Initiatives table of [`../ARCHITECTURE.md`](../ARCHITECTURE.md).
