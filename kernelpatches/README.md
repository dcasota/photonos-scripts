# Photon OS Kernel Backport Tool

Automated kernel patch backporting and CVE coverage tracking for Photon OS.

## Overview

The kernelpatches solution provides:

- **CVE Coverage Matrix** - Track CVE status across kernel versions with CVSS scores, severity, and fix references
- **Photon Version Awareness** - Compare Photon's current kernel version vs latest stable available
- **Gap Detection** - Identify CVEs without stable backports that require manual patching
- **Patch Backporting** - Automated CVE and stable patch integration into Photon spec files
- **Feed-based Analysis** - Fast offline CVE analysis using local NVD feed cache (no per-CVE API calls)
- **Scheduled Automation** - Install with cron for automated backporting

### Dependencies

- Python 3.9+
- click, requests, pydantic, GitPython, rich, aiohttp

## Quick Start

Recommended Workflow

   1. **Initial Setup**

      ```bash
           cd kernelpatches
           pip install -e .
      ```
      
      After initial setup, the CLI tool can be invoked as `photon-kernel-backport` or the shorter alias `phkbp`.  

   2. **Assessment Phase** (understand current state)

      ```bash
           # Check kernel status first
           photon-kernel-backport status --kernel 5.10
      
           # Generate CVE coverage matrix with all CVE and stable patch data (auto-clones repos)
           photon-kernel-backport matrix --kernel 5.10
      
           # Identify specific CVE gaps requiring attention
           photon-kernel-backport gaps --kernel 5.10 --output /var/log/photon-kernel-backport/gap_reports
      ```
   3. **Patching Phase** (apply fixes)

      ```bash
           # Dry run first to see what will happen
           photon-kernel-backport backport --kernel 5.10 --source all --dry-run
      
           # Apply CVE and stable patches
           photon-kernel-backport backport --kernel 5.10 --source all --detect-gaps
      ```
   4. **Build Phase** (create RPMs)

      ```bash
           # Build kernel RPMs using official SRPM
           photon-kernel-backport build --kernel 5.10
      
           # Build specific spec only
           photon-kernel-backport build --kernel 5.10 --specs linux-esx.spec
      ```
   5. **Automation Phase** (ongoing maintenance)

      ```bash
           # Install with cron for automated backporting (every 2 hours default)
           photon-kernel-backport install --cron "0 4 * * *" --kernel 5.10,6.1,6.12
      ```
   Prerequisites Chain

   Step          │ Prerequisites
   --------------+-------------------------------------------------------
   `status`      │ Photon repo clones (auto-cloned to 4.0/, 5.0/, common/)
   `matrix`      │ Network access for NVD feeds, stable patches, and repo cloning
   `gaps`        │ NVD feed cache auto-downloaded
   `backport`    │ Network access for repo cloning (repos auto-cloned)
   `build`       │ Network access to packages.broadcom.com, tdnf for deps
   `install`     │ Root access for cron and /opt directories

   The typical flow is: status -> matrix/gaps (assess) -> backport (patch) -> build (compile) -> install (automate).
   
   **Note:** All commands that need Photon repos (`matrix`, `backport`, `cve-build-workflow`) automatically clone them.
   Use `--repo-base` and `--repo-url` to customize the clone location and source repository.
```

## Commands

| Command | Description |
|---------|-------------|
| `matrix` | Generate comprehensive CVE coverage matrix |
| `gaps` | Detect CVE backport gaps |
| `backport` | Run kernel patch backporting workflow |
| `cve-build-workflow` | Two-phase CVE coverage build with comprehensive reporting |
| `status` | Check kernel status and available updates |
| `download` | Download stable patches from kernel.org |
| `build` | Build kernel RPMs using official SRPM from Broadcom |
| `install` | Install with optional cron scheduling |
| `cve` | CVE-related subcommands |

### `matrix` - CVE Coverage Matrix Generation

Generate a comprehensive CVE coverage matrix with all CVEs and stable patches:

```bash
# Generate matrix for all kernels (auto-clones repos)
photon-kernel-backport matrix

