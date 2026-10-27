# Configuration

[← sharukhan overview](../README.md)

**Who this is for:** Anyone who needs to know which setting controls what, where the secret files live, and what sits in each directory of the work root.

**Contents**

- [Configuration](#configuration)
- [The directory layout](#the-directory-layout)

## Configuration

### Paths, the VM and the network

Every path has a default and an environment override. Nothing is tied to one
machine.

| Variable | Default |
| --- | --- |
| `PHOTON_TREE` | `/root/5.0` |
| `POI_TREE` | `/root/photon-os-installer` |
| `PHOTON_SCRIPTS` | `/root` |
| `SHARUKHAN_ROOT` | `/root/photonos-scripts/staging/mission-control` |
| `SHARUKHAN_MATRIX` | `$SHARUKHAN_ROOT/config/permutations.tsv` |
| `SHARUKHAN_DB` | `/root/photon-mc/memory.db` |
| `MC_RESULTS_DIR` | `/root/photon-mc/results` |
| `MC_BUILD_LOG_DIR` | `/root/photon-mc/build-logs` |
| `MC_RUN_LOG_DIR` | `/root/photon-mc/run-logs` |
| `MC_WORK` | `/root/photon-mc/work` |
| `MC_VARIANT_PATCH_DIR` | `/root/photon-mc/variant-patches` |
| `MC_ISO_CACHE` | `/mnt/c/photon-mc/iso-cache` |
| `MC_VM_ROOT_WSL` | `/mnt/c/photon-mc/vm` |
| `MC_DHCP_LEASES` | `/mnt/c/ProgramData/VMware/vmnetdhcp.leases` |
| `VMRUN` | `/mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe` |
| `VDISKMANAGER` | `/mnt/c/Program Files/VMware/VMware Workstation/vmware-vdiskmanager.exe` |
| `MC_BUILD_ROOT` | `/root` |
| `MC_BUILD_COMMON` | `common` |
| `MC_RELEASE` | `5.0` |
| `MC_PHOTON_REMOTE` | `https://github.com/dcasota/photon.git` |
| `GUEST_VCPUS` | `2` |
| `GUEST_MEM_MB` | `4096` |
| `BOOT_DISK_SIZE` | `32GB` |
| `BOOT_DISK_ADAPTER` | `lsilogic` |
| `BOOT_DISK_TYPE` | `0` |
| `MC_NET_PREFIX` | `192.168.225` |
| `MC_NET_GATEWAY` | `<MC_NET_PREFIX>.2` |
| `MC_NET_DNS` | `<MC_NET_PREFIX>.2` |
| `MC_NET_CIDR` | `24` |
| `MC_NET_V6_PREFIX` | `fd00:225` (a ULA — see the network axis below) |
| `MC_NET_VLAN_PREFIX` | `192.168.100` |
| `MC_IP_BASE` | `40` |
| `MC_NIC_DEV` | `e1000` |
| `SSH_KEY_DIR` | `$HOME/.ssh` |
| `SSH_KEY_NAME` | `photon-mc-rsa` |
| `SSH_USER` | `root` |
| `MC_GUEST_PASSWORD` | **required, no default** — the root password of every VM the harness installs (or `MC_GUEST_PASSWORD_FILE`, below) |
| `SERIAL_LOG_PREFIX` | `serial0` |
| `MC_INSTALL_TIMEOUT_SEC` | `2400` |
| `MC_BOOT_TIMEOUT_SEC` | no effect: nothing reads it, a warning says so (installs use `MC_INSTALL_TIMEOUT_SEC`) |
| `MC_SSH_TIMEOUT_SEC` | no effect, as above |
| `MC_SAMPLE_SEC` | no effect, as above |
| `MC_START_TIMEOUT` | `240` |

```
SHARUKHAN_DB=/tmp/other.db sharukhan findings
```

### The settings file and the secret files

The services read `/etc/sharukhan/sharukhan.env` (written by
`sharukhan service install`); `env-isolated.sh` loads the same file for
commands run by hand. It holds `KEY="value"` lines and nothing secret. A
secret is a file named by a setting, owned by the reading user, mode 0600, in
a directory nobody else can write:

| Setting | Points to | Read by |
|---|---|---|
| `MC_GUEST_PASSWORD_FILE` | the guest root password | everything that installs or configures a guest, when `MC_GUEST_PASSWORD` is not set |
| `MC_ANTHROPIC_KEY_FILE` | the Anthropic API key | the escalation, before `ANTHROPIC_API_KEY` |

A test (`every_variable_the_code_reads_is_classified`) fails when the code
reads an environment variable that is neither a service setting, a secret
pointer, a secret nor named as something else, so a new setting cannot be
left out of the services by accident.

### Settings of the build, the fork and the sync

| Variable | Default | Meaning |
| --- | --- | --- |
| `MC_FORK` | `dcasota/photon` | the fork whose PRs are gated and synced |
| `MC_UPSTREAM` | `vmware/photon` | the upstream repository of the fork |
| `MC_FORK_INSTALLER` / `MC_UPSTREAM_INSTALLER` | `dcasota/photon-os-installer` / `vmware/photon-os-installer` | the same for the installer |
| `MC_INSTALLER_BRANCH` | `master` | the installer branch |
| `MC_GATE_REPO` | `/root/photon-mc/gate/photon.git` | the gate repository (bare) |
| `MC_AUTHOR` | the gate repository's git `user.name` and `user.email` | `Name <mail>` of rebased commits and changelog entries; with neither, a sync refuses |
| `MC_BUILDER` | `host` | `host` or `container`: where make and the spec tools run |
| `MC_BUILDER_SHARED_ROOT` | `/root/photon-mc/gate` | the shared bind mount of the builder container |
| `MC_BUILDER_DIR` | `/root/photon-mc/gate/builder` | the builder image's context |
| `MC_ISO_STORE` | none | where finished ISOs are moved; the cache keeps a link |
| `SHARUKHAN_VARIANTS` | `$SHARUKHAN_ROOT/config/variants.conf` | installer variants and common branches |
| `SHARUKHAN_CHECK_PRS` | `$SHARUKHAN_ROOT/config/check-prs.tsv` | check to PR attribution |
| `MC_FASTLOOP_ROWS` | `k03 c03` | rows of a sync's FASTLOOP (minimal ISOs of the default variant) |
| `MC_STAGED_ROWS` | `k11` | rows of a sync's STAGEVM |
| `MC_PUBLISH_DCASOTA` | `auto` | `auto`, `approve` or `preview` (see the sync chapter) |
| `MC_NOTIFY` | `file:/root/photon-mc/events.log` | notification channels |
| `SHARUKHAN_SYNC_QUIET` | `7200` | seconds a base must be quiet before `sync auto` starts a run |
| `SHARUKHAN_SYNC_EVERY` | `30min` | the sync timer's interval (service option) |
| `SHARUKHAN_WATCH_INTERVAL` | `900` | the watcher's interval in seconds (service option) |

The escalation's settings are in its own chapter.

## The directory layout

Each directory belongs to one setting; `sharukhan settings` prints the values
on a host (`eval "$(sharukhan settings)"` sets them in a shell). With the
layout the 2026-10 host used (`<work root>` = `/root/photon-mc`):

| Directory (2026-10 example) | Setting | Holds | Safe to delete? |
|---|---|---|---|
| `<work root>/gate/photon.git` | `MC_GATE_REPO` | the bare gate repository: release branch, PR branches, local kernel branches | no - the source of every build |
| `<work root>/gate/build-root/{5.0,common}` | `MC_BUILD_ROOT`, `MC_RELEASE`, `MC_BUILD_COMMON` | the build trees of the regular ISOs, reset to the gate branches before each gate (`sharukhan sync reset-trees`) | no while a build runs; rebuilt otherwise |
| `<work root>/gate/work` | `MC_WORK` | sharukhan's work: `kbuild/<kernel>` (a kernel profile's own build root), `scriptdir/` (staged build directories), `photon-variants/` (the clone variant patches are made in), `common-check/` (the checker tree), `poi-image/` | `kbuild/<kernel>` once its ISO is stored and tested; the rest is recreated |
| `<work root>/gate/variant-patches` | `MC_VARIANT_PATCH_DIR` | `poi-<variant>.patch`, `common-fixes.patch`; `k<kernel>/` for a kernel profile | regenerated by `variant-patches` |
| `<work root>/gate` | `MC_BUILDER_SHARED_ROOT` | the shared bind mount the builder container sees; everything a build touches lives under it | no |
| `<work root>/results/<row>` | `MC_RESULTS_DIR` | each row's checks (`checks-<stamp>.jsonl`), harvested logs, serial logs - the evidence | no, it is indexed into memory.db |
| `<work root>/run-logs` | `MC_RUN_LOG_DIR` | one log per `run` job; the script's own logs (`kernel-iso-<kernel>-<step>-<stamp>.log`) | old ones, yes |
| `<work root>/build-logs` | `MC_BUILD_LOG_DIR` | one log per ISO build; `failed-attempts/` keeps the package logs of failed `make` attempts | old ones, yes |
| `<work root>/memory.db` | `SHARUKHAN_DB` | jobs, runs, findings, sync runs, escalations | no |
| an ISO cache, e.g. `C:\photon-mc\iso-cache-gate` | `MC_ISO_CACHE` | per build tuple `<type>-poi<variant>-<canister>/`: `photon.iso` (a link), `photon.iso.sha256`, `poi-nevr.txt`, `inputs.txt`; `k<kernel>/` for a kernel profile | links only; the ISO is in the store |
| an ISO store, e.g. `C:\Users\<user>\Downloads\Ph-Builds` | `MC_ISO_STORE` | the ISOs themselves, `<tuple>__<file>.iso` | an ISO nothing links to; renaming one breaks its cache link (`verify_media` then needs `ISO=`) |
| a VM store, e.g. `C:\photon-mc\vm` | `MC_VM_ROOT_WSL` | `mc-<row>/`: one VM per matrix row, recreated for every run | not while a run uses it |

---

[← sharukhan overview](../README.md)
