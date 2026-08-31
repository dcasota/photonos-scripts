# staging

This subdirectory contains early scripts and prototypes kept for staging purposes. Items here are works in progress or experimental and may not yet be integrated into the main project.

## Contents

### vm-lab/
End-to-end provisioning of a Photon OS VM on VMware Workstation: the VMX
template (every non-default key annotated with the failure it prevents), the
boot VMDK, the kickstart, an unattended install, SSH access, teardown, and the
verification scripts that say whether each stage actually did what it claims.
Defaults to **2 vCPU / 4 GB RAM / 50 GB thin disk in a single file**
(`monolithicSparse` — the size is a ceiling, not an allocation: a fresh disk
is ~6 MB and grows on use). Overridable per run.

Two things it documents that are easy to lose a day to: SSH access is decided
at **ISO build time** (the key variables default to empty, so a normal build
ships an empty `authorized_keys` and a locked root), and the install CDROM must
be on SATA because the `linux-mok` kernel has no IDE CDROM driver. See
[vm-lab/README.md](vm-lab/README.md); provenance and the kickstart-drift check
are in [vm-lab/PROVENANCE.md](vm-lab/PROVENANCE.md).

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

All scripts accept four optional positional parameters: `BASE_DIR`, `COMMON_BRANCH`, `RELEASE_BRANCH`, and `OUTPUT_DIR`.

### workstation-rest01.png
Screenshot reference image.
