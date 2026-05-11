<#
.SYNOPSIS
    Parses snyk-agent-scan JSON outputs into the existing snyk_issues.db.

.DESCRIPTION
    Companion to Parse-SnykLogs.ps1. Walks `*_agentscan_*.json` files
    produced by the Snyk Analysis workflow's agent-scan step and imports
    them into two new tables in the same SQLite DB:

        agent_scans   one row per (package, branch, agent_type, timestamp)
        agent_issues  one row per finding, joined to agent_scans

    Plus a view `v_latest_agent_scan` that returns the newest scan per
    (package, branch, agent_type) -- analogous to v_latest_run for SAST.

    Idempotent: agent_scans.log_file is UNIQUE, so re-parsing the same
    log is a no-op unless -Reparse is set (drops + re-imports). -Rebuild
    wipes the agent_* tables before parsing.

    Filename convention (set by snyk-analysis.yml):
        <package>_agentscan_<branch>_<agent_type>_<YYYYMMDD_HHMMSS>.json
    e.g. calico_agentscan_5.0_claude_20260511_103000.json

.PARAMETER Directory
    Directory to scan for *_agentscan_*.json files. Default: current dir.

.PARAMETER Database
    SQLite database file. Created if missing. Default: snyk_issues.db.

.PARAMETER Recursive
    Recurse into subdirectories. Default: $true.

.PARAMETER Reparse
    Drop+reimport rows for any log already in agent_scans.log_file.

.PARAMETER Rebuild
    Wipe agent_scans+agent_issues before parsing.
#>
[CmdletBinding()]
param(
    [string]$Directory = '.',
    [string]$Database  = 'snyk_issues.db',
    [bool]$Recursive   = $true,
    [switch]$Reparse,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Error "sqlite3 not found on PATH."
    exit 2
}

# Schema -- created additively so it co-exists with runs/issues from
# Parse-SnykLogs.ps1 in the same DB file.
$schema = @'
CREATE TABLE IF NOT EXISTS agent_scans (
    scan_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    package      TEXT NOT NULL,
    branch       TEXT,
    datetime     TEXT,
    agent_type   TEXT,
    config_path  TEXT,
    log_file     TEXT UNIQUE,
    log_size     INTEGER,
    total_issues INTEGER,
    scan_version TEXT
);
CREATE TABLE IF NOT EXISTS agent_issues (
    issue_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id    INTEGER NOT NULL REFERENCES agent_scans(scan_id) ON DELETE CASCADE,
    code       TEXT,
    severity   TEXT,
    category   TEXT,
    artefact   TEXT,
    message    TEXT,
    raw        TEXT
);
CREATE INDEX IF NOT EXISTS idx_agent_scans_pkgbranch ON agent_scans(package, branch);
CREATE INDEX IF NOT EXISTS idx_agent_scans_agent    ON agent_scans(agent_type);
CREATE INDEX IF NOT EXISTS idx_agent_issues_scanid  ON agent_issues(scan_id);
CREATE INDEX IF NOT EXISTS idx_agent_issues_sev     ON agent_issues(severity);
CREATE INDEX IF NOT EXISTS idx_agent_issues_code    ON agent_issues(code);
CREATE VIEW IF NOT EXISTS v_latest_agent_scan AS
    SELECT s.* FROM agent_scans s
    JOIN ( SELECT package, branch, agent_type, MAX(datetime) AS max_dt
           FROM agent_scans GROUP BY package, branch, agent_type ) m
      ON s.package     = m.package
     AND COALESCE(s.branch,'')     = COALESCE(m.branch,'')
     AND COALESCE(s.agent_type,'') = COALESCE(m.agent_type,'')
     AND s.datetime    = m.max_dt;
'@

$tmp = New-TemporaryFile
try {
    $schema | Out-File -LiteralPath $tmp.FullName -Encoding utf8
    & sqlite3 $Database ".read $($tmp.FullName)"
} finally { Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue }

if ($Rebuild) {
    Write-Host "Rebuild requested - wiping agent_scans+agent_issues before re-parse" -ForegroundColor Yellow
    & sqlite3 $Database "DELETE FROM agent_issues; DELETE FROM agent_scans; VACUUM;"
    $Reparse = $true
}

# Defensive orphan cleanup parallel to Parse-SnykLogs.ps1.
$orphanCount = (& sqlite3 $Database "SELECT COUNT(*) FROM agent_issues WHERE scan_id NOT IN (SELECT scan_id FROM agent_scans);").Trim()
if ($orphanCount -and [int]$orphanCount -gt 0) {
    Write-Host "Cleaning up $orphanCount orphaned agent_issues rows" -ForegroundColor Yellow
    & sqlite3 $Database "DELETE FROM agent_issues WHERE scan_id NOT IN (SELECT scan_id FROM agent_scans);"
}

$logFiles = Get-ChildItem -Path $Directory -Recurse:$Recursive -Filter '*_agentscan_*.json' -File -ErrorAction SilentlyContinue
Write-Host "Found $($logFiles.Count) agent-scan log files under '$Directory' (recursive=$Recursive)" -ForegroundColor Gray
if ($logFiles.Count -eq 0) { exit 0 }

