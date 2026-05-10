<#
.SYNOPSIS
    Fetch the latest package-report workflow artifact (or use a local scans dir)
    and extract a deduplicated list of upstream package URLs into urls.txt.

.DESCRIPTION
    Implements Option A from the analysis: pull the latest successful
    package-report.yml run's `package-reports` artifact via the gh CLI,
    extract the URLs from each `photonos-urlhealth-<branch>_*.prn` CSV,
    sort + dedupe, and write to -OutputFile (default ./urls.txt).

    Designed to feed Get-CybersecurityToolsWithGrok.ps1.

    The .prn files are CSVs with this header:
        Spec, Source0 original, Modified Source0 for url health check,
        UrlHealth, UpdateAvailable, UpdateURL, HealthUpdateURL,
        Name, SHAName, UpdateDownloadName, warning, ArchivationDate

    Columns 3 (expanded Source0) and 6 (upstream UpdateURL) hold the URLs.

.PARAMETER OutputFile
    File to write deduplicated URLs to. Default: ./urls.txt.

.PARAMETER Repo
    GitHub owner/repo. Default: dcasota/photonos-scripts.

.PARAMETER RunId
    Specific run id to download from. Default: latest successful run of
    package-report.yml.

.PARAMETER Branches
    Photon branches to include (one URL-health file is taken per branch,
    latest by filename timestamp). Default: 3.0,4.0,5.0,6.0,common,dev,master.

.PARAMETER ScansDir
    If set, skip the download and read photonos-urlhealth-*.prn from this
    directory instead. Useful when running inside the repo
    (./photonos-package-report/scans).

.PARAMETER IncludeUpdateUrls
    Also include column 6 (UpdateURL = newer-version URL when one was
    detected upstream). Default: $true.

.PARAMETER ArtifactName
    Artifact name to download. Default: package-reports.

.EXAMPLE
    pwsh ./Get-PackageReportUrls.ps1 -OutputFile urls.txt -Verbose

.EXAMPLE
    # Skip the download; reuse already-cloned repo
    pwsh ./Get-PackageReportUrls.ps1 -ScansDir ../photonos-package-report/scans

.EXAMPLE
    # Pin to a specific run id
    pwsh ./Get-PackageReportUrls.ps1 -RunId 25458435660
#>
[CmdletBinding()]
param(
    [string]$OutputFile        = 'urls.txt',
    [string]$Repo              = 'dcasota/photonos-scripts',
    [long]$RunId               = 0,
    [string[]]$Branches        = @('3.0','4.0','5.0','6.0','common','dev','master'),
    [string]$ScansDir          = '',
    [bool]$IncludeUpdateUrls   = $true,
    [string]$ArtifactName      = 'package-reports',
    # When set, also writes a JSON sidecar mapping each emitted URL to the list
    # of branches that referenced it. Consumed by build_per_branch_summary.py
    # to attribute classifier records back to source branches.
    [string]$BranchMapFile     = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "$Name not found on PATH. $InstallHint"
        exit 2
    }
}

# --- 1. Decide where the .prn files live ---------------------------------
$tempDir = $null
$srcDir  = $ScansDir

