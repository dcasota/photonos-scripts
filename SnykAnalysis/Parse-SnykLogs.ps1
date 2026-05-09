<#
.SYNOPSIS
    Parses *_snyk*.log files into a normalized SQLite schema (runs + issues tables).

.DESCRIPTION
    Replaces the prior per-log-table schema. New schema:
        runs(   run_id INTEGER PRIMARY KEY,
                package TEXT, branch TEXT, datetime TEXT,
                log_file TEXT UNIQUE, log_size INTEGER,
                project_path TEXT,
                total_issues INTEGER, ignored_issues INTEGER, open_issues INTEGER )
        issues( issue_id INTEGER PRIMARY KEY, run_id INTEGER, priority TEXT,
                title TEXT, finding_id TEXT, path TEXT, line_num INTEGER, info TEXT,
                FOREIGN KEY(run_id) REFERENCES runs(run_id) )
        v_latest_run AS — one row per (package,branch), the latest run

    Idempotent: runs.log_file is UNIQUE, so re-parsing the same log is a no-op
    unless -Reparse is set (drops + re-imports the matching run).

    Branch is extracted from the log filename if it embeds "_snyk_<branch>_<datetime>.log"
    (matches the format Run-SnykOnSubdirs.ps1 produces with -Branch). If the log path
    contains ".../photon-<branch>/clones/...", that is used as a fallback.
    Override with -Branch.

.PARAMETER Directory
    Directory to scan for log files. Default: current directory.

.PARAMETER Database
    SQLite database file. Created if missing. Default: snyk_issues.db.

.PARAMETER Recursive
    Recurse into subdirectories. Default: $true.

.PARAMETER Branch
    Override the branch tag for every log parsed in this run.

.PARAMETER Reparse
    Drop+reimport rows for any log that already exists in runs.log_file.

.PARAMETER Rebuild
    Wipe the runs+issues tables before parsing and re-import every log from
    scratch. Use this once after upgrading from a parser version that wrote
    invalid run_ids (the pre-fix `last_insert_rowid()` chain).
#>
[CmdletBinding()]
param(
    [string]$Directory = '.',
    [string]$Database  = 'snyk_issues.db',
    [bool]$Recursive   = $true,
    [string]$Branch    = '',
    [switch]$Reparse,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Error "sqlite3 not found on PATH."
    exit 2
}

# Initialize schema
$schema = @'
CREATE TABLE IF NOT EXISTS runs (
    run_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    package        TEXT NOT NULL,
    branch         TEXT,
    datetime       TEXT,
    log_file       TEXT UNIQUE,
    log_size       INTEGER,
    project_path   TEXT,
    total_issues   INTEGER,
    ignored_issues INTEGER,
    open_issues    INTEGER
);
CREATE TABLE IF NOT EXISTS issues (
    issue_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id     INTEGER NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
    priority   TEXT,
    title      TEXT,
    finding_id TEXT,
    path       TEXT,
    line_num   INTEGER,
    info       TEXT
);
CREATE INDEX IF NOT EXISTS idx_runs_pkgbranch ON runs(package, branch);
CREATE INDEX IF NOT EXISTS idx_runs_datetime  ON runs(datetime);
CREATE INDEX IF NOT EXISTS idx_issues_runid   ON issues(run_id);
CREATE INDEX IF NOT EXISTS idx_issues_pri     ON issues(priority);
CREATE VIEW IF NOT EXISTS v_latest_run AS
    SELECT r.* FROM runs r
    JOIN ( SELECT package, branch, MAX(datetime) AS max_dt
           FROM runs GROUP BY package, branch ) m
      ON r.package = m.package
     AND COALESCE(r.branch,'') = COALESCE(m.branch,'')
     AND r.datetime = m.max_dt;
'@

$tmp = New-TemporaryFile
try {
    $schema | Out-File -LiteralPath $tmp.FullName -Encoding utf8
    & sqlite3 $Database ".read $($tmp.FullName)"
} finally { Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue }

# One-time wipe: drop every row before re-parsing. Used to recover from the
# `last_insert_rowid()` regression which left orphan run_ids in `issues`.
if ($Rebuild) {
    Write-Host "Rebuild requested - wiping runs+issues before re-parse" -ForegroundColor Yellow
    & sqlite3 $Database "DELETE FROM issues; DELETE FROM runs; VACUUM;"
    $Reparse = $true   # force re-import even if a stale row was missed
}

