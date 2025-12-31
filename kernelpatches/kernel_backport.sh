#!/bin/bash
# =============================================================================
# Unified Kernel Backport Script for Photon OS
# =============================================================================
# Automated kernel patch backporting tool supporting:
#   - CVE patches from NVD, atom feed, or upstream commits
#   - Stable kernel subversion patches from kernel.org
#
# Usage:
#   ./kernel_backport.sh [OPTIONS]
#
# Options:
#   --kernel VERSION     Kernel version to backport (5.10, 6.1, 6.12) - REQUIRED
#   --source TYPE        Patch source: 'cve' (default), 'stable', 'stable-full', or 'all'
#   --cve-source SOURCE  CVE source: 'nvd' (default), 'atom', 'upstream', or 'ghsa'
#   --month YYYY-MM      Month to scan (for upstream CVE source only)
#   --analyze-cves       Analyze which CVE patches are redundant after stable patches
#   --cve-since YYYY-MM  Filter CVE analysis to CVEs since this date
#   --detect-gaps        Detect CVEs without stable backports (require manual porting)
#   --gap-report DIR     Directory for gap detection reports (default: /var/log/kernel-backport/gaps)
#   --resume             Resume from checkpoint (for stable-full workflow)
#   --report-dir DIR     Directory for CVE analysis reports (default: /var/log/kernel-backport/reports)
#   --repo-url URL       Photon repo URL (default: https://github.com/vmware/photon.git)
#   --branch NAME        Branch to use (default: auto-detected based on kernel)
#   --skip-clone         Skip cloning if repo already exists
#   --skip-review        Skip CVE review step
#   --skip-push          Skip git push and PR creation
#   --disable-build      Disable RPM build (enabled by default)
#   --limit N            Limit to first N patches (0 = no limit)
#   --dry-run            Show what would be done without making changes
#   --help               Show this help message
#
# Sources:
#   cve         - CVE patches from NVD/atom/upstream (default)
#   stable      - Stable kernel subversion patches from kernel.org (download only)
#   stable-full - Full spec2git workflow with stable patches, permutations, and testing
#   all         - Both CVE and stable patches
#
# CVE Sources (when --source cve):
#   nvd      - NIST NVD filtered by kernel.org CNA (default)
#              Recent feed every 2 hours + yearly feeds (2024+) once per day
#   atom     - Official linux-cve-announce mailing list Atom feed
#   upstream - Search torvalds/linux commits for "CVE" keyword
#   ghsa     - GitHub Advisory Database (requires gh CLI auth or GITHUB_TOKEN)
#
# Supported Kernels:
#   5.10 - Linux 5.10 LTS (Photon OS 4.0)
#   6.1  - Linux 6.1 LTS (Photon OS 5.0)
#   6.12 - Linux 6.12 (Photon OS development)
# =============================================================================

set -e

# Get script directory and load libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/cve_sources.sh"
source "$SCRIPT_DIR/lib/stable_patches.sh"
source "$SCRIPT_DIR/lib/cve_analysis.sh"
source "$SCRIPT_DIR/lib/cve_gap_detection.sh"
source "$SCRIPT_DIR/lib/build.sh"

# -----------------------------------------------------------------------------
# Configuration Defaults
# -----------------------------------------------------------------------------
KERNEL_VERSION=""
PATCH_SOURCE="cve"  # cve, stable, stable-full, or all
CVE_SOURCE="nvd"    # nvd, atom, or upstream
SCAN_MONTH=""
REPO_URL="https://github.com/vmware/photon.git"
BRANCH=""
BASE_DIR="${BASE_DIR:-/root/photonos-scripts}"
SKILLS_FILE="${SCRIPT_DIR}/patch_routing.skills"
REPORT_DIR="${REPORT_DIR:-/var/log/kernel-backport/reports}"

