# ADR-0002: Sub-Release Overlay Flavors

**Date**: 2026-05-13
**Status**: Accepted

## Context

Photon 5.0's `vmware/photon` checkout contains a top-level `SPECS/` tree and additional sub-release directories `SPECS/90/`, `SPECS/91/`, `SPECS/92/`. The latter hold per-flavor overrides — most commonly the kernel and kernel-adjacent specs — while everything else comes from the base `SPECS/` tree. The 2026-05-12 fix at `vmware/photon@8fb8549c` was applied to *both* `SPECS/libselinux/libselinux.spec` *and* `SPECS/91/libselinux/libselinux.spec` because each flavor is built independently from its own merged view.

Today's *Dependency Graph Scan* emits a single graph per branch by pointing `tdnf depgraph --setopt specsdir=` at `SPECS/`. Sub-release content is therefore ignored: scans of 5.0 do not see what builds for 5.0.91 actually depend on. The PRD requires per-flavor visibility (G2) so that flavor-specific cycles do not hide behind the base view.

The question is not whether to scan sub-releases — it is what *flavor* means when the on-disk tree is partial.

## Decision Drivers

- **Match build reality.** When the Photon build system constructs a 5.0.91 image, it composes `SPECS/` with `SPECS/91/` on top. The graph we emit for the `91` flavor should reflect what is actually built.
- **Discoverability.** The sub-release directory layout is conventional but not centrally declared. Hardcoding `90/91/92` will silently misbehave when 6.0 or `dev` grow their own sub-releases.
- **Stability of consumer contracts.** Downstream consumers parse filenames; the existing per-branch filenames must not change for branches that have no sub-releases.

## Considered Options

### Option 1: Treat each `SPECS/<N>/` as an independent, standalone tree

Run `tdnf depgraph --setopt specsdir=SPECS/91` directly.

**Pros:** Simple.
**Cons:** Wrong. `SPECS/91/` typically contains only a handful of overrides (kernel, microcode, perhaps glibc); a depgraph over it alone produces a graph with ~50 nodes that omits the bulk of the system. This does not match how Photon builds the 91 flavor.

### Option 2 (Chosen): Overlay `SPECS/<N>/` on top of `SPECS/`

For flavor `N`, assemble a temporary directory that contains every file from `SPECS/`, with every file from `SPECS/<N>/` copied on top — same-name wins. Run `tdnf depgraph` against the overlay.

**Pros:**
- Matches the build's effective view of the 91 spec tree.
- Cycle detection sees the same edges the builder sees, so detected cycles reflect real build-order problems.
- Naturally handles the empty case: branches with no `SPECS/[0-9]+/` directories produce a single (base) flavor identical to today's output.

**Cons:**
- Requires a temporary overlay directory per flavor; cleanup discipline in the workflow.
- Overlay semantics must be documented for consumers (see [`../features/subrelease-flavors.md`](../features/subrelease-flavors.md)).

### Option 3: Static configuration of (branch → flavor list)

Maintain a JSON file (or workflow input) enumerating the flavors per branch.

**Pros:** Explicit; reviewable.
**Cons:** Must be updated whenever Photon adds a sub-release. Drift between configuration and actual on-disk state is exactly the failure mode we want to avoid.

## Decision

For each (branch, flavor) pair:

1. Sparse-checkout `SPECS/` from the target branch.
2. Discover flavors dynamically: `find SPECS -maxdepth 1 -mindepth 1 -type d -regex 'SPECS/[0-9]+' -printf '%f\n' | sort`.
3. For the empty (base) flavor, run `tdnf depgraph --setopt specsdir=SPECS`.
4. For each numeric flavor `N`, materialize an overlay at `/tmp/photon-overlay-<branch>-<N>/` by:
   - `cp -a SPECS/. overlay/`
   - `cp -a SPECS/<N>/. overlay/` (same-name files overwrite)
   then run `tdnf depgraph --setopt specsdir=overlay`.
5. Emit one JSON per (branch, flavor). Filename convention is fixed in [`../features/subrelease-flavors.md`](../features/subrelease-flavors.md): unflavored branches keep `dependency-graph-<branch>-<datetime>.json`; flavored runs gain a `-<flavor>` suffix.
6. `metadata.flavor` carries the flavor token (`""` for base). `metadata.specsdir` carries a human-readable overlay descriptor (e.g. `"SPECS+SPECS/91"`).

## Consequences

- Photon 5.0 emits four files per run: base + 90 + 91 + 92. Branches 3.0/4.0/6.0/common/master/dev emit one file each with names unchanged.
- A future Photon 6.0 or `dev` sub-release directory is picked up automatically with no code change.
- Workflow cleanup must delete `/tmp/photon-overlay-*` between runs; covered as part of the existing `cleanup` step.
- Consumers that today iterate `tdnf-depgraph/scans/dependency-graph-5.0-*.json` will see new files matching the same glob. They must guard on `metadata.flavor` if they want only the base view. This is documented in the feature spec and the v2 schema notes.
- The overlay copy adds a small filesystem cost per flavor; at Photon spec-tree sizes (~30 MB) this is negligible compared to the existing tdnf clone+build step.
