# Photon OS Package Report Script - Structure & Workflow Overview

## SCRIPT STRUCTURE

```
photonos-package-report.ps1 (~5,330 lines)
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
│       ├── Wait-ForFetchCompletion (poll-based parallel fetch serialization)
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
│  │ ($global:github_token, etc.)│  │ (gitlab.freedesktop.org)            │   │
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
│       ├── Wait-ForFetchCompletion() [poll-based parallel fetch serialization]
│       ├── Get-FileHashWithRetry()  [file hash with lock retry]
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
| `github_token` | string | `$env:GITHUB_TOKEN` | GitHub API access token |
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

- **Operating System**: **Linux recommended** (Photon OS 5.0 tested with PowerShell Core 7.5.4). Windows 11 tested but has known limitations (see below). WSL/macOS also supported (cross-platform since v0.60).
- **PowerShell**: Minimum 5.1, Recommended 7.4+ for parallel processing
- **Required Commands**: `git`, `tar`
- **Required Module**: PowerShellCookbook (auto-installed if missing)
- **API Tokens**: GitHub and GitLab access tokens for API rate limits
- **Note**: On WSL/cross-filesystem setups, the script automatically adds `git safe.directory '*'` to handle ownership mismatches

### Why Linux is Recommended

Running on Windows introduces several platform-specific issues that do not occur on Linux:

1. **NTFS trailing-dot restriction:** Some upstream repos (e.g. hashicorp/consul) have branch names containing path components that end with a dot (e.g. `backport/ce_1.21.5./sec/constant-time-compare`). On Windows, NTFS/Win32 silently strips trailing dots from directory names, which prevents git from creating the ref tracking file at `.git/refs/remotes/origin/...`. The fetch fails with `error: cannot lock ref ... unable to create directory`. On Linux (ext4, xfs, btrfs), trailing dots in directory names are fully supported and these fetches complete without error.

2. **SChannel TLS buffer limitations:** Windows uses the SChannel TLS backend for HTTPS git operations. Very large repos (llvm-project, rust, chromium with 7+ GB packfiles) can exhaust SChannel's internal buffers during fetch, causing `curl 56 schannel: server closed abruptly` errors. While `http.postBuffer` mitigates the upload side, the receive path remains vulnerable. On Linux, git uses OpenSSL which handles large transfers more reliably.

3. **File path length limits:** Windows has a default 260-character path limit (`MAX_PATH`). Deeply nested clone paths inside `photon-upstreams/photon-{branch}/clones/{repo}/...` can exceed this. Linux has a 4096-character limit per path component, making this a non-issue.

For production use, running on Photon OS or another Linux distribution with PowerShell Core 7.4+ is recommended to avoid these platform limitations entirely.

---

## VERSION HISTORY

Current version: **0.64**. Full details for each version below; the script header contains one-line summaries.

### v0.64 (01.03.2026)

**Artifact restructure, git fetch fixes, poll-based fetch completion, netcat.spec, .asc version fix, Source0Lookup fixes**

- **Artifact directories moved to photon-upstreams/:** `clones`, `SOURCES_NEW`, `SPECS_NEW`, and `SOURCES_KojiFedora` are now created under `$sourcepath/photon-upstreams/photon-{branch}/` instead of inside the git repo directories. This keeps git repos clean, allows `git reset --hard` and re-clone without losing cached data, and preserves expensive clones (e.g. chromium) across repo resets.
- **New `$UpstreamsPath` parameter:** Added to `ModifySpecFile`, `CheckURLHealth`, and `GenerateUrlHealthReports` to thread the upstreams directory through the call chain including parallel runspaces.
- **Fixed hardcoded output paths:** Package Report and all Diff Report output paths were hardcoded to `$env:public`, ignoring the `-sourcepath` parameter and failing on Linux. Now uses `Join-Path $sourcepath` for cross-platform compatibility.
- **HTTP post buffer for large repos:** Added `git config --global http.postBuffer 524288000` (500MB) to prevent SChannel/curl `server closed abruptly` errors during fetch of extremely large repositories (llvm-project, rust, chromium).
- **Clone .git validation in CheckURLHealth:** All 3 clone logic blocks now validate `.git` directory existence before fetch. If the directory exists but `.git` is missing (interrupted/corrupted clone), the directory is removed and a re-clone is triggered via the retry loop.
- **Force-fetch for diverged tags:** Added `--force` to all fetch commands in CheckURLHealth. Upstream repos sometimes rewrite/force-push tags; without `--force`, git rejects the update with "would clobber existing tag". Since this script is a read-only consumer, force-overwriting local tags is the correct behavior.
- **Fixed per-repo mutex for parallel safety:** Removed branch-specific `$photonDir` from the mutex name so concurrent access to the same upstream repo (e.g. llvm-project from photon-5.0 and photon-6.0) is properly serialized. Increased mutex timeout from 120s to 600s for large repo fetches.
- **Renamed `$access` parameter to `$github_token`:** For consistency with `$gitlab_freedesktop_org_username` and `$gitlab_freedesktop_org_token`.
- **Poll-based fetch completion detection (`Wait-ForFetchCompletion`):** Replaced direct mutex-only serialization in all 3 clone blocks with a new helper function that mirrors the `Get-FileHashWithRetry` pattern. The first thread to reach a repo acquires the mutex and performs the fetch; all other threads poll the repo's `FETCH_HEAD` timestamp every 3 seconds and proceed immediately when it becomes fresh (written during the current script run), without acquiring the mutex or performing a redundant fetch. This eliminates redundant network transfers for shared repos like llvm-project (referenced by clang, lldb, compiler-rt, llvm specs).
- **Added `$ScriptStartTime` parameter:** Threaded through `GenerateUrlHealthReports` and `CheckURLHealth` (including parallel context) for `FETCH_HEAD` freshness detection.
- **netcat.spec special-case handling:** Version extracted from CVS revision ID in `openbsd/src` `netcat.c` header comment via `$OpenBSD: netcat.c,v` regex. Commit ID fetched from GitHub Commits API for `usr.bin/nc` directory. Source tarball built from existing persistent clone (Copy-Item from `clones/src/usr.bin/nc`, not a redundant shallow clone). Added `%global commit_id` replacement in `ModifySpecFile` and `%{commit_id}` macro substitution for Source0 URL resolution. Added `commit_id` extraction in `ParseDirectory`.
- **Fixed ModifySpecFile version truncation (.asc bug):** `GetExtension("1.238")` returned `".238"`, truncating the version to `"1"` and producing filenames like `netcat-1.spec` instead of `netcat-1.238.spec`. Now only strips the extension when it is actually `.asc`.
- **Source0Lookup fixes:** Fixed `entchant.spec` typo to `enchant.spec` with corrected release download URL. Added `libnetfilter_conntrack` git source. Moved packaging format change warnings from hardcoded `if` blocks into Source0Lookup CSV Warning column (`libnftnl`, `python-Twisted`).

### v0.63 (01.03.2026)

**GitPhoton robustness: throw on git errors, .git validation, reset --hard**

- **Invoke-GitWithTimeout now throws on non-zero exit codes:** Previously, git failures (e.g. "not a git repository", merge conflicts) were only logged as warnings but did not throw, making the catch/re-clone fallback in GitPhoton unreachable dead code.
- **GitPhoton .git directory validation:** Before attempting fetch/update, the function now checks that `.git` exists inside the branch directory; directories missing git metadata are automatically removed and re-cloned.
- **Replaced git merge with git reset --hard:** Since this script is a read-only consumer of Photon repos, `git reset --hard origin/$release` is used instead of `git merge`, eliminating merge conflicts entirely.
- **Fixed clone -WorkingDirectory bug:** The initial clone call passed `-WorkingDirectory` without a value; now correctly passes `-WorkingDirectory $SourcePath`.

### v0.62 (24.02.2026)

**Parallel deadlock fix, mutex serialization, subrelease detection, caching, security**

- **Parallel deadlock fix:** Replaced `Start-Job`/`Wait-Job` with `System.Diagnostics.Process` + async stdout/stderr event handlers in `Invoke-GitWithTimeout` to prevent runspace deadlocks inside `ForEach-Object -Parallel`.
- **Timeout hardening:** Added 120s timeouts to bare `git tag -l` calls, `HttpWebRequest`, and `Invoke-WebRequest` (replaced `WebClient.DownloadFile`).
- **Per-repo named mutex:** Serializes parallel `git clone`/`fetch` operations per repository to prevent file lock collisions.
- **Null propagation prevention:** Wrapped 165+ pipeline reassignments in `@()` and added null guards for `Get-HighestJdkVersion` and `.ToString()` calls.
- **GitLab credential refactor:** Renamed env vars to `GITLAB_FREEDESKTOP_ORG_USERNAME` / `GITLAB_FREEDESKTOP_ORG_TOKEN`, added dedicated parameters, git credentials configured unconditionally (not only from prompt path).
- **ModifySpecFile collision fix:** Output filename derived from `$SpecFileName` (e.g. `linux-aws-5.10.spec`) instead of `$Name` (e.g. `linux-5.10.spec`) to prevent parallel file lock conflicts for linux variant specs.
- **Numeric subrelease directory support:** Detects vendor-pinned packages in `SPECS/91/` etc.; tags with `SubRelease` property, skips upstream version checks, adds `SubRelease` column to Package Report, excludes from Diff Reports to prevent false positives.
- **Clone timeout increase:** `Invoke-GitWithTimeout` default raised to 14400s (4 hours) for large clones like chromium.
- **Source0Lookup caching:** CSV parsed once and passed via `$using:` to parallel runspaces, eliminating ~6000 redundant parse operations per run.
- **TLS 1.2 enforcement:** `$PSDefaultParameterValues` sets `-SslProtocol Tls12` for all `Invoke-WebRequest`/`Invoke-RestMethod` calls in both main scope and parallel init script.
- **Secure token cleanup:** `SecureStringToBSTR` results freed with `ZeroFreeBSTR` in `try/finally` to clear plaintext from unmanaged memory.
- **Cross-platform credential cleanup:** Git credential `--unset` now runs on all platforms (previously Windows-only, leaving tokens in `~/.gitconfig` on Linux).
- **HTTPS upgrades:** 9 Source0/SourceTag URLs upgraded from `http://` to `https://` (kernel.org, freedesktop.org, schmorp.de, oberhumer.com, antlr3.org, sourceforge.net).

