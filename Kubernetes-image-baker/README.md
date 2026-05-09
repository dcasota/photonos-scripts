# VCF Image Baker — multi-OS toolkit

End-to-end VKR (vSphere Kubernetes Release) OVA baking + scanning, packaged as a small set of bash scripts that can be driven from a developer workstation, a CI runner, or a GitHub Actions workflow.

The toolkit works around several known bugs in `vcf kubernetes-release` plugin **v3.6.2** in standalone mode (no vCenter context):
1. Missing `cri-containerd.tar` extraction in the LLB graph → containerd.service never reaches the disk.
2. Missing systemd unit stubs for `kubelet` and `registry`.
(3. if using on WSL, WSL host bug: `/proc/cmdline` containing `initrd=\initrd.img` makes `jq` reject the JSON in `/tmp/export-system-info.sh` (exit 5).
4. `OSImage name does not match the OVA destination folder name` always fires on the bake's own OVA-assembly step.
5. User-supplied `kernelParameters` are written only to `/etc/default/grub` and never reach `/boot/photon.cfg` (the file Photon's GRUB actually reads).
6. The bake's grub.cfg generation script can leave a 0-byte `grub.cfg` if its bash heredoc aborts under `set -u`.

The scripts here paper over all of those automatically.

---

## File layout

```
baked/
│
├── setup-image-baker.sh       Main driver. End-to-end: install
│                              prereqs+BuildKit+VCF CLI, build the
│                              vkr-wrapper + <os>-with-containerd
│                              custom images, run `vcf kr bake`,
│                              patch /boot/photon.cfg with custom
│                              kernelParameters, assemble OVA.
│                              ── start with ──
│                                 OS_TARGET=photon \
│                                 ARTIFACTS_DIR=$(pwd) \
│                                 ./setup-image-baker.sh
│                              (also: OS_TARGET=ubuntu, rhel)
│
├── scan-baked-ova.sh          Three-stage security/compliance scan
│                              of a baked OVA: Syft → SBOM,
│                              Grype → CVE scan, cinc-auditor →
│                              STIG/CIS profile via QEMU-KVM boot.
│                              ── start with ──
│                                 ./scan-baked-ova.sh \
│                                     <path-to.ova> <image-name>
│                              env: GRYPE_FAIL_ON, SKIP_STIG=1,
│                                   STIG_INPUTS_FILE
│
├── lib/
│   └── common.sh              Shared library sourced by both
│                              scripts. Single source of truth
│                              for ALL version pins (BuildKit,
│                              VCF CLI, KR plugin, VKR_K8S_VERSION,
│                              VKR_TAG, PHOTON_VERSION, ARCH),
│                              the OS_TARGET switch (photon |
│                              ubuntu | rhel), registry config,
│                              IMAGE_NAME, and helpers
│                              (detect_pkg_mgr, pkg_install,
│                               step, info, die, dump_config).
│                              Override any value via env.
│                              ── never run directly ──
│
├── .github/workflows/
│   └── bake-and-scan.yml      GitHub Actions glue. Exposes the
│                              same OS_TARGET / version pins as
│                              workflow_dispatch inputs, runs
│                              setup-image-baker.sh then
│                              scan-baked-ova.sh, uploads OVA +
│                              SBOM + Grype/STIG SARIF reports.
│                              ── triggered from GitHub UI ──
│                                 (workflow_dispatch)
│
└── <image-name>/              Generated per bake run. Contains:
    ├── <image-name>.ova         The bootable OVA (deploy this)
    ├── <image-name>-disk1.vmdk  20 GiB streamOptimized VMDK
    ├── kernel_config            Photon kernel .config
    ├── kernel_tunables.tgz      /etc/sysctl.d snapshot
    ├── manifest.json            Build manifest (versions, SHAs)
    ├── package_list.json        tdnf list installed
    ├── repo_sources.tgz         /etc/yum.repos.d snapshot
    └── system_info.json         /etc/os-release + boot params
```

---

## Quick reference

| Want to … | Run |
|---|---|
| Bake a Photon-5 + VKR 1.32.10 OVA into the current dir | `OS_TARGET=photon ARTIFACTS_DIR=$(pwd) ./setup-image-baker.sh` |
| Bake an Ubuntu-22.04 + VKR 1.32.10 OVA | `OS_TARGET=ubuntu ./setup-image-baker.sh` |
| Use a different VKR | `VKR_K8S_VERSION=1.32.7 VKR_TAG=v1.32.7_vmware.1-fips-vkr.1 VKR_INNER_VERSION=v1.32.7+vmware.1-fips ./setup-image-baker.sh` |
| Custom kernel cmdline params | `KERNEL_PARAMS_LIST="lsm=… ipv6.disable=1" ./setup-image-baker.sh` |
| Scan an OVA (default = high-CVE gate + STIG) | `./scan-baked-ova.sh photon-…/photon-….ova photon-…` |
| Skip STIG (no /dev/kvm) | `SKIP_STIG=1 ./scan-baked-ova.sh <ova> <name>` |
| Inspect effective config | `source ./lib/common.sh && dump_config` |

---

## Tunables (all exported in `lib/common.sh`)

Override any of them via env before invoking either script.

### Versions
| Var | Default | Notes |
|---|---|---|
| `BUILDKIT_VERSION`   | `v0.15.0` | moby/buildkit release tag |
| `VCF_VERSION`        | `v9.0.2`  | VCF CLI tarball |
| `KR_PLUGIN_VERSION`  | `v3.6.2`  | `kubernetes-release` plugin |
| `VKR_K8S_VERSION`    | `1.32.10` | Kubernetes release |
| `VKR_TAG`            | `v1.32.10_vmware.1-fips-vkr.2` | OCI tag in artifact-server |
| `VKR_INNER_VERSION`  | `v1.32.10+vmware.1-fips`       | path inside artifact-server image |
| `PHOTON_VERSION`     | `5.0`     | used by scanner for STIG profile path |

### OS target
| Var | Default | Notes |
|---|---|---|
| `OS_TARGET` | `photon` | one of: `photon`, `ubuntu`, `rhel` |
| `OS_NAME`, `OS_VERSION`, `OS_BASE_IMAGE` | derived from `$OS_TARGET` | overrideable |
| `ARCH` | `amd64` | |

### Paths / registry
| Var | Default |
|---|---|
| `WORKDIR`         | `$HOME` |
| `ARTIFACTS_DIR`   | `${WORKDIR}/artifacts` |
| `REGISTRY_HOST`   | `localhost` |
| `REGISTRY_PORT`   | `5000` |
| `WRAPPER_REPO`    | `${REGISTRY}/vkr-wrapper` |
| `OS_BASE_REPO`    | `${REGISTRY}/${OS_NAME}-with-containerd` |
| `IMAGE_NAME`      | `${OS_NAME}-${OS_VERSION//./}-${ARCH}-vmi-k8s-v${VKR_K8S_VERSION}---vmware.1-fips-vkr.2` |

### Bake / scan thresholds
| Var | Default |
|---|---|
| `KERNEL_PARAMS_LIST` | `lsm=lockdown,capability,landlock,yama,apparmor,bpf` (space-separated `key=value` tokens) |
| `GRYPE_FAIL_ON`      | `high` (`negligible`/`low`/`medium`/`high`/`critical`) |
| `STIG_FAIL_ON_HIGH`  | `1` (set to `0` to log-only) |
| `STIG_REPO_REF`      | `master` |
| `SKIP_STIG`          | `0` (set to `1` if `/dev/kvm` not available) |

---

## What `setup-image-baker.sh` actually does

```
[1/12]  Install host prereqs           xfsprogs, open-vmdk, libarchive, gcc + headers
[2/12]  Install BuildKit               systemd unit + insecure localhost:5000 config
[3/12]  Install VCF CLI + plugin       pinned to $KR_PLUGIN_VERSION
[4/12]  Start local docker registry    registry:2 on :5000
[5/12]  Patch /usr/bin/mkova.sh         tar → bsdtar (Photon's tar is toybox)
[6/12]  Build vkr-wrapper image        flatten /data/artifacts/, extract tarballs,
                                       strip non-target OSImage YAMLs
[7/12]  Build <os>-with-containerd     pre-extract cri-containerd.tar, stub
                                       registry+kubelet services, /usr/bin
                                       symlinks for kubectl/kubeadm/etc, plus
                                       LD_PRELOAD shim that strips backslashes
                                       from /proc/cmdline (WSL host fix)
[8/12]  Generate <os>-bpf.yaml         apiVersion imageconfiguration.vmware.com/
                                       v1alpha1 + kernelParameters block
[9/12]  Run vcf kr bake                produces VMDK; the bake's own OVA step is
                                       broken in v3.6.2 standalone mode and
                                       intentionally fails — we ignore it
[10/12] Post-bake disk repair          mount /boot, append every
                                       KERNEL_PARAMS_LIST entry to
                                       photon_cmdline (idempotent), regenerate
                                       grub.cfg from PARTUUIDs if empty
[11/12] Assemble OVA                   mkova.sh wraps the patched VMDK with an
                                       OVF template (default: HW15 + EFI)
[12/12] Done                           prints OVA path + scan command
```

---

## What `scan-baked-ova.sh` actually does

```
[setup] Tool prereqs                   jq, git, qemu-img, qemu-system-x86,
                                       cloud-image-utils, syft, grype,
                                       cinc-auditor (omits cinc if SKIP_STIG=1)

[1/3]   Unpack OVA → mount root        bsdtar extract → qemu-nbd attach (read
                                       only) → mount largest partition

[2/3]   Syft + Grype                   CycloneDX SBOM, Grype CVE scan, gates
                                       on $GRYPE_FAIL_ON severity

[3/3]   STIG via VM boot               cloud-init seed with one-shot SSH key,
                                       boot OVA in QEMU/KVM, run cinc-auditor
                                       over SSH, parse JSON, gate on
                                       $STIG_FAIL_ON_HIGH ≥ 0.7-impact failures
                                       (skipped entirely if SKIP_STIG=1)
```

---

## Output

After a successful run:

```
$ARTIFACTS_DIR/<image-name>/
├── <image-name>.ova            ← deploy this
├── <image-name>-disk1.vmdk
├── kernel_config
├── kernel_tunables.tgz
├── manifest.json
├── package_list.json
├── repo_sources.tgz
└── system_info.json
```

After a successful scan:

```
$WORKDIR/sbom/<image-name>.cdx.json
$WORKDIR/scan-reports/<image-name>.grype.txt
$WORKDIR/scan-reports/<image-name>.grype.json
$WORKDIR/scan-reports/<image-name>.stig.json    (if STIG ran)
```

---

## Known limitations

- `OS_TARGET=rhel` requires `RH_USERNAME` and `RH_PASSWORD` env vars (Red Hat subscription credentials). The plugin's `RhelBaker` runs `subscription-manager register --username=$RH_USERNAME --password=$RH_PASSWORD` inside the chroot to install RPMs from Red Hat's CDN — there is no offline alternative supported in v3.6.2. The script preflight-fails fast with a clear error if those vars are missing.
- The bake's `OSImage name does not match the OVA destination folder name` is allowed to fire — the script intentionally lets that step fail, then assembles the OVA itself with `mkova.sh`. If a future plugin version fixes that step, remove the `set +e` around the `vcf kr bake` invocation in step 9.
- The post-bake `photon.cfg` patcher only runs for `OS_TARGET=photon` (Ubuntu and RHEL use a different boot config layout); add an analogous block for those if you start using them.
