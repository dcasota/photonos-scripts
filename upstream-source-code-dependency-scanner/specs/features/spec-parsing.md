# Feature Requirement Document: Spec Parsing -- Full RPM Spec Directive Parsing

**Feature ID**: FRD-spec-parsing
**Related PRD Requirements**: REQ-1
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Parse all dependency-related RPM spec directives from `.spec` files to build a complete, typed dependency graph of the Photon OS package ecosystem. This is the foundational data-ingestion layer that feeds every downstream analysis phase.

### Value Proposition

RPM spec files encode the full dependency topology of the distribution. Incomplete parsing leads to false negatives downstream -- every missed directive type is a class of issues that the scanner cannot detect. Full coverage ensures the graph is authoritative.

### Success Criteria

- All 11 `EdgeType` values in `graph.h` are populated from corresponding spec directives
- Qualifier strings (`pre`, `post`, `preun`, `postun`, `pretrans`, `posttrans`, `verify`, `interp`, `meta`) are preserved on `Requires(qualifier):` edges
- Architecture and OS restriction directives (`ExcludeArch`, `ExclusiveArch`, `ExcludeOS`, `ExclusiveOS`, `BuildArch`) are captured on nodes
- Constraint operators (`=`, `>=`, `>`, `<=`, `<`) and version strings are correctly parsed from version-pinned dependencies
- `%package` subpackage directives (including `-n` syntax) create child nodes linked to the parent
- Zero parsing errors on the full Photon 5.0 SPECS directory (~4400 spec files)

---

## 2. Normative RPM Standard References

This feature's parsing rules are grounded in the authoritative RPM specification. See **ADR-0005** (`specs/adr/0005-rpm-spec-standard-compliance.md`) for the full analysis.

### Current: RPM 4.20.x

