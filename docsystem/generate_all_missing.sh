#!/bin/bash
# Generate all missing blog posts from first commit until 2026-01
# This script runs in the background and can be resumed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="/tmp/generate_missing_blog_posts.log"
BATCHES_COMPLETED_FILE="/tmp/generate_missing_batches_completed.txt"

echo "Starting blog post generation at $(date)" | tee -a "$LOG_FILE"

# Ensure XAI_API_KEY is set
if [ -z "$XAI_API_KEY" ]; then
    echo "ERROR: XAI_API_KEY environment variable not set" | tee -a "$LOG_FILE"
    exit 1
fi

# Function to run summarizer for a specific branch and month range
run_batch() {
    local branch=$1
    local start_month=$2
    local end_month=$3
    local batch_name="${branch}_${start_month}_${end_month}"

    # Check if already completed
    if grep -q "^$batch_name$" "$BATCHES_COMPLETED_FILE" 2>/dev/null; then
        echo "Skipping already completed batch: $batch_name" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "Processing batch: $batch_name at $(date)" | tee -a "$LOG_FILE"

    if python3 .factory/skills/photon-summarize/summarizer.py \
        --db-path photon_commits.db \
        --output-dir content/blog \
        --branches "$branch" \
        --months "${start_month}:${end_month}" \
        --model grok-4-0709 2>&1 | tee -a "$LOG_FILE"; then

        echo "$batch_name" >> "$BATCHES_COMPLETED_FILE"
        echo "Completed batch: $batch_name at $(date)" | tee -a "$LOG_FILE"
    else
        echo "ERROR: Failed batch: $batch_name at $(date)" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Branch 3.0: 2022-06 to 2025-12 (already has 2022-05, need 2022-06 onwards)
run_batch "3.0" "2022-06" "2025-12" || true

# Branch 4.0: 2021-01 to 2023-12 and 2024-06 to 2026-01
run_batch "4.0" "2021-01" "2023-12" || true
run_batch "4.0" "2024-06" "2026-01" || true

# Branch 5.0: 2021-01 to 2023-12 and 2024-05 to 2026-01
run_batch "5.0" "2021-01" "2023-12" || true
run_batch "5.0" "2024-05" "2026-01" || true

# Branch 6.0: 2021-01 to 2024-12 and 2025-04 to 2025-12
run_batch "6.0" "2021-01" "2024-12" || true
run_batch "6.0" "2025-04" "2025-12" || true

# Branch common: 2021-01 to 2025-12
run_batch "common" "2021-01" "2025-12" || true

# Branch master: 2021-01 to 2024-12
run_batch "master" "2021-01" "2024-12" || true

echo "All batches completed at $(date)" | tee -a "$LOG_FILE"

# Final summary
python3 << 'PYEOF'
import sqlite3
conn = sqlite3.connect('photon_commits.db')
cur = conn.cursor()
cur.execute('SELECT COUNT(*) FROM summaries')
count = cur.fetchone()[0]
print(f"\n=== FINAL SUMMARY ===")
print(f"Total summaries in database: {count}")
cur.execute('SELECT branch, COUNT(*) FROM summaries GROUP BY branch')
for row in cur.fetchall():
    print(f"  {row[0]}: {row[1]} months")
conn.close()
PYEOF

echo "Done at $(date)" | tee -a "$LOG_FILE"
