# Product Requirements Document (PRD)

**Project**: photonos-package-report (C port)
**Document version**: 1.0
**Status**: Reviewed
**Authors**: pm agent (drafted), devlead agent (reviewed)

---

## 1. Purpose

`photonos-package-report.ps1` is a 5,522-line PowerShell tool that drives Photon OS package supply-chain visibility: it parses every RPM `.spec` file across 7 Photon branches, resolves upstream source URLs, probes their health, detects new releases, generates URL-health and package-diff reports, and produces the `.prn` outputs the rest of the Photon-OS tooling consumes.

It encodes hard-won institutional knowledge in nearly every line: per-package overrides, per-host HTTP quirks (Referer headers, User-Agent strings, FTP fallbacks), version-comparison rules for date-based / OpenJDK / patchlevel-suffixed versions, an embedded 850-row lookup table for non-canonical `Source0` URLs, ~200 per-spec hand-coded conditionals, and the parallel-runspace orchestration that ties it all together.

Today's risks of remaining on PowerShell:
- **Maintainability**: PowerShell parallel runspaces have produced repeat regressions (most recently the `%{version}` substitution silently breaking due to runspace state).
- **Compute cost**: 3-hour runs per dispatch, all in interpreted PowerShell.
- **Single-point fragility**: one PS bug breaks every downstream consumer (snyk-analysis, package-classifier, gating-conflict-detection, …).

A pure C port shifts the canonical implementation to a statically-typed compiled binary while preserving every line of accumulated knowledge.

## 2. Scope

### In scope

- 1:1 functional migration of every PowerShell function (22 top-level + 7 nested in `CheckURLHealth`).
- Bit-identical `.prn` output (12 columns, exact bytes, exact sort order) for every fixture SPEC.
- Embedded 850-row `Source0LookupData` table (extracted from PS source at build time via bash+awk, no Python).
- All ~200 per-spec override blocks ported as hand-written C functions in a dispatch table.
- Parallel orchestration mirroring `ForEach-Object -Parallel` semantics: 20-worker pool, deterministic task ordering, per-thread state isolation, `flock`-protected `.prn` appends.
- libcurl-backed HTTP HEAD/GET with per-host User-Agent and Referer overrides preserved from PS.
- `git`/`tar` shell-outs (matching PS pattern) for repo clones and SRPM extraction.
- Side-by-side CI: `.github/workflows/package-report.yml` runs both PS and C and diffs their output.
- Retirement plan: PS script moves to `staging/legacy/` once C app demonstrates ≥90 days of strict-diff-clean parity.

### Out of scope (v1)

- Performance optimisation beyond what C naturally provides (no algorithmic refactoring).
- Cross-platform support — Photon-only build (ADR-0008).
- New features beyond what the PS script does today.
- Replacing the PS-side macro extractor / spec analyzer — the C port consumes `.spec` files exactly as PS does.
- Rewriting downstream consumers (snyk-analysis, package-classifier, etc.) — they keep consuming `.prn` files identically.

## 3. Goals & Success Criteria

### Goals

- **G1**: Eliminate the runspace-state class of regressions by moving to pthreads with explicit state isolation.
- **G2**: Make the package-report pipeline auditable — every byte of output traces back to a typed function call.
- **G3**: Preserve the knowledge in the script verbatim; no line removed without an ADR justifying it.
- **G4**: Reduce maintenance burden by letting future PS-side fixes flow through a tiny extraction layer (Source0LookupData) automatically.

### Success criteria

- **SC1**: For every committed `photonos-urlhealth-<branch>_<ts>.prn`, the C app produces a byte-identical file on the same inputs (volatile columns 4 and 7 — HTTP status — soft-diffed).
- **SC2**: Side-by-side CI runs for ≥90 days with strict-diff = 0 (after a 30-day soft-only grace period followed by 30 days of strict-warning).
- **SC3**: `photonos-package-report --help` output is parseable to the same parameter set as `pwsh -File photonos-package-report.ps1 -?`.
- **SC4**: Build time on a stock Photon 5 runner ≤ 60 seconds; runtime within ±50% of PS (informational only — bit-identical is the primary constraint).
- **SC5**: Every function in the PS script has a 1:1 named C translation unit with a unit test that compares against a PS-captured trace.

