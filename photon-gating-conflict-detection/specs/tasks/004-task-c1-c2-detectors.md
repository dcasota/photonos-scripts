# Task 004: C1 and C2 Constellation Detectors

**Dependencies**: Task 001
**Complexity**: High
**Status**: Complete

---

## Description

Implement detection for C1 (package split/merge) and C2 (version bump with new dependencies).

## Requirements

### C1

- For each gated spec pair, compute subpackage diff
- Find consumers of added/removed subpackages
- Classify as CRITICAL (consumers exist + old spec active) or WARNING (no consumers)

### C2

- For each gated spec pair, compute Requires/BuildRequires diff
- Check if added dependency is provided by another inactive gated spec
- Classify as HIGH

## Acceptance Criteria

- [ ] Detects libcap split: 3 new subpackages, consumers: libcap, rpm
- [ ] Detects gawk split: 4 new subpackages
- [ ] Detects strace split: 1 new subpackage
- [ ] Detects rpm -> libcap-libs cross-dependency (C2)
- [ ] Detects pgbackrest/python3-psycopg2/apr-util -> postgresql18-devel (C2)
- [ ] Zero false positives on spec pairs with identical subpackage sets

## Implementation

Functions: `detect_c1_package_split()`, `detect_c2_version_bump_deps()`, `find_consumers()`
