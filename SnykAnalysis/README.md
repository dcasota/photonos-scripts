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

### Parse-AgentScanLogs.ps1

Companion parser for the **Snyk Agent Scan** extension. Walks
`*_agentscan_*.json` files (emitted by the workflow's agent-scan step) and
imports them into the same SQLite DB used by `Parse-SnykLogs.ps1`.

```powershell
./Parse-AgentScanLogs.ps1 -Directory <upstreamsDir> -Database snyk_issues.db
```

Adds three objects to the DB (idempotent, additive — coexists with `runs` /
`issues`):

- `agent_scans(scan_id, package, branch, datetime, agent_type, config_path, log_file UNIQUE, log_size, total_issues, scan_version)`
- `agent_issues(issue_id, scan_id, code, severity, category, artefact, message, raw)` (FK)
- view `v_latest_agent_scan` — one row per `(package, branch, agent_type)` with the newest datetime

Filename convention (set by `snyk-analysis.yml`):

```
<package>_agentscan_<branch>_<agent_type>_<YYYYMMDD_HHMMSS>.json
e.g.  calico_agentscan_5.0_claude_20260511_103000.json
```

`agent_type` is the dotdir name stripped of its leading `.` (`claude`,
`cursor`, `gemini`, `codex`, …). The parser is defensive: unknown JSON
shapes are still recorded with the raw payload in `agent_issues.raw`.

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
- **Agent Components (snyk-agent-scan)** — only rendered if `agent_scans`
  has rows for the branch. Includes total scans / packages / issues,
  coverage by agent type (Claude / Cursor / Gemini / Codex / …), the top
  issue codes, and the top packages with agent-component issues.

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

# 2. (optional) Snyk Agent Scan extension: scan every AI-assistant config
#    dotdir (.claude / .cursor / .gemini / .codex / ...) under each clone.
#    Requires `uvx` (uv package manager) on PATH and a Snyk account.
for AGENT_DIR in $(find <upstreamsDir> -mindepth 4 -maxdepth 6 -type d \( \
    -name .claude -o -name .cursor -o -name .gemini -o -name .codex -o \
    -name .windsurf -o -name .aider -o -name .amp -o -name .kiro -o -name .opencode \)); do
    PKG_ROOT="$(dirname "$AGENT_DIR")"
    PKG="$(basename "$PKG_ROOT")"
    BR="$(echo "$AGENT_DIR" | sed -n 's|.*/photon-\([^/]*\)/clones/.*|\1|p')"
    AGENT="${AGENT_DIR##*/.}"
    STAMP="$(date -u +%Y%m%d_%H%M%S)"
    uvx snyk-agent-scan@latest scan --json --dangerously-run-mcp-servers \
        "$AGENT_DIR" > "$PKG_ROOT/${PKG}_agentscan_${BR}_${AGENT}_${STAMP}.json"
done

# 3. Parse all logs into one database (SAST + agent-scan)
./Parse-SnykLogs.ps1      -Directory <upstreamsDir> -Database snyk_issues.db
./Parse-AgentScanLogs.ps1 -Directory <upstreamsDir> -Database snyk_issues.db

# 4. Generate report (overall + per branch)
./Generate-SnykReport.ps1 -Database snyk_issues.db -Format markdown
./Generate-SnykReport.ps1 -Database snyk_issues.db -Format markdown -Branch 5.0
```

## CI

See `.github/workflows/snyk-analysis.yml` for the GitHub Actions workflow that
chains all three scripts on the self-hosted runner. Requires repo secret
`SNYK_TOKEN`.