if (-not $srcDir) {
    Require-Command gh 'On Photon OS: tdnf install -y gh   (or download from https://cli.github.com)'
    if ($RunId -le 0) {
        Write-Verbose "Resolving latest successful package-report run..."
        $RunId = [long](gh run list --workflow=package-report.yml -R $Repo `
                          --status success --limit 1 --json databaseId -q '.[0].databaseId')
        if (-not $RunId) {
            Write-Error "No successful package-report run found in $Repo"
            exit 1
        }
    }
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pkg-reports-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    Write-Host "Downloading artifact '$ArtifactName' from run $RunId -> $tempDir"
    & gh run download $RunId -R $Repo -n $ArtifactName -D $tempDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "gh run download failed (exit $LASTEXITCODE). The artifact may have expired (90-day retention) — try -ScansDir against a clone of the repo."
        exit 1
    }
    $srcDir = $tempDir
}

if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) {
    Write-Error "Source directory not found: $srcDir"
    exit 1
}

# --- 2. Pick the latest .prn per branch (by filename timestamp) ----------
function Get-LatestPrn {
    param([string]$Dir, [string]$Branch)
    $pattern = "photonos-urlhealth-${Branch}_*.prn"
    $files = Get-ChildItem -LiteralPath $Dir -Filter $pattern -File -ErrorAction SilentlyContinue
    if (-not $files) { return $null }
    # Filename embeds yyyyMMddHHmm (sortable lexicographically)
    $files | Sort-Object Name -Descending | Select-Object -First 1
}

$pickedFiles = @{}
foreach ($b in $Branches) {
    $f = Get-LatestPrn -Dir $srcDir -Branch $b
    if ($f) {
        $pickedFiles[$b] = $f.FullName
        Write-Verbose ("[{0,-7}] {1}" -f $b, $f.Name)
    } else {
        Write-Warning "No URL-health file for branch '$b' in $srcDir"
    }
}
if ($pickedFiles.Count -eq 0) {
    Write-Error "No matching photonos-urlhealth-<branch>_*.prn files found in $srcDir"
    exit 1
}

# --- 3. Extract URLs ------------------------------------------------------
$urls = New-Object System.Collections.Generic.HashSet[string]
$rowsByBranch = @{}
# url -> sorted unique list of branches that referenced this URL (for the
# optional sidecar)
$urlBranches = @{}

# Defensive filter for the well-known photon-OS macro-expansion artefact:
# old photonos-package-report runs substituted `%{url}` literally against
# `URL: https://vmware.github.io/photon` (no trailing slash), producing
# malformed URLs like `https://vmware.github.io/photonlicense.txt` or
# `https://vmware.github.io/photonphoton-upgrade.sh`. The classifier then
# resolved them all to "Photon" the distro and burned API calls. Skip any
# URL where /photon is followed by something other than `/` or end-of-path.
function Test-IsSyntheticPhotonUrl([string]$u) {
    return ($u -match '^https?://vmware\.github\.io/photon($|[^/])')
}
$skippedSynthetic = 0

foreach ($entry in $pickedFiles.GetEnumerator()) {
    $branch = $entry.Key
    $path   = $entry.Value
    $rows   = 0
    # CSV columns are simple (no embedded commas in URLs in practice).
    $lines = Get-Content -LiteralPath $path
    for ($i = 1; $i -lt $lines.Count; $i++) {  # skip header
        $cols = $lines[$i] -split ','
        if ($cols.Count -lt 6) { continue }
        $u3 = $cols[2].Trim()
        $u6 = $cols[5].Trim()
        if ($u3 -match '^https?://') {
            if (Test-IsSyntheticPhotonUrl $u3) { $skippedSynthetic++ }
            else {
                [void]$urls.Add($u3); $rows++
                if (-not $urlBranches.ContainsKey($u3)) { $urlBranches[$u3] = New-Object System.Collections.Generic.HashSet[string] }
                [void]$urlBranches[$u3].Add($branch)
            }
        }
        if ($IncludeUpdateUrls -and $u6 -match '^https?://') {
            if (Test-IsSyntheticPhotonUrl $u6) { $skippedSynthetic++ }
            else {
                [void]$urls.Add($u6)
                if (-not $urlBranches.ContainsKey($u6)) { $urlBranches[$u6] = New-Object System.Collections.Generic.HashSet[string] }
                [void]$urlBranches[$u6].Add($branch)
            }
        }
    }
    $rowsByBranch[$branch] = $rows
}

if ($skippedSynthetic -gt 0) {
    Write-Host "Skipped $skippedSynthetic synthetic vmware.github.io/photon* URLs (no real source archive)."
}

# --- 4. Write urls.txt ----------------------------------------------------
$sorted = $urls | Sort-Object
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $sorted | Out-File -LiteralPath $OutputFile -Encoding utf8NoBOM
} else {
    $absPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path (Get-Location).Path $OutputFile }
    [System.IO.File]::WriteAllText($absPath, ($sorted -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
}

# --- 5. Optional sidecar: URL -> [branches] ------------------------------
if ($BranchMapFile) {
    $map = [ordered]@{}
    foreach ($u in ($urls | Sort-Object)) {
        $brs = $urlBranches[$u]
        if ($brs) { $map[$u] = ($brs | Sort-Object) } else { $map[$u] = @() }
    }
    $payload = [ordered]@{
        generated = (Get-Date).ToUniversalTime().ToString('o')
        branches  = @($Branches)
        url_count = $urls.Count
        urls      = $map
    }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $payload | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $BranchMapFile -Encoding utf8NoBOM
    } else {
        $absPath = if ([System.IO.Path]::IsPathRooted($BranchMapFile)) { $BranchMapFile } else { Join-Path (Get-Location).Path $BranchMapFile }
        [System.IO.File]::WriteAllText($absPath, ($payload | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    }
    Write-Host "Wrote URL->branches sidecar to $BranchMapFile"
}

# --- 6. Summary -----------------------------------------------------------
Write-Host ""
Write-Host "Wrote $($urls.Count) unique URLs to $OutputFile"
Write-Host ("{0,-8} {1,8}" -f 'Branch', 'Source0')
Write-Host ("{0,-8} {1,8}" -f '------', '-------')
foreach ($b in $Branches) {
    if ($rowsByBranch.ContainsKey($b)) {
        Write-Host ("{0,-8} {1,8}" -f $b, $rowsByBranch[$b])
    }
}

# --- 7. Cleanup -----------------------------------------------------------
if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
