# Feature Requirement Document: CI Workflow Integration

**Feature ID**: FRD-ci-integration
**Related PRD Requirements**: REQ-9
**Status**: Planned
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Run the dependency scanner as a GitHub Actions workflow with configurable parameters, producing structured summary tables and uploading scan artifacts for downstream consumption.

### Value Proposition

Manual invocation of the scanner is error-prone and not reproducible. CI integration ensures every branch is scanned on a regular schedule (or on-demand), with results surfaced directly in the GitHub Actions summary and artifacts preserved for auditing.

### Success Criteria

- [SC-6] Full 7-branch scan completes within CI timeout (120 minutes)
- Workflow accepts configurable parameters (branches, directories, patch generation)
- Per-branch summary tables are rendered in the GitHub Actions job summary
- Scan artifacts (manifests, graphs, patched specs) are uploaded via `actions/upload-artifact`

---

## 2. Functional Requirements

### 2.1 GitHub Actions Workflow Definition

**Description**: Define a GitHub Actions workflow (`.github/workflows/dependency-scan.yml`) that orchestrates the scanner across all supported Photon branches.

**Supported branches**: `3.0`, `4.0`, `5.0`, `6.0`, `master`, `dev`, `common`

**Workflow triggers**:
- `workflow_dispatch`: Manual trigger with configurable inputs
- `schedule`: Periodic (e.g., weekly) full-scan cron trigger

**Workflow inputs**:

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `branches` | string | `"3.0,4.0,5.0,6.0,master,dev,common"` | Comma-separated list of branches to scan |
| `specs_base_dir` | string | `"/photon"` | Base directory containing `photon-{branch}/SPECS/` |
| `upstreams_base_dir` | string | `"/photon-upstreams"` | Base directory for upstream clones and sources |
| `patch_specs` | boolean | `true` | Whether to generate patched spec files |
| `json_output` | boolean | `true` | Whether to generate enriched dependency graph JSON |

**Acceptance Criteria**:
- Workflow file is valid YAML and passes `actionlint`
- All inputs have sensible defaults for the standard Photon build environment
- Workflow can be triggered manually from the GitHub Actions UI
- Scheduled runs use the same workflow with default inputs

### 2.2 Per-Branch Scan Execution

**Description**: For each branch in the input list, invoke the scanner binary with the appropriate directory paths.

**Command template**:
```bash
./depgraph-deep \
  --specs-dir "${specs_base_dir}/photon-${branch}/SPECS" \
  --specs-new-dir "${specs_base_dir}/photon-${branch}/SPECS_NEW" \
  --upstreams-dir "${upstreams_base_dir}/photon-${branch}" \
  --sources-dir "${specs_base_dir}/photon_sources/1.0" \
  --output-dir "./output/${branch}" \
  --data-dir "./data" \
  --branch "${branch}" \
  --prn-file "${specs_base_dir}/photon-${branch}/package-report.json" \
  --json \
  --patch-specs
```

**Acceptance Criteria**:
- Each branch runs as a separate step within the job (for clear log separation)
- Failure on one branch does not prevent scanning of remaining branches (`continue-on-error: true`)
- Each branch's output is isolated in `./output/{branch}/`
- Scanner binary is built from source in a preceding build step

### 2.3 Summary Table Generation

**Description**: After all branches are scanned, generate a markdown summary table and write it to `$GITHUB_STEP_SUMMARY`.

**Table format**:

| Branch | Specs Scanned | Issues Found | Specs Patched | Virtual Provides |
|--------|--------------|--------------|---------------|------------------|
| 3.0 | 3800 | 42 | 12 | 4 |
| 4.0 | 4100 | 68 | 18 | 6 |
| 5.0 | 4400 | 145 | 44 | 12 |
| ... | ... | ... | ... | ... |

**Data source**: Parse the `=== Summary ===` section from each branch's scanner stderr output.

**Acceptance Criteria**:
- Summary table includes all scanned branches in a single markdown table
- Table is written to `$GITHUB_STEP_SUMMARY` for rendering in the Actions UI
- Zero-issue branches are included (shows completeness)
- Table includes a totals row

