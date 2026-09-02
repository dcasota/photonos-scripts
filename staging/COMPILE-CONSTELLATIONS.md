# Photon OS build ("compile") constellations — reference

*Compiled 2026-08-31 from the trees present on this machine. Every claim below is
backed by a `path:line`, a package NEVR, a commit SHA, or an artifact on disk.
Where something could not be determined it says so explicitly.*

**Read-only survey.** No build was started to produce this document.

## Trees this document describes

| Path | What it is | State |
|---|---|---|
| `/root/common` | The **build system** (branch `common`): `build.py`, `support/package-builder`, `support/poi`, `common/data/packages_*.json` | HEAD `ed5bb42a1`; `build-config.json` + `support/package-builder/run-in-chroot.sh` locally modified |
| `/root/5.0` | The **5.0 release tree** (SPECS only, branch `5.0`) | HEAD `b7e3bedb6`, **56 commits behind `origin/5.0` (`9a90093d2`)**; 8 specs locally modified |
| `/root/photon-os-installer` | POI upstream clone, branch `upstream/tdnf-capture-output` (post-`master`) | tags `v1.0`…`v2.9` present |
| `/root/dcasota-photon` | A second 5.0 SPECS tree on branch `fix/docker-init-static-5.0` | idle |
| `/root/photonos-scripts/staging/runPh*.sh` | The five driver scripts | **being edited by other agents while this was written** |
| `/root/photonos-scripts/HABv4SimulationEnvironment` | Secure-Boot ISO post-processor (`PhotonOS-HABv4Emulation-ISOCreator`) | source under `src/` |
| **absent** | `/root/4.0`, `/root/6.0` | never cloned on this host |

`origin` for both photon trees is `https://github.com/dcasota/photon.git`; `vmware`
is a second remote with only `vmware/5.0` fetched.

---

## 1. Summary matrix — the primary constellations

"Verified" = an artifact or RPM produced by *this* machine exists on disk.

| # | Release line | Subrelease | Arch | Artifact (`IMG_NAME`) | Status here | Evidence |
|---|---|---|---|---|---|---|
| C1 | 5.0 | 92 (default) | x86_64 | `iso` (full, ~4.6 GB) | **Verified working** | `/mnt/c/Users/dcaso/Downloads/Ph-Builds/photon-5.0-dde71ec57.x86_64.iso` (4 624 398 336 B) |
| C2 | 5.0 | 92 (default) | x86_64 | `minimal-iso` (~531 MB) | **Verified working** | `…/photon-minimal-5.0-b7e3bedb6.x86_64.iso`, built 2026-08-30 23:14; sha of build number matches `/root/5.0` HEAD |
| C3 | 5.0 | 92 | x86_64 | `iso` + HABv4 Secure-Boot rewrap (~5.19 GB) | **Verified working** | `…/photon-5.0-dde71ec57.x86_64-secureboot.iso`, 2026-08-11 |
| C4 | 5.0 | 91 | x86_64 | `iso` / `minimal-iso` | Partially proven — kernel 6.1.176 branch exists, script exists, no ISO on disk | `runPh5_pinned91.sh`; `SPECS/91/linux/linux.spec` |
| C5 | 5.0 | 90 | x86_64 | `iso` / `minimal-iso` | Untested — script exists, README says "may need additional subrelease-90 bootstrap fixes" | `runPh5_pinned90.sh`; `staging/README.md` |
| C6 | 5.0 | 92 | x86_64 | `rt-iso` | **Known broken** — no `linux-rt` spec is active at ≥ 92 | see §11.3 |
| C7 | 5.0 | ≤ 90 | x86_64 | `rt-iso` | Theoretical only — `SPECS/91/linux/linux-rt.spec` is `build_if <= 90` |
| C8 | 5.0 | any | x86_64 | `basic-iso` | **Known broken** — no `support/poi/configs/basic-iso/` → no `basic-iso.yaml` | see §11.4 |
| C9 | 5.0 | any | x86_64 | `src-iso` | Untested; code path present (`poi.py:538`) |
| C10 | 5.0 | any | x86_64 | `ova` (→ `.vmdk` + `.ova`) | Untested |
| C11 | 5.0 | any | x86_64 | `ova-stig` (STIG-hardened OVA) | Untested, **not reachable via `make`** — `poi.py`-only target |
| C12 | 5.0 | any | x86_64 | `ami` (`.raw` → `.tar.gz`) | Untested |
| C13 | 5.0 | any | x86_64 | `gce` (`disk.raw` → `.tar.gz`) | Untested |
| C14 | 5.0 | any | x86_64 | `azure` (fixed-size VPC `.vhd` → `.tar.gz`) | Untested |
| C15 | 5.0 | any | aarch64 | `rpi` (`.img` → `.xz`) | Untested; `poi.py:513` asserts `arch == aarch64` |
| C16 | 5.0 | any | aarch64 | `ls1012afrwy` | **Known broken** — in `build.py` target list but `poi.py` has no handler → `assert False, unknown target` |
| C17 | 5.0 | any | x86_64 | `photon-docker-image` (rootfs tar.gz) | Untested |
| C18 | 5.0 | any | x86_64 | `k8s-docker-images` (21 container images) | Untested |
| C19 | 5.0 | any | x86_64 | `all-images` | **Known broken** — iterates `ova_uefi` first, which `poi.py` cannot build |
| C20 | 5.0 | any | aarch64 | any | **Not possible on this host** — no cross-arch support, see §4 |
| C21 | 4.0 | n/a (no subrelease gating) | x86_64 | `iso` / `minimal-iso` | Untested — `/root/4.0` does not exist; different build system (§2.2) |
| C22 | 4.0 | n/a | x86_64 | `ova_uefi` (EFI OVA) + `ova` (BIOS OVA) | 4.0-only target pair |
| C23 | 4.0 | n/a | x86_64 | `ostree-repo` + OSTree-host install | 4.0-only; removed in 5.0 and in POI ≥ 2.9 (§10) |
| C24 | 6.0 | 100 | x86_64 | `iso` / `minimal-iso` | Untested — `/root/6.0` does not exist; branch self-identifies as `.ph5` / release `5.0` (§2.3) |

**Counting.** `build.py` names **15** image targets; `poi.py` adds **2** more that
`build.py` cannot reach (`ova-stig`, `debug-iso`) → **17 named artifact types**.
There are **5 source-tree constellations** (4.0; 5.0/90; 5.0/91; 5.0/92; 6.0/100)
and **2 architectures**, so the full named cross-product is **17 × 5 × 2 = 170**.
Layering the orthogonal switches documented below (STIG off/on, SELinux
disabled/permissive/enforcing, FIPS off/on, canister off/usage/build, bootmode
bios/efi/dualboot, POI 2.7/2.8/2.9/master, sandbox chroot/nspawn/container) the
space is far larger; the practically meaningful set is the **24 rows above**, of
which **3 are verified built here (C1, C2, C3)**, **1 partially (C4)**, **5 are
known broken (C6, C8, C16, C19, and 4.0-STIG-on-minimal-ISO)** and the rest are
untested.

---

## 2. Dimension 1 — Release line (4.0 / 5.0 / 6.0)

### 2.1 How it is selected
`runPh*.sh $3` = the git branch of the release tree; the tree is cloned to
`$BASE_DIR/$RELEASE_BRANCH`, e.g. `/root/5.0`.
`build-config.json` in that tree carries `"photon-branch"`, `"photon-dist-tag"`
and `"photon-release-version"`.

| | 4.0 | 5.0 | 6.0 (this fork) |
|---|---|---|---|
| `photon-dist-tag` | `.ph4` | `.ph5` | `.ph5` ← note |
| `photon-release-version` | `4.0` | `5.0` | `5.0` ← note |
| `photon-subrelease` | *(key absent)* | `92` | `100` |
| kernel | `linux` 5.10.260 | `linux` 6.12.96 **and** 6.1.177 | `linux` 6.1.158 |
| kernel flavors with a spec | `linux`, `linux-esx`, `linux-secure` | `linux`, `linux-esx` (+ `linux-rt` at ≤ 90) | `linux`, `linux-esx`, `linux-rt` |
| `SPECS/<n>/` subrelease dirs | none | `90`, `91`, `92` | none |
| specs using `%global build_if` | 0 | 1471 | 0 |
| build system | **in-tree** (`build.py` + `support/image-builder`) | external `common` branch + POI container | external `common` branch + POI container |
| `photon-upgrade` payload | `ph4-to-ph5-upgrade.sh` | `ph5-to-ph6-upgrade.sh` | `ph5-to-ph6-upgrade.sh` |

Evidence: `git show origin/4.0:build-config.json`, `git show origin/6.0:build-config.json`,
`/root/5.0/build-config.json`, `git ls-tree origin/4.0:support`, `git ls-tree origin/6.0:SPECS`.

