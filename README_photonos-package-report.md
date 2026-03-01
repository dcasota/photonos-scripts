# Photon OS Package Report Script - Structure & Workflow Overview

## SCRIPT STRUCTURE

```
photonos-package-report.ps1 (~5,176 lines)
│
├── HEADER (Lines 1-113)
│   ├── Synopsis & Version History
│   ├── Prerequisites & Hints (debug, run on Windows/WSL/Photon OS)
│   └── Parameter Declarations (15 parameters)
│
├── HELPER FUNCTIONS (Lines 115-347)
│   ├── Convert-ToBoolean        (115-123)  - Convert string params to bool (-File compat)
│   ├── Invoke-GitWithTimeout    (138-204)  - Git commands with timeout via System.Diagnostics.Process
│   │                                         (async stdout/stderr event handlers, no runspace deadlocks)
│   ├── Get-SpecValue            (206-217)  - Safe spec field extraction
│   └── ParseDirectory           (219-347)  - Parse .spec files from branch
│                                              (detects numeric subrelease dirs e.g. SPECS/91/)
│
├── CORE FUNCTIONS (Lines 348-1522)
│   ├── Versioncompare           (348-405)  - Compare version strings
│   ├── Clean-VersionNames       (406-416)  - Extract clean version names from raw strings
│   ├── GitPhoton                (418-465)  - Clone/fetch/reset Photon repos
│   │                                         (.git validation, reset --hard, re-clone fallback)
│   ├── Source0Lookup            (467-1327) - Lookup table for 848+ packages
│   │                                         (columns: specfile, Source0Lookup, gitSource,
│   │                                          gitBranch, customRegex, replaceStrings,
│   │                                          ignoreStrings, Warning, ArchivationDate)
│   ├── ModifySpecFile           (1329-1406)- Update spec files with new versions
│   │                                         (output filename from $SpecFileName to avoid collisions)
│   ├── urlhealth                (1408-1468)- Check URL HTTP status (120s timeout)
│   └── KojiFedoraProjectLookUp  (1470-1522)- Lookup Fedora Koji packages
│
├── MAIN PROCESSING FUNCTION (Lines 1524-4848)
│   └── CheckURLHealth           (1524-4637)- URL health check per package
│       ├── Subrelease early-return (vendor-pinned packages skip all checks)
│       ├── Version extraction from URLs
│       ├── Data scraping (GitHub, GitLab, PyPI, RubyGems JSON API, etc.)
│       ├── Update availability detection
│       ├── GNU FTP mirror fallback (ftp.funet.fi)
│       ├── Per-repo named mutex for parallel clone/fetch serialization
│       ├── Get-FileHashWithRetry (file hash with lock retry)
│       └── Spec file modification
│   └── GenerateUrlHealthReports (4639-4848)- Orchestrates parallel/sequential processing
│       └── Parallel monitoring: ConcurrentDictionary + System.Threading.Timer
│           (reports active threads every 60s, flags long-runners > 5 min)
│
├── MAIN EXECUTION (Lines 4850-5176)
│   ├── Initialization           (4850-4960)
│   │   ├── Security protocol setup
│   │   ├── OS detection
│   │   ├── Command availability check (git, tar)
│   │   ├── Module check (PowerShellCookbook)
│   │   ├── Parallel processing detection
│   │   ├── CPU/throttle configuration
│   │   ├── Path validation
│   │   └── Git safe.directory wildcard (cross-filesystem support)
│   │
│   ├── Authentication           (4962-5002)
│   │   ├── GitHub token prompt
│   │   └── GitLab username/token prompt
│   │       (env: GITLAB_FREEDESKTOP_ORG_USERNAME / GITLAB_FREEDESKTOP_ORG_TOKEN)
│   │       Git credentials configured unconditionally
│   │
│   ├── URL Health Reports       (5004-5028)
│   │   └── Call GenerateUrlHealthReports()
│   │
│   ├── Package Report           (5030-5100)
│   │   ├── Git clone/fetch all branches
│   │   ├── Parse all directories
│   │   ├── SubRelease column for vendor-pinned packages
│   │   └── Generate package-report.prn
│   │
│   ├── Diff Reports             (5102-5162)
│   │   ├── Common vs Master (subrelease rows excluded)
│   │   ├── 5.0 vs 6.0      (subrelease rows excluded)
│   │   ├── 4.0 vs 5.0      (subrelease rows excluded)
│   │   └── 3.0 vs 4.0      (subrelease rows excluded)
│   │
│   └── Cleanup                  (5164-5176)
│       ├── Clear tokens from memory
│       └── Remove git credentials
```

