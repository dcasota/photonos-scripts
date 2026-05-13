# Task 013: Workflow Sub-Release Flavor Matrix

**Complexity**: Medium
**Dependencies**: [012](012-task-cycle-engine.md)
**Status**: Complete
**Requirement**: PRD G2 (AC-3, AC-4)
**Feature**: [FRD-subrelease-flavors](../features/subrelease-flavors.md)
**ADR**: [ADR-0002](../adr/0002-subrelease-overlay-flavors.md)

---

## Description

Extend `.github/workflows/depgraph-scan.yml` so that, per branch, the workflow discovers `SPECS/[0-9]+/` overlay directories and emits one dependency-graph JSON per (branch, flavor) pair. Filename convention preserves backwards compatibility for branches without sub-releases.

## Scope

- Modify `.github/workflows/depgraph-scan.yml` (the active workflow at the repo root).
- After the existing `git sparse-checkout set SPECS` step, enumerate flavors per [FRD-subrelease-flavors §2.1](../features/subrelease-flavors.md):
  ```bash
  FLAVORS=("")
  mapfile -t -O 1 FLAVORS < <(
    find "${CLONE_DIR}/SPECS" -maxdepth 1 -mindepth 1 -type d \
         -regex '.*/SPECS/[0-9]+' -printf '%f\n' | sort
  )
  ```
- Wrap the existing per-branch body in an inner `for FLAVOR in "${FLAVORS[@]}"` loop per [FRD-subrelease-flavors §2.4](../features/subrelease-flavors.md).
- Assemble the overlay per [§2.2](../features/subrelease-flavors.md) for numeric flavors only; base flavor uses `SPECS/` directly.
- Filename token: `${SAFE_BRANCH}` for base, `${SAFE_BRANCH}-${FLAVOR}` for numeric flavors. Filename pattern: `dependency-graph-<token>-<datetime>.json`.
- Add `--setopt flavor="$FLAVOR"` to the `tdnf depgraph` invocation so the (eventual) cycle pass can pick up the value from `metadata.flavor`. The C extension ignores unknown setopt keys, so no C-side change is required.
- Extend the per-branch summary table in `$GITHUB_STEP_SUMMARY` with a `Flavor` column (rendered as `-` when base).
- Extend the existing `Cleanup` step: `rm -rf /tmp/photon-overlay-*`.

## Implementation Notes

- The existing workflow's "Commit to scans directory" step (`tdnf-depgraph/scans/`) must continue to work for any glob it already uses. Validate that `git add tdnf-depgraph/scans/` still picks up every new file.
- The `--filter=blob:none --sparse` clone already in the workflow is unchanged. Only the post-checkout loop differs.
- Overlay assembly uses `cp -a SOURCE/. DEST/` (trailing `.`) so that contents — including dotfiles — are copied, not the source directory itself.
- For branches that historically produced exactly one file (e.g. 3.0, 4.0, 6.0, common, master, dev), the new code path produces exactly one file with the unchanged filename. Verified by inspection of the per-branch flavor list (`("")` only).

## Acceptance Criteria

- [ ] **AC-3.** Workflow_dispatch on `branches: 5.0` produces four files in the `dependency-graphs` artifact:
  - `dependency-graph-5.0-<datetime>.json`
  - `dependency-graph-5.0-90-<datetime>.json`
  - `dependency-graph-5.0-91-<datetime>.json`
  - `dependency-graph-5.0-92-<datetime>.json`
- [ ] **AC-4.** Workflow_dispatch on `branches: 3.0,4.0,6.0,common,master,dev` produces six files whose names match the v1 convention (no `-<flavor>-` suffix).
- [ ] Each emitted file's `metadata.flavor` matches the flavor it represents (`""` for base, numeric string otherwise). *(Set by `--setopt flavor=`; the field will be visible after task 014 lands.)*
- [ ] `metadata.specsdir` reads `SPECS` for base and `SPECS+SPECS/<F>` for numeric flavors. *(Same caveat as above.)*
- [ ] Step summary contains one row per (branch, flavor).
- [ ] No leftover `/tmp/photon-overlay-*` directories after the job completes.
- [ ] A future hypothetical `SPECS/95/` directory on any branch is picked up automatically with no code change. Verified by adding a temporary `SPECS/95/` dir in a test branch and re-running.

## Testing Requirements

- [ ] Manual workflow_dispatch on 5.0 only — confirm four artifacts.
- [ ] Manual workflow_dispatch on the seven-branch default — confirm one artifact per non-5.0 branch with v1-style names.
- [ ] `act` or local YAML lint to catch syntax errors before push.

## Out of Scope

- Cycle pass invocation (task 014).
- Schema v2 fields (task 012 + task 014).
- Removing existing v1 filename consumers (none required — additive).
