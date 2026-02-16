<#
.SYNOPSIS
    Loops through all immediate subdirectories of a given base directory
    and runs "snyk code test" on each one, redirecting all output to a log file.

.PARAMETER BaseDir
    The base directory containing the subdirectories to process.
    This parameter is mandatory.
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the base directory")]
    [string]$BaseDir
)

# Validate the base directory exists
if (-not (Test-Path $BaseDir -PathType Container)) {
    Write-Error "Base directory does not exist or is not a folder: $BaseDir"
    exit 1
}

# Process each immediate subdirectory
foreach ($subdir in Get-ChildItem -Path $BaseDir -Directory) {
    $datetime = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Log file will be placed next to the subdirectory (same folder as BaseDir)
    # Example: C:\basedir\aufs-linux_snyk_20260216_204500.log
    $logFile = Join-Path (Split-Path $subdir.FullName -Parent) "$($subdir.Name)_snyk_${datetime}.log"

    Write-Host "Processing: $($subdir.Name)  →  $logFile" -ForegroundColor Cyan

    # Run snyk and redirect BOTH stdout and stderr to the log file
    # (compatible with Windows PowerShell 5.1 and PowerShell 7+)
    snyk code test "$($subdir.FullName)" 2>&1 > "$logFile"
}

Write-Host "Done! Processed $($subdir.Count) subdirectories." -ForegroundColor Green