# Specific kernel
photon-kernel-backport matrix --kernel 5.10

# Multiple kernels
photon-kernel-backport matrix --kernel 6.1,6.12

# Custom output directory
photon-kernel-backport matrix --kernel 5.10 --output /tmp/cve_matrix

# Custom repo location and URL
photon-kernel-backport matrix --kernel 5.10 --repo-base /tmp/repos --repo-url https://github.com/myorg/photon.git

# Update existing repos before generating matrix
photon-kernel-backport matrix --kernel 5.10 --update-repos
```

This will:
1. Fetch ~7,500 CVEs from NVD (kernel.org CNA)
2. Download stable patches from kernel.org
3. Read Photon's current kernel versions from spec files
4. Build complete coverage matrix with five-state tracking
5. Download CVE patches for CVEs with fix commits
6. Analyze patches against kernel source to detect already-included fixes
7. Export to JSON, CSV, and Markdown formats

**Summary Output:**

The matrix command produces a summary showing:
- Total CVEs and severity distribution
- Coverage by kernel (included, in newer stable, spec patch, missing)
- Critical/High gaps requiring attention
- **Applicable CVE Patches** section with:
  - Total applicable patches count
  - Severity distribution of applicable patches
  - Coverage by kernel
  - All critical/high applicable patches listed with CVSS scores

**Five CVE States:**

| State | Icon | Description |
|-------|------|-------------|
| `cve_not_applicable` | ➖ | CVE doesn't affect this kernel version |
| `cve_included` | ✅ | Fix is included in Photon's current stable version |
| `cve_in_newer_stable` | ⬆️ | Fix exists in newer stable patch (upgrade available) |
| `cve_patch_available` | 🔄 | Patch exists in spec file but not in any stable |
| `cve_patch_missing` | ❌ | CVE affects kernel but no patch exists (gap) |

### `gaps` - CVE Gap Detection

Identify CVEs that affect a kernel but have no available patch.

```bash
# Analyze all kernel.org CVEs from NVD feeds
photon-kernel-backport gaps --kernel 5.10

# Analyze specific CVEs from a file
photon-kernel-backport gaps --kernel 6.1 --cve-list /var/log/photon-kernel-backport/gap_reports/cves.txt

# Custom output directory
photon-kernel-backport gaps --kernel 6.12 --output /var/log/photon-kernel-backport/gap_reports
```

**Performance:** Analyzes 7,500+ CVEs in ~30 seconds (vs ~20 hours with per-CVE API calls)

### `backport` - Patch Backporting

Run the full backport workflow for CVE or stable patches.

```bash
# CVE patches from NVD
photon-kernel-backport backport --kernel 6.1 --source cve

# Stable kernel patches
photon-kernel-backport backport --kernel 5.10 --source stable

# Both CVE and stable
photon-kernel-backport backport --kernel 6.12 --source all

# Dry run
photon-kernel-backport backport --kernel 6.1 --dry-run

# With gap detection
photon-kernel-backport backport --kernel 5.10 --detect-gaps

# Custom repo location and URL
photon-kernel-backport backport --kernel 5.10 --repo-base /tmp/repos --repo-url https://github.com/myorg/photon.git
```

### `cve-build-workflow` - Two-Phase CVE Coverage Build

Run a comprehensive two-phase workflow that:
1. **Phase 1**: Builds current kernel (e.g., 6.12.60) with CVE patches
2. **Phase 2**: Builds latest stable kernel (e.g., 6.12.63) with CVE patches

Each phase generates CVE coverage matrix, downloads missing patches, integrates them into spec files, builds RPMs, and produces comprehensive JSON/Markdown reports.

```bash
# Full workflow for all kernels
photon-kernel-backport cve-build-workflow

# Single kernel
photon-kernel-backport cve-build-workflow --kernel 6.12

# Multiple kernels
photon-kernel-backport cve-build-workflow --kernel 5.10,6.1

# Phase 1 only (current kernel)
photon-kernel-backport cve-build-workflow --kernel 6.12 --phase1-only

