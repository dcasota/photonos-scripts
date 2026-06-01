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
import numpy as np

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

    # Wider figure + legend pushed OUTSIDE the plot area on the right
    # so the .docx-embedded 6-inch-wide rendering stays uncluttered and
    # x-axis date labels never collide with the legend or source caption.
    fig, ax = plt.subplots(figsize=(12.5, 5.4))

    for b in BRANCH_ORDER:
        if b not in data:
            continue
        xs = [p[0] for p in data[b]]
        ys = [p[1] for p in data[b]]
        ax.plot(xs, ys, "-o", lw=2, ms=4, label=f"photon-{b}",
                color=BRANCH_COLORS[b], alpha=0.95)

    # Dashed trend line: linear regression on the AGGREGATE — average
    # update count across all branches at each scan_datetime, fitted
    # as a single straight line. One trend instead of eight keeps the
    # chart readable; the slope tells the maintainer at a glance
    # whether the population of updates-per-scan is trending up or
    # down across the whole timeline.
    all_pts = [(d, n) for v in data.values() for d, n in v]
    if len(all_pts) >= 2:
        # Group by exact timestamp -> mean
        grouped = defaultdict(list)
        for d, n in all_pts:
            grouped[d].append(n)
        ts_sorted = sorted(grouped.keys())
        means = [sum(grouped[t]) / len(grouped[t]) for t in ts_sorted]
        x_num = mdates.date2num(ts_sorted)
        m, c = np.polyfit(x_num, means, 1)
        ax.plot(ts_sorted, m * x_num + c,
                "--", color="#222", lw=2.0, alpha=0.55,
                label="Aggregate trend (linear)")

    ax.set_title("Photon OS package-report — Updates available per branch over time", pad=12)
    ax.set_xlabel("Scan date (UTC)")
    ax.set_ylabel("Packages with a real upstream update")

    # Legend OUTSIDE the right margin (vertical column). reserve_right
    # gives the legend its own canvas region so labels never overlap data.
    ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1.0),
              frameon=False, fontsize=9, borderaxespad=0)

    ax.xaxis.set_major_locator(mdates.AutoDateLocator(minticks=6, maxticks=12))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m"))
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda v, _: f"{int(v):,}"))
    fig.autofmt_xdate(rotation=30, ha="right")

    # Source/metadata caption — placed INSIDE the axes (top-right interior)
    # so it never collides with x-tick labels or the right-side legend.
    all_dt = [d for v in data.values() for d, _ in v]
    if all_dt:
        rng = f"{min(all_dt):%Y-%m-%d}  →  {max(all_dt):%Y-%m-%d}"
        ax.text(0.99, 0.97,
                f"{sum(len(v) for v in data.values())} scans  ·  {rng}",
                transform=ax.transAxes, ha="right", va="top",
                fontsize=8.5, color="#555", style="italic",
                bbox=dict(boxstyle="round,pad=0.25",
                          fc="white", ec="#DDD", lw=0.5, alpha=0.85))

    # subplots_adjust to give the legend column room without colliding.
    fig.subplots_adjust(right=0.80)
    plt.savefig(args.out, bbox_inches="tight")
    plt.close()

    sz = os.path.getsize(args.out)
    print(f"timeline chart written: {args.out}  ({sz/1024:.0f} KB, "
          f"{sum(len(v) for v in data.values())} points, {len(data)} branches)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
