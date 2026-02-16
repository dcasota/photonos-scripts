<#
.SYNOPSIS
    Generates a structured Snyk issues report from the snyk_issues.db database (crypto filter + package breakdown).
#>
param (
    [string]$Database = "snyk_issues.db",
    [string]$ReportFile = "SnykReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"   # UPDATED default
)

# Verify database exists
if (-not (Test-Path $Database)) {
    Write-Error "Database '$Database' not found. Run the parser script first."
    exit 1
}

Write-Host "Generating report from $Database ..." -ForegroundColor Cyan

# Get all snyk_* tables
$tablesRaw = & sqlite3 $Database "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'snyk_%';"
$tables = $tablesRaw -split "`n" | Where-Object { $_ -ne '' }

$allIssues = @()
$header = "SourcePackage,Filename,Datetime,Priority,Title,FindingID,Path,LineNum,Info,TotalIssues,IgnoredIssues,OpenIssues"

foreach ($tbl in $tables) {
    $query = "SELECT SourcePackage,Filename,Datetime,Priority,Title,FindingID,Path,LineNum,Info,TotalIssues,IgnoredIssues,OpenIssues FROM `"$tbl`""
    $csvData = & sqlite3 -csv $Database $query
    if ($csvData) {
        $csvWithHeader = $header + "`n" + ($csvData -join "`n")
        $allIssues += $csvWithHeader | ConvertFrom-Csv
    }
}

if ($allIssues.Count -eq 0) {
    Write-Host "No issues found in database." -ForegroundColor Yellow
    "No data available." | Out-File $ReportFile
    exit 0
}

# Latest run per source package (max Datetime per SourcePackage)
$latestIssues = $allIssues | Group-Object SourcePackage | ForEach-Object {
    $grp = $_.Group
    $maxDt = ($grp | Measure-Object -Property Datetime -Maximum).Maximum
    $grp | Where-Object { $_.Datetime -eq $maxDt }
}

# === Issue Category Overview (all issues) ===
$highCryptoCats = $allIssues |
    Where-Object { $_.Priority -eq 'HIGH' -and $_.Title -like '*crypto*' } |
    Group-Object Title |
    Sort-Object Count -Descending |
    Select-Object @{Name='Category';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} -First 10

$highNoCryptoCats = $allIssues |
    Where-Object { $_.Priority -eq 'HIGH' -and $_.Title -notlike '*crypto*' } |
    Group-Object Title |
    Sort-Object Count -Descending |
    Select-Object @{Name='Category';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} -First 10

$mediumCats = $allIssues |
    Where-Object { $_.Priority -eq 'MEDIUM' } |
    Group-Object Title |
    Sort-Object Count -Descending |
    Select-Object @{Name='Category';Expression={$_.Name}}, @{Name='Count';Expression={$_.Count}} -First 10

# === Summary Overview (latest runs only) ===
$totalOverall = $latestIssues.Count
$highCryptoSum = ($latestIssues | Where-Object { $_.Priority -eq 'HIGH' -and $_.Title -like '*crypto*' }).Count
$highNoCryptoSum = ($latestIssues | Where-Object { $_.Priority -eq 'HIGH' -and $_.Title -notlike '*crypto*' }).Count
$mediumSum = ($latestIssues | Where-Object Priority -eq 'MEDIUM').Count
$lowSum = ($latestIssues | Where-Object Priority -eq 'LOW').Count

# === Source Package Overview (latest runs only) ===
$pkgData = $latestIssues | Group-Object SourcePackage | ForEach-Object {
    $pkg = $_.Name
    $rows = $_.Group
    $total = $rows.Count
    $highCrypto = ($rows | Where-Object { $_.Priority -eq 'HIGH' -and $_.Title -like '*crypto*' }).Count
    $highTotal = ($rows | Where-Object { $_.Priority -eq 'HIGH' }).Count
    $medium = ($rows | Where-Object { $_.Priority -eq 'MEDIUM' }).Count
    $low = ($rows | Where-Object { $_.Priority -eq 'LOW' }).Count
    [PSCustomObject]@{
        Package           = $pkg
        'Total Issues'    = $total
        'High (+ crypto)' = $highCrypto
        'High'            = $highTotal
        'Medium'          = $medium
        'Low'             = $low
    }
} | Sort-Object 'Total Issues' -Descending | Select-Object -First 10

# Build report
$report = @"
# Snyk Issues Report (crypto filter + package breakdown)
Generated: $(Get-Date)
Database: $Database
Total runs processed: $($tables.Count)

## Issue Category Overview (all issues)

### Top 10 High Categories with "crypto" in title (case-independent)
$($highCryptoCats | Format-Table -AutoSize | Out-String)

### Top 10 High Categories without "crypto" (case-independent)
$($highNoCryptoCats | Format-Table -AutoSize | Out-String)

### Top 10 Medium Categories
$($mediumCats | Format-Table -AutoSize | Out-String)

## Summary Overview (latest run per source package only)
- Total issues overall: $totalOverall
- High with crypto: $highCryptoSum
- High without crypto: $highNoCryptoSum
- Medium: $mediumSum
- Low: $lowSum

## Source Package Overview (latest run per source package only)

### Top 10 Source Packages with most issues (with breakdown)
$($pkgData | Format-Table -AutoSize | Out-String)
"@

$report | Out-File -FilePath $ReportFile -Encoding utf8
Write-Host "Report saved to: $ReportFile" -ForegroundColor Green
Write-Host "Open the file for full formatted view." -ForegroundColor Cyan
