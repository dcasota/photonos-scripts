# Design note: Hyper-V (Azure) kernel config as a sharukhan-cli build parameter

Status: **largely implemented.** Written as a proposal, derived from the manual proof of concept in
`/root/aarch64-azure-work` (Photon 5.0 aarch64 ISO 3de6164e1 → `photon-5.0-3de6164e1.aarch64.azure.iso`), and kept
here as the record of *why* the implementation looks the way it does.

What has since been built: `src/kconfig.rs` (fragment, tristate parser, `dependency_closure`, ikconfig extraction),
`src/remaster/{buildroot,kernel,cc1,initrd,repo,iso,guard}.rs`, `src/embedded/hyperv.fragment`, and the
`Injection::KernelConfig` / `ReleaseBump` pair in `buildmode.rs`/`buildexec.rs`. The §7 mapping table below names
the Rust home of each PoC script and is accurate as built.

Two corrections the implementation established, which the text below predates:

* The fragment in the repo deliberately does **not** list `CONNECTOR`, `VSOCKETS`, `SCSI_FC_ATTRS` or
  `PCI_HYPERV_INTERFACE`, exactly as §2 argues: `kconfig::dependency_closure` computes them per config, and
  `PCI_HYPERV` `select`s the interface symbol.
* §6a states the 5.0 aarch64 initrd carries photon-os-installer 2.7. The `PKG-INFO` in that initrd's
  `site-packages` reads **2.2**. Because the two disagree, `remaster::poi` gates its installer patching on the
  source text rather than on a version number.

## 1. Goal

Add one opt-in parameter that makes a Photon kernel flavour carry Hyper-V guest support **built in**, so the ISO's installer
kernel can find VMBus storage and network devices without extra initrd modules:

```
CONFIG_HYPERV=y  CONFIG_HYPERV_STORAGE=y  CONFIG_HYPERV_NET=y  CONFIG_HYPERV_UTILS=y
CONFIG_HYPERV_BALLOON=y  CONFIG_HYPERV_VSOCKETS=y  CONFIG_PCI_HYPERV=y
```

It applies to **x86_64 and aarch64** ISOs.

## 2. Kconfig facts that drive the design (6.1.128; re-checked per kernel version by the injection)

| symbol | depends on | gating symbol in Photon configs |
|---|---|---|
| HYPERV | ACPI && ((X86 && X86_LOCAL_APIC && HYPERVISOR_GUEST) \|\| (ARM64 && !CPU_BIG_ENDIAN)) | all present |
| HYPERV_UTILS | HYPERV && CONNECTOR && NLS && PTP_1588_CLOCK_OPTIONAL | CONNECTOR=m caps it at m |
| HYPERV_STORAGE | SCSI && HYPERV && (m \|\| SCSI_FC_ATTRS != m) | SCSI_FC_ATTRS=m caps it at m |
| HYPERV_VSOCKETS | VSOCKETS && HYPERV | VSOCKETS=m caps it at m |
| PCI_HYPERV | (X86_64 \|\| ARM64) && HYPERV && PCI_MSI && PCI_MSI_IRQ_DOMAIN && SYSFS; selects PCI_HYPERV_INTERFACE | ok |
| HYPERV_BALLOON / HYPERV_NET | HYPERV (select PAGE_REPORTING / NLS, UCS2_STRING) | ok |

A tristate can only be `y` when every dependency is `y`. The fragment therefore has two parts:
the seven target symbols, plus the **dependency closure** that is `m` in the current config.
The closure must be computed, not hard-coded. The generic implementation reads each target's resulting value after
`olddefconfig`. If a target came out below `y`, it reports the gating symbol, taken from `scripts/config`/`.config` as in the table.
It then raises that symbol to `y` and iterates. Where a dependency cannot be `y`, it fails with the Kconfig evidence.

### What the configs carry today

These values were read with `git show`, without touching the working tree.

