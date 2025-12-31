# Kernel Backport Processor for Photon OS

   The kernelpatches system is an automated kernel patch backporting solution for Photon OS. Here's the workflow:

   Architecture

     kernelpatches/
     ├── install.sh           # Installer with cron job setup
     ├── kernel_backport.sh   # Main backport script
     ├── patch_routing.skills # Rules for routing patches to spec files
     ├── lib/
     │   ├── common.sh        # Shared functions (logging, network, routing, SHA512)
     │   ├── build.sh         # Build functions (rpmbuild, version updates)
     │   ├── cve_sources.sh   # CVE detection from NVD/atom/upstream
     │   ├── stable_patches.sh # Stable kernel patch handling
     │   └── cve_analysis.sh  # CVE redundancy analysis
     ├── 4.0/                 # Cloned Photon 4.0 branch (kernel 5.10)
     ├── 5.0/                 # Cloned Photon 5.0 branch (kernel 6.1)
     └── common/              # Photon common branch (kernel 6.12)

   Workflow Steps

   1. Installation: install.sh installs to /opt/kernel-backport, sets up cron (every 2 hours by default), creates config and helper scripts (status.sh, run-now.sh)

   2. Clone/Update Repository: Clones the appropriate Photon branch based on kernel version (5.10→4.0, 6.1→5.0, 6.12→common)

   3. Find Patches: Scans for patches from:
     •  CVE patches: NVD (kernel.org CNA), atom feed, or upstream commits
     •  Stable patches: kernel.org subversion patches (e.g., 6.1.120→6.1.121)

   4. Route Patches: Uses patch_routing.skills or auto-detection to determine which spec files receive each patch:
     •  all → linux.spec, linux-esx.spec, linux-rt.spec
     •  base → linux.spec only
     •  esx → linux-esx.spec only
     •  none → skip patch

   5. Integrate: Adds patches to spec files (Patch100-249 range for CVEs), copies patch files to SPECS/linux directory

   6. Build (optional): Runs rpmbuild for kernel RPMs

   7. Commit/Push/PR: Creates git commit, pushes to branch, opens GitHub PR

## Supported Kernels

| Kernel | Photon Branch | Spec Files | Spec Directory |
|--------|---------------|------------|----------------|
| 5.10   | 4.0           | linux.spec, linux-esx.spec, linux-rt.spec | SPECS/linux |
| 6.1    | 5.0           | linux.spec, linux-esx.spec, linux-rt.spec | SPECS/linux |
| 6.12   | common        | linux.spec, linux-esx.spec | SPECS/linux/v6.12 |

## Quick Start

```bash
# CVE patches (default) - uses NVD kernel.org CNA feed
./kernel_backport.sh --kernel 5.10

# CVE patches with specific source
./kernel_backport.sh --kernel 6.1 --source cve --cve-source atom

# Stable kernel patches from kernel.org (download only)
./kernel_backport.sh --kernel 6.1 --source stable

# Full stable patch workflow with integration
./kernel_backport.sh --kernel 6.1 --source stable-full

# Stable patches with CVE analysis (find redundant CVE patches)
./kernel_backport.sh --kernel 5.10 --source stable-full --analyze-cves --cve-since 2023-01

# Both CVE and stable patches
./kernel_backport.sh --kernel 6.12 --source all

# Dry run to see what would be done
./kernel_backport.sh --kernel 6.12 --dry-run
```

## Installation

```bash
# Install with default settings (cron job every 2 hours)
sudo ./install.sh

# Install without cron job
sudo ./install.sh --no-cron

# Custom installation directory
sudo ./install.sh --install-dir /custom/path

# Uninstall
sudo ./install.sh --uninstall
```

### Install Options

| Option | Default | Description |
|--------|---------|-------------|
| `--install-dir DIR` | `/opt/kernel-backport` | Installation directory |
| `--log-dir DIR` | `/var/log/kernel-backport` | Log directory |
| `--cron SCHEDULE` | `0 */2 * * *` | Cron schedule (every 2 hours) |
| `--kernels LIST` | `5.10,6.1,6.12` | Comma-separated kernel versions |
| `--no-cron` | - | Skip cron job installation |
| `--uninstall` | - | Remove installation |

