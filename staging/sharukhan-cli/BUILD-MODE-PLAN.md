# Build mode: one cascade, five scripts retired

## Why

`sharukhan build-iso` shells out to `runPh5_normal.sh`. Four sibling scripts
exist for the other release/subrelease combinations, and they have drifted:

| fixup | Ph4 | Ph5n | Ph5p90 | Ph5p91 | Ph6 |
|---|---|---|---|---|---|
| openjdk / python3 / sssd | y | y | y | y | y |
| libcap stale-RPM | - | y | y | y | y |
| rpm 6.x removal | - | y | y | y | - |
| blank-line spec fix | - | y | y | y | - |
| run-in-chroot fd 255 | - | y | y | - | - |
| createrepo_c repair | - | y | - | - | y |

Every one of those is a condition of the **host or the tree**, not of the
release. `run-in-chroot` closing fd 255 breaks a 4.0 build exactly as it breaks
a 5.0 one. So the table is not a set of decisions, it is a record of which
script someone happened to be editing that day. Five copies cannot be kept in
step by discipline.

The axes that genuinely vary are two:

    release     4.0 | 5.0 | 6.0
    subrelease  mainline | 90 | 91

`runPh5_pinned90` and `runPh5_pinned91` already differ only in `PINNED_SUB`.

## The second reason: injections have nowhere to live

`--canister equivalent` needs two changes that are not in the release tree:

- the kernel spec change (`fix/canister-equivalent-mode`) - already carried
  reproducibly by the variant patch, verified against a pristine tree
- the package-builder change (`fix/sans-snapshot-...`) - carried by **nothing**

The variant-patch mechanism diffs `origin/5.0..branch` and applies to `SPECS`.
A branch off `common` is not in that range and touches files the release tree
does not have. So the tooling fix reaches a build only because the operator's
`/root/common` happens to sit on the right branch, and `sync_repo`'s
`git merge --autostash` happens to preserve it. On a fresh machine
`runPh5_normal.sh` clones `-b common`, which does not contain it, and phase B
fails after two hours with `package not found or not installed`.

A build mode with an explicit, ordered injection stage gives that fix a home,
and gives every future one a home too.

## Architecture

    BuildSpec { release, subrelease, img, canister, injections, ... }
        |
        v
    Cascade: an ordered list of Phases, each
        - named after the failure it prevents
        - with a precondition it evaluates against THIS host and tree
        - skipped, with a reason, when the precondition does not hold
        - reported before it runs (`--dry-run` prints the cascade)

A phase never asks "which release is this". It asks "is the thing I fix present
here". That is what stops the table above from reappearing.

### Stages, in order

1. **Resolve** - args and env to a `BuildSpec`; validate img type and canister
   mode; `equivalent-a|b` require `MC_CANISTER_NEVR`.
2. **Sync** - clone if absent, unshallow, fetch, `merge --autostash` for the
   common and release trees.
3. **Reset** - release `SPECS` to pristine. Scoped, never a blanket clean.
4. **Inject** - the ordered cascade of tree modifications:
   - `TreePatch{Release}` - the variant patch (carries the canister spec change)
   - `TreePatch{Common}` - **new**: package-builder patches, where the
     sans-snapshot fix belongs
   - `Subrelease` - pin `photon-subrelease` (the pinned90/91 behaviour)
   - `PkgBuildOptions` - canister macros
   - `SpecFixup(..)` - the six workarounds, each with its own precondition
5. **Preflight** - docker image has `file`; createrepo_c works; disk space.
6. **Purge** - stale RPMs (rpm 6.x, libcap, release-shadowing, corrupted),
   sandboxes, SRPMs, logs.
7. **Make** - the retry loop.
8. **Post** - canister phase-A artifact assertion, ISO discovery, sha256
   dedupe, delivery.

### Injection is data, not code

    Injection::TreePatch { tree: Tree::Common, patch: "common-fixes.patch" }

so adding the next tooling fix is a line in a manifest, not an edit to a shell
script that has four siblings.

## Status (2026-09-03)

P1, P2 and P4 are done; the cascade runs natively and every phase of
`runPh5_normal.sh` is ported. P3 (parity) is partially done - see below.

    runPh4.sh            sharukhan build --release 4.0
    runPh5_normal.sh     sharukhan build
    runPh5_pinned90.sh   sharukhan build --subrelease 90
    runPh5_pinned91.sh   sharukhan build --subrelease 91
    runPh6.sh            sharukhan build --release 6.0

`--dry-run` prints all 17 stages and touches nothing.

**Test-only changes are compiled in.** `canister_equivalent` and the
sans-snapshot package-builder fix have no destination in vmware/photon -
upstream has no reason to carry a switch whose only consumer is this harness -
so they live in `src/embedded/` and are applied by the cascade on top of the
variant patch. `VARIANTS` carries only upstream-bound PR branches. A fresh
clone of photonos-scripts can build an equivalent-canister ISO with no other
repository on any particular branch.

**The canister decision is three-way**, asked in this order:

| published at this kernel level | link it, stays CMVP validated |
| not published, already built locally | link that, no phase A |
| neither | build it (phase A), then relink (phase B) |

Only the third costs the extra build; the middle case was missing and cost
~90 minutes rebuilding an artifact already on disk.

### What the parity run established

Run for real against throwaway worktrees of pristine `origin/5.0` and
`origin/common`, stopping in `sources`:

