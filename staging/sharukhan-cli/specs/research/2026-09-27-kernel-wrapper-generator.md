# Handoff: port the kernel-wrapper generator to a sharukhan subcommand

> **Resolved 2026-09-27.** Implemented as [FRD-001](../features/kernel-wrapper.md) with
> ADR-0002 .. ADR-0007. The open questions of section 6 are answered there: `sharukhan wrapper`
> (ADR-0002), the base made version-neutral first and the Python generator retired (ADR-0007),
> profiles in `sharukhan-cli/profiles/kernel/` cross-checked against the branch manifest
> (ADR-0004), derived versions from the profile with a base-version review guard (ADR-0005). Slots
> replaced anchors (ADR-0003); pins are established by signature verification (ADR-0006).

Date: 2026-09-27. Status: **research / handoff, no authority.** Under this project's SDD workflow
(`specs/README.md`) the work enters at Phase 1 (PRD). Nothing below is approved. It records the
ground truth a PRD needs and the open questions it must close.

## 1. What exists today

The staging repository ships two experimental ISO wrappers that put a newer Linux kernel under the
Photon OS 5.0 userland:

| File | Kernel | Wrapper version | Lines |
|---|---|---|---|
| `staging/runPh7-2-7.sh` | Linux 7.2.7 (stable) | v13 | 1,026 |
| `staging/runPh7-3-RC4.sh` | Linux 7.3-rc4 (mainline RC) | v8 | 1,195 |

`runPh7-3-RC4.sh` is **not hand-maintained**. It is generated from `runPh7-2-7.sh` by a Python
script, `tools/make-73rc4.py`, 316 lines. The reference copy was added with this handoff; the working
copy lives outside the repository in `/root/tmp/k73rc4/`. The pattern is: fix a problem once in the
base wrapper, regenerate, and both scripts carry the fix. Every fix since wrapper v2 went through it.

**Golden baseline, verified 2026-09-27.** Running the generator on `staging/runPh7-2-7.sh` (v13)
produces a file byte-identical to `staging/runPh7-3-RC4.sh` (v8). The Rust port must reproduce this
exactly. That is the primary acceptance test, and it needs no VM or build.

The user's standing rule is that generators become Rust subcommands in sharukhan-cli once they are
reusable beyond one case. This one is: the next kernel (7.3-rc5, 7.3 final, 7.4) is the same
transformation with different data.

## 2. What the generator does

It reads the base wrapper as text, applies a fixed sequence of edits, runs two global renames, asserts
nothing of the old kernel remains, and writes the result with mode 0755.

The core primitive is `rep(a, b, count=1)`: replace an exact substring and **assert it occurred exactly
`count` times**. That assertion is the whole safety model. When the base wrapper changes under a
replacement, generation stops at that anchor instead of emitting a silently wrong script. The port
must keep it: a missing or duplicated anchor is a typed error that names the anchor.

The edits (25 anchored `rep` calls, one function swap located by `index`, and two global renames), grouped by what they are. Line numbers refer to `tools/make-73rc4.py`, excluding its
5-line reference header.