| file (origin/5.0 = 41e75907c, kernel 6.12.109; 3de6164e1 = 6.1.128) | HYPERV | the other six | cap-setting deps |
|---|---|---|---|
| `SPECS/linux/config_x86_64` (generic) | **m** | all **m** (HYPERV_TIMER=y, HYPERV_IOMMU=y) | VSOCKETS=m, SCSI_FC_ATTRS=m; CONNECTOR=y, PTP_1588_CLOCK_OPTIONAL=y |
| `SPECS/linux/config-esx_x86_64` (linux-esx) | not set | not set | VSOCKETS=y, CONNECTOR=m, SCSI_FC_ATTRS not set, PTP_1588_CLOCK_OPTIONAL=**m** |
| `SPECS/linux/config_aarch64` (generic) | not set | not set | VSOCKETS=m, CONNECTOR=m, SCSI_FC_ATTRS=m |
| `SPECS/linux/config-esx_aarch64` | not set | not set | VSOCKETS=y, CONNECTOR=m, SCSI_FC_ATTRS not set, PTP_1588_CLOCK_OPTIONAL=m |
| branch `fix/kernel-single-source` (0b673b593): `SPECS/linux/6.1/config_x86_64-6.1`, `config_aarch64-6.1`, `config-esx_*-6.1`; 6.12 configs keep the plain names; the spec selects them by `photon_subrelease` (≤90 → 6.1) | same pattern | | |

Notes:
* x86_64 generic is **already Hyper-V capable as modules**. Its initrd builds via dracut in the installed system, but the *installer*
  initrd is a fixed rootfs, so storvsc/netvsc as `m` depend on udev autoloading from the full module tree.
  `=y` removes that dependency and makes the ISO boot path equal to aarch64's.
* ESX flavours: `HYPERV_UTILS=y` there also needs PTP_1588_CLOCK=y. PTP_1588_CLOCK_OPTIONAL=m means PTP is m, which is a
  larger change to a VMware-tuned flavour. **Recommendation:** by default the parameter targets the **generic `linux` flavour only**.
  `--hyperv-flavours linux,linux-esx` is an explicit opt-in that runs the same closure algorithm and reports the additional forced symbols.
  The installer always offers both `linux` and `linux-esx`; the Azure kickstart/UI choice must be `linux`.
  The verify step (below) asserts this.

### Config file targeting per arch/flavour

`kernel_config_path(tree, arch, flavour, kernel_series)` →

| arch \ flavour | linux | linux-esx |
|---|---|---|
| x86_64 | `SPECS/linux/config_x86_64` (single-source & subrelease ≤90: `SPECS/linux/6.1/config_x86_64-6.1`) | `config-esx_x86_64` / `6.1/config-esx_x86_64-6.1` |
| aarch64 | `SPECS/linux/config_aarch64` / `6.1/config_aarch64-6.1` | `config-esx_aarch64` / `6.1/config-esx_aarch64-6.1` |

On 3de6164e1-era trees (`SPECS/91` etc. layout) the 6.1 configs live in `SPECS/91/linux/`. The resolver must use
the same subrelease logic that `PinSubrelease` already feeds, and it must never guess. A missing file is a typed error.

**Never touch `config_x86_64_acvp`.** ACVP and KAT builds are FIPS certification artefacts.

## 3. CLI surface and composition with existing axes

* `build` / `build-iso`: new flag `--hyperv` (default off), plus `--hyperv-flavours linux[,linux-esx]` (default `linux`) and
  `--arch x86_64|aarch64` (default: host arch; aarch64 on an x86_64 host implies the emulated builder, see §5).
* Build model (`buildmode.rs`):
  * new `Injection::KernelConfig { arch, flavour, fragment: KconfigFragment }`
  * new `Embedded`-like constant `KconfigFragment::HyperVBuiltin` (the 7 symbols, compiled in with `include_str!`)
  * new `Injection::ReleaseBump { spec, suffix, changelog }`
  * `spec_for` pushes the pair after `TreePatch(poi)`/`Embed`/`PkgBuildOptions` and before the fixups. Stage order
    stays Reset → Inject(..) → Sources → Preflight → Purge → Make → Post, and `reset` already restores `SPECS/`.
* **Composition with canister modes** (x86_64 generic has `%global fips 1`):
  * `prebuilt`: allowed. The FIPS canister object is linked unchanged. HYPERV=y does not touch crypto structs, but the spec's
    struct-comparator (`struct-comparator.c` over vmlinux) is the authority. Preflight must not skip it, and a mismatch fails the build.
  * `equivalent` (A/B): the injection is applied identically in both phases, so the phase-B kernel differs from phase A only by the
    canister. `post_assert` gains the Hyper-V assertion for both phases.
  * `acvp` / `kat`: rejected with a typed error (`HyperVIncompatible { mode }`), because it would change certified configs.