---

## WORKFLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SCRIPT START                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: INITIALIZATION                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ TLS 1.2/1.3 │→ │ OS Detection│→ │ Check git,  │→ │ Check PowerShell    │ │
│  │ Protocol +  │  │ (Windows?)  │  │ tar commands│  │ Cookbook module     │ │
│  │ SslProtocol │  │             │  │             │  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                                    │                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                          │
│  │ Parallel    │→ │ CPU/Throttle│→ │ Validate    │                          │
│  │ Support?    │  │ Calculation │  │ SourcePath  │                          │
│  └─────────────┘  └─────────────┘  └─────────────┘                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: AUTHENTICATION                                                    │
│  ┌────────────────────────┐       ┌────────────────────────────────────────┐│
│  │ GitHub Token           │       │ GitLab Username + Token                ││
│  │ ($env:GITHUB_TOKEN or  │       │ ($env:GITLAB_FREEDESKTOP_ORG_USERNAME  ││
│  │  prompt)               │       │  + $env:GITLAB_FREEDESKTOP_ORG_TOKEN   ││
│  │                        │       │  or prompt)                            ││
│  │                        │       │ Git credentials always configured      ││
│  └────────────────────────┘       └────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: URL HEALTH REPORTS (per enabled branch: 3.0, 4.0, 5.0, 6.0,       │
│           common, dev, master)                                              │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  GenerateUrlHealthReports()                                         │    │
│  │  ┌────────────────┐     ┌────────────────┐     ┌──────────────────┐ │    │
│  │  │ GitPhoton()    │  →  │ ParseDirectory │  →  │ For each package │ │    │
│  │  │ Clone/Fetch    │     │ Extract .spec  │     │ CheckURLHealth() │ │    │
│  │  │ Branch         │     │ metadata       │     │                  │ │    │
│  │  └────────────────┘     └────────────────┘     └────────┬─────────┘ │    │
│  │                                                          │          │    │
│  │                    ┌─────────────────────────────────────┘          │    │
│  │                    ▼                                                │    │
│  │  ┌─────────────────────────────────────────────────────────────────┐│    │
│  │  │  CheckURLHealth() - Per Package                                 ││    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ ││    │
│  │  │  │ Source0Lookup│→ │ urlhealth()  │→ │ Data Scraping:         │ ││    │
│  │  │  │ Get metadata │  │ Check HTTP   │  │ - GitHub API           │ ││    │
│  │  │  │ for package  │  │ status       │  │ - GitLab API           │ ││    │
│  │  │  └──────────────┘  └──────────────┘  │ - PyPI, RubyGems       │ ││    │
│  │  │                                      │ - SourceForge, GNU     │ ││    │
│  │  │                                      │ - Fedora Koji          │ ││    │
│  │  │                                      └────────────┬───────────┘ ││    │
│  │  │                                                   │             ││    │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌───────────▼──────────┐   ││    │
│  │  │  │ ModifySpec   │← │ Download     │← │ Detect Update        │   ││    │
│  │  │  │ File()       │  │ New Source   │  │ Available?           │   ││    │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────────┘   ││    │
│  │  └─────────────────────────────────────────────────────────────────┘│    │
│  │                                                                     │    │
│  │  Processing Mode:                                                   │    │
│  │  ┌─────────────────────┐  OR  ┌─────────────────────────────────┐   │    │
│  │  │ PARALLEL (PS 7.4+)  │      │ SEQUENTIAL (PS < 7.4)           │   │    │
│  │  │ ForEach-Object      │      │ ForEach-Object                  │   │    │
│  │  │ -Parallel            │      │ (standard)                      │   │    │
│  │  │ + Thread Monitoring │      │                                 │   │    │
│  │  │   (60s timer, 5min  │      │                                 │   │    │
│  │  │    long-runner flag) │      │                                 │   │    │
│  │  └─────────────────────┘      └─────────────────────────────────┘   │    │
│  │                                                                     │    │
│  │  Output: photonos-urlhealth-{branch}_{timestamp}.prn                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: PACKAGE REPORT (if enabled)                                       │
│  ┌────────────────┐     ┌────────────────┐     ┌─────────────────────────┐  │
│  │ GitPhoton()    │  →  │ ParseDirectory │  →  │ Combine all branches    │  │
│  │ All 7 branches │     │ All 7 branches │     │ into single report      │  │
│  └────────────────┘     └────────────────┘     └─────────────────────────┘  │
│                                                                             │
│  Output: photonos-package-report_{timestamp}.prn                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 5: DIFF REPORTS (if enabled)                                         │
│  Compare versions between branches, report where older > newer              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │ Common vs Master│  │ 5.0 vs 6.0     │  │ 4.0 vs 5.0     │                │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│  ┌─────────────────┐                                                        │
│  │ 3.0 vs 4.0     │                                                         │
│  └─────────────────┘                                                        │
│  Output: photonos-diff-report-{branches}_{timestamp}.prn                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 6: CLEANUP                                                           │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────────┐   │
│  │ Clear tokens from memory    │  │ Remove git credentials from config  │   │
│  │ ($global:access, etc.)      │  │ (gitlab.freedesktop.org)            │   │
│  └─────────────────────────────┘  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SCRIPT END                                     │
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
│   │   └── Invoke-GitWithTimeout()  [System.Diagnostics.Process, async event handlers]
│   ├── ParseDirectory()
│   │   └── Get-SpecValue()
│   │   └── SubRelease detection (numeric SPECS/ subdirs)
│   └── CheckURLHealth()  [parallel with monitoring, or sequential]
│       ├── [subrelease early-return for vendor-pinned packages]
│       ├── Source0Lookup()           [848 packages, 9 columns]
│       ├── urlhealth()              [120s timeout]
│       ├── KojiFedoraProjectLookUp()
│       ├── Versioncompare()
│       ├── Clean-VersionNames()
│       └── ModifySpecFile()         [$SpecFileName-based output naming]
│
├── Parallel Monitoring (System.Threading.Timer + ConcurrentDictionary)
│   └── Reports active threads every 60s, flags long-runners > 5 min
│
├── GitPhoton() [for Package Report]
│   └── Invoke-GitWithTimeout()
│
├── ParseDirectory() [for Package Report]
│   └── Get-SpecValue()
│
└── Versioncompare() [for Diff Reports, subrelease rows excluded]
```

---

## OUTPUT FILES

| Report Type | Filename Pattern | Content |
|-------------|------------------|---------|
| URL Health | `photonos-urlhealth-{branch}_{timestamp}.prn` | Package URL status, versions, updates, Warning, ArchivationDate. Vendor-pinned packages show `UrlHealth=pinned`. |
| Package Report | `photonos-package-report_{timestamp}.prn` | All packages across all branches with SubRelease column (vendor-pinned packages listed separately) |
| Diff Report | `photonos-diff-report-{v1}-{v2}_{timestamp}.prn` | Packages where older version > newer (subrelease packages excluded) |

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
| `gitlab_freedesktop_org_username` | string | `$env:GITLAB_FREEDESKTOP_ORG_USERNAME` | GitLab username for gitlab.freedesktop.org |
| `gitlab_freedesktop_org_token` | string | `$env:GITLAB_FREEDESKTOP_ORG_TOKEN` | GitLab access token for gitlab.freedesktop.org |
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
$env:GITLAB_FREEDESKTOP_ORG_USERNAME = "your_gitlab_username"
$env:GITLAB_FREEDESKTOP_ORG_TOKEN = "your_gitlab_token"
pwsh -File photonos-package-report.ps1
```

