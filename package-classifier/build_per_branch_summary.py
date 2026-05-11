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


def pkg_name(record: dict) -> str:
    """Photon-side display name for a record.

    Prefers `_pkg_name` (derived from the Photon SPEC filename, e.g.
    `perl-WWW-Curl` from `perl-WWW-Curl.spec`) so the report shows the
    Photon package identity rather than Grok's upstream tool name (e.g.
    `WWW::Curl`). Falls back to `tool_name` when no SPEC mapping exists
    (e.g. records sourced from URLs not in url_to_packages).
    """
    return record.get("_pkg_name") or record.get("tool_name") or "(unnamed)"


def dedup_by_tool(records: list[dict]) -> list[dict]:
    """Keep the highest-composite record per normalized Photon package name
    (SPEC-derived) -- so two SPECs with the same upstream tool name remain
    distinct, and two URLs of the same SPEC collapse together."""
    by_key: dict[str, dict] = {}
    for r in records:
        key = _norm_name(pkg_name(r))
        if not key:
            continue
        if key not in by_key or composite_for_dedup(r) > composite_for_dedup(by_key[key]):
            by_key[key] = r
    return list(by_key.values())


def clean_alts(record: dict, top: int = 3) -> list[dict]:
    """Return up to `top` alternatives for a record, with the package itself
    filtered out and the remainder sorted by composite_score (desc).

    Grok regularly returns the package itself as a candidate inside its own
    alternatives ranking pool (observed for Python, requests, pydantic,
    PyJWT, etc.). That entry is not an "alternative" and must not appear in
    any of the rendered tables. Centralised here so per-branch and combined
    renderers behave identically.
    """
    alts = record.get("alternatives") or []
    # PowerShell ConvertTo-Json serialises a single-element array as a bare
    # object instead of a 1-element list. Coerce back.
    if isinstance(alts, dict):
        alts = [alts]
    elif not isinstance(alts, list):
        alts = []
    self_norm = _norm_name(record.get("tool_name"))
    if self_norm:
        alts = [a for a in alts
                if isinstance(a, dict)
                and _norm_name(a.get("name")) != self_norm]
    try:
        alts = sorted(alts, key=composite_for_dedup, reverse=True)
    except Exception:
        pass
    return alts[:top]


def alts_beating_self(record: dict) -> list[dict]:
    """Return alternatives whose composite_score is strictly greater than the
    package's own. Self-named entries are filtered out. Sorted by score desc.

    Used for the "Alternatives outscoring the package" branch section: for
    each package, surface every alternative where the dynamic ranking says
    the alternative beats the incumbent.
    """
    pkg_score = composite_for_dedup(record)
    if pkg_score < 0:
        return []
    alts = record.get("alternatives") or []
    if isinstance(alts, dict):
        alts = [alts]
    elif not isinstance(alts, list):
        return []
    self_norm = _norm_name(record.get("tool_name"))
    out = []
    for a in alts:
        if not isinstance(a, dict):
            continue
        if self_norm and _norm_name(a.get("name")) == self_norm:
            continue
        if composite_for_dedup(a) > pkg_score:
            out.append(a)
    return sorted(out, key=composite_for_dedup, reverse=True)


def build_better_alt_rows(records: list[dict]) -> list[dict]:
    """For every dedup'd record in `records`, emit one row per alternative
    that outscores the package. Sorted by score delta (desc) -- biggest
    gaps surface first. A package legitimately appears in multiple rows
    when it has multiple alternatives beating it (e.g. Apache Commons
    HttpClient -> OkHttp +53.5 AND Apache HttpComponents Client +50.7).
    """
    deduped = dedup_by_tool(records)
    rows = []
    for r in deduped:
        display   = pkg_name(r)
        pkg_score = composite_for_dedup(r)
        for a in alts_beating_self(r):
            a_score = composite_for_dedup(a)
            rows.append({
                "package":         display,
                "package_score":   r.get("composite_score"),
                "alt_name":        a.get("name") or "(unnamed)",
                "alt_score":       a.get("composite_score"),
                "alt_weblink":     a.get("weblink") or "",
                "delta":           round(a_score - pkg_score, 1),
                "rationale":       a.get("rationale") or "",
            })
    return sorted(rows, key=lambda r: r["delta"], reverse=True)