SKIP_CLONE=false
SKIP_REVIEW=false
SKIP_PUSH=false
ENABLE_BUILD=true
PATCH_LIMIT=0
DRY_RUN=false
ANALYZE_CVES=false
CVE_SINCE=""
RESUME=false
DETECT_GAPS=false
GAP_REPORT_DIR="${GAP_REPORT_DIR:-/var/log/kernel-backport/gaps}"

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --kernel) KERNEL_VERSION="$2"; shift 2 ;;
    --source) PATCH_SOURCE="$2"; shift 2 ;;
    --cve-source) CVE_SOURCE="$2"; shift 2 ;;
    --month) SCAN_MONTH="$2"; shift 2 ;;
    --analyze-cves) ANALYZE_CVES=true; shift ;;
    --cve-since) CVE_SINCE="$2"; shift 2 ;;
    --detect-gaps) DETECT_GAPS=true; shift ;;
    --gap-report) GAP_REPORT_DIR="$2"; shift 2 ;;
    --resume) RESUME=true; shift ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --skip-clone) SKIP_CLONE=true; shift ;;
    --skip-review) SKIP_REVIEW=true; shift ;;
    --skip-push) SKIP_PUSH=true; shift ;;
    --disable-build) ENABLE_BUILD=false; shift ;;
    --limit) PATCH_LIMIT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help)
      head -50 "$0" | tail -45
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
if [ -z "$KERNEL_VERSION" ]; then
  echo "ERROR: --kernel VERSION is required"
  echo "Supported versions: ${SUPPORTED_KERNELS[*]}"
  exit 1
fi

if ! validate_kernel_version "$KERNEL_VERSION"; then
  echo "ERROR: Unsupported kernel version '$KERNEL_VERSION'"
  echo "Supported versions: ${SUPPORTED_KERNELS[*]}"
  exit 1
fi

if [ "$PATCH_SOURCE" != "cve" ] && [ "$PATCH_SOURCE" != "stable" ] && \
   [ "$PATCH_SOURCE" != "stable-full" ] && [ "$PATCH_SOURCE" != "all" ]; then
  echo "ERROR: Invalid --source '$PATCH_SOURCE'"
  echo "Valid options: cve, stable, stable-full, all"
  exit 1
fi

if [ "$CVE_SOURCE" != "nvd" ] && [ "$CVE_SOURCE" != "atom" ] && [ "$CVE_SOURCE" != "upstream" ] && [ "$CVE_SOURCE" != "ghsa" ]; then
  echo "ERROR: Invalid --cve-source '$CVE_SOURCE'"
  echo "Valid options: nvd, atom, upstream, ghsa"
  exit 1
fi

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
[ -z "$BRANCH" ] && BRANCH=$(get_branch_for_kernel "$KERNEL_VERSION")
REPO_DIR="${BASE_DIR}/kernelpatches/${BRANCH}"
SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
AVAILABLE_SPECS=$(get_spec_files_for_kernel "$KERNEL_VERSION")
KERNEL_ORG_URL=$(get_kernel_org_url "$KERNEL_VERSION")
OUTPUT_BASE=$(create_output_dir "backport")
PATCH_LIST="$OUTPUT_BASE/patches.txt"

# Create report directory if needed
mkdir -p "$REPORT_DIR" 2>/dev/null

# Setup logging
setup_logging "kernel" "$KERNEL_VERSION"

# -----------------------------------------------------------------------------
# Display Configuration
# -----------------------------------------------------------------------------
log "=== Unified Kernel Backport Script ==="
log "Kernel version: $KERNEL_VERSION"
log "Patch source: $PATCH_SOURCE"
log "Output directory: $OUTPUT_BASE"

case "$PATCH_SOURCE" in
  cve|all)
    case "$CVE_SOURCE" in
      nvd) log "CVE source: NIST NVD (kernel.org CNA, recent + yearly feeds)" ;;
      atom) log "CVE source: linux-cve-announce Atom feed" ;;
      upstream) log "CVE source: upstream commits (searching for CVE keyword)" ;;
      ghsa) log "CVE source: GitHub Advisory Database (GHSA)" ;;
    esac
    ;;