### v0.61 (23.02.2026)

**Version format, Warning/ArchivationDate columns, Source0Lookup expansion**

- Quarterly version format support in `Get-LatestName` (YYYY.Q#.# for amdvlk, etc.).
- Warning/ArchivationDate columns in URL health report output (warnings no longer overwrite UpdateAvailable).
- `v-` prefix handling in UpdateDownloadName.
- Fixed missing `$` in runit.spec condition.
- `git fetch --prune --prune-tags --tags` to ensure all remote tags are synced (fixes missing tags like httpd 2.4.66).
- `Get-FileHashWithRetry` helper for file hash with automatic retry on lock.
- Fixed `GITHUB_USERNAME` -> `GITLAB_USERNAME` in usage hints.

### v0.60 (11.02.2026)

**Robustness, security and cross-platform improvements**

- Git timeout handling (600s for all operations) to prevent hanging.
- Cross-platform path handling (Windows/Linux/macOS).
- Safe git calls (`&` operator instead of `Invoke-Expression`).
- Security cleanup (clear tokens from memory, remove git credentials).
- Performance improvements (`List<T>` instead of array `+=`).
- Safe spec parsing with `Get-SpecValue` helper and null checks.
- `Convert-ToBoolean` for proper `-File` parameter handling.
- RubyGems version detection via JSON API (replaces HTML scraping).
- GNU FTP mirror fallback (`ftp.funet.fi` for `ftp.gnu.org`).
- Delete and re-clone on git merge failure.
- Git `safe.directory` wildcard for WSL/cross-filesystem support.
- Linux compatibility fix for `Stop-Job`/`Remove-Job` (no `-Force`).
- `Test-Path` guards before `Set-Location` after clone.
- Source0Lookup expanded to 848 packages with Warning/ArchivationDate columns.
- Improved version comparison algorithm (fixes 2.41.3 vs 2.9).

### v0.50-0.59

- v0.59 (11.02.2026): Various bugfixes.
- v0.58 (29.07.2025): Various bugfixes.
- v0.57 (17.06.2025): Data scraping modifications, Source0Lookup gitSource/gitBranch/customRegex/replaceStrings added, various bugfixes.
- v0.56 (11.06.2025): Various bugfixes.
- v0.55 (30.05.2025): Parallel processing for spec file modifications.
- v0.54 (30.05.2025): Parallel processing for URL health checks.
- v0.53 (13.02.2025): KojiFedoraProjectLookUp, various URL fixes.
- v0.52 (08.09.2024): Photon 6.0 and common branch added.
- v0.51 (06.03.2024): Git check added.
- v0.50 (04.02.2024): Various URL fixes.

### v0.40-0.49

- v0.49 (24.01.2024): Fix chrpath host path.
- v0.48 (03.06.2023): Separated sources_new and specs_new directories, bugfixes packages netfilter + python, Source0 urlhealth check.
- v0.47 (20.05.2023): Bugfixes, ModifySpecFile added.
- v0.46 (09.05.2023): UpdateURL added.
- v0.45 (08.05.2023): Bugfix for zip.spec + unzip.spec.
- v0.44 (17.03.2023): URL health coverage improvements, updateavailable signalization for rubygems.org and sourceforge.net.
- v0.43 (06.03.2023): URL health coverage improvements, updateavailable signalization without alpha/release candidate/pre/dev versions.
- v0.42 (01.03.2023): URL health coverage improvements.
- v0.41 (28.02.2023): URL health coverage improvements.
- v0.4 (27.02.2023): CheckURLHealth added, timestamp in reports, URL health coverage improvements.

### v0.1-0.3

- v0.3 (05.02.2023): 5.0 added, report release x package with a higher version than same release x+1 package.
- v0.2 (17.04.2021): dev added.
- v0.1 (06.03.2021): First release.
