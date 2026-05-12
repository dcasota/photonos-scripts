# Product Requirements Document (PRD)

## tdnf-depgraph — Cycle Detection & Sub-Release Flavors

**Version**: 1.0
**Last Updated**: 2026-05-13
**Status**: Draft — Phase 1

---

## 1. Purpose

The *Dependency Graph Scan* workflow exports an RPM dependency graph for every Photon OS branch and commits it to `tdnf-depgraph/scans/`. The graph captures `Requires`, `BuildRequires`, and `Conflicts` edges over every spec and binary node, and is consumed by downstream initiatives (Snyk classifier, package report, gating-conflict detector, the PQC QUBO formulation in `upstream-source-code-dependency-scanner`).

The graph contains everything needed to detect circular dependencies between packages — but the workflow itself never analyses it. On 2026-04-15 the Photon team identified a build-time loop, `libselinux ↔ python3`: `libselinux.spec` carried a `python3` sub-package, which required `python3` to be already built, while `python3-pip` / `python3-setuptools` / `python3-devel` build-required `libselinux`. The fix landed on `vmware/photon@8fb8549c` on 2026-05-12, splitting the python3 bindings into a separate `libselinux-python3.spec` and adding `libselinux`/`libsepol` to `data/builder-pkg-preq.json` so the bootstrap can pre-stage them.

The latest *Dependency Graph Scan* run prior to the fix (`25661049895`, 2026-05-11 09:10 UTC) emitted a graph whose edges encode exactly this cycle:

```
libselinux (id 1155) --buildrequires--> python3-pip       (466)
libselinux (id 1155) --buildrequires--> python3-setuptools(462)
libselinux (id 1155) --buildrequires--> python3-devel     (458)
libselinux-python3   (1158) --requires--> libselinux       (1155)
```

The cycle was present in the data, ~27 hours before the manual fix, but the workflow neither flagged it in the Actions summary nor failed the run. The same gap will hide the next cycle.

This PRD specifies adding **cycle detection** to the artifact, and — as a prerequisite — **first-class sub-release flavors** so that Photon 5.0's `SPECS/`, `SPECS/90`, `SPECS/91`, `SPECS/92` overlays are scanned independently rather than collapsed into a single "5.0" graph.

---

## 2. Scope

### In Scope

- Detect strongly-connected components and cycles in every graph produced by the workflow.
- Distinguish cycle classes: `buildrequires`, `requires`, `mixed`, and `self-loop`. (The `requires`-only class is informational; `buildrequires` is the actionable one.)
- Cross-check each cycle against the branch's `data/builder-pkg-preq.json` to classify it as `bootstrap_resolved: true` (every member pre-staged) or `bootstrap_resolved: false` (actionable).
- Scan Photon 5.0 sub-release overlays separately: discover `SPECS/[0-9]+/` dirs on the fly and assemble per-flavor overlay trees (`SPECS/` with `SPECS/<N>/` files copied on top, same-name wins).
- Augment the existing artifact JSON schema additively: bump `metadata.schema_version` 1 → 2; add `sccs[]`, `cycles[]`, `cycle_summary{}`, and `metadata.flavor`. All v1 keys preserved.
- Optional fail-on-cycle gate: a new workflow input `fail_on_buildrequires_cycle` (default `false`). When `true`, the job exits non-zero if any `bootstrap_resolved: false` `buildrequires` cycle is found.
- Update the GitHub Actions step summary table to surface cycle counts per (branch, flavor), plus a fenced block listing up to the first ten representative cycles per scan.
- Regression coverage on the 2026-05-11 master snapshot to prove the detector finds the documented libselinux ↔ python3 cycle.

### Out of Scope

