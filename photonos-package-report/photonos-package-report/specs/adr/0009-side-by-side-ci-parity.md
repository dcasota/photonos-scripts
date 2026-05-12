# ADR-0009: Side-by-side CI parity for ≥90 days before retirement

**Status**: Accepted
**Date**: 2026-05-12

## Context

A direct cutover from PS to C carries unacceptable risk — invisible regressions could degrade output for days before downstream consumers (snyk-analysis, package-classifier, etc.) start producing wrong reports. The lesson from the recent `%{version}` substitution regression is fresh.

## Decision

After phase 7 (C app produces full output), `.github/workflows/package-report.yml` is modified to run the **PS script first**, then the **C binary** on the same inputs (same SPECs, same SOURCES_NEW/SPECS_NEW state). The PS `.prn` output is committed (as today); the C output goes to a sibling `.prn.c` file. A `tools/parity-diff.sh` step diffs them and writes a verdict to the workflow step summary.

Strict-diff gate timeline:

| Days since side-by-side enabled | Diff verdict treatment |
|---|---|
| 0-30  | **Soft** — informational only, no PR failure |
| 30-60 | **Strict-warning** — divergence appears in step summary, marked yellow, no PR failure |
| 60-90 | **Strict-failure** — PRs that don't already have a green diff fail CI |
| 90+   | **Cutover-ready** — schedule retirement (ADR 0011 sibling task 091) |

## Rationale

- 90 days covers four weekly scheduled runs plus dozens of manual dispatches — enough to surface seasonal data quirks (e.g. holiday-related upstream URL changes).
- Phased strictness lets early divergence be caught and fixed without blocking unrelated PRs.
- Once 90 days of strict-green is established, the parity harness itself becomes a regression detector for future PS-side changes.

## Consequences

- CI run time roughly doubles for the package-report workflow during the side-by-side window — acceptable.
- `tools/parity-diff.sh` is itself spec-described (FRD-016) and tested.
- A new GitHub Actions secret / env var is NOT needed; the existing runner produces both outputs locally.

## Retirement trigger

The retirement PR (Phase 9 task 090) is opened automatically once a workflow run detects 90 consecutive days of strict-green diffs in the journal file `tools/parity-journal.tsv` (committed alongside each run).

## Considered alternatives

- **Direct cutover after Phase 7**: rejected, see Context.
- **Side-by-side forever**: pays double compute cost forever; rejected once parity is proven.
