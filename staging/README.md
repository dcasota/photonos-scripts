# staging

This subdirectory contains early scripts and prototypes kept for staging purposes. Items here are works in progress or experimental and may not yet be integrated into the main project.

## Contents

### install-sizes-calc/
Package install size estimation for Photon OS, organized into two approaches:
- **shell-based/** -- `DynamicSizeCalculation.sh`: A Bash script that uses `tdnf repoquery` and `tdnf info` to query installed package sizes without downloading, then calculates totals with a configurable buffer and compression ratio estimate.
- **C-based/** -- `tdnf-size-estimate`: A fork of [tdnf](https://github.com/vmware/tdnf) with a native `size-estimate` command added for Docker rootfs tarball size calculation directly in C.

### custom-initramfs-with-ollama/
Script to integrate Ollama and TinyLlama into a Photon OS initramfs using Dracut, enabling LLM inference during the early boot phase. See [custom-initramfs-with-ollama/README.md](custom-initramfs-with-ollama/README.md) for details.

### custom-4.0-installer/
Custom Photon OS 4.0 installer repository for building minimal x86_64 ISO images using the poi-in-a-container approach. Contains a modified photon-os-installer (v2.7) with Dockerfiles and configuration for custom ISO builds. See [custom-4.0-installer/README.md](custom-4.0-installer/README.md) for details. Related upstream issue: [vmware/photon-os-installer#35](https://github.com/vmware/photon-os-installer/issues/35#issuecomment-3062141397).

### ISO Build Scripts

Automated ISO build scripts for Photon OS. Each script pulls the latest sources from [dcasota/photon](https://github.com/dcasota/photon), runs `make image` in a retry loop (up to 10 attempts), and copies the resulting ISO to a configurable output directory (`/mnt/c/Users/dcaso/Downloads/Ph-Builds` by default).

| Script | Photon | Description |
|--------|--------|-------------|
| `runPh4.sh` | 4.0 | Builds from the `4.0` branch. |
| `runPh5_normal.sh` | 5.0 | Builds from the `5.0` branch at the current upstream subrelease (`>= 92`). Applies the bundled `photonos-patches/downstream-fixes.patch` (installer + package fixes), builds the `photon/installer` POI image when missing, and includes self-healing fixes for spec formatting, OpenJDK WSL2 detection, missing source tarballs, and rpm 6.x bootstrap issues. |
| `runPh5_pinned90.sh` | 5.0 | Builds from the `5.0` branch pinned to `photon-subrelease 90` (older GA ecosystem: python 3.11, libcap 2.x, rpm 4.x, nginx 1.26.x). Activates the large `SPECS/90/` gated set — useful to build/verify SPECS/90 packages (e.g. the `SPECS/90/nginx` CVE-2026-42945 backport). Pins via `base-commit` bypass and excludes `libcap-libs`; a fully-clean ISO may need additional subrelease-90 bootstrap fixes added iteratively (as in the 91 script). |
| `runPh5_pinned91.sh` | 5.0 | Builds from the `5.0` branch pinned to `photon-subrelease 91` (6.1.x kernel, python 3.11). Bypasses the spec checker via `base-commit`, removes conflicting python 3.14 / rpm 6.x RPMs from prior `>= 92` builds, and bootstraps `python3-macros` and `rpm-build 4.18.0` from the Broadcom repo. |
| `runPh6.sh` | 6.0 | Builds from the `6.0` branch. Includes OpenJDK WSL2 fix and missing-source prefetch. |
| `runPh7-2-7.sh` | 5.0 | **Experimental.** Photon 5.0 userland with Linux 7.2.7 instead of 6.12, from the `experimental/linux-7.2.7` branch. Wraps `runPh5_normal.sh`; see [runPh7-2-7.sh (experimental Linux 7.2.7)](#runph7-2-7sh-experimental-linux-727) below. |

All scripts accept four optional positional parameters: `BASE_DIR`, `COMMON_BRANCH`, `RELEASE_BRANCH`, and `OUTPUT_DIR`.

#### runPh7-2-7.sh (experimental Linux 7.2.7)

Builds a Photon OS 5.0 ISO whose kernel (`linux` and `linux-esx`) is Linux 7.2.7 while the
rest of the userland stays on the regular 5.0 (subrelease `>= 92`) package set. The release
tree is the `experimental/linux-7.2.7` branch of [dcasota/photon](https://github.com/dcasota/photon).
This is a prototype for trying a newer kernel line on Photon 5.0, not a supported build.

```sh
./runPh7-2-7.sh [BASE_DIR] [COMMON_BRANCH] [RELEASE_BRANCH] [OUTPUT_DIR] [IMG_TYPE] [CANISTER_MODE]
```

| Parameter | Default |
|-----------|---------|
| `BASE_DIR` | `/root` |
| `COMMON_BRANCH` | `common` |
| `RELEASE_BRANCH` | `experimental/linux-7.2.7` |
| `OUTPUT_DIR` | `/mnt/c/Users/dcaso/Downloads/Ph-Builds` |
| `IMG_TYPE` | `minimal-iso` |
| `CANISTER_MODE` | `none` (`prebuilt` is forced to `none`: the prebuilt canister is a 6.12 artifact) |

How it works:

- **Wrapper, not a fork.** It needs `runPh5_normal.sh` next to it (or in `$HOME`,
  `$HOME/staging`, `/root`, `/root/staging` or `/root/photonos-scripts/staging`). From that script it
  generates a temporary build script, rewired to the 7.2.7 release branch and to the
  `common` tree as `common-branch-path`, then runs it.
- **Self-contained pin.** All 7.2.7 adjustments are embedded in the wrapper and re-applied
  before every `make`, because `runPh5_normal.sh` may `git checkout` specs in between. There is no
  separate pin script any more; the former standalone `pin-linux-7.2.7.sh` was removed.
- **Kernel spec pinning.** Forces `Version: 7.2.7` and the v7.x source URL, and applies
  only Patch0 and Patch1, since the other Photon patches are rebased for 6.12. It also leaves the kernel CVE
  patch include (Patch3000-3999) empty, and replaces the 6.12 config-applicability check with an
  `olddefconfig` merge. That merge keeps Photon's `=y`/`=m` symbols that still exist, takes upstream defaults for new
  Kconfig symbols, and turns off io_uring BPF. It skips the Amazon ENA/EFA and viomem out-of-tree modules.
- **Userland fixes needed to finish the ISO.** Rust built with `LANG=C` and docs off, a
  PostgreSQL 18 configure cache fix, subversion without `/usr/lib/debug`, docker and
  apparmor build fixes, and repair of a broken host or sandbox `/dev/null` before the ISO step.
- **STIG packages.** Before `make image`, builds the set the installer asks for:
  `audit`, `rsyslog`, `openssl-fips-provider`, `selinux-policy`, `libselinux-utils`, `ntpsec`,
  `aide` and `libgcrypt`.
- **Self-healing.** It removes leftovers of older wrapper versions in `common`: a
  "7.2.7 SpecData compatibility" wrap in `SpecData.py` that failed builds with
  `Invalid package: aide-0.19-3.ph5`, and commented-out `build_if` gates in specs.

Environment knobs: `FORCE_WIPE_LINUX=1` rebuilds the kernel sandboxes from scratch
(they are kept by default).

Known limitation: `build.py` runs the spec checker only when stdout is **not** a terminal
(for example `nohup`, CI, or output redirected to a file). The pinned `linux-esx.spec` declares
patches that are not applied, so the checker rejects it. Run the wrapper from an interactive
terminal.

Verified result (wrapper v9): `photon-minimal-5.0-<commit>.x86_64.iso` (about 523 MB) with kernel
`7.2.7-1.ph5`. A full build takes about an hour. The ISO boots to the Photon installer under
QEMU/KVM in both BIOS and UEFI (OVMF) mode; installing from it has not been verified yet.

### mission-control/
The matrix's configuration and evidence: `config/permutations.tsv` (the executable
form of the matrix), the VMX template, and `results/`. The bash harness that used to
live here has been absorbed into `sharukhan-cli` and is kept, unused, under
`superseded-bash/` with a README naming what replaced each script — and six latent
bugs found while porting.

It is committed now. What kept it out of the repository was a literal throwaway
password in its config; `MC_GUEST_PASSWORD` is required with no default, and a test
guards against a default coming back.

### sharukhan-cli/
The harness. One Rust binary drives the whole matrix: it builds one ISO per
build-time axis tuple, injects the install-time axes per VM via
`guestinfo.kickstart.data`, verifies each installed guest over SSH, and harvests the
evidence. Every verdict is gated on the media genuinely containing the packages under
test, because a stale ISO otherwise produces passes that mean nothing.

`doctor`, `plan`, `run`, `stop`, `watch`, `report`, `findings`, `status`, `card`,
`canister`, `build-iso`, `variant-patches`. Findings persist in SQLite so they outlive
the session that produced them. See [sharukhan-cli/README.md](sharukhan-cli/README.md).

What remains a subprocess is either a Windows binary (`vmrun.exe`,
`vmware-vdiskmanager.exe`), the system under test (`make`/`build.py`), or a deliberate
instrument: `ssh` stays exec'd because a FIPS defect was once found through OpenSSH's
own error text, and a different client would change what the harness observes.

### photonos-patches/
`downstream-fixes.patch` — the accumulated downstream spec/installer fixes applied by
the `runPh*.sh` scripts. mission-control generates per-variant copies of this from the
open PR branches so a PR can be tested before it merges.

### Reference documents
- [ISO-PERMUTATION-MATRIX.md](ISO-PERMUTATION-MATRIX.md) — the five install axes
  (ISO type, installer version, STIG, filesystem, UI vs kickstart), why they collapse
  to 34 rows rather than 512, and the measured verdict for each.
- [COMPILE-CONSTELLATIONS.md](COMPILE-CONSTELLATIONS.md) — the build-side axes:
  release line, subrelease gating, architecture, image type and flavor, kernel flavor,
  POI version, EFI/BIOS, Secure Boot, SELinux mode, output format.

### workstation-rest01.png
Screenshot reference image.
