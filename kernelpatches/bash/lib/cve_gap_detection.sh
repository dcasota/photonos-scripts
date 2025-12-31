#!/bin/bash
# =============================================================================
# CVE Gap Detection Library for Kernel Backport Solution
# =============================================================================
# Functions for detecting CVEs that affect Photon kernels but have no
# official stable kernel backport available, requiring manual backporting.
#
# Source this file after common.sh and cve_sources.sh
# =============================================================================

[[ -n "${_CVE_GAP_DETECTION_SH_LOADED:-}" ]] && return 0
_CVE_GAP_DETECTION_SH_LOADED=1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
GAP_REPORT_DIR="${GAP_REPORT_DIR:-${LOG_DIR:-/var/log/kernel-backport}/gaps}"

# Stable kernel branch patterns (kernel version -> stable branch suffix)
declare -A STABLE_BRANCHES=(
  ["5.10"]="5.10"
  ["5.15"]="5.15"
  ["6.1"]="6.1"
  ["6.6"]="6.6"
  ["6.11"]="6.11"
  ["6.12"]="6.12"
)

# -----------------------------------------------------------------------------
# NVD CPE Version Range Parsing
# -----------------------------------------------------------------------------

# Fetch CVE details from NVD API (CVE 2.0 format)
# Returns JSON with affected configurations
fetch_nvd_cve_details() {
  local CVE_ID="$1"
  local OUTPUT_FILE="$2"
  
  local NVD_API_URL="https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=${CVE_ID}"
  
  if ! curl -s --max-time 30 -o "$OUTPUT_FILE" "$NVD_API_URL" 2>/dev/null; then
    log_error "Failed to fetch NVD details for $CVE_ID" >&2
    return 1
  fi
  
  # Check for valid response
  if ! jq -e '.vulnerabilities[0]' "$OUTPUT_FILE" >/dev/null 2>&1; then
    log_warn "No vulnerability data found for $CVE_ID" >&2
    return 1
  fi
  
  return 0
}

