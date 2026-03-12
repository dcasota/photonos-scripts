# Task 008: GitHub Actions CI Workflow

**Complexity**: Medium
**Dependencies**: 004
**Status**: Complete
**Requirement**: REQ-9 (CI Workflow Integration)
**Feature**: FRD-ci-integration

---

## Description

Implement a GitHub Actions workflow that runs the upstream dependency scanner as part of CI, with full parameterization for branch selection, directory paths, and output options.

### Workflow Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `branches` | string | `"5.0"` | Comma-separated branch list (e.g., `"3.0,4.0,5.0,6.0,master,dev,common"`) |
| `specs_base_dir` | string | (required) | Base path to `photon-{branch}/SPECS/` directories |
| `upstreams_base_dir` | string | `""` | Base path to `photon-upstreams/` |
| `sources_base_dir` | string | `""` | Base path to `photon_sources/` |
| `data_dir` | string | `"./data"` | Path to CSV mapping data files |
| `output_dir` | string | `"./output"` | Output directory for manifests and patches |
| `patch_specs` | boolean | `true` | Whether to generate patched spec files |
| `write_json` | boolean | `true` | Whether to write enriched dependency graph JSON |
| `prn_file` | string | `""` | Path to PRN package report file |

### Workflow Steps

1. **Checkout** repository
2. **Build** scanner (`cmake -B build && cmake --build build`)
3. **For each branch**: Run scanner with branch-specific paths
4. **Upload artifacts**: Manifests, patched specs, dependency graphs
5. **Generate summary**: Aggregate results across all branches

## Implementation Details

- **Workflow file**: `.github/workflows/scan-upstream-deps.yml`
- **Trigger**: `workflow_dispatch` (manual) with `inputs`, plus `schedule` for nightly runs
- **Build dependencies**: `gcc`, `cmake`, `json-c-devel`
- **Artifacts**: `depfix-manifest-{branch}-{timestamp}.json`, `SPECS_DEPFIX/{branch}/`, `dep-graph-{branch}.json`
- **Exit codes**: Non-zero on build failure; scanner always exits 0 (findings are informational)

### Summary Generation

```
=== Upstream Dependency Scan Summary ===
Branch: 5.0
  Specs scanned:  3475
  Specs patched:  46
  Issues found:   145
```

## Acceptance Criteria

- [ ] Workflow accepts all parameters via `workflow_dispatch.inputs`
- [ ] Scanner builds successfully in CI environment
- [ ] Each branch is scanned independently with correct `--specs-dir` path
- [ ] JSON manifests uploaded as workflow artifacts
- [ ] Patched specs uploaded as workflow artifacts
- [ ] Workflow summary shows per-branch results
- [ ] Full 7-branch scan completes within 120-minute timeout
- [ ] Missing directories (upstreams, sources) cause graceful skip, not failure

## Testing Requirements

- [ ] Trigger workflow with single branch (`5.0`) — verify manifest artifact
- [ ] Trigger workflow with all 7 branches — verify all manifests produced
- [ ] Trigger workflow without `upstreams_base_dir` — verify Phases 2a-2d skip
- [ ] Verify workflow summary includes per-branch statistics
- [ ] Verify artifacts are downloadable and JSON-valid
- [ ] Verify workflow completes within timeout for full scan
