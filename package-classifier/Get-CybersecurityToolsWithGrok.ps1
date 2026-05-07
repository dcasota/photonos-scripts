<#
.SYNOPSIS
    Classify upstream package source URLs against xAI Grok-4.3, including
    research on top-3 alternatives with a composite ranking, and emit one
    NDJSON record per URL (resumable, append-as-you-go).

.DESCRIPTION
    Cross-platform PowerShell 7+ script (Linux/macOS/Windows). Verified on
    Photon OS 5 with `tdnf install -y powershell`.

    For each URL the script asks Grok-4.3 to:
      (1) identify the package (name, weblink, summary, language, license,
          last_release),
      (2) research alternatives that do what the package does and produce
          a dynamic ranking of the top 3 alternatives (or fewer when
          appropriate) plus the package itself, considering popularity
          (e.g. github stars), reputation (e.g. CVEs in the last 12 months),
          integration ease, documentation actuality, and ecosystem
          (e.g. github issues in the last 12 months),
      (3) emit per-candidate metrics with sub-scores (0..100) and a
          composite_score also computed locally as a sanity check,
      (4) supply confidence_score 0..1 for cybersecurity-relevance.

    Output format defaults to NDJSON (one JSON object per line) so the run
    is resumable: re-running with -Resume (default $true) skips URLs that
    already have a record in the output file. Pass an OutputFile with a
    .json extension to write a legacy single JSON array at the end (no
    resume).

    Source: https://grok.com/share/bGVnYWN5_fcb265fe-84e5-4fec-99c0-d6b9c3162cf2

.PARAMETER InputFile
    Text file with one URL per line. Default: ./urls.txt.

.PARAMETER OutputFile
    Output path. Default: ./cybersecurity_tools.jsonl.
    If extension is .json the script writes a single JSON array (legacy);
    otherwise NDJSON (one record per line, resumable).

.PARAMETER ApiKey
    xAI API key. Falls back to $env:XAI_API_KEY then $env:GROK_API_KEY.

.PARAMETER Model
    Grok model id. Default: grok-4.3.

.PARAMETER ApiUrl
    xAI completions endpoint. Default: https://api.x.ai/v1/chat/completions.

.PARAMETER MaxAlternatives
    Cap on alternatives to request per package. Default 3, set to 0 to
    disable alternatives research (faster, cheaper).

.PARAMETER MaxRetries
    Per-URL retry count for transient (5xx/408/429/network) failures.

.PARAMETER RetryDelaySeconds
    Base delay between retries; doubled each attempt (exponential).

.PARAMETER RequestTimeoutSec
    Per-request timeout sent to Invoke-RestMethod. Default 90.

.PARAMETER Resume
    Skip URLs already present in OutputFile (NDJSON only). Default: $true.

.PARAMETER EmitTsv
    Also write a flattened TSV (one row per (package, candidate)) next to
    OutputFile. Default: $false.

.PARAMETER StrictValidation
    Drop records whose Grok-claimed composite_score diverges by >5 from
    the locally-recomputed value (instead of correcting + warning).

.EXAMPLE
    XAI_API_KEY=xai-... pwsh ./Get-CybersecurityToolsWithGrok.ps1 -Verbose

.EXAMPLE
    pwsh ./Get-CybersecurityToolsWithGrok.ps1 -MaxAlternatives 0  # cheap mode
#>
[CmdletBinding()]
param(
    [string]$InputFile         = 'urls.txt',
    [string]$OutputFile        = 'cybersecurity_tools.jsonl',
    [string]$ApiKey            = '',
    [string]$Model             = 'grok-4.3',
    [string]$ApiUrl            = 'https://api.x.ai/v1/chat/completions',
    [int]$MaxAlternatives      = 3,
    [int]$MaxRetries           = 3,
    [int]$RetryDelaySeconds    = 2,
    [int]$RequestTimeoutSec    = 90,
    [bool]$Resume              = $true,
    [switch]$EmitTsv,
    [switch]$StrictValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Composite weights (kept in sync with the prompt) ---------------------
$script:Weights = [ordered]@{
    popularity    = 0.30
    reputation    = 0.30
    integration   = 0.15
    documentation = 0.10
    ecosystem     = 0.15
}

# --- Environment introspection -------------------------------------------
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

# --- API key resolution ---------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = $env:XAI_API_KEY
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = $env:GROK_API_KEY }
}
$useApi = -not [string]::IsNullOrWhiteSpace($ApiKey)
if (-not $useApi) {
    Write-Warning "No API key provided (-ApiKey, `$env:XAI_API_KEY, `$env:GROK_API_KEY). Running in fallback-only mode (degraded records)."
}

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

