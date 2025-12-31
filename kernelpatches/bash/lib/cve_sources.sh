#!/bin/bash
# =============================================================================
# CVE Sources Library for Kernel Backport Solution
# =============================================================================
# Functions for fetching CVE patches from NVD, atom feed, and upstream
# Source this file after common.sh
# =============================================================================

[[ -n "${_CVE_SOURCES_SH_LOADED:-}" ]] && return 0
_CVE_SOURCES_SH_LOADED=1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NVD_FEED_BASE="https://nvd.nist.gov/feeds/json/cve/2.0"
NVD_YEARLY_MARKER="${LOG_DIR:-.}/.nvd_yearly_last_run"
CVE_ANNOUNCE_FEED="https://lore.kernel.org/linux-cve-announce/new.atom"
UPSTREAM_REPO="torvalds/linux"

# -----------------------------------------------------------------------------
# NVD Feed Functions
# -----------------------------------------------------------------------------
process_nvd_json() {
  local nvd_json="$1"
  local CVE_INFO_FILE="$2"
  local PATCH_LIST="$3"
  
  # Parse for GitHub torvalds/linux commits
  jq -r --arg cna "$KERNEL_ORG_CNA" '
    .vulnerabilities[]? |
    select(.cve.sourceIdentifier == $cna) |
    {
      cve_id: .cve.id,
      refs: [.cve.references[]? | select(.url | test("github.com/torvalds/linux/commit/[a-f0-9]{40}")) | .url]
    } |
    select(.refs | length > 0) |
    "\(.cve_id)|\(.refs[])"
  ' "$nvd_json" 2>/dev/null | while IFS='|' read -r cve_id ref_url; do
    if [ -n "$ref_url" ]; then
      local commit=$(echo "$ref_url" | grep -oP 'commit/\K[a-f0-9]{40}')
      if [ -n "$commit" ]; then
        echo "$commit" >> "$PATCH_LIST"
        echo "$cve_id|$commit" >> "$CVE_INFO_FILE"
      fi
    fi
  done
  
  # Also parse git.kernel.org commits
  # Matches both formats:
  #   - git.kernel.org/stable/c/[hash]
  #   - git.kernel.org/.../commit/?id=[hash]
  jq -r --arg cna "$KERNEL_ORG_CNA" '
    .vulnerabilities[]? |
    select(.cve.sourceIdentifier == $cna) |
    {
      cve_id: .cve.id,
      refs: [.cve.references[]? | select(.url | test("git.kernel.org.*(commit|/c/).*[a-f0-9]{40}")) | .url]
    } |
    select(.refs | length > 0) |
    "\(.cve_id)|\(.refs[])"
  ' "$nvd_json" 2>/dev/null | while IFS='|' read -r cve_id ref_url; do
    if [ -n "$ref_url" ]; then
      local commit=$(echo "$ref_url" | grep -oP '[a-f0-9]{40}')
      if [ -n "$commit" ]; then
        echo "$commit" >> "$PATCH_LIST"
        echo "$cve_id|$commit" >> "$CVE_INFO_FILE"
      fi
    fi
  done
}

fetch_and_process_nvd_feed() {
  local feed_url="$1"
  local CVE_INFO_FILE="$2"
  local PATCH_LIST="$3"
  local feed_name="$4"
  local OUTPUT_DIR="$5"
  
  local nvd_gz="$OUTPUT_DIR/nvd_${feed_name}.json.gz"
  local nvd_json="$OUTPUT_DIR/nvd_${feed_name}.json"
  
  log "  Fetching $feed_name feed..." >&2
  if ! curl -s --max-time 180 -o "$nvd_gz" "$feed_url"; then
    log_warn "Failed to fetch $feed_name feed"
    return 1
  fi
  
  if [ ! -s "$nvd_gz" ]; then
    log_warn "$feed_name feed is empty"
    return 1
  fi
  
  if ! gunzip -f "$nvd_gz" 2>/dev/null; then
    log_warn "Failed to decompress $feed_name feed"
    return 1
  fi
  
  if [ ! -s "$nvd_json" ]; then
    log_warn "$feed_name JSON is empty"
    rm -f "$nvd_json"
    return 1
  fi
  
  process_nvd_json "$nvd_json" "$CVE_INFO_FILE" "$PATCH_LIST"
  rm -f "$nvd_json"
  return 0
}

