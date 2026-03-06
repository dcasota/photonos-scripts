# ADR-0003: Detection Agent Architecture

**Date**: 2026-03-06
**Status**: Accepted

## Context

We need an automated pipeline to detect gating-snapshot conflicts across the Photon OS build tree. The design must be maintainable, testable, and runnable in CI without special infrastructure.

## Decision Drivers

- Must run on standard GitHub Actions `ubuntu-latest` runners
- Must not require LLM, AI, or cloud inference services
- Must produce deterministic, reproducible results
- Must complete a full scan in under 60 seconds
- Must integrate with existing vmware/photon CI patterns

## Considered Options

### Option 1: Single Python script with phased execution

One `photon-gating-agent.py` script with `--phase` flag controlling execution (inventory, detect, all).

**Pros**: Single file to maintain. No import dependencies between modules. Easy to run locally.
**Cons**: Large file. Harder to test individual constellations.

### Option 2: Multi-module Python package

Separate modules per constellation (`c1.py`, `c2.py`, etc.) with a shared spec parser.

**Pros**: Clean separation. Testable per constellation. Easier to extend.
**Cons**: More files. Requires package structure.

### Option 3: Shell-based with jq/grep

Parse specs with grep/awk, process with jq.

**Pros**: No Python dependency.
**Cons**: Fragile parsing. Hard to maintain. Poor error handling.

## Decision Outcome

**Chosen**: Option 1 (single script), with the `.github/agents/` markdown files serving as design specs for each role (orchestrator, detector, remediation, fips-validator, artifactory-probe, build-config-fixer).

**Rationale**:
- A single 600-line Python script is easier to copy into vmware/photon than a package
- The agent role separation exists in the documentation, not in code modules
- Phased execution (`--phase inventory` vs `--phase detect`) provides the orchestration
- Future refactoring into a package is straightforward (functions already map to roles)

## Implementation Details

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Python | 3.11+ | Runtime |
| requests | any | HTTP HEAD for C6 snapshot probing |
| jsonschema | any | Findings schema validation |

### Architecture

```
photon-gating-agent.py
  ├── Spec Parser (parse_spec, is_active, full_package_names)
  ├── Phase 0: build_inventory()
  ├── Phase 1: detect_c1..c6() + detect_c3_upgrade_conflict()
  ├── Output: generate_json_output() + generate_md_output()
  └── CLI: argparse entry point
```

### Agent-to-Code Mapping

| Agent (docs) | Function(s) in script |
|-------------|----------------------|
| gating-orchestrator | `main()`, CLI argument parsing |
| gating-detector | `detect_c1` through `detect_c6`, `detect_c3_upgrade_conflict` |
| fips-validator | `detect_c5_fips_canister()` |
| artifactory-probe | `detect_c6_snapshot_url()` with `--check-urls` |
| build-config-fixer | Not implemented (detection only) |
| gating-remediation | Remediation fields in findings JSON (advisory) |

## Consequences

### Positive

- Zero infrastructure requirements beyond Python 3.11
- Fully deterministic -- same input always produces same output
- Can run locally (`python3 photon-gating-agent.py --base-dir /root`) or in CI
- Single file is portable and easy to review

### Negative

- Single file may grow as constellations are refined
- No unit test isolation per constellation (integration tests recommended)

## References

- PRD: `specs/prd.md` -- REQ-8, Constraints
- Quality rubric: `.github/quality-rubric.md`
- JSON Schema: `.github/gating-findings-schema.json`