# --- Output mode detection ------------------------------------------------
$ext = [System.IO.Path]::GetExtension($OutputFile).ToLowerInvariant()
$isNdjson = $ext -ne '.json'   # default: NDJSON unless extension is .json
Write-Verbose ("Output mode: {0} ({1})" -f ($(if ($isNdjson) { 'NDJSON' } else { 'JSON array' })), $OutputFile)

# --- Resume support: read existing URLs from NDJSON output ---------------
$alreadyDone = New-Object System.Collections.Generic.HashSet[string]
if ($isNdjson -and $Resume -and (Test-Path -LiteralPath $OutputFile)) {
    Get-Content -LiteralPath $OutputFile | ForEach-Object {
        if (-not $_) { return }
        try {
            $u = ($_ | ConvertFrom-Json -ErrorAction Stop).url
            if ($u) { [void]$alreadyDone.Add($u) }
        } catch { }
    }
    Write-Host "Resume: $($alreadyDone.Count) URLs already classified — they will be skipped."
}

# --- Helpers --------------------------------------------------------------
function Append-NdjsonLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Record)
    $line = $Record | ConvertTo-Json -Depth 10 -Compress
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Add-Content -LiteralPath $Path -Value $line -Encoding utf8NoBOM
    } else {
        $absPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location).Path $Path }
        [System.IO.File]::AppendAllText($absPath, $line + "`n", (New-Object System.Text.UTF8Encoding $false))
    }
}

function Write-JsonArrayFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Records)
    $json = $Records | ConvertTo-Json -Depth 10
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $json | Out-File -LiteralPath $Path -Encoding utf8NoBOM
    } else {
        $absPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location).Path $Path }
        [System.IO.File]::WriteAllText($absPath, $json, (New-Object System.Text.UTF8Encoding $false))
    }
}

