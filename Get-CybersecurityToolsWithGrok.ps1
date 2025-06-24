# https://grok.com/share/bGVnYWN5_fcb265fe-84e5-4fec-99c0-d6b9c3162cf2
# Define input file with URLs (one per line)
$inputFile = "urls.txt"
# Define output JSON file
$outputFile = "cybersecurity_tools.json"

# xAI Grok 3 API key (replace with your key)
$xaiApiKey = ""  # Get from https://x.ai/api
# xAI Grok 3 API endpoint
$xaiApiUrl = "https://api.x.ai/v1/chat/completions"


# Cybersecurity-related keywords for fallback
$cybersecurityKeywords = @(
    "security", "cybersecurity", "penetration testing", "vulnerability",
    "malware", "firewall", "encryption", "OSINT", "phishing", "forensics",
    "intrusion detection", "packet sniffer", "network security", "cryptography"
)

# Initialize output JSON file
@() | ConvertTo-Json | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host "Created output file: $outputFile"

# Check if input file exists
if (-not (Test-Path $inputFile)) {
    Write-Error "Input file $inputFile not found. Please create a file with one URL per line."
    exit
}

# Read URLs from file
$urls = Get-Content $inputFile

# Set headers for xAI API
$xaiHeaders = @{
    "Authorization" = "Bearer $xaiApiKey"
    "Content-Type"  = "application/json"
}

# Test API key
try {
    $testPayload = @{
        messages = @(
            @{
                role = "system"
                content = "You are a test assistant."
            },
            @{
                role = "user"
                content = "Testing. Just say hi and hello world and nothing else."
            }
        )
        model = "grok-3-latest"
        stream = $false
        temperature = 0
    } | ConvertTo-Json -Depth 4
    $testResponse = Invoke-RestMethod -Uri $xaiApiUrl -Method Post -Body $testPayload -Headers $xaiHeaders -ErrorAction Stop
    if ($testResponse.choices -and $testResponse.choices[0].message.content -eq "hi and hello world") {
        Write-Host "xAI Grok 3 API key validated successfully."
    } else {
        Write-Warning "API test succeeded but unexpected response: $($testResponse.choices[0].message.content)"
        Write-Host "Continuing with fallback logic if API fails."
    }
} catch {
    Write-Warning "xAI Grok 3 API key test failed: $_"
    Write-Host "Continuing with fallback logic if API fails."
}

