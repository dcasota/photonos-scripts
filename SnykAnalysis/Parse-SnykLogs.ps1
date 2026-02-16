<#
.SYNOPSIS
    Parses *_snyk*.log files recursively and stores results in per-file SQLite tables.
#>
param (
    [string]$Directory = ".",
    [string]$Database = "snyk_issues.db",
    [bool]$Recursive = $true   # NEW: Externalized recursion control (default: recursive)
)

# Verify sqlite3
if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Error "sqlite3 not found. Install: sudo apt install sqlite3 (Debian/Ubuntu) or equivalent."
    exit 1
}

# Ensure database file exists
if (-not (Test-Path $Database)) {
    Write-Host "Creating new database: $Database" -ForegroundColor Yellow
    & sqlite3 $Database "VACUUM;"
} else {
    Write-Host "Using existing database: $Database" -ForegroundColor Cyan
}

# Scanning feedback (now shows recursion setting)
Write-Host "Scanning directory '$Directory' $(if($Recursive){'(recursive)'}else{'(top-level only)'}) for files matching '*_snyk*.log'..." -ForegroundColor Gray
$logFiles = Get-ChildItem -Path $Directory -Recurse:$Recursive -Filter "*_snyk*.log" -ErrorAction SilentlyContinue
Write-Host "Found $($logFiles.Count) matching log files." -ForegroundColor Gray
if ($logFiles.Count -eq 0) {
    Write-Host "No matching files found. Verify the directory path contains *_snyk*.log files $(if($Recursive){'or subfolders'}else{'in the top level only'})." -ForegroundColor Yellow
    exit 0
}

function Escape-SqlValue {
    param([string]$Value)
    if ($null -eq $Value -or $Value -eq '') { return 'NULL' }
    "'" + ($Value -replace "'", "''") + "'"
}

foreach ($logFile in $logFiles) {
    $filename = $logFile.Name
    Write-Host "Processing file: $filename" -ForegroundColor Green

    $content = Get-Content $logFile.FullName

    # Metadata
    $projectPath = $null; $totalIssues = 0; $ignoredIssues = 0; $openIssues = 0
    foreach ($line in $content) {
        if ($line -match 'Project path:\s*(.+)') { $projectPath = $matches[1].Trim() }
        if ($line -match 'Total issues:\s*(\d+)') { $totalIssues = [int]$matches[1] }
        if ($line -match 'Ignored issues:\s*(\d+)') { $ignoredIssues = [int]$matches[1] }
        if ($line -match 'Open issues:\s*(\d+)') { $openIssues = [int]$matches[1] }
    }
    if ($projectPath) {
        $package = $projectPath.Split('/')[-1].Trim()
    } else {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($filename)
        $package = ($baseName -split '_snyk_')[0]
    }

    $datetimeStr = ''
    if ($filename -match '_snyk_(\d{8})_(\d{6})\.log$') {
        $datetimeStr = "$($matches[1])_$($matches[2])"
    } else {
        $datetimeStr = (Get-Date).ToString("yyyyMMdd_HHmmss")
    }

    $safePackage = $package -replace '[^a-zA-Z0-9_]', '_'
    $tableName = "snyk_${safePackage}_${datetimeStr}"

    # Parse issues
    $issues = @()
    for ($i = 0; $i -lt $content.Count; $i++) {
        $line = $content[$i]
        if ($line -match '^\s*✗\s*\[([^\]]+)\]\s*(.+)') {
            $priority = $matches[1].Trim()
            $title = $matches[2].Trim()
            $i++
            $findingID = if ($i -lt $content.Count -and $content[$i] -match 'Finding ID:\s*(.+)') { $matches[1].Trim() } else { '' }
            $i++
            $path = ''; $lineNum = ''
            if ($i -lt $content.Count) {
                $pathLine = $content[$i]
                if ($pathLine -match 'Path:\s*(.+?)(?:,\s*line\s*(\d+))?') {
                    $path = $matches[1].Trim()
                    $lineNum = if ($matches[2]) { $matches[2] } else { '' }
                } else {
                    $path = $pathLine.Trim()
                }
            }
            $i++
            $info = if ($i -lt $content.Count -and $content[$i] -match 'Info:\s*(.+)') { $matches[1].Trim() } else { $content[$i].Trim() }
            $issues += [PSCustomObject]@{Priority=$priority; Title=$title; FindingID=$findingID; Path=$path; Line=$lineNum; Info=$info}
        }
    }

    # Build & execute SQL
    $sql = "CREATE TABLE IF NOT EXISTS `"$tableName`" (SourcePackage TEXT, Filename TEXT, Datetime TEXT, Priority TEXT, Title TEXT, FindingID TEXT, Path TEXT, LineNum TEXT, Info TEXT, TotalIssues INTEGER, IgnoredIssues INTEGER, OpenIssues INTEGER);`n"

    if ($issues.Count -gt 0) {
        foreach ($iss in $issues) {
            $sql += "INSERT INTO `"$tableName`" (SourcePackage, Filename, Datetime, Priority, Title, FindingID, Path, LineNum, Info, TotalIssues, IgnoredIssues, OpenIssues) VALUES ("
            $sql += "$(Escape-SqlValue $package), $(Escape-SqlValue $filename), $(Escape-SqlValue $datetimeStr), "
            $sql += "$(Escape-SqlValue $iss.Priority), $(Escape-SqlValue $iss.Title), $(Escape-SqlValue $iss.FindingID), "
            $sql += "$(Escape-SqlValue $iss.Path), $(Escape-SqlValue $iss.Line), $(Escape-SqlValue $iss.Info), "
            $sql += "$totalIssues, $ignoredIssues, $openIssues);`n"
        }
    } else {
        $sql += "INSERT INTO `"$tableName`" (SourcePackage, Filename, Datetime, Priority, Title, FindingID, Path, LineNum, Info, TotalIssues, IgnoredIssues, OpenIssues) VALUES ("
        $sql += "$(Escape-SqlValue $package), $(Escape-SqlValue $filename), $(Escape-SqlValue $datetimeStr), 'SUMMARY', "
        $sql += "$(Escape-SqlValue 'No open issues or processing error'), NULL, NULL, NULL, NULL, "
        $sql += "$totalIssues, $ignoredIssues, $openIssues);`n"
    }

    $tempFile = New-TemporaryFile
    $sql | Out-File -FilePath $tempFile.FullName -Encoding utf8
    & sqlite3 $Database ".read $($tempFile.FullName)"
    Remove-Item $tempFile.FullName -Force

    Write-Host "Completed processing of $filename → table $tableName ($($issues.Count) issues)" -ForegroundColor Cyan
}