* **Matrix** (`permutations.tsv`): add a build-time axis value rather than a new column, to keep the TSV shape and `iso_key()`
  stable. The `canister` column becomes a `+`-joined build-variant list: `prebuilt+hyperv`, `equivalent+hyperv`,
  `fips0-aarch64+hyperv`. `Permutation::build_variants()` splits it. `iso_key` stays `{type}/{poi}/{canister}`, so these ISOs cache
  separately (`full-poi2.8-prebuilt+hyperv`). `CanisterMode::parse` receives only the canister part. This also fixes the
  gap that `fips0-aarch64` is currently unparseable: it becomes `Arch::Aarch64` + `CanisterMode::Prebuilt`.
  `unrunnable_reason()` changes from "needs aarch64 hardware" to "needs aarch64 hardware **or** a registered qemu-aarch64 binfmt +
  arm64 builder image" (checked in `doctor`).

## 4. Release bump / changelog

A config change must yield a distinguishable NEVR. Otherwise `kernel_nevr()` predictions, repo metadata and the verify oracle cannot tell
the Hyper-V kernel from the stock one.

* `Release: N%{?acvp_build:.acvp}%{?kat_build:.kat}%{?dist}` → `N+1…​.azure%{?dist}`. The PoC produced `6.1.128-2.azure.ph5`.
  rpmvercmp orders it above `1.ph5` and below upstream `2.ph5` (`azure` < `ph5`), so a later official build still upgrades it.
  An alternative is to keep N and use `N.azure1`, which sorts below `N.ph5` and would therefore be replaced by `tdnf distro-sync`. Rejected.
* uname_r follows Release (`CONFIG_LOCALVERSION="-%{release}"` via the spec sed), so /lib/modules, vermagic and `/boot/linux-*.cfg`
  all carry `.azure`, which is visible on the running system.
* changelog: prepend `* <date> <author> <ver>-<rel>` + `- <arch>: build Hyper-V guest support in (...)`. The author comes from config
  (`Daniel Casota <dcasota@gmail.com>`). On the single-source branch the changelog lives in `*-changelog.inc` and the Release in
  `linux-6.1.inc`/`linux-6.12.inc` (the same files the canister-equivalent patch edits). ReleaseBump must therefore target the resolved
  file, and it must compose with the equivalent patch's own bump: apply after Embed and bump relative to what is there.
* `build.rs::kernel_nevr*` learns the `.azure` suffix, so post_assert and verify predict the right RPM names.
* When both flavours are selected, both `linux.spec` and `linux-esx.spec` are bumped. Dependent subpackages (`-devel`, `-drivers-*`, `-docs`,
  `-tools`, `-python3-perf`) come from the same spec, which matters because the ISO repo has `Requires: linux = V-R` on them.

## 5. Producing the aarch64 ISO without aarch64 hardware

Two paths:

**(a) Full Photon build under emulation.** Photon's `make` with a `photon:5.0-arm64` sandbox under qemu-user. This works in
principle, but a whole ISO means hundreds of packages at 5–10× slowdown, so it is days of work. It is also not how the PoC was proven.

**(b) Remaster phase (recommended; proven by the PoC).** Start from a published/cached aarch64 ISO. Rebuild only the kernel spec(s)
in an emulated arm64 build root, then remaster:

1. `remaster::bootstrap_buildroot`: `tdnf --installroot` of the spec's BuildRequires **from the input ISO's own RPMS**, so the
   toolchain matches the ISO (gcc 12.2.0-5, glibc 2.36, rpm 4.18), then `docker import` → `sharukhan-arm64-buildroot:<iso-id>`.
   Caveat: a newer helper image with rpm 6 needs `%__transaction_unshare %{nil}` in unprivileged containers.
   The kernel config check also needs `linux-api-headers`.
2. `remaster::gen_config` (= KernelConfig injection run in the arm64 root): `rpmbuild -bp`, fragment via `scripts/config`,
   `make ARCH=arm64 olddefconfig`, per-symbol assertion, drop line 3, and a **fixed-point re-run** (the same check as Photon's
   `check_for_config_applicability.inc`). It must run with the target toolchain, because CC_VERSION_TEXT and CC_HAS_* land in the config.
