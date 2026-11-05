# A systemd release: `--systemd`

[← sharukhan overview](../../README.md)

**Who this is for:** Someone who wants the matrix run with a systemd release other than the one Photon OS 5.0 packages.

## A systemd release: `--systemd`

Every permutation runs with the systemd the 5.0 tree packages (257.13 at subrelease 92).
`--systemd <release>` runs them with another release of
[systemd/systemd](https://github.com/systemd/systemd/releases), e.g. `262.2` (or `v262.2`). It is
optional, like `--kernel`; without it nothing changes. It applies to the mainline (subrelease 92
today) and not together with `--kernel`.

```sh
sharukhan systemd profile-new 262.2                  # verify, write the profile, start the port branch
#   ... finish the port on experimental/systemd-262.2 ...
sharukhan systemd check 262.2                        # the gate every --systemd build passes first
sharukhan variant-patches --systemd 262.2            # the variants on the port, systemd PRs left out
sharukhan build-iso --systemd 262.2 --iso-type minimal --allow-build
sharukhan run --systemd 262.2 --only k03             # the guest must run systemd 262.2
```

### The trust: a signed tag and a pinned tarball

`sharukhan systemd verify <release>` fetches the tag from systemd/systemd and the GitHub tarball, and
accepts the release only when the tag carries exactly one good signature by a reviewed signer
(`profiles/systemd/systemd-signers.json`), checked in a keyring private to the run, and the tarball's
content is byte-identical to `git archive` of the tagged commit. The profile
(`profiles/systemd/<release>.json`) pins the tarball's sha512, the commit and the signer. Sources and
keys are fetched from `github.com`, `codeload.github.com` and `keys.openpgp.org` only.

### The port: a branch, and a report of what it needs

`profile-new` starts `experimental/systemd-<release>` in the gate repository from the release branch:
Version and Release set, one `%changelog` entry, and `config.yaml` pinned to the verified tarball. Then
it replays Photon's patches on the release's own source and checks the meson options the spec passes.
For 262.2 (2026-11-05) the report was:

```
  does not apply:   0001-enoX-uses-instance-number-for-vmware-hv.patch - port it (1 out of 1 hunk FAILED)
  applies:          0002-Fetch-dns-servers-from-environment.patch
  does not apply:   0003-systemd-do-not-use-ftrivial-auto-var-init-zero.patch - port it (1 out of 1 hunk FAILED)
  does not apply:   0004-Remove-unused-default-groups-rules-and-tmpfiles.patch - port it (1 out of 1 hunk FAILED)
  does not apply:   0005-default-conf-modifications.patch - port it (1 out of 3 hunks FAILED / 1 out of 1 hunk FAILED)
  meson option -Dlibidn: v262.2 does not declare it - drop or rename it
  meson option -Dlibiptc: v262.2 does not declare it - drop or rename it
  meson option -Drc-local: v262.2 does not declare it - drop or rename it
  meson option -Dsysvinit-path: v262.2 does not declare it - drop or rename it
8 item(s) for the port on experimental/systemd-262.2; ...
```

It exits 10 while work remains. The files lists and new units are proven by the build itself.

### The gate: `sharukhan systemd check`

A `--systemd` build is refused until the branch passes, and every problem is named:

- `config.yaml` pins the profile's tarball, sha512, url and commit;
- the tree is a mainline tree (its subrelease is the mainline);
- the spec is the profile's Version-Release, parses on x86_64 and aarch64, and `check_spec.py` passes;
- every patch applies in `%autosetup` order at fuzz 0 to the verified tarball (one the release already
  carries must be dropped);
- every meson option the spec passes is one the release declares.

A port branch behind the release branch is reported: rebase it to test today's tree.

### What a `--systemd` build is

It builds in its own root (`$MC_WORK/sbuild/<release>`), whose release tree is the port branch, with
its own variant patches and ISO cache (`s<release>`). PRs that change `SPECS/systemd` are left out of
its variant patches and named in the log (`left out - it changes N systemd file(s) (SPECS/systemd),
which the port owns`); every other PR is applied. The ISO's input record names the profile. Every row
run with `--systemd` checks `guest.systemd_version`: the installed systemd must be the profile's
Version-Release; without `--systemd` the installed systemd is recorded.

### Settings

| Setting | Default | Meaning |
|---|---|---|
| `SHARUKHAN_SYSTEMD_PROFILES` | the profiles built into sharukhan | a directory with `<release>.json` and `systemd-signers.json` under review |
| `SHARUKHAN_SYSTEMD_CACHE` | `$XDG_CACHE_HOME/sharukhan/systemd`, else `~/.cache/sharukhan/systemd` | downloaded tarballs and the tag repository |

The decisions are [ADR-0013](../../specs/adr/0013-systemd-version.md), the requirements
[FRD-003](../../specs/features/systemd-version.md).
