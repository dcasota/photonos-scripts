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
           # Check kernel status first.
           photon-kernel-backport status --kernel 5.10
      
           # Generate CVE coverage matrix to see current gaps
           photon-kernel-backport matrix --output /var/log/photon-kernel-backport/cve_coverage_matrix --print-table
      ```  
   3. **Deep Analysis Phase** (comprehensive view)
      
      ```bash
           # Generate full matrix with all CVE and stable patch data
           photon-kernel-backport full-matrix --output /var/log/photon-kernel-backport/cve_coverage_matrix --download-patches --repo-base .
      
           # Identify specific CVE gaps requiring attention
           photon-kernel-backport gaps --kernel 5.10 --output /var/log/photon-kernel-backport/gap_reports
      ```
   4. **Patching Phase** (apply fixes)

      ```bash
           # Dry run first to see what will happen
           photon-kernel-backport backport --kernel 5.10 --source all --dry-run
      
           # Apply CVE and stable patches
           photon-kernel-backport backport --kernel 5.10 --source all --detect-gaps
      ```
   5. **Build Phase** (create RPMs)

      ```bash
           # Recommended: Build using official SRPM (includes all sources)
           photon-kernel-backport build-srpm --kernel 5.10
      
           # Or build from local specs if you have all sources
           photon-kernel-backport build --kernel 5.10
      ```
   6. **Automation Phase** (ongoing maintenance)

      ```bash
           # Install with cron for automated backporting (every 2 hours default)
           photon-kernel-backport install --cron "0 4 * * *" --kernels 5.10,6.1,6.12
      ```
   Prerequisites Chain

   Step          │ Prerequisites
   --------------+-------------------------------------------------------
   `status`      │ Photon repo clones (4.0/, 5.0/, common/)
   `matrix`      │ None (uses NVD feed cache)
   `full-matrix` │ `--download-patches` needs network access
   `gaps`        │ NVD feed cache auto-downloaded
   `backport`    │ Photon repo clones with spec files
   `build-srpm`  │ Network access to packages.broadcom.com, tdnf for deps
   `build`       │ Local spec files + all source tarballs
   `install`     │ Root access for cron and /opt directories

   The typical flow is: status -> matrix/gaps (assess) -> backport (patch) -> build-srpm (compile) -> install (automate).
```

## Commands

| Command | Description |
|---------|-------------|
| `matrix` | Generate CVE coverage matrix |
| `full-matrix` | Generate comprehensive matrix with all data |
| `gaps` | Detect CVE backport gaps |
| `backport` | Run kernel patch backporting workflow |
| `status` | Check kernel status and available updates |
| `download` | Download stable patches from kernel.org |
| `build` | Build kernel RPMs from local spec files |
| `build-srpm` | Build kernel RPMs using official SRPM from Broadcom |
| `install` | Install with optional cron scheduling |
| `cve` | CVE-related subcommands |

### `matrix` - CVE Coverage Matrix

Generate a CVE coverage matrix across kernel versions.

```bash
# Generate in all formats (JSON, CSV, Markdown)
photon-kernel-backport matrix --output /var/log/photon-kernel-backport/cve_coverage_matrix

# Generate for specific kernel only
photon-kernel-backport matrix --kernel 5.10 --output /var/log/photon-kernel-backport/cve_coverage_matrix

# Print to console
photon-kernel-backport matrix --print-table --max-rows 100

# CSV format only
photon-kernel-backport matrix --format csv --output /var/log/photon-kernel-backport/cve_coverage_matrix
```

**Five CVE States:**

| State | Icon | Description |
|-------|------|-------------|
| `cve_not_applicable` | ➖ | CVE doesn't affect this kernel version |
| `cve_included` | ✅ | Fix is included in Photon's current stable version |
| `cve_in_newer_stable` | ⬆️ | Fix exists in newer stable patch (upgrade available) |
| `cve_patch_available` | 🔄 | Patch exists in spec file but not in any stable |
| `cve_patch_missing` | ❌ | CVE affects kernel but no patch exists (gap) |

### `full-matrix` - Comprehensive Matrix Generation

Generate a comprehensive matrix with all CVEs and stable patches:

```bash
# Generate full matrix with all data
photon-kernel-backport full-matrix --output /var/log/photon-kernel-backport/cve_coverage_matrix --download-patches --repo-base .

# Quick matrix without downloading patches
photon-kernel-backport full-matrix --output /var/log/photon-kernel-backport/cve_coverage_matrix

# Specific kernels only
photon-kernel-backport full-matrix --kernels 6.1,6.12 --output /var/log/photon-kernel-backport/cve_coverage_matrix
```

This will:
1. Fetch ~7,500 CVEs from NVD (kernel.org CNA)
2. Download stable patches from kernel.org (with `--download-patches`)
3. Read Photon's current kernel versions from spec files
4. Generate matrix showing coverage and upgrade impact

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
```

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

## License

See Photon OS licensing terms.
