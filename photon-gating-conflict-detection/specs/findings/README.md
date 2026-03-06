# Scan Findings

Timestamped snapshots of detection runs. Each scan produces a JSON + Markdown pair.

## 2026-03-06

**Branches**: 4.0, 5.0, 6.0
**Configuration**: 5.0 subrelease=91 mainline=91, 6.0 subrelease=92 mainline=92

| Severity | Count |
|----------|-------|
| CRITICAL | 89 |
| HIGH | 4 |
| WARNING | 4 |
| **Total** | **97** |

| Constellation | Count |
|--------------|-------|
| C1 (package split) | 3 |
| C2 (version bump deps) | 4 |
| C3 (boundary / upgrade conflict) | 86 |
| C4 (cross-branch) | 2 |
| C5 (FIPS canister) | 2 |

**Key Discovery**: Setting `photon-mainline=91` to bypass snapshot resolves C1 (libcap split) but exposes C3+ (tdnf upgrade pulls newer packages from remote repo), affecting 86 packages including systemd, openssh, sudo.

Files:
- `2026-03-06-findings.json` (machine-readable)
- `2026-03-06-findings.md` (human-readable)

**Note**: Spec paths in findings reference the local build tree where the scan was executed. When running in CI, paths will reflect the workspace checkout layout instead.
