#!/usr/bin/env python3
"""Build per-branch package-classifier summaries.

Joins:
  - cybersecurity_tools.jsonl (one classifier record per URL, produced by
    Get-CybersecurityToolsWithGrok.ps1)
  - urls-by-branch.json       (URL -> [branches], produced by
    Get-PackageReportUrls.ps1 with -BranchMapFile)

For every branch, emits markdown + text reports showing the Top-N tools by
composite_score, each tool's resume (the `summary` field), and its Top-3
alternatives. Within a branch, deduplicates by tool_name (case-insensitive)
keeping the record with the highest composite_score.

Outputs:
  <out>/BranchSummary_<branch>_<stamp>.md
  <out>/BranchSummary_<branch>_<stamp>.txt
  <out>/BranchSummary_<branch>_<stamp>.json
And a combined Markdown for the GitHub step summary on stdout (caller pipes
it into $GITHUB_STEP_SUMMARY).
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
import sys
from collections import defaultdict


def load_jsonl(path: str) -> list[dict]:
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception as exc:
                sys.stderr.write(f"warn: skipping malformed jsonl line: {exc}\n")
    return rows


def truncate(s: str, n: int) -> str:
    if not s:
        return ""
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"


def composite_for_dedup(d: dict) -> float:
    """Return composite_score as float for sort/dedup, falling back to -1."""
    cs = d.get("composite_score")
    try:
        return float(cs) if cs is not None else -1.0
    except (TypeError, ValueError):
        return -1.0


def _norm_name(name: str | None) -> str:
    """Aggressive normalization for dedup: lowercase + strip everything that
    isn't a letter or digit. Catches near-duplicates like 'fmt' vs '{fmt}',
    'NumPy' vs 'numpy', 'Click' vs 'click ' etc. — the classifier sometimes
    emits the same tool with brand stylization or trailing punctuation."""
    import re as _re
    return _re.sub(r"[^a-z0-9]+", "", (name or "").lower())


def dedup_by_tool(records: list[dict]) -> list[dict]:
    """Keep the highest-composite record per normalized tool_name."""
    by_key: dict[str, dict] = {}
    for r in records:
        key = _norm_name(r.get("tool_name"))
        if not key:
            continue
        if key not in by_key or composite_for_dedup(r) > composite_for_dedup(by_key[key]):
            by_key[key] = r
    return list(by_key.values())


def build_per_branch_records(jsonl_rows: list[dict],
                             url_to_branches: dict[str, list[str]],
                             branches: list[str]) -> dict[str, list[dict]]:
    by_branch: dict[str, list[dict]] = defaultdict(list)
    for rec in jsonl_rows:
        url = rec.get("url")
        if not url:
            continue
        for b in url_to_branches.get(url, []):
            if b in branches:
                by_branch[b].append(rec)
    return {b: by_branch.get(b, []) for b in branches}


def render_markdown(branch: str, records: list[dict], top_n: int,
                    generated: str) -> str:
    deduped = sorted(
        dedup_by_tool(records),
        key=composite_for_dedup, reverse=True,
    )[:top_n]
    out = [f"# Package Classifier — Branch {branch}\n",
           f"_Generated: {generated}_  ",
           f"_Records considered (this branch): {len(records)}; deduplicated: {len(deduped)} of top {top_n}_  \n"]
    if not deduped:
        out.append("\n_No classifier records mapped to this branch._\n")
        return "\n".join(out)
    for i, r in enumerate(deduped, 1):
        name   = r.get("tool_name") or "(unnamed)"
        cs     = r.get("composite_score")
        cs_str = f"{cs}" if cs is not None else "n/a"
        weblink = r.get("weblink") or ""
        summary = truncate(r.get("summary"), 220)
        out.append(f"### {i}. {name} — composite_score {cs_str}")
        if weblink:
            out.append(f"[{weblink}]({weblink})  ")
        out.append(f"**Resume:** {summary}")
        alts = r.get("alternatives") or []
        # PowerShell ConvertTo-Json serialises a single-element array as a
        # bare object instead of a 1-element list. Coerce back.
        if isinstance(alts, dict):
            alts = [alts]
        elif not isinstance(alts, list):
            alts = []
        # Drop any "alternative" whose name is the package itself -- Grok
        # often returns the package as a candidate in its own ranking pool,
        # which is not useful in an "alternatives" column. Use the same
        # normalisation as dedup so '{fmt}' and 'fmt' are treated as one.
        self_norm = _norm_name(r.get("tool_name"))
        if self_norm:
            alts = [a for a in alts
                    if isinstance(a, dict)
                    and _norm_name(a.get("name")) != self_norm]
        # Top-3 alternatives by composite_score (alternatives carry their own
        # composite_score; preserve the order the classifier emitted but cap at 3).
        try:
            alts_sorted = sorted(alts, key=lambda a: composite_for_dedup(a), reverse=True)
        except Exception:
            alts_sorted = alts
        top3 = alts_sorted[:3]
        if top3:
            out.append("\n**Top alternatives:**")
            out.append("")
            out.append("| # | Name | Composite | Rationale |")
            out.append("|---|---|---|---|")
            for j, a in enumerate(top3, 1):
                aname = (a.get("name") or "(unnamed)").replace("|", r"\|")
                acs   = a.get("composite_score")
                acs_str = f"{acs}" if acs is not None else "n/a"
                rat   = truncate(a.get("rationale") or "", 160).replace("|", r"\|")
                out.append(f"| {j} | {aname} | {acs_str} | {rat} |")
        out.append("")
    return "\n".join(out)


def render_text(branch: str, records: list[dict], top_n: int,
                generated: str) -> str:
    deduped = sorted(
        dedup_by_tool(records),
        key=composite_for_dedup, reverse=True,
    )[:top_n]
    out = [f"Package Classifier -- Branch {branch}",
           "",
           f"Generated: {generated}",
           f"Records considered (this branch): {len(records)}; deduplicated: {len(deduped)} of top {top_n}",
           ""]
    if not deduped:
        out.append("No classifier records mapped to this branch.")
        return "\n".join(out)
    for i, r in enumerate(deduped, 1):
        name = r.get("tool_name") or "(unnamed)"
        cs   = r.get("composite_score")
        cs_str = f"{cs}" if cs is not None else "n/a"
        out.append(f"{i:>2}. {name}  --  composite_score {cs_str}")
        wl = r.get("weblink") or ""
        if wl:
            out.append(f"    {wl}")
        out.append(f"    Resume: {truncate(r.get('summary'), 200)}")
        alts = r.get("alternatives") or []
        # PowerShell ConvertTo-Json serialises a single-element array as a
        # bare object instead of a 1-element list. Coerce back.
        if isinstance(alts, dict):
            alts = [alts]
        elif not isinstance(alts, list):
            alts = []
        # Drop any "alternative" whose name is the package itself -- Grok
        # often returns the package as a candidate in its own ranking pool,
        # which is not useful in an "alternatives" column. Use the same
        # normalisation as dedup so '{fmt}' and 'fmt' are treated as one.
        self_norm = _norm_name(r.get("tool_name"))
        if self_norm:
            alts = [a for a in alts
                    if isinstance(a, dict)
                    and _norm_name(a.get("name")) != self_norm]
        try:
            alts_sorted = sorted(alts, key=lambda a: composite_for_dedup(a), reverse=True)
        except Exception:
            alts_sorted = alts
        top3 = alts_sorted[:3]
        if top3:
            out.append("    Top alternatives:")
            for j, a in enumerate(top3, 1):
                aname = a.get("name") or "(unnamed)"
                acs   = a.get("composite_score")
                acs_str = f"{acs}" if acs is not None else "n/a"
                rat   = truncate(a.get("rationale") or "", 140)
                line  = f"      {j}. {aname}  ({acs_str})"
                if rat:
                    line += f"  -- {rat}"
                out.append(line)
        out.append("")
    return "\n".join(out)


def render_json(branch: str, records: list[dict], top_n: int,
                generated: str) -> str:
    deduped = sorted(
        dedup_by_tool(records),
        key=composite_for_dedup, reverse=True,
    )[:top_n]
    def _alts(r):
        a = r.get("alternatives") or []
        if isinstance(a, dict):
            a = [a]
        elif not isinstance(a, list):
            a = []
        self_norm = _norm_name(r.get("tool_name"))
        if self_norm:
            a = [x for x in a
                 if isinstance(x, dict)
                 and _norm_name(x.get("name")) != self_norm]
        return a[:3]
    payload = {
        "branch": branch,
        "generated": generated,
        "records_considered": len(records),
        "top_n": top_n,
        "tools": [
            {
                "rank":             i + 1,
                "tool_name":        r.get("tool_name"),
                "composite_score":  r.get("composite_score"),
                "weblink":          r.get("weblink"),
                "summary":          r.get("summary"),
                "language":         r.get("language"),
                "license":          r.get("license"),
                "last_release":     r.get("last_release"),
                "metrics":          r.get("metrics"),
                "url":              r.get("url"),
                "alternatives":     _alts(r),
                "ranking_winner":   r.get("ranking_winner"),
            }
            for i, r in enumerate(deduped)
        ],
    }
    return json.dumps(payload, indent=2)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--jsonl", required=True, help="cybersecurity_tools.jsonl path")
    ap.add_argument("--url-map", required=True, help="urls-by-branch.json path")
    ap.add_argument("--out-dir", required=True, help="output directory")
    ap.add_argument("--branches", default="3.0,4.0,5.0,6.0,common,dev,master",
                    help="comma-separated branches to render")
    ap.add_argument("--top-n", type=int, default=10)
    ap.add_argument("--stamp", default=dt.datetime.now(dt.timezone.utc)
                    .strftime("%Y%m%d_%H%M%S"))
    args = ap.parse_args()

    if not os.path.isfile(args.jsonl):
        sys.stderr.write(f"error: jsonl not found: {args.jsonl}\n"); return 2
    if not os.path.isfile(args.url_map):
        sys.stderr.write(f"error: url-map not found: {args.url_map}\n"); return 2

    os.makedirs(args.out_dir, exist_ok=True)
    rows = load_jsonl(args.jsonl)

    with open(args.url_map, "r", encoding="utf-8") as fh:
        umap = json.load(fh)
    url_to_branches = umap.get("urls") or {}

    branches = [b.strip() for b in args.branches.split(",") if b.strip()]
    by_branch = build_per_branch_records(rows, url_to_branches, branches)

    generated = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    # Per-branch files
    for b in branches:
        recs = by_branch.get(b, [])
        for ext, renderer in (("md", render_markdown), ("txt", render_text), ("json", render_json)):
            text = renderer(b, recs, args.top_n, generated)
            out_path = os.path.join(args.out_dir,
                                    f"BranchSummary_{b}_{args.stamp}.{ext}")
            with open(out_path, "w", encoding="utf-8") as fh:
                fh.write(text + "\n")
            print(f"wrote {out_path}", file=sys.stderr)

    # Combined markdown for $GITHUB_STEP_SUMMARY (sent to stdout).
    combined = ["# Package Classifier — per-branch top-N\n",
                f"_Generated: {generated}_\n",
                f"Total classifier records: {len(rows)}\n"]
    for b in branches:
        recs = by_branch.get(b, [])
        deduped = sorted(dedup_by_tool(recs), key=composite_for_dedup, reverse=True)[:args.top_n]
        combined.append(f"\n## Branch `{b}` — top {min(args.top_n, len(deduped))} of {len(recs)} records\n")
        if not deduped:
            combined.append("_No records mapped to this branch._\n")
            continue
        combined.append("| # | Tool | Score | Resume | Top-3 alternatives |")
        combined.append("|---|---|---|---|---|")
        for i, r in enumerate(deduped, 1):
            name = (r.get("tool_name") or "(unnamed)").replace("|", r"\|")
            cs   = r.get("composite_score")
            cs_str = f"{cs}" if cs is not None else "n/a"
            sm   = truncate(r.get("summary"), 140).replace("|", r"\|")
            alts = r.get("alternatives") or []
            if isinstance(alts, dict):
                alts = [alts]
            elif not isinstance(alts, list):
                alts = []
            alts = alts[:3]
            alt_lines = []
            for j, a in enumerate(alts):
                aname = (a.get("name") or "?").replace("|", r"\|")
                acs   = a.get("composite_score", "?")
                alt_lines.append(f"{j+1}. {aname} ({acs})")
            alt_cell = "<br>".join(alt_lines) if alt_lines else "_(none)_"
            combined.append(f"| {i} | {name} | {cs_str} | {sm} | {alt_cell} |")
    print("\n".join(combined))
    return 0


if __name__ == "__main__":
    sys.exit(main())
