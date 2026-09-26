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
| `runPh7-3-RC4.sh` | 5.0 | **Experimental.** Same approach with the Linux 7.3-rc4 mainline release candidate, from the `experimental/linux-7.3-rc4` branch (wrapper v5); see [runPh7-3-RC4.sh (experimental Linux 7.3-rc4)](#runph7-3-rc4sh-experimental-linux-73-rc4) below. |

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
- **Hyper-V restore (v10).** `HYPERV` became a `bool` in 7.x, while Photon's 6.12 `config_x86_64` has
  `CONFIG_HYPERV=m`. `olddefconfig` therefore turned Hyper-V off along with every Hyper-V driver. The
  `linux` package's dracut config requires `hv_utils`, so dracut failed and an installed system panicked
  with `VFS: Unable to mount root fs on unknown-block(0,0)` (no initrd). The merge now sets `HYPERV=y`
  and re-applies Photon's Hyper-V driver values when the original config had Hyper-V on. `linux-esx`
  keeps Hyper-V off, as its config intends. The merge also prints `config-merge: CONFIG_X off` lines
  in the kernel build log for every symbol Photon enabled that ended up off.
- **Legacy netfilter restore (v11).** Since 7.x the legacy iptables, ip6tables, arptables and
  ebtables modules (`IP_NF_*`, `IP6_NF_*`, `BRIDGE_EBT_*`) depend on the new bool
  `NETFILTER_XTABLES_LEGACY`, which defaults to `n`, so the merge dropped all 64 of them
  (`ip_tables`, `iptable_filter`, `iptable_nat`, `ip6_tables`, `ebtables`, `arp_tables`, ...). When
  Photon's original config has legacy tables on, the merge now enables `NETFILTER_XTABLES_LEGACY`
  and re-applies Photon's values for them. This applies to both `linux` and `linux-esx`. Photon 5.0
  itself uses the nft backend (`/usr/sbin/iptables` is `xtables-nft-multi`), so only software that
  loads the legacy modules needs this.
- **BTF only where Photon has it (v12).** The merge used to force `CONFIG_DEBUG_INFO_BTF=y` on every
  kernel. Photon's esx config has BTF off, and `linux-esx.spec` (unlike `linux.spec`) does not keep the
  `.BTF` section when it strips modules, so esx modules loaded without BTF. `nf_conntrack` then logged
  `missing module BTF, cannot register kfunc` twice at every boot. The merge now enables BTF only when
  Photon's original config has it: `linux` keeps BTF, `linux-esx` goes back to BTF off.
- **perf files only with a tools subpackage (v10).** The perf-core install hook now goes only into
  specs with `%files tools`. In `linux-esx` it left `/etc/bash_completion.d/perf` unpackaged, which
  failed any fresh `linux-esx` build.
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

Status (wrapper v9 build, `photon-minimal-5.0-<commit>.x86_64.iso`, about 523 MB, kernel `7.2.7-1.ph5`):
the ISO boots to the installer under QEMU/KVM (BIOS and UEFI). Installing the VMware hypervisor-optimized
kernel (`linux-esx`, normal hard disk, no STIG hardening) works. Installing the generic `linux` kernel
from that build panics at boot because of the Hyper-V issue above. Kernels built before v11 also lack
the legacy netfilter modules. The wrapper skips packages whose RPM already exists, so to pick up the
v10/v11 config fixes remove the `linux-*7.2.7-1.ph5*`, `linux-esx-*7.2.7-1.ph5*` and
`bpftool-7.2.7-1.ph5*` RPMs from `stage/RPMS/x86_64` of the release tree and run the wrapper again.
Both kernels then rebuild in parallel, in about 90 minutes.

#### runPh7-3-RC4.sh (experimental Linux 7.3-rc4)

Same wrapper as `runPh7-2-7.sh`, pointed at the Linux 7.3-rc4 mainline release candidate
(2026-09-20). The release tree is the `experimental/linux-7.3-rc4` branch of
[dcasota/photon](https://github.com/dcasota/photon); its `SPECS/linux/EXPERIMENTAL-7.3-rc4.md` records
the tarball, sha512 and tag commit. Parameters and defaults are the same as above, except that
`RELEASE_BRANCH` defaults to `experimental/linux-7.3-rc4`.

What differs from 7.2.7:

- **Source.** Release candidates are published only as git.kernel.org snapshots:
  `https://git.kernel.org/torvalds/t/linux-7.3-rc4.tar.gz`. Patch0 and Patch1 still apply cleanly.
- **Version scheme.** RPM versions cannot contain `-`, so the kernel is packaged as `Version: 7.3.0`,
  `Release: 0.rc4.1%{?dist}`, which sorts below a later 7.3.0 final. The tarball directory lives in
  `%define kernel_src 7.3-rc4`, and `%prep` blanks the Makefile's `EXTRAVERSION = -rc4`. The kernel
  then names itself `7.3.0` plus `CONFIG_LOCALVERSION`, which equals `uname_r`: `uname -r` is
  `7.3.0-0.rc4.1.ph5` for `linux` and `7.3.0-0.rc4.1.ph5-esx` for `linux-esx`.
- **No `noreplace-smp` (v2).** `linux-esx` puts `noreplace-smp` on its kernel command line. That option
  controlled the uniprocessor lock-prefix patching, which was removed in the 7.3 cycle (7.2.7 still
  has it). 7.3-rc4 logs `Unknown kernel command line parameters "noreplace-smp", will be passed to
  user space` on every boot. The kernel pin now strips it from the kernel specs. Behaviour does not
  change: the kernel always keeps the lock prefixes now. `runPh7-2-7.sh` keeps the option.
- **RAP/KCFI on (v3).** The generic `linux` flavor builds with Photon's RAP/KCFI gcc plugin
  (`CONFIG_PAX_RAP=y`), as the 5.0 kernel does. The 6.12 plugin patch (`Patch61`) no longer applies to
  7.3-rc4. Its `vermagic.h` context still names `CONFIG_M486` / `M486SX`, which Linux 7.1 removed, and
  `CFI_CLANG` became `CFI`. The branch carries a rebased
  `SPECS/linux/secure/0001-gcc-rap-plugin-with-kcfi-7.3.patch` (sha256 `267919b1…`), documented in
  `SPECS/linux/EXPERIMENTAL-7.3-rc4.md`. Beyond the rebase, 7.x needs `__nocfi` without the kCFI
  attribute under RAP, and RAP must hash `gimple_call_fntype()` and build with `-fno-tree-tail-merge`.
  Otherwise the union-based sysctl converter calls fail their RAP check, and the first sysctl read
  panics init. The pin (`enable_rap_73rc4`) points `Patch61` at the rebased file and enables
  `Patch61` and `Patch63` (PAX tasklet fix). `Patch62` (`objtool: Return error in case of failures`)
  stays off: it no longer applies, and RAP builds emit objtool `no-cfi indirect call!` notes that it
  would make fatal. `linux-esx` has no RAP.
- **rdrand-rng (v4).** systemd ships `/etc/modules-load.d/10-rdrand-rng.conf`, and both kernel configs set
  `CONFIG_HW_RANDOM_RDRAND=m`, but the driver comes from Photon's `Patch6`, which the pin skipped: every
  boot logged `Failed to find module 'rdrand-rng'`. The branch carries a rebased
  `SPECS/linux/vmw/0001-hwrng-rdrand-Add-RNG-driver-based-on-x86-rdrand-inst-7.3.patch`. Its Makefile
  line follows the AMD entry, because 7.3 added AIROHA where the old context expected ATMEL, and
  `static_cpu_has()`, removed in 7.x, becomes `cpu_feature_enabled()`. The pin (`enable_rdrand_73rc4`)
  re-adds `Patch6` for both flavors and applies it with `%autopatch -p1 -m6 -M6`.
- **cloud-init 26.2-3.** The `experimental/linux-7.3-rc4` branch carries the cloud-init fix from
  vmware/photon#1676 (cherry-picked, commit `5a54342ac`). The systemd generator now finds `ds-identify`
  in `/usr/libexec`; before, it exited with status 3 at every boot and cloud-init did not run.
  `minimal` requires cloud-init, and `make image` does not rebuild an install-only dependency, so the
  older 26.2-2 RPM kept being used. Wrapper v5 adds `cloud-init` to the pre-build list next to the
  STIG packages, so 26.2-3 is built before the image.

Status (branch commit `6c918e10a`, `photon-minimal-5.0-6c918e10a.x86_64.iso`, 507 MB):

- The ISO boots to the installer under QEMU/KVM (BIOS).
- `linux-esx` (VMware hypervisor optimized) was installed by kickstart onto a PVSCSI disk (BIOS,
  no STIG hardening). The installed system boots to a login prompt with kernel
  `7.3.0-0.rc4.1.ph5-esx`. `systemctl is-system-running` reports `running`, the root filesystem is
  on `/dev/sda3` (ext4), and a vmxnet3 NIC gets a DHCP address. `linux-esx` has no virtio drivers,
  so test it with VMware-style virtual hardware.
- The generic `linux` kernel in that ISO still had the Hyper-V issue described above, so an installed
  system panicked at boot.
- Rebuilt with the v10 config fix (`CONFIG_HYPERV=y`), the generic kernel works: the rebuilt ISO
  (about 508 MB) was installed interactively onto a virtio disk under QEMU/KVM (BIOS, no STIG
  hardening). The installed system boots to login with kernel `7.3.0-0.rc4.1.ph5`, `initrd.img` is
  present, `systemctl is-system-running` reports `running`, root is on `/dev/vda3` (ext4), and
  `eth0` gets a DHCP address and reaches the gateway.
- Those kernels still lacked the legacy netfilter modules: on the installed generic system,
  `modprobe ip_tables` fails with "Module ip_tables not found". Both kernels were rebuilt with
  v11 (ISO `20260925-191421-photon-minimal-5.0-6c918e10a.x86_64.iso`, 508 MB). Fresh installs of
  both kernels under QEMU/KVM (BIOS, no STIG hardening) boot to login with `systemctl
  is-system-running` = `running`. The generic `linux` was installed interactively on virtio and
  `linux-esx` by kickstart on PVSCSI + vmxnet3. On both, `ip_tables`, `iptable_filter`,
  `iptable_nat`, `ip6_tables`, `ip6table_filter`, `ebtables`, `ebtable_filter`, `arp_tables` and
  `arptable_filter` load with `modprobe`, and `eth0` gets a DHCP address.
- `linux-esx` rebuilt with the v2 pin (ISO `20260925-204806-photon-minimal-5.0-6c918e10a.x86_64.iso`):
  a fresh kickstart install on PVSCSI + vmxnet3 boots with a `/proc/cmdline` without `noreplace-smp`,
  0 unknown-parameter warnings in `dmesg`, the legacy netfilter modules loading, and `systemctl
  is-system-running` = `running`.
- Generic `linux` rebuilt with RAP (v3, branch commit `1ed5b5003`, ISO
  `photon-minimal-5.0-1ed5b5003.x86_64.iso`). The build log shows `rap_plugin.so` in use, the config
  has `CONFIG_PAX_RAP=y`, `CONFIG_CFI=y`, `CONFIG_DEBUG_INFO_BTF=y`, and module vermagic ends in `RAP`.
  The installer runs on the RAP kernel, and an interactive install onto a virtio disk under QEMU/KVM
  (BIOS, no STIG hardening) boots to login. `sysctl -a` reads all 1,088 sysctls without error, `dmesg`
  has 0 PAX/Oops/BUG lines, the kernel is not tainted, the legacy netfilter modules and `hv_vmbus`
  load, `systemctl is-system-running` = `running`, and `eth0` gets a DHCP address.
- v5 (branch commit `616dc4d8f`, ISO `20260926-031233-photon-minimal-5.0-616dc4d8f.x86_64.iso`,
  509 MB): `linux-esx` has `DEBUG_INFO_BTF` off, both kernels ship `rdrand-rng.ko`, and the ISO carries
  cloud-init 26.2-3. A fresh kickstart install of `linux-esx` on PVSCSI + vmxnet3 has 0 journal lines for
  `missing module BTF`, `Failed to find module` and `cloud-init-generator failed`. `rdrand_rng` is
  loaded, `cloud-init status` reports `done`, and `systemctl is-system-running` = `running`.
- If an ISO name already exists in the output directory, the wrapper prefixes the new ISO with a
  timestamp (for example `20260925-163049-photon-minimal-5.0-6c918e10a.x86_64.iso`).

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
