# FRD-001 — Kernel wrapper derivation (`sharukhan wrapper`)

Status: implemented (2026-09-27)
Research: [`research/2026-09-27-kernel-wrapper-generator.md`](../research/2026-09-27-kernel-wrapper-generator.md)
Decisions: [ADR-0002](../adr/0002-wrapper-subcommand.md) · [ADR-0003](../adr/0003-wrapper-slots.md) ·
[ADR-0004](../adr/0004-wrapper-profiles.md) · [ADR-0005](../adr/0005-wrapper-versions.md) ·
[ADR-0006](../adr/0006-kernel-source-verification.md) · [ADR-0007](../adr/0007-retire-python-generator.md)
Code: `src/wrapper/` (`identity`, `escape`, `profile`, `base`, `render`, `derive`, `validate`,
`kernelorg`, `branch`, `cli`), `src/sha512.rs`
Data: `profiles/kernel/<release>.json`, `profiles/kernel/kernel-org-signers.json`

## 1. Purpose

`runPh7-2-7.sh` builds Photon OS 5.0 with an upstream kernel instead of 6.12. A wrapper for another
kernel.org release was produced by a Python script with 25 hard-coded replacements for exactly one
target (7.3-rc4). This feature replaces it with a generic derivation: the base wrapper declares which
of its regions are kernel-specific, a reviewed per-release profile holds what is not computable, and
everything else - names, versions, URLs, paths, regexes - is computed from the release string that
kernel.org publishes. No template placeholder exists that could survive; no value is trusted before
it is verified.

## 2. Requirements

Each requirement names the code that meets it and the test that proves it.