# Parse NVD CPE configurations to extract affected kernel version ranges
# Returns: "start_version|end_version" pairs, one per line
parse_nvd_affected_versions() {
  local NVD_JSON="$1"
  
  if [ ! -f "$NVD_JSON" ]; then
    return 1
  fi
  
  # Extract version ranges from CPE configurations
  # Handles both versionStartIncluding/versionEndExcluding patterns
  jq -r '
    .vulnerabilities[0].cve.configurations[]?.nodes[]?.cpeMatch[]? |
    select(.criteria | test("linux:linux_kernel")) |
    select(.vulnerable == true) |
    {
      start: (.versionStartIncluding // .versionStartExcluding // "0"),
      end: (.versionEndExcluding // .versionEndIncluding // "999"),
      start_inc: (if .versionStartIncluding then true else false end),
      end_exc: (if .versionEndExcluding then true else false end)
    } |
    "\(.start)|\(.end)|\(.start_inc)|\(.end_exc)"
  ' "$NVD_JSON" 2>/dev/null | sort -u
}

# Check if a specific kernel version falls within an affected range
# Arguments:
#   $1 - version to check (e.g., "6.1.159")
#   $2 - range_start (e.g., "4.2")
#   $3 - range_end (e.g., "6.6.62")
#   $4 - start_inclusive (true/false)
#   $5 - end_exclusive (true/false)
# Returns: 0 if affected, 1 if not
is_version_in_range() {
  local VERSION="$1"
  local RANGE_START="$2"
  local RANGE_END="$3"
  local START_INC="${4:-true}"
  local END_EXC="${5:-true}"
  
  # Normalize versions for comparison
  local v_major=$(echo "$VERSION" | cut -d. -f1)
  local v_minor=$(echo "$VERSION" | cut -d. -f2)
  local v_patch=$(echo "$VERSION" | cut -d. -f3)
  v_patch=${v_patch:-0}
  
  local s_major=$(echo "$RANGE_START" | cut -d. -f1)
  local s_minor=$(echo "$RANGE_START" | cut -d. -f2)
  local s_patch=$(echo "$RANGE_START" | cut -d. -f3)
  s_minor=${s_minor:-0}
  s_patch=${s_patch:-0}
  
  local e_major=$(echo "$RANGE_END" | cut -d. -f1)
  local e_minor=$(echo "$RANGE_END" | cut -d. -f2)
  local e_patch=$(echo "$RANGE_END" | cut -d. -f3)
  e_minor=${e_minor:-999}
  e_patch=${e_patch:-999}
  
  # Convert to comparable integers (major*1000000 + minor*1000 + patch)
  local v_num=$((v_major * 1000000 + v_minor * 1000 + v_patch))
  local s_num=$((s_major * 1000000 + s_minor * 1000 + s_patch))
  local e_num=$((e_major * 1000000 + e_minor * 1000 + e_patch))
  
  # Check start boundary
  if [ "$START_INC" = "true" ]; then
    [ "$v_num" -lt "$s_num" ] && return 1
  else
    [ "$v_num" -le "$s_num" ] && return 1
  fi
  
  # Check end boundary
  if [ "$END_EXC" = "true" ]; then
    [ "$v_num" -ge "$e_num" ] && return 1
  else
    [ "$v_num" -gt "$e_num" ] && return 1
  fi
  
  return 0
}

# -----------------------------------------------------------------------------
# Stable Kernel Backport Detection
# -----------------------------------------------------------------------------

# Extract fix commit branches from NVD references
# Returns: list of stable branches that have fixes (e.g., "6.6 6.11")
get_fix_branches_from_nvd() {
  local NVD_JSON="$1"
  
  if [ ! -f "$NVD_JSON" ]; then
    return 1
  fi
  
  # Parse git.kernel.org/stable/c/ URLs to determine which branches have fixes
  # The commit hash doesn't directly tell us the branch, but we can infer from
  # the multiple references (each stable branch gets its own backport commit)
  jq -r '
    .vulnerabilities[0].cve.references[]? |
    select(.url | test("git.kernel.org/stable/c/[a-f0-9]{40}")) |
    .url
  ' "$NVD_JSON" 2>/dev/null | while read -r url; do
    # Each git.kernel.org/stable/c/ URL is a backport to a specific stable branch
    # We need to check which branch by querying the commit
    local commit=$(echo "$url" | grep -oP '/c/\K[a-f0-9]{40}')
    if [ -n "$commit" ]; then
      echo "$commit"
    fi
  done | sort -u
}

# Query kernel.org to determine which stable branches contain a commit
# This is expensive, so we cache results
check_commit_in_stable_branches() {
  local COMMIT="$1"
  local CACHE_DIR="$2"
  
  local CACHE_FILE="$CACHE_DIR/commit_branches_${COMMIT:0:12}.txt"
  
  # Use cache if available and recent (< 24 hours)
  if [ -f "$CACHE_FILE" ]; then
    local cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ "$cache_age" -lt 86400 ]; then
      cat "$CACHE_FILE"
      return 0
    fi
  fi
  
  # Query kernel.org git web interface to find branches containing commit
  # This checks the stable tree
  local branches=""
  
  # Check each known stable branch
  for branch in "${!STABLE_BRANCHES[@]}"; do
    local branch_name="${STABLE_BRANCHES[$branch]}"
    local check_url="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?h=linux-${branch_name}.y&id=${COMMIT}"
    
    # Quick HEAD request to check if commit exists in branch
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$check_url" 2>/dev/null)
    
    if [ "$status" = "200" ]; then
      branches="$branches $branch"
    fi
    
    sleep 0.5  # Rate limiting
  done
  
  # Cache the result
  mkdir -p "$CACHE_DIR"
  echo "$branches" | xargs > "$CACHE_FILE"
  
  echo "$branches" | xargs
}

# Determine which stable branches have a backport for a CVE
# Arguments:
#   $1 - CVE_ID
#   $2 - NVD_JSON file with CVE details
#   $3 - CACHE_DIR for commit lookups
# Returns: space-separated list of branches with fixes
get_cve_backport_branches() {
  local CVE_ID="$1"
  local NVD_JSON="$2"
  local CACHE_DIR="$3"
  
  local fix_branches=""
  
  # Get fix commits from NVD
  local commits=$(get_fix_branches_from_nvd "$NVD_JSON")
  local commit_count=$(echo "$commits" | wc -w)
  
  if [ "$commit_count" -eq 0 ]; then
    echo ""
    return 0
  fi
  
  # For performance, if there are multiple commits, assume they're backports
  # to different stable branches. Map commit count to likely branches.
  if [ "$commit_count" -ge 3 ]; then
    # Multiple commits usually means mainline + multiple stable backports
    # We'll check a sample commit to verify
    local first_commit=$(echo "$commits" | head -1)
    fix_branches=$(check_commit_in_stable_branches "$first_commit" "$CACHE_DIR")
  else
    # Few commits - check each one
    for commit in $commits; do
      local branches=$(check_commit_in_stable_branches "$commit" "$CACHE_DIR")
      fix_branches="$fix_branches $branches"
    done
  fi
  
  # Deduplicate and return
  echo "$fix_branches" | tr ' ' '\n' | sort -u | xargs
}

# -----------------------------------------------------------------------------
# Gap Detection Core Functions
# -----------------------------------------------------------------------------

# Analyze a single CVE for backport gaps
# Arguments:
#   $1 - CVE_ID
#   $2 - TARGET_KERNEL (e.g., "6.1")
#   $3 - CURRENT_VERSION (e.g., "6.1.159")
#   $4 - OUTPUT_DIR
# Returns: JSON object with gap analysis
analyze_cve_gap() {
  local CVE_ID="$1"
  local TARGET_KERNEL="$2"
  local CURRENT_VERSION="$3"
  local OUTPUT_DIR="$4"
  
  local NVD_FILE="$OUTPUT_DIR/nvd_${CVE_ID}.json"
  local CACHE_DIR="$OUTPUT_DIR/.cache"
  
  mkdir -p "$CACHE_DIR"
  
  # Fetch CVE details
  if ! fetch_nvd_cve_details "$CVE_ID" "$NVD_FILE"; then
    echo '{"cve_id":"'"$CVE_ID"'","status":"fetch_failed"}'
    return 1
  fi
  
  # Parse affected version ranges
  local affected_ranges=$(parse_nvd_affected_versions "$NVD_FILE")
  
  if [ -z "$affected_ranges" ]; then
    echo '{"cve_id":"'"$CVE_ID"'","status":"no_version_info"}'
    rm -f "$NVD_FILE"
    return 0
  fi
  
  # Check if target kernel is affected
  local is_affected=false
  while IFS='|' read -r start end start_inc end_exc; do
    if is_version_in_range "$CURRENT_VERSION" "$start" "$end" "$start_inc" "$end_exc"; then
      is_affected=true
      break
    fi
  done <<< "$affected_ranges"
  
  if [ "$is_affected" = false ]; then
    echo '{"cve_id":"'"$CVE_ID"'","status":"not_affected","target_version":"'"$CURRENT_VERSION"'"}'
    rm -f "$NVD_FILE"
    return 0
  fi
  
  # Get branches with backports
  local fix_branches=$(get_cve_backport_branches "$CVE_ID" "$NVD_FILE" "$CACHE_DIR")
  
  # Check if target kernel branch has a fix
  local has_fix=false
  for branch in $fix_branches; do
    if [ "$branch" = "$TARGET_KERNEL" ]; then
      has_fix=true
      break
    fi
  done
  
  # Extract severity and other metadata
  local severity=$(jq -r '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseSeverity // 
                          .vulnerabilities[0].cve.metrics.cvssMetricV30[0].cvssData.baseSeverity // 
                          "UNKNOWN"' "$NVD_FILE" 2>/dev/null)
  local cvss=$(jq -r '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseScore // 
                      .vulnerabilities[0].cve.metrics.cvssMetricV30[0].cvssData.baseScore // 
                      0' "$NVD_FILE" 2>/dev/null)
  # Extract description and sanitize control characters for JSON output
  local description=$(jq -r '.vulnerabilities[0].cve.descriptions[0].value // ""' "$NVD_FILE" 2>/dev/null | \
                      tr '\n\r\t' '   ' | sed 's/[[:cntrl:]]//g' | head -c 200)
  
  # Build result JSON
  local fix_branches_json=$(echo "$fix_branches" | tr ' ' '\n' | jq -R . | jq -s .)
  local missing_json="[]"
  
  if [ "$has_fix" = false ]; then
    missing_json='["'"$TARGET_KERNEL"'"]'
  fi
  
  cat <<EOF
{
  "cve_id": "$CVE_ID",
  "status": "$([ "$has_fix" = true ] && echo "has_backport" || echo "gap_detected")",
  "severity": "$severity",
  "cvss": $cvss,
  "target_kernel": "$TARGET_KERNEL",
  "current_version": "$CURRENT_VERSION",
  "is_affected": true,
  "fix_branches": $fix_branches_json,
  "missing_backports": $missing_json,
  "requires_manual_backport": $([ "$has_fix" = false ] && echo "true" || echo "false"),
  "description": "$(echo "$description" | sed 's/"/\\"/g')"
}
EOF
  
  rm -f "$NVD_FILE"
}

# -----------------------------------------------------------------------------
# Gap Report Generation
# -----------------------------------------------------------------------------

# Initialize a new gap report
init_gap_report() {
  local KERNEL_VERSION="$1"
  local CURRENT_VERSION="$2"
  local REPORT_DIR="$3"
  
  mkdir -p "$REPORT_DIR"
  
  local REPORT_FILE="$REPORT_DIR/gap_report_${KERNEL_VERSION}_$(date +%Y%m%d_%H%M%S).json"
  
  cat > "$REPORT_FILE" <<EOF
{
  "kernel_version": "$KERNEL_VERSION",
  "photon_version": "$CURRENT_VERSION",
  "generated": "$(date -Iseconds)",
  "gaps": [],
  "patchable": [],
  "not_affected": [],
  "summary": {
    "total_cves_analyzed": 0,
    "cves_with_gaps": 0,
    "cves_patchable": 0,
    "cves_not_affected": 0
  }
}
EOF
  
  echo "$REPORT_FILE"
}

# Add CVE analysis result to report
add_to_gap_report() {
  local REPORT_FILE="$1"
  local CVE_RESULT="$2"
  
  local status=$(echo "$CVE_RESULT" | jq -r '.status')
  local cve_id=$(echo "$CVE_RESULT" | jq -r '.cve_id')
  
  case "$status" in
    gap_detected)
      # Add to gaps array
      local tmp=$(mktemp)
      jq --argjson cve "$CVE_RESULT" '.gaps += [$cve] | .summary.cves_with_gaps += 1 | .summary.total_cves_analyzed += 1' "$REPORT_FILE" > "$tmp" && mv "$tmp" "$REPORT_FILE"
      ;;
    has_backport)
      # Add to patchable array
      local tmp=$(mktemp)
      jq --argjson cve "$CVE_RESULT" '.patchable += [$cve] | .summary.cves_patchable += 1 | .summary.total_cves_analyzed += 1' "$REPORT_FILE" > "$tmp" && mv "$tmp" "$REPORT_FILE"
      ;;
    not_affected)
      # Add to not_affected array
      local tmp=$(mktemp)
      jq --argjson cve "$CVE_RESULT" '.not_affected += [$cve] | .summary.cves_not_affected += 1 | .summary.total_cves_analyzed += 1' "$REPORT_FILE" > "$tmp" && mv "$tmp" "$REPORT_FILE"
      ;;
  esac
}