esac

log "Target branch: $BRANCH"
log "Spec directory: $SPEC_SUBDIR"
log "Available specs: $AVAILABLE_SPECS"
log "Skills file: $SKILLS_FILE"
log "Kernel.org URL: $KERNEL_ORG_URL"
[ "$ANALYZE_CVES" = true ] && log "CVE Analysis: enabled"
[ -n "$CVE_SINCE" ] && log "CVE since: $CVE_SINCE"
[ "$DETECT_GAPS" = true ] && log "Gap detection: enabled"
[ "$DETECT_GAPS" = true ] && log "Gap report directory: $GAP_REPORT_DIR"
[ "$RESUME" = true ] && log "Resume from checkpoint: enabled"
log "Report directory: $REPORT_DIR"
log "Dry run: $DRY_RUN"

# -----------------------------------------------------------------------------
# Network Check
# -----------------------------------------------------------------------------
if ! check_network; then
  log_error "Network is not available. Aborting."
  exit 0
fi

# -----------------------------------------------------------------------------
# Clone Repository
# -----------------------------------------------------------------------------
log ""
log "=== Step 1: Clone Photon Repository ==="

if [ "$SKIP_CLONE" = true ] && [ -d "$REPO_DIR" ]; then
  log "Skipping clone (--skip-clone), using existing $REPO_DIR"
else
  if [ -d "$REPO_DIR" ]; then
    log "Repository already exists at $REPO_DIR"
    log "Updating repository..."
    (cd "$REPO_DIR" && git fetch origin && git reset --hard origin/"$BRANCH") 2>&1 | while read line; do
      log_debug "  $line"
    done
  else
    log "Cloning $REPO_URL (branch: $BRANCH) to $REPO_DIR"
    git clone -b "$BRANCH" "$REPO_URL" "$REPO_DIR" 2>&1 | while read line; do
      log "  $line"
    done
  fi
fi

# Verify spec directory exists
if [ ! -d "$REPO_DIR/$SPEC_SUBDIR" ]; then
  log_error "Spec directory not found: $REPO_DIR/$SPEC_SUBDIR"
  exit 1
fi

# -----------------------------------------------------------------------------
# Check Stable Kernel Status
# -----------------------------------------------------------------------------
log ""
log "=== Step 2: Check Stable Kernel Status ==="

CURRENT_PHOTON_VERSION=$(get_photon_kernel_version "$KERNEL_VERSION" "$REPO_DIR")
STABLE_STATUS=$(check_stable_kernel_status "$KERNEL_VERSION" "$REPO_DIR")
STABLE_UPDATE_NEEDED=false
LATEST_STABLE_VERSION=""

if [[ "$STABLE_STATUS" == UPDATE_NEEDED* ]]; then
  STABLE_UPDATE_NEEDED=true
  LATEST_STABLE_VERSION=$(echo "$STABLE_STATUS" | cut -d'|' -f3)
  VERSIONS_BEHIND=$(get_versions_behind "$CURRENT_PHOTON_VERSION" "$LATEST_STABLE_VERSION")
  
  log "WARNING: Kernel $KERNEL_VERSION is behind stable!"
  log "  Current Photon: $CURRENT_PHOTON_VERSION"
  log "  Latest stable:  $LATEST_STABLE_VERSION"
  log "  Versions behind: $VERSIONS_BEHIND"
  log ""
  log "A stable update will be performed automatically."
elif [[ "$STABLE_STATUS" == UP_TO_DATE* ]]; then
  log "Kernel is up to date: $CURRENT_PHOTON_VERSION"
else
  log_warn "Could not determine stable kernel status"
fi

