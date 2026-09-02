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
