# Gating Agent Quality Rubric

## Purpose

This rubric defines pass/fail criteria for the gating agent pipeline output. Every detection run must satisfy all MUST criteria. SHOULD criteria are recommended but non-blocking.

---

## Detection Output Quality (gating-detector)

### MUST (Fail the run if violated)

| # | Criterion | Validation |
|---|-----------|------------|
| D1 | `gating-inventory.json` was produced before any detection | Check timestamp ordering |
| D2 | Every finding references at least one spec file path | `spec_paths.length >= 1` |
| D3 | Every finding includes branch name and subrelease value | `branch` and `subrelease` fields non-null |
| D4 | Every C1 finding lists specific missing subpackages | `missing_subpackages.length >= 1` when `constellation == "C1"` |
| D5 | Every C5 finding includes exact canister version string | `canister_version` non-null when `constellation == "C5"` |
| D6 | Every C6 finding includes HTTP status code and URL | `http_status` and `url` non-null when `constellation == "C6"` |
| D7 | Every remediation specifies which build-config.json keys to change | `remediation.config_keys.length >= 1` |
| D8 | `findings.json` conforms to `gating-findings-schema.json` | JSON Schema validation passes |
| D9 | Both `findings.md` and `findings.json` are produced | Both files exist and are non-empty |
| D10 | All 6 constellations were checked (not just a subset) | Scan log confirms C1-C6 all executed |

### SHOULD (Log warning if violated)

| # | Criterion | Notes |
|---|-----------|-------|
| D11 | Traceability matrix covers all dimensions (branch, arch, flavor) | Flavor may be "unknown" if not determinable |
| D12 | Findings are sorted by severity (BLOCKING first) | In findings.md |
| D13 | Summary statistics are included | `summary` object in findings.json |
| D14 | No duplicate findings (same spec + same branch + same constellation) | Deduplicate before output |

---

## Remediation Output Quality (gating-remediation)

### MUST

| # | Criterion | Validation |
|---|-----------|------------|
| R1 | Every BLOCKING finding has a remediation action | All findings with `severity == "BLOCKING"` appear in remediation plan |
| R2 | Every CRITICAL finding has a remediation action | All findings with `severity == "CRITICAL"` appear in remediation plan |
| R3 | Before/after values recorded for each edit | `old_value` and `new_value` present |
| R4 | Verification scan ran after applying fixes | Re-detection confirms resolution |
| R5 | ADR created for each applied remediation | ADR file exists with correct finding references |
| R6 | Remediation plan specifies exact file paths | No relative or ambiguous paths |

### SHOULD

| # | Criterion | Notes |
|---|-----------|-------|
| R7 | Rollback procedure tested | Backup files created and restorable |
| R8 | No unnecessary changes | Only change what is needed for the finding |

---

## Inventory Output Quality (Phase 0)

### MUST

| # | Criterion | Validation |
|---|-----------|------------|
| I1 | All configured branches scanned | Branch count matches `--branches` parameter |
| I2 | Common branch scanned | `common` entry present |
| I3 | Every .spec file processed | No parse errors silently swallowed |
| I4 | All SPECS/<N>/ directories discovered | Count matches filesystem reality |
| I5 | JSON output is valid | `json.loads()` succeeds |

### SHOULD

| # | Criterion | Notes |
|---|-----------|-------|
| I6 | Cross-references between old/new spec pairs | Paired specs linked by package name |
| I7 | ExtraBuildRequires captured | Needed for C5 canister detection |

---

## CI Integration Quality

### MUST

| # | Criterion | Validation |
|---|-----------|------------|
| CI1 | CI job fails on BLOCKING findings | Exit code != 0 |
| CI2 | CI job fails on CRITICAL findings in PR gate | Exit code != 0 |
| CI3 | Findings artifact uploaded even on failure | `findings.json` available for download |

### SHOULD

| # | Criterion | Notes |
|---|-----------|-------|
| CI4 | PR annotations for WARNING findings | GitHub annotations via `::warning::` |
| CI5 | Run duration logged | For performance tracking |