# -----------------------------------------------------------------------------
# Perform Stable Update if Needed
# -----------------------------------------------------------------------------
STABLE_UPDATE_SUCCESS=false
if [ "$STABLE_UPDATE_NEEDED" = true ]; then
  log ""
  log "=== Step 2a: Perform Stable Kernel Update ==="
  
  if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would update kernel from $CURRENT_PHOTON_VERSION to $LATEST_STABLE_VERSION"
    log "DRY RUN: Would reset Release to 1"
    log "DRY RUN: Would add changelog entry"
  else
    # Integrate the stable update (update Version, reset Release, add changelog)
    if integrate_stable_update "$KERNEL_VERSION" "$REPO_DIR" "$LATEST_STABLE_VERSION" "$AVAILABLE_SPECS"; then
      STABLE_UPDATE_SUCCESS=true
      log "Stable update integrated successfully"
      
      # Analyze CVE patches that may now be redundant
      remove_redundant_cve_patches "$KERNEL_VERSION" "$REPO_DIR" "$LATEST_STABLE_VERSION" "$AVAILABLE_SPECS"
      
      # Update current version for CVE filtering
      CURRENT_PHOTON_VERSION="$LATEST_STABLE_VERSION"
    else
      log_error "Failed to integrate stable update"
      exit 1
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Process CVE Patches
# -----------------------------------------------------------------------------
CVE_TOTAL=0
if [ "$PATCH_SOURCE" = "cve" ] || [ "$PATCH_SOURCE" = "all" ]; then
  log ""
  log "=== Step 3: Find CVE Patches ==="
  
  if [ -n "$CURRENT_PHOTON_VERSION" ]; then
    log "Current Photon kernel: $CURRENT_PHOTON_VERSION"
  fi
  
  CVE_TOTAL=$(find_cve_patches "$CVE_SOURCE" "$KERNEL_VERSION" "$OUTPUT_BASE" "$PATCH_LIST" "$DRY_RUN" "$SCAN_MONTH" "$CURRENT_PHOTON_VERSION")
  
  if [ "$CVE_TOTAL" -gt 0 ]; then
    log "Sample commits:"
    head -5 "$PATCH_LIST" | while read sha; do
      log "  $sha"
    done
    [ "$CVE_TOTAL" -gt 5 ] && log "  ... and $((CVE_TOTAL - 5)) more"
  fi
  
  # Run gap detection if enabled
  if [ "$DETECT_GAPS" = true ] && [ "$CVE_TOTAL" -gt 0 ]; then
    log ""
    log "=== Step 3a: CVE Gap Detection ==="
    log "Analyzing CVEs for missing stable backports..."
    
    # Create CVE list file from cve_info.txt (contains CVE_ID|commit pairs)
    CVE_LIST_FILE="$OUTPUT_BASE/cve_ids.txt"
    if [ -f "$OUTPUT_BASE/cve_info.txt" ]; then
      cut -d'|' -f1 "$OUTPUT_BASE/cve_info.txt" | sort -u > "$CVE_LIST_FILE"
    elif [ -f "$OUTPUT_BASE/cve_info_ghsa.txt" ]; then
      cut -d'|' -f1 "$OUTPUT_BASE/cve_info_ghsa.txt" | sort -u > "$CVE_LIST_FILE"
    else
      # Generate CVE IDs from patch list by querying NVD (slower)
      log "No CVE info file found, will analyze commits individually"
      > "$CVE_LIST_FILE"
    fi
    
    if [ "$DRY_RUN" = true ]; then
      log "DRY RUN: Would run gap detection with:"
      log "  - Kernel: $KERNEL_VERSION"
      log "  - Current version: $CURRENT_PHOTON_VERSION"
      log "  - CVE list: $CVE_LIST_FILE"
      log "  - Gap report dir: $GAP_REPORT_DIR"
    else
      mkdir -p "$GAP_REPORT_DIR"
      
      if [ -s "$CVE_LIST_FILE" ]; then
        GAP_REPORT=$(run_gap_detection "$KERNEL_VERSION" "$CURRENT_PHOTON_VERSION" "$CVE_LIST_FILE" "$OUTPUT_BASE" "$GAP_REPORT_DIR")
        
        if [ -n "$GAP_REPORT" ] && [ -f "$GAP_REPORT" ]; then
          GAPS_FOUND=$(jq -r '.summary.cves_with_gaps' "$GAP_REPORT" 2>/dev/null || echo "0")
          
          if [ "$GAPS_FOUND" -gt 0 ]; then
            log ""
            log "WARNING: $GAPS_FOUND CVE(s) require manual backporting!"
            log "These CVEs affect kernel $KERNEL_VERSION but have no official stable backport."
            log "Gap report: $GAP_REPORT"
            log ""
            log "CVEs requiring manual backport:"
            jq -r '.gaps[] | "  - \(.cve_id) [\(.severity)] - \(.description | .[0:80])..."' "$GAP_REPORT" 2>/dev/null | head -10
          else
            log "No backport gaps detected - all CVEs have available patches"
          fi
        fi
      else
        log "No CVE IDs to analyze for gaps"
      fi
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Process Stable Patches
# -----------------------------------------------------------------------------
STABLE_TOTAL=0
if [ "$PATCH_SOURCE" = "stable" ] || [ "$PATCH_SOURCE" = "stable-full" ] || [ "$PATCH_SOURCE" = "all" ]; then
  log ""
  log "=== Step 3: Find Stable Patches ==="
  
  STABLE_TOTAL=$(find_and_download_stable_patches "$KERNEL_VERSION" "$OUTPUT_BASE" "$DRY_RUN")