### 2.2 ADDITIONAL DIMENSION: build-system topology (monolithic vs split)
This is a real, load-bearing difference the user's list did not have.

* **4.0 is self-contained**: `origin/4.0` top level contains `build.py`,
  `common/`, `support/`, `tools/`, `Dockerfile`, `Vagrantfile`. Images are built
  by `support/image-builder/imagebuilder.py` in a chroot — **no Docker POI image
  is involved**. Target list at `origin/4.0:build.py:43-59`.
* **5.0 and 6.0 are split**: the release tree ships only `SPECS/`, `data/`,
  `Makefile`, `build-config.json`; `Makefile` `pushd`es into
  `../common` (`5.0/Makefile:14,24-29`) and runs `common/build.py`, which shells out
  to `common/support/poi/poi.py` → `docker run photon/installer`.
* Consequence documented in `runPh6.sh:6-13`: `make` still runs with the *release*
  worktree as cwd, so `stage-path` (`./stage`) resolves under `$RELEASE_BRANCH/stage`,
  not under `common/stage`.

### 2.3 Caveat on the 6.0 branch present here
`origin/6.0:build-config.json` sets `photon-dist-tag: ".ph5"`,
`photon-release-version: "5.0"`, `photon-subrelease: "100"`, and has **no**
`photon-mainline`. Because `build.py:1562` triggers the snapshot path whenever
`subrelease != photon-mainline`, an unpatched 6.0 build would demand
`…/photon_snapshots_5.0_x86_64/100/snapshot-100-latest.x86_64.list`.
`runPh6.sh:146-147` works around this by injecting `photon-mainline = subrelease`.
I could not determine whether upstream `vmware/6.0` looks the same — only
`vmware/5.0` is fetched on this host.

---

## 3. Dimension 2 — Subrelease gating (5.0 default 92 / SPECS/90 / SPECS/91)

### 3.1 The mechanism
1. `photon-subrelease` in the *release* `build-config.json` (`/root/5.0/build-config.json:6`)
   is read at `build.py:1552-1554` and becomes the rpm macro `photon_subrelease`
   (`support/package-builder/constants.py:259-261`).
2. **`PHOTON_SUBRELEASE` env var overrides the JSON** — `build.py:1879-1881`.
   This is the clean selector; the `runPh5_pinned9*.sh` scripts instead `sed`
   `build-config.json` in place.
3. Every spec may open with `%global build_if %{photon_subrelease} <op> <n>`.
   `SpecParser._parseBuildIf` (`support/package-builder/SpecParser.py:317-324`)
   evaluates it; a false condition sets `skipSpec` (`SpecParser.py:139-141`) and the
   spec is dropped from the build graph entirely (`SpecData.py:157`).
4. `SPECS/<n>/<pkg>/<pkg>.spec` is therefore not a magic directory — the *directory
   name is documentation only*; the gating is the `build_if` line inside. Both
   `SPECS/` and `SPECS/<n>/` are on the same search path
   (`build.py:1461-1481` adds `<common>/SPECS` and `<release>/SPECS`; the spec
   walker recurses).
5. `photon-mainline` is separate: when `subrelease != mainline`, `build.py:1562-1574`
   *requires* `package-repo-snapshot-file-url` and pins the external repo to the
   frozen snapshot list for that subrelease. When they are equal it prints
   `Skipping snapshot for <n> builds …`.
6. The spec **checker** asserts `90 <= subrelease <= mainline`
   (`support/spec-checker/check_spec.py:708-709,929-930`). Pinning below mainline
   therefore trips the checker — which is exactly why both pinned scripts set
   `base-commit` to the *common* HEAD so `git diff --name-only <base>` comes back
   empty and validation is skipped (`runPh5_pinned91.sh:6-14`).

### 3.2 What actually exists in `/root/5.0`

| Directory | package dirs | dominant gate |
|---|---|---|
| `SPECS/` (top level) | 1018 | 617× `>= 91`, 76× `>= 92`, rest ungated |
| `SPECS/90/` | 695 | 701× `<= 90`, 8× `== 90` |
| `SPECS/91/` | 61 | 38× `== 91`, 24× `<= 91`, 2× `<= 90` |
| `SPECS/92/` | 1 (`linux/v6.1`) | `>= 92` |

Approximate **active** spec-file count (heuristic scan of the first `build_if`
line in each of the 1834 `*.spec` files):

* subrelease 90 → ~1100 active
* subrelease 91 → ~1044 active
* subrelease 92 → ~1061 active

### 3.3 Installed-system side of the same dimension
`photon-repos` writes `/etc/tdnf/vars/subrelease` from the build-time macro
(`SPECS/photon-repos/photon-repos.spec:64-67`) and deliberately marks it
`%config` **not** `%config(noreplace)` (`:78-80`) so a subrelease upgrade rewrites it.
`photon-snapshot.repo` then expands `$subrelease` and `$updatenumber`
(default `latest`) into the snapshot list URL.
`SPECS/90/photon-repos/photon-repos.spec` is gated `== 90` and its
`photon-snapshot.repo` is `enabled=1` (vs `enabled=0` at ≥ 92) and trusts the
old 2048-bit GPG key as well as the 4096-bit one.

### 3.4 ADDITIONAL DIMENSION: two kernel lines inside one subrelease
At subrelease 92 **both** of these are active and both are built:

* `SPECS/linux/linux.spec` — `build_if >= 92`, Version 6.12.96
* `SPECS/92/linux/v6.1/linux.spec` — `build_if >= 92`, Version 6.1.177
  (added by `e62687f06 "92: kernel: Fork from 91 to 92,Update to 6.1.177"`)

Proof on disk — `/root/5.0/stage/RPMS/x86_64/`:
`linux-6.1.177-2.ph5.x86_64.rpm`, `linux-6.12.96-10.ph5.x86_64.rpm`,
`linux-esx-6.1.177-2.ph5.x86_64.rpm`, `linux-esx-6.12.96-8.ph5.x86_64.rpm`.

Note the side effect: `SpecData.initialize()` (`SpecData.py:578-600`) picks the
"default" kernel by `sorted(glob(SPECS/linux) + glob(SPECS/*/linux))` and takes the
first non-skipped one. String order puts `SPECS/92/linux` before `SPECS/linux`, so
the `KERNEL_VERSION` / `kernelsubrelease` macros are derived from **6.1.177**, not
6.12.96, at subrelease 92. I did not run a build to confirm the downstream effect
on `kernel-deps` spec generation — flagging this as *observed code path, unverified
outcome*.

---

## 4. Dimension 3 — Architecture (x86_64 / aarch64)

### How it is selected
It **is not selected — it is inherited from the host**:
`constants.buildArch = platform.machine()` (`support/package-builder/constants.py:68`),
with no setter anywhere.

* `photon-build-config.txt:78-81` documents a `"target-arch"` option with values
  `["aarch64","x86_64"]`. **It is not implemented.** Nothing reads that key.
* `build.py:1717` maps env `CROSS_TARGET` → config key `"tarsetdefaultArch"` —
  a typo; grepping the whole `common` tree finds that string only on that one line.
  **Dead knob.**
* `support/poi/poi.py` *does* support `--arch` with
  `ARCH_MAP = {"x86_64":"amd64","aarch64":"arm64"}` (`poi.py:22`) and adds
  `--platform=linux/<arch>` when it differs from the host, **but `build.py` never
  passes `--arch`** (`build.py:1251-1262` passes only `--config`, `--docker-image`,
  `--stage-dir`, `--sha`).

**Conclusion: an aarch64 Photon image must be built on an aarch64 host.** This host
is x86_64 (WSL2). All aarch64 rows in the matrix are therefore theoretical here.

Arch-aware content that does exist:
* `build-config.json` `photon-docker-image-urls` has both x86_64 and aarch64 rootfs
  tarballs.
* `packages_*.json` support `packages_x86_64` / `packages_aarch64` overlay keys
  (`ami`, `developer`, `installer_initrd` → x86_64; `ami`, `rpi` → aarch64).
* `SPECS/linux/` ships `config_x86_64`, `config_aarch64`, `config-esx_x86_64`,
  `config-esx_aarch64`, and a separate `aarch64/` patch set.
* `linux.spec:47-53`: **`%global fips 1` on x86_64, `%global fips 0` on aarch64** —
  the arch dimension and the FIPS/canister dimension are coupled.
* `SPECS/shim-signed/shim-signed.spec:11` is `BuildArch: x86_64` — Secure Boot shim
  is x86_64-only.
* `isoBuilder.py:411-414`: the BIOS El Torito boot image is emitted **only** when
  `arch == "x86_64"`; aarch64 ISOs are EFI-only.
