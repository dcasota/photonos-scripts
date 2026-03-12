# Task 003: Source Tarball Extraction and Analysis Module

**Complexity**: Medium
**Dependencies**: 002 (Go Module Analysis)
**Status**: Complete
**Requirement**: REQ-3 (Source Tarball Analysis)
**Feature**: FRD-tarball-analysis
**ADR**: ADR-0002

---

## Description

Implement secure source tarball extraction and analysis for packages where git clones are unavailable. The analyzer extracts `go.mod` from `.tar.gz` (and other archive formats) source tarballs located in `photon_sources/1.0/` and `SOURCES_NEW/` directories.

1. **Tarball discovery**: Match `{package}-{version}.tar.gz` (and `.tgz`, `.tar.bz2`, `.tar.xz`, `.zip`) filenames to graph nodes
2. **Clone-skip logic**: Only analyze packages that `BuildRequires: go` AND have no existing `EDGE_SRC_GOMOD` edges (already analyzed from clone)
3. **Two-pass extraction**: List tarball contents (`tar -tzf --wildcards */go.mod`) to find exact inner path, then extract that file (`tar -xzf -O`)
4. **Safe extraction**: Use `fork()/execlp()` (no `system()`), `mkstemp()` for temp files, `unlink()` on all exit paths
5. **Path validation**: `_is_safe_path_component()` rejects names containing `..`, shell metacharacters, or non-alphanumeric characters beyond `.-_+~`

## Implementation Details

- **Source file**: `src/tarball_analyzer.c` (230+ lines)
- **Header**: `src/tarball_analyzer.h`
- **Entry points**:
  - `tarball_find_source()` — locate tarball by package name + version
  - `tarball_extract_file()` — extract a single file from tarball to temp path
  - `tarball_analyze_gomod()` — full pipeline: find, extract, parse `go.mod`
- **Edge source**: `EDGE_SRC_TARBALL`
- **Security**: `_is_safe_path_component()` at line 16, `mkstemp()` at line 48, `fork()/execlp()` at lines 62/126

## Acceptance Criteria

- [ ] Tarballs in `photon_sources/1.0/` are discovered by `{name}-{version}.tar.gz` pattern
- [ ] Multiple archive extensions supported (`.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.zip`)
- [ ] Packages already analyzed from clones are skipped (no duplicate edges)
- [ ] `go.mod` correctly extracted from nested tarball paths (e.g., `docker-compose-2.32.4/go.mod`)
- [ ] No shell injection possible via package names or tarball paths
- [ ] `_is_safe_path_component()` rejects `../`, `;`, `|`, `$`, backticks
- [ ] All temp files cleaned up via `unlink()` even on extraction failure
- [ ] Non-Go packages are skipped (no `BuildRequires: go` → no analysis)
- [ ] Edge evidence includes `"tarball: {path}"` provenance

## Testing Requirements

- [ ] Extract `go.mod` from a known SOURCES_NEW tarball — verify parsed dependencies
- [ ] Attempt extraction with `name=../etc/passwd` — verify `_is_safe_path_component()` rejects
- [ ] Analyze a tarball with no `go.mod` — verify graceful failure
- [ ] Verify clone-skip: package with both clone and tarball → only clone edges
- [ ] Full tarball scan produces additional edges for packages without clones
- [ ] Verify `mkstemp` temp file is deleted after successful and failed extractions