### Post-Installation Commands

```bash
# Check status
/opt/kernel-backport/status.sh

# Run manually
/opt/kernel-backport/run-now.sh

# View logs
tail -f /var/log/kernel-backport/summary.log

# Uninstall
./install.sh --uninstall
```

## Usage

### Command Line Options (kernel_backport.sh)

```
Options:
  --kernel VERSION     Kernel version (5.10, 6.1, 6.12) - REQUIRED
  --source TYPE        Patch source: cve (default), stable, stable-full, or all
  --cve-source SOURCE  CVE source: nvd (default), atom, or upstream
  --month YYYY-MM      Month to scan (for upstream CVE source only)
  --analyze-cves       Analyze which CVE patches become redundant after stable patches
  --cve-since YYYY-MM  Filter CVE analysis to CVEs since this date
  --resume             Resume from checkpoint (for stable-full workflow)
  --report-dir DIR     Directory for CVE analysis reports (default: /var/log/kernel-backport/reports)
  --repo-url URL       Photon repo URL (default: https://github.com/vmware/photon.git)
  --branch NAME        Branch to use (auto-detected by default)
  --skip-clone         Skip cloning if repo exists
  --skip-review        Skip CVE review step
  --skip-push          Skip git push and PR creation
  --disable-build      Disable RPM build (enabled by default)
  --limit N            Limit to first N patches (0 = no limit)
  --dry-run            Show what would be done
  --help               Show help
```

### Patch Sources

| Source | Description |
|--------|-------------|
| `cve` | CVE patches from NVD/atom/upstream (default) |
| `stable` | Stable kernel subversion patches from kernel.org (download only) |
| `stable-full` | Full workflow: download stable patches and integrate into spec files |
| `all` | Both CVE and stable patches |

### Stable-Full Workflow

The `stable-full` source performs a complete integration workflow:

1. Downloads stable kernel patches from kernel.org
2. Integrates patches into spec files (linux.spec, linux-esx.spec, etc.)
3. Optionally analyzes CVE coverage to identify redundant CVE patches

**Integration Methods:**
- **spec2git** (if available): Advanced tool that converts spec to git, applies patches, and converts back
- **Simple integration** (fallback): Copies patches to spec directory and adds Patch entries to spec files

The script automatically falls back to simple integration if spec2git is not available in the Photon repository.

### CVE Sources (when --source cve)

| Source | Description |
|--------|-------------|
| `nvd` | NIST NVD filtered by kernel.org CNA (default). Recent feed every 2h + yearly feeds (2024+) once per day |
| `atom` | Official linux-cve-announce mailing list Atom feed |
| `upstream` | Search torvalds/linux commits for "CVE" keyword |

### Default Behavior

- **Patch source**: CVE patches
- **CVE source**: NIST NVD (kernel.org CNA)
- **NVD feeds**: Recent feed every run + yearly feeds (2024 to current year) once per 24 hours
- **Build**: RPM build is enabled by default

## Workflow

### Step 1: Clone Repository
```bash
# Auto-selects branch based on kernel version
./kernel_backport_unified.sh --kernel 6.1

# Clones with branch 5.0 for kernel 6.1
git clone -b 5.0 https://github.com/vmware/photon.git ./5.0
```

### Step 2: Find Eligible Patches
```bash
# Scans upstream torvalds/linux for commits matching:
# - "CVE" keyword (default, CVE-only processing)
# Date range: 2024-01 to current month (unless --month specified)
```

### Step 3: Download and Route Patch
```bash
# Download patch from upstream
curl -s -o "$PATCH_FILE" "https://github.com/torvalds/linux/commit/${SHA}.patch"

# Determine routing using patch_routing.skills or auto-detection
TARGETS=$(get_patch_targets "$SHA" "$PATCH_FILE")
# Returns: all, base, esx, rt, base,esx, base,rt, esx,rt, or none
```