* `installer.py` (v2.8) `:666-667`: `aarch64 targets do not support BIOS boot. Set 'bootmode' to 'efi'.`

---

## 5. Dimension 4 — Image type (`IMG_NAME`)

### How it is selected
`make image IMG_NAME=<t>` → `build.py:1924-1925` reads env `IMG_NAME` and overrides
the target. Falls back to `photon-build-param.target` (`"iso"` in
`common/build-config.json`). A `CONFIG=<file.json>` env var takes an *earlier*
precedence path and reads `image_type` out of that JSON (`build.py:1917-1922`) — see §12.4.

All five driver scripts now accept the image type as positional **`$5`**
(default `minimal-iso`), validated against `iso|minimal-iso|basic-iso|rt-iso`
(e.g. `runPh5_normal.sh:39-47`). *Note:* that validation list is over-permissive for
`runPh4.sh` — 4.0's `build.py` has neither `basic-iso` nor `rt-iso`.

### The full target table (`common/build.py:36-95`)

| group | targets |
|---|---|
| `image` | `iso`, `ami`, `gce`, `azure`, `rpi`, `ova`, `all`, `src-iso`, `ls1012afrwy`, `photon-docker-image`, `k8s-docker-images`, `all-images`, `minimal-iso`, `basic-iso`, `rt-iso` |
| `rpmBuild` | `packages`, `packages-minimal`, `packages-basic`, `packages-rt`, `packages-initrd`, `packages-docker`, `updated-packages`, `core-toolchain`, `tool-chain`, `check-packages`, `generate-yaml-files`, `create-repo`, `distributed-build`, `extra-packages` |
| `buildEnvironment` | `packages-cached`, `sources`, `sources-cached`, `photon-stage` |
| `cleanup` | `clean`, `clean-install`, `clean-chroot`, `clean-sandbox`, `clean-stage-rpms`, `clean-stage-for-incremental-build` |
| `tool-checkup` | `check-pre-reqs`, `check-spec-files`, `initialize-constants` |
| `utilities` | `generate-dep-lists`, `generate-pkg-info`, `pkgtree`, `imgtree`, `who-needs`, `print-upward-deps`, `pull-stage-rpms` |

`poi.py` additionally handles `ova-stig` (`poi.py:512`) and `debug-iso` (`poi.py:538`)
which `build.py` cannot reach.

### full ISO vs minimal ISO — the real difference
This is not just size. Two different code paths:

* `iso` → `poi.create_full_iso()` (`poi.py:334-365`) passes
  `--rpms-list-file <basename>.rpm-list`. `isoBuilder` then takes the **copyPkgs**
  path and puts **every built RPM** on the ISO.
* `minimal-iso` / `rt-iso` / `basic-iso` → `poi.create_custom_iso()` (`poi.py:403-427`)
  omits `--rpms-list-file`, so `isoBuilder.downloadPkgs()` (`isoBuilder.py:186-247`)
  ships only the **dependency closure of `packages_<type>.json`**.

Measured on this machine:

| | full ISO repo | minimal ISO repo |
|---|---|---|
| RPMs | 1586 x86_64 + 315 noarch = **1901** | 214 x86_64 + 40 noarch = **254** |
| `aide` / `rsyslog` / `openssl-fips-provider` / `selinux-policy` / `libselinux-utils` / `ntpsec` | all present | **all absent** |
| path | `/root/5.0/stage/iso/photon-so839tgh/RPMS` | `/root/5.0/stage/minimal-iso/photon-16jushya/RPMS` |

That measurement *is* the proof for the STIG-on-minimal-ISO failure (§11.1).

Also: `build_iso()` moves the finished full ISO from `stage/iso/` up into `stage/`
(`build.py:1288-1290`); a **minimal ISO is left in `stage/minimal-iso/`**.

---

## 6. ADDITIONAL DIMENSION — image *flavors* (the `packages_*.json` set)

Each `packages_*.json` in `common/common/data/` is a distinct target package
closure. These are the "12 flavors":

| flavor file | base pkgs | +x86_64 | +aarch64 | purpose / consumed by |
|---|---|---|---|---|
| `packages_minimal.json` | 7 | – | – | default install option; `minimal-iso`; base of the full ISO |
| `packages_basic.json` | 2 (`basic`, `linux-esx`) | – | – | `basic-iso` (currently unbuildable, §11.4) |
| `packages_developer.json` | 20 | 1 (`grub2-pc`) | – | full-ISO menu option "2. Photon Developer" |
| `packages_rt.json` | 31 | – | – | real-time (`linux-rt`, `tuna`, `stalld`, `linuxptp`); `rt-iso` + menu option "4" |
| `packages_appliance.json` | 68 | – | – | hidden menu entry (`visible: false`), appliance base |
| `packages_ova.json` | 2 (`minimal`, `linux-esx`) | – | – | `ova` target |
| `packages_stig.json` (in `support/poi/configs/ova-stig/`) | 14 | – | – | `ova-stig` target |
| `packages_ami.json` | 7 | 1 (`linux`) | 1 (`linux`) | AWS AMI |
| `packages_azure.json` | 9 (incl. `WALinuxAgent`) | – | – | Azure VHD |
| `packages_gce.json` | 16 (google-guest-*, `kubernetes`, `ntp`) | – | – | GCE |
| `packages_rpi.json` | 52 | – | 4 (`dtb-raspberrypi`, `u-boot-rpi3/4`, `u-boot`) | Raspberry Pi 3/4 |
| `packages_ls1012afrwy.json` | 47 | – | – | NXP LS1012A-FRWY board |
| `packages_installer_initrd.json` | 68 | 1 (`grub2-pc`) | – | the **installer initrd** itself (contains `photon-os-installer` and `stig-hardening`) |
| `packages_ostree_host.json` | `{"packages": []}` | – | – | **4.0 only** (§10) |

The **installer menu** is a separate selector on top of these:
`common/data/build_install_options_all.json` → minimal / developer / realtime
(+ appliance, `visible:false`). Variants `build_install_options_{minimal,basic,rt}.json`
are used for the single-option custom ISOs
(`build.py:1183-1191` derives `build_install_options_<flavor>.json` from the img name).
4.0's version of that file has a fourth visible entry, `"3. Photon OSTree Host"`.

---

## 7. ADDITIONAL DIMENSION — kernel flavor

Two independent lists:

* what the **installer offers** at install time —
  `installer.py:124`: `all_linux_flavors = ["linux","linux-esx","linux-aws","linux-secure","linux-rt"]`
  and the interactive menu `linuxselector.py:31-36` with labels
  Generic / VMware hypervisor optimized / AWS optimized / Security hardened / Real Time.
  A flavor only appears if it is in `install_config['packages']`; `linux-esx` is
  additionally hidden when not running under VMware virtualization
  (`linuxselector.py:42-43`). With a single candidate the screen self-skips.
* what the **ISO builder guarantees** — `isoBuilder.py:198-206` appends `linux`
  if none of `linux, linux-esx, linux-rt, linux-aws, linux-secure` is in the list.

Which ones actually have a spec:

| flavor | 4.0 | 5.0 ≤ 90 | 5.0 == 91 | 5.0 ≥ 92 | 6.0 |
|---|---|---|---|---|---|
| `linux` | ✓ 5.10.260 | ✓ 6.1.176 (`SPECS/91/linux`) | ✓ 6.1.176 | ✓ 6.12.96 **and** 6.1.177 | ✓ 6.1.158 |
| `linux-esx` | ✓ | ✓ | ✓ | ✓ (both lines) | ✓ |
| `linux-rt` | ✗ | ✓ (`SPECS/91/linux/linux-rt.spec`, `build_if <= 90`) | ✗ | ✗ | ✓ |
| `linux-secure` | ✓ own spec | — | — | **merged**: `linux.spec:484-486` `Obsoletes: linux-aws`, `Obsoletes: linux-secure`, `Provides: linux-secure` | — |
| `linux-aws` | ✗ | — | — | obsoleted (`linux.spec:1452` "Depricate linux-aws kernel flavor") | — |

`common/common/data/kernel-deps.json` drives out-of-tree driver spec generation per
flavor and per kernel line: `linux_flavour = [linux, linux-esx, linux-rt]`, with
`v6.1` and `v6.12` variants of `kernels-drivers-intel-{iavf,i40e,ice}`, plus
`sysdig` and `falco` (`linux` only). Generator:
`support/spec-generator/create-kernel-deps-specs-from-template.py`.

---

## 8. Dimension 5 — Photon OS Installer (POI) version

**This is two knobs, not one.** Keep them apart:

