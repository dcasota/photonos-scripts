# Kernel Backport Processor Skill

## Description
Autonomously processes kernel patch backports for Photon OS, supporting multiple kernel versions (5.10, 6.1, 6.12) and multiple spec files (linux.spec, linux-esx.spec, linux-rt.spec). Uses skills-based routing to determine which spec files should receive each patch.

## Supported Kernels

| Kernel | Photon Branch | Spec Files | Spec Directory |
|--------|---------------|------------|----------------|
| 5.10   | 4.0           | linux.spec, linux-esx.spec, linux-rt.spec | SPECS/linux |
| 6.1    | 5.0           | linux.spec, linux-esx.spec, linux-rt.spec | SPECS/linux/v6.1 |
| 6.12   | common        | linux.spec, linux-esx.spec | SPECS/linux/v6.12 |

## Files

| File | Description |
|------|-------------|
| `install.sh` | Installer with cron job setup |
| `kernel_backport_unified.sh` | Main backport processor script |
| `integrate_kernel_patches.sh` | Spec2git-based integration script |
| `patch_routing.skills` | Skills file for patch routing rules |
| `kernel-backport-processor.md` | This documentation |

## Installation

### Quick Install
```bash
cd /path/to/photonos-scripts/kernelpatches
./install.sh
```

### Custom Install
```bash
./install.sh --install-dir /opt/kernel-backport \
             --log-dir /var/log/kernel-backport \
             --cron "0 3 * * *" \
             --kernels "6.1,6.12"
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

## Triggers
- When manually invoked with `--kernel <version>` parameter
- When a new report appears in `/tmp/backport_reports_*`

## Inputs
- `--kernel VERSION`: Required. Kernel version (5.10, 6.1, or 6.12)
- `--month YYYY-MM`: Month to scan for patches (default: 2025-07)
- `--repo-url URL`: Photon repo URL
- `--branch NAME`: Override auto-detected branch
- `--skip-clone`: Skip cloning if repo exists
- `--skip-review`: Skip CVE review step
- `--skip-push`: Skip git push and PR creation
- `--enable-build`: Enable RPM build (slow)
- `--limit N`: Limit to first N patches
- `--dry-run`: Show what would be done

## Patch Routing (Skills File)

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
# - "fix" keyword
# - "CVE" keyword
# - "Fixes:" tag
```

### Step 3: Download and Route Patch
```bash
# Download patch from upstream
curl -s -o "$PATCH_FILE" "https://github.com/torvalds/linux/commit/${SHA}.patch"

# Determine routing
TARGETS=$(get_patch_targets "$SHA" "$PATCH_FILE")
# Returns: all, base, esx, rt, base,esx, base,rt, esx,rt, or none

# Expand to spec files
TARGET_SPECS=$(expand_targets_to_specs "$TARGETS" "$AVAILABLE_SPECS")
# Example: "linux.spec linux-esx.spec"
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

### Step 5: Commit Changes
```bash
# Add patch file and all modified specs
git add "$SPEC_SUBDIR/$PATCH_NAME"
for spec in $MODIFIED_SPECS; do
    git add "$SPEC_SUBDIR/$spec"
done

git commit -m "Backport kernel patch ${SHA:0:12}

Backported from upstream commit: $SHA
Patch number: Patch${PATCH_NUM}
Modified specs: linux.spec, linux-esx.spec
Kernel version: 6.1
Auto-generated by kernel-backport-processor skill"
```

### Step 6: Build Kernel RPMs (Optional)
```bash
# Build each modified spec
for spec in $MODIFIED_SPECS; do
    rpmbuild -bb "$SPEC_SUBDIR/$spec" 2>&1 | tee "/tmp/build_${SHA:0:12}_${spec}.log"
done
```

### Step 7: Push and Create PR
```bash
git push -u origin "backport/${SHA:0:12}"

gh pr create \
  --title "Backport: ${SHA:0:12} kernel patch" \
  --body "## Backport Summary

**Upstream Commit**: https://github.com/torvalds/linux/commit/$SHA
**Target Branch**: $BRANCH
**Kernel Version**: $KERNEL_VERSION

### Modified Spec Files
- linux.spec
- linux-esx.spec

### Patch Routing
Routing: all → linux.spec linux-esx.spec

---
*Auto-generated by kernel-backport-processor skill*"
```

## Usage Examples

### Backport patches for kernel 6.1
```bash
./kernel_backport_unified.sh --kernel 6.1 --month 2025-07 --skip-push
```

### Backport patches for kernel 5.10 with build
```bash
./kernel_backport_unified.sh --kernel 5.10 --enable-build --limit 10
```

### Dry run for kernel 6.12
```bash
./kernel_backport_unified.sh --kernel 6.12 --dry-run
```

### Using integrate_kernel_patches.sh
```bash
./integrate_kernel_patches.sh 6.1
./integrate_kernel_patches.sh 5.10 --stop-before-patch Patch512
```

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

## Network Handling

The solution gracefully handles network unavailability:

1. **Pre-flight Check**: Before any operation, connectivity to `github.com`, `api.github.com`, and `cdn.kernel.org` is verified
2. **Retry Logic**: Failed network checks are retried (default: 3 attempts with 5-second delays)
3. **Graceful Exit**: If network is unavailable, scripts exit with code 0 (not error) to avoid cron error emails
4. **Configurable Timeouts**: `NETWORK_TIMEOUT` (default: 30s) and `NETWORK_RETRIES` (default: 3) can be set in config

### Network Configuration
```bash
# In config.conf or environment
NETWORK_TIMEOUT=30    # Seconds per connection attempt
NETWORK_RETRIES=3     # Number of retry attempts
```

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

### Sample Log Output
```
[2025-07-15 02:00:01] [INFO] Kernel Backport Cron Job Started
[2025-07-15 02:00:01] [INFO] Checking network connectivity...
[2025-07-15 02:00:02] [INFO] Network OK: github.com reachable
[2025-07-15 02:00:02] [INFO] Processing kernel: 6.1
[2025-07-15 02:05:30] [INFO] Kernel 6.1: SUCCESS
[2025-07-15 02:05:30] [INFO] Processing kernel: 6.12
[2025-07-15 02:10:15] [INFO] Kernel 6.12: SUCCESS
[2025-07-15 02:10:15] [INFO] COMPLETED: Success=2 Failed=0 Skipped=0
```

## Dependencies
- `git` >= 2.0
- `gh` CLI (authenticated)
- `rpmbuild`
- `rpm`
- `curl`
- `ping` (or curl fallback for network check)
- `timeout` (coreutils)
- `sed`, `grep`, `awk`
- `python3` (for integrate_kernel_patches.sh)
- `cron` (for scheduled execution)