3. `remaster::build_kernel`: `rpmbuild -ba --nodeps` in the arm64 container. The disk layout is parameterised: `_builddir` on tmpfs or a large volume,
   `_buildrootdir`/`_rpmdir` elsewhere. `KCFLAGS/KAFLAGS=-gz=zlib` is optional and only for low-disk hosts; it changes only debug-section encoding and degrades
   the -debuginfo package.
4. `remaster::initrd`: unpack the installer initrd (gzip newc cpio), swap `usr/lib/modules/<old uname>` for the new RPM's tree, run
   `depmod` with the ISO's kmod (arm64 root), and repack.
5. `remaster::repo`: overlayfs over the read-only ISO `RPMS`, replace the spec's subpackages, run `createrepo_c --update --outputdir`.
6. `remaster::iso`: `xorriso -indev in -outdev out -boot_image any replay`. It rm/maps the RPMs, repodata, `/boot/{config,System.map,linux-*.cfg}`,
   `isolinux/vmlinuz` and `isolinux/initrd.img`, keeps `/boot/grub2/efiboot.img` and the boot catalog, then writes `.sha256`.

   Known gap: `/ostree-repo.tar.gz` still contains the stock kernel for OSTree installs.

The same phase works for x86_64 on an x86_64 host with native docker (`photon:5.0`), so one code path covers
"make an Azure variant of an existing ISO" for both arches. A full `build-iso --hyperv` on x86_64 uses the normal cascade (§3).

New subcommand:
```
sharukhan remaster --in <iso> --out <iso> [--arch aarch64|x86_64] --hyperv [--hyperv-flavours linux] [--builder-image <img>]
                   [--builddir <path>] [--jobs N] [--dry-run]
```
Runs as `Stage::Remaster{Bootstrap,GenConfig,BuildKernel,Initrd,Repo,Iso,Verify}` with `run/stop/watch` semantics (ADR 0001)
because BuildKernel takes hours under emulation. A disk-space guard mirrors the PoC watchdog: stop the builder container below a threshold.

## 6. Verify / media assertions (both arches)

Extend `oracle::media` (today it only lists RPM names via xorriso `-find`) with `media.kernel_config`:

1. `xorriso -osirrox on -indev <iso> -extract /RPMS/<arch>/linux-<V-R>.<arch>.rpm <tmp>`, then read the rpm payload via `rpm2cpio | cpio`
   (or the `cpio` crate) and parse `/boot/config-<uname>` → `BTreeMap<String, Tristate>`.
2. Assert the seven symbols `== y` (and, for the negative control, that a stock ISO yields `m`/unset for them, i.e. the check can fail).
3. Installer kernel: extract `/isolinux/vmlinuz` and assert it is byte-identical to `/boot/vmlinuz-<uname>` from the RPM.
   Independently, extract its IKCONFIG: arm64 `Image` is uncompressed and x86 `bzImage` needs decompression; search for the `IKCFG_ST` marker
   + gzip, in a Rust port of `scripts/extract-ikconfig`. Assert the same seven symbols.
4. initrd consistency: gunzip+cpio list `usr/lib/modules/*`. Exactly one dir must equal the uname, and there must be no `hv_*.ko*` (they are built in).
   Checking one module's `vermagic` (modinfo section in `.ko.xz`) against the uname is also a matter of a few lines.
5. Repo consistency: primary.xml lists the new NEVR and not the old one, and `Requires: linux = V-R` of `linux-devel`/`-drivers-*` resolves.
6. Results land as `media.hyperv.{rpm_config,installer_ikconfig,vmlinuz_identical,initrd_modules,repo}` with pass/fail and evidence.
   The matrix `expect` column can then require them for `*+hyperv` rows.

Runtime proof (optional, later): boot the ISO in `qemu-system-aarch64`/`x86_64` with edk2 up to the installer prompt. The real
acceptance test is an Azure arm64/x64 VM install, which sits outside the VMware-only VM layer (`vmware.rs`) and needs a new VM provider.

## 6a. Lessons from producing the ISO (must be encoded, not rediscovered)