### 8.1 The POI *RPM* — what runs inside the ISO / on the installed system
Built from `/root/5.0/SPECS/photon-os-installer/`:
* `config.yaml` pins the **v2.8 release tarball**:
  `url: https://github.com/vmware/photon-os-installer/archive/refs/tags/v2.8.tar.gz`,
  `commit_id: 8b63bb56db64746021c3b98d56ea9b858bdaa048`,
  sha512 `023e58…c47ab`.
* `photon-os-installer.spec:1` — `%global build_if %{photon_subrelease} >= 91`
  → **POI is not built at subrelease 90 at all**; `SPECS/90/photon-os-installer/`
  is the `<= 90` variant.
* Local (uncommitted) state adds `Patch2`–`Patch4` and bumps to `2.8-3`:
  `0003-isoInstaller-fix-interactive-NoneType-crash.patch`,
  `0004-installer-add-btrfs-progs.patch`,
  `0005-tdnf-capture-install-output.patch`
  (upstream base is `2.8-2`, "Extended to build for subrelease 91 and above").

**Correction to a seed fact.** The seed said "the built RPM tonight was
`photon-os-installer-2.8-5`". On disk:

| RPM | mtime | source |
|---|---|---|
| `photon-os-installer-2.8-3.ph5.x86_64.rpm` | **2026-08-30 22:50** ← tonight | current spec (`Release: 3`) |
| `photon-os-installer-2.8-4.ph5.x86_64.rpm` | 2026-06-04 20:43 | earlier iteration |
| `photon-os-installer-2.8-5.ph5.x86_64.rpm` | 2026-06-04 23:08 | earlier iteration |

`rpm -qp --qf '%{BUILDTIME:date}'` on `2.8-5` returns *Thu 04 Jun 2026 11:08:53 PM CEST*.
So **2.8-5 was built on 4 June, and tonight's build produced 2.8-3** — the three
patches were later folded into a single `2.8-3` changelog entry. Everything else in
the seed (v2.8 tarball, commit `8b63bb56`, `Patch0`–`Patch4`) is confirmed.

### 8.2 The POI *container image* — what builds the ISO
`build-config.json` key `poi-image` (default `"photon/installer:latest"`,
`common/build-config.json`), overridable by env `POI_IMAGE`
(`build.py:1727`, and `poi.py:481-482`). Passed as `--docker-image`
(`build.py:1256-1257`). Local image present: `photon/installer:latest` (600 MB).
Its Dockerfile installs `qemu-img`, `open-vmdk`, `stig-hardening`, `createrepo`,
`grub2`(+`grub2-pc` on amd64), `file` — the last one being the fix all five
runPh scripts check for (`FileNotFoundError: 'file'` in `generate_initrd.py`'s
`strip_if_needed()`).

The image and the RPM can legitimately be different POI versions.

### 8.3 Version landscape in `/root/photon-os-installer`

| version | notable |
|---|---|
| v2.7 | last one used for 4.0 (`staging/custom-4.0-installer`, POI `2.7-4.ph4`) |
| **v2.8** (`8b63bb56`, 2026-01-21) | shipped RPM; **has ostree**; default bootmode `dualboot` on x86_64 |
| **v2.9** (`59a011da9`, 2026-06-09) | **ostree removed** by commit `abdff38 "remove ostree support"` |
| `master` / `upstream/tdnf-capture-output` | + `a88cf02 "installer: configure selinux explicitly"`; default bootmode now `efi` everywhere; plugin hooks (`6061ec6 "suport check-config and add-defaults hooks in plugins"`) |

`isoBuilder.py:23-24`: `SUPPORTED_RELEASES = ["4.0","5.0"]`, `DEV_RELEASES = ["6.0"]`.

**Trap:** `common/support/poi/poi.py:14` hardcodes `RELEASE_VER = "5.0"` and
`build.py` never overrides it, so `photon-iso-builder -v 5.0` is passed regardless
of the release line being built.

Confirmation of the seed fact about `a88cf02` (`git show a88cf02`): it injects
`install_config['security'] = {'selinux': Defaults.SELINUX_DEFAULT}` when the
config has no `security` section, and the block below unconditionally appends
`selinux-policy` when `security['selinux']` is not `None`. `Defaults.SELINUX_DEFAULT = "permissive"` (added by `a88cf02` to
`photon_installer/defaults.py`; not present on the branch checked out here). It also changes the kernel
cmdline from `security=selinux selinux=1` to
`security=selinux selinux=1 enforcing=0|1`, or `selinux=0` when disabled.

---

## 9. Dimension 6 — Upgrade paths

Shipped tooling, not a build switch. Package `photon-upgrade`
(`/root/5.0/SPECS/photon-upgrade/`, v1.1-8):

| path | how | evidence |
|---|---|---|
| **within 5.0** (5.0 → 5.0, incl. 90 → 92 and 91 → 92) | `photon-upgrade` with **no** `--upgrade-os` → `tdnf update` / `distro-sync` against the configured repos | `photon-upgrade.sh:16` (`TO_VERSION=''` ⇒ update, not upgrade); `:443` `tdnf … distro-sync --releasever=$ver` |
| **subrelease step** | `photon-repos` is upgraded, rewriting `/etc/tdnf/vars/subrelease` because that file is `%config` (**not** `noreplace`) | `SPECS/photon-repos/photon-repos.spec:64-67, 78-80` |
| **5.0 → 6.0** | `photon-upgrade --upgrade-os [--to-ver=6.0]`; `--to-ver` accepts **only** `6.0` | `photon-upgrade.sh:66, 872, 934, 940-944`; payload `ph5-to-ph6-upgrade.sh` + `ph5-deprecated-pkgs.txt` (184 entries) + a replaced-package map (tomcat9→11, dhcp→dhcpcd/kea, openjdk11→25/21/17, pgaudit…) |
| **4.0 → 5.0** | same tool on the 4.0 branch: `ph4-to-ph5-upgrade.sh` + `ph4-to-ph5-deprecated-pkgs.txt` | `git ls-tree origin/4.0:SPECS/photon-upgrade` |

Other `photon-upgrade.sh` switches that are themselves constellation axes:
`--repos=`, `--install-all`, `--rm-pkgs-pre=`, `--rm-pkgs-post=`, `--skip-update`,
`--precheck-only`, `--assume-yes`, `--retain-deprecated-pkgs` (marked *dev only,
DO NOT USE IN PRODUCTION*).

Documented policy note for 4.0 STIG, from
`staging/custom-4.0-installer/README.md`: *"Backporting the full functionality
bundle to 4.0 is not planned upstream. The supported migration path is to upgrade
from 4.0 to 5.0 and activate hardening settings afterwards."*

I found **no** in-repo automation for a *downgrade* (92 → 91 → 90); the pinned
build scripts rebuild from source instead.

---

## 10. ADDITIONAL DIMENSION — OSTree (a constellation that is disappearing)

Three independent removals, all confirmed:

1. **POI**: present in `v2.7` and `v2.8`
   (`photon_installer/ostreeinstaller.py`, `ostreeserverselector.py`,
   `ostreewindowstringreader.py`, `ostree-release-repo.conf`,
   `packages_ostree_host.json`), **gone from `v2.9` and `master`** — commit
   `abdff38 "remove ostree support"` is the only `--diff-filter=D` commit touching
   `ostreeinstaller.py`. `git grep -c ostree v2.9 -- 'photon_installer/*.py'` → 0 hits.
2. **Build system**: `origin/4.0:build.py` has an `ostree-repo` rpmBuild target
   (`:695-712`, driving `support/image-builder/ostree-tools/make-ostree-image.sh`)
   and calls it for every non-`minimal-iso` image (`:1114, :1129`).
   `common/build.py` (5.0/6.0) has **no** ostree target at all.
3. **Install menu**: `origin/4.0:common/data/build_install_options_all.json` has
   `"ostree_host": {"title": "3. Photon OSTree Host", …, "additional-files": ["ostree-repo.tar.gz"]}`.
   The 5.0 `common` branch's copy has no such entry.

So: **OSTree installs are a 4.0-only constellation, and only with POI ≤ 2.8.**
Since `/root/4.0` does not exist here, it is unbuildable on this machine as-is.

---

## 11. Dimension 7 — STIG hardening (off / on) — and where it breaks

### 11.1 Interactive "Apply STIG hardening" (ISO install time)
* Menu screen: `photon_installer/stigenable.py`, wired in at
  `photon_installer/iso_config.py:202-203`.
* On "Yes" it sets (`stigenable.py:51-54`):
  * `install_config['ansible'] = KS_STIG_ANSIBLE` — playbook
    `/usr/share/ansible/stig-hardening/playbook.yml`, extra-vars
    `@/usr/share/ansible/stig-hardening/vars-chroot.yml`, `skip-tags: [PHTN-50-000245]`
  * `install_config['additional_packages'] = KS_STIG_PACKAGES` (`stigenable.py:21-30`):
    `audit, rsyslog, openssl-fips-provider, selinux-policy, libselinux-utils, ntp, aide, libgcrypt`
    — **confirmed exactly as the seed stated.**

