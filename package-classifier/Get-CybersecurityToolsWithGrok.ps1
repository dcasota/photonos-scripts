<#
.SYNOPSIS
    Classify a list of URLs against xAI Grok ("Grok-4.3" by default) and emit a
    JSON file describing each entry's tool name, parent webpage, summary, and
    a 0..1 cybersecurity-relevance confidence score.

.DESCRIPTION
    Cross-platform PowerShell 7+ script (Linux/macOS/Windows). Verified on
    Photon OS 5 with the `powershell` package (tdnf install -y powershell).
    Falls back to URL/heuristic-based scoring when the API is unavailable so
    it remains useful when the runner is rate-limited or the key is invalid.

    Source: https://grok.com/share/bGVnYWN5_fcb265fe-84e5-4fec-99c0-d6b9c3162cf2

.PARAMETER InputFile
    Path to a text file containing one URL per line. Default: ./urls.txt

.PARAMETER OutputFile
    Path to write the resulting JSON array. Default: ./cybersecurity_tools.json

.PARAMETER ApiKey
    xAI API key. If omitted, read from $env:XAI_API_KEY (preferred), then
    $env:GROK_API_KEY. If neither is set, the script runs in fallback-only
    mode (no API calls).

.PARAMETER Model
    Grok model id. Default: grok-4.3

.PARAMETER ApiUrl
    xAI completions endpoint. Default: https://api.x.ai/v1/chat/completions

.PARAMETER MaxRetries
    Per-URL retry count for transient (5xx / network) failures. Default: 3.

.PARAMETER RetryDelaySeconds
    Base delay between retries; doubled each attempt (exponential). Default: 2.

.PARAMETER RequestTimeoutSec
    Per-request timeout sent to Invoke-RestMethod. Default: 60.

.EXAMPLE
    XAI_API_KEY=xai-... pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt

.EXAMPLE
    pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -Model grok-4.3 -Verbose
#>
[CmdletBinding()]
param(
    [string]$InputFile         = 'urls.txt',
    [string]$OutputFile        = 'cybersecurity_tools.json',
    [string]$ApiKey            = '',
    [string]$Model             = 'grok-4.3',
    [string]$ApiUrl            = 'https://api.x.ai/v1/chat/completions',
    [int]$MaxRetries           = 3,
    [int]$RetryDelaySeconds    = 2,
    [int]$RequestTimeoutSec    = 60
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Environment introspection (helpful when run on Photon OS) -------------
$psVersion = $PSVersionTable.PSVersion.ToString()
$osInfo    = if ($IsLinux -and (Test-Path '/etc/os-release')) {
    $rel = Get-Content /etc/os-release | Where-Object { $_ -match '^PRETTY_NAME=' }
    if ($rel) { ($rel -split '=', 2)[1].Trim('"') } else { 'Linux' }
} elseif ($IsMacOS) { 'macOS' }
  elseif ($IsWindows -or [System.Environment]::OSVersion.Platform -eq 'Win32NT') { 'Windows' }
  else { 'unknown' }

Write-Verbose "PowerShell $psVersion on $osInfo"
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "PowerShell 7+ recommended (running $psVersion). On Photon OS 5: tdnf install -y powershell"
}

# --- API key resolution ----------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = $env:XAI_API_KEY
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = $env:GROK_API_KEY }
}
$useApi = -not [string]::IsNullOrWhiteSpace($ApiKey)
if (-not $useApi) {
    Write-Warning "No API key provided (-ApiKey, `$env:XAI_API_KEY, `$env:GROK_API_KEY). Running in fallback-only mode."
}

# --- Input / fallback config ----------------------------------------------
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Error "Input file not found: $InputFile"
    exit 1
}
$urls = Get-Content -LiteralPath $InputFile | ForEach-Object { $_.Trim() } | Where-Object { $_ }
Write-Host "Loaded $($urls.Count) URLs from $InputFile"

$cybersecurityKeywords = @(
    'security','cybersecurity','penetration testing','vulnerability',
    'malware','firewall','encryption','OSINT','phishing','forensics',
    'intrusion detection','packet sniffer','network security','cryptography'
)

$xaiHeaders = @{
    'Authorization' = "Bearer $ApiKey"
    'Content-Type'  = 'application/json'
}

# --- Helpers ---------------------------------------------------------------
function Write-JsonFile {
    param([Parameter(Mandatory)][object]$Data, [Parameter(Mandatory)][string]$Path)
    # PS 7+ supports utf8NoBOM; PS 5.1 does not — fall back gracefully.
    $json = ($Data | ConvertTo-Json -Depth 6)
    if ($json -is [array]) { $json = $json -join "`n" }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $json | Out-File -LiteralPath $Path -Encoding utf8NoBOM
    } else {
        $absPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location).Path $Path }
        [System.IO.File]::WriteAllText($absPath, $json, (New-Object System.Text.UTF8Encoding $false))
    }
}

