# Feature Requirement Document: Sub-Release Overlay Flavors

**Feature ID**: FRD-subrelease-flavors
**Related PRD Requirements**: G2, AC-3, AC-4
**Status**: Specified — Phase 4
**Last Updated**: 2026-05-13

---

## 1. Feature Overview

### Purpose

Scan Photon sub-release directories (`SPECS/[0-9]+/` overlays) as first-class flavors. Photon 5.0's `SPECS/90`, `SPECS/91`, `SPECS/92` produce distinct dependency graphs that reflect how the build system actually composes spec trees for each sub-release; the base `SPECS/` continues to produce a single non-flavored scan.

### Value Proposition

Today's single-graph-per-branch model collapses flavor-specific differences. The 2026-05-12 fix touched **both** `SPECS/libselinux/libselinux.spec` **and** `SPECS/91/libselinux/libselinux.spec` precisely because the 91 flavor is built from a different effective tree. Scanning only `SPECS/` misses flavor-only changes entirely.

### Success Criteria

See PRD acceptance criteria AC-3 and AC-4. In brief:

- Workflow_dispatch on Photon 5.0 produces four output files (base + 90 + 91 + 92).
- Workflow_dispatch on Photon 3.0/4.0/6.0/common/master/dev produces output files whose names are unchanged from v1.
- Adding (or removing) a `SPECS/<N>/` directory on any branch is picked up automatically, with no code change.

---

## 2. Functional Requirements

### 2.1 Flavor discovery

After the branch's sparse checkout completes (the existing `git sparse-checkout set SPECS` step), enumerate flavors as follows:

```bash
FLAVORS=("")     # element 1: empty token = base scan
mapfile -t -O 1 FLAVORS < <(
  find "${CLONE_DIR}/SPECS" -maxdepth 1 -mindepth 1 -type d \
       -regex '.*/SPECS/[0-9]+' -printf '%f\n' | sort
)
```

Result examples:

| Branch | Discovered `FLAVORS` |
|---|---|
| 5.0 | `("" "90" "91" "92")` |
| 6.0 | `("")`  *(if no SPECS/[0-9]+ dirs exist today)* |
| 4.0 | `("")` |
| common | `("")` |
| master | `("")` |
| dev | `("")` |

A future Photon 6.0 sub-release directory (say `SPECS/95`) is picked up automatically on the next workflow run. No hardcoded list of numeric tokens exists anywhere in the workflow or in the cycle pass.

### 2.2 Overlay assembly

For each flavor `F` in `FLAVORS`:

- **Base flavor (`F == ""`):**
  - `SPECS_DIR=${CLONE_DIR}/SPECS`
  - No overlay needed. Run `tdnf depgraph --setopt specsdir=${SPECS_DIR}` directly.
  - `metadata.flavor = ""`
  - `metadata.specsdir = "SPECS"`
- **Numeric flavor (`F` matches `[0-9]+`):**
  - `OVERLAY_DIR=/tmp/photon-overlay-${BRANCH}-${F}`
  - Assemble: `mkdir -p "$OVERLAY_DIR" && cp -a "${CLONE_DIR}/SPECS/." "$OVERLAY_DIR/" && cp -a "${CLONE_DIR}/SPECS/${F}/." "$OVERLAY_DIR/"`
  - Run `tdnf depgraph --setopt specsdir=${OVERLAY_DIR}`.
  - `metadata.flavor = F`
  - `metadata.specsdir = "SPECS+SPECS/${F}"`

**Overlay semantics:** `cp -a` with a trailing `.` copies the *contents* of the source directory. Running it twice in sequence means files from the second source (the flavor subdir) overwrite same-name files from the first (the base SPECS). This matches the Photon build system's "overlay" composition exactly.

**Cleanup:** the existing workflow `Cleanup` step is extended to also `rm -rf /tmp/photon-overlay-*`.

### 2.3 Filename convention

Per [ADR-0002](../adr/0002-subrelease-overlay-flavors.md) and the repo owner's 2026-05-13 decision:

| Case | Filename pattern |
|---|---|
| Base flavor (any branch, `F == ""`) | `dependency-graph-<branch>-<datetime>.json` *(unchanged from v1)* |
| Numeric flavor (`F` matches `[0-9]+`) | `dependency-graph-<branch>-<F>-<datetime>.json` |

The `<datetime>` token uses the existing format `YYYYMMDD_HHMMSS` (UTC). The `<branch>` token retains the existing `tr '/' '-'` sanitization.

**Examples:**

