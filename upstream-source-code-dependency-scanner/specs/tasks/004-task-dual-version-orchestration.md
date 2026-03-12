# Task 004: Dual-Version Orchestration

**Complexity**: High
**Dependencies**: 001, 002, 003
**Status**: Complete
**Requirement**: REQ-4 (Dual-Version Analysis)
**Feature**: FRD-dual-version
**ADR**: ADR-0003

---

## Description

Implement the multi-phase orchestration pipeline that analyzes both the current release specs (from `SPECS/`) and the latest version specs (from `SPECS_NEW/`), merging results with proper tagging and deduplication.

### Phase Execution Order

| Phase | Description | Source |
|-------|-------------|--------|
| 1a | Parse current release spec files from `--specs-dir` | `spec_parse_directory()` |
| 1b | Parse latest version specs from `--specs-new-dir` (`SPECS_NEW/`) | `spec_parse_directory()` + `bIsLatest = 1` tagging |
| 2a | Go module analysis from upstream clones | `gomod_analyze_clones()` |
| 2b | Python dependency analysis from clones | `pyproject_analyze_clones()` |
| 2c | API version constant extraction from source | `api_version_extract()` + `virtual_resolve_edges()` |
| 2d | Tarball analysis for `SOURCES_NEW/` (latest version tarballs) | `analyze_tarball_sources()` |
| 2e | Tarball analysis for current release `photon_sources/1.0/` | `analyze_tarball_sources()` |

### SPECS_NEW Parsing and bIsLatest Tagging

After Phase 1b parses `SPECS_NEW/`, all nodes added from index `dwLatestNodesStart` onward are tagged with `bIsLatest = 1`. This enables downstream detection to distinguish current-release vs. latest-version nodes for cross-version constellation analysis.

## Implementation Details

- **Source file**: `src/main.c` (lines 120-280)
- **CLI flags**: `--specs-dir`, `--specs-new-dir`, `--upstreams-dir`, `--sources-dir`, `--branch`, `--prn-file`
- **Data files**: `gomod-package-map.csv`, `api-version-patterns.csv`, `docker-api-version-map.csv`
- **Key variables**: `dwLatestNodesStart` (Phase 1b start index), `dwPhase1Edges` (spec-only edge count), `dwSpecsScanned` (total nodes)
- **Logging**: Each phase logs `[Phase Nx]` start/done with node/edge counts

## Acceptance Criteria

- [ ] Phase 1a populates graph with current spec nodes and edges
- [ ] Phase 1b adds SPECS_NEW nodes with `bIsLatest = 1` tag
- [ ] Phase 2a-2c run only when `--upstreams-dir` is provided
- [ ] Phase 2d runs against `SOURCES_NEW/` within upstreams directory
- [ ] Phase 2e runs against `--sources-dir` for current release tarballs
- [ ] Missing directories are gracefully skipped with `[Phase Nx] Skipped:` log
- [ ] Summary output shows node breakdown (current vs. latest)
- [ ] All 7 Photon branches can be processed: 3.0, 4.0, 5.0, 6.0, master, dev, common
- [ ] Phase ordering ensures clone analysis precedes tarball analysis (clone-skip logic works)

## Testing Requirements

- [ ] Run dual-version scan on 5.0 branch — verify both current and latest nodes
- [ ] Verify `bIsLatest` is `0` for SPECS/ nodes and `1` for SPECS_NEW/ nodes
- [ ] Run without `--specs-new-dir` — verify Phase 1b is skipped cleanly
- [ ] Run without `--upstreams-dir` — verify Phases 2a-2d are all skipped
- [ ] Verify summary output: node counts, edge breakdown (spec-declared vs. inferred)
- [ ] Full 5.0 scan produces `specs_scanned: 3475`, `specs_patched: 46`