# Finalize gap report and generate text summary
finalize_gap_report() {
  local REPORT_FILE="$1"
  
  local TEXT_REPORT="${REPORT_FILE%.json}.txt"
  
  local kernel=$(jq -r '.kernel_version' "$REPORT_FILE")
  local photon=$(jq -r '.photon_version' "$REPORT_FILE")
  local total=$(jq -r '.summary.total_cves_analyzed' "$REPORT_FILE")
  local gaps=$(jq -r '.summary.cves_with_gaps' "$REPORT_FILE")
  local patchable=$(jq -r '.summary.cves_patchable' "$REPORT_FILE")
  local not_affected=$(jq -r '.summary.cves_not_affected' "$REPORT_FILE")
  
  cat > "$TEXT_REPORT" <<EOF
================================================================================
CVE Gap Detection Report
Generated: $(date)
================================================================================

TARGET KERNEL
  Kernel series: $kernel
  Photon version: $photon

SUMMARY
  Total CVEs analyzed: $total
  CVEs requiring manual backport (GAPS): $gaps
  CVEs with available backports: $patchable
  CVEs not affecting this kernel: $not_affected

================================================================================
CVEs REQUIRING MANUAL BACKPORT (GAPS)
================================================================================
EOF

  # List gaps with details
  jq -r '.gaps[] | "
CVE: \(.cve_id)
  Severity: \(.severity) (CVSS: \(.cvss))
  Fix branches: \(.fix_branches | join(", "))
  Missing: \(.missing_backports | join(", "))
  Description: \(.description | .[0:150])...
"' "$REPORT_FILE" >> "$TEXT_REPORT" 2>/dev/null

  cat >> "$TEXT_REPORT" <<EOF

================================================================================
CVEs WITH AVAILABLE BACKPORTS (PATCHABLE)
================================================================================
EOF

  jq -r '.patchable[] | "  \(.cve_id) [\(.severity)] - backport in \(.fix_branches | join(", "))"' "$REPORT_FILE" >> "$TEXT_REPORT" 2>/dev/null

  echo "" >> "$TEXT_REPORT"
  echo "Full JSON report: $REPORT_FILE" >> "$TEXT_REPORT"
  
  echo "$TEXT_REPORT"
}