foreach ($url in $urls) {
    try {
        # Trim whitespace and skip empty lines
        $url = $url.Trim()
        if (-not $url) { continue }

        # Validate URL format
        if ($url -notmatch "^https?://") {
            Write-Warning "Skipping invalid URL: $url"
            continue
        }

        # Prepare xAI Grok 3 API payload
        $prompt = "Analyze the URL '$url', which points to an executable file, and provide the following in JSON format: { 'tool_name': 'name of the tool', 'weblink': 'parent webpage or tool homepage URL', 'summary': 'brief description of the tool (up to 200 characters)', 'confidence_score': probability (0 to 1) that the tool is cybersecurity-related }. If unsure, provide best guesses based on URL patterns."
        $payload = @{
            messages = @(
                @{
                    role = "user"
                    content = $prompt
                }
            )
            model = "grok-3-latest"
            stream = $false
            temperature = 0.7
        } | ConvertTo-Json -Depth 4

        # Initialize variables
        $toolName = ""
        $weblink = ""
        $summary = "No description available."
        $confidence = 0

        # Call xAI Grok 3 API
        $useFallback = $false
        try {
            $xaiResponse = Invoke-RestMethod -Uri $xaiApiUrl -Method Post -Body $payload -Headers $xaiHeaders -ErrorAction Stop
            if ($xaiResponse.choices -and $xaiResponse.choices[0].message.content) {
                $responseText = $xaiResponse.choices[0].message.content.Trim()
                # Try to parse as JSON
                try {
                    $parsedResponse = $responseText | ConvertFrom-Json
                    $toolName = $parsedResponse.tool_name
                    $weblink = $parsedResponse.weblink
                    $summary = $parsedResponse.summary
                    $confidence = [double]$parsedResponse.confidence_score
                } catch {
                    Write-Warning "Failed to parse Grok 3 response as JSON for $url : $responseText"
                    $useFallback = $true
                }
            } else {
                Write-Warning "Unexpected API response format for $url : $($xaiResponse | ConvertTo-Json -Depth 4)"
                $useFallback = $true
            }
        } catch {
            Write-Warning "xAI Grok 3 API request failed for $url : $_"
            $useFallback = $true
        }

        # Fallback logic if AI fails or response is incomplete
        if ($useFallback -or [string]::IsNullOrEmpty($toolName) -or [string]::IsNullOrEmpty($weblink) -or $confidence -eq 0) {
            Write-Verbose "Using fallback logic for $url"
            # Derive tool name from URL
            if ($url -match "/([^/]+)(\.exe|\.zip|\.tar\.gz|\.msi|\.dmg)$") {
                $toolName = $matches[1]
            } else {
                $toolName = ([uri]$url).Host -replace "^www\.", ""
            }

            # Derive weblink (parent page)
            if ($url -match "^https?://github\.com/([^/]+)/([^/]+)/releases/download/[^/]+/.+$") {
                $weblink = "https://github.com/$($matches[1])/$($matches[2])"
            } elseif ($url -match "^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/.+$") {
                $weblink = "https://github.com/$($matches[1])/$($matches[2])"
            } else {
                $weblink = "https://" + ([uri]$url).Host
            }

            # Use summary from AI if available, else default
            if ($summary -eq "No description available.") {
                $summary = "Description not provided by AI."
            }

            # Keyword-based confidence scoring
            $keywordCount = 0
            foreach ($keyword in $cybersecurityKeywords) {
                if ($summary -imatch $keyword -or $toolName -imatch $keyword) {
                    $keywordCount++
                }
            }
            $confidence = [Math]::Min(0.5 + ($keywordCount * 0.1), 0.9)  # Base 0.5 + 0.1 per keyword, max 0.9
        }

        # Validate weblink
        if ($weblink -notmatch "^https?://") {
            Write-Warning "Invalid weblink generated for $url : $weblink"
            $weblink = $url  # Fallback to original URL
        }

        # Create output object
        $outputObject = [PSCustomObject]@{
            tool_name       = $toolName
            weblink         = $weblink
            summary         = $summary
            confidence_score = $confidence
        }

        # Append to JSON file
        try {
            # Read existing JSON content
            $existingContent = if (Test-Path $outputFile) {
                Get-Content $outputFile -Raw | ConvertFrom-Json
            } else {
                @()
            }
            # Append new entry
            $updatedContent = @($existingContent) + $outputObject
            # Write back to file
            $updatedContent | ConvertTo-Json -Depth 4 | Out-File -FilePath $outputFile -Encoding UTF8
            Write-Verbose "Appended entry for $url to $outputFile"
        } catch {
            Write-Warning "Failed to append to $outputFile for $url : $_"
        }

    } catch {
        Write-Warning "Error processing $url : $_"
    }
}

Write-Host "Processing complete. Output saved to $outputFile"


# WARNING: xAI Grok 3 API request failed for https://github.com/autotools-mirror/automake/archive/refs/tags/v1.16.5.tar.gz : error code: 502
# WARNING: xAI Grok 3 API request failed for http://www.bluez.org : error code: 502
# WARNING: xAI Grok 3 API request failed for https://github.com/projectcalico/calico/archive/refs/tags/v3.26.4.tar.gz : error code: 502
# WARNING: Skipping invalid URL: ftp://ftp.isc.org/isc/dhcp/${version}/dhcp-4.4.3.tar.gz
# WARNING: Skipping invalid URL: ftp://ftp.uk.linux.org/pub/linux/Networking/netkit/bsd-finger-0.17.tar.gz
# WARNING: xAI Grok 3 API request failed for https://github.com/Irqbalance/irqbalance/archive/refs/tags/v1.9.2.tar.gz : error code: 502
# WARNING: Failed to parse Grok 3 response as JSON for https://github.com/rpm-software-management/librepo/archive/refs/tags/1.14.5.tar.gz
# WARNING: Skipping invalid URL: ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.45.tar.bz2
# WARNING: xAI Grok 3 API request failed for https://cpan.metacpan.org/authors/id/M/ML/MLEHMANN/JSON-XS-4.03.tar.gz : error code: 502
# WARNING: xAI Grok 3 API request failed for http://search.cpan.org/CPAN/authors/id/K/KW/KWILLIAMS/Path-Class-0.37.tar.gz : error code: 502
# WARNING: xAI Grok 3 API request failed for https://github.com/pyserial/pyserial/archive/refs/tags/v3.5.tar.gz : error code: 502
# WARNING: xAI Grok 3 API request failed for https://github.com/benjaminp/six/archive/refs/tags/1.16.0.tar.gz : error code: 502