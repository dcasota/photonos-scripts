#!/bin/bash

# =============================================================================
# Kernel Backport Solution Installer
# =============================================================================
# Installs the kernel backport solution with optional cron job scheduling.
#
# Usage:
#   ./install.sh [OPTIONS]
#
# Options:
#   --install-dir DIR    Installation directory (default: /opt/kernel-backport)
#   --log-dir DIR        Log directory (default: /var/log/kernel-backport)
#   --cron SCHEDULE      Cron schedule (default: "0 */2 * * *" = every 2 hours)
#   --kernels LIST       Comma-separated kernel versions (default: 5.10,6.1,6.12)
#   --no-cron            Skip cron job installation
#   --uninstall          Remove installation and cron job
#   --help               Show this help message
# =============================================================================

set -e

# Defaults
INSTALL_DIR="/opt/kernel-backport"
LOG_DIR="/var/log/kernel-backport"
CRON_SCHEDULE="0 */2 * * *"
KERNELS="5.10,6.1,6.12"
INSTALL_CRON=true
UNINSTALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

show_help() {
    head -20 "$0" | tail -16
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        --cron) CRON_SCHEDULE="$2"; shift 2 ;;
        --kernels) KERNELS="$2"; shift 2 ;;
        --no-cron) INSTALL_CRON=false; shift ;;
        --uninstall) UNINSTALL=true; shift ;;
        --help|-h) show_help ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Uninstall
if [ "$UNINSTALL" = true ]; then
    log_info "Uninstalling kernel backport solution..."
    
    # Remove cron job
    if crontab -l 2>/dev/null | grep -q "kernel-backport-cron.sh"; then
        log_info "Removing cron job..."
        crontab -l 2>/dev/null | grep -v "kernel-backport-cron.sh" | crontab - || true
    fi
    
    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removing $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
    fi
    
    log_info "Uninstallation complete."
    log_warn "Log directory $LOG_DIR was preserved. Remove manually if needed."
    exit 0
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_warn "Not running as root. Some operations may fail."
fi

log_info "Installing kernel backport solution..."
log_info "  Install directory: $INSTALL_DIR"
log_info "  Log directory: $LOG_DIR"
log_info "  Kernels: $KERNELS"
if [ "$INSTALL_CRON" = true ]; then
    log_info "  Cron schedule: $CRON_SCHEDULE"
fi

# Create directories
log_info "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$LOG_DIR/reports"

# Copy files
log_info "Copying files..."
mkdir -p "$INSTALL_DIR/lib"
cp "$SCRIPT_DIR/kernel_backport.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/integrate_kernel_patches.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/patch_routing.skills" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/lib/"*.sh "$INSTALL_DIR/lib/"

# Make scripts executable
chmod +x "$INSTALL_DIR/kernel_backport.sh"
chmod +x "$INSTALL_DIR/integrate_kernel_patches.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh

# Create configuration file
log_info "Creating configuration file..."
cat > "$INSTALL_DIR/config.conf" << EOF
# Kernel Backport Configuration
# Generated: $(date -Iseconds)

# Kernel versions to process (comma-separated)
KERNELS="$KERNELS"

# Log directory
LOG_DIR="$LOG_DIR"

# Report directory for CVE analysis
REPORT_DIR="$LOG_DIR/reports"

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
EOF

# Create cron wrapper script
log_info "Creating cron wrapper script..."
cat > "$INSTALL_DIR/kernel-backport-cron.sh" << 'CRONSCRIPT'
#!/bin/bash

# =============================================================================
# Kernel Backport Cron Wrapper
# =============================================================================
# This script is called by cron to run the kernel backport solution.
# It handles network checks, logging, and error recovery.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.conf"
LOCK_FILE="/tmp/kernel-backport.lock"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Set defaults if not in config
LOG_DIR="${LOG_DIR:-/var/log/kernel-backport}"
KERNELS="${KERNELS:-6.1}"
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-30}"
NETWORK_RETRIES="${NETWORK_RETRIES:-3}"
VERBOSE="${VERBOSE:-false}"

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Log file for this run
RUN_ID=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/backport_${RUN_ID}.log"
SUMMARY_LOG="$LOG_DIR/summary.log"

