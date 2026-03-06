---
agent: gating-remediation
---

# Create Architecture Decision Record for Gating Change

## Mission

Document a gating-related change as an Architecture Decision Record (ADR) using MADR format.

## When to Create

An ADR must be created whenever:

- A new `build_if` threshold is introduced or changed in a spec
- A `photon-mainline` value is set or changed in a `build-config.json`
- A `photon-subrelease` value is changed
- A snapshot URL is modified or disabled
- A package is split, merged, or relocated to a `SPECS/<N>/` directory

## ADR Template

```markdown
# ADR-NNNN: <Title>

## Status

Accepted | Proposed | Deprecated | Superseded

## Date

YYYY-MM-DD

## Context

<What gating conflict or build requirement led to this change?>

- Branch(es) affected: <list>
- Constellation(s): <C1-C6 identifiers>
- Finding severity: <BLOCKING | CRITICAL | HIGH>

## Decision

<What was changed and in which files?>

### Changes Made

| File | Key/Field | Old Value | New Value |
|------|-----------|-----------|-----------|
| ... | ... | ... | ... |

## Consequences

### Positive

- <What conflicts are resolved?>

### Negative

- <What tradeoffs were accepted? e.g., loss of snapshot reproducibility>

### Affected Dimensions

- **Branches**: <which branches>
- **Architectures**: <x86_64, aarch64, or both>
- **Flavors**: <minimal, full, FIPS>
- **Snapshots**: <which snapshots become stale or bypassed>

## Rollback Procedure

<Exact steps to revert this change if needed>

1. Restore `<file>` key `<key>` to `<old_value>`
2. Re-run `gating-detector --verify` to confirm

## Related

- Finding: <reference to findings.json entry>
- Commit: <upstream commit that triggered this, if applicable>
- Previous ADR: <if this supersedes another>
```

## File Location

Save ADRs in: `adr/NNNN-<slug>.md`

Numbering is sequential, zero-padded to 4 digits (0001, 0002, etc.).