should_run_yearly_feed() {
  if [ ! -f "$NVD_YEARLY_MARKER" ]; then
    return 0
  fi
  
  local last_run=$(cat "$NVD_YEARLY_MARKER" 2>/dev/null)
  local now=$(date +%s)
  local age=$((now - last_run))
  local hours=$((age / 3600))
  
  if [ $age -ge 86400 ]; then
    return 0
  else
    log "  Yearly feeds last run ${hours}h ago (next run in $((24 - hours))h)" >&2
    return 1
  fi
}

update_yearly_marker() {
  mkdir -p "$(dirname "$NVD_YEARLY_MARKER")"
  date +%s > "$NVD_YEARLY_MARKER"
}

find_patches_nvd() {
  local KERNEL_VERSION="$1"
  local OUTPUT_DIR="$2"
  local PATCH_LIST="$3"
  local DRY_RUN="${4:-false}"
  
  log "Source: NIST National Vulnerability Database (NVD)" >&2
  log "Filter: kernel.org CNA (sourceIdentifier: $KERNEL_ORG_CNA)" >&2
  log "Target kernel: $KERNEL_VERSION" >&2
  
  local CVE_INFO_FILE="$OUTPUT_DIR/cve_info.txt"
  > "$CVE_INFO_FILE"
  > "$PATCH_LIST"
  
  if [ "$DRY_RUN" = true ]; then
    log "Dry run - skipping actual feed fetch" >&2
    echo "0"
    return 0
  fi
  
  log "Fetching NVD CVE feeds..." >&2
  
  # Always process recent feed
  log "Processing recent feed..." >&2
  local feed_url="${NVD_FEED_BASE}/nvdcve-2.0-recent.json.gz"
  fetch_and_process_nvd_feed "$feed_url" "$CVE_INFO_FILE" "$PATCH_LIST" "recent" "$OUTPUT_DIR"
  
  # Additionally process yearly feeds once per 24 hours
  log "Checking yearly feeds (2023+)..." >&2
  if should_run_yearly_feed; then
    local current_year=$(date +%Y)
    local start_year=2023
    
    log "Processing yearly feeds from $start_year to $current_year..." >&2
    
    for year in $(seq $start_year $current_year); do
      local feed_url="${NVD_FEED_BASE}/nvdcve-2.0-${year}.json.gz"
      fetch_and_process_nvd_feed "$feed_url" "$CVE_INFO_FILE" "$PATCH_LIST" "$year" "$OUTPUT_DIR"
    done
    
    update_yearly_marker
    log "Yearly feeds processing complete, next run in 24h" >&2
  fi
  
  # Remove duplicates
  if [ -f "$PATCH_LIST" ] && [ -s "$PATCH_LIST" ]; then
    sort -u "$PATCH_LIST" -o "$PATCH_LIST"
  fi
  
  local total=$(wc -l < "$PATCH_LIST" 2>/dev/null | tr -d ' ' || echo "0")
  log "Found $total kernel.org CVE commits from NVD" >&2
  
  [ "$total" -gt 0 ] && log "CVE info saved to: $CVE_INFO_FILE" >&2
  
  echo "$total"
}