- Full enumeration of all elementary cycles per SCC (Johnson's algorithm). One *shortest representative* cycle per SCC is emitted, plus `scc_size` so consumers know how many alternatives exist.
- Rewriting the C `tdnf-depgraph` extension. Cycle detection runs as a Python post-step in the workflow, against the existing v1 JSON output. Algorithm may be ported to C later if runtime warrants.
- PR-time auto-gating on cycle introduction. The fail-on-cycle input ships in v2 but stays `false` by default; gating opt-in is a separate initiative.
- Cycle detection on the `conflicts` edge subset — `conflicts` edges do not form meaningful cycles for our purposes.
- Repairing or rewriting the underlying spec graph. The workflow reports, it does not patch.

---

## 3. Stakeholders

| Role | Stakeholder | Interest |
|------|-------------|----------|
| Maintainer | Photon spec maintainers (vmware/photon) | Get an early warning when a spec change introduces a build-time cycle. |
| Bootstrap owners | Toolchain pre-stage maintainers | Curate `data/builder-pkg-preq.json` precisely; see which cycles are intentional vs. accidental. |
| Downstream consumers | `upstream-source-code-dependency-scanner` (QUBO PQC plan), `snyk-analysis`, `package-classifier`, `gating-conflict-detection`, `package-report` | Consume `tdnf-depgraph/scans/*.json`; need a stable schema with a version field. |
| Reviewer | dcasota (repo owner) | Single approver for PRs; needs the Actions step summary to convey cycle status without opening artifacts. |

---

## 4. Goals & Success Criteria

### G1 — Detect cycles in every produced graph

Every JSON the workflow emits has a `cycles[]` array and a `cycle_summary{}` counter. If the input graph is acyclic, both are empty / zero. If it contains cycles, every non-trivial SCC contributes at least one representative cycle.

**Success metric:** Re-running the detector on the saved 2026-05-11 master JSON produces a cycle entry whose `path_names` contains both `libselinux` and a `python3-*` node, `category: "buildrequires"`, `bootstrap_resolved: false`.

### G2 — First-class sub-release flavors

The workflow discovers `SPECS/[0-9]+/` overlay directories after sparse-checkout and emits one JSON per (branch, flavor) pair. Discovery is dynamic (no hardcoded `90/91/92`), so when Photon 6.0 or `dev` grow sub-release dirs they pick up automatically.

**Success metric:** A workflow_dispatch on Photon 5.0 produces four artifact files (base + 90 + 91 + 92). Each contains `metadata.flavor` matching its overlay. The base 5.0 file keeps its existing filename `dependency-graph-5.0-<datetime>.json`; non-base flavors gain a `-<flavor>` suffix.

### G3 — Distinguish actionable from bootstrap-resolved cycles

Every cycle carries a `bootstrap_resolved` boolean derived from the branch's `data/builder-pkg-preq.json`. Cycles where every member is pre-staged are reported but never trip `fail_on_buildrequires_cycle`. The 2026-05-12 amendment to `builder-pkg-preq.json` (libselinux/libsepol) is the canonical example: post-fix, any residual `libselinux ↔ python3` cycle becomes `bootstrap_resolved: true` and falls below the action threshold.

**Success metric:** On a post-fix master scan, the libselinux ↔ python3 SCC — if any edges still exist — is reported with `bootstrap_resolved: true` and excluded from the `unresolved` summary counter.

### G4 — Backwards-compatible artifact schema

`metadata.schema_version` bumps from 1 to 2. All v1 keys (`metadata.{branch,specsdir,generated_at}`, `node_count`, `edge_count`, `nodes`, `edges`) are preserved unchanged. Consumers branch on `schema_version` to opt into the new fields.

**Success metric:** Downstream consumers `gating-conflict-detection`, `package-classifier`, `snyk-analysis`, and `upstream-source-code-dependency-scanner` continue to parse v2 JSONs without modification.

### G5 — Surface cycle status without opening artifacts

The GitHub Actions step summary table grows columns `Flavor | Cycles | BR-Cycles | Self-loops | Bootstrap-Resolved`, plus a fenced block listing up to the first ten representative cycles per (branch, flavor) as `pkg-a → pkg-b → … → pkg-a`.

**Success metric:** A reviewer can determine whether any unresolved buildrequires cycle exists by reading the Actions run summary alone.

---

## 5. Non-Goals

- Replacing the existing `tdnf depgraph` C extension or its libsolv-based resolution.
- Per-PR auto-detection or comment-bot integration on `vmware/photon` PRs.
- Cycle visualization (Graphviz, mermaid). Out of scope; downstream tooling may layer on top.
- Detecting *latent* runtime cycles that bootstrap_resolved tolerates today but would break under a different install order.
- A Web UI or dashboard. Consumers read JSON directly.

---

## 6. Acceptance Criteria

The cycle-detection initiative is complete when all of the following hold:

| # | Criterion | Verifier |
|---|-----------|----------|
| AC-1 | Regression scan on `vmware/photon` at the 2026-05-11 commit produces a cycle whose `path_names` contains both `libselinux` and a `python3-*` node, with `category: "buildrequires"` and `bootstrap_resolved: false`. | `specs/tasks/0001-task-cycles-post-step.md` T6 |
| AC-2 | Re-running the detector on the same input JSON twice produces byte-identical `cycles[]` and `sccs[]` arrays (deterministic ordering). | T1 unit test |
| AC-3 | Workflow_dispatch on Photon 5.0 produces four artifact files: `dependency-graph-5.0-<datetime>.json` (base) and `dependency-graph-5.0-{90,91,92}-<datetime>.json` (overlays). | T3 |
| AC-4 | Workflow_dispatch on Photon 3.0/4.0/6.0/common/master/dev produces files whose names are unchanged from v1 (`dependency-graph-<branch>-<datetime>.json`). | T3 |
| AC-5 | `metadata.schema_version == 2` in every emitted file; every v1 key preserved unchanged in field name and semantics. | T2 |
| AC-6 | `fail_on_buildrequires_cycle=true` causes the job to exit non-zero when any `bootstrap_resolved: false`, `category: "buildrequires"` cycle exists, and to exit zero otherwise. `bootstrap_resolved: true` cycles never trip the gate. | T5 |
| AC-7 | The Actions step summary shows `Cycles / BR-Cycles / Self-loops / Bootstrap-Resolved` columns per (branch, flavor), plus a fenced block listing up to ten representative cycle paths. | T4 |
| AC-8 | A consumer parsing v1 JSON (the existing `gating-conflict-detection` and `package-classifier` workflows) continues to read v2 JSON without code change. | Manual smoke after T7 |

---

## 7. Pre-locked Design Knobs

Decisions agreed before ADR drafting; ADRs in Phase 3 document the rationale:

1. **Cycle pass runs in Python, post-process to the C binary's JSON output** — not in the `tdnf depgraph` C extension. Cheaper iteration; the artifact contains everything needed.
2. **Subrelease scanning uses overlay merge** — for flavor `N`, the spec tree is `SPECS/` with `SPECS/<N>/` files copied on top. Same-name wins. Discovery is dynamic (`find SPECS -maxdepth 1 -mindepth 1 -type d -regex 'SPECS/[0-9]+'`).
3. **Cycle algorithm = Tarjan SCC + shortest representative cycle per SCC via BFS** — not Johnson's full enumeration. `scc_size` field tells consumers when the representative is one of many.
4. **Schema bump 1 → 2 is purely additive.** No v1 field changes name, position, or semantics.
5. **Filename compatibility.** Unflavored branches keep `dependency-graph-<branch>-<datetime>.json`. Only Photon 5.0's non-base flavors gain a `-<flavor>` suffix. Confirmed by repo owner on 2026-05-13.
6. **`bootstrap_resolved: true` cycles never trip `fail_on_buildrequires_cycle`.** They are informational. Confirmed by repo owner on 2026-05-13.

---

## 8. Risks & Open Questions

| Risk | Mitigation |
|------|------------|
| Tarjan on ~1800-node graphs hits Python recursion limits. | Implement iteratively. Validated against existing graph sizes during T1. |
| Overlay merge may produce a hybrid spec tree that doesn't match any real build configuration when SPECS/<N>/ contains a partial subset. | Document overlay semantics in `features/subrelease-flavors.md`; emit `metadata.specsdir` listing the overlay sources so consumers can audit. |
| `data/builder-pkg-preq.json` schema is undocumented and may vary across branches. | Treat absence/parse failure as `bootstrap_resolved: false` (conservative). Log a warning in the workflow step summary. |
| Cycle representative choice (shortest-path BFS) may pick a different concrete cycle on the same SCC across runs if there are ties. | Tie-break deterministically by lexicographic order of node names. Captured as a T1 unit test (AC-2). |
| `metadata.schema_version` bump may surprise consumers that don't guard on it. | Coordinated rollout: open issue against each downstream consumer before merging T7. Document in `features/cycle-detection.md`. |

### Open questions for Dev Lead review

- **Q1.** Should the 2026-05-11 snapshot live permanently as `tdnf-depgraph/tests/fixtures/` for ongoing regression coverage, or be rebuilt on demand? Recommendation: check in (small file, anchors AC-1).
- **Q2.** When a non-trivial SCC has only `requires` edges (runtime cycle, no build-time edges), should we still emit a `cycles[]` entry with `category: "requires"`? Recommendation: yes — informational, no failure impact.
- **Q3.** Should `metadata.flavor` be `""` or `null` for the base scan (no overlay)? Recommendation: `""` for consistent string typing.

---

## 9. References

- Photon commit fixing the libselinux ↔ python3 loop: `vmware/photon@8fb8549c`
- The workflow run that captured the cycle in data but didn't flag it: [`actions/runs/25661049895`](https://github.com/dcasota/photonos-scripts/actions/runs/25661049895)
- Workflow source: [`.github/workflows/depgraph-scan.yml`](../../.github/workflows/depgraph-scan.yml)
- Subproject architecture: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- Related SDD initiatives following the same pattern: [`../../upstream-source-code-dependency-scanner/specs/prd.md`](../../upstream-source-code-dependency-scanner/specs/prd.md), [`../../vCenter-CVE-drift-analyzer/specs/prd.md`](../../vCenter-CVE-drift-analyzer/specs/prd.md)
