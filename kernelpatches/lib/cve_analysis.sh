#!/bin/bash
# =============================================================================
# CVE Analysis Library for Kernel Backport Solution
# =============================================================================
# Functions for analyzing CVE patches, detecting redundancies after stable
# patches, and generating coverage reports.
# Source this file after common.sh
# =============================================================================

[[ -n "${_CVE_ANALYSIS_SH_LOADED:-}" ]] && return 0
_CVE_ANALYSIS_SH_LOADED=1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
REPORT_DIR="${REPORT_DIR:-/var/log/kernel-backport/reports}"
CVE_PATTERN='CVE-[0-9]{4}-[0-9]{4,}'

# -----------------------------------------------------------------------------
# CVE Extraction Functions
# -----------------------------------------------------------------------------

# Extract CVE IDs from a patch file
extract_cves_from_patch() {
  local patch_file="$1"
  
  if [ ! -f "$patch_file" ]; then
    return 1
  fi
  
  grep -oE "$CVE_PATTERN" "$patch_file" 2>/dev/null | sort -u
}

# Extract CVE IDs from a spec file's patch entries
extract_cves_from_spec() {
  local spec_file="$1"
  
  if [ ! -f "$spec_file" ]; then
    return 1
  fi
  
  # Look for CVE references in patch names and comments
  grep -E "(Patch[0-9]+:.*CVE|#.*CVE|Fix CVE)" "$spec_file" 2>/dev/null | \
    grep -oE "$CVE_PATTERN" | sort -u
}

# Get list of CVE patches from spec file with their patch numbers
get_cve_patches_from_spec() {
  local spec_file="$1"
  
  if [ ! -f "$spec_file" ]; then
    return 1
  fi
  
  # Extract Patch lines that reference CVEs
  grep -E "^Patch[0-9]+:.*" "$spec_file" 2>/dev/null | while read -r line; do
    local patch_num=$(echo "$line" | grep -oP '^Patch\K[0-9]+')
    local patch_name=$(echo "$line" | sed 's/^Patch[0-9]*:\s*//')
    local cves=$(echo "$line" | grep -oE "$CVE_PATTERN" || true)
    
    if [ -n "$cves" ]; then
      echo "${patch_num}|${patch_name}|${cves}"
    fi
  done
}

# -----------------------------------------------------------------------------
# CVE Version Analysis
# -----------------------------------------------------------------------------

# Check if a CVE affects a specific kernel version range
# Uses NVD data or kernel.org CVE announcements
is_cve_applicable_to_kernel() {
  local cve_id="$1"
  local kernel_version="$2"
  local cve_data_file="$3"  # Optional: pre-fetched CVE data
  
  # If we have CVE data file, check it
  if [ -n "$cve_data_file" ] && [ -f "$cve_data_file" ]; then
    if grep -q "$cve_id.*$kernel_version" "$cve_data_file" 2>/dev/null; then
      return 0  # CVE applies to this kernel
    fi
  fi
  
  # Default: assume applicable (conservative approach)
  return 0
}

# Check if a CVE was fixed in a specific stable kernel version
is_cve_fixed_in_stable() {
  local cve_id="$1"
  local stable_version="$2"  # e.g., "6.1.120"
  local cve_info_file="$3"   # File with CVE fix information
  
  if [ -n "$cve_info_file" ] && [ -f "$cve_info_file" ]; then
    # Check if CVE is listed as fixed in this or earlier version
    if grep -q "$cve_id.*Fixed.*$stable_version" "$cve_info_file" 2>/dev/null; then
      return 0
    fi
  fi
  
  return 1
}

# -----------------------------------------------------------------------------
# Patch Content Comparison
# -----------------------------------------------------------------------------