| ID | Requirement | Met by | Proven by |
|---|---|---|---|
| KW-1 | Derive a wrapper for any kernel.org release from one base and one profile, without code changes per release. | `derive::derive_text` | `cli::tests::golden_*`, `derive::controls::*` |
| KW-2 | Accept exactly kernel.org's release grammar: `X.Y-rcN`, `X.Y`, `X.Y.Z` (no `X.Y.0`, no `-rc0`, no leading zeros, no whitespace, bounded components); reject linux-next and anything else with the reason. | `identity::KernelRelease::parse` | `identity::tests::anything_outside_the_grammar_*` |
| KW-3 | Compute every identity string from the release: tag, ISO marker, token, sha variable, pin function, script and branch names, git tag, tarball, URL, `Source0`, signature URL, RPM Version/Release, `kernel_src` need, `%setup` macro, EXTRAVERSION. | `identity` | `identity::tests::*` |
| KW-4 | RPM rules: an RC is `Version X.Y.0`, `Release 0.rcN.<iter>` (sorts below the final); a mainline final is `X.Y.0` with `kernel_src X.Y`; a stable release keeps `%{version}`. | `identity::rpm_version/rpm_release/needs_kernel_src` | `identity::tests::*` |
| KW-5 | The base declares its own kernel, userland and native series (`# @sharukhan-wrapper ...`), strictly parsed, exactly once, unindented. | `base::Base::parse` | `base::tests::the_declaration_is_required_and_strict` |
| KW-6 | The base marks each kernel-specific region as a named slot; every known slot exactly once, paired, not nested; unknown names and malformed marker lines are errors. | `base::Base::parse` | `base::tests::*`, `derive::controls::a_missing_slot_*`, `a_duplicated_slot_is_found_2` |
| KW-7 | The base must be self-consistent: header and banner announce the same wrapper version; the declared kernel's tag, marker and release occur as whole identities. | `base::check_consistency`, `mentions_whole` | `base::tests::*` |
| KW-8 | A slot is re-rendered by a typed renderer; free text from the profile is validated for the context it lands in (shell comment, Python string, f-string, shell double quotes); regex literals are escaped. | `render`, `escape` | `escape::tests::*`, `profile::tests::each_invalid_field_is_named` |
| KW-9 | Text outside slots is carried over and renamed base identity -> target identity; every rename must apply at least once, with the count reported. | `derive::apply_renames` | `derive::controls::a_rename_with_nothing_to_rename_is_refused` |
| KW-10 | Before renaming, no target identity string may already occur in the carried text (collision). | `derive_text` step 3 | `derive::controls::a_target_identity_already_in_the_base_is_a_collision` |
| KW-11 | No rendered slot may carry a base identity string (render leak). | `derive_text` step 4 | `derive::controls::a_profile_text_carrying_the_base_tag_leaks_and_is_refused` |
| KW-12 | After derivation no base identity string survives anywhere; a bare token inside a ≥32-hex-digit run (a digest) is not a hit; offending lines are printed once each. | `derive::find_identity`, `token_hits` | `derive::tests::a_token_inside_a_digest_*`, `derive::controls::an_unrenamed_identity_string_*` |
| KW-13 | The output is validated by the tools that run it, on stdin (no temporary file): `sh -n`, and every `<< 'PY'` heredoc parsed by `python3`'s `ast`; both reported as measured. | `validate` | `validate::tests::*`, `derive::controls::output_that_is_not_valid_*` |
| KW-14 | Output is written atomically (same-directory temporary, fsync, mode 0755, rename); the base is never the output. | `derive::write_atomic`, `cli::derive_one` | `derive::tests::an_atomic_write_*` |
| KW-15 | `derive --check` compares with the committed wrapper byte for byte and reports the first differing line. | `derive::check_against` | `derive::tests::check_against_*` |
| KW-16 | `wrapper check` derives every profile and fails if any committed wrapper drifted. | `cli::cmd_check` | manual run (§5) |
| KW-17 | Profiles are strict JSON (`deny_unknown_fields`, schema 1), validated field by field with the field named in the error. | `profile::Profile::validate` | `profile::tests::*` |
| KW-18 | A profile names the base kernel and the base wrapper version it was reviewed against; a base bumped since then stops derivation with the review to do. | `derive_text` step 2 | `derive::controls::a_base_bumped_since_review_*` |
| KW-19 | The derived wrapper's own version comes from the profile, never computed. | `render::header/banner` | golden |
| KW-20 | Kernel patches are enabled by mode (`replace`, `readd`, `add`), anchored after the single live `%autopatch -p1 -m0 -M1` the base leaves; the base must still carry it. | `render::kernel_patch`, `derive_text` | golden |
| KW-21 | Installer patches are appended as the next `PatchN` with their own release bump and changelog entry; changelog dates carry a calendar-checked weekday. | `render::installer_patches`, `escape::changelog_date` | golden, `escape::tests::*` |
| KW-22 | Pre-build extras extend the base's own package list, found structurally; an extra already in it is an error. | `derive::prebuild` | `derive::controls::prebuild_extras_*` |
| KW-23 | Kernel parameters to drop are regex-escaped and explained in the emitted comment. | `render::kernel_pin` | golden |
| KW-24 | Texts in a profile may name only the target's release (and RPM version), never another release. | `profile::validate_release_mentions` | `profile::tests::a_text_naming_another_kernel_release_*` |
| KW-25 | Source verification: cdn tarballs by `.tar.sign` over the decompressed tar; git.kernel.org snapshots by a signed tag plus byte-identity with `git archive` of the tagged commit and its pax `comment`; only reviewed signer fingerprints accepted; exactly one good valid signature; every tar entry under `linux-<release>/`. | `kernelorg::verify` | `kernelorg::tests::*`, live runs (§5) |
| KW-26 | Signer keys are fetched from kernel.org's pgpkeys repository and imported into a private keyring only when the primary fingerprint is the reviewed one. | `kernelorg::Keyring::build` | `kernelorg::tests::primary_fingerprints_*`, live runs |
| KW-27 | The profile records how its pin was verified (method, signer, commit, date); `verify --profile` fails if the measured values differ. | `profile::Verified`, `cli::cmd_verify` | live run (§5) |
| KW-28 | Branch verification: `SPECS/linux/EXPERIMENTAL-<release>.md` on `origin/experimental/linux-<release>` agrees with the profile and identity on tarball URL, sha512, tag commit, Kernel and RPM Version/Release; every patch file exists exactly once under its directory. Skipping it must be explicit and is reported. | `branch` | `branch::tests::*`, live run |
| KW-29 | `wrapper kernel <selector>` resolves `mainline`, `stable`, `longterm`, `longterm-X.Y` or a release against releases.json and cross-checks each listed URL with the computed one. | `kernelorg::select`, `cross_check` | `kernelorg::tests::selectors_*` |
| KW-30 | `wrapper profile-new` starts a profile for another release from an existing one: verifies the source first, fills pin, method, signer, commit and a dated changelog, sets the base version it is now reviewed against, proves it derives, and lists every text naming a release or series for review. | `cli::cmd_profile_new` | `cli::tests::json_renames_*`, live run |
| KW-31 | Security: external programs only as argument vectors; only `https://{www,cdn,git}.kernel.org` with plain paths is fetched (`--proto =https`, redirects https only); git fetch allows the https protocol only; no shell. | `kernelorg::check_url`, `fetch` | `kernelorg::tests::only_https_*` |
| KW-32 | Determinism: the same base and profile always give the same bytes; no clock, host or network input enters derivation. | `derive_text` is pure but for `sh -n`/`python3` | golden |
| KW-33 | The base is version-neutral wherever the code does not need the version: leftover clean-up matches any release (`SpecData` marker regex, `c++.real[0-9]*` glob), comments say "kernel-specific". | `staging/runPh7-2-7.sh` | fixture equivalence (§5) |
| KW-34 | Errors are typed (`WrapperError`) and name the input, the expectation and the measurement. | `error` | every negative test |