### Step 4: Integrate into Spec Files
```bash
# For each target spec file:
for spec in $TARGET_SPECS; do
    # Find next available Patch number in CVE range (100-249)
    # Add Patch entry to spec file
    sed -i "/^Patch${LAST_CVE}:/a Patch${NEXT_PATCH}: ${PATCH_NAME}" "$spec"
done
```

### Step 5: Build Kernel RPMs
```bash
# Build is enabled by default
# Use --disable-build to skip
rpmbuild -bb "$SPEC_SUBDIR/$spec"
```

### Step 6: Commit, Push, and Create PR
```bash
git commit -m "Backport kernel patch ${SHA:0:12}"
git push -u origin "backport/${SHA:0:12}"
gh pr create --title "Backport: ${SHA:0:12} kernel patch" ...
```

## Patch Routing

The `patch_routing.skills` file controls which spec files receive each patch.

### Format
```
<commit_sha_prefix>|<targets>|<description>
```

### Targets
- `all` - Apply to linux.spec, linux-esx.spec, linux-rt.spec (if available)
- `base` - Apply to linux.spec only
- `esx` - Apply to linux-esx.spec only
- `rt` - Apply to linux-rt.spec only
- `base,esx` - Apply to linux.spec and linux-esx.spec
- `base,rt` - Apply to linux.spec and linux-rt.spec
- `esx,rt` - Apply to linux-esx.spec and linux-rt.spec
- `none` - Skip this patch entirely

### Auto-Detection Rules

If a commit SHA is not listed in the skills file, auto-detection is used:
- Patches touching `drivers/gpu/*` → `base` only (not ESX)
- Patches touching `arch/x86/kvm/*` → `base,esx`
- Patches touching `drivers/hyperv/*`, `drivers/vmw/*`, `drivers/xen/*` → `base,esx`
- Patches touching `kernel/sched/*rt*` → `base,rt`
- All other patches → `all`

### Example Skills File
```
abc123def456|all|Fix CVE-2024-1234 affecting all kernel variants
789xyz012abc|esx|ESX-specific virtualization fix
def456ghi789|base,rt|Fix for base and RT kernels, not ESX
skip12345678|none|Patch not applicable to Photon OS
```

## Files

Key Scripts:

   1. `install.sh` - Installer that sets up the solution at `/opt/kernel-backport` with cron scheduling (every 2 hours by default), creates status/run-now helper scripts, and config file

   2. `kernel_backport.sh` - Main orchestration script supporting:
     •  CVE patches from NVD, atom feed, or upstream commits
     •  Stable kernel subversion patches from kernel.org
     •  Automatic kernel version updates with SHA512 hash calculation
     •  RPM build integration

   3. `lib/common.sh` - Core utilities:
     •  Kernel version mappings (5.10→4.0, 6.1→5.0, 6.12→common)
     •  Spec file manipulation (patch numbering, release increment, changelog)
     •  SHA512 hash management for tarballs
     •  Patch routing logic (all/base/esx/rt)
     •  Network checks with retry logic

   4. `lib/build.sh` - RPM build functions:
     •  rpmbuild wrapper with canister/acvp permutations
     •  Kernel version updates with tarball download and SHA512 calculation
     •  Build timeout handling (1 hour default)

   5. `lib/cve_sources.sh` - CVE detection from:
     •  NVD (NIST) with kernel.org CNA filtering
     •  linux-cve-announce Atom feed
     •  Upstream torvalds/linux commit search

   6. `lib/stable_patches.sh` - Stable patch handling:
     •  Downloads incremental patches from kernel.org
     •  spec2git integration workflow (with fallback to simple mode)
     •  Checkpoint/resume capability for long operations

   7. `lib/cve_analysis.sh` - CVE redundancy detection:
     •  Identifies CVE patches made redundant by stable updates
     •  Generates JSON/text reports