# Compare two patches to detect if they address the same issue
# Returns 0 if patches are similar (likely same fix), 1 otherwise
compare_patch_content() {
  local patch1="$1"
  local patch2="$2"
  local threshold="${3:-70}"  # Similarity threshold percentage
  
  if [ ! -f "$patch1" ] || [ ! -f "$patch2" ]; then
    return 1
  fi
  
  # Extract the actual code changes (lines starting with + or -)
  local changes1=$(grep -E '^[+-][^+-]' "$patch1" 2>/dev/null | sort)
  local changes2=$(grep -E '^[+-][^+-]' "$patch2" 2>/dev/null | sort)
  
  if [ -z "$changes1" ] || [ -z "$changes2" ]; then
    return 1
  fi
  
  # Calculate similarity using comm
  local common=$(comm -12 <(echo "$changes1") <(echo "$changes2") | wc -l)
  local total1=$(echo "$changes1" | wc -l)
  local total2=$(echo "$changes2" | wc -l)
  local max_total=$((total1 > total2 ? total1 : total2))
  
  if [ "$max_total" -eq 0 ]; then
    return 1
  fi
  
  local similarity=$((common * 100 / max_total))
  
  if [ "$similarity" -ge "$threshold" ]; then
    return 0  # Patches are similar
  fi
  
  return 1
}

# Check if a stable patch makes a CVE patch redundant
check_cve_patch_redundancy() {
  local stable_patch="$1"
  local cve_patch="$2"
  local spec_dir="$3"
  
  if [ ! -f "$stable_patch" ]; then
    echo "not_found"
    return
  fi
  
  local cve_patch_path="$spec_dir/$cve_patch"
  if [ ! -f "$cve_patch_path" ]; then
    echo "cve_not_found"
    return
  fi
  
  # Check for direct CVE reference in stable patch
  local cve_id=$(echo "$cve_patch" | grep -oE "$CVE_PATTERN" | head -1)
  if [ -n "$cve_id" ] && grep -q "$cve_id" "$stable_patch" 2>/dev/null; then
    echo "direct_match"
    return
  fi
  
  # Check content similarity
  if compare_patch_content "$stable_patch" "$cve_patch_path" 60; then
    echo "content_similar"
    return
  fi
  
  # Check if stable patch touches same files
  local stable_files=$(grep -E '^\+\+\+' "$stable_patch" 2>/dev/null | sed 's/+++ [ab]\///' | sort -u)
  local cve_files=$(grep -E '^\+\+\+' "$cve_patch_path" 2>/dev/null | sed 's/+++ [ab]\///' | sort -u)
  
  local common_files=$(comm -12 <(echo "$stable_files") <(echo "$cve_files") | wc -l)
  if [ "$common_files" -gt 0 ]; then
    echo "same_files"
    return
  fi
  
  echo "no_match"
}

# -----------------------------------------------------------------------------
# CVE Analysis Workflow
# -----------------------------------------------------------------------------

# Analyze all CVE patches against a stable patch
analyze_stable_patch_cve_coverage() {
  local stable_patch="$1"
  local spec_file="$2"
  local spec_dir="$3"
  local output_file="$4"
  
  local stable_name=$(basename "$stable_patch")
  local cves_fixed=""
  local cves_redundant=""
  
  # Get CVEs mentioned in the stable patch itself
  local patch_cves=$(extract_cves_from_patch "$stable_patch")
  if [ -n "$patch_cves" ]; then
    cves_fixed="$patch_cves"
  fi
  
  # Check each CVE patch in the spec
  while IFS='|' read -r patch_num patch_name patch_cves; do
    [ -z "$patch_num" ] && continue
    
    local result=$(check_cve_patch_redundancy "$stable_patch" "$patch_name" "$spec_dir")
    
    case "$result" in
      direct_match|content_similar)
        cves_redundant="$cves_redundant $patch_cves"
        ;;
    esac
  done < <(get_cve_patches_from_spec "$spec_file")
  
  # Output results
  if [ -n "$output_file" ]; then
    echo "${stable_name}|${cves_fixed}|${cves_redundant}" >> "$output_file"
  fi
  
  echo "$cves_redundant"
}

# -----------------------------------------------------------------------------
# Report Generation
# -----------------------------------------------------------------------------