- SPECS reset, variant patch applied, both embedded patches applied
- pkg-build-options written for `equivalent-b`
- 4 openjdk specs fixed, python3 fixed, run-in-chroot fixed
- sssd and python3-setuptools correctly SKIPPED with reasons
- resulting tree: 3 `canister_equivalent` hits per spec, `Release: 14`,
  `REPO_LOCAL` present - identical to what the old VARIANTS path produced

**Still not proven: the cascade has never produced an ISO.** `build-iso`
therefore still calls the script. That is the remaining gate.

### The first real build, and what it proved

`sharukhan build --canister prebuilt` ran the full cascade against the live
trees and FAILED in make:

    error: Failed build dependencies:
      linux-fips-canister = 6.12.60-18.2.ph5 is needed by linux-6.12.103-13.ph5

Not a port defect. The shadowing purge removed `linux-6.12.103-14` - built
earlier by the equivalent path, and at Release 14 it genuinely shadows a
prebuilt spec at 13 - which forced a kernel rebuild at -13, which needs a
canister pin published NOWHERE (only `6.12.60-18` exists). The bash applies
the same rule to the same inputs and fails identically.

What it establishes, and it is worth stating plainly:

**On this host a `prebuilt` build succeeds only while the kernel stays cached.
Anything that forces a kernel rebuild hits the unpublished pin.** That is what
the equivalent mode is for, and why `plan_with_local` matters: with the local
canister present the same stage builds through phase B alone.

It also means a stage cannot serve both modes at once - each mode's purge
removes the other's kernel, because their spec Releases differ by the embedded
patch. Building prebuilt after equivalent costs a kernel rebuild that cannot
succeed.

### Phase A, verified (2026-09-03)

Phase A completed in 140m09s and produced
`linux-fips-canister-6.12.107-4.ph5.x86_64.rpm`. Not trusted on the build's
say-so - unpacked and checked:

    payload   /usr/lib/fips-canister/fips-canister-6.12.107-4.ph5.tar.bz2
    contents  crypto/fips_canister.o, crypto/fips_canister-kallsyms
    .o        ELF 64-bit LSB relocatable, x86-64, 3786368 bytes, not stripped
    symbols   2254, of which 10 name fips
    kallsyms  __canister_stext/_etext/_sinittext/_einittext/_sexittext

The artifact is copied to `photon-mc/canister-vault/` before phase B runs,
because phase B's first act is a purge of its siblings and 140 minutes is too
long to re-earn on a bad glob.

### Bugs the verification found that review did not

- `sync` tested `.git` with `is_dir()`. A linked worktree has `.git` as a
  FILE, so it reported "not a repository" and tried to clone over a populated
  directory.
- The rpm-6.x purge matched `-6.` anywhere, which also hits
  `rpm-4.18.0-6.ph5` - deleting the rpm 4.x the bootstrap requires.
- `pkg_build_options` computed the macros, logged them, and NEVER WROTE THE
  FILE. Every canister mode would have reported correct macros while build.py
  saw none. It also skipped entirely on `prebuilt`, where the script writes an
  EMPTY macro list - so a prebuilt build following an equivalent one would
  silently inherit `canister_equivalent 1`.
- The cascade's purge never removed phase A's kernels. `purged_before_phase_b`
  had unit tests and passed them all - while the only caller that matters,
  the cascade, did not call it. Phase A builds `linux` with `canister_build 1`
  (a kernel that CREATES the canister); phase B builds the same NEVR with
  `canister_usage 1`. Same name, same version, opposite meaning. Phase B would
  have found phase A's eight RPMs in the stage, skipped the rebuild, and
  shipped a kernel that never linked against the canister - passing every
  build-time check and failing only at runtime attestation. The test now
  exercises the phase rather than the predicate. Confirmed against the build
  system rather than argued: `PackageManager._readAlreadyAvailablePackages`
  marks a package built only if EVERY subpackage RPM is present, so phase A's
  complete set of eight was exactly the condition that triggers the skip.
  (It also explains why the leftover `bpftool-6.12.107-4` is harmless - "all",
  not "any", so one absent sibling is enough to force the rebuild.)
- The config.yaml parser was wrong three ways (wrong keys, values continued on
  the next line, nested lists splitting an entry). None was visible from
  counts: 1968 entries both sides while the contents differed. It is now
  byte-identical to python+pyyaml over 1968 entries in 1745 files.

## Plan

**P1 - skeleton.** `buildmode.rs`: `BuildSpec`, `Tree`, `Injection`, `Phase`,
`Cascade`, `--dry-run` printing the resolved cascade with per-phase
applicability. No side effects. Tests for resolution and ordering.

**P2 - injections.** Implement stage 4 natively, including the common-tree
patch. Generation of `common-fixes.patch` extends `variant-patches`
(`origin/common..fix/sans-snapshot-...`), verified to apply to a pristine
common. **Reset is scoped to the files the patch touches** - a blanket reset
would destroy `build-config.json` and `run-in-chroot.sh`, which are ambient
config, not artifacts.

**P3 - parity.** Run the bash and the cascade over the same spec, diff the
resulting tree and the emitted `pkg-build-options`. Parity is the gate for
switching, not code review.

**P4 - the rest.** Port sync, preflight, purge, make, post. Each phase keeps
the comment naming the scar it came from; that prose is the reason the scripts
are 871 lines and is the most valuable thing in them.

**P5 - switch.** `build-iso` uses the cascade; `--legacy-script` keeps the bash
reachable for one release cycle. Retire the five scripts once matrix rows have
passed on the cascade for each release.

## What this does not do

It does not reimplement `build.py` or `make`. The Photon build system is the
system under test; the cascade prepares a tree and invokes it, exactly as the
scripts do.
