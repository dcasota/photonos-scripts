<#
.SYNOPSIS
    Generates a Snyk issues report from snyk_issues.db (normalized schema).

.DESCRIPTION
    Consumes the normalized schema produced by Parse-SnykLogs.ps1:
        runs(run_id, package, branch, datetime, ...)
        issues(run_id, priority, title, finding_id, path, line_num, info)
        v_latest_run -- one row per (package,branch), the latest run

    Emits text by default; -Format markdown for GH step summaries; -Format json
    for tooling. -Branch filters every section to that branch -- intended for
    per-branch reports run from the workflow's `for B in branches` loop.

    Report layout:
      - Header: Generated, Total source packages processed, Tool used: SnykCLI
      - Summary (5 metrics)
      - Top 10 High Categories (combined; crypto + non-crypto)
      - Top 10 Source Packages with most issues (with severity breakdown columns)
      - Top 10 Source Packages on Level "High (+ crypto)"
      - Top 10 Source Packages on Level "High"
      - Top 10 Source Packages on Level "Medium"
      - Top 10 Source Packages on Level "Low"

.PARAMETER Database
    SQLite database file. Default: snyk_issues.db.

.PARAMETER ReportFile
    Output report path. Default: SnykReport_<datetime>.<ext>.

.PARAMETER Format
    text | markdown | json

.PARAMETER Branch
    Limit every section to one branch (e.g. "5.0"). Empty = all branches.

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

# PS 7.2+ defaults to ANSI rendering for Format-Table, which inserts U+2502
# vertical-bar box characters between columns and corrupts plain-text output.
# Force plain rendering when the property is available.
if ($PSStyle) { $PSStyle.OutputRendering = 'PlainText' }

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
    $csv = & sqlite3 -header -csv $Database $query
    if (-not $csv) { return @() }
    $csv | ConvertFrom-Csv
}

# Branch filter is applied uniformly. When the report covers a single branch,
# every aggregate is restricted -- categories included.
$brEsc = if ($Branch) { $Branch -replace "'", "''" } else { '' }
$branchFilter   = if ($Branch) { "AND r.branch = '$brEsc'" } else { '' }
$branchFilterLR = if ($Branch) { "WHERE branch = '$brEsc'" } else { '' }

# ------------------------------------------------------------------
# Aggregates
# ------------------------------------------------------------------

# Top 10 High categories (combined: crypto + non-crypto, sorted by count).
$highCats = Q @"
  SELECT i.title AS Category, COUNT(*) AS Count
  FROM issues i JOIN runs r ON r.run_id = i.run_id
  WHERE i.priority = 'HIGH' $branchFilter
  GROUP BY i.title ORDER BY Count DESC LIMIT $TopN;
"@

# Summary over LATEST runs only (matches the example block layout).
$summary = Q @"
  SELECT
    SUM(CASE WHEN i.priority='HIGH' AND lower(i.title) LIKE '%crypto%' THEN 1 ELSE 0 END) AS HighCrypto,
    SUM(CASE WHEN i.priority='HIGH' AND lower(i.title) NOT LIKE '%crypto%' THEN 1 ELSE 0 END) AS HighNonCrypto,
    SUM(CASE WHEN i.priority='MEDIUM' THEN 1 ELSE 0 END) AS Medium,
    SUM(CASE WHEN i.priority='LOW' THEN 1 ELSE 0 END) AS Low,
    SUM(CASE WHEN i.priority IN ('HIGH','MEDIUM','LOW') THEN 1 ELSE 0 END) AS Total
  FROM issues i
  JOIN ( SELECT run_id FROM v_latest_run $branchFilterLR ) lr ON lr.run_id = i.run_id;
"@ | Select-Object -First 1