fi

# -----------------------------------------------------------------------------
# Full Spec2Git Workflow (stable-full or all with --analyze-cves)
# -----------------------------------------------------------------------------
RUN_STABLE_INTEGRATION=false
if [ "$PATCH_SOURCE" = "stable-full" ]; then
  RUN_STABLE_INTEGRATION=true
elif [ "$PATCH_SOURCE" = "all" ] && [ "$ANALYZE_CVES" = true ] && [ "$STABLE_TOTAL" -gt 0 ]; then
  RUN_STABLE_INTEGRATION=true
  log ""
  log "Note: --analyze-cves with --source all triggers stable patch integration"
fi

if [ "$RUN_STABLE_INTEGRATION" = true ]; then
  log ""
  log "=== Step 3b: Stable Patch Integration Workflow ==="
  
  if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would run stable integration workflow with:"
    log "  - Kernel: $KERNEL_VERSION"
    log "  - Photon repo: $REPO_DIR"
    log "  - Stable patches: $OUTPUT_BASE/stable_patches"
    log "  - Report dir: $REPORT_DIR"
    log "  - Analyze CVEs: $ANALYZE_CVES"
    log "  - CVE since: ${CVE_SINCE:-all}"
    log "  - Resume: $RESUME"
  else
    STABLE_PATCH_DIR="$OUTPUT_BASE/stable_patches"
    
    if [ ! -d "$STABLE_PATCH_DIR" ] || [ "$(ls -1 "$STABLE_PATCH_DIR"/patch-"$KERNEL_VERSION".* 2>/dev/null | grep -v '\.xz$' | wc -l)" -eq 0 ]; then
      log_error "No stable patches found in $STABLE_PATCH_DIR"
      log "Please run with --source stable first to download patches"
      exit 1
    fi
    
    log "Starting stable patch integration workflow..."
    log "Patches: $(ls -1 "$STABLE_PATCH_DIR"/patch-"$KERNEL_VERSION".* 2>/dev/null | grep -v '\.xz$' | wc -l)"
    log "Spec files: $AVAILABLE_SPECS"
    
    if run_spec2git_full_workflow "$KERNEL_VERSION" "$REPO_DIR" "$STABLE_PATCH_DIR" \
         "$REPORT_DIR" "$RESUME" "$ANALYZE_CVES" "$CVE_SINCE"; then
      log "Stable integration workflow completed successfully"
      
      # Show report location if CVE analysis was enabled
      if [ "$ANALYZE_CVES" = true ]; then
        log ""
        log "CVE Analysis Reports:"
        ls -la "$REPORT_DIR"/cve_analysis_${KERNEL_VERSION}_*.json 2>/dev/null | tail -5 | while read line; do
          log "  $line"
        done
        ls -la "$REPORT_DIR"/cve_analysis_${KERNEL_VERSION}_*.txt 2>/dev/null | tail -5 | while read line; do
          log "  $line"
        done
      fi
    else
      log_error "Stable integration workflow failed"
      exit 1
    fi
  fi
  
  # For stable-full only source, exit here; for 'all', continue to CVE processing
  if [ "$PATCH_SOURCE" = "stable-full" ]; then
    log ""
    log "=== ALL DONE ==="
    log "Exit code: 0"
    log "Output directory: $OUTPUT_BASE"
    log "Report directory: $REPORT_DIR"
    log "Log file: $LOG_FILE"
    exit 0
  fi
