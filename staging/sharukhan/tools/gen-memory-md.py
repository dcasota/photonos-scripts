#!/usr/bin/env python3
"""Regenerate MEMORY.md from the memory database.

MEMORY.md is a VIEW, not a copy. Every fact in it is read from the database at
generation time, and the file states which database and at what point, so a
stale render is visible rather than silently authoritative.

This exists as a Python tool only until the Rust `sharukhan db render`
subcommand lands (Task 013); the SQL is identical either way.
"""
import sqlite3, sys, datetime, os

SEV = {"blocker": 0, "high": 1, "medium": 2, "low": 3}

def main(db_path: str, out_path: str) -> int:
    if not os.path.exists(db_path):
        print(f"FAIL: no database at {db_path}", file=sys.stderr)
        return 3
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    findings = db.execute(
        "SELECT slug,title,category,severity,evidence,consequence,mitigation,verified,source"
        " FROM finding WHERE superseded_by IS NULL").fetchall()
    findings.sort(key=lambda r: (SEV.get(r[3], 9), r[2], r[0]))

    runs = db.execute("SELECT COUNT(*) FROM run").fetchone()[0]
    perms = db.execute("SELECT COUNT(*) FROM permutation").fetchone()[0]
    checks = db.execute("SELECT COUNT(*) FROM check_result").fetchone()[0]
    arts = db.execute("SELECT COUNT(*) FROM artifact").fetchone()[0]
    open_blockers = db.execute(
        "SELECT COUNT(*) FROM finding WHERE severity='blocker' AND verified=0").fetchone()[0]

    L = []
    L.append("# MEMORY.md")
    L.append("")
    L.append("**Generated. Do not edit.** This file is a rendering of the sharukhan memory")
    L.append("database; the database is the system of record. Editing here changes nothing and")
    L.append("will be overwritten on the next render.")
    L.append("")
    L.append(f"- Source database: `{db_path}`")
    L.append(f"- Rendered at: {now}")
    L.append(f"- Regenerate with: `python3 tools/gen-memory-md.py {db_path} MEMORY.md`")
    L.append("")
    L.append("| Table | Rows |")
    L.append("|---|---|")
    L.append(f"| `run` | {runs} |")
    L.append(f"| `permutation` | {perms} |")
    L.append(f"| `check_result` | {checks} |")
    L.append(f"| `artifact` | {arts} |")
    L.append(f"| `finding` | {len(findings)} |")
    L.append("")
    if open_blockers:
        L.append(f"> **{open_blockers} unresolved blocker finding(s).** See the Blocker section.")
        L.append("")

    # permutation report, straight from the view so it cannot drift from the CLI
    rows = db.execute(
        "SELECT perm_id,iso_type,poi,stig,fs,mode,doc_verdict,result,failed_checks,prs_implicated"
        " FROM v_permutation_report ORDER BY perm_id").fetchall()
    L.append("## Permutation results")
    L.append("")
    if not rows:
        L.append("_No permutation has completed yet._")
    else:
        L.append("| ID | ISO | POI | STIG | FS | Mode | Matrix said | Result | Failed | PRs implicated |")
        L.append("|---|---|---|---|---|---|---|---|---|---|")
        for r in rows:
            L.append("| " + " | ".join("" if c is None else str(c) for c in r) + " |")
        L.append("")
        L.append("A result that reproduces the *Matrix said* value of `fails` is a PR regression.")
    L.append("")

    cur_sev = None
    L.append("## Findings")
    L.append("")
    for slug, title, cat, sev, ev, cons, mit, ver, src in findings:
        if sev != cur_sev:
            cur_sev = sev
            L.append(f"### {sev.capitalize()}")
            L.append("")
        flag = "verified" if ver else "**UNRESOLVED**"
        L.append(f"#### `{slug}` — {title}")
        L.append("")
        L.append(f"*{cat} · {flag}*" + (f" · source: `{src}`" if src else ""))
        L.append("")
        L.append(f"**Observed.** {ev}")
        L.append("")
        L.append(f"**Consequence.** {cons}")
        if mit:
            L.append("")
            L.append(f"**Mitigation.** {mit}")
        L.append("")

    # control integrity: a run whose negative controls passed proves nothing
    ci = db.execute("SELECT perm_id,controls,controls_ok FROM v_control_integrity"
                    " WHERE controls > 0 ORDER BY perm_id").fetchall()
    if ci:
        L.append("## Negative-control integrity")
        L.append("")
        L.append("A permutation whose controls did not all hold is **inconclusive**, not passing.")
        L.append("")
        L.append("| Permutation | Controls | Held |")
        L.append("|---|---|---|")
        for p, c, ok in ci:
            L.append(f"| {p} | {c} | {ok} |")
        L.append("")

    open(out_path, "w").write("\n".join(L) + "\n")
    print(f"  rendered {out_path}: {len(findings)} findings, {len(rows)} permutation rows")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: gen-memory-md.py <memory.db> <MEMORY.md>", file=sys.stderr)
        sys.exit(64)
    sys.exit(main(sys.argv[1], sys.argv[2]))