# Initialize a new report
init_cve_report() {
  local kernel_version="$1"
  local report_dir="$2"
  
  mkdir -p "$report_dir"
  
  local report_file="$report_dir/cve_analysis_${kernel_version}_$(date +%Y%m%d_%H%M%S).json"
  
  cat > "$report_file" << EOF
{
  "kernel_version": "$kernel_version",
  "generated": "$(date -Iseconds)",
  "stable_patches": [],
  "summary": {
    "total_stable_patches": 0,
    "total_cves_in_spec": 0,
    "cves_fixed_by_stable": 0,
    "cves_still_needed": 0
  }
}
EOF
  
  echo "$report_file"
}

# Add stable patch entry to report
add_patch_to_report() {
  local report_file="$1"
  local patch_name="$2"
  local applied="$3"
  local cves_fixed="$4"
  local cves_redundant="$5"
  
  # Convert space-separated CVEs to JSON array
  local cves_fixed_json=$(echo "$cves_fixed" | tr ' ' '\n' | grep -E "$CVE_PATTERN" | \
    awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')
  local cves_redundant_json=$(echo "$cves_redundant" | tr ' ' '\n' | grep -E "$CVE_PATTERN" | \
    awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')
  
  [ -z "$cves_fixed_json" ] && cves_fixed_json="[]"
  [ -z "$cves_redundant_json" ] && cves_redundant_json="[]"
  
  # Create patch entry
  local patch_entry=$(cat << EOF
    {
      "patch": "$patch_name",
      "applied": $applied,
      "cves_fixed": $cves_fixed_json,
      "cves_now_redundant": $cves_redundant_json
    }
EOF
)
  
  # Add to report using jq if available, otherwise use sed
  if command -v jq &>/dev/null; then
    local tmp_file=$(mktemp)
    jq ".stable_patches += [$patch_entry]" "$report_file" > "$tmp_file" && mv "$tmp_file" "$report_file"
  else
    # Fallback: simple append before closing bracket
    sed -i 's/\("stable_patches": \[\)/\1'"$(echo "$patch_entry" | tr '\n' ' ')"',/' "$report_file"
  fi
}

# Finalize report with summary
finalize_cve_report() {
  local report_file="$1"
  local total_stable="$2"
  local total_cves_spec="$3"
  local cves_fixed="$4"
  local cves_needed="$5"
  
  if command -v jq &>/dev/null; then
    local tmp_file=$(mktemp)
    jq ".summary.total_stable_patches = $total_stable |
        .summary.total_cves_in_spec = $total_cves_spec |
        .summary.cves_fixed_by_stable = $cves_fixed |
        .summary.cves_still_needed = $cves_needed" "$report_file" > "$tmp_file" && mv "$tmp_file" "$report_file"
  fi
  
  # Also generate text summary
  local text_report="${report_file%.json}.txt"
  cat > "$text_report" << EOF
================================================================================
CVE Analysis Report for Kernel $(jq -r '.kernel_version' "$report_file" 2>/dev/null || echo "N/A")
Generated: $(date)
================================================================================

SUMMARY
-------
Total stable patches analyzed: $total_stable
Total CVE patches in spec:     $total_cves_spec
CVEs fixed by stable patches:  $cves_fixed
CVEs still needed:             $cves_needed

DETAILS
-------
EOF
  
  # Add patch details
  if command -v jq &>/dev/null; then
    jq -r '.stable_patches[] | "Patch: \(.patch)\n  Applied: \(.applied)\n  CVEs Fixed: \(.cves_fixed | join(", "))\n  CVEs Redundant: \(.cves_now_redundant | join(", "))\n"' "$report_file" >> "$text_report" 2>/dev/null
  fi
  
  echo "$text_report"
}

# -----------------------------------------------------------------------------
# CVE Since Date Filtering
# -----------------------------------------------------------------------------

# Filter CVEs by date (YYYY-MM format)
filter_cves_since() {
  local cve_list="$1"
  local since_date="$2"  # Format: YYYY-MM or YYYY
  
  if [ -z "$since_date" ]; then
    echo "$cve_list"
    return
  fi
  
  local since_year=$(echo "$since_date" | cut -d'-' -f1)
  local since_month=$(echo "$since_date" | cut -d'-' -f2)
  [ -z "$since_month" ] && since_month="01"
  
  echo "$cve_list" | while read -r cve; do
    # Extract year from CVE ID (CVE-YYYY-NNNN)
    local cve_year=$(echo "$cve" | grep -oP 'CVE-\K[0-9]{4}')
    if [ -n "$cve_year" ] && [ "$cve_year" -ge "$since_year" ]; then
      echo "$cve"
    fi
  done
}

# Get CVE count since a specific date
count_cves_since() {
  local spec_file="$1"
  local since_date="$2"
  
  local all_cves=$(extract_cves_from_spec "$spec_file")
  local filtered=$(filter_cves_since "$all_cves" "$since_date")
  
  echo "$filtered" | grep -c "$CVE_PATTERN" || echo "0"
}

# -----------------------------------------------------------------------------
# Main Analysis Function
# -----------------------------------------------------------------------------

# Run full CVE analysis for a kernel version
run_cve_analysis() {
  local kernel_version="$1"
  local spec_dir="$2"
  local stable_patch_dir="$3"
  local report_dir="${4:-$REPORT_DIR}"
  local since_date="${5:-}"
  
  log "Starting CVE analysis for kernel $kernel_version" >&2
  
  mkdir -p "$report_dir"
  
  # Get available spec files
  local specs=$(get_spec_files_for_kernel "$kernel_version")
  
  # Initialize report
  local report_file=$(init_cve_report "$kernel_version" "$report_dir")
  log "Report file: $report_file" >&2
  
  local total_stable=0
  local total_cves=0
  local cves_fixed=0
  local all_redundant_cves=""
  
  # Count CVEs in specs
  for spec in $specs; do
    local spec_path="$spec_dir/$spec"
    if [ -f "$spec_path" ]; then
      local spec_cves=$(extract_cves_from_spec "$spec_path" | wc -l)
      total_cves=$((total_cves + spec_cves))
    fi
  done
  
  # Analyze each stable patch
  for patch_file in $(ls "$stable_patch_dir"/patch-"$kernel_version".* 2>/dev/null | grep -v '\.xz$' | sort -V); do
    [ ! -f "$patch_file" ] && continue
    
    total_stable=$((total_stable + 1))
    local patch_name=$(basename "$patch_file")
    
    log "  Analyzing: $patch_name" >&2
    
    # Extract CVEs from this patch
    local patch_cves=$(extract_cves_from_patch "$patch_file")
    
    # Check for redundant CVE patches
    local redundant=""
    for spec in $specs; do
      local spec_path="$spec_dir/$spec"
      [ ! -f "$spec_path" ] && continue
      
      local spec_redundant=$(analyze_stable_patch_cve_coverage "$patch_file" "$spec_path" "$spec_dir" "")
      redundant="$redundant $spec_redundant"
    done
    
    # Filter by date if specified
    if [ -n "$since_date" ]; then
      patch_cves=$(filter_cves_since "$patch_cves" "$since_date")
      redundant=$(filter_cves_since "$redundant" "$since_date")
    fi
    
    # Add to report
    add_patch_to_report "$report_file" "$patch_name" "true" "$patch_cves" "$redundant"
    
    # Track unique redundant CVEs
    all_redundant_cves="$all_redundant_cves $redundant"
  done
  
  # Count unique redundant CVEs
  cves_fixed=$(echo "$all_redundant_cves" | tr ' ' '\n' | grep -E "$CVE_PATTERN" | sort -u | wc -l)
  local cves_needed=$((total_cves - cves_fixed))
  [ "$cves_needed" -lt 0 ] && cves_needed=0
  
  # Finalize report
  local text_report=$(finalize_cve_report "$report_file" "$total_stable" "$total_cves" "$cves_fixed" "$cves_needed")
  
  log "Analysis complete:" >&2
  log "  Total stable patches: $total_stable" >&2
  log "  Total CVEs in specs: $total_cves" >&2
  log "  CVEs fixed by stable: $cves_fixed" >&2
  log "  CVEs still needed: $cves_needed" >&2
  log "  Report: $report_file" >&2
  log "  Text report: $text_report" >&2
  
  echo "$report_file"
}
