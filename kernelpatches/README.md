# Kernel Backport Processor for Photon OS

Automated kernel CVE patch backporting tool for Photon OS. Scans upstream Linux kernel commits for CVE fixes and integrates them into Photon OS kernel spec files.

## Supported Kernels

| Kernel | Photon Branch | Spec Files | Spec Directory |
|--------|---------------|------------|----------------|
| 5.10   | 4.0           | linux.spec, linux-esx.spec, linux-rt.spec | SPECS/linux |
| 6.1    | 5.0           | linux.spec, linux-esx.spec, linux-rt.spec | SPECS/linux/v6.1 |
| 6.12   | common        | linux.spec, linux-esx.spec | SPECS/linux/v6.12 |

## Quick Start

```bash
# Scan for CVE patches for kernel 5.10 (scans 2024-01 to current month)
./kernel_backport_unified.sh --kernel 5.10

# Scan a specific month only
./kernel_backport_unified.sh --kernel 6.1 --month 2024-07

# Dry run to see what would be done
./kernel_backport_unified.sh --kernel 6.12 --dry-run

# Skip RPM build (enabled by default)
./kernel_backport_unified.sh --kernel 5.10 --disable-build
```

## Installation

```bash
# Install with default settings (cron job at 2 AM daily)
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
| `--cron SCHEDULE` | `0 2 * * *` | Cron schedule (daily 2 AM) |
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

### Command Line Options

```
Options:
  --kernel VERSION     Kernel version (5.10, 6.1, 6.12) - REQUIRED
  --month YYYY-MM      Month to scan (default: all months from 2024-01 to current)
  --repo-url URL       Photon repo URL (default: https://github.com/dcasota/photon.git)
  --branch NAME        Branch to use (auto-detected by default)
  --skip-clone         Skip cloning if repo exists
  --skip-review        Skip CVE review step
  --skip-push          Skip git push and PR creation
  --disable-build      Disable RPM build (enabled by default)
  --limit N            Limit to first N patches (0 = no limit)
  --dry-run            Show what would be done
  --help               Show help
```

### Default Behavior

- **Date range**: Scans from January 2024 to current month
- **Keywords**: CVE only (processes only CVE-related patches)
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

| File | Description |
|------|-------------|
| `kernel_backport_unified.sh` | Main backport processor script |
| `install.sh` | Installer with cron job setup |
| `integrate_kernel_patches.sh` | Spec2git-based integration script |
| `patch_routing.skills` | Skills file for patch routing rules |
| `README.md` | This documentation |

## Logging

All operations are logged to files for debugging and auditing:

| Log File | Description |
|----------|-------------|
| `/var/log/kernel-backport/summary.log` | One-line summary per cron run |
| `/var/log/kernel-backport/backport_YYYYMMDD_HHMMSS.log` | Detailed cron wrapper log |
| `/var/log/kernel-backport/kernel_X.Y_YYYYMMDD_HHMMSS.log` | Per-kernel execution log |
| `/tmp/backport_YYYYMMDD_HHMMSS/execution.log` | Real-time execution details |

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
