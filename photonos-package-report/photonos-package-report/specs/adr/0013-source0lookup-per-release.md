# ADR-0013 — Source0Lookup per-release scoping

**Status**: Accepted (Option A — status quo + case-variant rows)

**Date**: 2026-05-18

**Deciders**: user (TODO §5 checkpoint), 2026-05-18

## Context

`Source0LookupData` is a CSV embedded in
`photonos-package-report.ps1` between markers `=@'` and `'@`
(currently L 509-1366, ~855 rows). One row per spec. Shared across
all branches and subreleases.

The C port reads the same CSV at build time via
`tools/extract-source0-lookup.sh` → `build/generated/source0_lookup_data.h`
and parses with `pr_source0_lookup_table_t`.

## Problem

Some specs have **per-release divergent upstream conventions**:

- `dbus.spec` in main 5.0 SPECS/ uses upstream
  `https://dbus.freedesktop.org/releases/dbus/dbus-<v>.tar.xz`.
  Same spec in `SPECS/91/dbus/` is vendor-pinned — short-circuits the
  lookup entirely. Same row applies to both; the SPECS/91/ pipeline
  is short-circuited externally (in PS substitution logic).
- `Linux-PAM.spec` exists in SPECS/, SPECS/90/, SPECS/91/. Each
  branch may want a different version-stream Source0Lookup row.
- `gstreamer-plugins-base.spec` — overridden `repoName` in PS (see
  L 2368). Subrelease variants may diverge further.

Today these divergences are handled either by:

1. Hard-coded `if ($currentTask.spec -ilike '...')` exception
   blocks scattered through the PS script (Phase 3b `extract-spec-hooks.sh`
   tracks these and the C port mirrors via `src/hooks/*.c`).
2. The Source0Lookup's `Warning` column to flag manual overrides.
3. Implicit acceptance that the same lookup row applies to all
   variants and the result for the "wrong" variant is filtered
   downstream.

This works for the current ~5-10 divergent specs but doesn't scale
cleanly if more vendor-pinned subreleases land.

## Options

### A. Status quo

Keep one shared `Source0LookupData` CSV. Per-release / per-subrelease
exceptions stay as PS hook blocks + C `src/hooks/*.c` mirrors.

- **Pros:** zero schema change. ~855 rows × 1 = 855 rows total. Easy
  to grep / maintain.
- **Cons:** doesn't scale. If a new subrelease wants a different
  upstream URL for spec X, today's only mechanism is a hook block.
  Hook blocks are imperative code; the CSV is declarative — hooks
  encode information that "should" be data.

### B. Add `subrelease` column to CSV

CSV schema gains col 10 `subrelease` (after `ArchivationDate`).
Empty → matches all subreleases. Specific value (`"91"`,
`"90"`) → matches only that subrelease.

- **Pros:** backward-compat (empty subrelease keeps current
  behaviour). Targeted divergence — one row per
  (spec, subrelease) tuple. Replaces several hook blocks with data.
- **Cons:** lookup is now a two-key match (spec basename +
  subrelease path). PS + C both need updating. CSV row count grows
  by the count of (spec, subrelease) tuples actually diverging.

### C. Per-release split files

`Source0Lookup-default.csv`, `Source0Lookup-91.csv`, `-90.csv`. PS
script reads the appropriate file at runtime based on subrelease.

- **Pros:** maximum separation. Easy to see "what's special for
  91". Each file ~855 rows or smaller.
- **Cons:** maintaining N files where most rows are duplicates.
  Multiple file updates per spec change. PS-extract logic doubles.
  Easy to drift between files.

### D. Source0LookupData as inheritance chain

Default file is the base. Per-subrelease files contain only the
differences (overrides). Lookup falls through default → subrelease.

- **Pros:** DRY. Override files are tiny (only the diverging rows).
- **Cons:** new conceptual layer. Cache invalidation harder. Drift
  detection more complex.

## Decision

**Option A — status quo + case-variant rows + hook blocks.**

Rationale:
- The convention is already in use: per-branch divergence is captured
  by listing the **same conceptual package twice in Source0LookupData
  with different filename casings** (e.g. `Linux-PAM.spec` and
  `linux-pam.spec`). PS L 2147's `.IndexOf` is case-sensitive, so the
  two rows match different branches' specs correctly.
- Captured as a memory entry in 2026-05-18 to ensure future Phase-M
  work preserves the asymmetric case-sensitivity (Source0Lookup
  case-sensitive; warnings/hooks case-insensitive).
- Genuinely per-spec divergence beyond what case-variants cover is
  already handled by Phase 3b hooks (`src/hooks/<name>.c` in C,
  `if ($currentTask.spec -ilike ...) {...}` chains in PS).
- Schema change would require: extract-source0-lookup.sh,
  csv-to-c-string.sh, `pr_source0_lookup_t`, the embedded CSV format,
  parity-diff.sh column awareness. High coordination cost for a
  problem the case-variant convention already solves.

**Documentation updated:** `docs/maintainer-runbook.md` §1 (Adding a
Source0LookupData row) describes the case-variant convention so future
contributors know to use it when adding per-branch-divergent rows.

If the residual divergence past hooks + case-variants grows beyond
maintainable hand-curation (e.g. >100 case-variant rows), revisit
with a new ADR proposing Option B (add subrelease column).

## Consequences

- Whichever option is chosen, `tools/extract-source0-lookup.sh` and
  `tools/csv-to-c-string.sh` need updating (and possibly a new
  `csv-to-c-multitable.sh` for option C/D).
- `pr_source0_lookup_t` schema may gain a `subrelease` field.
- Parity gate must handle the choice symmetrically PS↔C.
- This ADR is gating for Stage 5 of [`TODO.md`](../../../../TODO.md).

## Related

- ADR-0005 (bash+awk source0 embedder)
- ADR-0006 (bit-identical `.prn`)
- FRD-003 (Source0Lookup embed)
- ADR-0012 (subrelease output layout — companion)