function Invoke-GrokWithRetry {
    param([Parameter(Mandatory)][string]$Body, [int]$Attempts, [int]$BaseDelay)
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

function Get-MetricsScore {
    param([object]$Metrics)
    # Recompute composite from sub-scores using $script:Weights, rescaling
    # when sub-metrics are null. Returns @{ score; usedKeys }.
    if ($null -eq $Metrics) { return @{ score = $null; usedKeys = @() } }
    $sum = 0.0; $w = 0.0; $used = @()
    foreach ($k in $script:Weights.Keys) {
        $val = $null
        try {
            $sub = $Metrics.$k
            if ($null -ne $sub -and $null -ne $sub.score) { $val = [double]$sub.score }
        } catch {}
        if ($null -ne $val) {
            $sum += $script:Weights[$k] * $val
            $w   += $script:Weights[$k]
            $used += $k
        }
    }
    if ($w -le 0) { return @{ score = $null; usedKeys = @() } }
    @{ score = [math]::Round($sum / $w, 1); usedKeys = $used }
}

function Build-Prompt {
    param([string]$Url, [int]$MaxAlt)
    $altClause = if ($MaxAlt -gt 0) {
        "Conduct ongoing research about package alternatives which can do what the package does and calculate a dynamic ranking of the top $MaxAlt alternatives (or less if not possible) and the package itself. The calculation must consider popularity (e.g. github stars), reputation (e.g. amount of vulnerabilities found in the last 12 months), integration ease, documentation actuality, ecosystem e.g. amount of github issues in the last 12 months, etc."
    } else {
        "Skip alternatives research; emit alternatives: []."
    }
    @"
Analyze the URL '$Url'.

(1) Identify the package: tool_name, weblink (homepage/parent page), summary (<=200 chars), language, license, last_release (yyyy-mm when known else null).

(2) $altClause

(3) For each candidate (the package itself + each alternative) emit metrics with these sub-objects: popularity {stars (int|null), score (0..100|null)}, reputation {cves_12mo (int|null), score (0..100|null)}, integration {score (0..100|null), notes (string|null)}, documentation {last_doc_update (yyyy-mm|null), score (0..100|null)}, ecosystem {issues_12mo (int|null), prs_12mo (int|null), score (0..100|null)}. Provide composite_score 0..100 = round(0.30*popularity.score + 0.30*reputation.score + 0.15*integration.score + 0.10*documentation.score + 0.15*ecosystem.score, 1). When a sub-score is null, exclude it and rescale the remaining weights to sum to 1.

(4) Set confidence_score 0..1 = probability the package is cybersecurity-related.

Respond with ONLY a single JSON object (no markdown, no fencing) with these keys:
  url, tool_name, weblink, summary, confidence_score, language, license, last_release,
  metrics, composite_score, alternatives, ranking_winner.

alternatives is an array of objects: { rank (1..$MaxAlt), name, weblink, summary, language, license, last_release, metrics, composite_score, rationale }.
"@
}

# --- API smoke test (best effort) ----------------------------------------
if ($useApi) {
    try {
        $tBody = @{
            messages    = @(
                @{ role = 'system'; content = 'You are a test assistant.' },
                @{ role = 'user';   content = 'Reply with the exact text: PING' }
            )
            model       = $Model
            stream      = $false
            temperature = 0
        } | ConvertTo-Json -Depth 4
        $tResp = Invoke-GrokWithRetry -Body $tBody -Attempts 2 -BaseDelay 1
        $reply = ($tResp.choices[0].message.content).Trim()
        Write-Host ("API reachable (model={0}); test reply: {1}" -f $Model, ($reply -replace '\s+',' ').Substring(0, [math]::Min(80, $reply.Length)))
    } catch {
        Write-Warning "API smoke test failed for model '$Model': $($_.Exception.Message). Continuing — per-URL calls will retry; otherwise fallback heuristics will be used."
    }
}

# --- Initialize output for legacy JSON-array mode ------------------------
if (-not $isNdjson) {
    Write-JsonArrayFile -Path $OutputFile -Records @()
}

# --- Main loop ------------------------------------------------------------
$results  = New-Object System.Collections.Generic.List[object]
$apiOk    = 0
$apiFail  = 0
$skipped  = 0
$resumed  = 0
$idx      = 0

foreach ($url in $urls) {
    $idx++
    if ($url -notmatch '^https?://') {
        Write-Warning "[$idx/$($urls.Count)] Skipping non-http(s) URL: $url"
        $skipped++; continue
    }
    if ($alreadyDone.Contains($url)) { $resumed++; continue }

    Write-Host "[$idx/$($urls.Count)] $url"
    $degraded = $false
    $rec = $null

    if ($useApi) {
        $body = @{
            messages    = @(@{ role = 'user'; content = (Build-Prompt -Url $url -MaxAlt $MaxAlternatives) })
            model       = $Model
            stream      = $false
            temperature = 0.2
        } | ConvertTo-Json -Depth 4
        try {
            $resp = Invoke-GrokWithRetry -Body $body -Attempts $MaxRetries -BaseDelay $RetryDelaySeconds
            $text = ($resp.choices[0].message.content).Trim() -replace '^```(?:json)?\s*','' -replace '\s*```$',''
            $rec = $text | ConvertFrom-Json -ErrorAction Stop
            $apiOk++
        } catch {
            Write-Verbose "API/parse failed for $url : $($_.Exception.Message)"
            $apiFail++
        }
    }

    if ($null -eq $rec) {
        # Fallback: degraded record, no alternatives, no metrics.
        $fb = Get-FallbackClassification -Url $url -Summary '' -ToolName ''
        $rec = [pscustomobject]@{
            url              = $url
            tool_name        = $fb.tool_name
            weblink          = $fb.weblink
            summary          = $fb.summary
            confidence_score = $fb.confidence_score
            language         = $null
            license          = $null
            last_release     = $null
            metrics          = $null
            composite_score  = $null
            alternatives     = @()
            ranking_winner   = $fb.tool_name
        }
        $degraded = $true
    }

    # --- Local recompute + sanity check (defense-in-depth) --------------
    $localPkg = (Get-MetricsScore -Metrics $rec.metrics).score
    $claimed  = $null
    try { $claimed = if ($null -ne $rec.composite_score) { [double]$rec.composite_score } else { $null } } catch {}
    if ($null -ne $localPkg -and $null -ne $claimed -and [math]::Abs($localPkg - $claimed) -gt 5) {
        Write-Warning ("composite_score mismatch for {0}: claimed={1} local={2}" -f $rec.tool_name, $claimed, $localPkg)
        if ($StrictValidation) {
            Write-Verbose "Strict mode: dropping record for $url"
            continue
        }
        $rec | Add-Member -NotePropertyName composite_score_claimed -NotePropertyValue $claimed -Force
        $rec.composite_score = $localPkg
    } elseif ($null -eq $claimed -and $null -ne $localPkg) {
        $rec.composite_score = $localPkg
    }

    # --- Recompute composite for each alternative + rank locally ---------
    if ($rec.PSObject.Properties['alternatives'] -and $null -ne $rec.alternatives) {
        $altsRecomputed = @()
        foreach ($alt in $rec.alternatives) {
            $altScore = (Get-MetricsScore -Metrics $alt.metrics).score
            if ($null -ne $altScore) { $alt | Add-Member -NotePropertyName composite_score -NotePropertyValue $altScore -Force }
            $altsRecomputed += $alt
        }
        # Re-rank defensively: sort by composite_score desc, then assign rank.
        $sorted = $altsRecomputed | Sort-Object {
            $s = $null
            try { if ($null -ne $_.composite_score) { $s = [double]$_.composite_score } } catch {}
            if ($null -eq $s) { -1 } else { -$s }   # null -> bottom
        }
        $r = 1
        foreach ($a in $sorted) { $a | Add-Member -NotePropertyName rank -NotePropertyValue $r -Force; $r++ }
        $rec.alternatives = $sorted

        # Pick overall winner across {self, alternatives}.
        $best     = $rec.tool_name
        $bestScore = if ($null -ne $rec.composite_score) { [double]$rec.composite_score } else { -1 }
        foreach ($a in $sorted) {
            $as = $null
            try { if ($null -ne $a.composite_score) { $as = [double]$a.composite_score } } catch {}
            if ($null -ne $as -and $as -gt $bestScore) { $best = $a.name; $bestScore = $as }
        }
        $rec | Add-Member -NotePropertyName ranking_winner -NotePropertyValue $best -Force
    }

    # --- Stamp metadata ---------------------------------------------------
    $rec | Add-Member -NotePropertyName url           -NotePropertyValue $url           -Force
    $rec | Add-Member -NotePropertyName degraded      -NotePropertyValue $degraded      -Force
    $rec | Add-Member -NotePropertyName model         -NotePropertyValue $Model         -Force
    $rec | Add-Member -NotePropertyName generated_at  -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force

    # --- Persist ----------------------------------------------------------
    if ($isNdjson) {
        Append-NdjsonLine -Path $OutputFile -Record $rec
    } else {
        $results.Add($rec)
    }
}

# --- Final write for JSON-array mode -------------------------------------
if (-not $isNdjson) {
    Write-JsonArrayFile -Path $OutputFile -Records $results.ToArray()
}

# --- Optional flat TSV view ----------------------------------------------
function Get-TsvField {
    param([object]$Obj, [string]$Path)
    try {
        $cur = $Obj
        foreach ($p in $Path -split '\.') { if ($null -eq $cur) { return '' }; $cur = $cur.$p }
        if ($null -eq $cur) { '' } else { ([string]$cur) -replace "`t", ' ' -replace "`n", ' ' -replace "`r", '' }
    } catch { '' }
}

if ($EmitTsv) {
    $tsvPath = [System.IO.Path]::ChangeExtension($OutputFile, '.tsv')
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add(("url`tcandidate_kind`tcandidate_name`trank`tcomposite_score`tpopularity`treputation`tintegration`tdocumentation`tecosystem`tcves_12mo`tstars`tissues_12mo`tlanguage`tlicense`tlast_release`tweblink`tsummary`tconfidence_score"))
    $iter = if ($isNdjson) {
        Get-Content -LiteralPath $OutputFile | ForEach-Object {
            if ($_) { try { $_ | ConvertFrom-Json -ErrorAction Stop } catch {} }
        }
    } else { $results }
    foreach ($r in $iter) {
        if (-not $r) { continue }
        $rows.Add(("{0}`tself`t{1}`t0`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}`t{9}`t{10}`t{11}`t{12}`t{13}`t{14}`t{15}`t{16}" -f `
            (Get-TsvField $r 'url'),
            (Get-TsvField $r 'tool_name'),
            (Get-TsvField $r 'composite_score'),
            (Get-TsvField $r 'metrics.popularity.score'),
            (Get-TsvField $r 'metrics.reputation.score'),
            (Get-TsvField $r 'metrics.integration.score'),
            (Get-TsvField $r 'metrics.documentation.score'),
            (Get-TsvField $r 'metrics.ecosystem.score'),
            (Get-TsvField $r 'metrics.reputation.cves_12mo'),
            (Get-TsvField $r 'metrics.popularity.stars'),
            (Get-TsvField $r 'metrics.ecosystem.issues_12mo'),
            (Get-TsvField $r 'language'),
            (Get-TsvField $r 'license'),
            (Get-TsvField $r 'last_release'),
            (Get-TsvField $r 'weblink'),
            (Get-TsvField $r 'summary'),
            (Get-TsvField $r 'confidence_score')))
        if ($r.PSObject.Properties['alternatives'] -and $null -ne $r.alternatives) {
            foreach ($a in $r.alternatives) {
                $rows.Add(("{0}`talternative`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}`t{9}`t{10}`t{11}`t{12}`t{13}`t{14}`t{15}`t{16}" -f `
                    (Get-TsvField $r 'url'),
                    (Get-TsvField $a 'name'),
                    (Get-TsvField $a 'rank'),
                    (Get-TsvField $a 'composite_score'),
                    (Get-TsvField $a 'metrics.popularity.score'),
                    (Get-TsvField $a 'metrics.reputation.score'),
                    (Get-TsvField $a 'metrics.integration.score'),
                    (Get-TsvField $a 'metrics.documentation.score'),
                    (Get-TsvField $a 'metrics.ecosystem.score'),
                    (Get-TsvField $a 'metrics.reputation.cves_12mo'),
                    (Get-TsvField $a 'metrics.popularity.stars'),
                    (Get-TsvField $a 'metrics.ecosystem.issues_12mo'),
                    (Get-TsvField $a 'language'),
                    (Get-TsvField $a 'license'),
                    (Get-TsvField $a 'last_release'),
                    (Get-TsvField $a 'weblink'),
                    (Get-TsvField $a 'summary'),
                    ''))
            }
        }
    }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $rows | Out-File -LiteralPath $tsvPath -Encoding utf8NoBOM
    } else {
        $absPath = if ([System.IO.Path]::IsPathRooted($tsvPath)) { $tsvPath } else { Join-Path (Get-Location).Path $tsvPath }
        [System.IO.File]::WriteAllText($absPath, ($rows -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))
    }
    Write-Host "TSV written: $tsvPath ($($rows.Count - 1) rows)"
}

# --- Summary --------------------------------------------------------------
$total = if ($isNdjson) {
    if (Test-Path -LiteralPath $OutputFile) { (Get-Content -LiteralPath $OutputFile | Measure-Object -Line).Lines } else { 0 }
} else { $results.Count }
Write-Host ""
Write-Host ("Wrote {0} entries to {1} ({2})" -f $total, $OutputFile, $(if ($isNdjson) { 'NDJSON' } else { 'JSON array' }))
Write-Host ("API: ok={0} failed={1}; URLs skipped: {2}; resumed: {3}" -f $apiOk, $apiFail, $skipped, $resumed)