function Sql([string]$value) {
    if ($null -eq $value -or $value -eq '') { return 'NULL' }
    "'" + ($value -replace "'", "''") + "'"
}

# Parse filename: <package>_agentscan_<branch>_<agent_type>_<yyyymmdd>_<hhmmss>.json
function Parse-LogName([string]$name) {
    if ($name -match '^(?<pkg>.+?)_agentscan_(?<br>[^_]+)_(?<agent>[^_]+)_(?<d>\d{8})_(?<t>\d{6})\.json$') {
        return @{
            Package   = $matches.pkg
            Branch    = $matches.br
            AgentType = $matches.agent
            Datetime  = "$($matches.d)_$($matches.t)"
        }
    }
    return $null
}

# Flatten the agent-scan JSON's `issues` (or similar) array. The exact
# schema isn't formally documented; we look for any list-of-objects field
# at the top level and inspect common keys. Anything we can't extract
# structurally goes into the `raw` column unchanged.
function Extract-Issues([object]$doc) {
    $issues = @()
    if ($null -eq $doc) { return ,$issues }
    foreach ($key in @('issues','findings','results','vulnerabilities')) {
        try {
            $arr = $doc.$key
            if ($null -ne $arr) {
                $arr = @($arr)
                foreach ($it in $arr) { $issues += ,$it }
            }
        } catch {}
    }
    # Some Snyk JSON wraps per-server: { servers: { name: { issues: [...] } } }
    try {
        $servers = $doc.servers
        if ($null -ne $servers) {
            foreach ($svr in $servers.PSObject.Properties) {
                $arr = $svr.Value.issues
                if ($null -ne $arr) {
                    foreach ($it in @($arr)) { $issues += ,$it }
                }
            }
        }
    } catch {}
    return ,$issues
}

function _Get([object]$obj, [string[]]$keys) {
    foreach ($k in $keys) {
        try {
            $v = $obj.$k
            if ($null -ne $v -and "$v" -ne '') { return "$v" }
        } catch {}
    }
    return ''
}

$imported = 0
$updated  = 0
$skipped  = 0

foreach ($logFile in $logFiles) {
    $logPath = $logFile.FullName
    $existing = (& sqlite3 $Database "SELECT scan_id FROM agent_scans WHERE log_file=$(Sql $logPath);")
    if ($existing -and -not $Reparse) {
        $skipped++
        continue
    }

    $meta = Parse-LogName $logFile.Name
    if (-not $meta) {
        Write-Warning "Skipping $($logFile.Name) -- filename doesn't match <pkg>_agentscan_<br>_<agent>_<datetime>.json"
        continue
    }

    $rawText = Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue
    if (-not $rawText) {
        Write-Warning "Empty file: $($logFile.Name)"
        continue
    }

    $doc = $null
    try { $doc = $rawText | ConvertFrom-Json -ErrorAction Stop } catch {
        Write-Warning "Invalid JSON in $($logFile.Name): $($_.Exception.Message)"
    }

    $configPath  = if ($doc) { _Get $doc @('config_path','path','scanned_path','target') } else { '' }
    $scanVersion = if ($doc) { _Get $doc @('version','scanner_version','snyk_agent_scan_version') } else { '' }

    $issues = Extract-Issues $doc
    $total  = @($issues).Count

    $logSql = Sql $logPath
    $sql = "BEGIN;`n"
    if ($existing) {
        $sql += "DELETE FROM agent_issues WHERE scan_id IN (SELECT scan_id FROM agent_scans WHERE log_file=$logSql);`n"
        $sql += "DELETE FROM agent_scans WHERE log_file=$logSql;`n"
    }
    $sql += "INSERT INTO agent_scans (package,branch,datetime,agent_type,config_path,log_file,log_size,total_issues,scan_version) VALUES ("
    $sql += "$(Sql $meta.Package),$(Sql $meta.Branch),$(Sql $meta.Datetime),$(Sql $meta.AgentType),$(Sql $configPath),$logSql,$($logFile.Length),$total,$(Sql $scanVersion));`n"

    if ($total -gt 0) {
        $sql += "INSERT INTO agent_issues (scan_id,code,severity,category,artefact,message,raw)`n  VALUES`n"
        $rows = @()
        foreach ($iss in $issues) {
            $code     = _Get $iss @('code','rule','id','issue_code')
            $severity = _Get $iss @('severity','level','priority')
            $category = _Get $iss @('category','type','class')
            $artefact = _Get $iss @('artefact','artifact','tool','file','path','source')
            $message  = _Get $iss @('message','title','description','msg')
            $rawJson  = try { $iss | ConvertTo-Json -Depth 6 -Compress } catch { '' }
            $rows += "  ((SELECT scan_id FROM agent_scans WHERE log_file=$logSql),$(Sql $code),$(Sql $severity),$(Sql $category),$(Sql $artefact),$(Sql $message),$(Sql $rawJson))"
        }
        $sql += ($rows -join ",`n") + ";`n"
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
