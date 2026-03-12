# Task 002: Go Module Analysis from Git Clones

**Complexity**: Medium
**Dependencies**: 001 (Spec Parser)
**Status**: Complete
**Requirement**: REQ-2 (Go Module Dependency Analysis)
**Feature**: FRD-gomod-analysis

---

## Description

Implement Go module dependency analysis by extracting `require` directives from `go.mod` files found in upstream git clones. The analyzer must:

1. **Clone discovery**: Walk `photon-upstreams/{branch}/clones/` to find Go project clones
2. **PRN-based mapping**: Use the PRN (Package Report) file to map Photon package names to upstream git repository names (e.g., `docker-compose` → `compose` clone directory)
3. **Version-specific checkout**: Use `git show {tag}:go.mod` to extract `go.mod` at the exact version tag matching the spec's `Version:` field
4. **Module-to-package mapping**: Map Go module paths (e.g., `github.com/docker/docker`) to Photon package names (e.g., `docker`) using `gomod-package-map.csv`
5. **Edge generation**: Create `EDGE_SRC_GOMOD` edges with `EDGE_REQUIRES` type, including version constraints and evidence strings
6. **Safe temp files**: Use `mkstemp()` for intermediate `go.mod` extraction; clean up unconditionally

## Implementation Details

- **Source file**: `src/gomod_analyzer.c` (370+ lines)
- **Header**: `src/gomod_analyzer.h`
- **Entry point**: `gomod_analyze_clones(DepGraph*, const char *pszClonesDir, const GomodPackageMap*, const PrnMap*)`
- **Helper**: `gomod_parse_file(DepGraph*, const char *pszGomodPath, const char *pszPackageName, const GomodPackageMap*)`
- **Mapping data**: `data/gomod-package-map.csv`
- **Security**: `_is_safe_dir_name()` validates directory names, `fork()/execlp("git", ...)` avoids shell injection

## Acceptance Criteria

- [ ] `go.mod` extracted from git clone at correct version tag
- [ ] All `require` directives parsed (direct and indirect)
- [ ] Module paths mapped to Photon packages via CSV lookup
- [ ] Evidence field contains `"go.mod: github.com/docker/docker v28.5.1"` format
- [ ] Packages without Go `BuildRequires` are skipped
- [ ] Packages without matching clones are gracefully skipped (no error)
- [ ] `mkstemp()` temp files are `unlink()`ed in all code paths (including error paths)
- [ ] No shell metacharacter injection via clone directory names

## Testing Requirements

- [ ] Analyze `docker-compose` clone — verify dependencies on `docker`, `containerd`, `kubernetes`
- [ ] Analyze `calico` clone — verify 15+ inferred dependencies
- [ ] Analyze a package with no `go.mod` — verify graceful skip
- [ ] Verify PRN mapping: `kubernetes-dns` → `dns` clone directory
- [ ] Verify edge evidence string format and version extraction
- [ ] Full clone analysis produces correct edge counts matching reference scan