# -----------------------------------------------------------------------------
# Atom Feed Functions (linux-cve-announce)
# -----------------------------------------------------------------------------
find_patches_atom() {
  local KERNEL_VERSION="$1"
  local OUTPUT_DIR="$2"
  local PATCH_LIST="$3"
  local DRY_RUN="${4:-false}"
  local CURRENT_VERSION="${5:-}"
  
  log "Source: linux-cve-announce mailing list (kernel.org official CVE feed)" >&2
  log "Target kernel: $KERNEL_VERSION" >&2
  if [ -n "$CURRENT_VERSION" ]; then
    log "Current Photon version: $CURRENT_VERSION (will skip fixes already in tarball)" >&2
  fi
  
  local CVE_INFO_FILE="$OUTPUT_DIR/cve_info.txt"
  > "$CVE_INFO_FILE"
  > "$PATCH_LIST"
  
  local kernel_pattern=$(get_kernel_stable_pattern "$KERNEL_VERSION")
  log "Looking for fixes in kernel ${kernel_pattern}*" >&2
  
  if [ "$DRY_RUN" = true ]; then
    log "Dry run - skipping actual feed fetch" >&2
    echo "0"
    return 0
  fi
  
  log "Fetching CVE announcements from $CVE_ANNOUNCE_FEED" >&2
  local feed_file="$OUTPUT_DIR/cve_feed.xml"
  
  if ! curl -s --max-time 60 -o "$feed_file" "$CVE_ANNOUNCE_FEED"; then
    log_error "Failed to fetch CVE announce feed"
    echo "0"
    return 1
  fi
  
  if [ ! -s "$feed_file" ]; then
    log_error "CVE feed is empty"
    echo "0"
    return 1
  fi
  
  log "Parsing CVE entries for kernel $KERNEL_VERSION fixes..." >&2
  
  local fixes=$(grep -oP "Fixed in ${kernel_pattern}[0-9]+ with commit [a-f0-9]{40}" "$feed_file" 2>/dev/null || true)
  
  if [ -z "$fixes" ]; then
    fixes=$(grep -oP "Fixed in ${KERNEL_VERSION}\.[0-9]+ with commit [a-f0-9]{40}" "$feed_file" 2>/dev/null || true)
  fi
  
  local skipped=0
  if [ -n "$fixes" ]; then
    while IFS= read -r fix_line; do
      if [ -n "$fix_line" ]; then
        local fix_version=$(echo "$fix_line" | grep -oP "Fixed in \K${kernel_pattern}[0-9]+")
        local commit=$(echo "$fix_line" | grep -oP 'commit \K[a-f0-9]{40}')
        
        if [ -n "$commit" ]; then
          # Skip if fix version <= current Photon version (already in tarball)
          if [ -n "$CURRENT_VERSION" ] && [ -n "$fix_version" ]; then
            if ! version_less_than "$CURRENT_VERSION" "$fix_version"; then
              log "  Skipping $commit (fixed in $fix_version, already in $CURRENT_VERSION)" >&2
              skipped=$((skipped + 1))
              continue
            fi
          fi
          
          echo "$commit" >> "$PATCH_LIST"
          echo "$fix_version|$commit" >> "$CVE_INFO_FILE"
        fi
      fi
    done <<< "$fixes"
  fi
  
  # Remove duplicates
  if [ -f "$PATCH_LIST" ] && [ -s "$PATCH_LIST" ]; then
    sort -u "$PATCH_LIST" -o "$PATCH_LIST"
  fi
  
  local total=$(wc -l < "$PATCH_LIST" 2>/dev/null | tr -d ' ' || echo "0")
  log "Found $total CVE fix commits for kernel $KERNEL_VERSION (skipped $skipped already in tarball)" >&2
  
  [ "$total" -gt 0 ] && log "CVE info saved to: $CVE_INFO_FILE" >&2
  
  echo "$total"
}

# -----------------------------------------------------------------------------
# Upstream Search Functions
# -----------------------------------------------------------------------------
find_patches_upstream() {
  local KERNEL_VERSION="$1"
  local OUTPUT_DIR="$2"
  local PATCH_LIST="$3"
  local DRY_RUN="${4:-false}"
  local SCAN_MONTH="${5:-}"
  
  log "Source: upstream torvalds/linux commits" >&2
  log "Searching for commits containing keyword: CVE" >&2
  log "Note: Most CVE fixes don't mention CVE in commit messages" >&2
  
  > "$PATCH_LIST"
  
  if [ "$DRY_RUN" = true ]; then
    log "Dry run - skipping actual API calls" >&2
    echo "0"
    return 0
  fi
  
  local current_year=$(date +%Y)
  local current_month=$(date +%-m)
  
  if [ -n "$SCAN_MONTH" ]; then
    log "Scanning upstream $UPSTREAM_REPO for month $SCAN_MONTH" >&2
    _scan_month_upstream "$SCAN_MONTH" "$PATCH_LIST"
  else
    log "Scanning upstream $UPSTREAM_REPO from 2024-01 to ${current_year}-$(printf '%02d' $current_month)" >&2
    
    for scan_month in $(_generate_month_range 2024 1 "$current_year" "$current_month"); do
      _scan_month_upstream "$scan_month" "$PATCH_LIST"
    done
  fi
  
  # Remove duplicates
  if [ -f "$PATCH_LIST" ] && [ -s "$PATCH_LIST" ]; then
    sort -u "$PATCH_LIST" -o "$PATCH_LIST"
  fi
  
  local total=$(wc -l < "$PATCH_LIST" 2>/dev/null | tr -d ' ' || echo "0")
  log "Found $total commits with CVE keyword" >&2
  
  echo "$total"
}

