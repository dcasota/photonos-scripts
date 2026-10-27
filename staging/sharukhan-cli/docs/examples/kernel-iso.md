# Example: a kernel.org kernel to a tested ISO

[← sharukhan overview](../../README.md)

**Who this is for:** Someone who wants a full ISO with a kernel.org kernel, the latest installer and the equivalent canister, from scratch, with the script that does it.

**Contents**

- [Real-world example: a full ISO with kernel 7.3, the latest installer and the equivalent canister](#real-world-example-a-full-iso-with-kernel-73-the-latest-installer-and-the-equivalent-canister)
- [Step 1: from scratch - a host that can run sharukhan](#step-1-from-scratch---a-host-that-can-run-sharukhan)
- [The directory layout](#the-directory-layout)
- [Why a kernel branch, and how it is named](#why-a-kernel-branch-and-how-it-is-named)
- [The script and its variables](#the-script-and-its-variables)
- [The 2026-10 run: result](#the-2026-10-run-result)
- [Culprits and how each was solved](#culprits-and-how-each-was-solved)
- [Timings](#timings)

## Real-world example: a full ISO with kernel 7.3, the latest installer and the equivalent canister

This chapter takes one request from nothing to a tested ISO: *one full ISO
with Linux 7.3, the latest photon-os-installer variant, the canister built from
that kernel (`--canister equivalent`), and every fork PR applied*. The script
[`examples/kernel-iso.sh`](../../examples/kernel-iso.sh) performs it; this chapter
explains how to get to the point where the script can run, what the script
does line by line, and what went wrong on the first real run (2026-10-25 to
2026-10-27) and how each problem was solved.

Nothing in the script names a host path, a branch or a matrix row. The kernel,
installer variant, canister mode and ISO type are variables; every path comes
from sharukhan's own settings (`sharukhan settings`); the kernel branch, the
derived wrapper and the RPM version come from `sharukhan wrapper kernel`; the
rows to boot come from the permutation matrix. Values from the 2026-10 run
appear only as *example output*, marked as such.

## Step 1: from scratch - a host that can run sharukhan

**Host requirements**

| What | Why | Check |
|---|---|---|
| A Linux host with systemd, as root; on Windows a WSL2 distribution (the 2026-10 run: Photon OS 5.0 under WSL2) | the build and the services run there | `systemctl is-system-running` |
| VMware Workstation on the Windows side (`vmrun.exe`, `vmware-vdiskmanager.exe`) | every boot test installs a VM | `"$VMRUN" -T ws list` (sharukhan's `VMRUN`) |
| docker | the builder container runs Photon's build tools | `docker version` |
| git, gh logged in (`gh auth login`), Rust (`cargo`), python3, sqlite3, bsdtar | clones and PRs, building sharukhan, the script's checks | `gh auth status` |
| About 40 GB free on the disk of the work root for one kernel build, 4 GB for each VM in the VM store | measured: the 7.3 build used about 30 GB | `sharukhan status` |

**Get and build sharukhan**

```sh
git clone https://github.com/dcasota/photonos-scripts.git
cd photonos-scripts/staging/sharukhan-cli
cargo build --release
./target/release/sharukhan doctor          # what is still missing on this host
```

**Install the services and the settings.** `sharukhan service install` writes
the settings file `/etc/sharukhan/sharukhan.env` from the settings exported in
the invoking shell, the unit files, and the secret files; it installs the
binary to `/usr/local/libexec/sharukhan/sharukhan`. Export what differs from
the defaults first - at least where the work, the gate repository and the ISO
store live, and the guest password (it never goes into the settings file, only
into a root-only secret file):

```sh
export MC_WORK=<work root>/gate/work MC_BUILD_ROOT=<work root>/gate/build-root \
       MC_GATE_REPO=<work root>/gate/photon.git MC_VARIANT_PATCH_DIR=<work root>/gate/variant-patches \
       MC_ISO_STORE=<a folder for finished ISOs> MC_BUILDER=container MC_AUTHOR='Name <mail>'
read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD     # the root password of every test VM
nsenter --target 1 --mount -- ./target/release/sharukhan service install --guest-password-from-env
/usr/local/libexec/sharukhan/sharukhan service status     # every file "current"
/usr/local/libexec/sharukhan/sharukhan doctor             # every line ok
```

Add `--sync --escalation-key-from-env` only if the fork-sync automation should
run too; this example does not need it. On WSL2 run sharukhan in the host mount
namespace (`nsenter --target 1 --mount -- ...`): the builder's overlay mounts
must be visible to dockerd.

**Clone the gate repository.** The gate repository is a bare clone of the
Photon fork that the builds read their branches from; the release branch and
every PR branch the variants name must be in it:

```sh
git clone --bare "$MC_PHOTON_REMOTE" "$MC_GATE_REPO"      # see `sharukhan settings`
sharukhan variants                                       # every branch of variants.conf is an open PR
```

## The directory layout

What each directory under the work root holds, which setting places it and what is safe to delete: [Configuration: the directory layout](../configuration.md#the-directory-layout).

## Why a kernel branch, and how it is named

A kernel profile builds Photon's userland with a different kernel. The new
kernel's spec files, patch sets and FIPS canister series live on a branch of
the gate repository, the **kernel branch**, named by sharukhan from the release:
`sharukhan wrapper kernel <release>` prints it (`experimental/linux-7.3` for
7.3, `experimental/linux-7.3-rc4` for 7.3-rc4).

- It is **local to the gate repository** and never pushed: it carries a kernel
  port for testing, not a PR.
- It must **contain today's release branch** (`$MC_RELEASE`): a kernel build
  assembles each installer variant as `origin/<kernel branch>..origin/<PR>`, so
  every commit of the release that the kernel branch lacks would be carried
  into every PR's range. The 7.3-rc4 branch sat on a release from 2026-09-19,
  100 commits behind - one of the culprits below. `prepare_branch` refuses a
  branch that does not contain the release.
- The kernel goes into **the tree's kernel directory**, the one the release
  uses (`SPECS/<subrelease>/linux` on 5.0 since 2026-10, `SPECS/linux`
  before); sharukhan reads it from the tree, never assumes it.

## The script and its variables

```sh
nsenter --target 1 --mount -- env KERNEL=7.3 POI=latest CANISTER=equivalent ISO_TYPE=full \
    examples/kernel-iso.sh --dry-run          # every command it would run
nsenter --target 1 --mount -- env KERNEL=7.3 examples/kernel-iso.sh            # the whole example
nsenter --target 1 --mount -- env KERNEL=7.3 examples/kernel-iso.sh --step verify_media
nsenter --target 1 --mount -- env KERNEL=7.3 examples/kernel-iso.sh --from variant_patches
```

| Variable | Default | Meaning, and where the value comes from |
|---|---|---|
| `KERNEL` | none (required) | the kernel.org release: `7.3`, `7.3-rc4`, `7.2.5` ... |
| `POI` | `latest` | the installer variant; must be a `[variant <name>]` of `variants.conf` (`sharukhan variants`) |
| `CANISTER` | `equivalent` | `equivalent`: a canister built from this kernel (phase A) and linked into both flavours (phase B), **never CMVP validated**; `prebuilt`: a published canister, if one exists for the kernel |
| `ISO_TYPE` | `full` | `full` or `minimal` |
| `ROWS` | derived | the matrix rows to boot; derived from the matrix: the first `ISO_TYPE`/`POI` kickstart row on ext4 and the default network without STIG, and the first with STIG |
| `FROM_PROFILE` | none | `write_profile`: the existing profile a new one starts from (`profiles/kernel/<release>.json`) |
| `DISK_MIN_GB` | `40` | free space under `MC_WORK` the build needs (the 7.3 build used about 30 GB) |
| `WAIT` | `1` | `1`: wait for a detached build or boot test; `0`: start it and return |
| `ISO` | none | `verify_media`: verify this file instead of the cache's `photon.iso` (for an ISO moved or renamed in the store) |
| `SHARUKHAN` | `sharukhan` on `PATH`, else the installed `/usr/local/libexec/sharukhan/sharukhan` | the binary |
| `SHARUKHAN_CLI_DIR` | the `sharukhan-cli` directory the script is in | where the kernel profiles are |
| `SETTINGS_FILE` | `/etc/sharukhan/sharukhan.env` | the settings `sharukhan service install` wrote |
| `MC_*`, `SHARUKHAN_*` | from `sharukhan settings` | every path; see [the directory layout](../configuration.md#the-directory-layout) |

The steps, in order (`--list`): `preflight`, `settings`,
`verify_kernel_release`, `prepare_branch`, `write_profile`, `prove_patches`,
`variant_patches`, `build_iso`, `boot_test`, `verify_media`, `report`. Three of
them may stop for a person - `prepare_branch` (porting the kernel to the
branch), `write_profile` (reviewing a new profile) and `prove_patches` (the
`%prep` replay, and porting a rejected hunk): they print what to do and the
command that proves it was done, exit with status 10, and the script continues
with `--from <step>`.

## The 2026-10 run: result

*Example output; host-specific values as they were on that host.*

| | |
|---|---|
| ISO | `full-poilatest-equivalent__photon-5.0-cb2b916647.x86_64.iso` in the ISO store |
| Kernel on the media | `linux` / `linux-esx` `7.3.0-1.ph5` (guest `uname -r`: `7.3.0-1.ph5-esx`) |
| Installer | `photon-os-installer-2.9-1.ph5`, the same as the regular latest-variant ISO |
| Canister | `linux-fips-canister-7.3.0-1.ph5`, built in phase A, relinked into both flavours in phase B - **not CMVP validated** |
| PRs | every branch of `[variant latest]` and `[common]` except the kernel PR stack (see `variant_patches`) |
| Rows | k13 (full, latest, ext4): 44 checks, 0 fail; k15 (full, latest, STIG, `fips=1`): 46 checks, 0 fail, canister 7.3 based on `7.3.0-1.ph5` |

## Culprits and how each was solved

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | The kernel-profile tooling could not build against the release of 2026-10 | 5.0 keeps its kernel per subrelease (`SPECS/92/linux`); the base wrapper, the branch check, the profile and `spec_canister_pin` assumed `SPECS/linux` | the kernel directory is read from the tree everywhere; base wrapper v15 (`5088b218`) |
| 2 | "All PRs" would have dragged 100 upstream commits into every variant | the rc4 kernel branch sat on a release from 2026-09-19 | a kernel branch on today's release; `prepare_branch` refuses one that lacks it |
| 3 | rc4's `config.yaml` license-review hashes did not belong to its tarball | copied from the 6.12 entry | the 7.3 hashes computed from `linux-7.3.tar.xz` |
| 4 | `version: 7.3` in `config.yaml` read as the float `7.3` | YAML typing | quoted `'7.3'`, confirmed with `yaml.safe_load` in the builder |
| 5 | `1000-FIPS-canister-creation-7.3.patch`: 1 of 23 hunks failed at `--fuzz=0` | 7.3 moved `assoclen -= orig_len_this_step;` in `gcm_process_assoc()` | the same change on 7.3's context, proven by the `%prep` replay (kernel branch commit `cb2b916647`) |
| 6 | Phase A stopped after 1 h 48 min: `failed to build contain_unpriv`, `linux/errno.h: No such file or directory` | build.py compiles `contain_unpriv` in a fresh build root; the builder image had gcc and glibc-devel but no `linux-api-headers` | `linux-api-headers` in the image, and every new image must compile a C program that includes `<errno.h>` (`fe532e0a`) |
| 7 | `could not obtain rpcbind-1.3.1.tar.bz2 / pgbouncer-1.26.0.tar.gz from any source` | both upstreams are gone and not on Photon's mirror | a missing archive is restored from the local caches first, only when its sha512 is the declared one (`1204fe90`) |
| 8 | Phase B needed 6 `make` attempts: `linux` failed once, `linux-esx` three times, `kafka` once; attempt 6 passed | the one failure whose log survived: `cc1: internal compiler error: Bus error` on `fs/jbd2/recovery.o` (linux-esx); the kernel log showed no OOM kill, no SIGBUS record, no I/O error, only Hyper-V order-7 page-allocation warnings; the same sources built cleanly later - environmental, not reproduced | the retries carried the build; failed attempts' package logs are now kept under `<build-log dir>/failed-attempts/` (`a04b4a6d`) |
| 9 | `Debug symbols found in following rpms: subversion-1.14.5-2.ph5` (non-fatal) | open: the base wrapper's `pin_svn_nodebug` is the only difference to the regular subversion RPM; not proven | finding 124 (`wrapper-svn-nodebug-ships-debug-files`) |

## Timings

*Example output: the 2026-10 run, all times UTC.*

| Step | When | Took |
|---|---|---|
| Tooling port, kernel branch, profile, `%prep` proof | 2026-10-25 20:34 - 21:06 | 32 min |
| `variant_patches` | 21:06 | about 1 min |
| First build to the `contain_unpriv` stop (fetching 2 030 sources into the fresh root) | 21:07 - 22:55 | 1 h 48 min |
| Idle until the stop was picked up, then the builder fix and a new image | 22:55 - 04:11 | 5 h 16 min |
| Phase A (fresh toolchain bootstrap, then `linux` with the canister) | 2026-10-26 04:11 - 10:19 | 6 h 08 min |
| Phase B (6 `make` attempts: 147, 165, 209, 27, 267 and 125 min) | 10:20 - 2026-10-27 03:28 | 17 h 08 min |
| `boot_test` (k13, k15) | 2026-10-27 07:47 - 08:03 | 16 min |

---

[← sharukhan overview](../../README.md)