# -----------------------------------------------------------------------------
# Main Gap Detection Function
# -----------------------------------------------------------------------------

# Run gap detection for a list of CVEs
# Arguments:
#   $1 - KERNEL_VERSION (e.g., "6.1")
#   $2 - CURRENT_VERSION (e.g., "6.1.159")
#   $3 - CVE_LIST_FILE (one CVE ID per line)
#   $4 - OUTPUT_DIR
#   $5 - REPORT_DIR
# Returns: Path to generated report
run_gap_detection() {
  local KERNEL_VERSION="$1"
  local CURRENT_VERSION="$2"
  local CVE_LIST_FILE="$3"
  local OUTPUT_DIR="$4"
  local REPORT_DIR="${5:-$GAP_REPORT_DIR}"
  
  log "=== CVE Gap Detection ===" >&2
  log "Target kernel: $KERNEL_VERSION" >&2
  log "Current version: $CURRENT_VERSION" >&2
  
  if [ ! -f "$CVE_LIST_FILE" ] || [ ! -s "$CVE_LIST_FILE" ]; then
    log_warn "No CVEs to analyze" >&2
    echo ""
    return 0
  fi
  
  local cve_count=$(wc -l < "$CVE_LIST_FILE" | tr -d ' ')
  log "CVEs to analyze: $cve_count" >&2
  
  # Initialize report
  local REPORT_FILE=$(init_gap_report "$KERNEL_VERSION" "$CURRENT_VERSION" "$REPORT_DIR")
  log "Report file: $REPORT_FILE" >&2
  
  # Process each CVE
  local processed=0
  local gaps_found=0
  
  while IFS= read -r CVE_ID || [ -n "$CVE_ID" ]; do
    [ -z "$CVE_ID" ] && continue
    
    # Clean CVE ID (remove any extra data after |)
    CVE_ID=$(echo "$CVE_ID" | cut -d'|' -f1)
    
    # Skip if not a valid CVE ID format
    if ! echo "$CVE_ID" | grep -qE '^CVE-[0-9]{4}-[0-9]+$'; then
      continue
    fi
    
    processed=$((processed + 1))
    log "  [$processed/$cve_count] Analyzing $CVE_ID..." >&2
    
    # Analyze CVE
    local result=$(analyze_cve_gap "$CVE_ID" "$KERNEL_VERSION" "$CURRENT_VERSION" "$OUTPUT_DIR")
    
    if [ -n "$result" ]; then
      add_to_gap_report "$REPORT_FILE" "$result"
      
      local status=$(echo "$result" | jq -r '.status' 2>/dev/null)
      if [ "$status" = "gap_detected" ]; then
        gaps_found=$((gaps_found + 1))
        log "    -> GAP DETECTED (no backport for $KERNEL_VERSION)" >&2
      fi
    fi
    
    # Rate limiting for NVD API
    sleep 0.5
    
  done < "$CVE_LIST_FILE"
  
  # Finalize report
  local TEXT_REPORT=$(finalize_gap_report "$REPORT_FILE")
  
  log "" >&2
  log "Gap detection complete:" >&2
  log "  Analyzed: $processed CVEs" >&2
  log "  Gaps found: $gaps_found" >&2
  log "  JSON report: $REPORT_FILE" >&2
  log "  Text report: $TEXT_REPORT" >&2
  
  echo "$REPORT_FILE"
}

# Quick gap check for a single CVE (used during patch processing)
# Returns: "gap" if no backport available, "ok" if backport exists, "na" if not affected
quick_gap_check() {
  local CVE_ID="$1"
  local TARGET_KERNEL="$2"
  local CURRENT_VERSION="$3"
  local CACHE_DIR="${4:-/tmp/cve_cache}"
  
  mkdir -p "$CACHE_DIR"
  
  local result=$(analyze_cve_gap "$CVE_ID" "$TARGET_KERNEL" "$CURRENT_VERSION" "$CACHE_DIR")
  local status=$(echo "$result" | jq -r '.status' 2>/dev/null)
  
  case "$status" in
    gap_detected) echo "gap" ;;
    has_backport) echo "ok" ;;
    not_affected) echo "na" ;;
    *) echo "unknown" ;;
  esac
}
