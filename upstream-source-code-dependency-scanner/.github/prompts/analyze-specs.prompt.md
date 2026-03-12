---
agent: scanner-analyzer
---

# Analyze Spec Files

## Mission

Parse all RPM spec files in the target directory to build the initial dependency graph. This covers Phase 1a (current release) and Phase 1b (latest version) of the scan pipeline.

## Step-by-Step Workflow

### 1. Validate inputs

- Confirm the `--specs-dir` argument points to a valid directory containing `.spec` files
- If `--specs-new-dir` is provided, confirm it exists and contains `.spec` files
- Verify the data directory contains required CSV mapping files

### 2. Run Phase 1a: Current release spec parsing

Parse all `.spec` files in `SPECS/`:

- Recursively discover `.spec` files in all subdirectories
- For each spec, extract:
  - Package name, version, release, epoch
  - All dependency directives: `Requires:`, `BuildRequires:`, `Provides:`, `Conflicts:`, `Obsoletes:`, `Recommends:`, `Suggests:`, `Supplements:`, `Enhances:`, `BuildConflicts:`, `OrderWithRequires:`
  - Qualified requires: `Requires(pre):`, `Requires(post):`, `Requires(preun):`, `Requires(postun):`, `Requires(pretrans):`, `Requires(posttrans):`, `Requires(verify):`, `Requires(interp):`, `Requires(meta):`
  - Architecture/OS directives: `ExcludeArch:`, `ExclusiveArch:`, `ExcludeOS:`, `ExclusiveOS:`, `BuildArch:`
  - Subpackage definitions from `%package` sections
- Create graph nodes for each main package and subpackage
- Create graph edges for each declared dependency relationship
- Tag all edges with `EDGE_SRC_SPEC` provenance

### 3. Run Phase 1b: Latest version spec parsing (if applicable)

If `--specs-new-dir` was provided:

- Parse all `.spec` files in `SPECS_NEW/` using the same extraction logic
- Tag all new nodes with `bIsLatest = 1`
- Record the starting node index for latest nodes

### 4. Report results

Output summary statistics:

- Total specs parsed (current + latest)
- Total nodes created (packages + subpackages)
- Total edges created (by directive type)
- Any parse errors encountered (with file paths)

## Quality Checklist

- [ ] All `.spec` files in the target directories were discovered and parsed
- [ ] No spec files were silently skipped (errors are logged with file paths)
- [ ] Every RPM dependency directive type is handled per [rpm.org/docs/4.20.x/manual/spec.html](https://rpm.org/docs/4.20.x/manual/spec.html)
- [ ] Qualified requires preserve their qualifier (pre, post, preun, etc.)
- [ ] Subpackage nodes reference their parent package via `szParentPackage`
- [ ] Latest version nodes are tagged with `bIsLatest = 1`
- [ ] Edge provenance is set to `EDGE_SRC_SPEC` for all parsed directives
- [ ] Architecture/OS exclusion directives are stored on nodes
- [ ] Node count > 0 and edge count > 0 after Phase 1a
