# Upstream Source Code Dependency Scanner — Technical Tasks

## Task Overview

### Phase 1: Parsing and Core Analysis (Tasks 001-003)

| Task | Description | Complexity | Dependencies | Status |
|------|-------------|------------|--------------|--------|
| 001 | Full RPM directive parser (BuildConflicts, Enhances, qualifiers, arch/OS) | Medium | None | Complete |
| 002 | Go module analysis from git clones with version matching | Medium | 001 | Complete |
| 003 | Source tarball extraction and analysis module | Medium | 002 | Complete |

### Phase 2: Orchestration and Detection (Tasks 004-006)

| Task | Description | Complexity | Dependencies | Status |
|------|-------------|------------|--------------|--------|
| 004 | Dual-version orchestration (Phase 1a/1b/2a-2e, SPECS_NEW, bIsLatest) | High | 001, 002, 003 | Complete |
| 005 | API constellation detection (Docker SDK/API mapping, cross-version) | High | 004 | Complete |
| 006 | Global deduplication in add_patch_to_set() and accurate issue counting | Low | 005 | Complete |

### Phase 3: Hardening and CI (Tasks 007-009)

| Task | Description | Complexity | Dependencies | Status |
|------|-------------|------------|--------------|--------|
| 007 | Security hardening — all 10 CVE-class fixes | High | 001-006 | Complete |
| 008 | GitHub Actions CI workflow with full parameter set | Medium | 004 | Complete |
| 009 | Security compliance documentation (MITRE/OWASP/NIST) | Low | 007 | Complete |

## Quality Gates

Before marking any task complete:

- [ ] Scanner builds without warnings (`cmake --build . -- -Wall -Wextra`)
- [ ] JSON manifest validates against `depfix-manifest-schema.json`
- [ ] Quality rubric MUST criteria all pass
- [ ] No duplicate directives in any patched spec file
- [ ] No false positives on known dependency cases (docker-compose, calico, kubernetes-dns)
- [ ] All temp files cleaned up after extraction

## Current Status

- **Tasks 001-009**: Complete
- **Dual-version scan**: Validated against Photon 5.0 with SPECS_NEW

**Reference Scan Results (5.0)**:
- Specs scanned: 3,475 (current + latest)
- Specs patched: 46
- Issues detected: 145+ missing dependencies
- API conflicts: Docker SDK-to-API version mapping validated

**Last Updated**: 2026-03-12
