#!/bin/bash

# Script to recursively crawl (spider) a website using wget, handling self-signed certificates
# by extracting the certificate and adjusting for hostname mismatches.
# Generates report-<datetime>.log with wget debug output and report-<datetime>.csv with broken links (referring_page,broken_link).
# Usage: ./weblinkchecker.sh <URL or IP[:PORT]>
# Example: ./weblinkchecker.sh https://127.0.0.1
#          ./weblinkchecker.sh 192.168.225.137
#          ./weblinkchecker.sh example.com:8443
# Output: Generates report-<datetime>.log and report-<datetime>.csv with details on broken links.

if [ $# -ne 1 ]; then
    echo "Usage: $0 <URL or IP[:PORT]>"
    exit 1
fi

INPUT="$1"
CERT_FILE="server.crt"
DATETIME=$(date +%Y-%m-%d_%H-%M-%S)
REPORT_FILE="report-${DATETIME}.log"
CSV_FILE="report-${DATETIME}.csv"
REDIRECT_FILE="redirects-${DATETIME}.log"
REDIRECT_LOOP_FILE="redirect-loops-${DATETIME}.log"

# Prepend https:// if no protocol is specified
if ! [[ "$INPUT" =~ ^[a-zA-Z]+:// ]]; then
    URL="https://$INPUT"
else
    URL="$INPUT"
fi

# Extract host and port from URL
temp="${URL#*://}"  # Remove protocol
if [[ "$temp" =~ : ]]; then
    HOST="${temp%%:*}"
    PORT="${temp#*:}"
    PORT="${PORT%%/*}"  # Remove path if present
else
    HOST="${temp%%/*}"
    PORT=443
fi

# Validate PORT is numeric
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid port '$PORT'. Must be a number."
    exit 1
fi

# Extract the server certificate
echo | openssl s_client -connect "$HOST:$PORT" 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$CERT_FILE"

if [ ! -s "$CERT_FILE" ]; then
    echo "Error: Failed to extract certificate from $HOST:$PORT"
    exit 1
fi

# Extract the Common Name (CN) from the certificate
CN=$(openssl x509 -in "$CERT_FILE" -noout -subject | sed -n 's/.*CN[ ]*=[ ]*//p' | awk -F'/' '{print $1}')

# If CN differs from HOST, update the URL to use CN (to avoid hostname mismatch)
if [ "$CN" != "$HOST" ] && [ -n "$CN" ]; then
    echo "Hostname mismatch detected. Updating URL from $HOST to $CN"
    NEW_URL=$(echo "$URL" | sed "s/$HOST/$CN/")
else
    NEW_URL="$URL"
fi

# Run wget in spider mode for recursive crawl, ignoring robots.txt, with debug logging
# Increased depth to 10 and limit redirects to detect loops
wget --spider \
     -r \
     -nd \
     -d \
     -l 10 \
     --max-redirect=5 \
     -e robots=off \
     --ca-certificate="$CERT_FILE" \
     "$NEW_URL" \
     -o "$REPORT_FILE"

# Parse the log for broken links and their referring pages, output to CSV
awk '
  BEGIN { print "referring_page,broken_link" }
  /^--.*--  / { current_url = $3; referrer = "" }
  /^Referer: / { referrer = $2; gsub(/\r/, "", referrer) }
  /Remote file does not exist -- broken link!!!/ { gsub(/\r/, "", current_url); if (referrer != "") print referrer "," current_url }
' "$REPORT_FILE" > "$CSV_FILE"

# Extract redirect information
awk '
  /^--.*--  / { current_url = $3 }
  /^Location: / { redirect_to = $2; gsub(/\r/, "", redirect_to); print current_url " -> " redirect_to }
' "$REPORT_FILE" > "$REDIRECT_FILE"

# Detect redirect loops (same URL appearing multiple times in redirect chain)
awk '
  BEGIN { print "url,redirect_count,status" }
  {
    split($0, parts, " -> ")
    url = parts[1]
    urls[url]++
  }
  END {
    for (url in urls) {
      if (urls[url] > 2) {
        print url "," urls[url] ",REDIRECT_LOOP"
      } else if (urls[url] == 2) {
        print url "," urls[url] ",EXCESSIVE_REDIRECTS"
      }
    }
  }
' "$REDIRECT_FILE" > "$REDIRECT_LOOP_FILE"

# Count redirect issues
LOOP_COUNT=$(grep -c "REDIRECT_LOOP" "$REDIRECT_LOOP_FILE" 2>/dev/null || echo 0)
EXCESSIVE_COUNT=$(grep -c "EXCESSIVE_REDIRECTS" "$REDIRECT_LOOP_FILE" 2>/dev/null || echo 0)

# Clean up certificate file (optional)
rm -f "$CERT_FILE"

# Print summary
echo "========================================"
echo "Crawl complete!"
echo "========================================"
echo "Full details: $REPORT_FILE"
echo "Broken links (404): $CSV_FILE"
echo "Redirects: $REDIRECT_FILE"
echo "Redirect loops: $REDIRECT_LOOP_FILE"
echo ""
echo "Summary:"
BROKEN_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l)
echo "  - Broken links (404): $BROKEN_COUNT"
echo "  - Redirect loops: $LOOP_COUNT"
echo "  - Excessive redirects: $EXCESSIVE_COUNT"
echo ""
if [ "$LOOP_COUNT" -gt 0 ]; then
  echo "WARNING: Redirect loops detected!"
  head -5 "$REDIRECT_LOOP_FILE"
fi
if [ "$EXCESSIVE_COUNT" -gt 0 ]; then
  echo "WARNING: Excessive redirects detected!"
  grep "EXCESSIVE_REDIRECTS" "$REDIRECT_LOOP_FILE" | head -5
fi
echo "========================================"
