#!/usr/bin/env bash
# =============================================================================
# suggestion-2-dynamic-size-calculation-v9.sh
#
# Uses tdnf repoquery + tdnf info to get accurate Install Size without downloads.
# - repoquery finds the exact package name/version
# - info parses Install Size (unpacked on-disk size)
# Requires base repo enabled for full results.
# =============================================================================

set -euo pipefail

# CONFIGURATION
PACKAGES=(
    bash
    coreutils
    glibc
    # Add more after repo fix: curl, tdnf, libgomp, libstdc++, rpm-sequoia, etc.
)

BUFFER_PERCENT=15
COMPRESSION_RATIO=0.65  # Typical tar.gz vs unpacked; tune empirically

echo ""
echo "=== Dynamic Size Calculation for Photon minimal image ==="
echo "Packages: ${PACKAGES[*]}"
echo "Buffer:   ${BUFFER_PERCENT}%"
echo ""

# Step 1: Quick repo sanity check
echo "Checking repository status..."
if ! tdnf repolist >/dev/null 2>&1; then
    echo "ERROR: tdnf repolist failed — tdnf not functional." >&2
    exit 1
fi

enabled_count=$(tdnf repolist | grep -c "enabled" || true)
if [ "$enabled_count" -eq 0 ]; then
    echo "ERROR: No enabled repositories found." >&2
    echo "Fix: Enable base repo (see below)." >&2
    exit 1
fi

echo "Found ${enabled_count} enabled repo(s). Proceeding..."
echo ""

# Step 2: Size calculation
total_installed_bytes=0

for pkg in "${PACKAGES[@]}"; do
    echo "→ Querying $pkg ..."

    # Step 1: Get exact package name from repoquery (latest available)
    pkg_exact=$(tdnf repoquery "$pkg" 2>/dev/null | head -n1 || echo "")

    if [ -z "$pkg_exact" ]; then
        echo "Error: No package found for '$pkg' in enabled repos." >&2
        echo "  → Run: tdnf repoquery $pkg" >&2
        echo "  → Ensure base repo is enabled[](https://packages.broadcom.com/photon/5.0/...)" >&2
        echo "  → Try: tdnf update photon-repos" >&2
        continue
    fi

    echo "  Exact package: $pkg_exact"

    # Step 2: Get Install Size from tdnf info
    install_size_line=$(tdnf info "$pkg_exact" 2>/dev/null | grep -i "Install Size" | head -n1 || echo "")

    if [ -z "$install_size_line" ]; then
        echo "Error: Could not parse Install Size for $pkg_exact" >&2
        continue
    fi

    # Parse bytes (e.g., "Install Size : 1.73M (1813714)" → extract 1813714)
    install_bytes=$(echo "$install_size_line" | grep -oP '\(\K[0-9]+(?=\))' || echo "0")

    if [ "$install_bytes" = "0" ]; then
        echo "Warning: Failed to extract bytes from: $install_size_line" >&2
        continue
    fi

    printf "%-18s : %10d bytes  (~ %5d KiB)\n" "$pkg" "$install_bytes" "$((install_bytes / 1024))"
    ((total_installed_bytes += install_bytes))
done

# Results
echo "──────────────────────────────────────────────"
printf "TOTAL installed size     : %10d bytes  (~ %4d MiB)\n" \
    "$total_installed_bytes" "$((total_installed_bytes / 1024 / 1024))"

if [ "$total_installed_bytes" -eq 0 ]; then
    echo ""
    echo "WARNING: No sizes obtained — base repo likely missing/disabled." >&2
    echo "Fix steps:" >&2
    echo "  1. tdnf repolist all" >&2
    echo "  2. Create/edit /etc/yum.repos.d/photon.repo with baseurl=https://packages.broadcom.com/photon/5.0/photon_release_5.0_x86_64" >&2
    echo "  3. tdnf clean all && tdnf makecache" >&2
    echo "  4. Test: tdnf repoquery glibc" >&2
    exit 1
fi

buffer_bytes=$(( total_installed_bytes * BUFFER_PERCENT / 100 ))
max_allowed_bytes=$(( total_installed_bytes + buffer_bytes ))

printf "Buffer (%d%%)            : %10d bytes\n" "$BUFFER_PERCENT" "$buffer_bytes"
printf "Max allowed uncompressed : %10d bytes  (~ %4d MiB)\n" \
    "$max_allowed_bytes" "$((max_allowed_bytes / 1024 / 1024))"

estimated_tar_gz_bytes=$(echo "scale=0; $max_allowed_bytes * $COMPRESSION_RATIO / 1" | bc)
printf "Estimated max .tar.gz    : %10s bytes  (~ %4d MiB)   [~%.0f%% comp]\n" \
    "$estimated_tar_gz_bytes" "$((estimated_tar_gz_bytes / 1024 / 1024))" "$(echo "$COMPRESSION_RATIO * 100" | bc)"

echo ""