fi

# -----------------------------------------------------------------------------
# Process and Integrate Patches
# -----------------------------------------------------------------------------
log ""
log "=== Step 4: Process Patches ==="

# Backup spec files
for spec in $AVAILABLE_SPECS; do
  SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
  if [ -f "$SPEC_PATH" ]; then
    cp "$SPEC_PATH" "$OUTPUT_BASE/${spec}.backup"
  fi
done
log "Backed up spec files to $OUTPUT_BASE/"

TOTAL_PATCHES=$((CVE_TOTAL + STABLE_TOTAL))
if [ "$TOTAL_PATCHES" -eq 0 ]; then
  log "No patches found in this scan. Nothing to process."
else
  log "Total patches to process: $TOTAL_PATCHES (CVE: $CVE_TOTAL, Stable: $STABLE_TOTAL)"
  
  # Process CVE patches
  if [ "$CVE_TOTAL" -gt 0 ]; then
    log ""
    log "Processing $CVE_TOTAL CVE patches..."
    
    PROCESSED=0
    SUCCESS=0
    FAILED=0
    SKIPPED=0
    
    # Apply limit if set
    if [ "$PATCH_LIMIT" -gt 0 ] && [ "$CVE_TOTAL" -gt "$PATCH_LIMIT" ]; then
      log "Limiting to first $PATCH_LIMIT patches"
      head -n "$PATCH_LIMIT" "$PATCH_LIST" > "${PATCH_LIST}.limited"
      mv "${PATCH_LIST}.limited" "$PATCH_LIST"
      CVE_TOTAL=$PATCH_LIMIT
    fi
    
    while IFS= read -r SHA; do
      [ -z "$SHA" ] && continue
      PROCESSED=$((PROCESSED + 1))
      
      log "[$PROCESSED/$CVE_TOTAL] SHA: ${SHA:0:12}"
      
      if [ "$DRY_RUN" = true ]; then
        log "  DRY RUN: Would process this patch"
        continue
      fi
      
      # Download patch
      PATCH_FILE="$OUTPUT_BASE/${SHA:0:12}-backport.patch"
      if ! curl -sf --max-time 30 -o "$PATCH_FILE" \
           "https://github.com/torvalds/linux/commit/${SHA}.patch" 2>/dev/null; then
        log "  FAIL: Could not download patch"
        FAILED=$((FAILED + 1))
        continue
      fi
      
      # Determine routing
      TARGETS=$(get_patch_targets "$SHA" "$PATCH_FILE" "$SKILLS_FILE")
      TARGET_SPECS=$(expand_targets_to_specs "$TARGETS" "$AVAILABLE_SPECS")
      
      if [ -z "$TARGET_SPECS" ]; then
        log "  SKIP: Patch routing is 'none'"
        SKIPPED=$((SKIPPED + 1))
        rm -f "$PATCH_FILE"
        continue
      fi
      
      log "  Routing: $TARGETS -> $TARGET_SPECS"
      
      # Check if already integrated
      ALREADY_INTEGRATED=""
      for spec in $TARGET_SPECS; do
        SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
        if [ -f "$SPEC_PATH" ] && grep -q "${SHA:0:12}" "$SPEC_PATH" 2>/dev/null; then
          ALREADY_INTEGRATED="$ALREADY_INTEGRATED $spec"
        fi
      done
      
      if [ -n "$ALREADY_INTEGRATED" ]; then
        log "  SKIP: Already integrated in:$ALREADY_INTEGRATED"
        SKIPPED=$((SKIPPED + 1))
        rm -f "$PATCH_FILE"
        continue
      fi
      
      # Find next patch number
      MAX_PATCH=$CVE_PATCH_MIN
      for spec in $TARGET_SPECS; do
        SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
        if [ -f "$SPEC_PATH" ]; then
          LAST=$(grep -oP 'Patch\K([1-4][0-9]{2})(?=:)' "$SPEC_PATH" 2>/dev/null | sort -n | tail -1)
          if [ -n "$LAST" ] && [ "$LAST" -ge "$MAX_PATCH" ]; then
            MAX_PATCH=$((LAST + 1))
          fi
        fi
      done
      NEXT_PATCH=$MAX_PATCH
      
      if [ "$NEXT_PATCH" -gt "$CVE_PATCH_MAX" ]; then
        log "  ERROR: CVE patch range ($CVE_PATCH_MIN-$CVE_PATCH_MAX) is full"
        FAILED=$((FAILED + 1))
        rm -f "$PATCH_FILE"
        continue
      fi
      
      # Copy patch and add to specs
      PATCH_NAME="${SHA:0:12}-backport.patch"
      cp "$PATCH_FILE" "$REPO_DIR/$SPEC_SUBDIR/$PATCH_NAME"
      
      for spec in $TARGET_SPECS; do
        SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
        if [ -f "$SPEC_PATH" ]; then
          add_patch_to_spec "$SPEC_PATH" "$PATCH_NAME" "$NEXT_PATCH"
          log "    Added Patch${NEXT_PATCH} to $spec"
        fi
      done
      
      SUCCESS=$((SUCCESS + 1))
      rm -f "$PATCH_FILE"
      
    done < "$PATCH_LIST"
    
    log ""
    log "CVE Processing Complete: Success=$SUCCESS, Failed=$FAILED, Skipped=$SKIPPED"
  fi
  
  # Process stable patches
  if [ "$STABLE_TOTAL" -gt 0 ]; then
    log ""
    log "Processing $STABLE_TOTAL stable patches..."
    log "Note: Stable patches require manual integration via spec2git"
    log "Patches downloaded to: $OUTPUT_BASE/stable_patches/"
  fi