# Custom output directory
photon-kernel-backport cve-build-workflow -k 6.12 -o /tmp/cve_report

# Build multiple specs
photon-kernel-backport cve-build-workflow -k 6.12 --specs "linux.spec,linux-esx.spec"

# Skip cleanup (for debugging/rerun)
photon-kernel-backport cve-build-workflow --kernel 6.12 --no-cleanup

# Custom repo location and URL
photon-kernel-backport cve-build-workflow --kernel 6.12 --repo-base /tmp/repos --repo-url https://github.com/myorg/photon.git
```

**Report Output:**
- `report.json` - Complete workflow results in JSON format
- `report.md` - Human-readable Markdown summary

**Report Contents:**
- CVE coverage statistics (included, in newer stable, patch available, missing, not applicable)
- Coverage percentage calculation
- Patches downloaded and integrated counts
- Build success/failure with duration and log paths
- RPM output locations

### `status` - Kernel Status

Check current kernel version and patch status.

```bash
photon-kernel-backport status --kernel 6.1
```

### `download` - Download Stable Patches

Download stable patches from kernel.org without integration.

```bash
photon-kernel-backport download --kernel 6.1 --output /var/log/photon-kernel-backport/patches
```

### `build` - Build Kernel RPMs

Build kernel RPMs from local spec files. Automatically installs build dependencies via tdnf.

```bash
# Build with auto-generated output directory (kernelpatches/build/{version}-{release}/)
photon-kernel-backport build --kernel 5.10

# Build with custom output directory
photon-kernel-backport build --kernel 6.1 --output /var/log/photon-kernel-backport/build

# Skip dependency installation
photon-kernel-backport build --kernel 6.1 --skip-deps

# Build all canister/acvp permutations
photon-kernel-backport build --kernel 5.10 --all-permutations
```

### `build-srpm` - Build from Official SRPM

Build kernel RPMs using the official SRPM from packages.broadcom.com. This is the recommended method as it includes all required source files and patches. By default, builds all kernel specs (linux.spec, linux-esx.spec, linux-rt.spec).

```bash
# Build all kernel specs (linux.spec, linux-esx.spec, linux-rt.spec)
photon-kernel-backport build-srpm --kernel 5.10

# Build only linux-esx kernel
photon-kernel-backport build-srpm --kernel 5.10 --specs linux-esx.spec

# Build linux and linux-esx
photon-kernel-backport build-srpm --kernel 5.10 --specs "linux.spec,linux-esx.spec"

# Skip dependency installation
photon-kernel-backport build-srpm --kernel 5.10 --skip-deps
```

**Build Process:**
1. Downloads SRPM from `packages.broadcom.com/artifactory/photon/`
2. Extracts sources using `rpm2cpio`
3. Sets up build environment at `/usr/local/src`
4. Creates symlink `/usr/src/photon` -> `/usr/local/src`
5. Copies local spec files (with CVE patches and updated release) to build directory
6. Installs build dependencies via tdnf
7. Runs `rpmbuild -bb` for each spec file

**Output:** RPMs are placed in `/usr/local/src/RPMS/x86_64/`

**Note:** The local spec files in `{kernel}/SPECS/linux/` are used instead of the SRPM's spec files. This ensures that CVE patches and release number updates are included in the build.

### `install` - Install with Cron Scheduling

Install the kernel backport solution with optional cron job:

```bash
# Install with default settings (cron every 2 hours)
photon-kernel-backport install

# Install with custom schedule (daily at 4 AM)
photon-kernel-backport install --cron "0 4 * * *" --kernels 6.1,6.12

# Install without cron
photon-kernel-backport install --no-cron

# Custom directories (defaults: /opt/photon-kernel-backport and /var/log/photon-kernel-backport)
photon-kernel-backport install --install-dir /opt/photon-kernel-backport --log-dir /var/log/photon-kernel-backport

