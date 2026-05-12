# FRD-009-koji-fedora-srpm: Koji Fedora SRPM resolver

**Feature ID**: FRD-009-koji-fedora-srpm
**Related PRD Requirements**: REQ-9
**Related ADRs**: ADR-0002
**PS source range**: photonos-package-report.ps1 L 1520-1572
**Status**: Accepted
**Last updated**: 2026-05-12

---

## 1. Overview

Fedora SRPM lookup via Koji + tar extract.

This FRD specifies the 1:1 C port of the corresponding section of the PowerShell script. It captures the bit-identical assertions, dependencies, and acceptance tests required for the C implementation to ship.

## 2. Functional requirements

(To be expanded by the dev agent at the start of the phase that implements this FRD; the implementation must be a literal, line-ordered translation of the PS source range above. No reordering, no merging of cases.)

## 3. Bit-identical assertions

- All non-volatile bytes of the implementation's outputs must match PS output exactly.
- The HTTP-status columns (col 4, col 7 of `.prn`) are soft-diffed when this feature touches network calls; everything else is strict.
- Mutations on `$Source0` (and equivalents) execute in the same line order as PS.

## 4. Acceptance tests

- Unit: PS-captured trace dumps for the corresponding function are replayed; C output diffs against PS dump = 0.
- Integration: 10 representative SPECs from photon-5.0/SPECS produce identical `.prn` rows under PS and C.
- (For phases that touch network) Side-by-side fixture replay with cached HTTP responses.

## 5. Dependencies

- Upstream PS source range L 1520-1572.
- The ADRs listed above.
- Predecessor FRDs (declared in `specs/tasks/README.md`).

## 6. Open questions

None at this Status. Re-open if a task surfaces an ambiguity in the PS source.
