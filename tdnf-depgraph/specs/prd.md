# Product Requirements Document (PRD)

## tdnf-depgraph — Cycle Detection & Sub-Release Flavors

**Version**: 1.2
**Last Updated**: 2026-05-13
**Status**: Accepted — Active (amended 2026-05-13 per [findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md](findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md) and [findings/2026-05-13-upstream-no-spec92.md](findings/2026-05-13-upstream-no-spec92.md))

---

## 1. Purpose

The *Dependency Graph Scan* workflow exports an RPM dependency graph for every Photon OS branch and commits it to `tdnf-depgraph/scans/`. The graph captures `Requires`, `BuildRequires`, and `Conflicts` edges over every spec and binary node, and is consumed by downstream initiatives (Snyk classifier, package report, gating-conflict detector, the PQC QUBO formulation in `upstream-source-code-dependency-scanner`).

The graph contains everything needed to detect circular dependencies between packages — but the workflow itself never analyses it. The motivating incident is the `libselinux ↔ python3` build-time coupling that landed as `vmware/photon@8fb8549c` on 2026-05-12: `libselinux.spec` carried a `python3` sub-package, while `libselinux` build-required `python3-pip` / `python3-setuptools` / `python3-devel`. The fix split the python3 bindings into a separate `libselinux-python3.spec` and added `libselinux`/`libsepol` to `data/builder-pkg-preq.json` so the bootstrap can pre-stage them.

> **Note (amended 2026-05-13).** The libselinux ↔ python3 coupling is a **spec-source-coupling**, not a graph-level cycle. The C extension records `BuildRequires` against source-package nodes only and does not propagate them to subpackages, so the coupling does not surface as a directed SCC in the exported binary-package edge graph. See [findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md](findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md) for the empirical analysis. Acceptance criteria below are anchored on cycles that **do** exist in the 2026-05-11 master fixture; whether to extend the C extension to propagate source-level BuildRequires to subpackages is a separate initiative.

The latest *Dependency Graph Scan* run prior to the fix (`25661049895`, 2026-05-11 09:10 UTC) emitted a graph that, when analysed by the cycle engine, contains **twelve** strongly-connected components. The most concrete actionable cycle is:

```
python3-attrs (id …) --buildrequires--> python3-pytest
python3-pytest        --buildrequires--> python3-attrs
```

The largest entanglement is a 37-node toolchain SCC (`autogen, bash, cmake, curl, gcc, openssl, python3, readline, tcl, util-linux, …`) which is expected to flip to `bootstrap_resolved: true` once the branch's `data/builder-pkg-preq.json` is loaded.

This PRD specifies adding **cycle detection** to the artifact, and — as a prerequisite — **first-class sub-release flavors** so that Photon 5.0's `SPECS/` plus each `SPECS/[0-9]+/` overlay is scanned independently rather than collapsed into a single "5.0" graph. (Today, on `vmware/photon@5.0`, the overlays are `SPECS/90` and `SPECS/91`; the discovery is dynamic so additional overlays such as `SPECS/92` would be picked up automatically if/when they appear — see [findings/2026-05-13-upstream-no-spec92.md](findings/2026-05-13-upstream-no-spec92.md).)

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
- Regression coverage on the 2026-05-11 master snapshot to prove the detector finds the cycles documented in this PRD (specifically `python3-attrs ↔ python3-pytest` for the actionable buildrequires class, and the 37-node toolchain SCC for the `bootstrap_resolved` transition once the real `builder-pkg-preq.json` loads).

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

**Success metric:** Re-running the detector on the saved 2026-05-11 master JSON produces a cycle entry with `path_names == ["python3-attrs", "python3-pytest", "python3-attrs"]`, `category: "buildrequires"`, `length: 2`, and (with empty preq) `bootstrap_resolved: false`. The same scan also yields a 37-member SCC whose members include `python3`, `gcc`, `bash`, `cmake`, `openssl`.

### G2 — First-class sub-release flavors

The workflow discovers `SPECS/[0-9]+/` overlay directories after sparse-checkout and emits one JSON per (branch, flavor) pair. Discovery is dynamic (no hardcoded flavor list), so when Photon 6.0 or `dev` grow sub-release dirs they pick up automatically.

