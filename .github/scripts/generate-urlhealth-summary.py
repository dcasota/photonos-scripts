#!/usr/bin/env python3
"""Generate a per-branch URL health issue summary from photonos-urlhealth .prn files.

Usage:
    python3 generate-urlhealth-summary.py <scans_dir>

For every photonos-urlhealth-*.prn file in <scans_dir>, the script picks the
latest (by timestamp in the filename) per branch, analyses its contents, and
writes a companion .md issue report next to the .prn file.

Output filename pattern:
    photonos-urlhealth-issues-<branch>_<timestamp>.md
"""

import csv
import os
import re
import sys
from collections import defaultdict


def find_latest_urlhealth_prns(scans_dir):
    """Return dict {branch: filepath} keeping only the latest .prn per branch."""
    pattern = re.compile(
        r"^photonos-urlhealth-([A-Za-z0-9._-]+)_(\d{12})\.prn$"
    )
    latest = {}
    for name in os.listdir(scans_dir):
        m = pattern.match(name)
        if not m:
            continue
        branch, ts = m.group(1), m.group(2)
        path = os.path.join(scans_dir, name)
        if branch not in latest or ts > latest[branch][0]:
            latest[branch] = (ts, path)
    return {b: v[1] for b, v in latest.items()}


def classify_row(uh, ua, uurl, huurl, udn, warn):
    """Return the category key for one .prn row, or None if healthy.

    Single source of the issue taxonomy: both the per-branch report
    (analyse_prn) and the cross-branch aggregate (aggregate_matrix) call
    this, so the two views can never drift apart.
    """
    if uh == "":
        return "cat1_url_blank"
    if uh == "substitution_unfinished":
        return "cat2_substitution"
    if uh == "0":
        return "cat3_unreachable"
    if (uh == "200" and ua and not ua.startswith("Warning:")
            and ua != "(same version)" and huurl == "200" and not udn):
        return "cat4_update_200_nodownload"
    if uh == "200" and ua and ua.startswith("Warning:"):
        return "cat5_version_warning"
    if uh == "200" and not ua and not warn:
        return "cat6_no_update_info"
    if (uh == "200" and ua and not ua.startswith("Warning:")
            and ua != "(same version)" and not huurl):
        return "cat7_update_nohealth"
    if warn:
        return "cat8_warnings"
    return None


def analyse_prn(filepath):
    """Parse a .prn CSV and return (total, categories_dict)."""
    categories = defaultdict(list)
    total = 0

    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            next(reader)  # skip header
        except StopIteration:
            return 0, categories

        for row in reader:
            total += 1
            while len(row) < 12:
                row.append("")
            (spec, src0, mod_src0, uh, ua, uurl,
             huurl, name, sha, udn, warn, adate) = (c.strip() for c in row[:12])

            entry = dict(
                spec=spec, name=name, url_health=uh,
                update_available=ua, update_url=uurl,
                health_update_url=huurl, update_download_name=udn,
                warning=warn, source0=src0, modified_source0=mod_src0,
            )

            key = classify_row(uh, ua, uurl, huurl, udn, warn)
            if key:
                categories[key].append(entry)

    return total, categories


CAT_META = [
    ("cat1_url_blank",
     "Source URL blank / macro unresolved (UrlHealth=blank)", "High"),
    ("cat2_substitution",
     "URL substitution unfinished", "High"),
    ("cat3_unreachable",
     "Source URL unreachable (UrlHealth=0)", "High"),
    ("cat4_update_200_nodownload",
     "Update reachable (HealthUpdateURL=200) but UpdateDownloadName blank", "Medium"),
    ("cat5_version_warning",
     "Version comparison anomaly (UpdateAvailable contains Warning)", "Medium"),
    ("cat6_no_update_info",
     "Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank", "Medium"),
    ("cat7_update_nohealth",
     "Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed)", "Medium"),
    ("cat8_warnings",
     "Other warnings (VMware internal URL, unmaintained repo, etc.)", "Low-Medium"),
]

# Display number (1..8) per category key, matching the per-branch report's
# numbered "## N." sections. cat4 keeps its slot even when unused.
CAT_NUM = {key: i for i, (key, _label, _sev) in enumerate(CAT_META, 1)}

# Severity colour marker. GitHub markdown (job summaries + .md) strips inline
# CSS/HTML, so a coloured-circle emoji is the only way to colour a table cell.
SEV_EMOJI = {"High": "\U0001F534", "Medium": "\U0001F7E0", "Low-Medium": "\U0001F7E1"}
_NUM_SEV = {i: sev for i, (_k, _l, sev) in enumerate(CAT_META, 1)}
_SEV_RANK = {"High": 3, "Medium": 2, "Low-Medium": 1}
_HEALTHY_MARK = "\U0001F7E2"   # green circle
_NA_MARK = "⚪"            # white circle