| # | Group | Lines | Kind | Notes |
|---|---|---|---|---|
| A | Header, banner, `RELEASE_BRANCH` defaults, `mktemp` name, `sed` rewrites of `runPh5_normal.sh`, ISO marker name | 13–31 | data | Pure substitutions. The banner text and wrapper version number are maintained here by hand; see §5. |
| B | Kernel pin: replace the whole `pin_727()` function with `pin_73rc4()` | 33–89 | **template** | Located by `index("pin_727() {\n")` up to the next `"\n}\n"`, not by `rep`. The new body carries the RC version scheme: Version 7.3.0, Release 0.rc4.1, `%define kernel_src`, the git.kernel.org Source0, `EXTRAVERSION` blanking, `noreplace-smp` removal and a changelog entry. |
| C | `%autopatch` anchor follows `%setup -q -n linux-%{kernel_src}` | 91–97 | data | Needed because the RC tarball directory is not `linux-%{version}`. |
| D | Kernel-specific patch enablers, inserted after `disable_unrebased_ranges SPECS/linux/linux-esx.spec` | 99–191 | **template + data** | `enable_rap_73rc4` (Patch61 → rebased file, `%autopatch` m61 and m63, generic flavour only), `enable_rdrand_73rc4` (Patch6, both flavours), `enable_vmwgfx_73rc4` (Patch7300, both flavours). They share a shape: point PatchN at a file, anchor it after `Patch1:`, add `%autopatch -p1 -mN -MN` after `%autopatch -p1 -m0 -M1`, idempotent. |
| E | Installer patch appender `pin_installer_73rc4` | 193–235 | **template + data** | Appends 0008 and 0009 as the next PatchN, each with its own Release bump and changelog entry. The per-patch bump is deliberate: a fresh tree and an already-pinned one both end at 2.8-7, so a stale 2.8-6 RPM can never pass as the new build. |
| F | Sandbox-wipe name globs | 238–242 | data | `linux-7.3.0*`: the RPM version, not the tarball name. |
| G | Tarball name, URL, sha512 | 244–252 | data | RCs exist only as git.kernel.org snapshots (`.tar.gz`); stable releases come from cdn.kernel.org (`.tar.xz`). |
| H | Version assert (`expected 7.3.0`) | 254–258 | data | |
| I | Version-neutral cleanups | 260–295 | **should move upstream** | They rewrite 7.2.7-specific leftover handling (SpecData compat marker, `c++.real727`, an ENA comment) into version-neutral forms. They exist only because the base wrapper hard-codes its own version. See §6, question 2. |
| J | Global rename `7.2.7` → `7.3-rc4`, then `assert "7.2.7" not in t and "727" not in t` | 296–297 | rule | **Ordering trap:** every `rep` after this line must match the renamed text. The pre-build edits below are written against `7.3-rc4` for that reason. |
| K | Pre-build package list | 299–307 | data | Appends `cloud-init,sudo,dbus,photon-os-installer` to the STIG set that is built before `make image`. `make image` does not rebuild an install-only dependency whose older RPM exists, so branch-updated packages must be listed. |
| L | Global rename `runPh7-2-7` → `runPh7-3-RC4` | 310 | rule | Also turns every `[runPh7-2-7]` log tag, including those inside inserted templates, into `[runPh7-3-RC4]`. The templates in B, D and E are therefore written with the **base** tag. |

## 3. The traps a port will hit

These all came up while the Python generator was maintained. Each has cost at least one broken build.

1. **Three quoting layers.** The generator is Python, it emits shell, and the shell embeds Python
   heredocs (`python3 - "$spec" << 'PY' … PY`). A regex that must read `\d` in the emitted file is
   written `\\d` in the generator's non-raw strings. In Rust, keep templates in `include_str!` files
   (the `src/embedded/` precedent) so they are written exactly as emitted, with no escaping layer.
2. **Heredoc terminators.** An inner `PY` line ends an outer heredoc early. This is irrelevant in Rust
   but matters for anyone editing the templates with shell tools.
3. **Rename ordering (J).** Replacements after the global rename must use the new name. A data-driven
   port should apply all anchored edits first, then the renames, then the leftover assertion. Moving
   K before J needs care, because K's anchor text contains no version.
4. **Template tags (L).** Templates carry `[runPh7-2-7]` and become `[runPh7-3-RC4]` only through the
   final rename. If the port renders the target tag directly, the golden output still matches, but
   only because both paths agree. Test it.
5. **The leftover assertion must stay.** `7.2.7` and `727` must not survive (`K727_SHA`,
   `.runph727-iso-marker`, `c++.real727`). For a base that is itself a derived name, the forbidden
   tokens are data, not constants.
6. **Two version numbers.** The wrapper banner (`wrapper v13`) and the derived banner (`wrapper v8`)
   are edited by hand in the anchor text of edit A. Each base bump breaks that `rep` until someone
   updates it. This is intended (it forces a review), but the error message must say so.
7. **The output must be valid shell.** The workflow ran `sh -n` after every generation. A port can
   run it as an argv-only external command and report the measured result (AGENTS.md).

## 4. Proposed shape (for the PRD to confirm or reject)

A data + template design keeps the generic part in code and the kernel-specific part in reviewable files:

- **Profile** (JSON; `serde_json` is already a dependency, so no new crate): target kernel tarball
  name, URL and sha512; RPM Version, Release and `kernel_src`; branch name; script name; forbidden
  leftover tokens; pre-build additions; the enabled kernel patches as (PatchN, file, flavours,
  `%autopatch` ranges); installer patches as (file, date, changelog text).
- **Templates** (`include_str!`): the pin function (B) and one generic patch enabler that replaces
  the three near-identical functions in D, parameterised by the profile.
