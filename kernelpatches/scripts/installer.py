"""
Installer for the kernel backport solution.
"""

import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

import click
from rich.console import Console

from scripts import __version__
from scripts.config import SUPPORTED_KERNELS

console = Console()


DEFAULT_INSTALL_DIR = Path("/opt/photon-kernel-backport")
DEFAULT_LOG_DIR = Path("/var/log/photon-kernel-backport")
DEFAULT_CRON_SCHEDULE = "0 */2 * * *"  # Every 2 hours
DEFAULT_KERNELS = ",".join(SUPPORTED_KERNELS)


def create_config_file(
    install_dir: Path,
    log_dir: Path,
    kernels: str,
) -> None:
    """Create configuration file."""
    config_content = f"""# Kernel Backport Configuration
# Generated: {datetime.now().isoformat()}

# Kernel versions to process (comma-separated)
KERNELS="{kernels}"

# Log directory
LOG_DIR="{log_dir}"

# Report directory for CVE analysis
REPORT_DIR="{log_dir}/reports"

# Gap report directory
GAP_REPORT_DIR="{log_dir}/gaps"

# Photon repository URL
REPO_URL="https://github.com/vmware/photon.git"

# Skip options
SKIP_REVIEW=true
SKIP_PUSH=true

# Network timeout (seconds)
NETWORK_TIMEOUT=30

# Retry attempts for network operations
NETWORK_RETRIES=3

# Enable verbose logging
VERBOSE=true
"""
    config_file = install_dir / "config.conf"
    config_file.write_text(config_content)
    console.print(f"  Created: {config_file}")


def create_cron_wrapper(install_dir: Path, log_dir: Path) -> None:
    """Create cron wrapper script."""
    wrapper_content = f'''#!/usr/bin/env python3
"""
Kernel Backport Cron Wrapper
Runs the kernel backport solution on a schedule.
"""

import os
import sys
import fcntl
import time
from datetime import datetime
from pathlib import Path

# Add install dir to path
sys.path.insert(0, str(Path(__file__).parent))

LOCK_FILE = Path("/tmp/kernel-backport.lock")
LOG_DIR = Path("{log_dir}")
CONFIG_FILE = Path("{install_dir}/config.conf")


def load_config():
    """Load configuration from file."""
    config = {{}}
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip().strip('"')
    return config


def check_network():
    """Check network connectivity."""
    import socket
    hosts = ["github.com", "cdn.kernel.org"]
    for host in hosts:
        try:
            socket.create_connection((host, 443), timeout=10)
            return True
        except Exception:
            continue
    return False


def main():
    config = load_config()
    kernels = config.get("KERNELS", "{','.join(SUPPORTED_KERNELS)}").split(",")
    
    # Create log file
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = LOG_DIR / f"backport_{{run_id}}.log"
    summary_log = LOG_DIR / "summary.log"
    
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    
    # Acquire lock
    try:
        lock_fd = open(LOCK_FILE, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_fd.write(str(os.getpid()))
        lock_fd.flush()
    except IOError:
        print(f"Another instance is running. Exiting.")
        with open(summary_log, "a") as f:
            f.write(f"[{{datetime.now()}}] SKIPPED: Another instance running\\n")
        return
    
    try:
        # Check network
        if not check_network():
            print("Network unavailable. Exiting.")
            with open(summary_log, "a") as f:
                f.write(f"[{{datetime.now()}}] SKIPPED: Network unavailable\\n")
            return
        
        # Process each kernel
        from scripts.backport import run_backport_workflow
        from scripts.models import PatchSource, CVESource
        from scripts.config import KernelConfig
        
        success = 0
        failed = 0
        
        for kernel in kernels:
            kernel = kernel.strip()
            print(f"Processing kernel {{kernel}}...")
            
            try:
                config_obj = KernelConfig()
                config_obj.log_dir = LOG_DIR
                
                result = run_backport_workflow(
                    kernel_version=kernel,
                    patch_source=PatchSource.CVE,
                    cve_source=CVESource.NVD,
                    skip_clone=True,
                    skip_review=True,
                    skip_push=True,
                    config=config_obj,
                )
                
                if result:
                    success += 1
                else:
                    failed += 1
                    
            except Exception as e:
                print(f"Error processing {{kernel}}: {{e}}")
                failed += 1
        
        with open(summary_log, "a") as f:
            f.write(f"[{{datetime.now()}}] COMPLETED: Success={{success}} Failed={{failed}} Kernels={{','.join(kernels)}}\\n")
        
        # Cleanup old logs (30 days)
        for old_log in LOG_DIR.glob("*.log"):
            if old_log.stat().st_mtime < time.time() - 30 * 86400:
                old_log.unlink()
                
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()
        LOCK_FILE.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
'''
    
    wrapper_file = install_dir / "kernel-backport-cron.py"
    wrapper_file.write_text(wrapper_content)
    wrapper_file.chmod(0o755)
    console.print(f"  Created: {wrapper_file}")


