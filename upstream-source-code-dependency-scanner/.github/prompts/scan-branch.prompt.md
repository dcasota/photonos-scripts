---
agent: scanner-orchestrator
---

# Full Branch Scan

## Mission

Execute a complete end-to-end dependency scan for a single Photon OS branch. Coordinate all phases from spec parsing through conflict detection to patched spec generation.

## Step-by-Step Workflow

### 1. Determine branch configuration

Identify the target branch and resolve all input paths:

- `SPECS/` directory: `photon-{branch}/SPECS/` (current release specs)
- `SPECS_NEW/` directory: `photon-{branch}/SPECS_NEW/` (latest version specs, if available)
- Upstreams directory: `photon-upstreams/photon-{branch}/`
- Clones directory: `photon-upstreams/photon-{branch}/clones/`
- Sources directory: `photon_sources/1.0/` (current release tarballs)
- SOURCES_NEW directory: `photon-upstreams/photon-{branch}/SOURCES_NEW/` (latest tarballs)
- Data directory: `data/` (CSV mapping files)
- PRN file: `package-report-{branch}.log` (if available)
- Output directory: `output/{branch}/`

### 2. Validate environment

Before invoking any phase:

- Verify the scanner binary is built (`build/depscanner`)
- Verify `SPECS/` directory exists and contains `.spec` files
- Verify `data/gomod-package-map.csv` exists
- Verify `data/api-version-patterns.csv` exists
- Verify `data/docker-api-version-map.csv` exists
- Create output directory if needed

### 3. Execute Phase 1: Spec parsing

Invoke **scanner-analyzer** via `analyze-specs` prompt:

- Phase 1a: Parse current release specs from `SPECS/`
- Phase 1b: Parse latest version specs from `SPECS_NEW/` (if available)
- Validate: node count > 0, edge count > 0

### 4. Execute Phase 2: Upstream analysis

Invoke **scanner-analyzer** via `analyze-upstream` prompt:

- Phase 2a: Go module analysis from clones
- Phase 2b: Python project analysis from clones
- Phase 2c: API version extraction from source code
- Phase 2d: Tarball analysis from SOURCES_NEW
- Phase 2e: Tarball analysis from current sources
- Validate: inferred edge count > 0

### 5. Execute Phase 3: Conflict detection

Invoke **conflict-detector** via `detect-conflicts` prompt:

- Detect missing `Requires:`, `Conflicts:`, `Provides:` directives
- Detect Docker SDK-to-API constellation conflicts
- Perform global deduplication
- Validate: issue count is reported

### 6. Execute output generation

If `--patch-specs` is enabled:

- Invoke **spec-patcher** via `patch-specs` prompt
- Validate: patched specs written to `SPECS_DEPFIX/{branch}/`

Always:

- Write depfix manifest JSON to output directory
- Write enriched dependency graph JSON (if `--json` is enabled)
- Print summary to stderr

### 7. Verify results

Post-scan verification:

- Manifest JSON exists in output directory
- If patching was enabled, `SPECS_DEPFIX/{branch}/` contains patched specs
- No duplicate directives in any patched spec
- Summary statistics are consistent across phases

## Quality Checklist

- [ ] All applicable phases executed in order (1a→1b→2a→2b→2c→2d→2e→3→output)
- [ ] Phase 1a produced nodes and edges (mandatory)
- [ ] Phases 1b and 2a-2e ran if inputs were available (optional but attempted)
- [ ] Phase 3 ran and reported issue count
- [ ] Manifest JSON was produced in the output directory
- [ ] If `--patch-specs` was set, `SPECS_DEPFIX/{branch}/` has patched files
- [ ] If `--json` was set, enriched graph JSON was written
- [ ] No original spec files were modified
- [ ] No duplicate directives in patched specs
- [ ] Scan completed within timeout budget
