---
agent: conflict-detector
---

# Detect Dependency Conflicts

## Mission

Analyze the populated dependency graph to detect missing dependency declarations, virtual provides gaps, and API constellation conflicts. Produce deduplicated patch sets for spec-patcher to apply.

## Step-by-Step Workflow

### 1. Read and understand the dependency graph

**ALWAYS start by reviewing:**

- The graph node count (current vs. latest packages)
- The graph edge count (spec-declared vs. inferred)
- Virtual provides (API version constants)
- The Docker SDK-to-API version mapping (`data/docker-api-version-map.csv`)

### 2. Run Phase 3a: Missing dependency detection

For each package node:

- Compare inferred edges (GOMOD, PYPROJECT, TARBALL) against declared `Requires:` edges (SPEC)
- For each inferred dependency not covered by an existing `Requires:`:
  - Verify the target package exists as a graph node
  - Create a `SpecPatch` record: `Requires: <target-package>`
  - Include version constraint if available from go.mod (`>= X.Y.Z`)
  - Assign severity: CRITICAL for direct runtime imports, IMPORTANT for indirect
  - Attach evidence: source file path, module path, line from go.mod

### 3. Run Phase 3b: API constellation detection

For Docker/containerd ecosystem packages:

- Identify all packages that import Docker SDK modules
- Map SDK versions to API versions using `docker-api-version-map.csv`
- For each consumer:
  - **Lower-bound conflict**: `Conflicts: docker-engine < <min-api-version-engine>`
    - The consumer requires at least this API version
  - **Upper-bound conflict**: `Conflicts: docker-engine > <max-api-version-engine>`
    - The latest SDK exceeds the current engine's max supported API
  - **Virtual provide**: `Provides: docker-api = <version>` for API providers
- Validate version strings are well-formed semver

### 4. Run Phase 3c: Cross-version comparison

If both current and latest version nodes exist:

- For each package present in both current and latest:
  - Compare inferred dependency sets
  - Flag new dependencies introduced in the latest version
  - Flag dependencies removed in the latest version
  - For new dependencies: verify they are satisfiable by Photon packages
  - Flag unsatisfiable new dependencies as constellation conflicts

### 5. Run Phase 3d: Global deduplication

Before finalizing:

- Collect ALL patches from Phases 3a-3c
- Deduplicate by `(package, directive, value)` tuple
- When multiple sources produce the same patch, keep the strongest evidence
- Remove patches that would duplicate existing spec declarations
- Verify: zero duplicate `(directive, value)` pairs per package

### 6. Produce output

- Attach all patch sets to the graph for spec-patcher
- Attach all conflict records to the graph for the manifest
- Report: total issues, patches by severity, API constellations found

## Quality Checklist

- [ ] Every missing dependency finding includes evidence (go.mod line, pyproject entry)
- [ ] Every API constellation conflict includes SDK version and API version numbers
- [ ] Lower-bound conflicts use `Conflicts: <pkg> < <version>` format
- [ ] Upper-bound conflicts use `Conflicts: <pkg> > <version>` format
- [ ] Virtual provides use `Provides: <name> = <version>` format
- [ ] Global deduplication eliminates all duplicate `(directive, value)` pairs
- [ ] Cross-version analysis correctly identifies new vs. removed dependencies
- [ ] Severity assignment is consistent (CRITICAL/IMPORTANT/INFORMATIONAL)
- [ ] No false positives: every flagged issue is a genuine dependency gap
- [ ] Patch sets are ordered by severity, then directive type, then alphabetically
