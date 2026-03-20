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

### runPh4.sh, runPh5.sh, runPh6.sh
Automated ISO build scripts for Photon OS 4.0, 5.0, and 6.0 respectively. Each script pulls the latest sources, runs `make image` in a retry loop (up to 10 attempts), and copies the resulting ISO to a local download directory.

### workstation-rest01.png
Screenshot reference image.