- **Engine**: ordered anchored edits with exact-count assertion, then renames, then the leftover
  assertion, then an `sh -n` check. Errors are typed and name the anchor, the expected count and the
  measured count.
- **Surface**: something like `sharukhan wrapper derive --base staging/runPh7-2-7.sh --profile
  <file> --out <path>`, with `--check` comparing against an existing output and exiting non-zero on
  any difference. `--check` is what keeps the committed `runPh7-3-RC4.sh` honest in CI.

A literal port (the 25 `rep` calls hard-coded in Rust) is the cheapest option and passes the golden
test. It fails the "generic" rule that motivates the work, though, because the next kernel would
again mean editing code.

## 5. Acceptance tests to carry into the task breakdown

- **Golden:** the base `staging/runPh7-2-7.sh` at the commit where this doc lands, plus the 7.3-rc4
  profile, gives output byte-identical to `staging/runPh7-3-RC4.sh` at the same commit.
- **Negative control (anchor drift):** change one anchor in a copy of the base. Generation fails with
  a typed error naming that anchor and "expected 1, found 0". No output file is written.
- **Negative control (duplicate anchor):** duplicate an anchor. The error reports "found 2".
- **Negative control (leftover):** a profile that omits a forbidden token rename fails the leftover
  assertion and prints the offending lines.
- **Idempotence of the emitted pins:** out of scope for the generator itself. The emitted shell
  functions are idempotent and were proven so by builds (`already applied` / `already pinned` log
  lines in `runPh7-3-RC4.run12.log`). Do not re-prove that in Rust.
- **`sh -n`** passes on generated output, and the report prints the measured result.
- Project gates from `specs/README.md`: `cargo test`, `clippy -D warnings`, `fmt --check`, ≥ 80%
  coverage on the new module, and accurate `--help` text.

## 6. Open questions the PRD must close

1. **Subcommand name and scope.** Is this `wrapper derive`, or part of `build`? Should it also
   derive `runPh7-2-7.sh` from `runPh5_normal.sh`? That relationship is a different mechanism
   (generate-and-rewrite at run time, inside the wrapper) and is probably out of scope.
2. **Move group I upstream first?** If `runPh7-2-7.sh` stopped hard-coding `7.2.7` in its
   leftover-cleanup code (SpecData marker regex, `c++.real*` glob, ENA comment), six replacements
   would disappear from the generator. That is a shell change to the base wrapper and needs one
   rebuild to prove it. Doing it before the port shrinks the port.
3. **Where profiles live.** `sharukhan-cli/profiles/`, next to the wrappers in `staging/`, or on the
   kernel branch (`SPECS/linux/EXPERIMENTAL-7.3-rc4.md` already records the tarball, sha512 and tag
   commit)?
4. **Retire the Python?** Once `--check` passes in CI, should `tools/make-73rc4.py` be deleted or
   kept with a pointer, as `tools/regen-canister-equivalent.py` is?
5. **Version numbers.** Should the derived banner's version come from the profile, or be computed?

## 7. Context a new owner needs

- **How the wrappers are used.** `runPh7-*.sh` wraps `runPh5_normal.sh`. It generates a temporary
  build script, sources an embedded pin (`EMBEDPIN` heredoc) before every `make`, and builds the ISO
  into `OUTPUT_DIR`. Run it under a pseudo-TTY: `build.py` runs the spec checker only when stdout is
  not a terminal, and the pinned kernel specs fail that checker. `staging/README.md` documents every
  wrapper version, what it fixed and how it was verified.
- **Release tree.** `experimental/linux-7.3-rc4` on github.com/dcasota/photon carries the rebased
  kernel patches (RAP 7.3, rdrand 7.3, vmwgfx blend) and installer patches 0008 and 0009. The
  generator's templates point at those files by name, so the profile and the branch must agree.
- **Recent history.** Wrapper v7/v8 (2026-09-27) fixed STIG installs. A stale local edit in the
  `common` tree had dropped `stig-hardening` from `packages_installer_initrd.json`, so the installer
  initrd had no Ansible. The base wrapper now restores the committed list before every build
  (`pin_restore_initrd_pkgs`). The generator did not need to change for that, because the fix sits
  in the base and flows through. That is the design working as intended.
- **Commit conventions.** Attribution "Daniel Casota <dcasota@gmail.com>". PR bodies end with the
  Generated-with line, never a session link.
