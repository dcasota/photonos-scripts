# custom-4.0-installer

Custom Photon OS 4.0 installer repository for building minimal x86_64 ISO images using the poi-in-a-container approach.

## Background

This work originates from the investigation documented in [vmware/photon-os-installer#35 (comment)](https://github.com/vmware/photon-os-installer/issues/35#issuecomment-3062141397), which tracks the issue of Photon OS 4.0 x86_64 provisioning failing when STIG hardening is enabled.

The official Photon OS 4.0 minimal ISO does not support STIG hardening during installation. The root causes are:
- **tdnf version dependency**: The photon-os-installer package built for 5.0 depends on tdnf >= 3.5.6, which is not available in 4.0. The workaround is to use the 4.0-native `photon-os-installer` 2.7-4.ph4 (with tdnf 3.3.12-1.ph4).
- **POI_IMAGE URL dependency**: The `poi.py` script contains hardcoded container image URLs for the installer initrd, which are release-specific and may break in the future.
- **Ansible locale issue**: When STIG hardening is enabled, the ansible playbook fails with `Ansible requires the locale encoding to be UTF-8: Detected None`, and additional space constraints on `/dev/shm` prevent resolution during install.

Backporting the full functionality bundle to 4.0 is not planned upstream. The supported migration path is to upgrade from 4.0 to 5.0 and activate hardening settings afterwards.

## Archive Contents

`custom-4.0-installer-repo.tar.gz` contains a cloned [photon-os-installer](https://github.com/vmware/photon-os-installer) repository (tag v2.7) with custom additions for building minimal Photon OS 4.0 x86_64 ISO images. The archive structure is:

```
repo/4.0/photon-os-installer/
├── docker/                          # Container build scripts and Dockerfiles
│   ├── Dockerfile                   # Main installer container Dockerfile
│   ├── build-rpms.sh                # RPM build helper script
│   ├── create-image                 # Image creation script
│   └── ...
├── minimal-iso-4.0_x86_64/         # Custom minimal ISO build configuration
│   ├── Dockerfile                   # Dockerfile for minimal ISO builds (uses 4.0-20250727 base)
│   └── installer/                   # Installer JSON configuration files
│       ├── packages_minimal.json
│       ├── packages_installer_initrd.json
│       ├── build_install_options_minimal.json
│       └── ...
├── minimal-iso-4.0_x86_64.zip      # Packaged minimal ISO build files
├── modifications.zip                # Optional UI menu extensions (e.g., API key input)
├── photon_installer/                # Python installer source code
│   ├── installer.py
│   ├── iso_config.py
│   └── ...
├── examples/                        # Example kickstart and config files
├── docs/                            # Documentation (ks_config, ui_config)
├── photon-os-installer.spec
├── setup.py
└── .git/                            # Git metadata (v2.7 tag)
```

## Usage

### Prerequisites

```bash
tdnf makecache
tdnf install -y git docker docker-buildx unzip wget
systemctl enable docker
systemctl start docker
docker login
```

### Building a Minimal Photon OS 4.0 ISO

```bash
# Extract the repository
cd $HOME
tar xzf custom-4.0-installer-repo.tar.gz
cd repo/4.0/photon-os-installer

# Unzip the minimal ISO build configuration
unzip ./minimal-iso-4.0_x86_64.zip

# (Optional) Apply UI menu extensions (e.g., API key input during setup)
unzip ./modifications.zip
mv ./iso_config.py photon_installer/
mv ./installer.py photon_installer/

# Build the container
CONTAINERNAME="photon-os-installer"
docker buildx build -t $CONTAINERNAME \
  --build-context poi-helper=$HOME/repo/4.0/photon-os-installer \
  ./minimal-iso-4.0_x86_64/.

# Run the container interactively
docker run --rm -it --privileged \
  -v /dev:/dev \
  -v $HOME/repo/4.0/photon-os-installer/minimal-iso-4.0_x86_64:/output \
  $CONTAINERNAME /bin/bash
```

Inside the container:
```bash
cd examples/iso
photon-iso-builder -y iso.yaml
cp photon-4.0.iso /output
```

### Key Modification for 4.0 Compatibility

As described in [the upstream discussion](https://github.com/vmware/photon-os-installer/issues/35#issuecomment-3062141397), to resolve the tdnf dependency conflict when building 4.0 ISOs:

1. Remove `/poi` from `repo_paths` in the ISO configuration.
2. Remove version-pinned RPM entries (`photon-os-installer-2.4-1.ph5.x86_64.rpm` and the aarch64 variant) from `packages_installer_initrd.json`.
3. Add `photon-os-installer` (without a version) to the package list so that the 4.0-native version is installed.

## Current Status

| Scenario | Status |
|----------|--------|
| Minimal x86_64 Ph4 ISO builds successfully | Working |
| VM setup with Generic kernel, STIG hardening = No | Working |
| VM setup with Generic kernel, STIG hardening = Yes | **Fails** (ansible locale/space issues) |
| VM setup with VMware hypervisor optimized kernel | **Fails** (missing packages) |

## Related Links

- [vmware/photon-os-installer#35](https://github.com/vmware/photon-os-installer/issues/35) -- Original issue: Provisioning of Ph4 x86_64 fails with stig hardening=yes
- [vmware/photon-os-installer#35 (comment)](https://github.com/vmware/photon-os-installer/issues/35#issuecomment-3062141397) -- Detailed status update and test script
- [photon-os-installer Docker README](https://github.com/vmware/photon-os-installer/tree/master/docker#readme) -- Official container-based build documentation
- [vmware/photon-os-installer](https://github.com/vmware/photon-os-installer) -- Upstream photon-os-installer repository
