# Photon OS Package Report Script - Structure & Workflow Overview

## SCRIPT STRUCTURE

```
photonos-package-report.ps1 (4,669 lines)
│
├── HEADER (Lines 1-58)
│   ├── Synopsis & Version History
│   └── Parameter Declarations (13 parameters)
│
├── HELPER FUNCTIONS (Lines 60-228)
│   ├── Invoke-GitWithTimeout    (60-93)    - Git commands with timeout
│   ├── Get-SpecValue            (96-107)   - Safe spec field extraction
│   └── ParseDirectory           (109-228)  - Parse .spec files from branch
│
├── CORE FUNCTIONS (Lines 231-1076)
│   ├── Versioncompare           (231-287)  - Compare version strings
│   ├── GitPhoton                (289-324)  - Clone/fetch/merge Photon repos
│   ├── Source0Lookup            (326-890)  - Lookup table for 550+ packages
│   ├── ModifySpecFile           (892-964)  - Update spec files with new versions
│   ├── urlhealth                (966-1025) - Check URL HTTP status
│   └── KojiFedoraProjectLookUp  (1027-1076)- Lookup Fedora Koji packages
│
├── MAIN PROCESSING FUNCTION (Lines 1079-4394)
│   └── CheckURLHealth           (1079-4178)- URL health check per package
│       ├── Version extraction from URLs
│       ├── Data scraping (GitHub, GitLab, PyPI, RubyGems, etc.)
│       ├── Update availability detection
│       └── Spec file modification
│   └── GenerateUrlHealthReports (4230-4394)- Orchestrates parallel/sequential processing
│
├── MAIN EXECUTION (Lines 4396-4669)
│   ├── Initialization           (4396-4478)
│   │   ├── Security protocol setup
│   │   ├── OS detection
│   │   ├── Command availability check (git, tar)
│   │   ├── Module check (PowerShellCookbook)
│   │   ├── Parallel processing detection
│   │   ├── CPU/throttle configuration
│   │   └── Path validation
│   │
│   ├── Authentication           (4481-4525)
│   │   ├── GitHub token prompt
│   │   └── GitLab username/token prompt
│   │
│   ├── URL Health Reports       (4528-4548)
│   │   └── Call GenerateUrlHealthReports()
│   │
│   ├── Package Report           (4554-4578)
│   │   ├── Git clone/fetch all branches
│   │   ├── Parse all directories
│   │   └── Generate package-report.prn
│   │
│   ├── Diff Reports             (4580-4656)
│   │   ├── Common vs Master
│   │   ├── 5.0 vs 6.0
│   │   ├── 4.0 vs 5.0
│   │   └── 3.0 vs 4.0
│   │
│   └── Cleanup                  (4658-4669)
│       ├── Clear tokens from memory
│       └── Remove git credentials
```

---

## WORKFLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SCRIPT START                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: INITIALIZATION                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ TLS 1.2/1.3 │→ │ OS Detection│→ │ Check git,  │→ │ Check PowerShell    │ │
│  │ Protocol    │  │ (Windows?)  │  │ tar commands│  │ Cookbook module     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                                    │                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                          │
│  │ Parallel    │→ │ CPU/Throttle│→ │ Validate    │                          │
│  │ Support?    │  │ Calculation │  │ SourcePath  │                          │
│  └─────────────┘  └─────────────┘  └─────────────┘                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: AUTHENTICATION                                                     │
│  ┌────────────────────────┐       ┌────────────────────────────────────────┐│
│  │ GitHub Token           │       │ GitLab Username + Token                ││
│  │ ($env:GITHUB_TOKEN or  │       │ ($env:GITLAB_TOKEN or prompt)          ││
│  │  prompt)               │       │ + Configure git credentials            ││
│  └────────────────────────┘       └────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: URL HEALTH REPORTS (per enabled branch: 3.0, 4.0, 5.0, 6.0,       │
│           common, dev, master)                                               │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  GenerateUrlHealthReports()                                          │   │
│  │  ┌────────────────┐     ┌────────────────┐     ┌──────────────────┐ │   │
│  │  │ GitPhoton()    │  →  │ ParseDirectory │  →  │ For each package │ │   │
│  │  │ Clone/Fetch    │     │ Extract .spec  │     │ CheckURLHealth() │ │   │
│  │  │ Branch         │     │ metadata       │     │                  │ │   │
│  │  └────────────────┘     └────────────────┘     └────────┬─────────┘ │   │
│  │                                                          │           │   │
│  │                    ┌─────────────────────────────────────┘           │   │
│  │                    ▼                                                 │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐│   │
│  │  │  CheckURLHealth() - Per Package                                 ││   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐││   │
│  │  │  │ Source0Lookup│→ │ urlhealth()  │→ │ Data Scraping:         │││   │
│  │  │  │ Get metadata │  │ Check HTTP   │  │ - GitHub API           │││   │
│  │  │  │ for package  │  │ status       │  │ - GitLab API           │││   │
│  │  │  └──────────────┘  └──────────────┘  │ - PyPI, RubyGems       │││   │
│  │  │                                      │ - SourceForge, GNU     │││   │
│  │  │                                      │ - Fedora Koji          │││   │
│  │  │                                      └────────────┬───────────┘││   │
│  │  │                                                   │            ││   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌───────────▼──────────┐ ││   │
│  │  │  │ ModifySpec   │← │ Download     │← │ Detect Update        │ ││   │
│  │  │  │ File()       │  │ New Source   │  │ Available?           │ ││   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────────┘ ││   │
│  │  └─────────────────────────────────────────────────────────────────┘│   │
│  │                                                                      │   │
│  │  Processing Mode:                                                    │   │
│  │  ┌─────────────────────┐  OR  ┌─────────────────────────────────┐   │   │
│  │  │ PARALLEL (PS 7.4+)  │      │ SEQUENTIAL (PS < 7.4)           │   │   │
│  │  │ ForEach-Object      │      │ ForEach-Object                  │   │   │
│  │  │ -Parallel           │      │ (standard)                      │   │   │
│  │  └─────────────────────┘      └─────────────────────────────────┘   │   │
│  │                                                                      │   │
│  │  Output: photonos-urlhealth-{branch}_{timestamp}.prn                │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: PACKAGE REPORT (if enabled)                                        │
│  ┌────────────────┐     ┌────────────────┐     ┌─────────────────────────┐  │
│  │ GitPhoton()    │  →  │ ParseDirectory │  →  │ Combine all branches    │  │
│  │ All 7 branches │     │ All 7 branches │     │ into single report      │  │
│  └────────────────┘     └────────────────┘     └─────────────────────────┘  │
│                                                                              │
│  Output: photonos-package-report_{timestamp}.prn                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 5: DIFF REPORTS (if enabled)                                          │
│  Compare versions between branches, report where older > newer               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ Common vs Master│  │ 5.0 vs 6.0     │  │ 4.0 vs 5.0     │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│  ┌─────────────────┐                                                         │
│  │ 3.0 vs 4.0     │                                                         │
│  └─────────────────┘                                                         │
│  Output: photonos-diff-report-{branches}_{timestamp}.prn                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 6: CLEANUP                                                            │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────────┐   │
│  │ Clear tokens from memory    │  │ Remove git credentials from config  │   │
│  │ ($global:access, etc.)      │  │ (gitlab.freedesktop.org)            │   │
│  └─────────────────────────────┘  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SCRIPT END                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## FUNCTION CALL HIERARCHY

```
Main Execution
│
├── GenerateUrlHealthReports()
│   ├── GitPhoton()
│   │   └── Invoke-GitWithTimeout()
│   ├── ParseDirectory()
│   │   └── Get-SpecValue()
│   └── CheckURLHealth()  [parallel or sequential]
│       ├── Source0Lookup()
│       ├── urlhealth()
│       ├── KojiFedoraProjectLookUp()
│       ├── Versioncompare()
│       └── ModifySpecFile()
│
├── GitPhoton() [for Package Report]
│   └── Invoke-GitWithTimeout()
│
├── ParseDirectory() [for Package Report]
│   └── Get-SpecValue()
│
└── Versioncompare() [for Diff Reports]
```

---

## OUTPUT FILES

