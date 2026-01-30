#!/bin/bash
# Build wifi-config RPM package for Photon OS 5.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/wifi-config-build"
OUTPUT_DIR="${SCRIPT_DIR}/../RPM"
VERSION="1.0.0"

echo "=== Building wifi-config-${VERSION} RPM ==="

# Create build directories
mkdir -p "${BUILD_DIR}"/{SOURCES,SPECS,BUILD,RPMS,SRPMS,BUILDROOT}
mkdir -p "${OUTPUT_DIR}"

# Copy spec file
cp "${SCRIPT_DIR}/wifi-config.spec" "${BUILD_DIR}/SPECS/"

# Build RPM (noarch - just config files)
echo "Building wifi-config RPM..."
rpmbuild --define "_topdir ${BUILD_DIR}" \
         --define "buildroot ${BUILD_DIR}/BUILDROOT" \
         -bb "${BUILD_DIR}/SPECS/wifi-config.spec"

# Copy result
cp "${BUILD_DIR}"/RPMS/noarch/wifi-config-*.rpm "${OUTPUT_DIR}/" 2>/dev/null || \
cp "${BUILD_DIR}"/RPMS/*/wifi-config-*.rpm "${OUTPUT_DIR}/"

echo ""
echo "=== Build Complete ==="
echo "Output: ${OUTPUT_DIR}/wifi-config-${VERSION}-1.ph5.noarch.rpm"
ls -la "${OUTPUT_DIR}"/wifi-config-*.rpm 2>/dev/null