# Logging functions
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [ "$VERBOSE" = true ] && log "DEBUG" "$@"; }

# Summary logging
log_summary() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" >> "$SUMMARY_LOG"
}

# Check for lock file (prevent concurrent runs)
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_warn "Another instance is running (PID: $pid). Exiting."
            log_summary "SKIPPED: Another instance running (PID: $pid)"
            exit 0
        else
            log_warn "Stale lock file found. Removing."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# Network connectivity check
check_network() {
    local hosts=("github.com" "cdn.kernel.org" "api.github.com")
    local attempt=1
    
    while [ $attempt -le $NETWORK_RETRIES ]; do
        log_debug "Network check attempt $attempt/$NETWORK_RETRIES"
        
        for host in "${hosts[@]}"; do
            if timeout "$NETWORK_TIMEOUT" ping -c 1 "$host" >/dev/null 2>&1; then
                log_debug "Network check passed: $host reachable"
                return 0
            fi
            
            # Try curl as fallback
            if timeout "$NETWORK_TIMEOUT" curl -s --head "https://$host" >/dev/null 2>&1; then
                log_debug "Network check passed (curl): $host reachable"
                return 0
            fi
        done
        
        log_warn "Network check failed (attempt $attempt/$NETWORK_RETRIES)"
        attempt=$((attempt + 1))
        [ $attempt -le $NETWORK_RETRIES ] && sleep 10
    done
    
    return 1
}

# Main execution
main() {
    log_info "=========================================="
    log_info "Kernel Backport Cron Job Started"
    log_info "Run ID: $RUN_ID"
    log_info "Kernels: $KERNELS"
    log_info "=========================================="
    
    # Check lock
    check_lock
    
    # Check network connectivity
    log_info "Checking network connectivity..."
    if ! check_network; then
        log_error "Network is not available. Aborting."
        log_summary "FAILED: Network unavailable"
        exit 0  # Exit cleanly to not trigger cron error emails
    fi
    log_info "Network connectivity OK"
    
    # Process each kernel version
    IFS=',' read -ra KERNEL_ARRAY <<< "$KERNELS"
    local success_count=0
    local fail_count=0
    local skip_count=0
    
    for kernel in "${KERNEL_ARRAY[@]}"; do
        kernel=$(echo "$kernel" | xargs)  # Trim whitespace
        log_info "------------------------------------------"
        log_info "Processing kernel: $kernel"
        log_info "------------------------------------------"
        
        CMD="$SCRIPT_DIR/kernel_backport.sh --kernel $kernel --source cve"
        [ "$SKIP_REVIEW" = true ] && CMD="$CMD --skip-review"
        [ "$SKIP_PUSH" = true ] && CMD="$CMD --skip-push"
        CMD="$CMD --skip-clone"
        
        # Run backport script
        KERNEL_LOG="$LOG_DIR/kernel_${kernel}_${RUN_ID}.log"
        log_info "Running: $CMD"
        log_info "Kernel log: $KERNEL_LOG"
        
        if $CMD >> "$KERNEL_LOG" 2>&1; then
            log_info "Kernel $kernel: SUCCESS"
            success_count=$((success_count + 1))
        else
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                log_info "Kernel $kernel: No patches to process"
                skip_count=$((skip_count + 1))
            else
                log_error "Kernel $kernel: FAILED (exit code: $EXIT_CODE)"
                fail_count=$((fail_count + 1))
            fi
        fi
    done
    
    # Summary
    log_info "=========================================="
    log_info "Kernel Backport Cron Job Completed"
    log_info "Success: $success_count, Failed: $fail_count, Skipped: $skip_count"
    log_info "=========================================="
    
    log_summary "COMPLETED: Success=$success_count Failed=$fail_count Skipped=$skip_count Kernels=$KERNELS"
    
    # Cleanup old logs (keep last 30 days)
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
    
    return 0
}