# Defensive orphan cleanup: drop any issue whose run_id no longer (or never)
# pointed at a real run. Cheap when there's nothing to do, decisive when the
# DB carries leftovers from a past parser bug.
$orphanCount = (& sqlite3 $Database "SELECT COUNT(*) FROM issues WHERE run_id NOT IN (SELECT run_id FROM runs);").Trim()
if ($orphanCount -and [int]$orphanCount -gt 0) {
    Write-Host "Cleaning up $orphanCount orphaned issue rows (run_id not in runs)" -ForegroundColor Yellow
    & sqlite3 $Database "DELETE FROM issues WHERE run_id NOT IN (SELECT run_id FROM runs);"
}

# Discover logs
$logFiles = Get-ChildItem -Path $Directory -Recurse:$Recursive -Filter '*_snyk*.log' -File -ErrorAction SilentlyContinue
Write-Host "Found $($logFiles.Count) log files under '$Directory' (recursive=$Recursive)" -ForegroundColor Gray
if ($logFiles.Count -eq 0) { exit 0 }

function Sql([string]$value) {
    if ($null -eq $value -or $value -eq '') { return 'NULL' }
    "'" + ($value -replace "'", "''") + "'"
}

function Parse-BranchFromPath([string]$logPath, [string]$logName) {
    # 1. _snyk_<branch>_<yyyymmdd>_<hhmmss>.log
    if ($logName -match '_snyk_([^_]+)_\d{8}_\d{6}\.log$') { return $matches[1] }
    # 2. .../photon-<branch>/clones/...
    if ($logPath -match '[/\\]photon-([^/\\]+)[/\\]clones[/\\]') { return $matches[1] }
    return ''
}

$imported = 0
$updated  = 0
$skipped  = 0

