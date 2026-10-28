# Build mode

[← sharukhan overview](../../README.md)

**Who this is for:** Someone building ISOs with sharukhan, or changing how it builds.

## Build mode: sharukhan builds the ISO itself

`sharukhan build` runs the whole build cascade natively. It replaces five shell
scripts that were the same build with different accretions:

| was | now |
|---|---|
| `runPh4.sh` | `sharukhan build --release 4.0` |
| `runPh5_normal.sh` | `sharukhan build` |
| `runPh5_pinned90.sh` | `sharukhan build --subrelease 90` |
| `runPh5_pinned91.sh` | `sharukhan build --subrelease 91` |
| `runPh6.sh` | `sharukhan build --release 6.0` |

Their fixups had drifted - `run-in-chroot`'s fd-255 fix was in two of the five,
`createrepo_c` repair in two, `rpm 6.x` removal in three - and none of that was
a decision about the release: fd 255 breaks a 4.0 build exactly as it breaks a
5.0 one. So a phase here never asks *which release is this*, it asks *is the
thing I fix present in this tree*, and says so when it is not:

```
$ sharukhan build --dry-run
   1. resolve          9. inject:fixup[release]:openjdk-wsl2-build-flag
   2. sync            10. inject:fixup[release]:python3-pgo-test-generators
   3. reset-specs     11. inject:fixup[release]:sssd-serial-make-install
   4. inject:patch[release]:poi-2.8.patch
   5. inject:embedded[release]:canister-equivalent
   6. inject:embedded[common]:sans-snapshot-local-canister
   7. inject:pkg-build-options[equivalent-b]      13. sources
   8. inject:fixup[release]:spec-blank-lines      14. preflight
  12. inject:fixup[common]:run-in-chroot-fd-255   15. purge / 16. make / 17. post

  [skip] sssd-serial-make-install: already correct in this tree
```

`--dry-run` touches nothing. The scripts had no equivalent: the only way to
learn their order was to run one for hours.

### Why one cascade

Five scripts had drifted because every fixup is a condition of the host or the
tree, not of the release: `run-in-chroot` closing fd 255 breaks a 4.0 build
exactly as it breaks a 5.0 one, so which script carried a fixup recorded who
had edited what, not a decision. The axes that really vary are two - release
(4.0, 5.0, 6.0) and subrelease (mainline, 90, 91) - and one cascade covers
them: each phase is named after the failure it prevents, has a precondition it
evaluates against this host and tree, and is skipped, with the reason, when the
precondition does not hold. A phase never asks "which release is this".

The second reason was the injections. `--canister equivalent` needs a
package-builder change on `common`, which the variant patches (`origin/5.0..branch`
applied to `SPECS`) can never carry; it reached a build only because an
operator's checkout happened to sit on the right branch. An explicit, ordered
injection stage gives such a change a home, as data rather than a script edit.

The plan this came from, with its September 2026 status notes, is archived as
[specs/archive/build-mode-plan-2026-09.md](../../specs/archive/build-mode-plan-2026-09.md).

### Two trees, and why that matters

Photon keeps per-release SPECS on `5.0`/`4.0`/`6.0` and shared build tooling on
`common`, and those branch lines never meet - `common` has no `SPECS/`, the
release branches have no `support/package-builder/`. The variant-patch
mechanism diffs `origin/<release>..branch` and applies to `SPECS`, so it can
**never** carry a change to the package builder. That is why the cascade
distinguishes `Tree::Release` from `Tree::Common` and can patch both.

### The common tree must hold only the build's own edits

Every Photon build on the host shares the common tree, and the driver restores
only the files it patches there. So `build`, `build-iso` and a `run` that would
build all refuse while that tree carries an edit the harness did not make, and
name each file with its modification time:

```
sharukhan: /root/common carries edits the build did not make, and every ISO built now would carry them too:
   M common/data/packages_appliance.json  (modified 2026-09-24 14:03:45)
```

On 2026-09-26 such an edit - an installer initrd list without stig-hardening -
went into every gate ISO, and every STIG row stalled in the installer. Stash
the edits in that checkout, or name them in `MC_COMMON_EDITS_ALLOWED` if they
are meant to ship - or give the build its own trees: with `MC_BUILD_ROOT` and
`PHOTON_TREE` pointing at an empty directory, `resolve` clones `common` and the
release branch from `MC_PHOTON_REMOTE` before it records the build inputs.

### Test-only changes are compiled in

