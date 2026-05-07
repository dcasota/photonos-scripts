<#
.SYNOPSIS
    Runs `snyk code test` on each immediate subdirectory of -BaseDir, writing one log per subdir.

.DESCRIPTION
    Designed to consume the photon-upstreams clone tree produced by photonos-package-report.ps1:
        ${workingDir}/photon-upstreams/photon-${branch}/clones/<package>/<source>
    Each subdir of BaseDir is treated as a single project. Logs go to -LogDir (default: BaseDir).

    Idempotent: skips a subdir if a log named ${pkg}_snyk_*.log already exists in -LogDir
    (override with -Force). Tracks success/fail counts and exits non-zero if any scan failed.

.PARAMETER BaseDir
    Path to the directory whose immediate subdirectories should be scanned.

.PARAMETER LogDir
    Where to write log files. Defaults to BaseDir.

.PARAMETER Branch
    Photon branch tag, embedded in the log filename so downstream parsing can attribute
    findings to a branch (e.g. "5.0", "master"). Optional.

.PARAMETER Skip
    Package names (subdir basenames) to skip. Useful for re-running after a partial scan.

.PARAMETER MaxSubdirs
    Process at most N subdirs (in lexicographic order). 0 = no limit.

.PARAMETER Force
    Re-scan even if a log file for the package already exists.

.EXAMPLE
    ./Run-SnykOnSubdirs.ps1 -BaseDir /mnt/d/photon-upstreams/photon-5.0/clones -Branch 5.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$BaseDir,
    [string]$LogDir = '',
    [string]$Branch = '',
    [string[]]$Skip = @(),
    [int]$MaxSubdirs = 0,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BaseDir -PathType Container)) {
    Write-Error "BaseDir does not exist or is not a directory: $BaseDir"
    exit 2
}
if (-not (Get-Command snyk -ErrorAction SilentlyContinue)) {
    Write-Error "snyk CLI not found on PATH. Install it and run 'snyk auth' first."
    exit 2
}

if ([string]::IsNullOrEmpty($LogDir)) { $LogDir = $BaseDir }
if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$branchTag = if ($Branch) { "_$($Branch -replace '[^a-zA-Z0-9._-]','_')" } else { '' }
$skipSet = @{}
foreach ($s in $Skip) { $skipSet[$s] = $true }

$subdirs = Get-ChildItem -LiteralPath $BaseDir -Directory | Sort-Object Name
if ($MaxSubdirs -gt 0 -and $subdirs.Count -gt $MaxSubdirs) {
    $subdirs = $subdirs | Select-Object -First $MaxSubdirs
}

$total   = $subdirs.Count
$ok      = 0
$failed  = 0
$skipped = 0
$index   = 0
$started = Get-Date

Write-Host "Run-SnykOnSubdirs: $total subdirs, branch='$Branch', logDir='$LogDir'" -ForegroundColor Cyan

foreach ($subdir in $subdirs) {
    $index++
    $pkg = $subdir.Name

    if ($skipSet.ContainsKey($pkg)) {
        Write-Host "[$index/$total] SKIP (Skip): $pkg" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if (-not $Force) {
        $existing = Get-ChildItem -LiteralPath $LogDir -Filter "${pkg}_snyk*.log" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "[$index/$total] SKIP (already logged): $pkg" -ForegroundColor DarkGray
            $skipped++
            continue
        }
    }

    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFile = Join-Path $LogDir "${pkg}_snyk${branchTag}_${stamp}.log"

    Write-Host "[$index/$total] $pkg -> $logFile" -ForegroundColor Cyan
    try {
        snyk code test "$($subdir.FullName)" *> "$logFile"
        $rc = $LASTEXITCODE
    } catch {
        $rc = 1
        Add-Content -LiteralPath $logFile -Value "RUN-SNYK-ON-SUBDIRS: exception: $_"
    }
    # snyk exit codes: 0 = no issues, 1 = issues found, 2 = CLI error, 3 = no tests found.
    if ($rc -eq 0 -or $rc -eq 1 -or $rc -eq 3) {
        $ok++
    } else {
        $failed++
        Write-Warning "snyk failed for ${pkg} (exit $rc)"
    }
}

$elapsed = (Get-Date) - $started
Write-Host ""
Write-Host "Done in $($elapsed.ToString('hh\:mm\:ss')): ok=$ok failed=$failed skipped=$skipped total=$total" -ForegroundColor Green

if ($failed -gt 0) { exit 1 }
exit 0
