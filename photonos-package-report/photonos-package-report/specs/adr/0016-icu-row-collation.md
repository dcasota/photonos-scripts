# ADR-0016: ICU collation for the `.prn` row sort

**Status**: Accepted
**Date**: 2026-05-23

## Context

The `.prn` report rows are sorted before emission to match PowerShell's
`Sort-Object Spec, SubRelease -Unique` (PS L 5476). `parity-diff.sh`
compares the C and PS `.prn` files **line-by-line at the same row index**,
so the C row order must reproduce PS's order exactly — this is the single
most load-bearing ordering invariant in the project (CLAUDE.md "the one
thing not to break").

`Sort-Object` orders strings with .NET `CompareInfo` for the current
culture, case-insensitively. On Linux, .NET globalization delegates to
**ICU**, so this is ICU culture-aware ("linguistic") collation, not an
ordinal byte comparison.

The C side used `strcasecmp` (M14). That fixed the case axis but is still
**ordinal**: it compares punctuation by byte value — `-` = 0x2D, `.` =
0x2E, `_` = 0x5F. ICU instead treats `-` and `.` as ignorable punctuation
and weights `_` differently, so the two disagree whenever spec names in a
neighbourhood differ only by punctuation. Observed on the 5.0 branch:

| PS order (ICU) | C order (strcasecmp) |
|---|---|
| `rubygem-http_parser.rb` before `rubygem-http-accept` … `rubygem-http.spec` | after them |
| `python-setuptools_scm` before `python-setuptools-rust` | after |
| `python-backports_abc` before `python-backports.ssl_match_hostname` | after |
| `rubygem-unf_ext` before `rubygem-unf` | after |

Each mis-ordered row shifts relative to PS, and because the diff is
row-index based, every shifted row surfaces as a **phantom diff** on the
neighbouring row (the detected values are identical, merely attached to
the wrong line). On 5.0 this accounted for ~10 of the reported strict
diffs — entirely artifactual.

## Decision

Sort `.prn` rows with an **ICU collator**, opened once per process via
`pthread_once`:

```c
ucol_open("en-US", &status);
ucol_setStrength(coll, UCOL_SECONDARY);   /* case-insensitive */
... ucol_strcollUTF8(coll, a, -1, b, -1, &status) ...
```

`en-US` matches the runner's culture; strength `SECONDARY` makes case a
non-distinguishing (tertiary) difference, matching `Sort-Object`'s default
case-insensitivity. If ICU initialisation ever fails, `cmp_str_asc` falls
back to `strcasecmp` so the report still sorts (degraded order, never a
crash).

New build dependency: **`icu-devel`** (Photon `tdnf install -y icu-devel`),
wired via `pkg_check_modules(ICU REQUIRED icu-i18n icu-uc)` in `CMakeLists.txt`
and added to the CI dependency install in `package-report-C.yml`.

## Rationale

- ICU is *the same engine PowerShell already uses* on Linux, so matching
  it is exact rather than approximate. Empirically validated: the ICU
  `en-US`/SECONDARY sort reproduces PS's `.prn` row order with **0
  mismatches across all five branches** (3.0: 919, 4.0: 1034, 5.0: 1113,
  6.0: 1093, common: 6 rows), and agrees with live `pwsh Sort-Object` on
  both ICU 72 and ICU 76.
- ICU runtime is already present on Photon (PowerShell/.NET depend on it);
  only the dev headers are added at build time.
- glibc `strcoll` (en_US.UTF-8) was rejected — it produces a *third*,
  different order (ISO 14651 fully-ignorable punctuation), matching
  neither PS nor the prior C behaviour.

## Consequences

- C and PS `.prn` files are now byte-identical in row order on the
  punctuation families that previously diverged; ~10 phantom 5.0 diffs
  are eliminated permanently (deterministic, not run-dependent).
- The binary and the PS reference must use the **same ICU major version**
  on the runner. Installing `icu-devel` upgrades the runner's `icu` to the
  current Photon build; PowerShell on the same runner then uses that same
  ICU, so they stay consistent. (Collation for the spec-name set is in
  fact stable across ICU 72→76, verified.)
- ICU collation is driven by the `ucol_open` locale argument, independent
  of `setlocale(LC_ALL, "C")` — the two sort axes do not interact.

## Considered alternatives

- **Keep `strcasecmp`, soften the row position in `parity-diff.sh`** (join
  by Spec instead of row index): rejected — it would mask a *real*
  byte-level difference in the output and weaken invariant 1 (bit-identical
  `.prn`). The output genuinely was in the wrong order.
- **glibc `strcoll` + `en_US.UTF-8` locale**: rejected (different order;
  see Rationale).
- **Hand-roll a .NET collation table in C**: rejected — large, fragile,
  and exactly what ICU already provides.