foreach ($logFile in $logFiles) {
    $logPath = $logFile.FullName
    $existing = (& sqlite3 $Database "SELECT run_id FROM runs WHERE log_file=$(Sql $logPath);")
    if ($existing -and -not $Reparse) {
        $skipped++
        continue
    }

    $content     = Get-Content -LiteralPath $logPath
    $projectPath = $null; $totalIssues = 0; $ignoredIssues = 0; $openIssues = 0
    foreach ($line in $content) {
        if ($line -match 'Project path:\s*(.+)') {
            # Snyk CLI output framing uses U+2502 (BOX DRAWINGS LIGHT VERTICAL)
            # as a tree-indent border; strip it plus surrounding whitespace
            # so the captured path doesn't end with "<pkg>    │".
            $projectPath = $matches[1] -replace '[│\s]+$', ''
            $projectPath = $projectPath.Trim()
        }
        if ($line -match 'Total issues:\s*(\d+)')    { $totalIssues   = [int]$matches[1] }
        if ($line -match 'Ignored issues:\s*(\d+)')  { $ignoredIssues = [int]$matches[1] }
        if ($line -match 'Open issues:\s*(\d+)')     { $openIssues    = [int]$matches[1] }
    }

    $package = if ($projectPath) {
        ($projectPath -split '[/\\]')[-1]
    } else {
        ([IO.Path]::GetFileNameWithoutExtension($logFile.Name) -split '_snyk')[0]
    }
    # Defence-in-depth: also strip any U+2502 + trailing whitespace from the
    # final package name (handles older logs that slipped through).
    $package = ($package -replace '[│\s]+$', '').Trim()

    $datetime = ''
    if ($logFile.Name -match '_snyk[^_]*_(\d{8})_(\d{6})\.log$') {
        $datetime = "$($matches[1])_$($matches[2])"
    } elseif ($logFile.Name -match '_(\d{8})_(\d{6})\.log$') {
        $datetime = "$($matches[1])_$($matches[2])"
    } else {
        $datetime = (Get-Date -Format 'yyyyMMdd_HHmmss')
    }

    $br = if ($Branch) { $Branch } else { Parse-BranchFromPath $logPath $logFile.Name }

    # Parse issues
    $issues = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $content.Count; $i++) {
        $line = $content[$i]
        if ($line -match '^\s*✗\s*\[([^\]]+)\]\s*(.+)') {
            $priority = $matches[1].Trim()
            $title    = $matches[2].Trim()
            $i++
            $findingID = if ($i -lt $content.Count -and $content[$i] -match 'Finding ID:\s*(.+)') { $matches[1].Trim() } else { '' }
            $i++
            $path = ''; $lineNum = ''
            if ($i -lt $content.Count) {
                $pathLine = $content[$i]
                if ($pathLine -match 'Path:\s*(.+?)(?:,\s*line\s*(\d+))?\s*$') {
                    $path    = $matches[1].Trim()
                    $lineNum = if ($matches[2]) { $matches[2] } else { '' }
                } else {
                    $path = $pathLine.Trim()
                }
            }
            $i++
            $info = if ($i -lt $content.Count -and $content[$i] -match 'Info:\s*(.+)') { $matches[1].Trim() } else { ($content[$i]).Trim() }
            $issues.Add([pscustomobject]@{
                Priority   = $priority
                Title      = $title
                FindingID  = $findingID
                Path       = $path
                LineNum    = $lineNum
                Info       = $info
            }) | Out-Null
        }
    }

    # Build SQL: replace any existing run for this log_file, then INSERT.
    #
    # Bug fix: previous version used `last_insert_rowid()` for run_id in
    # every issue VALUES tuple. SQLite updates last_insert_rowid() after
    # EACH row insert inside a multi-row INSERT, so issues #2..N pointed
    # at the previous issue's auto-increment id (an orphaned row), not at
    # the run. With FK enforcement off (SQLite default), the bad inserts
    # were silently accepted; the v_latest_run JOIN dropped 99% of issues
    # at report time. See run analysis: 290k orphan run_ids in issues vs
    # 3.3k real runs, jdk21u with 2997 issues showed only 2 in reports.
    #
    # Fix: reference the run via a deterministic subquery on log_file
    # (UNIQUE), so all VALUES tuples bind to the same run_id regardless
    # of last_insert_rowid() drift. Also explicitly delete any orphaned
    # issues for this log before re-inserting (FK ON DELETE CASCADE
    # doesn't fire when foreign_keys=OFF).
    $logSql = Sql $logPath
    $sql  = "BEGIN;`n"
    if ($existing) {
        $sql += "DELETE FROM issues WHERE run_id IN (SELECT run_id FROM runs WHERE log_file=$logSql);`n"
        $sql += "DELETE FROM runs WHERE log_file=$logSql;`n"
    }
    $sql += "INSERT INTO runs (package,branch,datetime,log_file,log_size,project_path,total_issues,ignored_issues,open_issues) VALUES ("
    $sql += "$(Sql $package),$(Sql $br),$(Sql $datetime),$logSql,$($logFile.Length),"
    $sql += "$(Sql $projectPath),$totalIssues,$ignoredIssues,$openIssues);`n"
    $sql += "INSERT INTO issues (run_id,priority,title,finding_id,path,line_num,info)`n"
    if ($issues.Count -gt 0) {
        $sql += "  VALUES`n"
        $rows = @()
        foreach ($iss in $issues) {
            $ln = if ($iss.LineNum -match '^\d+$') { $iss.LineNum } else { 'NULL' }
            $rows += "  ((SELECT run_id FROM runs WHERE log_file=$logSql),$(Sql $iss.Priority),$(Sql $iss.Title),$(Sql $iss.FindingID),$(Sql $iss.Path),$ln,$(Sql $iss.Info))"
        }
        $sql += ($rows -join ",`n") + ";`n"
    } else {
        # Placeholder so an empty run is still queryable
        $sql += "  VALUES (last_insert_rowid(),'SUMMARY','No open issues','','',NULL,'');`n"
    }
    $sql += "COMMIT;`n"

    $tmp = New-TemporaryFile
    try {
        $sql | Out-File -LiteralPath $tmp.FullName -Encoding utf8
        & sqlite3 $Database ".read $($tmp.FullName)"
        if ($LASTEXITCODE -ne 0) { Write-Warning "sqlite import returned $LASTEXITCODE for $($logFile.Name)" }
    } finally { Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue }

    if ($existing) { $updated++ } else { $imported++ }
}

Write-Host "Done: imported=$imported updated=$updated skipped=$skipped" -ForegroundColor Green
