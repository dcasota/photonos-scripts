# ADR-0002: tdnf Upgrade Conflict When Snapshot is Bypassed

**Date**: 2026-03-06
**Status**: Accepted (problem identified, remediation pending)

## Context

ADR-0001 set `photon-mainline=91` to bypass snapshot 91 for the 5.0 branch. This resolved the C1 libcap split conflict. However, the build still fails on systemd-253.19-17.ph5 with:

```
package libcap-devel-2.66-4.1.ph5.x86_64 requires libcap = 2.66-4.1.ph5,
but none of the providers can be installed
```

### Root Cause

The Photon OS build system (`PackageUtils.py`) runs three tdnf commands in sequence:

1. `tdnf makecache` -- refresh repo metadata
2. `tdnf upgrade` -- upgrade ALL packages in the installroot to latest from repo
3. `tdnf install <specific-versioned-packages>` -- install build dependencies

Step 2 is the problem. Without a snapshot filter, the remote repo at `packages.broadcom.com` serves ALL available packages, including:

- `libcap-2.77-1.ph5` (from the new >= 92 spec, published to repo)
- `Linux-PAM-1.7.2-1.ph5` (from the new >= 92 spec)
- `dbus-1.16.2-1.ph5` (from the new >= 92 spec)

The `tdnf upgrade` step pulls these newer versions. Then step 3 tries to install `libcap-devel-2.66-4.1.ph5` (built locally from the <= 91 spec), which `Requires: libcap = 2.66-4.1.ph5` (exact version pin). But libcap is now 2.77 in the installroot. Unresolvable.

### Blast Radius

The gating conflict detection agent identified **86 C3 CRITICAL findings** across 6 root-cause packages:

| Gated Package | Old (active) | New (in remote) | Consumers |
|--------------|-------------|-----------------|-----------|
| Linux-PAM | 1.5.3 | 1.7.2 | 32 |
| dbus | 1.15.4 | 1.16.2 | 21 |
| libcap | 2.66 | 2.77 | 18 |
| gawk | 5.1.1 | 5.3.2 | 11 |
| docker | 28.2.2 | 29.2.1 | 3 |
| containerd | 2.1.5 | 2.2.1 | 1 |

## Considered Options

### Option A: Use a valid snapshot

Create or find a snapshot that contains exactly the old package versions. This prevents `tdnf upgrade` from seeing newer versions.

**Pros**: Clean fix. The snapshot filter is designed for exactly this purpose.
**Cons**: Snapshot 91 is stale. A new snapshot would need to be built.

### Option B: Upgrade to subrelease 92

Set `photon-subrelease=92` and `photon-mainline=92`. All specs activate at >= 92, matching the remote repo contents.

**Pros**: Full consistency between specs, local builds, and remote repo.
**Cons**: Changes the kernel version from 6.1 to 6.12 for branch 5.0.

### Option C: Modify build system to exclude gated packages from upgrade

Patch `PackageUtils.py` to run `tdnf upgrade --exclude=<gated-packages>` or skip the upgrade step entirely for packages with `build_if` gating.

**Pros**: Surgical fix that addresses the exact root cause.
**Cons**: Requires modifying the Photon OS build system (upstream change).

### Option D: Pin gated packages in tdnf upgrade

Add `--exclude` flags for all packages that have gated spec pairs where the old version is active.

**Pros**: No spec changes needed, no subrelease change.
**Cons**: Requires dynamic computation of the exclude list per build.

## Decision Outcome

**No single option is sufficient**. The recommended approach is:

1. **Short-term**: Option B (upgrade to subrelease 92) if the 6.12 kernel is acceptable
2. **Medium-term**: Option C (patch build system) to make the `tdnf upgrade` step gating-aware
3. **Long-term**: Redesign the snapshot mechanism to be commit-aware, not just subrelease-aware

The detection agent (this project) enables Option D by producing the exact list of gated packages per branch, which could be consumed as an `--exclude` list.

## Consequences

### Positive

- Root cause of the systemd failure is fully understood
- The C3+ detection pattern is now implemented in the agent
- Blast radius is quantified: 86 packages across 6 root-cause gated packages

### Negative

- No clean fix exists that doesn't require either a subrelease change or a build system patch
- The `photon-mainline` bypass (ADR-0001) is necessary but insufficient

## References

- ADR-0001: `specs/adr/0001-snapshot-bypass-via-photon-mainline.md`
- FRD-C3: `specs/features/c3-subrelease-boundary.md`
- Findings: `specs/findings/2026-03-06-findings.json`
- `common/support/package-builder/PackageUtils.py`: `installRPMSInOneShot()` method
- `common/support/package-builder/TDNFSandbox.py`: repo configuration and snapshot handling