# Uninstall
photon-kernel-backport install --uninstall
```

## NVD Feed Cache

The solution uses local NVD feed caching for fast offline analysis:

| Feed | Update Frequency | Content |
|------|------------------|---------|
| `recent` | Every run | Last 8 days of CVEs |
| `modified` | Every run | Recently modified CVEs |
| `2023.json.gz` | Once per 24h | All 2023 CVEs |
| `2024.json.gz` | Once per 24h | All 2024 CVEs |
| `2025.json.gz` | Once per 24h | All 2025 CVEs |
| `2026.json.gz` | Once per 24h | All 2026 CVEs |

Cache location: `/var/cache/photon-kernel-backport/nvd_feeds/`

## Supported Kernels

| Kernel | Photon Branch | Spec Directory |
|--------|---------------|----------------|
| 5.10 | 4.0 | SPECS/linux |
| 6.1 | 5.0 | SPECS/linux |
| 6.12 | common | SPECS/linux/v6.12 |

## Output Formats

### JSON Matrix

```json
{
  "generated": "2025-12-31T18:40:30",
  "kernel_versions": ["5.10", "6.1", "6.12"],
  "total_cves": 7494,
  "kernel_coverage": {
    "6.12": {
      "kernel_version": "6.12",
      "photon_version": "6.12.60",
      "latest_stable": "6.12.63",
      "upgrade_available": true,
      "summary": {
        "cve_included": 100,
        "cve_in_newer_stable": 25,
        "cve_patch_available": 5,
        "cve_patch_missing": 7364
      }
    }
  }
}
```

### Markdown Matrix

```markdown
# CVE Coverage Matrix

## Coverage Summary
| Kernel | Photon Version | Latest Stable | CVE Included | In Newer Stable | Spec Patch | Missing | Coverage |
|--------|----------------|---------------|--------------|-----------------|------------|---------|----------|
| 6.12 | 6.12.60 | 6.12.63 ⬆️ | 100 | 25 | 5 | 7364 | 1.3% |

## Upgrade Impact
| Kernel | Current Coverage | After Upgrade | CVEs Fixed by Upgrade |
|--------|------------------|---------------|----------------------|
| 6.12 | 1.3% | 1.7% | 25 |
```

## Python API

```python
from pathlib import Path
from scripts.cve_matrix import CVEMatrixBuilder
from scripts.cve_gap_detection import GapDetector

# Build CVE matrix
builder = CVEMatrixBuilder(kernel_versions=["5.10", "6.1", "6.12"])
matrix = builder.build_from_cves(cves)

# Check upgrade impact
summary = matrix.summary()
for kv in matrix.kernel_versions:
    s = summary[kv]
    print(f"{kv}: {s['photon_version']} -> {s['latest_stable']}")
    if s.get('upgrade_available'):
        print(f"  Upgrade would fix {s['cve_in_newer_stable']} CVEs")

# Run gap detection
detector = GapDetector()
report = detector.run_detection(kernel_version="5.10", current_version="5.10.247")
print(f"Gaps found: {report.summary.cves_with_gaps}")
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_BACKPORT_CACHE_DIR` | `/var/cache/photon-kernel-backport` | Cache directory |
| `KERNEL_BACKPORT_LOG_DIR` | `/var/log/photon-kernel-backport` | Log directory |
| `KERNEL_BACKPORT_REPO_BASE` | Current directory | Base for repo clones |

## Project Structure

```
kernelpatches/
├── scripts/                          # Main Python package
│   ├── __init__.py
│   ├── backport.py                   # Main workflow orchestration
│   ├── build.py                      # RPM build functions
│   ├── cli.py                        # Click CLI (single entry point)
│   ├── common.py                     # Shared utilities
│   ├── config.py                     # Configuration and kernel mappings
│   ├── cve_analysis.py               # CVE redundancy analysis
│   ├── cve_gap_detection.py          # Gap detection with NVD feed cache
│   ├── cve_matrix.py                 # CVE coverage matrix (5 states)
│   ├── cve_sources.py                # NVD/GHSA/Atom CVE fetching
│   ├── generate_full_matrix.py       # Full matrix generation
│   ├── installer.py                  # Installation with cron
│   ├── models.py                     # Pydantic data models
│   ├── spec_file.py                  # RPM spec file manipulation
│   └── stable_patches.py             # Stable patch handling
├── tests/                            # Test suite (135 tests)
│   ├── __init__.py
│   ├── test_common.py
│   ├── test_config.py
│   ├── test_cve_matrix.py
│   ├── test_models.py
│   └── test_spec_file.py
├── 4.0/                              # Photon 4.0 repo (kernel 5.10)
├── 5.0/                              # Photon 5.0 repo (kernel 6.1)
├── common/                           # Photon common repo (kernel 6.12)
├── pyproject.toml                    # Package configuration
├── requirements.txt                  # Dependencies
└── README.md                         # Documentation
```

The `4.0/`, `5.0/`, and `common/` directories are Photon OS repository clones containing spec files.

## Testing

```bash
# Run all tests
pytest tests/ -v

