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
| `runPh5_normal.sh` | 5.0 | Builds from the `5.0` branch at the current upstream subrelease (`>= 92`). Includes self-healing fixes for spec formatting, OpenJDK WSL2 detection, missing source tarballs, and rpm 6.x bootstrap issues. |
| `runPh5_pinned91.sh` | 5.0 | Builds from the `5.0` branch pinned to `photon-subrelease 91` (6.1.x kernel, python 3.11). Bypasses the spec checker via `base-commit`, removes conflicting python 3.14 / rpm 6.x RPMs from prior `>= 92` builds, and bootstraps `python3-macros` and `rpm-build 4.18.0` from the Broadcom repo. |
| `runPh6.sh` | 6.0 | Builds from the `6.0` branch. Includes OpenJDK WSL2 fix and missing-source prefetch. |

All scripts accept four optional positional parameters: `BASE_DIR`, `COMMON_BRANCH`, `RELEASE_BRANCH`, and `OUTPUT_DIR`.

### workstation-rest01.png
Screenshot reference image.