### 2.4 Artifact Upload

**Description**: Upload all scan output files as GitHub Actions artifacts for downstream retrieval.

**Artifacts**:

| Artifact Name | Contents | Retention |
|---------------|----------|-----------|
| `depfix-manifests` | `output/*/depfix-manifest-*.json` | 90 days |
| `dependency-graphs` | `output/*/dependency-graph-*.json` | 90 days |
| `patched-specs` | `output/*/SPECS_DEPFIX/**` | 90 days |
| `scan-logs` | Scanner stderr logs for each branch | 30 days |

**Acceptance Criteria**:
- All artifacts are uploaded even if some branches failed
- Artifact names include the run ID or date for uniqueness
- Empty artifacts (no issues found) are still uploaded (proves the scan ran)
- Retention periods are configurable

### 2.5 Build Step

**Description**: Compile the scanner from source before running scans.

**Build requirements**:
- GCC (C11)
- cmake
- json-c-devel

**Build commands**:
```bash
mkdir build && cd build
cmake ..
make -j$(nproc)
```

**Acceptance Criteria**:
- Build step produces the `depgraph-deep` binary
- Build failure fails the entire workflow (no `continue-on-error`)
- Build output is cached or skipped if binary is pre-built

### 2.6 Performance Budget

**Description**: The full 7-branch scan must complete within the CI timeout.

**Budget**:
- Build: ~5 minutes
- Per-branch scan: ~10-15 minutes (dominated by tarball extraction I/O)
- Total: < 120 minutes for all 7 branches

**Acceptance Criteria**:
- Workflow sets `timeout-minutes: 120` at the job level
- Individual branch scans are logged with timing information
- If a branch scan exceeds 30 minutes, it's flagged as slow in the summary

---

## 3. Data Model

### Workflow Configuration

| Parameter | Source | Used By |
|-----------|--------|---------|
| `branches` | Workflow input | Branch loop |
| `specs_base_dir` | Workflow input | `--specs-dir`, `--specs-new-dir` |
| `upstreams_base_dir` | Workflow input | `--upstreams-dir` |
| `patch_specs` | Workflow input | `--patch-specs` flag |
| `json_output` | Workflow input | `--json` flag |

### Output Artifacts

| File Pattern | Producer | Consumer |
|-------------|----------|----------|
| `depfix-manifest-{branch}-{ts}.json` | `manifest_write()` | CI summary parser, downstream tools |
| `dependency-graph-{branch}-deep-{ts}.json` | `json_output_write()` | Graph visualization tools |
| `SPECS_DEPFIX/{branch}/{pkg}/{pkg}.spec` | `spec_patch_all()` | Package maintainers |

---

## 4. Edge Cases

- **Missing branch directory**: If `photon-{branch}/SPECS` doesn't exist for a configured branch, the scanner exits with an error for that branch. `continue-on-error` ensures other branches still run.
- **Empty SPECS_NEW**: Some branches may not have a SPECS_NEW directory. The scanner handles this gracefully (Phase 1b is skipped).
- **Disk space**: Large-scale tarball extraction and JSON output may consume significant disk. The CI runner should have at least 10 GB free.
- **Concurrent workflow runs**: Two triggered scans may race on output directories. Use `concurrency` group in the workflow to serialize runs.
- **PRN file not found**: If `package-report.json` is missing for a branch, the scanner logs a warning and continues without PRN mapping. Clone-to-package resolution falls back to directory name matching.
- **Network failures**: The scanner makes no network calls (deterministic, offline). Git clones must be pre-checked-out.
- **Pre-built binary**: If the scanner binary is provided as a release artifact instead of built from source, the build step can be replaced with a download step.

---

## 5. Dependencies

**Depends On**: FRD-output (produces the artifacts to upload), FRD-dual-version (scanner CLI flags for dual-version analysis), all other FRDs (scanner must implement all features for CI to produce meaningful results)

**Depended On By**: None (terminal feature in the dependency chain)