## 3. The base contract

```
#!/bin/sh
# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12
...
# @sharukhan-slot header begin
# Photon OS 5.0 userland + experimental Linux 7.2.7
# wrapper v13
# @sharukhan-slot header end
```

Slots, in file order: `header`, `banner`, `kernel-pin`, `kernel-pin-calls`, `kernel-patches` (empty
in the base), `kernel-sandbox-names`, `kernel-source`, `version-assert`, `prebuild`. Markers may be
indented (two are inside a Python expression). The declaration and every marker are dropped from the
output; a surviving `@sharukhan-` string is a validation error. The markers are comments to both
`sh` and Python, so the base runs unchanged.

## 4. Pipeline

1. Parse base (declaration, slots, self-consistency); load and validate the profile.
2. Profile ↔ base: same base kernel; same reviewed base wrapper version; live `%autopatch` present.
3. Collision pre-check on the carried text.
4. Render each slot; `prebuild` transforms the base's own slot content; leak check per slot.
5. Rename carried text (tag, marker, release, and the `%setup` directory in literal and awk-regex
   form when the macro changes); every rename counted and required.
6. Leftover check over the whole output (setup forms over the carried text only, since the rendered
   pin legitimately names the form it rewrites).
7. `sh -n`, Python heredocs; then write atomically, or compare (`--check`).

## 5. Verification record (2026-09-27)

- Golden: committed `runPh7-2-7.sh` + `profiles/kernel/7.3-rc4.json` derive `runPh7-3-RC4.sh`
  byte-identical (1195 lines; renames `runPh7-2-7`×76, `runph727`×1, `7.2.7`×35, both `%setup`
  forms ×1; `sh -n` exit 0; 19 heredocs parsed).
- `wrapper derive --profile 7.3-rc4 --check --repo /root/5.0`: branch `45092aa6d`, manifest,
  sha512, tag commit, RPM Version/Release and all five patch files agree.
- `wrapper verify 7.3-rc4 --profile 7.3-rc4`: tag `v7.3-rc4` signed by
  `ABAF11C65A2970B130ABE3C479BE3E4300411886` (Linus Torvalds); decompressed snapshot byte-identical to
  `git archive` of `93f51579e7df…`; 102,322 entries under `linux-7.3-rc4/`; profile agrees.
- `wrapper verify 7.2.7`: `.tar.sign` signed by `647F28654894E3BD457199BE38DBBDC86092693E` (Greg
  Kroah-Hartman); 101,077 entries under `linux-7.2.7/`; the digest equals the base's `K727_SHA`. The
  same tarball renamed to `linux-7.2.8.tar.xz` is refused: `BADSIG` against 7.2.8's signature.
- Base neutralisation (KW-33) proven by fixtures instead of a full rebuild: the old and new
  `pin_drop_specdata_compat` give identical files for a 7.2.7-marked `SpecData.py` and a clean one;
  the new code additionally strips a wrap left by any other release. The old and new `c++.real`
  loops leave identical trees. Every other base change is a comment or marker line.

## 6. Out of scope

Deriving `runPh7-2-7.sh` itself from `runPh5_normal.sh` (a run-time generate-and-rewrite inside the
wrapper, a different mechanism). Rebasing kernel patches for a new release: `profile-new` lists them
for review and the branch check proves the rebased files exist, but writing them is kernel work.
