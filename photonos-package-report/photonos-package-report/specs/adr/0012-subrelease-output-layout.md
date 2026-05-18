# ADR-0012 — Subrelease output layout

**Status**: Accepted (Option A — status quo / pinned-sentinel)

**Date**: 2026-05-18

**Deciders**: user (TODO §4 checkpoint), 2026-05-18

## Context

Photon 5.0 carries vendor-pinned subrelease trees:

- `SPECS/91/` — 16 packages, marker `vendor-pinned (subrelease 91)`
- `SPECS/90/` — 53 packages (added 2026-05-12, not yet in the parity snapshot)
- main `SPECS/` — ~1100 default packages

Today the PS workflow emits ONE `.prn` per branch
(`photonos-urlhealth-5.0_<ts>.prn`) that contains both default rows and
subrelease rows mixed together. Subrelease rows are identified by:

- col 4 `UrlHealth` = literal `pinned`
- col 11 `warning` = `vendor-pinned (subrelease N)`

The same basename (e.g. `dbus.spec`) can appear twice in the same
`.prn` — once for `SPECS/dbus/dbus.spec` (with full pipeline result)
and once for `SPECS/91/dbus/dbus.spec` (with pinned sentinel).

## Problem

Disambiguating rows by spec basename alone is impossible at the `.prn`
level. Tooling that consumes `.prn` (parity-diff, journal, downstream
report generators) cannot tell which `dbus.spec` row is which without
inspecting cols 4 + 11.

When SPECS/90 lands in a future snapshot, the same problem doubles.

## Options

### A. Status quo

Single `.prn` per branch. Disambiguation via cols 4 + 11.

- **Pros:** zero tooling change. Backward-compat with all existing
  parity-diff / journal logic.
- **Cons:** consumers must know the sentinel encoding. Hard to slice
  reports "show me only main SPECS for 5.0".

### B. Per-subrelease `.prn` filename

Three files per branch: `photonos-urlhealth-5.0_<ts>.prn`,
`photonos-urlhealth-5.0-90_<ts>.prn`, `photonos-urlhealth-5.0-91_<ts>.prn`.

- **Pros:** unambiguous slicing. Each `.prn` is internally consistent
  (no duplicate basenames).
- **Cons:** parity-diff, journal schema, workflow output collection,
  and the runbook `gh run download` examples all need updates. New
  `-GeneratePh5_91URLHealthReport`-style flags? Or detect from SPECS
  tree automatically?

### C. Column 13 — SubreleasePath

Add a new column to `.prn` carrying the `SpecRelativePath` prefix
(empty for main, `91` for SPECS/91, `90` for SPECS/90). Filename stays
single-per-branch.

- **Pros:** unambiguous within a single `.prn`. Disambiguation by a
  proper data column instead of sentinel-encoding in cols 4 + 11.
  Tooling diff is smaller than Option B.
- **Cons:** schema change. Parity-diff awareness of col 13 needed.
  Journal columns unchanged. Existing `pinned` sentinel can stay or
  be removed.

## Decision

**Option A — status quo / pinned-sentinel.**

Rationale:
- PS already implements this at L 2104-2106 (vendor-pinned short-circuit
  that emits the fixed-shape sentinel row).
- ADR-0006 (bit-identical `.prn`) is best served by NOT changing the
  schema. Any of Options B/C requires coordinated changes across PS,
  C, `parity-diff.sh`, the journal schema, and the runbook.
- The duplicate-basename problem (`dbus.spec` from SPECS/ vs SPECS/91/)
  is real but already solved: the rows differ in cols 4 (`UrlHealth`),
  11 (`warning`), and other columns the pipeline fills for the
  non-pinned variant. Consumers that need to disambiguate inspect
  col 4 = `pinned` and col 11 = `vendor-pinned (subrelease N)`.
- M17 (Phase M task) is the matching C-side implementation. After it
  lands, both PS and C emit byte-identical pinned rows.

If a future need arises to slice `.prn` by subrelease without parsing
sentinels (e.g. for the kernel-CVE-gate skill), revisit with a new
ADR. For now, the sentinel encoding is sufficient.

## Consequences

- Whichever option is chosen, the PS L 2155-2200 (or equivalent)
  pinned-emit short-circuit must continue to recognise the SPECS/<N>/
  subpath.
- C port needs symmetric implementation in `parse_directory` →
  `check_urlhealth` → row assembly.
- This ADR is gating for Stage 4 of [`TODO.md`](../../../../TODO.md).

## Related

- ADR-0006 (bit-identical `.prn`)
- ADR-0009 (CI parity gate)
- FRD-002 (spec parsing)
- FRD-014 (`.prn` row assembly)
- [`docs/prn-analysis/photon-5.0-SPECS-90.md`](../../docs/prn-analysis/photon-5.0-SPECS-90.md)
- [`docs/prn-analysis/photon-5.0-SPECS-91.md`](../../docs/prn-analysis/photon-5.0-SPECS-91.md)
