# Photon OS Offline Mirror

Docker image based on `photon:5.0-20251221` that mirrors Photon OS documentation, the Broadcom Artifactory package repository index, and all relevant GitHub repositories for offline access.

## Contents

| Component | Source | Local path |
|-----------|--------|------------|
| Documentation website | https://vmware.github.io/photon/ | `/mirror/docs/` |
| Broadcom Artifactory index | https://packages.broadcom.com/artifactory/photon/ | `/mirror/artifactory/` |
| vmware/photon | https://github.com/vmware/photon | `/mirror/repos/photon/` |
| vmware/photon-os-installer | https://github.com/vmware/photon-os-installer | `/mirror/repos/photon-os-installer/` |
| vmware/tdnf | https://github.com/vmware/tdnf | `/mirror/repos/tdnf/` |
| vmware/photon-docker-image | https://github.com/vmware/photon-docker-image | `/mirror/repos/photon-docker-image/` |
| vmware/dod-compliance-and-automation | https://github.com/vmware/dod-compliance-and-automation | `/mirror/repos/dod-compliance-and-automation/` |
| vmware/open-vm-tools | https://github.com/vmware/open-vm-tools | `/mirror/repos/open-vm-tools/` |
| vmware/pmd-next-gen | https://github.com/vmware/pmd-next-gen | `/mirror/repos/pmd-next-gen/` |
| vmware/pmd | https://github.com/vmware/pmd | `/mirror/repos/pmd/` |

## Build

```bash
docker build -t photonos-mirror .
```

## Usage

```bash
# Run and show mirror summary
docker run --rm photonos-mirror

# Extract mirror to a local directory
docker run --rm -v /path/to/local:/export photonos-mirror \
    sh -c "cp -r /mirror/* /export/"

# Browse documentation offline
docker run --rm -v /path/to/local:/export photonos-mirror \
    sh -c "cp -r /mirror/docs/* /export/"
```

## Notes

- All git repositories are cloned with `--depth 1` (latest commit only) to reduce image size.
- The Artifactory mirror is depth-limited (`-l 2`) to capture the repository index structure without downloading all RPM packages. To mirror full RPM content, increase the depth or use a dedicated `reposync` approach.
- The documentation mirror uses `wget --mirror` with link conversion for offline browsing.
- Rebuild the image periodically to refresh the mirror with upstream changes.