| Branch | Flavor | Filename |
|---|---|---|
| 5.0 | `""` | `dependency-graph-5.0-20260518_030000.json` |
| 5.0 | `90` | `dependency-graph-5.0-90-20260518_030000.json` |
| 5.0 | `91` | `dependency-graph-5.0-91-20260518_030000.json` |
| 5.0 | `92` | `dependency-graph-5.0-92-20260518_030000.json` |
| master | `""` | `dependency-graph-master-20260518_030000.json` |
| 6.0 | `""` | `dependency-graph-6.0-20260518_030000.json` |

**Glob compatibility:** existing consumers using `dependency-graph-5.0-*.json` will pick up *all* 5.0 flavors plus the base. Consumers that want only the base must either filter by `metadata.flavor == ""` (preferred for v2-aware consumers) or use a stricter glob `dependency-graph-5.0-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*.json`. The feature spec recommends the metadata filter.

### 2.4 Workflow loop structure

The existing `for BRANCH in $BRANCHES` loop is extended with an inner `for FLAVOR in "${FLAVORS[@]}"` loop scoped to the per-branch sparse checkout. The summary table in `$GITHUB_STEP_SUMMARY` grows a `Flavor` column (rendered as `-` for base) and one row per (branch, flavor) pair.

Pseudocode for the inner loop body:

```bash
for FLAVOR in "${FLAVORS[@]}"; do
  if [ -z "$FLAVOR" ]; then
    SPECS_DIR="${CLONE_DIR}/SPECS"
    FILE_TOKEN="${SAFE_BRANCH}"
    SPECSDIR_META="SPECS"
  else
    SPECS_DIR="/tmp/photon-overlay-${SAFE_BRANCH}-${FLAVOR}"
    mkdir -p "$SPECS_DIR"
    cp -a "${CLONE_DIR}/SPECS/." "$SPECS_DIR/"
    cp -a "${CLONE_DIR}/SPECS/${FLAVOR}/." "$SPECS_DIR/"
    FILE_TOKEN="${SAFE_BRANCH}-${FLAVOR}"
    SPECSDIR_META="SPECS+SPECS/${FLAVOR}"
  fi
  FILENAME="dependency-graph-${FILE_TOKEN}-${DATETIME}.json"
  OUTPATH="/tmp/depgraph-scans/${FILENAME}"

  env $TDNF_ENV $TDNF depgraph --json \
    --setopt specsdir="$SPECS_DIR" \
    --setopt branch="$BRANCH" \
    --setopt flavor="$FLAVOR" \
    2>"$ERR_LOG" > "$OUTPATH" || ...

  # ... existing stats extraction ...
  # ... new: invoke depgraph_cycles.py to rewrite as schema v2 ...
done
```

**Note on the `--setopt flavor=` argument:** the existing C extension accepts arbitrary `--setopt` keys; it ignores unrecognized ones. The Python post-step uses `flavor` to populate `metadata.flavor`. No C-side change is required.

### 2.5 Consumer migration

Five workflows in this repo currently read `tdnf-depgraph/scans/*.json`:

| Consumer | Read pattern | Migration action |
|---|---|---|
| `gating-conflict-detection` | iterates `dependency-graph-<branch>-*.json` | None required; v2 fields are additive. To restrict to the base flavor, add `if d["metadata"].get("flavor", "") != "": continue`. |
| `package-classifier` | Same. | Same. |
| `snyk-analysis` | Same. | Same. |
| `upstream-source-code-dependency-scanner` | Same — feeds QUBO formulation. | Same. May choose to consume specific flavors for the QUBO cost vector; future enhancement. |
| `photonos-package-report` | Same. | Same. |

A coordination issue is opened against each consumer before the implementation T7 PR merges, per PRD section 8 risk mitigation.

---

## 3. Out of Scope

- Photon 3.0 / 4.0 sub-release support. No `SPECS/[0-9]+/` directories exist on those branches today.
- Cross-flavor diff reports (e.g. "what edges are new in 91 vs base?"). Future enhancement; out of scope for v2.
- Per-flavor commit gating on `vmware/photon` PRs.
- Non-numeric flavor directories (e.g. hypothetical `SPECS/dev`). The flavor regex is strict: `[0-9]+` only.

---

## 4. Implementation Pointers

- Workflow YAML changes: tasks T3 (flavor matrix), T4 (step-summary integration) in `specs/tasks/0001-task-cycles-post-step.md`.
- The Python cycle pass reads `metadata.flavor` already set by the C extension via `--setopt flavor=`; it also sets `metadata.specsdir` to the overlay descriptor for human-readability.
- Cleanup: `rm -rf /tmp/photon-overlay-*` extended in the workflow's existing cleanup step.
