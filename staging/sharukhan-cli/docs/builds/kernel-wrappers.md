# Kernel wrappers

[← sharukhan overview](../../README.md)

**Who this is for:** Someone deriving, checking or verifying a build wrapper for a kernel.org kernel.

## Kernel wrappers: `sharukhan wrapper`

`staging/runPh7-2-7.sh` builds Photon OS 5.0 with Linux 7.2.7. A wrapper for any other
kernel.org release is **derived** from it, not written by hand:

```sh
sharukhan wrapper kernel mainline                 # what kernel.org has; the identity it derives
sharukhan wrapper profile-new --kernel 7.3-rc5 --from 7.3-rc4   # verified pin, review list
sharukhan wrapper derive --profile 7.3-rc5 --repo /root/5.0     # writes staging/runPh7-3-RC5.sh
sharukhan wrapper check --repo /root/5.0          # every committed wrapper is up to date
sharukhan wrapper verify 7.3-rc4 --profile 7.3-rc4              # re-prove a pin
```

Run from `staging/sharukhan-cli` (profiles default to `./profiles/kernel`), or set
`SHARUKHAN_WRAPPER_PROFILES`, `SHARUKHAN_WRAPPERS`, `SHARUKHAN_PHOTON_REPO` and
`SHARUKHAN_KERNEL_CACHE`.

How it is built, in short (the full contract is [FRD-001](../../specs/features/kernel-wrapper.md)):

- **The base marks its own kernel-specific regions.** `runPh7-2-7.sh` declares
  `# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12` and ten
  `# @sharukhan-slot <name> begin|end` pairs. Each slot is re-rendered for the target; the rest is
  carried over and renamed by identity. The markers are comments, so the base still runs as is.
- **Everything else is computed from the release string**: tag, ISO marker, script and branch
  names, tarball and signature URLs, `Source0`, RPM `Version`/`Release` (an RC is `X.Y.0` /
  `0.rcN.1`), `%define kernel_src`, `EXTRAVERSION` handling.
- **What cannot be computed lives in a reviewed profile** (`profiles/kernel/<release>.json`): the
  patch enablers, dropped kernel parameters, installer patches, pre-build extras, the derived
  wrapper's version, and the pin with how it was verified.
- **Nothing is trusted on arrival.** A pin is established by `verify`: cdn tarballs by their
  `.tar.sign`, git.kernel.org snapshots (release candidates) by the signed tag plus byte-identity
  with `git archive` of the tagged commit. Only the fingerprints in
  `profiles/kernel/kernel-org-signers.json` (from kernel.org/signature.html) are accepted, in a
  keyring private to the run. `derive` also reads `EXPERIMENTAL-<release>.md` in the kernel spec
  directory of `origin/experimental/linux-<release>` and requires it to agree with the profile.
- **The kernel spec directory is read from the tree, never assumed.** 5.0 keeps its kernel per
  subrelease (`SPECS/90/linux`, `SPECS/91/linux`, `SPECS/92/linux`); the directory is the one
  whose `linux.spec` `build_if` accepts the tree's `photon-subrelease`. The pin script works on
  `$KDIR`: a build exports the directory sharukhan resolved (`specresolve::kernel_dir`), a run by
  hand resolves it with the same rule (`pin_kernel_dir`), and a test keeps the two in agreement.
- **Every derivation proves itself** before it writes: no target name already in the base, no base
  name in a rendered slot, every rename applied, no base name left anywhere, `sh -n` clean, every
  Python heredoc parses. The write is atomic; `--check` compares byte for byte instead.
- **A base bump stops derivation** until each profile is reviewed against it
  (`base.wrapper_version`), because a fix in the base flows into every derived wrapper.

`runPh7-3-RC4.sh` is the first derived wrapper; the golden test keeps it byte-identical to what the
committed base and `profiles/kernel/7.3-rc4.json` derive (wrapper v11, base v15).

### A FIPS canister series for a profile kernel

A profile may carry a `fips` section: where the release branch keeps a ported
canister series (`SPECS/linux/fips-<series>/manifest.json`) and its LKCM series.
The manifest - written by the port's export and proven by a `%prep` replay -
says which file every `PatchN`/`SourceN` line names, which 6.12 patches the
kernel does not need, the `%autopatch` ranges and the per-flavour additions.

The derived wrapper renders a manifest-driven spec editor
(`src/wrapper/assets/fips_spec_edit.py`, compiled in) into the `kernel-fips`
slot and runs it **only for a canister build** (`CANISTER_MODE` `build`,
`equivalent-a`, `equivalent-b`); `none` leaves the kernel FIPS-off. The editor:

- rewrites the Patch/Source lines, drops what the kernel does not need and
  restores the commented-out `%autopatch` ranges in place;
- makes both canister pins overridable in the two-macro shape Photon's
  SpecParser can read (`canister_equivalent` + `fips_canister_override`,
  `canister_stamp_real` + `fips_certified_override`), defaulting to the tree's
  own `linux` NEVR - there is no certified canister of the series to claim;
- moves `Name:` before the first canister conditional (see below);
- after the config merge, enables `CRYPTO_SELFTESTS`, re-applies Photon's
  `CRYPTO_FIPS*`/`CRYPTO_JITTERENTROPY*` settings and fails `%prep` if any does
  not hold.

`derive`'s branch check also reads the manifest and requires every file it
names on the branch exactly once under `SPECS/linux` (rpm sees it flattened).

---

[← sharukhan overview](../../README.md)
