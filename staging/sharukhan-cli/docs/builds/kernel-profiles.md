# Kernel-profile builds and runs

[← sharukhan overview](../../README.md)

**Who this is for:** Someone building or testing an ISO with a kernel profile (`--kernel`).

## Kernel-profile builds and runs: `--kernel`

```sh
sharukhan variant-patches --kernel 7.3-rc4        # variants on experimental/linux-7.3-rc4
sharukhan build-iso --kernel 7.3-rc4 --iso-type full --poi latest --canister equivalent --allow-build
sharukhan run --kernel 7.3-rc4 --only k13,k14,k15,k16
sharukhan verify --kernel 7.3-rc4 --id k15
```

- **Own trees.** A kernel build runs in `$MC_WORK/kbuild/<release>` with its
  own ISO cache (`$MC_ISO_CACHE/k<release>`) and variant patches, and never
  touches `/root/5.0`, `/root/common` or `/root/experimental/*`. The release
  branch is verified before anything is purged (tarball manifest, patch files,
  FIPS manifest).
- **The cascade, in every mode.** The derived wrapper's pin script is one
  injection (`inject:kernel-pins[<release>]`), sourced exactly as the wrapper
  sources it; the 6.12 canister-equivalent patch is left out (the profile brings
  its own series); the canister NEVR comes from the profile.
- **Photon's spec checker is honoured, not skipped.** The pins leave the 5.0
  kernel's own patches unreferenced; `build.py` checks modified specs whenever
  `make` has no TTY, which the wrapper's own runs never met. After the pins the
  checker runs per kernel spec and over both, exactly what it lists is pruned
  from the working tree (a `PatchN` only from the spec whose own run lists it,
  a `SourceN` only when unreferenced), and it must then pass.
- **Kernel variants.** PR branches that touch a kernel spec directory
  (`SPECS/linux` or `SPECS/<n>/linux`) are left out (the profile owns the
  kernel) - a PR stacked on such a branch too, because its range carries the
  parent's kernel files; a conflicting commit is skipped only when the kernel
  branch already carries it (same subject, identical non-spec files).
- **Runs.** Under `--kernel` every row takes the canister axis `equivalent`,
  `verify` expects the profile's NEVR, records `meta.kernel`, and
  `guest.kernel_release` requires `uname -r` to be that kernel; the media gate
  adds the installer Release bumps the profile's pins make.

### Linux 7.3-rc4 (2026-09-29)

`photon-5.0-899f55a42.x86_64.iso` - full, photon-os-installer 2.9-4, canister
equivalent, `linux`/`linux-esx` 7.3.0-0.rc4.1 relinked in phase B against
`linux-fips-canister-7.3.0-0.rc4.1`. `run --kernel 7.3-rc4` over k13-k16: 0
failing checks; every guest runs `7.3.0-0.rc4.1.ph5-esx`; the STIG rows k15/k16
boot with `fips=1`, "FIPS canister verification passed", canister version 7.3
based on 7.3.0-0.rc4.1.ph5. **Not CMVP validated** - no canister of the 7.3
series is published; the port's per-patch decisions are in
`SPECS/linux/fips-7.3/README.md` on the release branch.

---

[← sharukhan overview](../../README.md)
