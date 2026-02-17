# Photon OS Package Report Script - Structure & Workflow Overview

## SCRIPT STRUCTURE

```
photonos-package-report.ps1 (~5,022 lines)
│
├── HEADER (Lines 1-58)
│   ├── Synopsis & Version History
│   └── Parameter Declarations (13 parameters)
│
├── HELPER FUNCTIONS (Lines 60-253)
│   ├── Convert-ToBoolean        (60-68)    - Convert string params to bool (-File compat)
│   ├── Invoke-GitWithTimeout    (83-117)   - Git commands with 600s timeout via Start-Job
│   ├── Get-SpecValue            (119-130)  - Safe spec field extraction
│   └── ParseDirectory           (132-253)  - Parse .spec files from branch
│
├── CORE FUNCTIONS (Lines 254-1401)
│   ├── Versioncompare           (254-311)  - Compare version strings
│   ├── GitPhoton                (312-360)  - Clone/fetch/merge Photon repos
│   │                                         (delete + re-clone on merge failure)
│   ├── Source0Lookup            (361-1215) - Lookup table for 848 packages
│   │                                         (columns: specfile, Source0Lookup, gitSource,
│   │                                          gitBranch, customRegex, replaceStrings,
│   │                                          ignoreStrings, isArchived, ArchivationDate)
│   ├── ModifySpecFile           (1216-1289)- Update spec files with new versions
│   ├── urlhealth                (1290-1350)- Check URL HTTP status
│   └── KojiFedoraProjectLookUp  (1351-1401)- Lookup Fedora Koji packages
│
├── MAIN PROCESSING FUNCTION (Lines 1403-4553)
│   └── CheckURLHealth           (1403-4505)- URL health check per package
│       ├── Version extraction from URLs
│       ├── Data scraping (GitHub, GitLab, PyPI, RubyGems JSON API, etc.)
│       ├── Update availability detection
│       ├── GNU FTP mirror fallback (ftp.funet.fi)
│       └── Spec file modification
│   └── GenerateUrlHealthReports (4555-4699)- Orchestrates parallel/sequential processing
│
├── MAIN EXECUTION (Lines 4701-5022)
│   ├── Initialization           (4701-4810)
│   │   ├── Security protocol setup
│   │   ├── OS detection
│   │   ├── Command availability check (git, tar)
│   │   ├── Module check (PowerShellCookbook)
│   │   ├── Parallel processing detection
│   │   ├── CPU/throttle configuration
│   │   ├── Path validation
│   │   └── Git safe.directory wildcard (cross-filesystem support)
│   │
│   ├── Authentication           (4812-4870)
│   │   ├── GitHub token prompt
│   │   └── GitLab username/token prompt
│   │
│   ├── URL Health Reports       (4872-4892)
│   │   └── Call GenerateUrlHealthReports()
│   │
│   ├── Package Report           (4894-4930)
│   │   ├── Git clone/fetch all branches
│   │   ├── Parse all directories
│   │   └── Generate package-report.prn
│   │
│   ├── Diff Reports             (4932-5008)
│   │   ├── Common vs Master
│   │   ├── 5.0 vs 6.0
│   │   ├── 4.0 vs 5.0
│   │   └── 3.0 vs 4.0
│   │
│   └── Cleanup                  (5010-5022)
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
├── Convert-ToBoolean()  [applied to all boolean params at startup]
│
├── GenerateUrlHealthReports()
│   ├── GitPhoton()
│   │   └── Invoke-GitWithTimeout()  [600s timeout, delete+re-clone on failure]
│   ├── ParseDirectory()
│   │   └── Get-SpecValue()
│   └── CheckURLHealth()  [parallel or sequential]
│       ├── Source0Lookup()           [848 packages, 9 columns]
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
     │                                           Source0Lookup() (848 entries)
     │                                                     │
     │                                                     ▼
     │                                           Web Scraping (GitHub, PyPI, RubyGems API,
     │                                           GitLab, SourceForge, GNU mirrors, etc.)
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

- **Operating System**: Windows 11 (tested), Linux/WSL/macOS (cross-platform support in v0.60)
- **PowerShell**: Minimum 5.1, Recommended 7.4+ for parallel processing
- **Required Commands**: `git`, `tar`
- **Required Module**: PowerShellCookbook (auto-installed if missing)
- **API Tokens**: GitHub and GitLab access tokens for API rate limits
- **Note**: On WSL/cross-filesystem setups, the script automatically adds `git safe.directory '*'` to handle ownership mismatches

---

## VERSION HISTORY

See script header for complete version history. Current version: **0.60**

Key improvements in v0.60:
- Git timeout handling (600s for all operations) to prevent hanging
- Cross-platform path handling (Windows/Linux/macOS)
- Safe git calls (& operator instead of Invoke-Expression)
- Security cleanup (clear tokens from memory, remove git credentials)
- Performance improvements (List<T> instead of array +=)
- Safe spec parsing with Get-SpecValue helper and null checks
- Convert-ToBoolean for proper -File parameter handling
- RubyGems version detection via JSON API (replaces HTML scraping)
- GNU FTP mirror fallback (ftp.funet.fi for ftp.gnu.org)
- Delete and re-clone on git merge failure
- Git safe.directory wildcard for WSL/cross-filesystem support
- Linux compatibility fix for Stop-Job/Remove-Job (no -Force)
- Test-Path guards before Set-Location after clone
- Source0Lookup expanded to 848 packages with isArchived/ArchivationDate columns
- Improved version comparison algorithm (fixes 2.41.3 vs 2.9)