## Kernel Version Updates

When a new stable kernel version is released (e.g., 5.10.247 → 5.10.248), the spec files need to be updated with:
- New Version number
- New SHA512 hash for the tarball
- Reset Release to 1
- Changelog entry

### SHA512 Hash Updates

Photon OS spec files use `%define sha512 <name>=<hash>` to verify source tarballs. The `lib/build.sh` library provides functions to automate this:

```bash
# Source the libraries
source lib/common.sh
source lib/build.sh

# Check and update kernel version automatically
check_and_update_kernel_version "5.10" "./4.0" "/tmp/sources" "linux.spec linux-esx.spec linux-rt.spec"

# Or update to a specific version
update_kernel_version "5.10" "5.10.248" "./4.0" "/tmp/sources" "linux.spec linux-esx.spec linux-rt.spec"

# Low-level SHA512 functions (from lib/common.sh)
get_spec_sha512 "4.0/SPECS/linux/linux.spec" "linux"           # Get current hash
update_spec_sha512 "spec.file" "linux" "abc123..."             # Update hash
calculate_file_sha512 "/path/to/linux-5.10.248.tar.xz"         # Calculate hash
```

### Version Update Workflow

1. **Check for updates**: Queries kernel.org for latest stable version
2. **Download tarball**: Downloads new kernel tarball to sources directory
3. **Calculate SHA512**: Computes hash of downloaded tarball
4. **Update spec files**: Updates Version, SHA512, resets Release to 1
5. **Add changelog**: Adds changelog entry with update message

## Logging

All operations are logged to files for debugging and auditing:

| Log File | Description |
|----------|-------------|
| `/var/log/kernel-backport/summary.log` | One-line summary per cron run |
| `/var/log/kernel-backport/backport_YYYYMMDD_HHMMSS.log` | Detailed cron wrapper log |
| `/var/log/kernel-backport/kernel_X.Y_YYYYMMDD_HHMMSS.log` | Per-kernel execution log |
| `/tmp/backport_YYYYMMDD_HHMMSS/execution.log` | Real-time execution details |
| `/var/log/kernel-backport/reports/cve_analysis_*.json` | CVE analysis reports (JSON) |
| `/var/log/kernel-backport/reports/cve_analysis_*.txt` | CVE analysis reports (text) |

### Log Rotation
- Logs older than 30 days are automatically deleted by the cron wrapper
- Manual cleanup: `find /var/log/kernel-backport -name "*.log" -mtime +30 -delete`

## Network Handling

The solution gracefully handles network unavailability:

1. **Pre-flight Check**: Before any operation, connectivity to `github.com`, `api.github.com`, and `cdn.kernel.org` is verified
2. **Retry Logic**: Failed network checks are retried (default: 3 attempts with 5-second delays)
3. **Graceful Exit**: If network is unavailable, scripts exit with code 0 (not error) to avoid cron error emails
4. **Configurable Timeouts**: `NETWORK_TIMEOUT` (default: 30s) and `NETWORK_RETRIES` (default: 3) can be set in config

## Outputs

- `PATCH_FILE`: Generated patch file path
- `BUILD_LOG`: Build log path per spec file
- `TEST_LOG`: Test results log path
- `PR_URL`: Created PR URL (on success)
- `STATUS`: `success` | `already_integrated` | `build_failed` | `test_failed` | `routing_none`

## Error Handling

- If patch already integrated in any target spec: Skip and log
- If patch routing is `none`: Skip patch entirely
- If patch generation fails: Log error, continue to next SHA
- If build fails: Preserve logs, do not push/PR
- If target spec file not found: Log warning, continue with available specs

## Dependencies

- `bash`
- `git` >= 2.0
- `curl`
- `jq`
- `gh` CLI (authenticated, for PR creation)
- `rpmbuild` (for kernel builds)
- `rpm`
- `python3` (for integrate_kernel_patches.sh)
- `cron` (for scheduled execution)

## License

See Photon OS licensing terms.
