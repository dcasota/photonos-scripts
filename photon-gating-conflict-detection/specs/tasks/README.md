# Photon OS Gating Conflict Detection -- Technical Tasks

## Task Overview

### Phase 1: Core Implementation (Tasks 001-003)

| Task | Description | Complexity | Dependencies |
|------|------------|------------|--------------|
| 001 | Spec parser and inventory builder | Medium | None |
| 002 | Dual-format output and schema validation | Low | 001 |
| 003 | GitHub Actions workflow integration | Medium | 002 |

### Phase 2: Constellation Detectors (Tasks 004-006)

| Task | Description | Complexity | Dependencies |
|------|------------|------------|--------------|
| 004 | C1 + C2 detectors (spec pairs, subpackages, deps) | High | 001 |
| 005 | C3 + C3+ detectors (boundary, upgrade conflict) | High | 004 |
| 006 | C4 + C5 + C6 detectors (cross-branch, FIPS, URLs) | Medium | 001 |

### Phase 3: Validation and Documentation (Tasks 007-008)

| Task | Description | Complexity | Dependencies |
|------|------------|------------|--------------|
| 007 | Test against commit 6b7bc7c reference case | Medium | 004, 005 |
| 008 | ADR-0001 and ADR-0002 documentation | Low | 007 |

## Quality Gates

Before marking any task complete:

- [ ] Script runs without errors on local build tree
- [ ] Findings JSON validates against schema
- [ ] Quality rubric MUST criteria all pass
- [ ] No false negatives on known conflict cases (libcap, systemd)

## Current Status

- **Tasks 001-006**: Complete (implemented in `photon-gating-agent.py`)
- **Task 007**: Complete (validated against 5.0 branch with subrelease 91)
- **Task 008**: Complete (ADR-0001, ADR-0002, ADR-0003 written)

**Total Findings from Reference Scan**: 97 (89 CRITICAL, 4 HIGH, 4 WARNING)

**Last Updated**: 2026-03-06
