# Task 001: Spec Parser and Inventory Builder

**Dependencies**: None
**Complexity**: Medium
**Status**: Complete

---

## Description

Implement the spec file parser and Phase 0 inventory builder that produces a complete map of all branches, their `build-config.json` parameters, all gated specs, and relocated spec directories.

## Requirements

- Parse `%global build_if` directives from `.spec` files (first 10 lines)
- Extract `Name:`, `Version:`, `Release:`, `%package` directives
- Extract `Requires:` and `BuildRequires:` dependency lists
- Expand `%{name}` macros in subpackage and dependency names
- Build inventory JSON with branch configs, spec lists, and gated subdirectory contents
- Determine `uses_snapshot` from `mainline` vs `subrelease` comparison

## Acceptance Criteria

- [ ] Parses all 1000+ specs in each branch without errors
- [ ] Correctly identifies all 16 SPECS/91/ packages in 5.0 branch
- [ ] Correctly extracts `build_if` gate operator and threshold
- [ ] Inventory JSON includes branch subrelease, mainline, uses_snapshot for each branch
- [ ] Handles architecture-gated specs (e.g., `%{_arch} == "aarch64"`) without crashing

## Implementation

Functions: `parse_spec()`, `is_active()`, `full_package_names()`, `scan_specs()`, `build_inventory()`

## Validation

Run against local build tree and verify:
```
4.0: subrelease=None, specs=1035, gated_subdirs=[]
5.0: subrelease=91, mainline=91, specs=1118, gated_subdirs=['91']
6.0: subrelease=92, mainline=92, specs=1098, gated_subdirs=[]
Common specs: 30
```