# Run specific test file
pytest tests/test_cve_matrix.py -v

# With coverage
pytest tests/ --cov=scripts
```

## Complete Command Reference

### Global Options

| Option           | Description                    |
|------------------|--------------------------------|
| `--version`      | Show version                   |
| `-v, --verbose`  | Enable verbose output          |
| `-q, --quiet`    | Suppress non-essential output  |

### `backport` - Run kernel patch backporting workflow

| Option            | Type                                   | Default                                      | Description                                      |
|-------------------|----------------------------------------|----------------------------------------------|--------------------------------------------------|
| `-k, --kernel`    | Choice: 5.10, 6.1, 6.12                | **Required**                                 | Kernel version to process                        |
| `-s, --source`    | Choice: cve, stable, stable-full, all  | cve                                          | Patch source type                                |
| `--cve-source`    | Choice: nvd, atom, ghsa, upstream      | nvd                                          | CVE source when using --source cve               |
| `--month`         | String                                 | None                                         | Month to scan (YYYY-MM) for upstream source      |
| `--analyze-cves`  | Flag                                   | False                                        | Analyze CVE redundancy after stable patches      |
| `--cve-since`     | String                                 | None                                         | Filter CVE analysis to CVEs since date (YYYY-MM) |
| `--detect-gaps`   | Flag                                   | False                                        | Detect CVEs without stable backports             |
| `--gap-report`    | Path                                   | None                                         | Directory for gap detection reports              |
| `--resume`        | Flag                                   | False                                        | Resume from checkpoint                           |
| `--report-dir`    | Path                                   | None                                         | Directory for analysis reports                   |
| `--repo-base`     | Path                                   | /root/photonos-scripts/kernelpatches         | Base directory for cloning Photon repos          |
| `--repo-url`      | String                                 | https://github.com/vmware/photon.git         | Photon repository URL                            |
| `--branch`        | String                                 | Auto-detected                                | Git branch to use                                |
| `--skip-clone`    | Flag                                   | False                                        | Skip cloning if repo exists                      |
| `--skip-review`   | Flag                                   | False                                        | Skip CVE review step                             |
| `--skip-push`     | Flag                                   | False                                        | Skip git push and PR creation                    |
| `--disable-build` | Flag                                   | False                                        | Disable RPM build                                |
| `--limit`         | Integer                                | 0                                            | Limit to first N patches                         |
| `--dry-run`       | Flag                                   | False                                        | Show what would be done without changes          |

### `cve-build-workflow` - Two-phase CVE coverage build workflow

| Option          | Type   | Default                              | Description                                            |
|-----------------|--------|--------------------------------------|--------------------------------------------------------|
| `-k, --kernel`  | String | all                                  | Kernel version(s): 5.10, 6.1, 6.12, comma-list, or all |
| `-o, --output`  | Path   | Auto-generated                       | Output directory for reports                           |
| `--repo-base`   | Path   | /root/photonos-scripts/kernelpatches | Base directory for cloning Photon repos                |
| `--repo-url`    | String | https://github.com/vmware/photon.git | Photon repository URL                                  |
| `--no-cleanup`  | Flag   | False                                | Skip cleanup of previous run artifacts                 |
| `--phase1-only` | Flag   | False                                | Only run phase 1 (current kernel)                      |
| `-s, --specs`   | String | linux-esx.spec                       | Comma-separated spec files to build                    |

### `matrix` - Generate comprehensive CVE coverage matrix

| Option           | Type   | Default                                    | Description                                            |
|------------------|--------|--------------------------------------------|--------------------------------------------------------|
| `-k, --kernel`   | String | all                                        | Kernel version(s): 5.10, 6.1, 6.12, comma-list, or all |
| `-o, --output`   | Path   | /var/log/photon-kernel-backport/cve_matrix | Output directory for matrix files                      |
| `--repo-base`    | Path   | /root/photonos-scripts/kernelpatches       | Base directory for cloning Photon repos                |
| `--repo-url`     | String | https://github.com/vmware/photon.git       | Photon repository URL                                  |
| `--skip-clone`   | Flag   | False                                      | Skip cloning repos (use existing or fail)              |
| `--update-repos` | Flag   | False                                      | Force update existing repos                            |

### `gaps` - Detect CVE backport gaps

| Option         | Type                      | Default      | Description                          |
|----------------|---------------------------|--------------|--------------------------------------|
| `-k, --kernel` | Choice: 5.10, 6.1, 6.12   | **Required** | Kernel version to analyze            |
| `--cve-list`   | Path                      | None         | File with CVE IDs (one per line)     |
| `-o, --output` | Path                      | None         | Output directory for reports         |

### `status` - Check kernel status and available updates

| Option         | Type                      | Default      | Description      |
|----------------|---------------------------|--------------|------------------|
| `-k, --kernel` | Choice: 5.10, 6.1, 6.12   | **Required** | Kernel version   |

### `download` - Download stable patches from kernel.org

| Option         | Type                      | Default                      | Description        |
|----------------|---------------------------|------------------------------|--------------------|
| `-k, --kernel` | Choice: 5.10, 6.1, 6.12   | **Required**                 | Kernel version     |
| `-o, --output` | Path                      | /tmp/stable_patches_{kernel} | Output directory   |

### `build` - Build kernel RPMs using official SRPM

| Option              | Type                      | Default        | Description                         |
|---------------------|---------------------------|----------------|-------------------------------------|
| `-k, --kernel`      | Choice: 5.10, 6.1, 6.12   | **Required**   | Kernel version                      |
| `-o, --output`      | Path                      | Auto-generated | Output directory for logs           |
| `-s, --specs`       | String                    | All specs      | Comma-separated spec files to build |
| `--canister`        | Integer                   | 0              | canister_build value (0 or 1)       |
| `--acvp`            | Integer                   | 0              | acvp_build value (0 or 1)           |
| `--all-permutations`| Flag                      | False          | Build all canister/acvp combos      |
| `--skip-deps`       | Flag                      | False          | Skip installing build dependencies  |

### `install` - Install with optional cron scheduling

| Option          | Type   | Default                  | Description                                            |
|-----------------|--------|--------------------------|--------------------------------------------------------|
| `--install-dir` | String | /opt/kernel-backport     | Installation directory                                 |
| `--log-dir`     | String | /var/log/kernel-backport | Log directory                                          |
| `--cron`        | String | 0 */2 * * *              | Cron schedule                                          |
| `-k, --kernel`  | String | all                      | Kernel version(s): 5.10, 6.1, 6.12, comma-list, or all |
| `--no-cron`     | Flag   | False                    | Skip cron job installation                             |
| `--uninstall`   | Flag   | False                    | Remove installation                                    |

### `cve fetch` - Fetch CVEs from specified source

| Option         | Type                               | Default                  | Description      |
|----------------|------------------------------------|--------------------------|------------------|
| `-s, --source` | Choice: nvd, atom, ghsa, upstream  | nvd                      | CVE source       |
| `-k, --kernel` | Choice: 5.10, 6.1, 6.12            | **Required**             | Kernel version   |
| `-o, --output` | Path                               | /tmp/cve_fetch_{kernel}  | Output directory |

## License

See Photon OS licensing terms.
