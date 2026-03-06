# Task 002: Dual-Format Output and Schema Validation

**Dependencies**: Task 001
**Complexity**: Low
**Status**: Complete

---

## Description

Implement dual-format output (JSON + Markdown) and validate JSON against `gating-findings-schema.json`.

## Requirements

- Generate `findings.json` with schema version, summary, and findings array
- Generate `findings.md` with severity icons, tables, and remediation text
- Sort findings by severity (BLOCKING > CRITICAL > HIGH > WARNING)
- Deduplicate findings by ID
- Include summary counts by severity and constellation

## Acceptance Criteria

- [ ] JSON output validates against `.github/gating-findings-schema.json`
- [ ] Markdown output includes severity icons and remediation per finding
- [ ] Summary table shows counts by severity and constellation
- [ ] Exit code 1 if BLOCKING or CRITICAL findings exist, 0 otherwise

## Implementation

Functions: `generate_json_output()`, `generate_md_output()`, `severity_rank()`