# Total source packages processed = unique packages with a latest run.
$totalPackages = (Q @"
  SELECT COUNT(DISTINCT package) AS C FROM v_latest_run $branchFilterLR;
"@).C

# Top N packages with the most issues (with breakdown columns).
$topPackages = Q @"
  WITH lr AS ( SELECT run_id,package,branch FROM v_latest_run $branchFilterLR )
  SELECT lr.package AS Package,
    SUM(CASE WHEN i.priority IN ('HIGH','MEDIUM','LOW') THEN 1 ELSE 0 END) AS TotalIssues,
    SUM(CASE WHEN i.priority='HIGH' AND lower(i.title) LIKE '%crypto%' THEN 1 ELSE 0 END) AS HighCrypto,
    SUM(CASE WHEN i.priority='HIGH' THEN 1 ELSE 0 END) AS High,
    SUM(CASE WHEN i.priority='MEDIUM' THEN 1 ELSE 0 END) AS Medium,
    SUM(CASE WHEN i.priority='LOW' THEN 1 ELSE 0 END) AS Low
  FROM issues i JOIN lr ON lr.run_id = i.run_id
  WHERE i.priority IN ('HIGH','MEDIUM','LOW')
  GROUP BY lr.package ORDER BY TotalIssues DESC LIMIT $TopN;
"@

# Top N packages by a single severity bucket.
function TopPackagesBy([string]$bucket) {
    # bucket: 'HighCrypto' | 'High' | 'Medium' | 'Low'
    $where = switch ($bucket) {
        'HighCrypto' { "i.priority='HIGH' AND lower(i.title) LIKE '%crypto%'" }
        'High'       { "i.priority='HIGH'" }
        'Medium'     { "i.priority='MEDIUM'" }
        'Low'        { "i.priority='LOW'" }
    }
    Q @"
      WITH lr AS ( SELECT run_id,package FROM v_latest_run $branchFilterLR )
      SELECT lr.package AS Package, COUNT(*) AS Count
      FROM issues i JOIN lr ON lr.run_id = i.run_id
      WHERE $where
      GROUP BY lr.package
      HAVING Count > 0
      ORDER BY Count DESC LIMIT $TopN;
"@
}
$topHighCrypto = TopPackagesBy 'HighCrypto'
$topHigh       = TopPackagesBy 'High'
$topMedium     = TopPackagesBy 'Medium'
$topLow        = TopPackagesBy 'Low'

# Top N packages for a specific HIGH category title.
function TopPackagesByCategory([string]$title) {
    $tEsc = $title -replace "'", "''"
    Q @"
      WITH lr AS ( SELECT run_id,package FROM v_latest_run $branchFilterLR )
      SELECT lr.package AS Package, COUNT(*) AS Count
      FROM issues i JOIN lr ON lr.run_id = i.run_id
      WHERE i.priority='HIGH' AND i.title='$tEsc'
      GROUP BY lr.package
      HAVING Count > 0
      ORDER BY Count DESC LIMIT $TopN;
"@
}

# For each Top N High Category, capture the Top N packages contributing to it.
$highCatTopPkgs = foreach ($cat in $highCats) {
    [pscustomobject]@{
        Category = $cat.Category
        Count    = $cat.Count
        Packages = @(TopPackagesByCategory $cat.Category)
    }
}

$now           = Get-Date
$generatedFmt  = $now.ToString('MM/dd/yyyy HH:mm:ss')

# ------------------------------------------------------------------
# JSON output
# ------------------------------------------------------------------
if ($Format -eq 'json') {
    $payload = [ordered]@{
        generated                   = $now.ToString('o')
        generated_local             = $generatedFmt
        database                    = $Database
        branch                      = $Branch
        tool                        = 'SnykCLI'
        total_source_packages       = [int]$totalPackages
        summary                     = $summary
        top_high_categories         = @($highCats)
        top_packages_per_high_category = @($highCatTopPkgs)
        top_packages                = @($topPackages)
        top_packages_by_high_crypto = @($topHighCrypto)
        top_packages_by_high        = @($topHigh)
        top_packages_by_medium      = @($topMedium)
        top_packages_by_low         = @($topLow)
    }
    $payload | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $ReportFile -Encoding utf8
    Write-Host "Report saved (JSON): $ReportFile" -ForegroundColor Green
    return
}

# ------------------------------------------------------------------
# Text / Markdown output
# ------------------------------------------------------------------
function FmtTable($data, [string[]]$cols) {
    if (-not $data -or @($data).Count -eq 0) { return "(none)`n" }
    if ($Format -eq 'markdown') {
        $h = ($cols -join ' | '); $sep = (($cols | ForEach-Object { '---' }) -join ' | ')
        $rows = foreach ($r in $data) { ($cols | ForEach-Object { "$($r.$_)" }) -join ' | ' }
        return "| $h |`n| $sep |`n" + (($rows | ForEach-Object { "| $_ |" }) -join "`n") + "`n"
    }
    return ($data | Select-Object $cols | Format-Table -AutoSize | Out-String)
}

$brSuffix = if ($Branch) { " ($Branch)" } else { ' (all branches)' }

# Per-category sub-sections that follow the Top N High Categories table.
# Built upfront so the here-strings below stay simple.
$highCatBlocksMd  = ''
$highCatBlocksTxt = ''
foreach ($entry in $highCatTopPkgs) {
    $heading = "Top $TopN Packages with HIGH issues in category ""$($entry.Category)"" (category total=$($entry.Count))"
    $highCatBlocksMd  += "### $heading`n`n"
    $highCatBlocksMd  += (FmtTable $entry.Packages @('Package','Count')) + "`n"
    $highCatBlocksTxt += "$heading`n"
    $highCatBlocksTxt += (FmtTable $entry.Packages @('Package','Count')) + "`n"
}

if ($Format -eq 'markdown') {
    $report = @"
# Snyk Issues Report$brSuffix

Generated: $generatedFmt
Total source packages processed: $totalPackages
Tool used: SnykCLI

## Summary

| Metric | Count |
|---|---|
| Total issues overall | $($summary.Total) |
| High with crypto | $($summary.HighCrypto) |
| High without crypto | $($summary.HighNonCrypto) |
| Medium | $($summary.Medium) |
| Low | $($summary.Low) |

## Top $TopN High Categories

$(FmtTable $highCats @('Category','Count'))

$highCatBlocksMd
## Top $TopN Source Packages with most issues (with breakdown)

$(FmtTable $topPackages @('Package','TotalIssues','HighCrypto','High','Medium','Low'))

## Top $TopN Source Packages with most issues on Level "High (+ crypto)"

$(FmtTable $topHighCrypto @('Package','Count'))

## Top $TopN Source Packages with most issues on Level "High"

$(FmtTable $topHigh @('Package','Count'))

## Top $TopN Source Packages with most issues on Level "Medium"

$(FmtTable $topMedium @('Package','Count'))

## Top $TopN Source Packages with most issues on Level "Low"

$(FmtTable $topLow @('Package','Count'))
"@
} else {
    $report = @"
Snyk Issues Report$brSuffix

Generated: $generatedFmt
Total source packages processed: $totalPackages
Tool used: SnykCLI


Summary
- Total issues overall: $($summary.Total)
- High with crypto: $($summary.HighCrypto)
- High without crypto: $($summary.HighNonCrypto)
- Medium: $($summary.Medium)
- Low: $($summary.Low)


Top $TopN High Categories
$(FmtTable $highCats @('Category','Count'))

$highCatBlocksTxt
Top $TopN Source Packages with most issues (with breakdown)
$(FmtTable $topPackages @('Package','TotalIssues','HighCrypto','High','Medium','Low'))

Top $TopN Source Packages with most issues on Level "High (+ crypto)"
$(FmtTable $topHighCrypto @('Package','Count'))

Top $TopN Source Packages with most issues on Level "High"
$(FmtTable $topHigh @('Package','Count'))

Top $TopN Source Packages with most issues on Level "Medium"
$(FmtTable $topMedium @('Package','Count'))

Top $TopN Source Packages with most issues on Level "Low"
$(FmtTable $topLow @('Package','Count'))
"@
}

$report | Out-File -LiteralPath $ReportFile -Encoding utf8
Write-Host "Report saved: $ReportFile" -ForegroundColor Green
