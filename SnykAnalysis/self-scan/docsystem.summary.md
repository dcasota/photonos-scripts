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

## tools/ iter 2 (2026-11-09)

Snyk on `docsystem/tools`: 6 findings (4 MEDIUM, 2 LOW). Runtime-fixed: 6; Snyk still lists 6.

- **documentation_lecturer.py PT x4 (MEDIUM) -> FIXED, false-positive-post-fix.** The iter-1
  "plugin data dir" verdict was wrong: page URLs come from the remote `sitemap.xml`, and
  `apply_fixes.map_url_to_local_path` followed `..` segments out of the docs checkout
  (reproduced). Now dot segments are rejected, exact-name lookups pick `os.listdir()` entries,
  and the result must resolve under `local_webserver`. Snyk follows taint through the
  unresolved call into `open()`, so it cannot see the fix.
- **mirror-repository.py PT x2 (LOW) -> DESIGN-DECISION** (operator `--local-path`, now
  resolved and checked; deletion target is the `mkdtemp` dir).
- Found while fixing: the mirror script **printed the GitHub token** in `Running: git push
  https://user:TOKEN@...` and in error text (now redacted), and its URL parser truncated repo
  names at the first dot (now anchored, GitHub naming rules).

Verification: traversal PoC (`..`, `%2e%2e`, symlink) refused, legitimate, mixed-case and
content-based mappings unchanged vs HEAD; lecturer test suite 22 pass / same 12 pre-existing
errors before and after (stale tests calling removed methods); mirror URL/redaction cases pass.