main "$@"
CRONSCRIPT

chmod +x "$INSTALL_DIR/kernel-backport-cron.sh"

# Install cron job
if [ "$INSTALL_CRON" = true ]; then
    log_info "Installing cron job..."
    
    # Remove existing cron job if present
    (crontab -l 2>/dev/null | grep -v "kernel-backport-cron.sh") | crontab - 2>/dev/null || true
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $INSTALL_DIR/kernel-backport-cron.sh") | crontab -
    
    log_info "Cron job installed: $CRON_SCHEDULE"
fi

# Create status check script
log_info "Creating status script..."
cat > "$INSTALL_DIR/status.sh" << 'STATUSSCRIPT'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.conf" 2>/dev/null

LOG_DIR="${LOG_DIR:-/var/log/kernel-backport}"

echo "=== Kernel Backport Solution Status ==="
echo ""
echo "Installation: $SCRIPT_DIR"
echo "Log Directory: $LOG_DIR"
echo ""

# Check cron job
echo "Cron Job:"
if crontab -l 2>/dev/null | grep -q "kernel-backport-cron.sh"; then
    crontab -l 2>/dev/null | grep "kernel-backport-cron.sh" | sed 's/^/  /'
else
    echo "  Not installed"
fi
echo ""

# Show recent runs
echo "Recent Runs (last 5):"
if [ -f "$LOG_DIR/summary.log" ]; then
    tail -5 "$LOG_DIR/summary.log" | sed 's/^/  /'
else
    echo "  No runs yet"
fi
echo ""

# Show disk usage
echo "Log Disk Usage:"
if [ -d "$LOG_DIR" ]; then
    du -sh "$LOG_DIR" 2>/dev/null | sed 's/^/  /'
    echo "  Files: $(find "$LOG_DIR" -name "*.log" 2>/dev/null | wc -l)"
else
    echo "  Log directory not found"
fi
echo ""

# Check lock file
echo "Lock Status:"
if [ -f "/tmp/kernel-backport.lock" ]; then
    pid=$(cat "/tmp/kernel-backport.lock" 2>/dev/null)
    if kill -0 "$pid" 2>/dev/null; then
        echo "  Running (PID: $pid)"
    else
        echo "  Stale lock file (PID: $pid not running)"
    fi
else
    echo "  Not running"
fi
STATUSSCRIPT

chmod +x "$INSTALL_DIR/status.sh"

# Create manual run script
log_info "Creating manual run script..."
cat > "$INSTALL_DIR/run-now.sh" << 'RUNNOWSCRIPT'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running kernel backport manually..."
echo "This will use the same configuration as the cron job."
echo ""

exec "$SCRIPT_DIR/kernel-backport-cron.sh" "$@"
RUNNOWSCRIPT

chmod +x "$INSTALL_DIR/run-now.sh"

# Print summary
echo ""
log_info "=========================================="
log_info "Installation Complete!"
log_info "=========================================="
echo ""
echo "Installed files:"
ls -la "$INSTALL_DIR/"
echo ""
echo "Commands:"
echo "  Check status:  $INSTALL_DIR/status.sh"
echo "  Run manually:  $INSTALL_DIR/run-now.sh"
echo "  View logs:     tail -f $LOG_DIR/summary.log"
echo "  Uninstall:     $SCRIPT_DIR/install.sh --uninstall"
echo ""
if [ "$INSTALL_CRON" = true ]; then
    echo "Cron job installed: $CRON_SCHEDULE"
    echo "Next run: $(date -d "next hour" +"%Y-%m-%d %H:00" 2>/dev/null || echo "Check with 'crontab -l'")"
fi