## 4. Functional requirements

Each FR maps to one or more FRDs (`specs/features/FRD-NNN-*.md`).

| Req | Title | FRD |
|---|---|---|
| REQ-1 | CLI parameter block parity | FRD-001 |
| REQ-2 | SPEC parsing (Get-AllSpecs) | FRD-002 |
| REQ-3 | Source0Lookup data embedding | FRD-003 |
| REQ-4 | Macro substitution engine | FRD-004 |
| REQ-5 | Per-spec override dispatch (~200 hooks) | FRD-005 |
| REQ-6 | URL health probe (libcurl HEAD) | FRD-006 |
| REQ-7 | GitHub tag detection | FRD-007 |
| REQ-8 | GitLab tag detection | FRD-008 |
| REQ-9 | Koji / Fedora SRPM resolver | FRD-009 |
| REQ-10 | Version-comparison engine | FRD-010 |
| REQ-11 | CheckURLHealth orchestrator | FRD-011 |
| REQ-12 | GitPhoton (clone/fetch reports/photon-<release>) | FRD-012 |
| REQ-13 | Parallel runspace mirror (pthread pool + flock) | FRD-013 |
| REQ-14 | `.prn` row assembly + sort | FRD-014 |
| REQ-15 | GenerateUrlHealthReports orchestrator | FRD-015 |
| REQ-16 | Parity harness (PS-vs-C diff) | FRD-016 |

## 5. Non-functional requirements

- **NFR-1 (bit-identical)**: see G3/SC1. Enforced by FRD-016.
- **NFR-2 (Photon-only)**: ADR-0008. Build uses `tdnf` deps; no portability shims.
- **NFR-3 (no Python)**: ADR-0005. Build pipeline is POSIX shell + awk only.
- **NFR-4 (Claude Code only for agents)**: ADR-0011.
- **NFR-5 (TLS 1.2 floor)**: matches the PS script's explicit setting at L 5030.
- **NFR-6 (locale-independent sort)**: `setlocale(LC_ALL, "C")` at startup so `strcasecmp` and `qsort` produce bytes identical to PS `Sort-Object` in OrdinalIgnoreCase mode.

## 6. Constraints

- **C1**: PS source-of-truth must not be edited from this sub-project. Bugfixes go upstream first, then re-port.
- **C2**: Every commit must reference at least one FRD and one ADR (commit-msg hook).
- **C3**: Phase exit gates are mandatory; no skipping ahead.
- **C4**: Bit-identical regressions block CI strictly after the 90-day side-by-side window closes.

## 7. Stakeholders

- **End consumers** of `.prn` output: snyk-analysis, package-classifier, gating-conflict-detection, upstream-source-code-dependency-scanner workflows.
- **Maintainer** (single): dcasota.
- **Runtime**: the self-hosted GitHub Actions runner on this machine.

## 8. Retirement plan

After 90 consecutive days of strict-diff-clean side-by-side runs (FRD-016 reporting), `photonos-package-report.ps1` is moved to `staging/legacy/photonos-package-report.ps1` and the workflow YAML stops invoking it. The C binary becomes the sole producer of `.prn` outputs.

## 9. Open items (to be addressed before Phase 1)

None — all five open items from planning have been answered and locked into ADRs.

---

## Review notes (devlead agent, Status: Reviewed)

- Technical feasibility: confirmed. All dependencies (libcurl, pcre2, json-c, pthread, libarchive) are available as Photon RPMs.
- Risk register (`specs/tasks/README.md` §risks) acknowledges the high-risk items (substitution-order, parallel-runspace mirror, version comparison).
- Bit-identical requirement is enforced via FRD-016 and the side-by-side CI gate. Acceptable.
- Phase sequencing is dependency-clean; no forward references.
- Estimated effort: ~40 tasks across 9 phases. Realistic for an iterative, spec-gated rollout.