def _sev_marker(nums):
    """Colour marker for a cell = highest severity among its categories."""
    sev = max((_NUM_SEV.get(n, "Medium") for n in nums),
              key=lambda s: _SEV_RANK.get(s, 0))
    return SEV_EMOJI.get(sev, "")

# Branch column order for the cross-branch matrix. Subrelease columns
# (e.g. 5.0/SPECS/91) are inserted right after their parent branch.
_BRANCH_ORDER = ["3.0", "4.0", "5.0", "6.0", "common", "dev", "master", "main"]
_SUBRELEASE_RE = re.compile(r"subrelease\s+(\d+)", re.IGNORECASE)


def aggregate_matrix(latest):
    """Build the cross-branch view from the latest .prn per branch.

    Returns (issue, present):
      issue[spec][col]  -> set of category numbers (1..8)
      present[col]      -> set of specs present in that column (any health)
    A 5.0 row whose warning says "(subrelease NN)" is routed to the
    synthetic column "5.0/SPECS/NN" instead of "5.0".
    """
    issue = defaultdict(lambda: defaultdict(set))
    present = defaultdict(set)
    for branch in latest:
        with open(latest[branch], newline="", encoding="utf-8") as f:
            reader = csv.reader(f)
            next(reader, None)  # header
            for row in reader:
                while len(row) < 12:
                    row.append("")
                (spec, _src0, _mod, uh, ua, uurl,
                 huurl, _name, _sha, udn, warn, _adate) = (c.strip() for c in row[:12])
                if not spec.endswith(".spec"):
                    continue
                col = branch
                m = _SUBRELEASE_RE.search(warn or "")
                if m:
                    col = f"{branch}/SPECS/{m.group(1)}"
                present[col].add(spec)
                key = classify_row(uh, ua, uurl, huurl, udn, warn)
                if key:
                    issue[spec][col].add(CAT_NUM[key])
    return issue, present


def order_columns(present):
    """Order columns by _BRANCH_ORDER, each parent branch immediately
    followed by its SPECS/NN subrelease columns; unknown branches last."""
    allcols = set(present)
    cols = []
    for b in _BRANCH_ORDER:
        if b in allcols:
            cols.append(b)
        cols.extend(sorted(c for c in allcols if c.startswith(b + "/SPECS/")))
    for c in sorted(allcols):
        if c not in cols:
            cols.append(c)
    return cols


def write_matrix_and_categories(out, issue, present):
    """Write the spec-matrix and the category->affected-packages tables."""
    cols = order_columns(present)
    specs = sorted(issue.keys())

    def cell(s, c):
        if c in issue.get(s, {}):
            nums = sorted(issue[s][c])
            return _sev_marker(nums) + ",".join(str(n) for n in nums)
        return _HEALTHY_MARK if s in present[c] else _NA_MARK

    out.write("## Spec-matrix — issue applicability per branch\n\n")
    out.write(f"**{len(specs)}** packages with at least one issue across "
              f"{len([c for c in cols if '/' not in c])} branches.\n\n")
    out.write("Cell legend: severity colour + issue category number(s) — "
              f"{SEV_EMOJI['High']} High (1,2,3) · {SEV_EMOJI['Medium']} Medium "
              f"(4,5,6,7) · {SEV_EMOJI['Low-Medium']} Low-Medium (8) · "
              f"{_HEALTHY_MARK} present & URL health OK · {_NA_MARK} not carried "
              "in that branch/subrelease.\n\n")
    out.write("| Spec | " + " | ".join(cols) + " |\n")
    out.write("|---|" + "|".join(["---"] * len(cols)) + "|\n")
    for s in specs:
        out.write("| " + s + " | " + " | ".join(cell(s, c) for c in cols) + " |\n")
    out.write("\n")

    # category number -> set of affected specs (across all columns)
    cat_specs = defaultdict(set)
    for s, bycol in issue.items():
        for nums in bycol.values():
            for n in nums:
                cat_specs[n].add(s)
    num2meta = {i: (label, sev) for i, (_k, label, sev) in enumerate(CAT_META, 1)}

    out.write("## Issue categories — affected packages\n\n")
    out.write("| # | Issue Category | Severity | Packages | Affected specs |\n")
    out.write("|---|---|---|---|---|\n")
    for n in sorted(cat_specs):
        label, sev = num2meta.get(n, ("?", "?"))
        pkgs = ", ".join(sorted(cat_specs[n]))
        out.write(f"| {n} | {label} | {SEV_EMOJI.get(sev, '')} {sev} | {len(cat_specs[n])} | {pkgs} |\n")
    out.write("\n")