def create_status_script(install_dir: Path, log_dir: Path) -> None:
    """Create status check script."""
    status_content = f'''#!/usr/bin/env python3
"""Check kernel backport solution status."""

from pathlib import Path
from datetime import datetime

INSTALL_DIR = Path("{install_dir}")
LOG_DIR = Path("{log_dir}")
LOCK_FILE = Path("/tmp/kernel-backport.lock")

print("=== Kernel Backport Tool Status ===")
print()
print(f"Installation: {{INSTALL_DIR}}")
print(f"Log Directory: {{LOG_DIR}}")
print()

# Check cron
import subprocess
try:
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    cron_lines = [l for l in result.stdout.splitlines() if "kernel-backport" in l]
    print("Cron Job:")
    if cron_lines:
        for line in cron_lines:
            print(f"  {{line}}")
    else:
        print("  Not installed")
except Exception:
    print("  Could not check crontab")
print()

# Recent runs
print("Recent Runs (last 5):")
summary_log = LOG_DIR / "summary.log"
if summary_log.exists():
    lines = summary_log.read_text().strip().splitlines()[-5:]
    for line in lines:
        print(f"  {{line}}")
else:
    print("  No runs yet")
print()

# Disk usage
print("Log Disk Usage:")
if LOG_DIR.exists():
    import shutil
    total, used, free = shutil.disk_usage(LOG_DIR)
    log_files = list(LOG_DIR.glob("*.log"))
    print(f"  Directory size: {{sum(f.stat().st_size for f in log_files) // 1024}}KB")
    print(f"  Log files: {{len(log_files)}}")
else:
    print("  Log directory not found")
print()

# Lock status
print("Lock Status:")
if LOCK_FILE.exists():
    try:
        pid = LOCK_FILE.read_text().strip()
        # Check if process is running
        import os
        try:
            os.kill(int(pid), 0)
            print(f"  Running (PID: {{pid}})")
        except ProcessLookupError:
            print(f"  Stale lock file (PID {{pid}} not running)")
    except Exception:
        print("  Unknown")
else:
    print("  Not running")
'''
    
    status_file = install_dir / "status.py"
    status_file.write_text(status_content)
    status_file.chmod(0o755)
    console.print(f"  Created: {status_file}")


def create_run_now_script(install_dir: Path) -> None:
    """Create manual run script."""
    run_content = f'''#!/bin/bash
# Run kernel backport manually

echo "Running kernel backport manually..."
exec python3 "{install_dir}/kernel-backport-cron.py" "$@"
'''
    
    run_file = install_dir / "run-now.sh"
    run_file.write_text(run_content)
    run_file.chmod(0o755)
    console.print(f"  Created: {run_file}")


def install_cron_job(install_dir: Path, schedule: str) -> bool:
    """Install cron job."""
    cron_line = f"{schedule} /usr/bin/python3 {install_dir}/kernel-backport-cron.py"
    
    try:
        # Get current crontab
        result = subprocess.run(
            ["crontab", "-l"],
            capture_output=True,
            text=True,
        )
        current_cron = result.stdout if result.returncode == 0 else ""
        
        # Remove existing kernel-backport entries
        lines = [l for l in current_cron.splitlines() if "kernel-backport" not in l]
        lines.append(cron_line)
        
        # Install new crontab
        new_cron = "\n".join(lines) + "\n"
        process = subprocess.Popen(
            ["crontab", "-"],
            stdin=subprocess.PIPE,
            text=True,
        )
        process.communicate(new_cron)
        
        return process.returncode == 0
    except Exception as e:
        console.print(f"[red]Failed to install cron job: {e}[/red]")
        return False