| Report Type | Filename Pattern | Content |
|-------------|------------------|---------|
| URL Health | `photonos-urlhealth-{branch}_{timestamp}.prn` | Package URL status, versions, updates |
| Package Report | `photonos-package-report_{timestamp}.prn` | All packages across all branches |
| Diff Report | `photonos-diff-report-{v1}-{v2}_{timestamp}.prn` | Packages where older version > newer |

---

## KEY DATA FLOW

```
.spec files → ParseDirectory() → Package Objects → CheckURLHealth() → .prn Reports
     │                                                     │
     │                                                     ▼
     │                                           Source0Lookup() (550+ entries)
     │                                                     │
     │                                                     ▼
     │                                           Web Scraping (GitHub, PyPI, etc.)
     │                                                     │
     │                                                     ▼
     └─────────────────────────────────────────→ ModifySpecFile() (optional)
```

---

## PARAMETERS

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `access` | string | `$env:GITHUB_TOKEN` | GitHub API access token |
| `gitlabaccess` | string | `$env:GITLAB_TOKEN` | GitLab API access token |
| `sourcepath` | string | `$env:PUBLIC` or `$HOME` | Working directory for git clones |
| `GeneratePh3URLHealthReport` | bool | `$true` | Generate URL health report for Photon 3.0 |
| `GeneratePh4URLHealthReport` | bool | `$true` | Generate URL health report for Photon 4.0 |
| `GeneratePh5URLHealthReport` | bool | `$true` | Generate URL health report for Photon 5.0 |
| `GeneratePh6URLHealthReport` | bool | `$true` | Generate URL health report for Photon 6.0 |
| `GeneratePhCommonURLHealthReport` | bool | `$true` | Generate URL health report for common branch |
| `GeneratePhDevURLHealthReport` | bool | `$true` | Generate URL health report for dev branch |
| `GeneratePhMasterURLHealthReport` | bool | `$true` | Generate URL health report for master branch |
| `GeneratePhPackageReport` | bool | `$true` | Generate combined package report |
| `GeneratePhCommontoPhMasterDiffHigherPackageVersionReport` | bool | `$true` | Generate diff report common vs master |
| `GeneratePh5toPh6DiffHigherPackageVersionReport` | bool | `$true` | Generate diff report 5.0 vs 6.0 |
| `GeneratePh4toPh5DiffHigherPackageVersionReport` | bool | `$true` | Generate diff report 4.0 vs 5.0 |
| `GeneratePh3toPh4DiffHigherPackageVersionReport` | bool | `$true` | Generate diff report 3.0 vs 4.0 |

---

## USAGE EXAMPLES

```powershell
# Run all reports (default)
pwsh -File photonos-package-report.ps1

# Run only Photon 3.0 URL health report
pwsh -File photonos-package-report.ps1 `
    -GeneratePh3URLHealthReport $true `
    -GeneratePh4URLHealthReport $false `
    -GeneratePh5URLHealthReport $false `
    -GeneratePh6URLHealthReport $false `
    -GeneratePhCommonURLHealthReport $false `
    -GeneratePhDevURLHealthReport $false `
    -GeneratePhMasterURLHealthReport $false `
    -GeneratePhPackageReport $false

# Use environment variables for tokens
$env:GITHUB_TOKEN = "your_github_token"
$env:GITLAB_TOKEN = "your_gitlab_token"
pwsh -File photonos-package-report.ps1
```

---

## PREREQUISITES

- **Operating System**: Windows 11 (tested), Linux/macOS (cross-platform support in v0.60)
- **PowerShell**: Minimum 5.1, Recommended 7.4+ for parallel processing
- **Required Commands**: `git`, `tar`
- **Required Module**: PowerShellCookbook (auto-installed if missing)
- **API Tokens**: GitHub and GitLab access tokens for API rate limits

---

## VERSION HISTORY

See script header for complete version history. Current version: **0.60**

Key improvements in v0.60:
- Git timeout handling to prevent hanging
- Cross-platform path handling (Windows/Linux/macOS)
- Security cleanup (clear tokens from memory)
- Performance improvements (List<T> instead of array +=)
- Safe spec parsing with null checks
