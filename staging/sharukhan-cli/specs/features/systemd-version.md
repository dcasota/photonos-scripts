# FRD-003 — A systemd release as a build parameter (`--systemd`)

Status: implemented (2026-11-05); the first port, 262.2, is started and not yet ready
Decisions: [ADR-0013](../adr/0013-systemd-version.md)
Code: `src/sdver.rs`, `src/build.rs` (`IsoRequest::systemd`, `make_systemd_variant_patches`,
`is_systemd_path`), `src/oracle.rs` (`systemd_version`), `src/wrapper/kernelorg.rs` (`Trust::parse`,
`check_url_in`, `fetch_in`), `build.rs`
Data: `profiles/systemd/<release>.json`, `profiles/systemd/systemd-signers.json`

## 1. Purpose

Every permutation of the matrix runs with the systemd that Photon OS 5.0 packages, 257.13 at
subrelease 92. `--systemd <release>` builds and tests the same permutations with another systemd
release, e.g. 262.2 ([v262.2](https://github.com/systemd/systemd/releases/tag/v262.2)). It is optional,
as `--kernel` is: without it nothing changes.

A systemd release cannot be dropped into Photon's spec: Photon carries its own patches, passes meson
options that releases rename or remove, and lists the files the build installs. So, as for a kernel,
the port of `SPECS/systemd` lives on a branch of its own, `experimental/systemd-<release>`, and the
tool's part is to verify the source, start the port, report what it still has to do, and refuse to
build until it is done.

## 2. Requirements

| ID | Requirement | Met by | Proven by |
|---|---|---|---|
| SV-1 | Accept a systemd/systemd release tag `<major>` or `<major>.<point>`, with or without `v`; refuse release candidates (Photon's RPM version comparison has no `~`), leading zeros, `.0`, whitespace and out-of-range components, with the reason. | `sdver::SystemdRelease::parse` | `sdver::tests::anything_outside_the_grammar_*` |
| SV-2 | Compute every name from the release: version, tag, tarball, its top directory, GitHub URL, branch, profile file, cache key. Nothing about a release is written in the code. | `SystemdRelease` | `sdver::tests::a_release_string_yields_every_name` |
| SV-3 | A reviewed profile per release pins the tarball's sha512, the tagged commit and the signer; every field is checked against the release it names and the reviewed signers. | `sdver::Profile::parse` | `sdver::tests::a_profile_round_trips_and_each_wrong_field_is_named` |
| SV-4 | Verify a release from scratch: the tag fetched from systemd/systemd over https only, signed by exactly one reviewed signer in a keyring private to the verification, and the tarball's content byte-identical to `git archive` of the tagged commit, with the commit in its pax header. Sources and keys come only from `github.com`, `codeload.github.com` and `keys.openpgp.org`. | `sdver::verify`, `kernelorg::Trust/Keyring/judge_status` | `sdver::tests::the_built_in_signers_*`, `kernelorg::tests::a_trust_file_for_another_project_*`; live: 262.2 and 262.1 verified, a tampered tarball and an unreviewed signer refused |
| SV-5 | Start a port: verify, write the profile, create `experimental/systemd-<release>` in the gate repository from the release branch with Version, Release, one changelog entry and the `config.yaml` source pinned to the verified tarball, and report every Photon patch (applies / already upstream / does not apply) and every meson option the release does not declare. | `sdver::profile_new`, `bump_spec`, `set_source`, `replay`, `unknown_meson_options` | `sdver::tests::the_version_bump_*`, `the_source_entry_*`, `the_replay_*`, `meson_options_*` |
| SV-6 | Refuse a build until the branch carries what the profile pins (config.yaml: tarball, sha512, url, commit), is a mainline tree, its spec is that Version-Release, parses on x86_64 and aarch64 and passes the spec checker, every patch applies in `%autosetup` order at fuzz 0 and every meson option is declared; every problem is named. A branch behind the release is reported. | `sdver::check`, called by `build::resolve_in` | live: the started 262.2 branch is refused with its 5 problems |
| SV-7 | A `--systemd` build runs in its own build root (`$MC_WORK/sbuild/<release>`), ISO cache and variant patches (`s<release>`), and its ISO's input record names the profile. | `sdver::effective_cfg`, `build::build_inputs` | `sdver::tests::a_systemd_build_runs_in_a_root_*`, `build::sd_tests::*` |
| SV-8 | PRs that change `SPECS/systemd` are left out of a `--systemd` build's variant patches and named; every other PR is applied. | `build::make_systemd_variant_patches`, `is_systemd_path` | `build::sd_tests::the_port_owns_the_mainline_systemd_spec_only` |
| SV-9 | Under `--systemd`, every installed guest must run the profile's systemd (`guest.systemd_version`); without it the installed systemd is recorded. | `oracle::systemd_version` | `oracle::sd_tests::the_installed_systemd_is_judged_only_under_a_profile` |
| SV-10 | Mainline only, and not together with `--kernel`: both are refused with the reason. | `sdver::check`, `sdver::context`, `main` | `sdver::tests::a_systemd_build_runs_in_a_root_*` |
| SV-11 | A profile or signer list under review is used from `SHARUKHAN_SYSTEMD_PROFILES`; otherwise the copies built into the binary. | `sdver::data_file`, `build.rs` | `wrapper::embedded::tests::*` |

## 3. Pipeline

```
sharukhan systemd profile-new 262.2     verify, profile, branch, report; exit 10 while work remains
  (port SPECS/systemd on experimental/systemd-262.2)
sharukhan systemd check 262.2           the gate a build passes first
sharukhan variant-patches --systemd 262.2
sharukhan build-iso --systemd 262.2 --iso-type minimal --allow-build
sharukhan run --systemd 262.2 --only k03
```

## 4. The first port: 262.2 (2026-11-05)

`profile-new 262.2` verified v262.2 (tag signed by Luca Boccassi, `A9EA9081…BC8C7E2E`; tarball sha512
`111da2e7…`, content `git archive` of `63511d72…`) and started the branch on 5.0 `682001eb08`. Its
report is the port's work list: Photon's patches 0001, 0003, 0004 and 0005 do not apply (0002 does),
and the spec passes `-Dlibidn`, `-Dlibiptc`, `-Drc-local` and `-Dsysvinit-path`, which 262.2 no longer
declares. `systemd check 262.2` refuses it with exactly those problems.

## 5. Out of scope

Release candidates; subreleases other than the mainline; `--systemd` combined with `--kernel`;
porting the PRs that change `SPECS/systemd` (they are left out, ADR-0013).