`canister_equivalent` and the sans-snapshot package-builder fix have no
destination in vmware/photon - upstream has no reason to carry a switch whose
only consumer is this harness - so they live in `src/embedded/`, are compiled
into the binary with `include_str!`, and are applied **on top of** the variant
patch. `VARIANTS` therefore carries only work genuinely bound upstream, and
nothing test-only can leak into a PR.

The practical effect: a fresh clone of this repository can build an
equivalent-canister ISO with no other repository checked out at any particular
revision.

### The canister question, in the order it is asked

| state | plan | validated? |
|---|---|---|
| Broadcom publishes one at this kernel level | link it | **yes**, CMVP |
| not published, but already built locally | link that, no phase A | no |
| neither | build it (phase A), then relink both flavours (phase B) | no |

Only the third costs the extra ~90 minutes. `sharukhan canister` reports the
same decision the build will take - it asks the same question, so the two
cannot disagree.

Two further answers are possible. If the published repository cannot be reached
the answer is `unknown`, not `equivalent`: "build one locally" and "we could not
look" are different claims. On aarch64 it is `absent` by design, because both
kernel specs set `fips 0` there. The published lookup reads the repository URL
from `SPECS/photon-repos/photon-updates.repo`.

### One build, not two

`build-iso` resolves a matrix tuple to an ISO; `build` runs the cascade
directly. They used to be two implementations of the same build, and they
drifted - the visible half being the phase-B purge, which the cascade taught
about per-flavour NEVRs while the legacy path kept a rule keyed only on the
canister's. Anything through `build-iso`, or `run --allow-build`, could still
ship a `linux-esx` that never linked the canister, on the flavour these rows
boot.

Sharing the predicate would not have fixed it:

- **Ordering.** The cascade purges AFTER the injections, against patched specs.
  At the equivalent point in the script path the tree is still pristine, where
  both flavours read `Release: 1`, so a per-flavour purge there matches nothing.
- **The embedded patch.** `fix/canister-equivalent-mode` is test-only, compiled
  into `src/embedded/` and applied as an injection, so only the cascade applies
  it - while `resolve` called `equivalent_kernel_nevr`, which *reads* it, to
  pick the NEVR. The legacy path expected `linux` at Release 4, would have
  built Release 3, and purged on a NEVR its own build could not produce.

So `equivalent` runs the cascade. `prebuilt` still runs `runPh5_normal.sh`: it
applies no embedded patch and needs no inter-phase purge, so it has nothing to
drift on. The delete rule lives once in `build::doomed_before_phase_b`, and the
spec assembly once in `buildmode::spec_for`.

### The embedded patch pins Release numbers, and 5.0 moves

`src/embedded/canister-equivalent.patch` bumps the kernel Release on top of the
variant patch, so it carries the pre-bump number as diff context. Every time
5.0 bumps a kernel Release, that context stops matching and the patch fails to
apply — the build dies at the inject stage.

This is not rare: in five days in September 5.0 took `linux` from Release 1 to
4 to 8, and the patch needed retargeting three times. As of 2026-09-29
(6.12.111, after 5.0 took both kernels to Release 2 for the aarch64 RELR
config) the chain is:

```
                  linux   linux-esx
pristine 5.0        2         2
variant patch       3         3      PR#24/#29 share one entry, #36 keeps it in its includes
embedded patch      4         4      +1 each
```

**Changelog dates do not make it stale.** A sync re-dates the kernel stack's own
changelog entry on every rebase, and that header is context of the patch. Before
each apply, `caneq::align_changelog_context` re-dates such context headers to the
ones the target tree carries for the same author and version-release, and
`--check` ignores those dates. A moved Release or a different entry still fails
to apply, and needs a regeneration.

**Regenerate it, never hand-edit it.** `sharukhan canister-equivalent --out
src/embedded/canister-equivalent.patch` (`--repo <photon clone>`, default
`$PHOTON_TREE`, so it need not touch a tree another build is using; `--check`
compares a regeneration with the patch this binary embeds)
applies the variant patch to a pristine worktree, makes the embedded edits,
derives the kernel version, runs the spec checker over the result and writes the
patch; `--check` only reports whether the committed patch is current. The patch
is compiled in, so rebuild the binary afterwards. `sharukhan doctor` reports
`canister-equivalent applies` on every run, so a moved kernel is caught before a
build rather than seconds into one. Hand-editing hunk offsets is how an earlier
attempt produced an orphan changelog entry and a descending-order violation that
`rpmspec` rejected.