**KNOWN BROKEN: STIG on a minimal ISO.** Confirmed by direct measurement, not
inference. The minimal ISO's on-media repo has 254 RPMs and contains **none** of
`aide`, `rsyslog`, `openssl-fips-provider`, `selinux-policy`, `libselinux-utils`,
`ntp`/`ntpsec`. (It *does* carry `stig-hardening` and `ansible`, because those come
in via `packages_installer_initrd.json`.) The full ISO's repo has 1901 RPMs and
contains all of them. Root cause is the `downloadPkgs()` vs `copyPkgs()` split
described in §5 — `isoBuilder.downloadPkgs()` builds the media repo purely from the
package-list closure and never consults `KS_STIG_PACKAGES`.

**`ntp` at subrelease 92 — seed fact confirmed.** There is no `ntp` package in
`/root/5.0/SPECS` (only `SPECS/90/ntp`), but
`rpm -qp --provides ntpsec-1.2.3-13.ph5.x86_64.rpm` lists a bare
`ntp` — so `tdnf install ntp` resolves to `ntpsec-1.2.3-13.ph5` **provided that RPM
is on the media**. On the minimal ISO it is not, so this does not rescue the case above.

### 11.2 ADDITIONAL: STIG as a *build-time* constellation — the `ova-stig` target
`support/poi/configs/ova-stig/` is a fully separate image constellation:
* `ova-stig_ks.yaml` — `packagelist_file: packages_stig.json`,
  `linux_flavor: linux-esx`, and an `ansible:` block running the STIG playbook with
  `skip-tags: [PHTN-50-000245, PHTN-50-000013]` (one more skip than the interactive path).
* `packages_stig.json` — 14 packages. **It differs from `KS_STIG_PACKAGES`**: it adds
  `minimal, linux, linux-esx, initramfs, lvm2, less, sudo` but **omits
  `openssl-fips-provider`**. If you are diffing hardened images, that is the gap.
* `photon.yaml` differs from the plain OVA only in `system.type` (`vmx-14` instead of
  the full `vmx-14 … vmx-22` list).
* Reachable **only** via `./poi.py ova-stig` — `ova-stig` is absent from
  `build.py:36-52`, so `make image IMG_NAME=ova-stig` falls through to
  `RpmBuildTarget().package("ova-stig")` and tries to build a package by that name.

### 11.3 The `stig-hardening` package itself
`SPECS/stig-hardening/stig-hardening.spec:1` — `%global build_if %{photon_subrelease} >= 91`
→ **STIG hardening is unavailable at subrelease 90.**
Upstream is 2.1-8; the local tree carries an uncommitted bump to **2.1-9** adding
`Patch3: fix-stig-playbook-fips-pam.patch` and `Patch4: fix-selinux-relabel-first-boot.patch`
(changelog: pam_faillock PHTN-50-000192 fix, `ima_hash=sha256` when `fips=1`,
`fipsmodule.cnf` generation, first-boot SELinux relabel service).
It is shipped in the initrd via `packages_installer_initrd.json`.

---

## 12. ADDITIONAL DIMENSIONS found in the build system

### 12.1 Sandbox type (`photon-build-type`)
`build.py:1484-1487` accepts exactly **three** values:
`"chroot"` (default and what is configured here), `"systemd-nspawn"`, `"container"`.
Implementations: `Sandbox.py:152 class Chroot`, `:278 class SystemdNspawn`,
`:403 class Container`. `photon-build-config.txt` only documents two of the three.

### 12.2 FIPS — three separate switches
1. **Build-time, userspace**: `"ossl-fips-in-make-check": true`
   (`common/build-config.json`) → `constants.enable_fips_in_make_check()`
   (`build.py:1646-1647`). Package `openssl-fips-provider-3.1.2-4.ph5` is built here.
2. **Build-time, kernel**: `linux.spec:20-41` documents the flag family
   `fips`, `canister_build`, `canister_usage` (derived), `acvp_build`, `kat_build`.
   Defaults: x86_64 → `fips 1`; aarch64 → `fips 0` (`linux.spec:44-53`).
3. **Install-time**: kickstart `security: {fips: true}` →
   `openssl-fips-provider` appended to packages and `fips=1` on the kernel cmdline
   (`installer.py` `_setup_security`).

### 12.3 Canister (FIPS crypto canister) — the "with/without canister" axis
Not a boolean; a tri-state, and it is *not* the same thing as UEFI Secure Boot.

