# ADR-0001: Snapshot Bypass via photon-mainline

**Date**: 2026-03-06
**Status**: Accepted (with caveats -- see ADR-0002)

## Context

Photon OS 5.0 builds with `photon-subrelease=91` fail because snapshot 91 was captured before gating commits (e.g., 6b7bc7c) that split packages like libcap into subpackages. The snapshot metadata is inconsistent with the current spec tree.

The build system in `common/build.py` line 1520 implements:

```python
phMainlineVer = configdict["photon-build-param"].get("photon-mainline", "92")
if subrelease != phMainlineVer:
    # use snapshot
else:
    print(f"Skipping snapshot for {phMainlineVer} builds ...")
```

## Decision Drivers

- Build must complete without modifying upstream `.spec` files
- Snapshot 91 cannot be regenerated (it's a historical artifact)
- The `build_if` gating itself is correct -- only the snapshot is stale

## Considered Options

### Option 1: Set photon-mainline = photon-subrelease (bypass snapshot)

Set `"photon-mainline": "91"` in `5.0/build-config.json`. When `subrelease == mainline`, the build system skips the snapshot and uses the remote repo directly.

**Pros**: Simple one-line config change. `build_if` gating alone correctly selects old specs.

**Cons**: Remote repo contains newer package versions (2.77 for libcap). The `tdnf upgrade` step pulls these, creating version conflicts. See ADR-0002.

### Option 2: Create a curated snapshot

Manually build a snapshot file listing only packages from the old (pre-gating) spec set.

**Pros**: Clean solution -- tdnf sees exactly the right packages.

**Cons**: Requires deep knowledge of the full package set. Error-prone. Not scalable.

### Option 3: Upgrade to subrelease 92

Set `photon-subrelease=92` and `photon-mainline=92`. Both old and new specs activate consistently with the remote repo.

**Pros**: Everything is consistent. Remote repo, specs, and snapshot all agree.

**Cons**: Changes the kernel version (6.12 instead of 6.1 for branch 5.0). May not be desired.

## Decision Outcome

**Chosen**: Option 1 (photon-mainline bypass) as initial fix.

**However**: This decision was found to be incomplete. See ADR-0002 for the follow-up discovery that Option 1 causes C3+ upgrade conflicts affecting 86+ packages.

## Consequences

### Positive

- libcap and rpm build successfully (the original C1 conflict is resolved)
- No spec file modifications needed
- Reversible by removing the `photon-mainline` key

### Negative

- Exposes the C3+ upgrade conflict pattern (ADR-0002)
- systemd and 85 other packages fail due to `tdnf upgrade` pulling newer versions from remote repo
- Full resolution requires Option 2 or Option 3

## References

- PRD: `specs/prd.md` -- REQ-3
- FRD-C3: `specs/features/c3-subrelease-boundary.md`
- `common/build.py` line 1518-1522: snapshot bypass logic
