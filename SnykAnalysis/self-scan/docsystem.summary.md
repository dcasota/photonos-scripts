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

## Processing pass (2026-11-12)

Scope: tracked files only (`git archive HEAD docsystem`); the untracked `docsystem/photon/`
upstream checkout is out of scope. Snyk: **21 open (10 MEDIUM, 11 LOW) -> 4 open (4 MEDIUM)**.

- **Duplicate Factory scripts removed.** `.factory/teams/docs-blogger/{importer,summarizer,db_schema}.py`
  were byte-identical stale copies of `.factory/skills/`; everything (workflow, tests, droids,
  SKILL.md, `generate_all_missing.sh`) uses the skills/ copies. 7 findings gone.
- **importer.py CommandInjection x3 -> FIXED.** Branch names, `--since-date` and commit hashes are
  rebuilt from fixed character tables and refused otherwise; `--since` is passed as
  `--since=<date>`. Before, `--since-date=--output=x` was accepted silently, and the old
  `validate_refname` regex (`$`) let a trailing newline, `a..b` and `a/` reach git.
- **summarizer.py PT x4 -> FIXED.** The branch is part of the post file name and the YAML front
  matter and must now be a plain name (no `/`, `..`, quotes). `--sync-check` only opens a stored
  `file_path` that names that row's post file (others: `unexpected_path`).
- **validate_hugo_frontmatter.py PT -> FIXED.** `FACTORY_PROJECT_DIR` is checked; symlinks out
  of `content/blog` are not read.
- **mirror-repository.py PT x2 -> FIXED.** `--local-path` is checked before any GitHub call or
  repository creation (it used to be checked only after the target repo was created).
- **documentation_lecturer.py PT x4 -> still accepted (FALSE-POSITIVE-POST-FIX).** Re-verified:
  the mapper fix from PR #331 refuses `..`, `%2e%2e` and symlink escapes, valid pages still map.
  Snyk cannot resolve the `self.fix_applicator.map_url_to_local_path()` call.

Verification: `pytest docsystem/tests` 14 passed; old-vs-new runs against a local git repo /
summaries DB / hook test tree give identical output for valid input (importer rows, exported
posts, generated markdown, hook verdicts), hostile values are refused with a message. Only
visible difference: `importer.py --check` now reports `db_path` as an absolute path.
