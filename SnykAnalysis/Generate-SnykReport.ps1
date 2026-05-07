<#
.SYNOPSIS
    Generates a Snyk issues report from snyk_issues.db (normalized schema).

.DESCRIPTION
    Consumes the normalized schema produced by Parse-SnykLogs.ps1:
        runs(run_id, package, branch, datetime, ...)
        issues(run_id, priority, title, finding_id, path, line_num, info)
        v_latest_run — one row per (package,branch), the latest run

    Emits text by default; -Format Markdown for GH step summaries; -Format Json for tooling.
    -Branch filters the package overview to a single branch (categories still cover all data).

.PARAMETER Database
    SQLite database file. Default: snyk_issues.db.

.PARAMETER ReportFile
    Output report path. Default: SnykReport_<datetime>.<ext>.

.PARAMETER Format
    text | markdown | json

.PARAMETER Branch
    Limit the package overview / summary to one branch (e.g. "5.0").

.PARAMETER TopN
    Max rows in each top-N table. Default 10.
#>
[CmdletBinding()]
param(
    [string]$Database  = 'snyk_issues.db',
    [ValidateSet('text','markdown','json')]
    [string]$Format    = 'text',
    [string]$ReportFile = '',
    [string]$Branch    = '',
    [int]$TopN         = 10
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Database)) {
    Write-Error "Database '$Database' not found. Run Parse-SnykLogs.ps1 first."
    exit 2
}
if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Error "sqlite3 not found on PATH."
    exit 2
}

if ([string]::IsNullOrEmpty($ReportFile)) {
    $ext = switch ($Format) { 'markdown' { 'md' } 'json' { 'json' } default { 'txt' } }
    $ReportFile = "SnykReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').$ext"
}

function Q([string]$query) {
    # Returns CSV rows; first row = header. Caller parses.
    $csv = & sqlite3 -header -csv $Database $query
    if (-not $csv) { return @() }
    $csv | ConvertFrom-Csv
}

$brEsc = if ($Branch) { $Branch -replace "'", "''" } else { '' }
$branchFilter   = if ($Branch) { "AND r.branch = '$brEsc'" } else { '' }
$branchFilterLR = if ($Branch) { "WHERE branch = '$brEsc'" } else { '' }

# === Aggregates over ALL data (categories) ===
$highCryptoCats = Q @"
  SELECT i.title AS Category, COUNT(*) AS Count
  FROM issues i JOIN runs r ON r.run_id = i.run_id
  WHERE i.priority = 'HIGH' AND lower(i.title) LIKE '%crypto%' $branchFilter
  GROUP BY i.title ORDER BY Count DESC LIMIT $TopN;
"@

$highNonCryptoCats = Q @"
  SELECT i.title AS Category, COUNT(*) AS Count
  FROM issues i JOIN runs r ON r.run_id = i.run_id
  WHERE i.priority = 'HIGH' AND lower(i.title) NOT LIKE '%crypto%' $branchFilter
  GROUP BY i.title ORDER BY Count DESC LIMIT $TopN;
"@

$mediumCats = Q @"
  SELECT i.title AS Category, COUNT(*) AS Count
  FROM issues i JOIN runs r ON r.run_id = i.run_id
  WHERE i.priority = 'MEDIUM' $branchFilter
  GROUP BY i.title ORDER BY Count DESC LIMIT $TopN;
"@

# === Summary over LATEST runs only ===
$summary = Q @"
  SELECT
    SUM(CASE WHEN i.priority='HIGH' AND lower(i.title) LIKE '%crypto%' THEN 1 ELSE 0 END) AS HighCrypto,
    SUM(CASE WHEN i.priority='HIGH' AND lower(i.title) NOT LIKE '%crypto%' THEN 1 ELSE 0 END) AS HighNonCrypto,
    SUM(CASE WHEN i.priority='MEDIUM' THEN 1 ELSE 0 END) AS Medium,
    SUM(CASE WHEN i.priority='LOW' THEN 1 ELSE 0 END) AS Low,
    COUNT(*) AS Total
  FROM issues i
  JOIN ( SELECT run_id FROM v_latest_run $branchFilterLR ) lr ON lr.run_id = i.run_id
  WHERE i.priority IN ('HIGH','MEDIUM','LOW');
"@ | Select-Object -First 1

# === Top packages (latest run per pkg/branch) ===
$topPackages = Q @"
  WITH lr AS ( SELECT run_id,package,branch FROM v_latest_run $branchFilterLR )
  SELECT lr.package AS Package, lr.branch AS Branch, COUNT(*) AS TotalIssues,
    SUM(CASE WHEN i.priority='HIGH' AND lower(i.title) LIKE '%crypto%' THEN 1 ELSE 0 END) AS HighCrypto,
    SUM(CASE WHEN i.priority='HIGH' THEN 1 ELSE 0 END) AS High,
    SUM(CASE WHEN i.priority='MEDIUM' THEN 1 ELSE 0 END) AS Medium,
    SUM(CASE WHEN i.priority='LOW' THEN 1 ELSE 0 END) AS Low
  FROM issues i JOIN lr ON lr.run_id = i.run_id
  WHERE i.priority IN ('HIGH','MEDIUM','LOW')
  GROUP BY lr.package, lr.branch ORDER BY TotalIssues DESC LIMIT $TopN;
