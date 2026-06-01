#!/usr/bin/env python3
"""gen-timeline-chart.py — M127.

Render the per-branch updates-available timeline as a high-quality PNG
from photon-scans.db. The workflow's database-report job calls this
right after the import step and passes the resulting path to
`photon-report-db --chart-png ...` so Section 1 of the dynamic .docx
embeds this image instead of the static OOXML chart1.xml.

Usage:
    gen-timeline-chart.py --db <path.db> --out <path.png>
"""
import argparse, os, sqlite3, sys
from collections import defaultdict
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick

SQL = """
SELECT sf.branch, sf.scan_datetime, COUNT(*) AS n
FROM scan_files sf JOIN packages p ON p.scan_file_id = sf.id
WHERE p.update_available IS NOT NULL
  AND p.update_available <> ''
  AND p.update_available NOT LIKE 'Warning:%'
  AND p.update_available NOT LIKE 'Info:%'
  AND p.update_available <> '(same version)'
GROUP BY sf.branch, sf.scan_datetime
ORDER BY sf.scan_datetime ASC
"""

# Stable colour assignment so the same branch reads as the same line
# across every weekly run.
BRANCH_COLORS = {
    "3.0":    "#7F7F7F",   # legacy — grey
    "4.0":    "#B22222",
    "5.0":    "#0F4C81",   # photon-blue (current focus)
    "6.0":    "#3FA34D",
    "common": "#E1A300",
    "dev":    "#9B59B6",
    "master": "#1B9E9E",
    "main":   "#FF7F0E",
}
BRANCH_ORDER = ["3.0", "4.0", "5.0", "6.0", "common", "dev", "master", "main"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if not os.path.exists(args.db):
        print(f"::error::DB not found: {args.db}", file=sys.stderr)
        return 1

    data = defaultdict(list)  # branch -> [(dt, n), ...]
    con = sqlite3.connect(args.db)
    for branch, ts_str, n in con.execute(SQL):
        try:
            dt = datetime.strptime(ts_str, "%Y%m%d%H%M")
        except ValueError:
            continue
        data[branch].append((dt, n))
    con.close()

    for b in data:
        data[b].sort(key=lambda p: p[0])

    if not any(data.values()):
        print("::warning::no timeline points — DB has no real-update rows", file=sys.stderr)
        return 1

    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "axes.titlesize": 13,
        "axes.titleweight": "bold",
        "axes.labelsize": 10,
        "axes.spines.top":   False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.linestyle": ":",
        "grid.alpha": 0.4,
        "figure.dpi": 160,
    })

    fig, ax = plt.subplots(figsize=(11, 5))
    for b in BRANCH_ORDER:
        if b not in data:
            continue
        xs = [p[0] for p in data[b]]
        ys = [p[1] for p in data[b]]
        ax.plot(xs, ys, "-o", lw=2, ms=4, label=f"photon-{b}",
                color=BRANCH_COLORS[b], alpha=0.95)

    ax.set_title("Photon OS package-report — Updates available per branch over time", pad=12)
    ax.set_xlabel("Scan date (UTC)")
    ax.set_ylabel("Packages with a real upstream update")
    ax.legend(loc="upper left", frameon=False, ncols=4, fontsize=9,
              bbox_to_anchor=(0, -0.13))
    ax.xaxis.set_major_locator(mdates.AutoDateLocator(minticks=6, maxticks=12))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda v, _: f"{int(v):,}"))
    fig.autofmt_xdate(rotation=30, ha="right")

    all_dt = [d for v in data.values() for d, _ in v]
    if all_dt:
        rng = f"{min(all_dt):%Y-%m-%d}  →  {max(all_dt):%Y-%m-%d}"
        ax.text(0.99, -0.32,
                f"Source: photon-scans.db  ({sum(len(v) for v in data.values())} scans, span: {rng})",
                transform=ax.transAxes, ha="right",
                fontsize=8.5, color="#555", style="italic")

    plt.tight_layout()
    plt.savefig(args.out, bbox_inches="tight")
    plt.close()

    sz = os.path.getsize(args.out)
    print(f"timeline chart written: {args.out}  ({sz/1024:.0f} KB, "
          f"{sum(len(v) for v in data.values())} points, {len(data)} branches)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
