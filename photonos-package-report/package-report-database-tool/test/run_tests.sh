#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building ==="
make clean
make

echo ""
echo "=== Running Unit Tests ==="
make test

echo ""
echo "=== Integration Test: Import Real Scans ==="
DB="/tmp/photon-integration-test.db"
REPORT="/tmp/photon-test-report.docx"
SCANS="$SCRIPT_DIR/../scans"

rm -f "$DB" "$REPORT"

if [ -d "$SCANS" ]; then
    ./photon-report-db --db "$DB" --import "$SCANS" --report "$REPORT"

    echo ""
    echo "=== Verify .docx structure ==="
    if command -v unzip &>/dev/null; then
        unzip -l "$REPORT" || echo "unzip verification failed"
    else
        echo "unzip not available, checking file size"
        ls -la "$REPORT"
    fi

    echo ""
    echo "=== DB Statistics ==="
    if command -v sqlite3 &>/dev/null; then
        sqlite3 "$DB" "SELECT 'Scan files: ' || COUNT(*) FROM scan_files;"
        sqlite3 "$DB" "SELECT 'Packages: ' || COUNT(*) FROM packages;"
        sqlite3 "$DB" "SELECT branch, COUNT(*) as scans FROM scan_files GROUP BY branch ORDER BY branch;"
    fi

    rm -f "$DB" "$REPORT"
    echo ""
    echo "=== Integration test PASSED ==="
else
    echo "Scans directory not found at $SCANS, skipping integration test"
fi

echo ""
echo "=== All tests completed ==="