def _fix_for_warning(w):
    if "VMware internal url" in w:
        return "Source0 points to a VMware internal URL. Provide a public upstream URL if available."
    if "maintained" in w:
        return ("Upstream repo is no longer maintained. Consider finding a fork, "
                "alternative, or mark package as archived.")
    if "Cannot detect correlating tags" in w:
        return "Tag detection failed. Check if upstream uses a different tagging convention."
    if "version packaging format" in w:
        return ("Manufacturer may have changed version packaging format. "
                "Verify the download URL pattern still works with current releases.")
    if "seems invalid" in w:
        return "Source0 URL appears invalid and no official source found. Find the correct upstream URL."
    if "duplicate" in w:
        return "This spec may be a duplicate. Consider consolidating with the referenced spec."
    return "Review warning and take appropriate action."


def write_report(out, branch, prn_path, total, cats):
    issue_specs = set()
    for entries in cats.values():
        for e in entries:
            issue_specs.add(e["spec"])

    prn_name = os.path.basename(prn_path)
    out.write(f"# Photon OS URL Health Issues - branch {branch}\n\n")
    out.write(f"**Source file:** {prn_name}\n\n")
    out.write(f"**Total packages analyzed:** {total}\n\n")
    out.write(f"**Total packages with issues:** {len(issue_specs)}\n\n")

    # Summary table
    out.write("## Summary\n\n")
    out.write("| # | Issue Category | Count | Severity |\n")
    out.write("|---|---|---|---|\n")
    for i, (key, label, sev) in enumerate(CAT_META, 1):
        cnt = len(cats.get(key, []))
        if cnt > 0:
            out.write(f"| {i} | {label} | {cnt} | {sev} |\n")
    out.write("\n---\n\n")

    # ---- Category 1 ----
    entries = sorted(cats.get("cat1_url_blank", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 1. Source URL Blank / Macro Unresolved (UrlHealth=blank)\n\n")
        out.write("The Source0 URL contains unexpanded RPM macros or is empty.\n\n")
        out.write("| # | Spec | Name | Source0 Original | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            w = e["warning"]
            if w:
                fix = f"Warning: {w}. Check if a public upstream URL exists."
            else:
                fix = ("Verify Source0 URL macro expansion. The %{version} or %{name} macro "
                       "may not resolve. Provide a direct URL or fix the macro.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | `{e['source0'][:120]}` | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 2 ----
    entries = sorted(cats.get("cat2_substitution", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 2. URL Substitution Unfinished\n\n")
        out.write("| # | Spec | Name | Source0 Original | Modified Source0 | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            fix = ("Fix the Source0 URL pattern. The version/name substitution is incomplete "
                   "-- check for nested or malformed macros.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | `{e['source0'][:80]}` "
                      f"| `{e['modified_source0'][:80]}` | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 3 ----
    entries = sorted(cats.get("cat3_unreachable", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 3. Source URL Unreachable (UrlHealth=0)\n\n")
        out.write("| # | Spec | Name | Modified Source0 | Warning | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            src = e["modified_source0"] or e["source0"]
            fix = ("URL is unreachable. Check if the domain/host is still active. "
                   "Find an alternative mirror or upstream source.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | `{src[:100]}` | {e['warning']} | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 4 ----
    entries = sorted(cats.get("cat4_update_200_nodownload", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 4. Update Reachable (HealthUpdateURL=200) but UpdateDownloadName Blank\n\n")
        out.write("| # | Spec | Name | Update Available | Update URL | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            uurl = e["update_url"][:100] if e["update_url"] else "(blank)"
            fix = ("Update URL is valid (HTTP 200) but download artifact name unresolved. "
                   "Check if the release asset naming pattern matches expectations or "
                   "if the URL resolves to a redirect/HTML page.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | {e['update_available']} "
                      f"| `{uurl}` | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 5 ----
    entries = sorted(cats.get("cat5_version_warning", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 5. Version Comparison Anomaly\n\n")
        out.write("| # | Spec | Name | Version Warning | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            fix = ("Version comparison heuristic may be confused by version format "
                   "(date-based, alpha suffixes, etc.). Verify manually.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | {e['update_available']} | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 6 ----
    entries = sorted(cats.get("cat6_no_update_info", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)\n\n")
        out.write("| # | Spec | Name | Modified Source0 | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            src = e["modified_source0"] or e["source0"]
            fix = ("Source URL works but update detection found no newer version. "
                   "May be correct or the version detection pattern does not match "
                   "upstream release naming. Verify manually.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | `{src[:100]}` | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 7 ----
    entries = sorted(cats.get("cat7_update_nohealth", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 7. Update Version Detected but Update URL Not Constructed "
                  "(Packaging Format Changed)\n\n")
        out.write("| # | Spec | Name | Update Available | Warning | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            fix = ("Upstream changed version/packaging format. Update the Source0 URL pattern "
                   "in the spec to match the new release naming convention.")
            out.write(f"| {i} | {e['spec']} | {e['name']} | {e['update_available']} "
                      f"| {e['warning']} | {fix} |\n")
        out.write("\n---\n\n")

    # ---- Category 8 ----
    entries = sorted(cats.get("cat8_warnings", []), key=lambda x: x["spec"])
    if entries:
        out.write("## 8. Other Warnings\n\n")
        out.write("| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |\n")
        out.write("|---|---|---|---|---|---|---|\n")
        for i, e in enumerate(entries, 1):
            fix = _fix_for_warning(e["warning"])
            out.write(f"| {i} | {e['spec']} | {e['name']} | {e['url_health']} "
                      f"| {e['update_available']} | {e['warning']} | {fix} |\n")
        out.write("\n")


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <scans_dir>", file=sys.stderr)
        sys.exit(1)

    scans_dir = sys.argv[1]
    if not os.path.isdir(scans_dir):
        print(f"Error: '{scans_dir}' is not a directory", file=sys.stderr)
        sys.exit(1)

    latest = find_latest_urlhealth_prns(scans_dir)
    if not latest:
        print("No photonos-urlhealth-*.prn files found.")
        return

    generated = []
    for branch in sorted(latest):
        prn_path = latest[branch]
        prn_name = os.path.basename(prn_path)
        ts_match = re.search(r"_(\d{12})\.prn$", prn_name)
        ts = ts_match.group(1) if ts_match else "unknown"

        total, cats = analyse_prn(prn_path)

        issue_count = len({e["spec"] for entries in cats.values() for e in entries})
        if issue_count == 0:
            print(f"  {branch}: {total} packages, 0 issues -- skipping .md")
            continue

        md_name = f"photonos-urlhealth-issues-{branch}_{ts}.md"
        # Defensive: branch is captured by [A-Za-z0-9._-]+ from a filename
        # in scans_dir, so it cannot contain "/" -- but confirm the
        # resolved write target still lives under scans_dir before opening.
        # (Closes Snyk SAST path-traversal taint warning.)
        md_path = os.path.join(scans_dir, md_name)
        scans_real = os.path.realpath(scans_dir)
        md_real    = os.path.realpath(md_path)
        if os.path.commonpath([scans_real, md_real]) != scans_real:
            raise ValueError(f"Refusing to write outside scans_dir: {md_path}")

        with open(md_real, "w", encoding="utf-8") as out:
            write_report(out, branch, prn_path, total, cats)

        print(f"  {branch}: {total} packages, {issue_count} issues -> {md_name}")
        generated.append(md_name)

    # --- Cross-branch aggregate: spec-matrix + category-affected tables ---
    # Reads every branch's latest .prn (not just the per-branch .md inputs),
    # so the matrix sees healthy/N-A cells too. Written as an artifact .md and
    # appended to the GitHub Actions job summary (the dynamic report).
    issue, present = aggregate_matrix(latest)
    if issue:
        ts_all = [m.group(1) for p in latest.values()
                  for m in [re.search(r"_(\d{12})\.prn$", os.path.basename(p))] if m]
        ts = max(ts_all) if ts_all else "unknown"
        matrix_name = f"photonos-urlhealth-issues-matrix_{ts}.md"
        matrix_path = os.path.join(scans_dir, matrix_name)
        scans_real = os.path.realpath(scans_dir)
        if os.path.commonpath([scans_real, os.path.realpath(matrix_path)]) != scans_real:
            raise ValueError(f"Refusing to write outside scans_dir: {matrix_path}")
        with open(matrix_path, "w", encoding="utf-8") as out:
            out.write("# Photon OS URL Health - cross-branch matrix\n\n")
            write_matrix_and_categories(out, issue, present)
        generated.append(matrix_name)
        print(f"  matrix: {len(issue)} specs with issues -> {matrix_name}")

        gh = os.environ.get("GITHUB_STEP_SUMMARY")
        if gh:
            with open(gh, "a", encoding="utf-8") as out:
                out.write("\n# URL health - spec-matrix & issue categories\n\n")
                write_matrix_and_categories(out, issue, present)

    print(f"\nGenerated {len(generated)} issue summary file(s).")


if __name__ == "__main__":
    main()