---

## PREREQUISITES

- **Operating System**: Windows 11 (tested), Photon OS 5.0 with PowerShell Core 7.5.4 (tested), Linux/WSL/macOS (cross-platform support since v0.60)
- **PowerShell**: Minimum 5.1, Recommended 7.4+ for parallel processing
- **Required Commands**: `git`, `tar`
- **Required Module**: PowerShellCookbook (auto-installed if missing)
- **API Tokens**: GitHub and GitLab access tokens for API rate limits
- **Note**: On WSL/cross-filesystem setups, the script automatically adds `git safe.directory '*'` to handle ownership mismatches

---

## VERSION HISTORY

See script header for complete version history. Current version: **0.64**

Key improvements in v0.64:
- **Artifact directories moved to photon-upstreams/:** `clones`, `SOURCES_NEW`, `SPECS_NEW`, and `SOURCES_KojiFedora` are now created under `$sourcepath/photon-upstreams/photon-{branch}/` instead of inside the git repo directories. This keeps git repos clean, allows `git reset --hard` and re-clone without losing cached data, and preserves expensive clones (e.g. chromium) across repo resets.
- **New `$UpstreamsPath` parameter:** Added to `ModifySpecFile`, `CheckURLHealth`, and `GenerateUrlHealthReports` to thread the upstreams directory through the call chain including parallel runspaces.
- **Fixed hardcoded output paths:** Package Report and all Diff Report output paths were hardcoded to `$env:public`, ignoring the `-sourcepath` parameter and failing on Linux. Now uses `Join-Path $sourcepath` for cross-platform compatibility.

