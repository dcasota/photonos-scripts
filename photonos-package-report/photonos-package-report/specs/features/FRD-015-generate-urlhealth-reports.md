# FRD-015-generate-urlhealth-reports: GenerateUrlHealthReports orchestrator

**Feature ID**: FRD-015-generate-urlhealth-reports
**Related PRD Requirements**: REQ-15
**Related ADRs**: ADR-0004
**PS source range**: photonos-package-report.ps1 L 4935-end
**Status**: Accepted
**Last updated**: 2026-05-12

---

## 1. Overview

Top-level branch loop + workspace setup.

This FRD specifies the 1:1 C port of the corresponding section of the PowerShell script. It captures the bit-identical assertions, dependencies, and acceptance tests required for the C implementation to ship.

## 2. Functional requirements

(To be expanded by the dev agent at the start of the phase that implements this FRD; the implementation must be a literal, line-ordered translation of the PS source range above. No reordering, no merging of cases.)

### 2.1 Multi-branch dispatcher (Phase M task M02)

When the hidden `--generate-urlhealth-report <branch>` flag is unset,
the C binary MUST iterate the 7 `-GeneratePh*URLHealthReport` flags
and call `generate_urlhealth_main(&params, "<branch>")` for each
enabled branch:

| Flag | Branch arg |
|---|---|
| `GeneratePh3URLHealthReport`      | `"3.0"`    |
| `GeneratePh4URLHealthReport`      | `"4.0"`    |
| `GeneratePh5URLHealthReport`      | `"5.0"`    |
| `GeneratePh6URLHealthReport`      | `"6.0"`    |
| `GeneratePhCommonURLHealthReport` | `"common"` |
| `GeneratePhDevURLHealthReport`    | `"dev"`    |
| `GeneratePhMasterURLHealthReport` | `"master"` |

Mirrors PS `photonos-package-report.ps1` L 5040-5215 (cluster
orchestrator loop). Per-branch failures (e.g. `parse_directory`
on a missing SPECS tree) are soft — they emit `::warning::` and the
loop continues to the next branch. The process exit code reflects
the last non-zero return from `generate_urlhealth_main`. When no
flag is enabled, exit code is 0 (no-op).

## 3. Bit-identical assertions

- All non-volatile bytes of the implementation's outputs must match PS output exactly.
- The HTTP-status columns (col 4, col 7 of `.prn`) are soft-diffed when this feature touches network calls; everything else is strict.
- Mutations on `$Source0` (and equivalents) execute in the same line order as PS.

## 4. Acceptance tests

- Unit: PS-captured trace dumps for the corresponding function are replayed; C output diffs against PS dump = 0.
- Integration: 10 representative SPECs from photon-5.0/SPECS produce identical `.prn` rows under PS and C.
- (For phases that touch network) Side-by-side fixture replay with cached HTTP responses.

## 5. Dependencies

- Upstream PS source range L 4935-end.
- The ADRs listed above.
- Predecessor FRDs (declared in `specs/tasks/README.md`).

## 6. Open questions

None at this Status. Re-open if a task surfaces an ambiguity in the PS source.
