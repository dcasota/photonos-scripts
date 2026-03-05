# Photon OS `photon-mainline` Key: Analysis and Impact

## Background

On March 5, 2026, commit [`d78115d`](https://github.com/vmware/photon/commit/d78115d55de328a4559b39432da9c507794c0394) on the **5.0 branch** of [vmware/photon](https://github.com/vmware/photon) introduced a new key `"photon-mainline"` in `build-config.json`.

### The change

```diff
 {
   "photon-build-param": {
     "photon-dist-tag": ".ph5",
     "photon-release-version": "5.0",
     "photon-subrelease": "92",
+    "photon-mainline": "92",
     "photon-docker-image": "photon:5.0",
     ...
   }
 }
```

The new key sits alongside the existing `"photon-subrelease": "92"`, and both currently share the same value.

### What `photon-mainline` represents

The Photon OS build system uses `build-config.json` to control release metadata. Until now, `photon-subrelease` served as the single counter that:

1. **Identifies vendor-pinned package directories** -- packages that need a specific version for a given subrelease are placed under `SPECS/<subrelease>/` (e.g. `SPECS/91/dbus/`, `SPECS/92/containerd/`).
2. **Tracks the overall build iteration** of the release branch.

The introduction of `photon-mainline` separates these concerns. `photon-subrelease` continues to identify the subrelease-specific directory for vendor-pinned packages, while `photon-mainline` tracks the mainline iteration counter. Today both values are `92`. In the future they may diverge -- for example, when a subrelease-specific patch directory retains its number while the mainline iteration advances, or when multiple subrelease directories coexist.

This is consistent with how `build-config.json` on the **master branch** does *not* carry either key (master uses a different, more extensive configuration structure), confirming that `photon-subrelease` and `photon-mainline` are release-branch-specific concepts (4.0, 5.0, 6.0).

## Impact analysis on photonos-scripts subtools

The following table summarises the impact on each subtool in this repository.

| Subtool | Impact | Explanation |
|---|---|---|
| **photonos-package-report** | Low-to-Medium (monitor) | See [detailed analysis](#photonos-package-report) below. |
| **staging/runPh5.sh** | None | Invokes `make image`; the build system reads the new key transparently. |
| **HABv4SimulationEnvironment** | None | Derives `.ph5` dist tag from the release version character; does not read `build-config.json`. |
| **kernelpatches** | None | Works with NVD data and kernel SRPM naming; no dependency on `build-config.json`. |
| **cve-aggregator** | None | Filters by `.ph5` version strings in published advisory data; unrelated to build config. |
| **docsystem** | None | References `photon-build-config.txt` only in a markdown formatting rule. |
| **SnykAnalysis** | None | Snyk vulnerability scanning; unrelated. |
| **SPAGAT-Librarian** | None | CLI Kanban board; unrelated. |
| **kube.academy** | None | Kubernetes learning scripts; unrelated. |
| **PwshOnPhotonOS** | None | PowerShell installation scripts; unrelated. |

### photonos-package-report

The `ParseDirectory` function in `photonos-package-report.ps1` (line 224) detects numeric subdirectories under `SPECS/` by matching directory names against the pattern `^\d+$`. It tags packages found in those directories with a `SubRelease` property and:

- **Skips upstream version checks** for vendor-pinned packages (line 2058), labeling them e.g. `vendor-pinned (subrelease 91)`.
- **Excludes them from cross-release diff reports** (line 5252) to prevent false-positive version regressions.
- **Appends them as separate rows** with a `SubRelease` column in the package report (line 5269).

**Current state:** The script discovers subreleases entirely by scanning the filesystem. It does not read `build-config.json`. Since both `photon-subrelease` and `photon-mainline` are `92` today, no behaviour change occurs.

**Future risk:** If the Photon OS team uses diverging values for `photon-mainline` and `photon-subrelease` to restructure how `SPECS/<number>/` directories work, the package report script would need to be updated to:

1. Read `build-config.json` from the cloned Photon repository.
2. Distinguish "current mainline" packages from "old subrelease-pinned" packages.
3. Adjust report labeling and diff-report filtering accordingly.

### staging/runPh5.sh

The build script clones the 5.0 branch and runs `make image`. The Photon build system (`Makefile` and Python build scripts) internally parses `build-config.json`. The new `photon-mainline` key is consumed by the upstream build machinery without any change needed in `runPh5.sh`.

### HABv4SimulationEnvironment

The `rpm_secureboot_patcher.c` constructs the dist tag as `.ph5` by reading the first character of the release version string (line 372). Driver spec files hardcode `1.ph5` in their `Release:` fields. None of these code paths reference `build-config.json` or use `photon-subrelease`/`photon-mainline`.

## Recommendations

1. **No immediate action required** -- all subtools continue to work correctly with the current `build-config.json` state.
2. **Monitor upstream changes** -- watch for future commits on the 5.0 (and 4.0/6.0) branches where `photon-mainline` and `photon-subrelease` diverge.
3. **Plan for photonos-package-report enhancement** -- if divergence occurs, update `ParseDirectory` to read `build-config.json` from the cloned Photon branch and use `photon-mainline` to determine which packages are in the current mainline vs. vendor-pinned to a specific subrelease.

## References

- Commit: [vmware/photon@d78115d](https://github.com/vmware/photon/commit/d78115d55de328a4559b39432da9c507794c0394)
- Photon OS 5.0 `build-config.json`: [5.0 branch](https://github.com/vmware/photon/blob/5.0/build-config.json)
- Photon OS master `build-config.json`: [master branch](https://github.com/vmware/photon/blob/master/build-config.json)
- photonos-package-report script: [photonos-package-report.ps1](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/photonos-package-report.ps1)