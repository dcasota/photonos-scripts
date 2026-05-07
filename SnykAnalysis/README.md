# SnykAnalysis

PowerShell scripts for running [Snyk](https://snyk.io/) Code analysis across the
upstream-source clone trees produced by `photonos-package-report.ps1`, parsing the
results into a normalized SQLite database, and generating per-branch reports.

Designed to chain into the photonos-scripts workflow sequence:

```
photon-commits-db          ──► commits.db
package-report             ──► photon-upstreams/photon-<branch>/clones/<pkg>/<src>
upstream-source-code-dependency-scanner
                           ──► depfix manifests
SnykAnalysis (this dir)    ──► snyk_issues.db, SnykReport_*.{txt,md,json}
```

## Prerequisites

- PowerShell 7+ (5.1 also works)
- [Snyk CLI](https://docs.snyk.io/snyk-cli/install-the-snyk-cli) on PATH; authenticated via `snyk auth $SNYK_TOKEN`
- `sqlite3` on PATH

## Scripts

### Run-SnykOnSubdirs.ps1

Runs `snyk code test` on each immediate subdirectory of `-BaseDir`, writing one
log per subdir. Idempotent (skips a package whose log already exists; override
with `-Force`).

```powershell
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-5.0/clones -Branch 5.0
```

Parameters:

| Parameter | Default | Notes |
|---|---|---|
| `-BaseDir` | (required) | The `clones/` directory of one Photon branch |
| `-LogDir` | `$BaseDir` | Where logs are written |
| `-Branch` | `''` | Embedded in log filename: `<pkg>_snyk_<branch>_<ts>.log` |
| `-Skip` | `@()` | Package names to skip |
| `-MaxSubdirs` | `0` | Cap subdirs processed (0 = no cap) |
| `-Force` | off | Re-scan packages with an existing log |

Exit code: `0` if all scans succeeded (snyk exit 0/1/3 = success), `1` if any failed.

### Parse-SnykLogs.ps1

Parses `*_snyk*.log` files into a normalized SQLite schema. Idempotent on
`runs.log_file` — re-running on the same logs is a no-op unless `-Reparse` is set.

```powershell
./Parse-SnykLogs.ps1 -Directory <logDir> -Database snyk_issues.db
```

Schema:

- `runs(run_id, package, branch, datetime, log_file UNIQUE, log_size, project_path, total_issues, ignored_issues, open_issues)`
- `issues(issue_id, run_id, priority, title, finding_id, path, line_num, info)` (FK runs)
- view `v_latest_run` — one row per `(package,branch)` with the latest datetime

Branch is extracted from the log filename if it embeds `_snyk_<branch>_<ts>.log`,
or from a path containing `photon-<branch>/clones/`. Override with `-Branch`.

### Generate-SnykReport.ps1

Builds a report from the normalized schema. Three output formats: text, Markdown
(suitable for `$GITHUB_STEP_SUMMARY`), JSON (for downstream tooling).

```powershell
./Generate-SnykReport.ps1 -Database snyk_issues.db -Format markdown -Branch 5.0
```

Sections:

- Summary (latest run per package/branch): totals by priority, crypto split
- Per-branch breakdown (when not filtered)
- Top-N High categories with `crypto` in title
- Top-N High categories without `crypto`
- Top-N Medium categories
- Top-N packages by total issues

## Typical workflow

```powershell
# 1. Per branch: scan the clone tree produced by photonos-package-report
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-3.0/clones -Branch 3.0
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-4.0/clones -Branch 4.0
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-5.0/clones -Branch 5.0
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-6.0/clones -Branch 6.0
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-common/clones -Branch common
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-dev/clones    -Branch dev
./Run-SnykOnSubdirs.ps1 -BaseDir <upstreamsDir>/photon-master/clones -Branch master

# 2. Parse all logs into one database
./Parse-SnykLogs.ps1 -Directory <upstreamsDir> -Database snyk_issues.db

# 3. Generate report (overall + per branch)
./Generate-SnykReport.ps1 -Database snyk_issues.db -Format markdown
./Generate-SnykReport.ps1 -Database snyk_issues.db -Format markdown -Branch 5.0
```

## CI

See `.github/workflows/snyk-analysis.yml` for the GitHub Actions workflow that
chains all three scripts on the self-hosted runner. Requires repo secret
`SNYK_TOKEN`.
