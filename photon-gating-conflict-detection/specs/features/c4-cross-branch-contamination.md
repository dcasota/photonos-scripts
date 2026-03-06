# Feature Requirement Document: C4 -- Cross-Branch Contamination via common/

**Feature ID**: FRD-C4
**Related PRD Requirements**: REQ-4, REQ-8, REQ-9
**Status**: Implemented
**Last Updated**: 2026-03-06

---

## 1. Feature Overview

Detect when two release branches share `common/` gated specs but use different subreleases, causing different spec sets to activate from the same gating threshold.

### Success Criteria

- Detects that 5.0 (subrelease=91) and 6.0 (subrelease=92) activate different kernel driver specs from common/
- Lists all affected specs by name

---

## 2. Functional Requirements

### 2.1 Threshold Grouping

Group all gated common/ specs by their threshold value.

### 2.2 Activation Diff

For each pair of branches with different subreleases, compare which specs are active at each subrelease.

### 2.3 Severity

WARNING -- this is expected behavior (branches intentionally use different subreleases for different kernel versions). It becomes a problem only if branches share build infrastructure that doesn't account for the difference.

---

## 3. Reference Findings

From scan 2026-03-06:

- Threshold 91: 5.0+6.0 activate different Intel driver spec sets (9 specs)
- Threshold 92: 5.0+6.0 activate different kernel + Intel driver spec sets (8 specs)

---

## 4. Dependencies

**Depends On**: REQ-7 (inventory), common/ spec parsing
