---
mode: agent
description: Analyze vCenter release coverage by correlating KB 326316 with Photon advisory data
tools: [filesystem]
---

# Track vCenter Release Coverage

## Context

The vCenter-CVE-drift-analyzer only tracks releases that have Photon OS security patch tables. This prompt identifies the full set of releases and the coverage gap.

## Workflow

1. Fetch Broadcom KB 326316:
   ```
   https://knowledge.broadcom.com/external/article/326316
   ```
   Parse vCenter 7.0, 8.0, and 9.0 release tables for: release name, version, date, build number.

2. Fetch Photon OS advisory wiki pages:
   - 8.0: `https://github.com/vmware/photon/wiki/Security-Advisories-8.0`
   - 9.0: `https://github.com/vmware/photon/wiki/Security-Advisories-9.0`

3. Cross-reference: for each KB 326316 release, check if a corresponding Photon advisory section exists.

4. Generate coverage report with:
   - Total releases per major version per year
   - Tracked vs. untracked counts
   - List of specific missing releases
   - Yearly velocity table

## Expected Output

```
Year     | vCenter 7.0 | vCenter 8.0 | vCenter 9.0 | Total
---------+-------------+-------------+-------------+------
2023     |      6      |      9      |     --      |  15
2024     |      4      |     10      |     --      |  14
2025     |      3      |      3      |      2      |   8

Coverage: 8.0 = 10/24 (42%), 9.0 = 2/3 (67%)
Missing: 8.0a, 8.0c, 8.0U1, 8.0U1a, ...
```

## Quality Checklist

- [ ] All 3 major versions covered (7.0, 8.0, 9.0)
- [ ] Release dates match KB 326316 exactly
- [ ] Coverage percentages computed correctly
- [ ] Missing releases listed individually