_get_days_in_month() {
  local year=$1
  local month=$2
  case $month in
    01|03|05|07|08|10|12) echo 31 ;;
    04|06|09|11) echo 30 ;;
    02)
      if [ $((year % 4)) -eq 0 ] && { [ $((year % 100)) -ne 0 ] || [ $((year % 400)) -eq 0 ]; }; then
        echo 29
      else
        echo 28
      fi
      ;;
  esac
}

_generate_month_range() {
  local start_year=$1
  local start_month=$2
  local end_year=$3
  local end_month=$4
  
  local year=$start_year
  local month=$start_month
  
  while [ "$year" -lt "$end_year" ] || { [ "$year" -eq "$end_year" ] && [ "$month" -le "$end_month" ]; }; do
    printf "%04d-%02d\n" "$year" "$month"
    month=$((month + 1))
    if [ "$month" -gt 12 ]; then
      month=1
      year=$((year + 1))
    fi
  done
}

_scan_month_upstream() {
  local scan_month=$1
  local PATCH_LIST=$2
  local year=$(echo "$scan_month" | cut -d'-' -f1)
  local month=$(echo "$scan_month" | cut -d'-' -f2)
  local days=$(_get_days_in_month "$year" "$month")
  
  log "  Scanning month: $scan_month ($days days)" >&2
  
  for day in $(seq 1 $days); do
    padded_day=$(printf "%02d" $day)
    since="${scan_month}-${padded_day}T00:00:00Z"
    until="${scan_month}-${padded_day}T23:59:59Z"
    
    api_url="https://api.github.com/repos/${UPSTREAM_REPO}/commits?since=${since}&until=${until}&per_page=100"
    response=$(curl -s -H "Accept: application/vnd.github+json" "$api_url")
    
    eligible=$(echo "$response" | jq -r \
      '.[] | select(.commit.message | test("CVE"; "i")) | .sha' 2>/dev/null)
    
    if [ -n "$eligible" ]; then
      echo "$eligible" >> "$PATCH_LIST"
    fi
  done
}

# -----------------------------------------------------------------------------
# GitHub Advisory Database Functions (GHSA)
# -----------------------------------------------------------------------------

# Configuration for GHSA
GHSA_GRAPHQL_URL="https://api.github.com/graphql"
GHSA_SEVERITY_FILTER="${GHSA_SEVERITY_FILTER:-HIGH,CRITICAL}"
GHSA_MARKER="${LOG_DIR:-.}/.ghsa_last_run"

# Check if GitHub CLI is available and authenticated
_check_gh_auth() {
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

# Get GitHub token from gh CLI or environment
_get_github_token() {
  # First check environment variable
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN"
    return 0
  fi
  
  # Try to get from gh CLI
  if _check_gh_auth; then
    gh auth token 2>/dev/null
    return $?
  fi
  
  return 1
}

# Query GitHub Advisory Database using GraphQL
# Returns JSON with CVE advisories related to Linux kernel
_query_ghsa_advisories() {
  local OUTPUT_FILE="$1"
  local AFTER_CURSOR="${2:-}"
  
  local TOKEN=$(_get_github_token)
  if [ -z "$TOKEN" ]; then
    log_error "No GitHub token available. Set GITHUB_TOKEN or authenticate with 'gh auth login'" >&2
    return 1
  fi
  
  # Build cursor parameter
  local AFTER_PARAM=""
  if [ -n "$AFTER_CURSOR" ]; then
    AFTER_PARAM=", after: \"$AFTER_CURSOR\""
  fi
  
  # GraphQL query for Linux kernel CVEs
  local QUERY='query {
    securityAdvisories(first: 100, orderBy: {field: PUBLISHED_AT, direction: DESC}'$AFTER_PARAM') {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        ghsaId
        summary
        severity
        publishedAt
        updatedAt
        identifiers {
          type
          value
        }
        references {
          url
        }
        cwes(first: 5) {
          nodes {
            cweId
            name
          }
        }
        vulnerabilities(first: 10) {
          nodes {
            package {
              name
              ecosystem
            }
            vulnerableVersionRange
            firstPatchedVersion {
              identifier
            }
          }
        }
      }
    }
  }'
  
  # Execute GraphQL query
  local RESPONSE=$(curl -s --max-time 60 \
    -H "Authorization: bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{\"query\": \"$(echo "$QUERY" | tr '\n' ' ' | sed 's/"/\\"/g')\"}" \
    "$GHSA_GRAPHQL_URL" 2>/dev/null)
  
  if [ -z "$RESPONSE" ]; then
    log_error "Empty response from GitHub GraphQL API" >&2
    return 1
  fi
  
  # Check for errors
  local ERRORS=$(echo "$RESPONSE" | jq -r '.errors[0].message // empty' 2>/dev/null)
  if [ -n "$ERRORS" ]; then
    log_error "GitHub API error: $ERRORS" >&2
    return 1
  fi
  
  echo "$RESPONSE" > "$OUTPUT_FILE"
  return 0
}