**Success metric:** A workflow_dispatch on Photon 5.0 produces `N+1` artifact files, where `N` = the number of `SPECS/[0-9]+/` subdirectories present on the cloned `vmware/photon@5.0` HEAD. As of 2026-05-13 `N=2` (overlays: `90`, `91`), yielding three files. Each contains `metadata.flavor` matching its overlay. The base 5.0 file keeps its existing filename `dependency-graph-5.0-<datetime>.json`; non-base flavors gain a `-<flavor>` suffix.

### G3 — Distinguish actionable from bootstrap-resolved cycles

Every cycle carries a `bootstrap_resolved` boolean derived from the branch's `data/builder-pkg-preq.json`. Cycles where every member is pre-staged are reported but never trip `fail_on_buildrequires_cycle`. The toolchain SCC (37 members: gcc, openssl, python3, bash, cmake, …) is the canonical example: every member is part of the bootstrap pre-stage list, so the SCC reports `bootstrap_resolved: true` and falls below the action threshold.

**Success metric:** On the 2026-05-11 master scan with the branch's real `data/builder-pkg-preq.json` loaded, the 37-node toolchain SCC reports `bootstrap_resolved: true` and is excluded from the `unresolved` summary counter. The `python3-attrs ↔ python3-pytest` cycle remains `bootstrap_resolved: false` (those packages are not in the bootstrap pre-stage list).

### G4 — Backwards-compatible artifact schema

`metadata.schema_version` bumps from 1 to 2. All v1 keys (`metadata.{generator,timestamp,branch}`, `node_count`, `edge_count`, `nodes`, `edges`) are preserved unchanged. Consumers branch on `schema_version` to opt into the new fields. *(Amended 2026-05-13: the v1 metadata keys are `generator` / `timestamp` / `branch` as actually emitted by the C extension, not `branch` / `specsdir` / `generated_at` as the v1.0 draft asserted; the engine preserves whatever v1 keys are present.)*

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
| AC-1 | Regression scan on `tdnf-depgraph/scans/dependency-graph-master-20260511_091039.json` produces a cycle with `path_names == ["python3-attrs", "python3-pytest", "python3-attrs"]`, `category: "buildrequires"`, `length: 2`, and (with empty preq) `bootstrap_resolved: false`. The same scan also produces exactly 12 SCCs, one of which has size 37 and includes the names `python3`, `gcc`, `bash`, `cmake`, `openssl`. *(Amended 2026-05-13: original AC-1 anchored on `libselinux ↔ python3` which is a spec-source coupling, not a graph cycle — see [findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md](findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md).)* | `specs/tasks/016-task-regression-fixture.md` |
| AC-2 | Re-running the detector on the same input JSON twice produces byte-identical `cycles[]` and `sccs[]` arrays (deterministic ordering). | T1 unit test |
| AC-3 | Workflow_dispatch on Photon 5.0 produces `N+1` artifact files, where `N` is the count of `SPECS/[0-9]+/` subdirectories on the cloned `vmware/photon@5.0` HEAD at run time. Filenames: `dependency-graph-5.0-<datetime>.json` (base) + one `dependency-graph-5.0-<flavor>-<datetime>.json` per discovered overlay. *(Today: `N=2`, overlays `{90,91}`, three files — verified by run `25795445195`. Amended 2026-05-13: original AC-3 anchored on a hardcoded `{90,91,92}` enumeration, but upstream has no `SPECS/92/` — see [findings/2026-05-13-upstream-no-spec92.md](findings/2026-05-13-upstream-no-spec92.md). The AC is now state-anchored on whatever upstream actually exposes.)* | T3 |
| AC-4 | Workflow_dispatch on Photon 3.0/4.0/6.0/common/master/dev produces files whose names are unchanged from v1 (`dependency-graph-<branch>-<datetime>.json`). | T3 |
| AC-5 | `metadata.schema_version == 2` in every emitted file; every v1 key preserved unchanged in field name and semantics. | T2 |
| AC-6 | `fail_on_buildrequires_cycle=true` causes the job to exit non-zero when any `bootstrap_resolved: false`, `category: "buildrequires"` cycle exists, and to exit zero otherwise. `bootstrap_resolved: true` cycles never trip the gate. | T5 |
| AC-7 | The Actions step summary shows `Cycles / BR-Cycles / Self-loops / Bootstrap-Resolved` columns per (branch, flavor), plus a fenced block listing up to ten representative cycle paths. | T4 |
| AC-8 | A consumer parsing v1 JSON (the existing `gating-conflict-detection` and `package-classifier` workflows) continues to read v2 JSON without code change. | Manual smoke after T7 |