function Invoke-GrokWithRetry {
    param(
        [Parameter(Mandatory)][string]$Body,
        [int]$Attempts,
        [int]$BaseDelay
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return Invoke-RestMethod `
                -Uri $ApiUrl -Method Post -Body $Body `
                -Headers $xaiHeaders -TimeoutSec $RequestTimeoutSec -ErrorAction Stop
        } catch {
            $statusCode = $null
            try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch {}
            $transient = ($null -eq $statusCode) -or ($statusCode -ge 500) -or ($statusCode -in 408,429)
            if (-not $transient -or $attempt -ge $Attempts) { throw }
            $delay = $BaseDelay * [math]::Pow(2, $attempt - 1)
            Write-Verbose "API attempt $attempt/$Attempts failed (status=$statusCode): retrying in ${delay}s"
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-FallbackClassification {
    param([Parameter(Mandatory)][string]$Url, [string]$Summary, [string]$ToolName)
    $name = $ToolName
    if ([string]::IsNullOrEmpty($name)) {
        if ($Url -match '/([^/]+)(\.exe|\.zip|\.tar\.gz|\.tgz|\.tar\.bz2|\.tar\.xz|\.msi|\.dmg|\.deb|\.rpm)$') {
            $name = $matches[1]
        } else {
            $name = ([uri]$Url).Host -replace '^www\.', ''
        }
    }

    $weblink =
        if     ($Url -match '^https?://github\.com/([^/]+)/([^/]+)/releases/download/[^/]+/.+$') { "https://github.com/$($matches[1])/$($matches[2])" }
        elseif ($Url -match '^https?://github\.com/([^/]+)/([^/]+)/archive/.+$')                { "https://github.com/$($matches[1])/$($matches[2])" }
        elseif ($Url -match '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/.+$')        { "https://github.com/$($matches[1])/$($matches[2])" }
        else                                                                                     { 'https://' + ([uri]$Url).Host }

    if ([string]::IsNullOrEmpty($Summary) -or $Summary -eq 'No description available.') {
        $Summary = 'Description not provided by AI.'
    }

    $hits = 0
    foreach ($k in $cybersecurityKeywords) {
        if (($Summary -imatch [regex]::Escape($k)) -or ($name -imatch [regex]::Escape($k))) { $hits++ }
    }
    $confidence = [math]::Min(0.5 + ($hits * 0.1), 0.9)

    [pscustomobject]@{
        tool_name        = $name
        weblink          = $weblink
        summary          = $Summary
        confidence_score = $confidence
    }
}

# --- API key smoke test (best effort, never blocks) -----------------------
if ($useApi) {
    try {
        $testBody = @{
            messages    = @(
                @{ role = 'system'; content = 'You are a test assistant.' },
                @{ role = 'user';   content = 'Reply with the exact text: PING' }
            )
            model       = $Model
            stream      = $false
            temperature = 0
        } | ConvertTo-Json -Depth 4
        $testResp = Invoke-GrokWithRetry -Body $testBody -Attempts 2 -BaseDelay 1
        $reply = ($testResp.choices[0].message.content).Trim()
        Write-Host ("API reachable (model={0}); test reply: {1}" -f $Model, ($reply -replace '\s+',' ').Substring(0, [math]::Min(80, $reply.Length)))
    } catch {
        Write-Warning "API smoke test failed for model '$Model': $($_.Exception.Message). Continuing — per-URL calls will retry; otherwise fallback heuristics will be used."
    }
}

# --- Main loop -------------------------------------------------------------
$results  = New-Object System.Collections.Generic.List[object]
$apiOk    = 0
$apiFail  = 0
$skipped  = 0
$idx      = 0

foreach ($url in $urls) {
    $idx++
    if ($url -notmatch '^https?://') {
        Write-Warning "[$idx/$($urls.Count)] Skipping non-http(s) URL: $url"
        $skipped++; continue
    }

    Write-Host "[$idx/$($urls.Count)] $url"
    $toolName  = ''
    $weblink   = ''
    $summary   = 'No description available.'
    $confidence = 0
    $needFallback = -not $useApi

    if ($useApi) {
        $prompt = "Analyze the URL '$url', which points to an executable or source archive, and respond with ONLY a single-line JSON object (no markdown, no fencing) with these keys: tool_name, weblink (parent webpage or tool homepage), summary (<=200 chars), confidence_score (number 0..1 that the tool is cybersecurity-related). If unsure, use best guesses based on URL patterns."
        $body = @{
            messages    = @(@{ role = 'user'; content = $prompt })
            model       = $Model
            stream      = $false
            temperature = 0.2
        } | ConvertTo-Json -Depth 4
        try {
            $resp = Invoke-GrokWithRetry -Body $body -Attempts $MaxRetries -BaseDelay $RetryDelaySeconds
            $text = ($resp.choices[0].message.content).Trim()
            # Some models wrap JSON in fences; strip if present.
            $text = $text -replace '^```(?:json)?\s*','' -replace '\s*```$',''
            $parsed = $text | ConvertFrom-Json -ErrorAction Stop
            $toolName    = [string]$parsed.tool_name
            $weblink     = [string]$parsed.weblink
            $summary     = [string]$parsed.summary
            $confidence  = [double]$parsed.confidence_score
            $apiOk++
        } catch {
            Write-Verbose "API/parse failed for $url : $($_.Exception.Message)"
            $apiFail++
            $needFallback = $true
        }
    }

    if ($needFallback -or [string]::IsNullOrEmpty($toolName) -or [string]::IsNullOrEmpty($weblink) -or $confidence -le 0) {
        $fb = Get-FallbackClassification -Url $url -Summary $summary -ToolName $toolName
        $toolName    = $fb.tool_name
        $weblink     = $fb.weblink
        $summary     = $fb.summary
        $confidence  = $fb.confidence_score
    }

    if ($weblink -notmatch '^https?://') { $weblink = $url }

    $results.Add([pscustomobject]@{
        tool_name        = $toolName
        weblink          = $weblink
        summary          = $summary
        confidence_score = $confidence
    })
}

# --- Single write at the end (O(n) instead of O(n²)) ----------------------
Write-JsonFile -Data $results.ToArray() -Path $OutputFile
Write-Host ""
Write-Host "Wrote $($results.Count) entries to $OutputFile"
Write-Host ("API: ok={0} failed={1}; URLs skipped: {2}" -f $apiOk, $apiFail, $skipped)