# Parse GHSA response and extract Linux kernel CVEs with commit references
_parse_ghsa_for_kernel_cves() {
  local GHSA_JSON="$1"
  local CVE_INFO_FILE="$2"
  local PATCH_LIST="$3"
  local SEVERITY_FILTER="$4"
  
  if [ ! -f "$GHSA_JSON" ]; then
    return 1
  fi
  
  # Build severity filter regex
  local SEV_REGEX=$(echo "$SEVERITY_FILTER" | tr ',' '|')
  
  # Extract advisories that:
  # 1. Have a CVE identifier
  # 2. Match severity filter
  # 3. Have references to git.kernel.org or torvalds/linux commits
  # 4. Summary/description mentions "linux kernel" or "kernel"
  jq -r --arg sev_regex "$SEV_REGEX" '
    .data.securityAdvisories.nodes[]? |
    select(.severity | test($sev_regex; "i")) |
    select(
      (.summary | test("linux kernel|kernel|smb|cifs|net/|fs/|drivers/|mm/|arch/"; "i")) or
      (.references[]?.url | test("git.kernel.org|torvalds/linux"; "i"))
    ) |
    {
      ghsa_id: .ghsaId,
      cve_id: (.identifiers[] | select(.type == "CVE") | .value),
      severity: .severity,
      summary: .summary,
      refs: [.references[]?.url | select(test("git.kernel.org.*/c/[a-f0-9]{40}|torvalds/linux/commit/[a-f0-9]{40}"))]
    } |
    select(.cve_id != null) |
    select(.refs | length > 0) |
    "\(.cve_id)|\(.severity)|\(.ghsa_id)|\(.refs[])"
  ' "$GHSA_JSON" 2>/dev/null | while IFS='|' read -r cve_id severity ghsa_id ref_url; do
    if [ -n "$ref_url" ] && [ -n "$cve_id" ]; then
      # Extract commit SHA from URL
      local commit=""
      if echo "$ref_url" | grep -q "git.kernel.org"; then
        commit=$(echo "$ref_url" | grep -oP '/c/\K[a-f0-9]{40}' | head -1)
      elif echo "$ref_url" | grep -q "torvalds/linux"; then
        commit=$(echo "$ref_url" | grep -oP 'commit/\K[a-f0-9]{40}' | head -1)
      fi
      
      if [ -n "$commit" ]; then
        echo "$commit" >> "$PATCH_LIST"
        echo "$cve_id|$commit|$severity|$ghsa_id" >> "$CVE_INFO_FILE"
      fi
    fi
  done
}

# Check if we should run full GHSA scan (rate limit: once per hour)
_should_run_ghsa_full() {
  if [ ! -f "$GHSA_MARKER" ]; then
    return 0
  fi
  
  local last_run=$(cat "$GHSA_MARKER" 2>/dev/null)
  local now=$(date +%s)
  local age=$((now - last_run))
  
  if [ $age -ge 3600 ]; then
    return 0
  else
    local mins=$((age / 60))
    log "  GHSA full scan last run ${mins}m ago (rate limit: 1/hour)" >&2
    return 1
  fi
}

_update_ghsa_marker() {
  mkdir -p "$(dirname "$GHSA_MARKER")"
  date +%s > "$GHSA_MARKER"
}