def _as_list(value) -> list:
    """Coerce a sidecar value to a list.

    PowerShell's ConvertTo-Json serializes a 1-element array as a bare
    scalar -- so the sidecar JSON returns a string when a URL maps to
    exactly one branch or package. Iterating it char-by-char ("spdlog"
    -> ['s','p',...]) corrupted the displayed package name and silently
    dropped single-branch URLs from per-branch records (run 25641789908
    showed packages as single characters). Normalize to a real list.
    """
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def build_per_branch_records(jsonl_rows: list[dict],
                             url_to_branches: dict[str, list[str]],
                             branches: list[str],
                             url_to_packages: dict[str, list[str]] | None = None
                             ) -> dict[str, list[dict]]:
    """Map each record to the branches it belongs to. Also enriches the
    record with `_pkg_name` (the Photon SPEC-derived name) when the URL
    has a matching entry in `url_to_packages` — used by `pkg_name()` for
    display and dedup."""
    url_to_packages = url_to_packages or {}
    by_branch: dict[str, list[dict]] = defaultdict(list)
    for rec in jsonl_rows:
        url = rec.get("url")
        if not url:
            continue
        if not rec.get("_pkg_name"):
            pkgs = _as_list(url_to_packages.get(url))
            if pkgs:
                rec["_pkg_name"] = pkgs[0]
        for b in _as_list(url_to_branches.get(url)):
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
        name   = pkg_name(r)
        cs     = r.get("composite_score")
        cs_str = f"{cs}" if cs is not None else "n/a"
        weblink = r.get("weblink") or ""
        summary = truncate(r.get("summary"), 220)
        out.append(f"### {i}. {name} — composite_score {cs_str}")
        if weblink:
            out.append(f"[{weblink}]({weblink})  ")
        out.append(f"**Resume:** {summary}")
        top3 = clean_alts(r, 3)
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

    # Branch-wide cross-cut: every alternative across all packages in this
    # branch that beats its incumbent. Independent of the top-N filter.
    better_rows = build_better_alt_rows(records)
    out.append("## Alternatives outscoring the package")
    out.append("")
    if not better_rows:
        out.append("_No alternative beats its package in this branch._")
    else:
        out.append(f"_{len(better_rows)} alternative(s) score higher than the corresponding package._")
        out.append("")
        out.append("| # | Package | Pkg score | Alternative | Alt score | Δ | Rationale |")
        out.append("|---|---|---|---|---|---|---|")
        for k, row in enumerate(better_rows, 1):
            pkg = str(row["package"]).replace("|", r"\|")
            alt = str(row["alt_name"]).replace("|", r"\|")
            rat = truncate(row["rationale"], 140).replace("|", r"\|")
            out.append(f"| {k} | {pkg} | {row['package_score']} | {alt} | {row['alt_score']} | +{row['delta']} | {rat} |")
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
        name = pkg_name(r)
        cs   = r.get("composite_score")
        cs_str = f"{cs}" if cs is not None else "n/a"
        out.append(f"{i:>2}. {name}  --  composite_score {cs_str}")
        wl = r.get("weblink") or ""
        if wl:
            out.append(f"    {wl}")
        out.append(f"    Resume: {truncate(r.get('summary'), 200)}")
        top3 = clean_alts(r, 3)
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

    # Branch-wide cross-cut: every alternative across all packages in this
    # branch that beats its incumbent. Independent of the top-N filter.
    better_rows = build_better_alt_rows(records)
    out.append("Alternatives outscoring the package")
    if not better_rows:
        out.append("  (none)")
    else:
        out.append(f"  {len(better_rows)} alternative(s) score higher than the corresponding package.")
        for k, row in enumerate(better_rows, 1):
            rat = truncate(row["rationale"], 140)
            line = (f"  {k:>3}. {row['package']} ({row['package_score']})"
                    f"  ->  {row['alt_name']} ({row['alt_score']}, +{row['delta']})")
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
        return clean_alts(r, 3)
    payload = {
        "branch": branch,
        "generated": generated,
        "records_considered": len(records),
        "top_n": top_n,
        "alternatives_outscoring_package": build_better_alt_rows(records),
        "tools": [
            {
                "rank":             i + 1,
                "package":          pkg_name(r),
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
    out_dir_real = os.path.realpath(args.out_dir)
    rows = load_jsonl(args.jsonl)

    # Canonicalize the input path so Snyk SAST can see we read a fixed
    # location, not raw argv.
    url_map_real = os.path.realpath(args.url_map)
    with open(url_map_real, "r", encoding="utf-8") as fh:
        umap = json.load(fh)
    url_to_branches = umap.get("urls") or {}
    url_to_packages = umap.get("url_to_packages") or {}

    branches = [b.strip() for b in args.branches.split(",") if b.strip()]
    by_branch = build_per_branch_records(rows, url_to_branches, branches, url_to_packages)

    generated = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    # Per-branch files. branch + stamp come from CLI, so sanitize the
    # filename components and confirm the resolved write target stays
    # inside out_dir before opening (Snyk SAST PT taint).
    import re as _re
    def _safe(s):
        return _re.sub(r"[^A-Za-z0-9._-]+", "_", str(s))
    for b in branches:
        recs = by_branch.get(b, [])
        for ext, renderer in (("md", render_markdown), ("txt", render_text), ("json", render_json)):
            text = renderer(b, recs, args.top_n, generated)
            out_name = f"BranchSummary_{_safe(b)}_{_safe(args.stamp)}.{_safe(ext)}"
            out_path = os.path.join(args.out_dir, out_name)
            out_real = os.path.realpath(out_path)
            if os.path.commonpath([out_dir_real, out_real]) != out_dir_real:
                raise ValueError(f"Refusing to write outside out_dir: {out_path}")
            with open(out_real, "w", encoding="utf-8") as fh:
                fh.write(text + "\n")
            print(f"wrote {out_real}", file=sys.stderr)

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
        combined.append("| # | Package | Score | Resume | Top-3 alternatives |")
        combined.append("|---|---|---|---|---|")
        for i, r in enumerate(deduped, 1):
            name = pkg_name(r).replace("|", r"\|")
            cs   = r.get("composite_score")
            cs_str = f"{cs}" if cs is not None else "n/a"
            sm   = truncate(r.get("summary"), 140).replace("|", r"\|")
            alts = clean_alts(r, 3)
            alt_lines = []
            for j, a in enumerate(alts):
                aname = (a.get("name") or "?").replace("|", r"\|")
                acs   = a.get("composite_score", "?")
                alt_lines.append(f"{j+1}. {aname} ({acs})")
            alt_cell = "<br>".join(alt_lines) if alt_lines else "_(none)_"
            combined.append(f"| {i} | {name} | {cs_str} | {sm} | {alt_cell} |")

        # Branch-wide cross-cut: alternatives outscoring their package.
        # Shown as a collapsible block to keep the run page navigable when
        # a branch has dozens of beating alternatives.
        better_rows = build_better_alt_rows(recs)
        combined.append("")
        combined.append(f"<details><summary><b>Alternatives outscoring the package</b> "
                        f"({len(better_rows)} found)</summary>")
        combined.append("")
        if not better_rows:
            combined.append("_No alternative beats its package in this branch._")
        else:
            combined.append("| # | Package | Pkg score | Alternative | Alt score | Δ | Rationale |")
            combined.append("|---|---|---|---|---|---|---|")
            for k, row in enumerate(better_rows, 1):
                pkg = str(row["package"]).replace("|", r"\|")
                alt = str(row["alt_name"]).replace("|", r"\|")
                rat = truncate(row["rationale"], 140).replace("|", r"\|")
                combined.append(f"| {k} | {pkg} | {row['package_score']} | {alt} | "
                                f"{row['alt_score']} | +{row['delta']} | {rat} |")
        combined.append("</details>")
    print("\n".join(combined))
    return 0


if __name__ == "__main__":
    sys.exit(main())
