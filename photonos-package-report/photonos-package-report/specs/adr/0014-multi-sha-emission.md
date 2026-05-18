# ADR-0014 — Multi-SHA emission strategy

**Status**: Draft

**Date**: 2026-05-18

**Deciders**: TBD (user gate)

## Context

`SHAValue` col 9 of `.prn` currently carries ONE hash, picked from
`%define sha1` / `sha256` / `sha512` in the spec file. Default is
SHA-512 when no `%define` is present.

Two complaints with the current design:

1. **Single-algorithm output is fragile.** SHA-1 is collision-broken
   for adversarial inputs; SHA-256 is the modern default; SHA-512 is
   the photon default. A report consumer that wants to verify the
   tarball with a different algorithm has to re-download the
   tarball, which defeats the report's purpose.
2. **GitHub auto-archive instability.** The current SHA computed on
   `github.com/.../archive/refs/tags/<tag>.tar.gz` shifts whenever
   GitHub re-generates the auto-archive (git version bumps, etc.).
   That makes the recorded SHA potentially stale at consumer time.
   Recording multiple SHAs widens the verification surface and
   moves the report toward "useful at any later time" rather than
   "useful only right after the run".

User direction (2026-05-18): "It could make sense to carry multiple
sha versions (SHA-256, SHA512,...)".

## Options

### A. Combined cell: `sha256:abc/sha512:def` in col 9

Pros: zero schema change; col count stays 12.
Cons: consumers must parse the prefix-keyed string. Backwards-compat
for existing consumers depends on whether they tolerate the `:`
embedded in col 9. parity-diff.sh would need updating to treat the
combined cell as a structured value.

### B. Additional columns: col 13 = `SHA256Name`, col 14 = `SHA512Name`

Pros: clean schema; each algorithm gets its own column.
Cons: PS + C + `parity-diff.sh` + journal schema + runbook all need
coordinated rollout. Mid-rollout, PS may emit 14-col rows while C
still emits 12 — every line diffs strict during the window.

### C. Sidecar manifest file

A new `photonos-urlhealth-shas-<branch>_<ts>.json` next to each
`.prn`, mapping spec → {sha1: ..., sha256: ..., sha512: ...}.

Pros: keeps `.prn` schema unchanged; rich structure for the manifest.
Cons: two-file output complicates download/upload-artifact (the M05
workflow needs the second file too). Parity-diff would either skip
the manifest or grow a separate diff mode.

### D. Per-algorithm row duplication

Emit one row per spec per algorithm. Triples row count.
Rejected: bloats the report and breaks downstream "unique spec per
row" assumptions.

## Decision

**Pending user input.** Agent recommendation: **Option B (additional
columns)**, gated by a clean coordinated PS + C + tooling rollout.
Reasons:

- Cleanest data model. Consumers that don't care about the new
  columns ignore them.
- Parity-diff.sh's existing column-comparison logic extends naturally
  to more cols (it already loops over `max(npf, ncf)`).
- The journal schema is unchanged — col counts don't affect
  per-row strict/soft classification, only the per-row column
  comparison.

Mid-rollout risk mitigated by: ship PS + C together in a single PR
that adds the columns to both sides plus updates parity-diff.sh.
Run a coordinated cutover with workflow re-dispatch.

## Consequences

- New columns 13 (`SHA256Name`) and 14 (`SHA512Name`). If a spec's
  `%define` already names sha512, col 14 duplicates col 9 (both PS
  and C produce identical values — no diff).
- `pr_sha_of_url` already supports SHA1/SHA256/SHA512; need to call
  it twice/thrice and capture each result.
- `urlhealth` infrastructure currently downloads ONCE for the
  existing single SHA. Multi-SHA should re-use the single download
  and stream through multiple hashers — avoid duplicate downloads.
- FRD-014 (.prn row assembly) needs amendment for the new schema.
- ADR-0006 (bit-identical) is amended: cols 13/14 added to the
  strict-compare set.
- Runbook §1 schema table grows.

## Implementation order (when accepted)

1. Add `pr_sha_of_url_multi(url, &sha256, &sha512)` API to `src/sha.c`.
   Single libcurl GET; feed bytes into multiple `EVP_MD_CTX` parallel.
2. Add `SHA256Name`, `SHA512Name` fields to `pr_state_t`.
3. PS: amend the `%define` detection in CheckURLHealth to compute
   both algorithms regardless of spec preference. Update L 4933 row
   assembly to emit 14 cols.
4. C: amend check_urlhealth.c to call multi-hash, append cols 13/14.
5. Update parity-diff.sh — no real change (loop already handles N).
6. Update FRD-014, ADR-0006 strict-col set, runbook §1.
7. Update diff_analyzer.py's COL_NAMES + VOLATILE set.
8. Ship as one PR. Re-dispatch C workflow to validate symmetric output.

## Related

- ADR-0006 (bit-identical priority — strict col set)
- ADR-0009 (CI parity gate)
- FRD-014 (.prn row assembly)
- The 63-spec `SHAName`-only bucket (github auto-archive instability)
  may be partially mitigated by multi-SHA: even if sha512 drifts,
  consumers can still verify against sha256 if those happen to match.
  Doesn't fully solve the instability (need a stable source like
  release-asset URLs), but adds redundancy.