### `--compose-only`

Rebuilding an image must not cost a kernel rebuild. The kernels in the stage
are already linked against the canister and verified, and `purge` would delete
them for the sake of a recompose. `--compose-only` keeps them - but the skip is
earned, not asserted: every `linux*` RPM must be shown to POSTDATE the canister
(phase A builds the canister as a subpackage of the kernel, so a phase-A kernel
shares its BUILDTIME), and the build is refused on any path that cannot be
proven.

It is not a uniform saving. A minimal recompose took **9m38s** against ~2h45m;
a full one took **154m**, because the full package set is 264 packages against
the minimal's 141 and most of the difference had never been built. What is
saved is the kernel rebuild, not the package set.

### The installer that composes the media is the variant's: `composer`

`make image` does not compose an ISO with the photon-os-installer RPM the build
just produced. `poi.py` runs a docker image (`photon-build-param.poi-image`),
and the installer inside that image decides what goes on the media; the RPM
under test only lands in the ISO's initrd. On this host `photon/installer:latest`
held photon-os-installer **2.4** on a Python 3.14 base, so every ISO had been
composed by 2.4. On 2026-09-29, in a fresh build root, both minimal gate groups
failed all ten attempts on `Error(1011) : No matching packages` for `ntp`. 2.4's
STIG set still names it; the variants' 0006 patch removes it. Earlier minimal
runs had passed only because a shared stage still held an `ntp` RPM from a full
build.

Upstream's Dockerfile is no way out: it runs `tdnf update` against the live
repos, and that day photon-updates had `librepo-1.14.5-7` requiring
`libxml2.so.2` next to a `libxml2-2.15.4` that no longer provides it. So
`build-iso` (and `sharukhan composer --poi <v>` on its own) builds the composer
offline, with `--network=none`:

1. the variant's installer spec directory, taken from `HEAD` with the variant
   patch applied,
2. every archive its `config.yaml` declares, each checked against its sha512,
3. the spec's own `%prep` (`rpmbuild -bp`),
4. the two commands `%py3_build`/`%py3_install` run, executed by the base
   image's own Python, on top of the base image pinned by ID
   (`MC_POI_BASE_IMAGE`, default `photon/installer:latest`), with the base's
   installer RPM removed.

Before the image is used, sharukhan proves it:

- every file of `photon_installer` in the image is byte-identical to the
  prepped tree, with nothing missing or left over;
- the rpmdb no longer lists the replaced installer;
- both console scripts resolve.

The tag, `sharukhan/photon-os-installer:<version>-<hash>`, is a content hash
over the base ID and the prepped tree, so an unchanged variant reuses its image.
The shared `photon/installer:latest` is never retagged. The legacy driver
receives the tag as `MC_POI_IMAGE` and writes and re-reads `poi-image` itself.
The cascade does the same in `preflight`, building the composer from the
already-injected tree when no tag was passed.

### How a medium boots: `iso-boot`

photon-os-installer 2.9 (upstream `b7c9039`) replaced syslinux. BIOS boots a
GRUB El Torito image, `/isolinux/eltorito.img`, which reads `/boot/grub2/grub.cfg`,
the same file UEFI GRUB reads. `isolinux.bin`, `isolinux.cfg` and `menu.cfg` are
gone. POI 2.8 media still boot `/isolinux/isolinux.bin`. The installer that
composes the medium decides which, so a tool that hardcodes one breaks on the
other: the HABv4 ISO creator stopped a 7.3-rc4 run with `Cannot find in ISO
image: -boot_image ... bin_path='/isolinux/isolinux.bin'`.

`sharukhan iso-boot --iso <path> [--json]` reads the layout from the El Torito
catalogue and reports:

- the catalogue, the BIOS image and the EFI image, each checked to be on the
  medium;
- the BIOS loader, identified from the image's own bytes: `ISOLINUX` for
  syslinux, and GRUB `cdboot.img`'s two messages for `grub-eltorito`;
- whether a hybrid MBR/GPT system area is present;
- the mkisofs boot options that reproduce the layout from an extracted tree,
  with the EFI load size left to xorriso, because a re-signed `efiboot.img`
  changes size.

The media oracle records the same layout (`media.boot_layout`) and fails a
catalogue that names a missing file (`media.boot_images`). `remaster` needs none
of this: it replays the input's boot catalogue (`-boot_image any replay`).

---

[← sharukhan overview](../../README.md)