* **Emulated compile speed / native cc1.** Under qemu-user the kernel compiles at ~34 objects/min. A static
  x86_64-hosted cross `cc1` built from the *same* GCC 12.2.0 tarball (sha512 from gcc.spec) + Photon's
  `PLUGIN_TYPE_CAST.patch`, in-tree gmp 6.2.1 / mpfr 4.1.0 / mpc 1.3.1, and the spec's codegen flags
  (`--enable-default-pie --enable-default-ssp --disable-multilib ...`), raised it to ~93/min. It is used via a
  wrapper that routes only `-nostdinc` compiles (kernel, ENA/EFA) to it; userspace (perf, bpftool, host tools)
  stays on Photon's emulated cc1.
  Correctness conditions found the hard way:
  1. gcc's configure must see a **target assembler, linker and objdump/readelf** (cross binutils 2.39 +
     `gcc_cv_objdump`/`gcc_cv_readelf`), and `--with-glibc-version=2.36`. Without them it silently disables
     SHF_MERGE, SHF_LINK_ORDER, CFI-directive and LEB128 support, and emits different code.
  2. The swap is gated by a **byte-identity test**. Real kernel TUs are compiled with the native cc1 and `cmp`'d
     against the objects the emulated Photon cc1 already produced. Passing run: 10/10 identical,
     47 KB – 2.7 MB, sched/mm/arm64/crypto/ext4/xfs/tcp/netdev. The Rust port must keep this gate and
     refuse to swap on any difference.
  3. The test harness must rewrite the **actual** `-o <path>` token from `.cmd` and verify the substitution.
     One `.cmd` used `arch/arm64/kvm/../../../virt/kvm/kvm_main.o`, and a naive substitution overwrote the
     real build object. It was detected, its mtime reset, and it was rebuilt by make.
  4. `as`/`ld` stay Photon's (emulated). Photon binutils carries `binutils-gas-dwarf-skip-empty-functions.patch`,
     which changes gas DWARF output.
* **rpm 4.18 resumable phases.** `-bp`, then `-bc --short-circuit` (incremental make), then `-bi --short-circuit`,
  then `-bb --short-circuit`. `-bb --short-circuit` alone does **not** run `%install`.
* **Disk guard pauses, never kills.** The build tree is on swap-backed tmpfs. The guard sends SIGSTOP/SIGCONT to the
  build process group on low / free space, so no compile work is lost.
* **Installer facts** (photon-os-installer 2.7 in the 5.0 aarch64 initrd):
  * Target installs use generated repo/tdnf configs with `gpgcheck=0`, so rebuilt unsigned RPMs install.
  * `linux-esx` is hidden unless VMware virtualization is detected, and `linux_flavor` defaults to `linux`, so an
    Azure VM gets the Hyper-V kernel without a kickstart override.
* **Replacement set** = every media RPM whose SOURCERPM is the kernel SRPM. On 5.0/6.1.128 that includes
  `bpftool` (it requires `linux-tools = V-R`). Resolve it from primary.xml, never hard-code it.
* **Boot smoke markers.** The ISO kernel runs with `loglevel=3`, so the kernel banner is not on serial. Use the
  getty issue line `Kernel <uname -r> on an aarch64 (ttyAMA0)` plus the `photon-installer` autologin and
  curses start. QEMU needs `romfile=` on virtio-net in a minimal firmware image. This was validated on the
  untouched input ISO (UEFI → GRUB → 6.1.128-1.ph5 → installer in about 3 min under TCG).
* **Release packaging must not be short-circuited.** Packages from `rpmbuild -bb --short-circuit` carry
  `Requires: rpmlib(ShortCircuited)`, which no rpm provides, so tdnf/the installer cannot install them. Final
  packaging uses `rpmbuild -bb --noprep` on the existing tree, which re-runs `%build` incrementally (0 of 7699
  objects recompiled), `%install` and packaging without that marker, plus `_binary_payload/_source_payload w19.zstdio`
  from build-config.json. The ISO packages then carry exactly the original rpmlib set (incl. `PayloadIsZstd`).
  `media`/verify must assert both properties on every replaced package.
* **Debuginfo is not on the media.** The eight ISO packages are complete when rpmbuild prints `Wrote:` for them.
  The remaster must not wait for `linux-debuginfo` (zstd-19 of the debug tree under emulation takes over an hour).
* **xorriso argv.** `-rm`/`-rm_r` take a path list terminated by `--`. Without it, following `-map`/`-rm` words
  become paths. Build the argv as typed tokens in Rust rather than strings.
