# Task 001: Full RPM Spec Directive Parser

**Complexity**: Medium
**Dependencies**: None
**Status**: Complete
**Requirement**: REQ-1 (RPM Spec Parsing)
**Feature**: FRD-spec-parsing
**ADR**: ADR-0001

---

## Description

Implement a complete RPM spec file parser that handles all dependency-related directives as defined by the [RPM 4.20.x specification](https://rpm.org/docs/4.20.x/manual/spec.html). The parser must correctly handle:

1. **All dependency directives**: `Requires`, `BuildRequires`, `Provides`, `Conflicts`, `Obsoletes`, `BuildConflicts`, `Recommends`, `Suggests`, `Supplements`, `Enhances`, `OrderWithRequires`
2. **Qualified Requires**: `Requires(pre)`, `Requires(post)`, `Requires(preun)`, `Requires(postun)`, `Requires(pretrans)`, `Requires(posttrans)`, `Requires(verify)`, `Requires(interp)`, `Requires(meta)` — preserved in `szQualifier` field
3. **Architecture/OS exclusions**: `ExcludeArch`, `ExclusiveArch`, `ExcludeOS`, `ExclusiveOS`, `BuildArch`
4. **Version constraints**: All operators (`=`, `>=`, `>`, `<=`, `<`) with epoch-version-release parsing
5. **Macro expansion**: `%{name}`, `%{version}`, `%{release}`, `%{epoch}` and custom `%define`/`%global` macros
6. **Subpackage handling**: `%package -n subname` and `%package subname` with correct node association
7. **Section tracking**: Header, `%package`, `%description`, `%prep`, `%build`, `%install`, `%check`, `%clean`, `%files`, `%changelog`

## Implementation Details

- **Source file**: `src/spec_parser.c` (812 lines)
- **Header**: `src/spec_parser.h`
- **Entry point**: `spec_parse_directory(DepGraph *pGraph, const char *pszSpecsDir)`
- **Key structures**: `ParseContext` with macro table, subpackage registry, section state machine
- **Edge types**: Mapped to `EdgeType` enum (`EDGE_REQUIRES` through `EDGE_ORDERWITH`)
- **Qualifier storage**: `GraphEdge.szQualifier[MAX_QUALIFIER_LEN]` preserves the qualifier string

## Acceptance Criteria

- [ ] All 11 dependency directive types are parsed and mapped to `EdgeType` values
- [ ] `Requires(post):` preserves qualifier `"post"` in `GraphEdge.szQualifier`
- [ ] `ExcludeArch: aarch64` is stored in `GraphNode.szExcludeArch`
- [ ] Macro expansion resolves `%{name}-%{version}` correctly
- [ ] Subpackages are linked to parent via `GraphNode.szParentPackage`
- [ ] Malformed spec lines are logged but do not crash the parser
- [ ] All SPECS/ subdirectories are recursively scanned

## Testing Requirements

- [ ] Parse `docker.spec` — verify `BuildRequires: go`, `Provides: docker-engine`, subpackages
- [ ] Parse a spec with `BuildConflicts:` and `Enhances:` — verify edge types
- [ ] Parse a spec with `Requires(post): /sbin/ldconfig` — verify qualifier preserved
- [ ] Parse a spec with `ExclusiveArch: x86_64` — verify node field populated
- [ ] Parse a spec with complex macros — verify macro expansion
- [ ] Scan full 5.0 SPECS/ directory — no parse crashes, node/edge counts match expectations