- [Spec File Format](https://rpm.org/docs/4.20.x/manual/spec.html) -- preamble tags, dependency syntax, `Requires(qualifier):` qualifiers, version constraints, architecture/OS directives
- [Dependencies Basics](https://rpm.org/docs/4.20.x/manual/dependencies.html) -- `Requires:`, `Provides:`, `Conflicts:`, `Obsoletes:`, weak deps (`Recommends:`, `Suggests:`, `Supplements:`, `Enhances:`), `rpmvercmp()` version ordering, epoch syntax `[epoch:]version[-release]`
- [More on Dependencies](https://rpm.org/docs/4.20.x/manual/more_dependencies.html) -- boolean expressions (`and`, `or`, `if`, `with`, `without`, `unless`), scriptlet dependencies, automatic dependency generation
- [Boolean Dependencies](https://rpm.org/docs/4.20.x/manual/boolean_dependencies.html) -- nesting rules, `Provides:` cannot contain boolean expressions

### Future: RPM 6.0.x

- [Spec File Format](https://rpm.org/docs/6.0.x/manual/spec.html) -- dependency directive grammar is **identical** to 4.20.x; editorial fixes only
- [Dependencies Basics](https://rpm.org/docs/6.0.x/manual/dependencies.html) -- unchanged from 4.20.x
- [More on Dependencies](https://rpm.org/docs/6.0.x/manual/more_dependencies.html) -- unchanged from 4.20.x

**Key finding**: No code changes are required for RPM 6.0.x forward compatibility. All dependency directives, qualifiers, operators, and version syntax are identical between the two versions.

---

## 3. Functional Requirements

### 3.1 Directive Recognition

**Description**: The parser must recognize and classify all dependency-related directives defined in the [RPM Spec Reference (4.20.x)](https://rpm.org/docs/4.20.x/manual/spec.html).

**Directive-to-EdgeType Mapping**:

| RPM Directive | EdgeType Enum | Notes |
|--------------|---------------|-------|
| `Requires:` | `EDGE_REQUIRES` | Including `Requires(qualifier):` |
| `BuildRequires:` | `EDGE_BUILDREQUIRES` | |
| `Provides:` | `EDGE_PROVIDES` | |
| `Conflicts:` | `EDGE_CONFLICTS` | |
| `Obsoletes:` | `EDGE_OBSOLETES` | |
| `Recommends:` | `EDGE_RECOMMENDS` | Weak forward dependency |
| `Suggests:` | `EDGE_SUGGESTS` | Weak forward dependency |
| `Supplements:` | `EDGE_SUPPLEMENTS` | Weak reverse dependency |
| `Enhances:` | `EDGE_ENHANCES` | Weak reverse dependency |
| `BuildConflicts:` | `EDGE_BUILDCONFLICTS` | |
| `OrderWithRequires:` | `EDGE_ORDERWITH` | Ordering hint only |

**Inputs**: `.spec` files under a `SPECS/` directory tree.

**Outputs**: `GraphNode` and `GraphEdge` entries in the `DepGraph`.

**Acceptance Criteria**:
- All directives in the table above are parsed (case-insensitive match)
- Multi-value lines (e.g., `Requires: foo >= 1.0, bar`) are split into separate edges
- Lines continued with `\` are concatenated before parsing
- All edges carry `nSource = EDGE_SRC_SPEC`

### 3.2 Qualifier Preservation

**Description**: `Requires(qualifier):` directives must preserve the qualifier string in the `szQualifier` field of the edge.

**Supported qualifiers**: `pre`, `post`, `preun`, `postun`, `pretrans`, `posttrans`, `verify`, `interp`, `meta`.

**Acceptance Criteria**:
- `Requires(post): /sbin/ldconfig` produces an edge with `szQualifier = "post"`
- `Requires(pre,post): shadow-utils` produces edges with qualifiers correctly captured
- Bare `Requires:` produces an edge with empty `szQualifier`

### 3.3 Version Constraint Parsing

**Description**: Version-pinned dependencies (e.g., `Requires: foo >= 2.0`) must be decomposed into a `ConstraintOp` and constraint version string.

**Supported operators**: `=` (`CONSTRAINT_EQ`), `>=` (`CONSTRAINT_GE`), `>` (`CONSTRAINT_GT`), `<=` (`CONSTRAINT_LE`), `<` (`CONSTRAINT_LT`).

**Acceptance Criteria**:
- `Requires: docker >= 28.0` → `nConstraintOp = CONSTRAINT_GE`, `szConstraintVer = "28.0"`
- `Conflicts: docker-engine < 25.0` → `nConstraintOp = CONSTRAINT_LT`, `szConstraintVer = "25.0"`
- Unversioned `Requires: bash` → `nConstraintOp = CONSTRAINT_NONE`

### 3.4 Architecture and OS Directives

**Description**: Architecture and OS restriction directives must be captured as node-level metadata.

**Directives**:
- `ExcludeArch:` → `szExcludeArch`
- `ExclusiveArch:` → `szExclusiveArch`
- `ExcludeOS:` → `szExcludeOS`
- `ExclusiveOS:` → `szExclusiveOS`
- `BuildArch:` → `szBuildArch`

**Acceptance Criteria**:
- `BuildArch: noarch` populates `szBuildArch = "noarch"` on the node
- `ExclusiveArch: x86_64 aarch64` populates `szExclusiveArch = "x86_64 aarch64"`
- Nodes carry their arch/OS restrictions for downstream filtering

### 3.5 Subpackage Handling

**Description**: `%package` directives define subpackages that become child nodes in the graph.

**Acceptance Criteria**:
- `%package devel` creates a node named `{parent}-devel` with `bIsSubpackage = 1` and `szParentPackage = "{parent}"`
- `%package -n libfoo` creates a node named `libfoo` (explicit name override)
- Dependencies declared in subpackage sections are attributed to the correct subpackage node
- `Name:`, `Version:`, `Release:`, `Epoch:` from the preamble are inherited by subpackages

### 3.6 Directory Traversal

**Description**: `spec_parse_directory()` must recursively scan a SPECS/ directory tree, parsing every `.spec` file found.

**Acceptance Criteria**:
- Handles nested `SPECS/{package}/{package}.spec` layout
- Skips non-`.spec` files silently
- Reports parse errors on stderr but continues scanning remaining files
- Returns total error count

---

## 4. Data Model

### Node Fields (Spec-Parsing-Specific)

| Field | Type | Max Size | Description |
|-------|------|----------|-------------|
| `szName` | char[] | 256 | Package or subpackage name |
| `szVersion` | char[] | 64 | Version string from `Version:` |
| `szRelease` | char[] | 64 | Release string from `Release:` |
| `szEpoch` | char[] | 64 | Epoch string from `Epoch:` |
| `szSpecPath` | char[] | 512 | Filesystem path to the `.spec` file |
| `szParentPackage` | char[] | 256 | Parent package name (empty if main) |
| `bIsSubpackage` | uint32_t | -- | 1 if subpackage, 0 if main |
| `szBuildArch` | char[] | 64 | `BuildArch:` value |
| `szExcludeArch` | char[] | 256 | `ExcludeArch:` value |
| `szExclusiveArch` | char[] | 256 | `ExclusiveArch:` value |
| `szExcludeOS` | char[] | 128 | `ExcludeOS:` value |
| `szExclusiveOS` | char[] | 128 | `ExclusiveOS:` value |

### Edge Fields (Spec-Parsing-Specific)

| Field | Type | Max Size | Description |
|-------|------|----------|-------------|
| `nType` | EdgeType | -- | One of 11 enum values |
| `nSource` | EdgeSource | -- | Always `EDGE_SRC_SPEC` for this feature |
| `szTargetName` | char[] | 256 | Raw target package name |
| `nConstraintOp` | ConstraintOp | -- | Version comparison operator |
| `szConstraintVer` | char[] | 64 | Version constraint string |
| `szQualifier` | char[] | 32 | Qualifier for `Requires(qual):` |

---

## 5. Edge Cases

- **Macro-expanded names**: `%{name}-devel` in `Provides:` should resolve to the literal `{name}-devel` string (macro expansion is not in scope; raw text is captured).
- **Conditional directives**: `%if`, `%ifarch`, `%ifos` blocks may gate directives. Current implementation captures all directives regardless of conditionals (conservative approach -- no false negatives).
- **Empty dependency values**: `Requires:` with no package name after it is silently skipped.
- **Epoch-prefixed versions**: `Requires: foo = 1:2.0-3` must correctly parse the epoch component.
- **Spec files with syntax errors**: Parsing continues past malformed lines; errors are logged to stderr.
- **Duplicate directives**: Multiple `Requires: bash` lines in the same spec produce multiple edges (deduplication is handled by FRD-deduplication at the patch phase).

---

## 6. Dependencies

**Depends On**: None (foundational feature)

**Depended On By**: FRD-gomod-analysis (Phase 2 needs Phase 1 nodes), FRD-dual-version (parses both SPECS and SPECS_NEW), FRD-deduplication (deduplicates spec-parsed edges), FRD-output (outputs parsed graph)