def uninstall_cron_job() -> bool:
    """Remove cron job."""
    try:
        result = subprocess.run(
            ["crontab", "-l"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return True
        
        lines = [l for l in result.stdout.splitlines() if "kernel-backport" not in l]
        new_cron = "\n".join(lines) + "\n" if lines else ""
        
        if new_cron.strip():
            process = subprocess.Popen(
                ["crontab", "-"],
                stdin=subprocess.PIPE,
                text=True,
            )
            process.communicate(new_cron)
        else:
            subprocess.run(["crontab", "-r"], capture_output=True)
        
        return True
    except Exception:
        return False


@click.command()
@click.option("--install-dir", default=str(DEFAULT_INSTALL_DIR),
              help=f"Installation directory (default: {DEFAULT_INSTALL_DIR})")
@click.option("--log-dir", default=str(DEFAULT_LOG_DIR),
              help=f"Log directory (default: {DEFAULT_LOG_DIR})")
@click.option("--cron", default=DEFAULT_CRON_SCHEDULE,
              help=f"Cron schedule (default: '{DEFAULT_CRON_SCHEDULE}')")
@click.option("--kernels", default=DEFAULT_KERNELS,
              help=f"Comma-separated kernel versions (default: {DEFAULT_KERNELS})")
@click.option("--no-cron", is_flag=True, help="Skip cron job installation")
@click.option("--uninstall", is_flag=True, help="Remove installation")
def main(
    install_dir: str,
    log_dir: str,
    cron: str,
    kernels: str,
    no_cron: bool,
    uninstall: bool,
):
    """
    Install the kernel backport solution.
    
    Sets up the kernel backport tool with optional cron job scheduling.
    """
    install_path = Path(install_dir)
    log_path = Path(log_dir)
    
    # Uninstall
    if uninstall:
        console.print("[bold]Uninstalling kernel backport solution...[/bold]")
        
        # Remove cron job
        if uninstall_cron_job():
            console.print("  Removed cron job")
        
        # Remove installation directory
        if install_path.exists():
            shutil.rmtree(install_path)
            console.print(f"  Removed {install_path}")
        
        console.print("[green]Uninstallation complete.[/green]")
        console.print(f"[yellow]Log directory {log_path} was preserved.[/yellow]")
        return
    
    # Check root
    if os.geteuid() != 0:
        console.print("[yellow]Warning: Not running as root. Some operations may fail.[/yellow]")
    
    console.print("[bold]Installing kernel backport solution...[/bold]")
    console.print(f"  Install directory: {install_path}")
    console.print(f"  Log directory: {log_path}")
    console.print(f"  Kernels: {kernels}")
    if not no_cron:
        console.print(f"  Cron schedule: {cron}")
    console.print()
    
    # Create directories
    console.print("Creating directories...")
    install_path.mkdir(parents=True, exist_ok=True)
    log_path.mkdir(parents=True, exist_ok=True)
    (log_path / "reports").mkdir(exist_ok=True)
    (log_path / "gaps").mkdir(exist_ok=True)
    
    # Copy package files
    console.print("Installing Python package...")
    
    # Find source directory
    source_dir = Path(__file__).parent
    
    # Copy kernelpatches package
    dest_package = install_path / "kernelpatches"
    if dest_package.exists():
        shutil.rmtree(dest_package)
    shutil.copytree(source_dir, dest_package)
    console.print(f"  Copied package to: {dest_package}")
    
    # Create scripts
    console.print("Creating scripts...")
    create_config_file(install_path, log_path, kernels)
    create_cron_wrapper(install_path, log_path)
    create_status_script(install_path, log_path)
    create_run_now_script(install_path)
    
    # Install cron job
    if not no_cron:
        console.print("Installing cron job...")
        if install_cron_job(install_path, cron):
            console.print(f"  Cron job installed: {cron}")
        else:
            console.print("[yellow]  Failed to install cron job[/yellow]")
    
    # Summary
    console.print()
    console.print("[green bold]Installation Complete![/green bold]")
    console.print()
    console.print("Commands:")
    console.print(f"  Check status:  python3 {install_path}/status.py")
    console.print(f"  Run manually:  {install_path}/run-now.sh")
    console.print(f"  View logs:     tail -f {log_path}/summary.log")
    console.print(f"  Uninstall:     kp-install --uninstall")


if __name__ == "__main__":
    main()
