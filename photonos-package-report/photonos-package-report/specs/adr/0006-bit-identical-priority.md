# ADR-0006: Bit-identical output is non-negotiable; performance is secondary

**Status**: Accepted
**Date**: 2026-05-12

## Context

The script's output (`.prn` files, URL-health markdown summaries, package-report rows) is consumed unchanged by half a dozen downstream workflows. Any byte-level divergence is a downstream regression.

## Decision

**Strict bit-identical parity** is the primary acceptance criterion for every phase. Performance is informational only.

## Rationale

- `.prn` output is a CSV consumed by other tools that parse columns 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 strictly. Even reordering would silently break consumers.
- PS `Sort-Object` post-processing is alphabetical OrdinalIgnoreCase. The C app uses `setlocale(LC_ALL, "C")` + `strcasecmp` to match byte-for-byte.
- The recent `%{version}` regression demonstrated that even invisible runspace-state shifts cause cascading downstream noise. We will not accept a port that's "almost identical".

## Consequences

- The parity harness (FRD-016) is mandatory at every phase exit gate.
- Volatile fields are explicitly enumerated and soft-diffed: column 4 (`UrlHealth`, HTTP status, changes day-to-day), column 7 (`HealthUpdateURL` HTTP status). Everything else is strict.
- Task-assignment ordering (ADR-0004) is constrained.
- HTTP retry semantics (per-host User-Agent / Referer) are preserved verbatim.
- Performance: 3-hour PS runs are acceptable to mirror. A C runtime of 30 minutes is welcomed but not required. A C runtime of 4 hours is acceptable.

## Enforcement

- CI gate: PR builds run `tools/parity-diff.sh`; warnings during the 30-day soft period, mandatory after.
- If a bug requires *changing* the PS behaviour, the change goes upstream into the PS script first, then re-ports into C, with a new spec status transition (`Drifted` → `Implemented`). Never the other way around.

## Considered alternatives

- **Performance-first**: rejected; downstream consumer fragility outweighs runtime savings.
