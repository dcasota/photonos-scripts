# Kernel Backport Solution for Photon OS

Automated kernel CVE patch backporting tool for Photon OS. Scans upstream Linux kernel commits for CVE fixes and integrates them into Photon OS kernel spec files.

## Features

- Scans upstream `torvalds/linux` for CVE patches
- Supports kernel versions: 5.10 (Photon 4.0), 6.1 (Photon 5.0), 6.12 (development)
- Auto-integrates patches into `linux.spec`, `linux-esx.spec`, `linux-rt.spec`
- Skills-based patch routing for targeted spec files
- Optional CVE review assistance
- Automated cron scheduling support

## Quick Start

```bash
# Scan for CVE patches for kernel 5.10 (Photon OS 4.0)
./kernel_backport_unified.sh --kernel 5.10

# Scan a specific date range
./kernel_backport_unified.sh --kernel 6.1 --start-month 2024-06 --end-month 2024-12

# Dry run to see what would be done
./kernel_backport_unified.sh --kernel 6.12 --dry-run
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

## Usage

### kernel_backport_unified.sh

Main script for scanning and backporting kernel patches.

```
Options:
  --kernel VERSION       Kernel version (5.10, 6.1, 6.12) - REQUIRED
  --start-month YYYY-MM  Start month to scan (default: 2024-01)
  --end-month YYYY-MM    End month to scan (default: current month)
  --repo-url URL         Photon repo URL
  --branch NAME          Branch to use (auto-detected by default)
  --skip-clone           Skip cloning if repo exists
  --skip-review          Skip CVE review step
  --skip-push            Skip git push and PR creation
  --enable-build         Enable RPM build (slow)
  --limit N              Limit to first N patches
  --dry-run              Show what would be done
  --help                 Show help
```

### Kernel Version to Branch Mapping

| Kernel | Photon OS | Branch |
|--------|-----------|--------|
| 5.10   | 4.0       | 4.0    |
| 6.1    | 5.0       | 5.0    |
| 6.12   | dev       | common |

## Patch Routing

The `patch_routing.skills` file controls which spec files receive each patch:

```
# Format: <commit_sha>|<targets>|<description>
abc123|all|Apply to all specs
def456|esx|ESX-specific fix
789xyz|none|Skip this patch
```

Targets:
- `all` - linux.spec, linux-esx.spec, linux-rt.spec
- `base` - linux.spec only
- `esx` - linux-esx.spec only
- `rt` - linux-rt.spec only
- `base,esx` - linux.spec and linux-esx.spec
- `none` - Skip patch

Auto-detection rules apply when not explicitly listed:
- `drivers/gpu/*` → base only
- `arch/x86/kvm/*` → esx only
- `kernel/sched/rt*` → rt only
- CVE fixes → all

## Directory Structure

```
kernelpatches/
├── kernel_backport_unified.sh   # Main backport script
├── install.sh                   # Installer with cron support
├── integrate_kernel_patches.sh  # Patch integration helper
├── patch_routing.skills         # Patch routing configuration
├── 4.0/                         # Photon OS 4.0 specs
├── 5.0/                         # Photon OS 5.0 specs
└── common/                      # Shared/development specs
```

## Output

Execution creates timestamped output in `/tmp/backport_YYYYMMDD_HHMMSS/`:
- `execution.log` - Full execution log
- `patches/` - Downloaded patch files
- `reviews/` - CVE review results
- `*.spec.backup` - Spec file backups

## Requirements

- bash
- curl
- jq
- git
- GitHub API access (for scanning upstream commits)

## License

See Photon OS licensing terms.