* **Process supervision.** `setsid cmd &` can fork, so `wait` returns immediately and records a bogus exit code.
  Supervise by process group liveness plus an explicit success sentinel written as the phase's last action.
* **Shell gotcha.** `cmd | grep -q` under `set -o pipefail` reports SIGPIPE as failure. Use argv runners
  and file-based matching (the Rust runner avoids this class of bug).

## 7. Script → Rust mapping (project rule: generic helpers become Rust in sharukhan-cli)

| PoC script (`/root/aarch64-azure-work/scripts`) | Rust home |
|---|---|
| `hyperv-aarch64.fragment` | `src/kconfig.rs`: `KconfigFragment::HyperVBuiltin` (+ `include_str!` data), tristate parser/merger, dependency-closure resolver |
| `02-gen-config.sh` | `buildexec::inject` → `Injection::KernelConfig` (`kernel_config()`), shared by the cascade and `remaster::gen_config` |
| spec Release/changelog edit (manual) | `Injection::ReleaseBump` in `buildexec.rs` (`release_bump()`), `build.rs::kernel_nevr*` suffix awareness |
| `01-bootstrap-buildroot.sh` | `src/remaster/buildroot.rs` (`bootstrap_buildroot`, argv-only docker/tdnf runner) |
| `03-build-kernel-rpms.sh` | `src/remaster/kernel.rs` (`build_kernel`) |
| `watchdog.sh` | `src/remaster/guard.rs` (disk guard inside the run/stop/watch loop) |
| `04-rebuild-initrd.sh` | `src/remaster/initrd.rs` |
| `05-remaster-iso.sh` | `src/remaster/repo.rs` (overlay + createrepo_c) and `src/remaster/iso.rs` (xorriso replay) |
| verification one-liners (extract rpm, grep config, cmp vmlinuz, extract-ikconfig) | `src/oracle.rs::media_kernel_config` + `src/kconfig.rs::extract_ikconfig` |

## 8. Tests (in-module `#[cfg(test)]`, sentence names, negative controls)

* `kconfig`:
  * `a_fragment_symbol_capped_by_a_module_dependency_is_reported_with_the_gating_symbol` (fixture: CONNECTOR=m → HYPERV_UTILS m)
  * `the_hyperv_fragment_on_a_stock_aarch64_config_forces_connector_vsockets_and_scsi_fc_attrs` (fixture: trimmed config_aarch64)
  * `a_config_that_is_already_all_y_needs_no_closure`
  * `parsing_is_not_set_lines_yields_unset_not_n`
* `extract_ikconfig`:
  * `the_ikconfig_blob_is_found_in_an_uncompressed_arm64_image` (a tiny synthetic image with IKCFG_ST/ED)
  * `a_kernel_without_ikconfig_is_an_error_not_an_empty_config`
* `buildmode`:
  * `a_hyperv_build_spec_carries_kernel_config_and_release_bump_after_embed`
  * `a_non_hyperv_spec_does_not`
  * `acvp_and_kat_reject_hyperv`
  * `hyperv_flavours_default_to_linux_only`
* `buildexec`:
  * `release_bump_is_relative_to_an_already_bumped_release` (applies after the canister-equivalent patch's bump)
  * `release_bump_is_idempotent_on_rerun`
  * `kernel_config_path_resolves_6_1_single_source_names_by_subrelease`
  * `a_missing_config_file_is_a_typed_error`
* `matrix`:
  * `a_plus_joined_canister_column_splits_into_canister_and_variants`
  * `fips0_aarch64_is_runnable_on_x86_64_when_an_arm64_builder_is_registered` (injected probe)
  * `iso_key_distinguishes_hyperv_isos`
* `oracle`:
  * `media_kernel_config_passes_for_all_seven_y` / `fails_on_the_stock_iso_negative_control` (fixture rpm cpio with a /boot/config)
  * `vmlinuz_mismatch_between_installer_and_rpm_fails`
* `remaster` (unit-testable pieces):
  * `xorriso_argv_replaces_every_subpackage_and_keeps_boot_image_replay`
  * `initrd_module_dir_swap_rejects_a_missing_old_uname`
  * `disk_guard_stops_below_threshold`
* Integration (`tests/remaster.rs`, ignored by default, needs binfmt + ISO): run the Initrd, Repo and Iso stages on the published PoC RPMs
  and assert `media.hyperv.*`.
