#!/bin/bash
# Build wireless-regdb and iw RPM packages for Photon OS 5.0
# These packages are not available in Photon repos but are needed for WiFi regulatory compliance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/wireless-rpm-build"
OUTPUT_DIR="${SCRIPT_DIR}/RPM"

# Versions
REGDB_VERSION="2024.01.23"
IW_VERSION="6.9"

echo "=== Building wireless packages for Photon OS 5.0 ==="

# Create build directories
mkdir -p "${BUILD_DIR}"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}
mkdir -p "${OUTPUT_DIR}"

# ============================================
# Build wireless-regdb (noarch - just data files)
# ============================================
echo ""
echo "=== Building wireless-regdb-${REGDB_VERSION} ==="

cd "${BUILD_DIR}"

# Download regulatory database files from kernel.org
echo "Downloading regulatory database..."
mkdir -p wireless-regdb-${REGDB_VERSION}
cd wireless-regdb-${REGDB_VERSION}

# Get the pre-built regulatory database
curl -sL "https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/plain/regulatory.db" -o regulatory.db
curl -sL "https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/plain/regulatory.db.p7s" -o regulatory.db.p7s
curl -sL "https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/plain/LICENSE" -o LICENSE

cd ..

# Create tarball
tar czf SOURCES/wireless-regdb-${REGDB_VERSION}.tar.gz wireless-regdb-${REGDB_VERSION}

# Copy spec file
cp "${SCRIPT_DIR}/wireless-regdb/wireless-regdb.spec" SPECS/

# Build RPM
echo "Building wireless-regdb RPM..."
rpmbuild --define "_topdir ${BUILD_DIR}" -bb SPECS/wireless-regdb.spec

# Copy result
cp RPMS/noarch/wireless-regdb-*.rpm "${OUTPUT_DIR}/"
echo "Built: $(ls RPMS/noarch/wireless-regdb-*.rpm)"

# ============================================
# Build iw (requires compilation)
# ============================================
echo ""
echo "=== Building iw-${IW_VERSION} ==="

cd "${BUILD_DIR}"

# Download iw source
echo "Downloading iw source..."
curl -sL "https://git.kernel.org/pub/scm/linux/kernel/git/jberg/iw.git/snapshot/iw-${IW_VERSION}.tar.gz" -o SOURCES/iw-${IW_VERSION}.tar.gz

# Copy spec file
cp "${SCRIPT_DIR}/iw/iw.spec" SPECS/

# Build RPM (requires libnl-devel)
echo "Building iw RPM..."
if ! rpm -q libnl-devel >/dev/null 2>&1; then
    echo "Installing build dependencies..."
    tdnf install -y libnl-devel pkg-config gcc make
fi

rpmbuild --define "_topdir ${BUILD_DIR}" -bb SPECS/iw.spec

# Copy result
cp RPMS/x86_64/iw-*.rpm "${OUTPUT_DIR}/" 2>/dev/null || cp RPMS/*/iw-*.rpm "${OUTPUT_DIR}/"
echo "Built: $(ls ${OUTPUT_DIR}/iw-*.rpm 2>/dev/null | head -1)"

# ============================================
# Summary
# ============================================
echo ""
echo "=== Build Complete ==="
echo "Output directory: ${OUTPUT_DIR}"
ls -la "${OUTPUT_DIR}"/*.rpm 2>/dev/null | grep -E "wireless-regdb|iw-"

echo ""
echo "To use these packages:"
echo "1. Copy RPMs to ISO's RPMS directory"
echo "2. Run 'createrepo' to update repository metadata"
echo "3. Add package names to packages_mok.json"
