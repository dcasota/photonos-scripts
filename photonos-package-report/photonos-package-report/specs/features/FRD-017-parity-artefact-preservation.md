# FRD-017-parity-artefact-preservation: Parity artefact preservation + diff analysis

**Feature ID**: FRD-017-parity-artefact-preservation
**Related PRD Requirements**: REQ-16 (parity harness)
**Related ADRs**: ADR-0006, ADR-0009
**PS source range**: n/a (post-run CI tooling only)
**Status**: Draft
**Last updated**: 2026-05-17

---

## 1. Overview

The C-side parity workflow (`package-report-C.yml`) writes `.prn` output to
`${RUNNER_TEMP}/parity-c-wd/scans/` and the GitHub Actions runner cleans
that path at job end. When the parity-diff step reports a strict-fail, the
actual offending `.prn` is no longer available for post-hoc inspection.
PRs investigating regressions are blocked on either re-running the
workflow (~1-2h) or trusting the strict-row count without per-spec
detail.

This FRD specifies:

1. Upload of the C-side `.prn` set as a workflow artifact with a
   meaningful retention window so post-hoc strict-fail analysis is
   possible.
2. A reproducible local diff workflow (`tools/diff_analyzer.py` or
   equivalent) that takes a PS-snapshot's `prn-snapshot/` and a
   C-side artefact, and emits per-branch markdown bucketed by which
   column(s) differ.

## 2. Functional requirements

### 2.1 C-side `.prn` upload (Phase M task M05)

- After the `Run C binary` step in `package-report-C.yml`, before the
  step that diffs against PS-side and before `_temp/` is cleaned, run:

  ```yaml
  - name: Upload C-side .prn
    if: always()
    uses: actions/upload-artifact@v4
    with:
      name: c-side-prn-${{ github.run_id }}
      path: ${{ steps.c_run.outputs.scans }}/photonos-urlhealth-*.prn
      if-no-files-found: warn
      retention-days: 30
  ```

- 30-day retention matches the journal soft-window per ADR-0009.
- `if: always()` ensures the artifact is uploaded even when subsequent
  parity-diff fails — that's exactly when we need the artefact.

### 2.2 Per-branch diff markdown (Phase M task M06)

- `tools/diff_analyzer.py` reads two `.prn` files (PS, C) per branch
  and emits a markdown report with the following sections:
  1. **Summary table** — row counts on each side, byte-identical
     count, divergent count, PS-only specs, C-only specs.
  2. **Diff-signature table** — for each unique tuple of differing
     non-volatile columns, list count + sample spec + sample
     PS/C values.
  3. **Top buckets — full spec lists** — top 8 diff-signature buckets
     with their complete affected-spec list (truncated at 30 with
     remainder count).

- Volatile columns 4 (`UrlHealth`) and 7 (`HealthUpdateURL`) are
  excluded from the signature per ADR-0006.
- One markdown per branch: `docs/prn-analysis/diff-c-vs-ps-photon-<branch>.md`.

## 3. Bit-identical assertions

This FRD describes post-run analysis tooling. It does NOT change `.prn`
output. ADR-0006's bit-identical mandate is unaffected.

## 4. Acceptance tests

- After M05 lands: dispatch a C-side workflow run; verify the artifact
  appears in `gh run view <id>` with 7 `.prn` files. Re-download via
  `gh run download <id> -n c-side-prn-<id>` and confirm file contents
  match what the workflow's `parity-diff` step saw (compare via byte
  diff against a side-by-side local run).
- After M06 lands: the 7 markdown files exist in `docs/prn-analysis/`
  and each opens with a valid summary table. Diff-signature buckets
  total to the journal's strict_rows count for the corresponding
  branch.

## 5. Dependencies

- ADR-0006 (bit-identical priority)
- ADR-0009 (CI parity gate)
- FRD-016 (parity harness)
- Workflow `package-report-C.yml` (Phase 8)

## 6. Open questions

- Should the markdown analyses also commit to master, or are they
  artefact-only / on-demand? Current Draft posits they commit. Open
  to flipping if the docs churn becomes noisy.
