# classifier

Two-step pipeline that classifies upstream package source URLs against an LLM
to surface cybersecurity-relevant tools across the Photon OS branches.

```
package-report.yml workflow
        │
        ▼
photonos-urlhealth-<branch>_<ts>.prn  (one per branch in the artifact)
        │
        │  Get-PackageReportUrls.ps1   (downloads artifact, extracts URLs)
        ▼
urls.txt  (deduplicated, ~3,200 URLs across all branches)
        │
        │  Get-CybersecurityToolsWithGrok.ps1   (calls xAI Grok-4.3 per URL)
        ▼
cybersecurity_tools.json
```

Verified on Photon OS 5 with `tdnf install -y powershell gh` (PowerShell 7.4 + gh).

## Scripts

### Get-PackageReportUrls.ps1

Fetches the latest successful `package-report.yml` artifact from GitHub Actions
and writes the deduplicated URL list to a file.

```pwsh
# Default: latest successful run, all 7 branches, write urls.txt
pwsh ./Get-PackageReportUrls.ps1 -Verbose

# Reuse an already-cloned repo's scans dir (no API calls, works offline)
pwsh ./Get-PackageReportUrls.ps1 -ScansDir ../photonos-package-report/scans

# Pin a specific run id (useful for reproducible runs)
pwsh ./Get-PackageReportUrls.ps1 -RunId 25458435660
```

Parameters:

| Name | Default | Notes |
|---|---|---|
| `-OutputFile` | `urls.txt` | Where the deduped URLs land (utf8 no BOM) |
| `-Repo` | `dcasota/photonos-scripts` | `owner/repo` for the workflow |
| `-RunId` | latest success | Specific run id to download |
| `-Branches` | `3.0,4.0,5.0,6.0,common,dev,master` | Per-branch URL-health files to consume |
| `-ScansDir` | (download) | Skip download; read from a local dir |
| `-IncludeUpdateUrls` | `$true` | Also include col 6 (newer-version URL) |
| `-ArtifactName` | `package-reports` | Artifact name on the workflow |

Requires `gh` CLI authenticated against the repo unless `-ScansDir` is passed.

### Get-CybersecurityToolsWithGrok.ps1

Reads the URL list, asks xAI Grok-4.3 to classify each, falls back to
URL-pattern heuristics when the API is unavailable, and writes a JSON array
of `{tool_name, weblink, summary, confidence_score}`.

```pwsh
export XAI_API_KEY=xai-...
pwsh ./Get-CybersecurityToolsWithGrok.ps1 \
  -InputFile urls.txt \
  -OutputFile cybersecurity_tools.json \
  -Model grok-4.3 \
  -Verbose
```

API key resolution: `-ApiKey` parameter > `$env:XAI_API_KEY` > `$env:GROK_API_KEY`.
If none is set the script runs in fallback-only mode.

## End-to-end on Photon OS 5

```bash
tdnf install -y powershell gh
gh auth login

cd classifier
pwsh ./Get-PackageReportUrls.ps1 -Verbose
export XAI_API_KEY=xai-...
pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -Verbose
```