"@

# === Per-branch breakdown (latest run per pkg) ===
$perBranch = Q @"
  WITH lr AS ( SELECT run_id,branch FROM v_latest_run )
  SELECT COALESCE(NULLIF(lr.branch,''),'(unknown)') AS Branch,
    COUNT(DISTINCT lr.run_id) AS Packages,
    SUM(CASE WHEN i.priority='HIGH' THEN 1 ELSE 0 END) AS High,
    SUM(CASE WHEN i.priority='MEDIUM' THEN 1 ELSE 0 END) AS Medium,
    SUM(CASE WHEN i.priority='LOW' THEN 1 ELSE 0 END) AS Low,
    COUNT(*) AS TotalIssues
  FROM issues i JOIN lr ON lr.run_id = i.run_id
  WHERE i.priority IN ('HIGH','MEDIUM','LOW')
  GROUP BY lr.branch ORDER BY TotalIssues DESC;
"@

$totalRuns = (Q "SELECT COUNT(*) AS C FROM runs;").C
$now       = Get-Date

if ($Format -eq 'json') {
    $payload = [ordered]@{
        generated  = $now.ToString('o')
        database   = $Database
        branch     = $Branch
        total_runs = [int]$totalRuns
        summary    = $summary
        per_branch = @($perBranch)
        categories = [ordered]@{
            high_crypto     = @($highCryptoCats)
            high_non_crypto = @($highNonCryptoCats)
            medium          = @($mediumCats)
        }
        top_packages = @($topPackages)
    }
    $payload | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $ReportFile -Encoding utf8
    Write-Host "Report saved (JSON): $ReportFile" -ForegroundColor Green
    return
}

function FmtTable($data, [string[]]$cols) {
    if (-not $data -or @($data).Count -eq 0) { return "(none)`n" }
    if ($Format -eq 'markdown') {
        $h = ($cols -join ' | '); $sep = (($cols | ForEach-Object { '---' }) -join ' | ')
        $rows = foreach ($r in $data) { ($cols | ForEach-Object { "$($r.$_)" }) -join ' | ' }
        return "| $h |`n| $sep |`n" + (($rows | ForEach-Object { "| $_ |" }) -join "`n") + "`n"
    }
    return ($data | Select-Object $cols | Format-Table -AutoSize | Out-String)
}

$brFilter = if ($Branch) { " (branch=$Branch)" } else { '' }

$report = if ($Format -eq 'markdown') { @"
# Snyk Issues Report$brFilter

- Generated: $now
- Database: $Database
- Total runs: $totalRuns

## Summary (latest run per package/branch)

| Metric | Value |
|---|---|
| Total issues | $($summary.Total) |
| High (crypto) | $($summary.HighCrypto) |
| High (non-crypto) | $($summary.HighNonCrypto) |
| Medium | $($summary.Medium) |
| Low | $($summary.Low) |

## Per-branch breakdown
$(FmtTable $perBranch @('Branch','Packages','High','Medium','Low','TotalIssues'))

## Top High categories (crypto)
$(FmtTable $highCryptoCats @('Category','Count'))

## Top High categories (non-crypto)
$(FmtTable $highNonCryptoCats @('Category','Count'))

## Top Medium categories
$(FmtTable $mediumCats @('Category','Count'))

## Top $TopN packages
$(FmtTable $topPackages @('Package','Branch','TotalIssues','HighCrypto','High','Medium','Low'))
"@ } else { @"
# Snyk Issues Report$brFilter
Generated: $now
Database:  $Database
Total runs: $totalRuns

## Summary (latest run per package/branch)
- Total issues: $($summary.Total)
- High (crypto): $($summary.HighCrypto)
- High (non-crypto): $($summary.HighNonCrypto)
- Medium: $($summary.Medium)
- Low:    $($summary.Low)

## Per-branch breakdown
$(FmtTable $perBranch @('Branch','Packages','High','Medium','Low','TotalIssues'))
## Top High categories (crypto)
$(FmtTable $highCryptoCats @('Category','Count'))
## Top High categories (non-crypto)
$(FmtTable $highNonCryptoCats @('Category','Count'))
## Top Medium categories
$(FmtTable $mediumCats @('Category','Count'))
## Top $TopN packages
$(FmtTable $topPackages @('Package','Branch','TotalIssues','HighCrypto','High','Medium','Low'))
"@ }

$report | Out-File -LiteralPath $ReportFile -Encoding utf8
Write-Host "Report saved: $ReportFile" -ForegroundColor Green