| state | how | consequence |
|---|---|---|
| `fips=0` | aarch64 default, or `--define 'fips 0'` on x86_64 | no canister at all. `linux.spec:700-707` (PR #14 downstream patch) then strips `CONFIG_GCC_PLUGIN_{MATCH,PAD}_CANISTER_STRUCTS` from `.config`, because the Kconfig-adding patch is not applied and `make olddefconfig` would otherwise silently drop them and trip the `check_for_config_applicability.inc` diff guard. **Seed fact confirmed verbatim.** |
| `fips=1, canister_build=0` ⇒ `canister_usage=1` | **x86_64 default** | links against a *prebuilt* canister: `linux.spec:133-135` `BuildRequires: linux-fips-canister = 6.12.60-18.2.ph5`. That RPM is **not** in `/root/5.0/stage` — it is pulled from the Broadcom repo at build time. I could not locate a local copy. |
| `fips=1, canister_build=1` | `CANISTER_BUILD=1` env or `"canister-build": true` in build-config | builds the canister and emits the `linux-fips-canister` subpackage (`linux.spec:559-563`, `%if 0%{?canister_build}`) |
| `acvp_build=1` / `kat_build=1` | `ACVP_BUILD` / `KAT_BUILD` env | certification builds; `kat_build` forces `acvp_build=1` + `canister_build=1`; `acvp_build` forces `fips=1`. Release string gains `.acvp` / `.kat` (`linux.spec:79`) |

Plumbing: `build.py:1614-1618` → `constants.setKatBuild/setCanisterBuild/setAcvpBuild`
→ `constants.py:263-270` adds rpm macros `kat_build`, `canister_build`, `acvp_build`.
Env aliases at `build.py:1718-1720`.
**None of these keys is set in either `build-config.json` here**, so every build on
this machine is the x86_64 default: `fips=1, canister_usage=1`.

### 12.4 Custom image via `CONFIG=<json>`
`build.py:1913-1922`: when `CONFIG` points at a JSON file, `image_type` is read
from it and the file is handed to `poi.py --config`. `poi.create_config_from_custom()`
(`poi.py:129-170`) then synthesises `<type>_ks.yaml` from the JSON's `installer`
section plus a `size`, and pulls the named `packagelist_file` out of
`common/data/`. This is a *fully user-defined* image constellation. Untested here.

### 12.5 Package repository variant
`package-repo-url` (env `PACKAGE_REPO_URL`) chooses which upstream repo the
sandbox consumes. Materially different choices:
* `…/photon_$releasever_$basearch` — rolling, everything since GA (the default)
* `…/photon_release_$releasever_$basearch` — GA-frozen. `runPh6.sh:157` pins to this
  and explains why (`:152-158`): the rolling repo drags in glibc-2.43 / libxcrypt-4.5.2 /
  gcc-12.2.0-12 / rpm-6.0.1 + the `libcap-libs` split, all ABI-incompatible with the
  local glibc-2.38 / pre-split libcap.
* `…/photon_updates_…`, `…/photon_snapshots_…/<subrelease>/snapshot-<n>-latest…`
  (`SPECS/photon-repos/photon-*.repo`)

Related: `package-repo-path`, `bootstrap-repo-path`, `PHOTON_SOURCES_PATH`,
`PHOTON_CACHE_PATH`, `PHOTON_PKG_BLACKLIST_FILE`.

### 12.6 RPM / artifact signing (SRP)
`support/package-builder/signing.py` turns three `copy-to-sandbox` entries —
`srp-signing-script`, `srp-signing-params`, `srp-signing-auth` — into rpm macros
`signing_script`, `signing_params`, `signing_auth` (`signing.py:9-14, 65-71`), which
specs consume, e.g. `SPECS/shim-signed/shim-signed.spec:14-22, 36-41`
(`%if "%{?signing_script}" != ""` → `sbsigntools` + PE signing of `revocations.efi`).
**Not configured here** — `copy-to-sandbox` in `common/build-config.json` contains only
`adjust-gcc-specs` and `print-java-home`, so `getSigningCmd()` returns `None` and all
RPMs are unsigned. OVA signing is a separate hook: `create-ova --sign-script`.

### 12.7 Other build-config switches worth knowing
`build-src-rpm`, `build-dbginfo-rpm` (+ `build-dbginfo-rpm-list`),
`BUILD_DEBUG_ISO=1` (sets `debug_iso_path`, `build.py:1202-1203`),
`extra-packages-list` (`["chromium"]`) + `BUILD_EXTRA_PKGS=1`,
`compression-macro` (`w1..w22.zstdio` or `gzip9`), `rpm-check-flag` /
`rpm-check-stop-on-error` (`RPMCHECK=enable_stop_on_error`),
`toolchain-bootstrap`, `resume-build`, `rebuild`,
`start-scheduler-server` + `distributed_build_options.json` (`pods`, NFS server)
for a **distributed build** constellation,
`observer-docker-image` / `observer-rules` (`Sandbox.py:559 class Observer`),
`isolated-docker-network`, `pkg_build_options.json` (per-package `pullsources` and
extra rpm `macros` — the escape hatch for per-package canister/FIPS overrides),
`threads` / `THREADS`.

### 12.8 Container-image constellations
* `photon-docker-image` → `photon-rootfs-<ver>-<sha>.<arch>.tar.gz`, built by running
  `support/dockerfiles/photon/make-docker-image.sh` inside a `photon:5.0` container
  (`build.py:1302-1358`).
* `k8s-docker-images` → 21 Dockerfiles under `support/dockerfiles/k8s-docker-images/`
  (kube-apiserver, kube-proxy, coredns, flannel, calico ×3, dashboard, metrics-server,
  nginx-ingress, wavefront-proxy, heapster, pause, sidecar, …), driven by 11 build
  scripts (`build.py:1360-1416`).

### 12.9 Branch constellations in the fork
`git branch -r` on `/root/5.0` shows purpose-built branches that are themselves
constellations: `4.0-LKCM-5.0-canister`, `linux-fips0-canister-kconfig-strip`,
`fix-stig-hardening-upstream`, `fix-selinux-relabel`,
`fix/nginx-cve-2026-42945-{4.0,5.0,5.0-specs90,6.0,master}`,
`fix/docker-init-static-{5.0,6.0}`, `distrib-compat-0.1-5-upstream-backports`,
`dev`, `master`, `6.0-2025-11-18`, `6.0-backup`.

---

## 13. Dimension 8 — EFI vs BIOS

Three layers, three different answers.

### 13.1 The ISO media itself — always hybrid on x86_64
`isoBuilder.py:395-422` builds one `mkisofs` command line:
* `-b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table`
  — **only when `self.arch == "x86_64"`** (`:411-414`)
* `-eltorito-alt-boot` separator, then `-e boot/grub2/efiboot.img -no-emul-boot`
The EFI El Torito image is built by `createEfiImg()` (`:276-298`): a 3 MB FAT
image holding `boot/efi/EFI`.
⇒ x86_64 ISO = BIOS + UEFI; aarch64 ISO = UEFI only.

### 13.2 The installed system — kickstart `bootmode`
Values: **`efi`, `bios`, `dualboot`** (three, not two).
* v2.8 default (`installer.py:355-360` at tag `v2.8`): `dualboot` on x86_64, `efi` otherwise.
* master default (`installer.py:369-371`): `efi` everywhere. **Behaviour change across POI versions.**
* `dualboot`/`efi` append `grub2-efi-image` to the package list (`installer.py:397-399` @v2.8).
* aarch64 + `bios`/`dualboot` → `InstallerConfigError: aarch64 targets do not support BIOS boot.`
  (`installer.py:666-667` @v2.8).
* Written to the target as `BOOT_TYPE=` (`installer.py:1225` @v2.8).

### 13.3 The OVA — `system.firmware`
`support/poi/configs/ova/photon.yaml` sets `firmware: efi` and `secure_boot: false`.
`docker/create-ova` cross-checks the two and fails the build on a mismatch:
`Error: installer config bootmode is 'efi', but ova config firmware is '<x>'`.
4.0 exposed this as two distinct make targets — `ova` and `ova_uefi`
(`origin/4.0:build.py:50-51`). In 5.0 `build.py:1169` still lists
`self.ova_images = ["ova_uefi","ova"]` but `poi.py` has **no `ova_uefi` handler**,
which is what breaks `all-images` (§11 / C19).

---

## 14. Dimension 9 — Secure Boot (and the canister confusion)

The phrase "with canister for secure boot" conflates two unrelated things. Both exist:

### 14.1 FIPS crypto canister
See §12.3. It is a *cryptographic module boundary* for FIPS 140 certification,
not a boot-chain feature.

### 14.2 UEFI Secure Boot
**a) Stock Broadcom chain (build-level).**
Specs present in `/root/5.0/SPECS`: `shim`, `shim-signed`, `sbsigntools`, `mokutil`,
`efibootmgr`, `efivar`, `grub2`, `gnu-efi`.
`shim-signed-16.1` ships `/boot/efi/EFI/BOOT/bootx64.efi` (Microsoft-UEFI-CA-signed
shim) and `revocations.efi`; the revocations file is re-signed in place when
`%{signing_script}` is set. `linux.spec` generates SBAT metadata from
`linux-sbat.csv.in` (x86_64 only) and carries `photon_sb2020.pem` / `photon_km_2025.pem`.
The OVA declares `secure_boot: false` by default.

