# package-classifier

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
        │  Get-CybersecurityToolsWithGrok.ps1   (calls xAI Grok-4.3 per URL,
        │                                        researches alternatives,
        │                                        ranks {self, top-3 alts})
        ▼
cybersecurity_tools.jsonl  (NDJSON; one record per URL, resumable)
        │
        │  -EmitTsv (optional) — flat row per (package, candidate)
        ▼
cybersecurity_tools.tsv
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

Reads the URL list and, per package, asks xAI Grok-4.3 to:

1. Identify the package (`tool_name`, `weblink`, `summary`, `language`,
   `license`, `last_release`).
2. **Research alternatives that do what the package does** and produce a
   dynamic ranking of the top-3 alternatives (or fewer when appropriate)
   plus the package itself, considering popularity (e.g. github stars),
   reputation (e.g. CVEs in the last 12 months), integration ease,
   documentation actuality, and ecosystem (e.g. github issues in the last
   12 months).
3. Per candidate, emit a `metrics` block with sub-scores 0..100 plus a
   `composite_score` (weighted sum). The script **recomputes the composite
   locally** as a sanity check and warns on >5-point divergence.
4. Set `confidence_score` 0..1 for cybersecurity-relevance.

Fallback: when the API is unreachable the script writes a `degraded:true`
record from URL-pattern heuristics (no alternatives, no metrics).

#### Output: NDJSON, one record per line, resumable

Default output is `cybersecurity_tools.jsonl` (NDJSON). Re-running with
`-Resume $true` (default) skips URLs already in the file — interruptible
long runs without losing work. Pass an output filename ending in `.json`
to use the legacy JSON-array format (no resume).

#### Per-record schema

```jsonc
{
  "url": "https://...tar.gz",
  "tool_name": "wireshark",
  "weblink": "https://www.wireshark.org",
  "summary": "Network protocol analyzer ...",
  "confidence_score": 0.95,
  "language": "C/C++",
  "license": "GPL-2.0",
  "last_release": "2026-04",
  "metrics": {
    "popularity":    { "stars": 8421, "score": 78 },
    "reputation":    { "cves_12mo": 3, "score": 64 },
    "integration":   { "score": 72, "notes": "..." },
    "documentation": { "last_doc_update": "2026-03", "score": 81 },
    "ecosystem":     { "issues_12mo": 412, "prs_12mo": 287, "score": 70 }
  },
  "composite_score": 73.2,
  "alternatives": [
    { "rank": 1, "name": "tshark", "composite_score": 75.8,
      "weblink": "...", "summary": "...", "metrics": { ... },
      "rationale": "..." },
    { "rank": 2, ... },
    { "rank": 3, ... }
  ],
  "ranking_winner": "tshark",
  "degraded": false,
  "model": "grok-4.3",
  "generated_at": "2026-05-07T03:42:00.123Z"
}
```

Composite weights (kept in sync between the prompt and the local recompute):
`popularity 0.30`, `reputation 0.30`, `integration 0.15`,
`documentation 0.10`, `ecosystem 0.15`. Null sub-scores are excluded and
the remaining weights rescaled.

#### Usage

```pwsh
export XAI_API_KEY=xai-...

# default — NDJSON, top-3 alternatives, resumable
pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -Verbose

# also emit a flat TSV (one row per (package, candidate))
pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -EmitTsv

# cheap mode: skip alternatives research
pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -MaxAlternatives 0

# strict: drop records where Grok's composite_score diverges >5 from local
pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -StrictValidation
```

API key resolution: `-ApiKey` parameter > `$env:XAI_API_KEY` > `$env:GROK_API_KEY`.
If none is set the script runs in fallback-only mode (`degraded:true`).

Cost note: with `-MaxAlternatives 3` each call is ~700–900 response
tokens and ~2–4 s of wall time. Plan ~3–4 hours for a 3,200-URL run; the
output is resumable so partial progress is never lost.

## End-to-end on Photon OS 5

```bash
tdnf install -y powershell gh
gh auth login

cd package-classifier
pwsh ./Get-PackageReportUrls.ps1 -Verbose
export XAI_API_KEY=xai-...
pwsh ./Get-CybersecurityToolsWithGrok.ps1 -InputFile urls.txt -Verbose
```