fi

# -----------------------------------------------------------------------------
# Count patches in spec
# -----------------------------------------------------------------------------
log ""
log "CVE patches in spec:"
for spec in $AVAILABLE_SPECS; do
  SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
  if [ -f "$SPEC_PATH" ]; then
    COUNT=$(grep -c "^Patch[1-4][0-9][0-9]:" "$SPEC_PATH" 2>/dev/null || echo "0")
    log "  $spec: $COUNT"
  fi
done

# -----------------------------------------------------------------------------
# Build Step
# -----------------------------------------------------------------------------
# Build is triggered if:
# 1. Stable update was performed (STABLE_UPDATE_SUCCESS=true)
# 2. CVE patches were integrated (SUCCESS > 0)
BUILD_NEEDED=false
BUILD_REASON=""

if [ "$STABLE_UPDATE_SUCCESS" = true ]; then
  BUILD_NEEDED=true
  BUILD_REASON="stable update to $LATEST_STABLE_VERSION"
fi

if [ "${SUCCESS:-0}" -gt 0 ]; then
  BUILD_NEEDED=true
  if [ -n "$BUILD_REASON" ]; then
    BUILD_REASON="$BUILD_REASON + $SUCCESS CVE patch(es)"
  else
    BUILD_REASON="$SUCCESS CVE patch(es)"
  fi
