## Overview

`weblinkchecker.sh` is a recursive website crawler that detects broken links, redirect loops, and other URL issues. It uses `wget` in spider mode to crawl websites, handling self-signed certificates automatically.

## Usage

```bash
./weblinkchecker.sh <URL or IP[:PORT]>
```

### Examples

```bash
# HTTPS URL
./weblinkchecker.sh https://vmware.github.io/photon

# IP address (defaults to HTTPS on port 443)
./weblinkchecker.sh 192.168.225.137

# Custom port
./weblinkchecker.sh example.com:8443

# HTTP URL
./weblinkchecker.sh http://localhost:8080
```

## Output Files

The script generates four timestamped output files:

| File | Description |
|------|-------------|
| `report-<datetime>.log` | Full wget debug output with all crawl details |
| `report-<datetime>.csv` | Broken links in CSV format: `referring_page,broken_link` |
| `redirects-<datetime>.log` | All detected redirects: `source -> destination` |
| `redirect-loops-<datetime>.log` | Redirect loops and excessive redirects |

## Summary Output

After crawling, the script displays a summary:

```
========================================
Crawl complete!
========================================
Full details: report-2025-12-01_09-36-37.log
Broken links (404): report-2025-12-01_09-36-37.csv
Redirects: redirects-2025-12-01_09-36-37.log
Redirect loops: redirect-loops-2025-12-01_09-36-37.log

Summary:
  - Broken links (404): 1399
  - Redirect loops: 0
  - Excessive redirects: 0
========================================
```

The report e.g. report-2025-12-01_09-36-37.csv contains a listing of webpages. Each line lists the webpage and the orphaned weblink found.

## Configuration

Default settings (hardcoded in script):

| Parameter | Value | Description |
|-----------|-------|-------------|
| `--level` | 10 | Maximum recursion depth |
| `--max-redirect` | 5 | Maximum redirects before flagging |
| `robots` | off | Ignores robots.txt |

## Certificate Handling

The script automatically:
1. Extracts the server's SSL certificate
2. Detects hostname mismatches
3. Skips URL replacement for wildcard certificates (e.g., `*.github.io`)

---

# Post-Analysis: Generating Issue Rankings

After running `weblinkchecker.sh`, use these commands to analyze and categorize broken links.

## Step 1: Count Total Issues

```bash
REPORT="report-2025-12-01_09-36-37.csv"
total=$(tail -n +2 "$REPORT" | wc -l)
echo "Total issues: $total"
```

## Step 2: Categorize Issues

```bash
REPORT="report-2025-12-01_09-36-37.csv"

tail -n +2 "$REPORT" | while IFS=',' read referring broken; do
  if echo "$referring" | grep -q "printview"; then
    echo "printview_double_slash"
  elif echo "$broken" | grep -qE "//[^/]"; then
    echo "double_slash"
  elif echo "$broken" | grep -qE "\.png$|\.jpg$|\.svg$|\.ico$"; then
    echo "missing_image"
  elif echo "$broken" | grep -qE "\.md$"; then
    echo "md_file_link"
  else
    echo "other"
  fi
done | sort | uniq -c | sort -rn
```

## Step 3: Generate Formatted Ranking

```bash
REPORT="report-2025-12-01_09-36-37.csv"

# Count totals
total=$(tail -n +2 "$REPORT" | wc -l)
printview=$(tail -n +2 "$REPORT" | cut -d',' -f1 | grep -c "printview")
non_pv_double_slash=$(tail -n +2 "$REPORT" | grep -v "printview" | cut -d',' -f2 | grep -cE "//[^/]")
missing_image=$(tail -n +2 "$REPORT" | grep -v "printview" | cut -d',' -f2 | grep -cE "\.png$|\.jpg$|\.svg$|\.ico$")
md_file_link=$(tail -n +2 "$REPORT" | grep -v "printview" | cut -d',' -f2 | grep -cE "\.md$")

total_double_slash=$((printview + non_pv_double_slash))
other=$((total - total_double_slash - missing_image))

# Print formatted table
echo "=============================================="
echo "  Broken Links Report - Top 3 Categories"
echo "  Total Issues: $total"
echo "=============================================="
echo ""
echo "  Rank | Category                              | Count | Percentage"
echo "  -----+---------------------------------------+-------+-----------"
printf "  1    | double_slash (malformed // in paths) | %5d | %5.1f%%\n" \
  $total_double_slash $(echo "scale=1; $total_double_slash * 100 / $total" | bc)
printf "       | - from printview pages               | %5d | %5.1f%%\n" \
  $printview $(echo "scale=1; $printview * 100 / $total" | bc)
printf "       | - from other pages                   | %5d | %5.1f%%\n" \
  $non_pv_double_slash $(echo "scale=1; $non_pv_double_slash * 100 / $total" | bc)
printf "  2    | missing_image (broken image refs)    | %5d | %5.1f%%\n" \
  $missing_image $(echo "scale=1; $missing_image * 100 / $total" | bc)
printf "  3    | other (md_file_link, wrong paths)    | %5d | %5.1f%%\n" \
  $other $(echo "scale=1; $other * 100 / $total" | bc)
echo ""
echo "=============================================="
```

## Example Output

```
==============================================
  Broken Links Report - Top 3 Categories
  Total Issues: 1399
==============================================

  Rank | Category                              | Count | Percentage
  -----+---------------------------------------+-------+-----------
  1    | double_slash (malformed // in paths) |  1301 |  92.9%
       | - from printview pages               |   997 |  71.2%
       | - from other pages                   |   304 |  21.7%
  2    | missing_image (broken image refs)    |    60 |   4.2%
  3    | other (md_file_link, wrong paths)    |    38 |   2.7%

==============================================
```

---

## Issue Categories Explained

| Category | Description | Example |
|----------|-------------|---------|
| `double_slash` | URLs with `//` in the path (not protocol) | `https://example.com/path//file/` |
| `printview` | Issues originating from printview pages | Referring page contains `/printview/` |
| `missing_image` | Broken image references (.png, .jpg, .svg, .ico) | `images/missing.png` returns 404 |
| `md_file_link` | Links to raw .md files instead of rendered HTML | `page.md` instead of `page/` |
| `other` | Malformed URLs, wrong relative paths | Parentheses in URLs, incorrect `../` paths |

---

## Troubleshooting

### Script Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Failed to extract certificate` | Cannot connect to host | Check host/port accessibility |
| `integer expression expected` | Empty grep results | Script handles this automatically |
| `Hostname mismatch` (info) | Certificate CN differs from host | Normal for wildcard certs, script skips replacement |

### Large Sites

For very large sites, the crawl may take a long time. Consider:
- Reducing `--level` in the script (default: 10)
- Running during off-peak hours
- Filtering output for specific patterns

---

## Dependencies

- `wget` (1.21+)
- `openssl`
- `awk`
- `grep`
- `bc` (for percentage calculations in post-analysis)
