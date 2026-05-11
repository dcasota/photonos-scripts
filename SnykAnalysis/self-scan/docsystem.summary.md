# docsystem self-scan summary

Scan date: 2026-05-11
Branch: snyk-self-scan-20260511

## Counts

| Phase     | Total | Warning | Note |
|-----------|-------|---------|------|
| Baseline  | 94    | 24      | 70   |
| Iter 1    | 93    | 23      | 70   |
| Accepted  | 20    | -       | -    |
| Deferred  | 73    | -       | -    |
| Open      | 0     | -       | -    |

## Iteration 1 fixes

| Rule | Location | Outcome |
|------|----------|---------|
| python/InsecureXmlParser | analyze_site.py:11 | HARD-FIX (defusedxml.ElementTree with stdlib fallback) |
| python/CommandInjection | importer.py (skills + teams) x6 | HARD-FIX (validate_refname regex guard on branch/commit_hash before git invocation) |

## Per-rule disposition

- 1 InsecureXmlParser - HARD-FIX
- 7 python/CommandInjection - 6 HARD-FIX (validate_refname runtime guard; Snyk still flags), 1 NOT-OUR-CODE (vendored photon/)
- 13 first-party python/PT - DESIGN-DECISION (env-var/CLI hooks and tools)
- 73 deferred: vendored docsystem/photon/ subtree (untracked upstream checkout) plus the long-tail in-scope python/PT

Per the project plan, docsystem stops iterating after iter 1 because >30 findings remain; deferred batch is documented in
`SnykAnalysis/self-scan/accepted/docsystem.json` (deferred:). Recommendation captured there:
add `docsystem/photon/` to a Snyk path-ignore list to drop the ~73 vendored-code findings.

## Build verification

`python3 -m py_compile` on each modified script succeeds.