fi

if [ "$ENABLE_BUILD" = true ] && [ "$BUILD_NEEDED" = true ]; then
  log ""
  log "=== Step 6: Build RPMs ==="
  log "Build reason: $BUILD_REASON"
  
  if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would build RPMs for: $BUILD_REASON"
    for spec in $AVAILABLE_SPECS; do
      SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
      if [ -f "$SPEC_PATH" ]; then
        VERSION=$(get_spec_version "$SPEC_PATH")
        RELEASE=$(get_spec_release "$SPEC_PATH")
        log "  $spec: Would build $VERSION-$RELEASE"
      fi
    done
  else
    BUILD_FAILED=false
    
    # If only CVE patches (no stable update), we need to increment release and add changelog
    if [ "$STABLE_UPDATE_SUCCESS" != true ] && [ "${SUCCESS:-0}" -gt 0 ]; then
      log "Updating spec files for CVE patches..."
      CHANGELOG_MSG="Backported $SUCCESS CVE patch(es)"
      
      for spec in $AVAILABLE_SPECS; do
        SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
        
        if [ ! -f "$SPEC_PATH" ]; then
          continue
        fi
        
        # Increment release number
        NEW_RELEASE=$(increment_spec_release "$SPEC_PATH")
        if [ -z "$NEW_RELEASE" ]; then
          log_error "Failed to increment release for $spec"
          BUILD_FAILED=true
          continue
        fi
        
        # Add changelog entry
        VERSION=$(get_spec_version "$SPEC_PATH")
        if ! add_changelog_entry "$SPEC_PATH" "$VERSION" "$NEW_RELEASE" "$CHANGELOG_MSG"; then
          log_error "Failed to add changelog entry for $spec"
          BUILD_FAILED=true
          continue
        fi
      done
    fi
    
    # Build all specs
    for spec in $AVAILABLE_SPECS; do
      SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
      
      if [ ! -f "$SPEC_PATH" ]; then
        log_warn "Spec file not found, skipping: $SPEC_PATH"
        continue
      fi
      
      log ""
      log "Building $spec..."
      
      VERSION=$(get_spec_version "$SPEC_PATH")
      RELEASE=$(get_spec_release "$SPEC_PATH")
      log "  Version: $VERSION-$RELEASE"
      
      # Build RPM
      BUILD_LOG="$OUTPUT_BASE/build_${spec%.spec}.log"
      if ! build_kernel_rpm "$SPEC_PATH" "$BUILD_LOG"; then
        log_error "Build failed for $spec - see $BUILD_LOG"
        BUILD_FAILED=true
        continue
      fi
      
      log "  Successfully built $spec"
    done
    
    if [ "$BUILD_FAILED" = true ]; then
      log_error ""
      log_error "One or more builds failed. Skipping push/PR."
      log "Build logs available in: $OUTPUT_BASE/"
      log "Log file: $LOG_FILE"
      exit 1
    fi
    
    log ""
    log "Build step completed successfully"
  fi
elif [ "$ENABLE_BUILD" = true ] && [ "${SUCCESS:-0}" -eq 0 ]; then
  log ""
  log "=== Step 5: Build Step Skipped ==="
  log "No patches were successfully integrated, skipping build."
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
log ""
log "=== ALL DONE ==="
log "Exit code: 0"
log "Output directory: $OUTPUT_BASE"
log "Log file: $LOG_FILE"

exit 0