find_patches_ghsa() {
  local KERNEL_VERSION="$1"
  local OUTPUT_DIR="$2"
  local PATCH_LIST="$3"
  local DRY_RUN="${4:-false}"
  
  log "Source: GitHub Advisory Database (GHSA)" >&2
  log "Filter: Severity $GHSA_SEVERITY_FILTER, Linux kernel related" >&2
  log "Target kernel: $KERNEL_VERSION" >&2
  
  local CVE_INFO_FILE="$OUTPUT_DIR/cve_info_ghsa.txt"
  > "$CVE_INFO_FILE"
  > "$PATCH_LIST"
  
  if [ "$DRY_RUN" = true ]; then
    log "Dry run - skipping actual API calls" >&2
    echo "0"
    return 0
  fi
  
  # Check for GitHub authentication
  if ! _get_github_token >/dev/null 2>&1; then
    log_error "GitHub authentication required for GHSA source" >&2
    log_error "Either set GITHUB_TOKEN environment variable or run 'gh auth login'" >&2
    echo "0"
    return 1
  fi
  
  log "Querying GitHub Advisory Database..." >&2
  
  local GHSA_JSON="$OUTPUT_DIR/ghsa_response.json"
  local page=1
  local total_fetched=0
  local cursor=""
  
  # Paginate through results (max 5 pages = 500 advisories)
  while [ $page -le 5 ]; do
    log "  Fetching page $page..." >&2
    
    if ! _query_ghsa_advisories "$GHSA_JSON" "$cursor"; then
      log_warn "Failed to fetch GHSA page $page" >&2
      break
    fi
    
    # Parse and extract kernel CVEs
    _parse_ghsa_for_kernel_cves "$GHSA_JSON" "$CVE_INFO_FILE" "$PATCH_LIST" "$GHSA_SEVERITY_FILTER"
    
    # Check for more pages
    local has_next=$(jq -r '.data.securityAdvisories.pageInfo.hasNextPage' "$GHSA_JSON" 2>/dev/null)
    cursor=$(jq -r '.data.securityAdvisories.pageInfo.endCursor // empty' "$GHSA_JSON" 2>/dev/null)
    
    local page_count=$(jq -r '.data.securityAdvisories.nodes | length' "$GHSA_JSON" 2>/dev/null)
    total_fetched=$((total_fetched + page_count))
    
    if [ "$has_next" != "true" ] || [ -z "$cursor" ]; then
      break
    fi
    
    page=$((page + 1))
    sleep 1  # Rate limiting
  done
  
  rm -f "$GHSA_JSON"
  
  # Remove duplicates
  if [ -f "$PATCH_LIST" ] && [ -s "$PATCH_LIST" ]; then
    sort -u "$PATCH_LIST" -o "$PATCH_LIST"
  fi
  
  _update_ghsa_marker
  
  local total=$(wc -l < "$PATCH_LIST" 2>/dev/null | tr -d ' ' || echo "0")
  log "Scanned $total_fetched advisories, found $total kernel CVE commits from GHSA" >&2
  
  [ "$total" -gt 0 ] && log "CVE info saved to: $CVE_INFO_FILE" >&2
  
  echo "$total"
}

# -----------------------------------------------------------------------------
# Main Dispatcher
# -----------------------------------------------------------------------------
find_cve_patches() {
  local CVE_SOURCE="$1"
  local KERNEL_VERSION="$2"
  local OUTPUT_DIR="$3"
  local PATCH_LIST="$4"
  local DRY_RUN="${5:-false}"
  local SCAN_MONTH="${6:-}"
  local CURRENT_VERSION="${7:-}"
  
  case "$CVE_SOURCE" in
    nvd)
      find_patches_nvd "$KERNEL_VERSION" "$OUTPUT_DIR" "$PATCH_LIST" "$DRY_RUN"
      ;;
    atom)
      find_patches_atom "$KERNEL_VERSION" "$OUTPUT_DIR" "$PATCH_LIST" "$DRY_RUN" "$CURRENT_VERSION"
      ;;
    upstream)
      find_patches_upstream "$KERNEL_VERSION" "$OUTPUT_DIR" "$PATCH_LIST" "$DRY_RUN" "$SCAN_MONTH"
      ;;
    ghsa)
      find_patches_ghsa "$KERNEL_VERSION" "$OUTPUT_DIR" "$PATCH_LIST" "$DRY_RUN"
      ;;
    *)
      log_error "Unknown CVE source: $CVE_SOURCE"
      echo "0"
      return 1
      ;;
  esac
}