**b) HABv4 post-processing (this repo's own constellation).**
`/root/photonos-scripts/HABv4SimulationEnvironment` — tool
`PhotonOS-HABv4Emulation-ISOCreator`, skill file
`.factory/skills/photonos-secureboot-iso/SKILL.md`. It **rewrites a finished stock
ISO** into one that boots on physical Secure-Boot hardware:
* replaces VMware's shim with the Microsoft-signed **SUSE shim** (SBAT `shim,4`)
* builds a custom GRUB stub **without `shim_lock`**, MOK-signed
* generates MOK-signed variant RPMs: `shim-signed-mok`, `grub2-efi-image-mok`,
  `linux-mok` (discovered by file path, not version), each with matching
  `Provides:` and `Conflicts:`
* injects `packages_mok.json` + a rewritten `build_install_options_all.json`
  ("1. Photon MOK Secure Boot") into the initrd, and patches `linuxselector.py` to
  add a `linux-mok` → "MOK Secure Boot" entry
* flags: `-r/--release {4.0,5.0,6.0}`, `-R/--rpm-signing` (GPG), `-E/--efuse-usb`,
  `-u/--create-efuse-usb=DEV`, `-d/--drivers[=DIR]`, `-D/--diagnose=ISO`, `-c/--clean`

**Verified working:** `photon-5.0-dde71ec57.x86_64-secureboot.iso`
(5 186 764 800 B, 2026-08-11) sits next to its 4.6 GB stock parent
`photon-5.0-dde71ec57.x86_64.iso` in `/mnt/c/Users/dcaso/Downloads/Ph-Builds/`.
The seed's memory of a `photon-5.0-secureboot.iso` in `/root/5.0/stage/` is
consistent with this artifact; the file is no longer under `stage/` (it was moved to
the output directory), so I could not verify the exact former filename.

---

## 15. ADDITIONAL DIMENSION — SELinux mode (disabled / permissive / enforcing)

Two independent controls.

### 15.1 Build-time: `/etc/selinux/config` shipped by `selinux-policy`

`249ac3ff4 "91/92: selinux-policy: Mark disabled in 91 and permissive in 92"`
(Vamsi Krishna Brahmajosyula, 2026-08-19) is now in the 5.0 tree, giving a
tri-state keyed to subrelease:

| | `SPECS/selinux-policy` | `SPECS/90/…` | `SPECS/91/…` |
|---|---|---|---|
| gate | `>= 92` | `<= 90` | `== 91` |
| `config` | `SELINUX=permissive` | `SELINUX=enforcing` | `SELINUX=disabled` |

**Measured 2026-09-01.** A default subrelease-92 install boots **Permissive**, and
that is the intended shipped behaviour, not a defect. Four full-ISO STIG installs
(k11, k12, k15, k16) installed `selinux-policy-43.6-4` and booted Permissive with
0 failed units; four minimal-ISO STIG installs (k03, k04, k07, k08) booted
Enforcing — but only because those ISOs carried a stale `43.6-3` left in
`stage/RPMS` from June. Same playbook, same package names, opposite outcome: the
release number was the whole difference.

Two consequences worth carrying forward:

* **Do not assert Enforcing on >= 92.** A test oracle that expects it will report
  four false failures, which is exactly what happened before the cause was found.
* **`selinux-relabel.service` is inert by default.** The STIG relabel task is gated
  on `grep -q '^SELINUX=enforcing' /etc/selinux/config`, so on a stock 92 install
  the trigger file is never written and the service never runs. The fix is correct
  but only applies to operators who opt into enforcing.

Related on the kernel side: `8273a71ea "92: linux: Default selinux to off for 6.12 kernel"`
*is* in local HEAD.

### 15.2 Install-time: kickstart `security.selinux`
Accepted values `enforcing | permissive | disabled | null`
(`installer.py` `validate_config`, post-`a88cf02`). Effects:
* `disabled` → `selinux=0` on the cmdline
* `permissive`/`enforcing` → `security=selinux selinux=1 enforcing=0|1`
* `null` → config untouched (explicit bypass)
* absent → **defaults to `permissive` and forces `selinux-policy` into the package
  set** (post-`a88cf02` only; in v2.8 an absent `security` section meant no
  selinux handling at all). This is the seed's "injects a default `security`
  section" — confirmed.

---

## 16. ADDITIONAL DIMENSION — output artifact format

Beyond ISO. Produced inside the POI container (`docker/Dockerfile` installs
`qemu-img` and `open-vmdk`):

| target | pipeline | final artifact |
|---|---|---|
| `iso` | `photon-iso-builder -f build-iso` + `--rpms-list-file` | `photon-<ver>-<sha>.<arch>.iso` |
| `minimal-iso`/`rt-iso`/`basic-iso` | `photon-iso-builder` w/o rpm-list | `photon-<type>-<ver>-<sha>.<arch>.iso` |
| `src-iso` | copy SRPMs → `createrepo` → `mkisofs` (`poi.py:367-400`) | `…<sha>.<arch>.src.iso` |
| `debug-iso` | same, `DEBUGRPMS` | `…<sha>.<arch>.debug.iso` (poi.py-only) |
| `ova` / `ova-stig` | `create-image` → raw `.img` → `vmdk-convert` → `ova-compose` | `.vmdk` (+ optional `.ovf`, `.mf`) → `.ova` |
| `azure` | `qemu-img resize` to 1048676 MB → `qemu-img convert -O vpc -o subformat=fixed,force_size` → tar | `.vhd.tar.gz` |
| `ami` | rename to `.raw` → `tar zcf` | `.tar.gz` |
| `gce` | rename to `disk.raw` → `tar zcf` | `.tar.gz` |
| `rpi` / `ls1012afrwy` | `xz -c` | `.img.xz` |
| `photon-docker-image` | container rootfs script | `photon-rootfs-<ver>-<sha>.<arch>.tar.gz` |
| `k8s-docker-images` | 11 build scripts | 21 `.tar.gz` container images in `stage/docker_images/` |

`create-ova` sub-modes are themselves a dimension: `--vmdk` (stop at VMDK),
`--ovf` (OVF instead of OVA), `--mf` (manifest), `--sign-script`,
`--compression-level`, `--num-threads`.

---

## 17. Known-broken / caveats

1. **STIG on a minimal ISO fails.** §11.1. Measured: 254 RPMs on the media, none of
   the six STIG packages. Root cause `isoBuilder.downloadPkgs()` builds the media
   repo from the package-list closure only. *Workaround:* build `IMG_NAME=iso`, or
   add the STIG set to `common/data/packages_minimal.json` before building.
2. **`rt-iso` cannot be built at subrelease ≥ 91.** The only `linux-rt.spec` in the
   5.0 tree is `SPECS/91/linux/linux-rt.spec` with `%global build_if %{photon_subrelease} <= 90`,
   yet `packages_rt.json` requires `linux-rt` and `linux-rt-devel`. The runPh
   scripts' `$5` validator accepts `rt-iso` regardless.
3. **`basic-iso` cannot be built at all.** There is no
   `support/poi/configs/basic-iso/` directory, so no `basic-iso.yaml` reaches
   `stage/basic-iso/`. `isoBuilder.main()` (`isoBuilder.py:622-628`) treats a
   non-existent `--config` path as a URL, `wget`s it, and raises
   `Exception: Error - …`. (`poi.py:105-127` only prints "not found, ignoring" for
   the config *directory*, which is why the failure surfaces later and confusingly.)
4. **`ls1012afrwy` cannot be built.** It is in `build.py:44` but `poi.py`'s dispatch
   (`:512, :538, :556`) has no branch for it → `assert False, f"unknown target {target}"`.
5. **`all-images` cannot complete.** `BuildImage.all_images()` (`build.py:1418-1423`)
   iterates `self.ova_images = ["ova_uefi","ova"]`; `ova_uefi` has no `poi.py` handler
   and no `configs/ova_uefi/` directory. Same failure mode as (4).
6. **`ova-stig` and `debug-iso` are not reachable from `make`.** Not in
   `build.py:36-52`; `IMG_NAME=ova-stig` degrades to "build a package named ova-stig".
7. **OSTree is gone.** §10. POI ≥ 2.9 has no ostree code; 5.0/6.0's build system has
   no `ostree-repo` target; the install menu entry exists only in 4.0.
8. **No cross-architecture builds.** §4. `target-arch` is documented but unimplemented;
   `CROSS_TARGET` maps to a typo'd dead key. aarch64 needs an aarch64 host.
9. **`poi.py` hardcodes `RELEASE_VER = "5.0"`** (`poi.py:14`) and `build.py` never
   overrides it — every `photon-iso-builder` invocation is told `-v 5.0`.
10. **`PHOTON_TDNF_EXCLUDE_PKGS` does not exist in this `common` checkout.**
    `runPh5_pinned90.sh:27-30` and `runPh5_pinned91.sh:26-33` export it and write
    `/tmp/photon-tdnf-exclude-pkgs.txt`, commenting that `TDNFSandbox.py` reads it.
    Grepping the entire `/root/common` tree for `PHOTON_TDNF_EXCLUDE_PKGS` or
    `photon-tdnf-exclude-pkgs` returns **nothing**. Either the mechanism was a local
    patch that has since been reverted, or it lives in a `common` branch not checked
    out here. `runPh6.sh:83-85` defensively deletes that leftover file because it
    breaks a 6.0 build with `rc 21 / "package libcap-libs-2.77 is disabled"`.
11. **The local `/root/5.0` is 56 commits behind `origin/5.0`.** The SELinux
    tri-state (§15.1) and everything else in those 56 commits is absent from any
    build you start right now.
12. **`/root/5.0` has 8 uncommitted spec modifications** (`linux.spec`, four
    `openjdk*.spec`, `photon-os-installer.spec`, `python3.spec`,
    `stig-hardening.spec`) plus 6 untracked patch files. `runPh5_normal.sh` and
    `runPh5_pinned90.sh` explicitly `git checkout --` every dirty tracked file at
    the start of a run, so **these local fixes are re-applied from
    `staging/photonos-patches/downstream-fixes.patch`, not preserved in place.**
13. **Subrelease pinning defeats the spec checker by design.** Both pinned scripts
    set `base-commit` to the *common* HEAD so the checker's `git diff` is empty
    (`runPh5_pinned91.sh:6-14`, `build.py:1937-1948`). You are trading away spec
    validation for the ability to pin.
14. **4.0 + STIG + minimal ISO is documented-unsupported upstream.**
    `staging/custom-4.0-installer/README.md` (upstream issue
    `vmware/photon-os-installer#35`): POI built for 5.0 needs `tdnf >= 3.5.6` which
    4.0 lacks; ansible fails with `locale encoding to be UTF-8: Detected None`;
    `/dev/shm` is too small. Supported path is 4.0 → 5.0 first.
15. **The runPh scripts were being edited by other agents while this was written.**
    `runPh5_normal.sh` changed between two consecutive reads (line 532 →
    line 562, `IMG_NAME=minimal-iso` → `IMG_NAME="$IMG_TYPE"`). Line numbers cited
    for `staging/runPh*.sh` may drift; the `build.py` / `poi.py` / spec citations are stable.
16. **`photon-os-installer` is not built at subrelease 90.**
    `photon-os-installer.spec:1` is `build_if >= 91`; the `<= 90` variant lives in
    `SPECS/90/photon-os-installer/`. Likewise `stig-hardening` is `>= 91`.

---

## 18. How to select each constellation — quick reference

```bash
# ---- release line + subrelease (choose the driver script) ----
staging/runPh4.sh          BASE_DIR COMMON_BRANCH RELEASE_BRANCH OUT_DIR [IMG_TYPE]  # 4.0
staging/runPh5_normal.sh   ...                                                        # 5.0 @ upstream subrelease (92)
staging/runPh5_pinned90.sh ...                                                        # 5.0 pinned to 90
staging/runPh5_pinned91.sh ...                                                        # 5.0 pinned to 91
staging/runPh6.sh          ...                                                        # 6.0 (subrelease 100)
# defaults: BASE_DIR=/root  COMMON_BRANCH=common  RELEASE_BRANCH=<line>
#           OUT_DIR=/mnt/c/Users/dcaso/Downloads/Ph-Builds  IMG_TYPE=minimal-iso

# ---- subrelease, without a script (the supported knob) ----
PHOTON_SUBRELEASE=91 make image IMG_NAME=iso          # build.py:1879-1881
# ...but the spec checker asserts subrelease <= photon-mainline, so also set
# "photon-mainline" to the same value in <release>/build-config.json,
# or set "base-commit" to bypass the checker.

# ---- image type ----
make image IMG_NAME=iso            # full ISO   (has the STIG package set)
make image IMG_NAME=minimal-iso    # minimal    (does NOT — see §11.1)
make image IMG_NAME=src-iso
make image IMG_NAME=ova            # -> .vmdk + .ova
make image IMG_NAME=azure          # -> .vhd.tar.gz
make image IMG_NAME=ami|gce        # -> .tar.gz
make image IMG_NAME=rpi            # aarch64 host only
make image IMG_NAME=photon-docker-image
make image IMG_NAME=k8s-docker-images
BUILD_DEBUG_ISO=1 make image IMG_NAME=iso
FORCE_IMG_BUILD=1 make image ...   # rebuild even if the artifact exists (build.py:1210-1211)

# poi.py-only targets (run from common/support/poi/):
./poi.py --stage-dir <stage> --docker-image photon/installer:latest ova-stig
./poi.py --stage-dir <stage> --arch aarch64 rpi        # --arch works here, not via make

# ---- architecture ----
# No flag. Build on the target architecture. (target-arch / CROSS_TARGET are dead.)

# ---- FIPS / canister ----
CANISTER_BUILD=1 make image IMG_NAME=iso   # build the canister
ACVP_BUILD=1     make image IMG_NAME=iso   # forces fips=1
KAT_BUILD=1      make image IMG_NAME=iso   # forces acvp_build=1 + canister_build=1
# per-package override: pkg_build_options.json -> {"linux": {"macros": ["fips 0"]}}

# ---- sandbox type ----
# <common>/build-config.json : "photon-build-type": "chroot" | "systemd-nspawn" | "container"

# ---- POI container image ----
POI_IMAGE=photon/installer:latest make image IMG_NAME=iso     # or build-config "poi-image"

# ---- POI RPM version ----
# edit SPECS/photon-os-installer/config.yaml (url + commit_id + archive_sha512sum)
# and bump Release: in photon-os-installer.spec

# ---- STIG ----
#   at install time : ISO menu "Apply STIG hardening" -> Yes   (needs the FULL ISO)
#   at build time   : ./poi.py ova-stig
#   in a kickstart  : ansible: [{playbook: /usr/share/ansible/stig-hardening/playbook.yml,
#                                extra-vars: "@/usr/share/ansible/stig-hardening/vars-chroot.yml"}]

# ---- SELinux ----
# kickstart:  security: {selinux: enforcing|permissive|disabled|null}
# build-time default comes from SPECS[/<n>]/selinux-policy/config  (see §15.1)

# ---- EFI / BIOS ----
# kickstart:  bootmode: efi | bios | dualboot     (aarch64: efi only)
# OVA:        support/poi/configs/ova/photon.yaml -> system.firmware / system.secure_boot

# ---- Secure Boot (MOK, physical hardware) ----
cd HABv4SimulationEnvironment && ./PhotonOS-HABv4Emulation-ISOCreator \
    --release 5.0 --build-iso [--rpm-signing] [--efuse-usb]

# ---- upgrades ----
photon-upgrade                                  # update within 5.0 (incl. subrelease step)
photon-upgrade --upgrade-os --to-ver=6.0        # 5.0 -> 6.0   (only 6.0 is accepted)
photon-upgrade --precheck-only                  # dry run
```

---

## 19. Things I could NOT determine

* Whether upstream `vmware/6.0` also self-identifies as `.ph5` / release `5.0` /
  subrelease `100` — only `vmware/5.0` is fetched on this host.
* ~~Where `linux-fips-canister-6.12.60-18.2.ph5` comes from concretely~~ —
  **answered 2026-09-02: nowhere. It is not published.** The guess that it
  resolves from `packages.broadcom.com` is wrong. The repo index at
  `https://packages.broadcom.com/artifactory/photon/5.0/photon_updates_5.0_x86_64/x86_64/`
  publishes `linux-fips-canister-6.12.60-18.ph5` — release `18`, not `18.2`. So the
  pin above cannot be satisfied by any published RPM, and a build that recompiles
  the kernel has no canister to link. This is the reason the `equivalent` canister
  mode exists and why its phase A is currently mandatory rather than optional:
  see the matrix docs, section 2b.
* The exact former filename of the secure-boot ISO in `/root/5.0/stage/` — that
  directory now holds only `iso/`, `minimal-iso/` and no ISO named `*secureboot*`.
* The numeric meaning of installer `Error(1011)`: no `tdnferror.h` is present on
  this machine and I could not locate the code table. The *cause* of the failure is
  nevertheless established independently by the repo-content measurement in §11.1.
* Whether the `SPECS/92/linux/v6.1` kernel winning the `KERNEL_VERSION` macro race
  (§3.4) actually mis-templates the kernel-dependent specs — that would need a build.
* Whether `PHOTON_TDNF_EXCLUDE_PKGS` (§17.10) ever existed in this `common` branch
  or came from a different checkout.

---

## 20. Evidence index

| Fact | Where |
|---|---|
| image target list | `/root/common/build.py:36-95` |
| `IMG_NAME` / `CONFIG` override | `/root/common/build.py:1913-1925` |
| `PHOTON_SUBRELEASE` override | `/root/common/build.py:1879-1881` |
| env → config key map (25 keys) | `/root/common/build.py:1709-1734` |
| snapshot repo gate | `/root/common/build.py:1560-1574` |
| sandbox type validation | `/root/common/build.py:1484-1487` |
| kat/canister/acvp wiring | `/root/common/build.py:1614-1618`, `constants.py:263-270` |
| spec search paths | `/root/common/build.py:1461-1481` |
| `run_poi` argv (no `--arch`) | `/root/common/build.py:1251-1262` |
| full vs custom ISO split | `/root/common/support/poi/poi.py:334-365` vs `:403-427` |
| poi target dispatch | `/root/common/support/poi/poi.py:512, 538, 556` |
| `RELEASE_VER = "5.0"` | `/root/common/support/poi/poi.py:14` |
| `build_if` evaluation | `support/package-builder/SpecParser.py:139-141, 317-324` |
| default-kernel resolution | `support/package-builder/SpecData.py:578-600` |
| `buildArch = platform.machine()` | `support/package-builder/constants.py:68` |
| signing macros | `support/package-builder/signing.py:9-14, 65-71` |
| STIG package list | `photon_installer/stigenable.py:21-30` |
| STIG menu wiring | `photon_installer/iso_config.py:202-203` |
| ISO repo built from closure | `photon_installer/isoBuilder.py:186-247` |
| kernel flavor fallback | `photon_installer/isoBuilder.py:198-206` |
| supported releases | `photon_installer/isoBuilder.py:23-24` |
| BIOS/EFI El Torito | `photon_installer/isoBuilder.py:276-298, 395-422` |
| `bootmode` handling | `photon_installer/installer.py` @`v2.8`:`355-360, 397-399, 666-667, 1225` |
| linux flavor list | `photon_installer/installer.py:124`; `linuxselector.py:31-36` |
| fips/canister flag family | `/root/5.0/SPECS/linux/linux.spec:20-79, 123-146, 559-563, 695-707` |
| POI source pin | `/root/5.0/SPECS/photon-os-installer/config.yaml` |
| subrelease tdnf var | `/root/5.0/SPECS/photon-repos/photon-repos.spec:64-67, 78-80` |
| upgrade tool | `/root/5.0/SPECS/photon-upgrade/photon-upgrade.sh:16, 66, 443, 934-944` |
| ostree removal | POI commit `abdff38`; `origin/4.0:build.py:695-712, 1114, 1129` |
| SELinux tri-state | `/root/5.0` commit `249ac3ff4` (on `origin/5.0`, **not** local HEAD) |
| installer selinux default | POI commit `a88cf02` (adds `Defaults.SELINUX_DEFAULT`) |
| secure-boot ISO tool | `HABv4SimulationEnvironment/.factory/skills/photonos-secureboot-iso/SKILL.md` |
| full-ISO repo contents | `/root/5.0/stage/iso/photon-so839tgh/RPMS` (1901 RPMs) |
| minimal-ISO repo contents | `/root/5.0/stage/minimal-iso/photon-16jushya/RPMS` (254 RPMs) |
| built artifacts | `/mnt/c/Users/dcaso/Downloads/Ph-Builds/` |