Key improvements in v0.63:
- **Invoke-GitWithTimeout now throws on non-zero exit codes:** Previously, git failures (e.g. "not a git repository", merge conflicts) were only logged as warnings but did not throw, making the catch/re-clone fallback in GitPhoton unreachable dead code
- **GitPhoton .git directory validation:** Before attempting fetch/update, the function now checks that `.git` exists inside the branch directory; directories missing git metadata are automatically removed and re-cloned
- **Replaced git merge with git reset --hard:** Since this script is a read-only consumer of Photon repos, `git reset --hard origin/$release` is used instead of `git merge`, eliminating merge conflicts entirely
- **Fixed clone -WorkingDirectory bug:** The initial clone call passed `-WorkingDirectory` without a value; now correctly passes `-WorkingDirectory $SourcePath`

Key improvements in v0.62:
- **Parallel deadlock fix:** Replaced `Start-Job`/`Wait-Job` with `System.Diagnostics.Process` + async stdout/stderr event handlers in `Invoke-GitWithTimeout` to prevent runspace deadlocks inside `ForEach-Object -Parallel`
- **Timeout hardening:** Added 120s timeouts to bare `git tag -l` calls, `HttpWebRequest`, and `Invoke-WebRequest` (replaced `WebClient.DownloadFile`)
- **Per-repo named mutex:** Serializes parallel `git clone`/`fetch` operations per repository to prevent file lock collisions
- **Null propagation prevention:** Wrapped 165+ pipeline reassignments in `@()` and added null guards for `Get-HighestJdkVersion` and `.ToString()` calls
- **GitLab credential refactor:** Renamed env vars to `GITLAB_FREEDESKTOP_ORG_USERNAME` / `GITLAB_FREEDESKTOP_ORG_TOKEN`, added dedicated parameters, git credentials configured unconditionally (not only from prompt path)
- **ModifySpecFile collision fix:** Output filename derived from `$SpecFileName` (e.g. `linux-aws-5.10.spec`) instead of `$Name` (e.g. `linux-5.10.spec`) to prevent parallel file lock conflicts for linux variant specs
- **Numeric subrelease directory support:** Detects vendor-pinned packages in `SPECS/91/` etc.; tags with `SubRelease` property, skips upstream version checks, adds `SubRelease` column to Package Report, excludes from Diff Reports to prevent false positives
- **Clone timeout increase:** `Invoke-GitWithTimeout` default raised to 14400s (4 hours) for large clones like chromium
- **Source0Lookup caching:** CSV parsed once and passed via `$using:` to parallel runspaces, eliminating ~6000 redundant parse operations per run
- **TLS 1.2 enforcement:** `$PSDefaultParameterValues` sets `-SslProtocol Tls12` for all `Invoke-WebRequest`/`Invoke-RestMethod` calls in both main scope and parallel init script
- **Secure token cleanup:** `SecureStringToBSTR` results freed with `ZeroFreeBSTR` in `try/finally` to clear plaintext from unmanaged memory
- **Cross-platform credential cleanup:** Git credential `--unset` now runs on all platforms (previously Windows-only, leaving tokens in `~/.gitconfig` on Linux)
- **HTTPS upgrades:** 9 Source0/SourceTag URLs upgraded from `http://` to `https://` (kernel.org, freedesktop.org, schmorp.de, oberhumer.com, antlr3.org, sourceforge.net)

Key improvements in v0.61:
- Quarterly version format support in Get-LatestName (YYYY.Q#.# for amdvlk, etc.)
- Warning/ArchivationDate columns in URL health report output (warnings no longer overwrite UpdateAvailable)
- v- prefix handling in UpdateDownloadName
- Fixed missing $ in runit.spec condition
- git fetch --prune --prune-tags --tags to ensure all remote tags are synced (fixes missing tags like httpd 2.4.66)
- Get-FileHashWithRetry helper for file hash with automatic retry on lock
- Fixed GITHUB_USERNAME → GITLAB_USERNAME in usage hints

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
- Source0Lookup expanded to 848 packages with Warning/ArchivationDate columns
- Improved version comparison algorithm (fixes 2.41.3 vs 2.9)