---

## 7. Pre-locked Design Knobs

Decisions agreed before ADR drafting; ADRs in Phase 3 document the rationale:

1. **Cycle pass runs in Python, post-process to the C binary's JSON output** — not in the `tdnf depgraph` C extension. Cheaper iteration; the artifact contains everything needed.
2. **Subrelease scanning uses overlay merge** — for flavor `N`, the spec tree is `SPECS/` with `SPECS/<N>/` files copied on top. Same-name wins. Discovery is dynamic (portable bash glob: iterate `SPECS/*/`, keep entries whose basename matches `^[0-9]+$`). *(The original draft prescribed `find -regex … -printf`; that's a GNU extension the self-hosted runner's `find` rejects — see [findings/2026-05-13-find-regex-portability.md](findings/2026-05-13-find-regex-portability.md).)*
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

- **Q1.** Should the 2026-05-11 snapshot live permanently as `tdnf-depgraph/tests/fixtures/` for ongoing regression coverage, or be rebuilt on demand? Recommendation: check in (small file, anchors AC-1). *(Resolved 2026-05-13: yes — task 016 checks it in.)*
- **Q2.** When a non-trivial SCC has only `requires` edges (runtime cycle, no build-time edges), should we still emit a `cycles[]` entry with `category: "requires"`? Recommendation: yes — informational, no failure impact. *(Resolved 2026-05-13: yes — engine in task 012 emits them; see cyc-001/004/005/006-009/011/012 on the master fixture.)*
- **Q3.** Should `metadata.flavor` be `""` or `null` for the base scan (no overlay)? Recommendation: `""` for consistent string typing. *(Resolved 2026-05-13: `""` — implemented in task 012's engine.)*
- **Q4 (new, opened 2026-05-13 by finding).** Should the C `tdnf-depgraph` extension propagate source-level `BuildRequires` from a `.spec` to its subpackages, so that spec-source-couplings (like the libselinux ↔ python3 incident) surface as graph cycles? Recommendation: separate initiative — its own PRD. Not in scope for the current cycle-detection work.

---

## 9. References

- Motivating Photon commit (`libselinux ↔ python3` spec-source coupling fix): `vmware/photon@8fb8549c`
- The workflow run that captured the source-level edges but didn't flag any graph cycle: [`actions/runs/25661049895`](https://github.com/dcasota/photonos-scripts/actions/runs/25661049895)
- Workflow source: [`.github/workflows/depgraph-scan.yml`](../../.github/workflows/depgraph-scan.yml)
- Subproject architecture: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- Empirical finding amending AC-1: [`findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md`](findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md)
- Related SDD initiatives following the same pattern: [`../../upstream-source-code-dependency-scanner/specs/prd.md`](../../upstream-source-code-dependency-scanner/specs/prd.md), [`../../vCenter-CVE-drift-analyzer/specs/prd.md`](../../vCenter-CVE-drift-analyzer/specs/prd.md)

---

## Changelog

- **1.2 (2026-05-13)** — AC-3 and the G2 success metric re-anchored on dynamic `N+1` (where `N` is the count of `SPECS/[0-9]+/` subdirs on the cloned upstream HEAD) instead of a hardcoded `{90,91,92}`. The verification run `25795445195` proved the workflow's dynamic discovery is correct, while empirically demonstrating that `vmware/photon@5.0` carries only `SPECS/90` and `SPECS/91` today (no `SPECS/92`). The §1 Purpose statement was updated likewise. ADR-0002 and FRD-subrelease-flavors brought into line. See [`findings/2026-05-13-upstream-no-spec92.md`](findings/2026-05-13-upstream-no-spec92.md).
- **1.1 (2026-05-13)** — AC-1 and G1/G3 success metrics re-anchored on cycles that exist in the binary-package edge graph (`python3-attrs ↔ python3-pytest` for the actionable buildrequires class; 37-node toolchain SCC for the `bootstrap_resolved` transition). Q1–Q3 resolved. New Q4 opened: should the C extension propagate source-level `BuildRequires` to subpackages? G4 v1-key list corrected (`generator`/`timestamp`/`branch`, not `branch`/`specsdir`/`generated_at` — the engine preserves whatever v1 keys are present regardless). See [`findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md`](findings/2026-05-13-libselinux-python3-not-a-graph-cycle.md).
- **1.0 (2026-05-13)** — Initial draft.
