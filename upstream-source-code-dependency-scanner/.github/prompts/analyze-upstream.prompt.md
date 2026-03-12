---
agent: scanner-analyzer
---

# Analyze Upstream Sources

## Mission

Analyze upstream source code to discover actual runtime dependencies from Go modules, Python projects, and API version constants. This covers Phases 2a through 2e of the scan pipeline.

## Step-by-Step Workflow

### 1. Validate inputs

- Confirm `--upstreams-dir` points to a valid upstream directory
- Check for `clones/` subdirectory (required for Phases 2a-2c)
- Check for `SOURCES_NEW/` subdirectory (for Phase 2d)
- If `--sources-dir` is provided, verify it exists (for Phase 2e)
- Verify `data/gomod-package-map.csv` is loadable
- Verify `data/api-version-patterns.csv` is loadable
- If `--prn-file` is provided, verify the PRN mapping file is loadable

### 2. Run Phase 2a: Go module analysis from clones

For each Go package in the graph (has `BuildRequires: go` or `BuildRequires: golang`):

- Locate the upstream clone via PRN mapping or directory naming convention
- Parse `go.mod` to extract all `require` directives
- Map Go module paths to Photon package names using `gomod-package-map.csv`
- Create `EDGE_SRC_GOMOD` edges for each successfully mapped dependency
- Record unmapped modules for reporting

### 3. Run Phase 2b: Python project analysis

For each Python package:

- Locate `pyproject.toml` (PEP 621) or `setup.cfg` in the clone
- Extract dependencies from `[project.dependencies]` or `install_requires`
- Map Python package names to Photon package names
- Create `EDGE_SRC_PYPROJECT` edges

### 4. Run Phase 2c: API version extraction

- Load patterns from `data/api-version-patterns.csv`
- For each pattern, grep source files in clone directories for version constants
- Extract Docker API version, containerd API version, and similar
- Create virtual provides in the graph (e.g., `docker-api = 1.52`)
- Resolve graph edges that target virtual provides

### 5. Run Phase 2d: Tarball analysis (SOURCES_NEW)

For Go packages not already analyzed from clones:

- Find matching `.tar.gz` in `SOURCES_NEW/`
- Securely extract (no shell interpolation: use `fork()/execlp("tar", ...)`)
- Parse extracted `go.mod` and map dependencies
- Create `EDGE_SRC_TARBALL` edges
- Clean up temporary extraction directories

### 6. Run Phase 2e: Tarball analysis (current sources)

For remaining Go packages still without inferred edges:

- Find matching `.tar.gz` in `photon_sources/1.0/` (via `--sources-dir`)
- Same secure extraction and analysis as Phase 2d
- Create `EDGE_SRC_TARBALL` edges

### 7. Report results

Output summary:

- Go packages analyzed from clones vs. tarballs
- Python packages analyzed
- API version constants discovered
- Virtual provides created
- Total inferred edges added (by source type)
- Unmapped Go modules (for gomod-package-map.csv updates)

## Quality Checklist

- [ ] All Go packages with `BuildRequires: go` were attempted for analysis
- [ ] Go module mapping uses `gomod-package-map.csv`, not hardcoded names
- [ ] Tarball extraction uses `fork()/execlp()`, never `system()`
- [ ] No shell interpolation in any file path construction
- [ ] Temporary extraction directories are cleaned up after use
- [ ] Edge provenance is correctly set (GOMOD, PYPROJECT, TARBALL, API_CONSTANT)
- [ ] Virtual provides include evidence strings (source file, line number)
- [ ] Packages already analyzed from clones are skipped in tarball phases
- [ ] PRN mapping is used when available for clone directory resolution
- [ ] API version patterns are loaded from CSV, not hardcoded
