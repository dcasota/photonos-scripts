#!/usr/bin/env python3
"""
Photon OS monthly commit summarizer.

Reads commits from photon_commits.db, groups by branch and month,
generates AI-powered summaries via the xAI/Grok API, and writes
Hugo-compatible blog posts.

Can be run standalone or invoked by the photon-summarize Factory skill.
"""

import os
import sys
import sqlite3
import requests
import json
import hashlib
import argparse
from datetime import datetime, timezone
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from db_schema import init_db as schema_init_db

try:
    from tqdm import tqdm
except ImportError:
    import subprocess
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'tqdm'],
                   check=True, capture_output=True)
    from tqdm import tqdm

DEFAULT_BRANCHES = ['3.0', '4.0', '5.0', '6.0', 'common', 'master']
XAI_API_URL = 'https://api.x.ai/v1/chat/completions'
BATCH_SIZE = 20
REPO_COMMIT_URL = 'https://github.com/vmware/photon/commit'

SYSTEM_PROMPT = """\
You are a technical writer producing scannable, user-friendly monthly \
changelogs for Photon OS. Follow these rules strictly:

1. Use bullet points (- ) for EVERY individual change. Never write dense \
   paragraphs. One change per bullet.
2. For every commit reference, use a Markdown link: \
   [short description](https://github.com/vmware/photon/commit/<full_hash>). \
   Never put bare hashes inline in prose.
3. Use Keep a Changelog categories: Added, Changed, Fixed, Security, Removed.
4. Start with a 3-sentence TL;DR, then an Action Required callout.
5. Write for an external alliance partner audience, not kernel developers. \
   Explain WHY a change matters, not just what changed.
6. Do NOT include a "Looking Ahead" section. Do not speculate about future \
   development.\
"""


def query_grok(prompt, api_key, model='grok-4-0709', max_tokens=16384):
    """Send a prompt to the xAI/Grok API and return the response text."""
    payload = {
        'model': model,
        'messages': [
            {'role': 'system', 'content': SYSTEM_PROMPT},
            {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
        'max_tokens': max_tokens,
    }
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Content-Type': 'application/json',
    }
    response = requests.post(XAI_API_URL, headers=headers, json=payload)
    response.raise_for_status()
    return response.json()['choices'][0]['message']['content'].strip()


def has_summary(cur, branch, year, month):
    """Return True if a summary already exists for this branch/year/month."""
    cur.execute(
        'SELECT 1 FROM summaries WHERE branch = ? AND year = ? AND month = ?',
        (branch, year, month))
    return cur.fetchone() is not None


def store_summary(conn, branch, year, month, commit_count, model,
                  file_path, changelog_md):
    """Insert or replace a changelog in the summaries table."""
    now = datetime.now(timezone.utc).isoformat()
    conn.execute("""
        INSERT INTO summaries (branch, year, month, commit_count, model,
                               file_path, changelog_md, generated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(branch, year, month) DO UPDATE SET
            commit_count = excluded.commit_count,
            model = excluded.model,
            file_path = excluded.file_path,
            changelog_md = excluded.changelog_md,
            generated_at = excluded.generated_at
    """, (branch, year, month, commit_count, model, file_path, changelog_md,
          now))
    conn.commit()


def check_summaries(db_path, branches):
    """Report summaries table status. Returns JSON-serialisable dict."""
    status = {'db_path': db_path, 'exists': os.path.exists(db_path),
              'branches': {}, 'total': 0}
    if not status['exists']:
        return status
    conn, cur = schema_init_db(db_path)
    for branch in branches:
        cur.execute("""
            SELECT year, month, commit_count, model,
                   length(changelog_md), file_path, generated_at
            FROM summaries WHERE branch = ?
            ORDER BY year, month
        """, (branch,))
        rows = cur.fetchall()
        entries = []
        for r in rows:
            entries.append({
                'period': f'{r[0]}-{r[1]:02d}',
                'commits': r[2], 'model': r[3],
                'md_bytes': r[4], 'file_path': r[5],
                'generated_at': r[6],
            })
        status['branches'][branch] = {
            'count': len(entries),
            'entries': entries,
        }
        status['total'] += len(entries)
    conn.close()
    return status


def export_summaries(db_path, output_dir, branches):
    """Write all changelogs from DB to disk. Returns manifest dict."""
    conn, cur = schema_init_db(db_path)
    manifest = {'exported': [], 'errors': []}
    for branch in branches:
        cur.execute("""
            SELECT year, month, changelog_md
            FROM summaries WHERE branch = ?
            ORDER BY year, month
        """, (branch,))
        for year, month, changelog_md in cur.fetchall():
            file_dir = os.path.join(output_dir, str(year), f'{month:02d}')
            os.makedirs(file_dir, exist_ok=True)
            file_path = os.path.join(
                file_dir, f'photon-{branch}-monthly-{year}-{month:02d}.md')
            try:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(changelog_md)
                conn.execute(
                    'UPDATE summaries SET file_path = ? '
                    'WHERE branch = ? AND year = ? AND month = ?',
                    (file_path, branch, year, month))
                manifest['exported'].append(file_path)
                print(f'Exported: {file_path}', file=sys.stderr)
            except Exception as exc:
                manifest['errors'].append(f'{branch}/{year}-{month:02d}: {exc}')
    conn.commit()
    conn.close()
    return manifest


def sync_check(db_path, branches):
    """Compare DB changelogs against files on disk. Returns drift report."""
    conn, cur = schema_init_db(db_path)
    report = {'in_sync': [], 'file_missing': [], 'content_mismatch': [],
              'orphan_in_db': []}
    for branch in branches:
        cur.execute("""
            SELECT year, month, file_path, changelog_md
            FROM summaries WHERE branch = ?
        """, (branch,))
        for year, month, file_path, changelog_md in cur.fetchall():
            key = f'{branch}/{year}-{month:02d}'
            if not file_path or not os.path.exists(file_path):
                report['file_missing'].append(key)
                continue
            with open(file_path, 'r', encoding='utf-8') as f:
                disk_content = f.read()
            db_hash = hashlib.sha256(changelog_md.encode()).hexdigest()[:12]
            disk_hash = hashlib.sha256(disk_content.encode()).hexdigest()[:12]
            if db_hash == disk_hash:
                report['in_sync'].append(key)
            else:
                report['content_mismatch'].append({
                    'key': key, 'db_hash': db_hash, 'disk_hash': disk_hash})
    conn.close()
    return report


def get_single_summary(branch, year, month, commits, api_key, model,
                       is_batch=False):
    """Summarize a single batch of commits."""
    batch_label = ' (batch)' if is_batch else ''
    commits_str = ''
    for c in commits:
        commits_str += f"Commit Hash: {c['commit_hash']}\n"
        commits_str += f"Date: {c['commit_datetime']}\n"
        commits_str += f"Change-ID: {c.get('change_id', 'N/A')}\n"
        commits_str += f"Message: {c['message']}\n"
        commits_str += f"Signed-off-by: {c.get('signed_off_by', 'N/A')}\n"
        commits_str += f"Reviewed-on: {c.get('reviewed_on', 'N/A')}\n"
        commits_str += f"Reviewed-by: {c.get('reviewed_by', 'N/A')}\n"
        commits_str += f"Tested-by: {c.get('tested_by', 'N/A')}\n"
        diff_preview = (c.get('content') or '')[:100]
        commits_str += f"Content (diff): {diff_preview}...\n\n"

    prompt = f"""
Generate a monthly changelog for Photon OS branch '{branch}' in \
{year}-{month:02d}{batch_label}.

The commit URL base is: {REPO_COMMIT_URL}

Structure your response with EXACTLY these sections in this order:

## TL;DR
Three sentences maximum. Summarise: how many commits, the single biggest \
theme, and the most critical action a user should take.

## Action Required
> **Breaking changes, removals, and mandatory updates go here.**

Use a Markdown blockquote (>) for each action item. If packages were \
removed, state the package name, what it provided, and what to migrate to. \
If a kernel update requires a reboot, say so. If there are no breaking \
changes, write "> None this month."

## Security
Bullet list. One CVE per bullet. Format each as:
- **package-name** version: Fix [CVE-YYYY-NNNNN](https://nvd.nist.gov/vuln/detail/CVE-YYYY-NNNNN) — \
one-sentence plain-English impact. \
([commit](https://github.com/vmware/photon/commit/FULL_HASH))

## Added
Bullet list of new features, new packages, new capabilities. Link commits.

## Changed
Bullet list of version upgrades, config changes, build system modifications. \
Link commits. State old version → new version where known.

## Fixed
Bullet list of bug fixes that are NOT security-related. Link commits.

## Removed
Bullet list of packages, features, or configs that were removed. Explain \
the user impact of each removal.

## Contributors
Bullet list of contributors this month, derived from Signed-off-by and \
Reviewed-by fields.

Commits:
{commits_str}
"""
    return query_grok(prompt, api_key, model)


def get_ai_summary(branch, year, month, commits, api_key, model):
    """Summarize commits, batching if necessary."""
    if len(commits) <= BATCH_SIZE:
        return get_single_summary(branch, year, month, commits, api_key, model)

    sub_summaries = []
    for i in range(0, len(commits), BATCH_SIZE):
        batch = commits[i:i + BATCH_SIZE]
        sub_summaries.append(
            get_single_summary(branch, year, month, batch, api_key, model,
                               is_batch=True))

    combine_prompt = f"""
Combine the following sub-summaries into a single monthly changelog for \
Photon OS branch '{branch}' in {year}-{month:02d}.

The commit URL base is: {REPO_COMMIT_URL}

Keep EXACTLY this section order: TL;DR, Action Required, Security, Added, \
Changed, Fixed, Removed, Contributors.

Rules:
- Deduplicate entries that appear in multiple batches.
- Keep bullet-point format throughout. No dense paragraphs.
- Every commit reference must be a Markdown link to the full commit URL.
- The TL;DR must be exactly 3 sentences.
- Action Required uses blockquote (>) format.
- Do NOT add a "Looking Ahead" or speculation section.

Sub-summaries:
{chr(10).join(sub_summaries)}
"""
    return query_grok(combine_prompt, api_key, model)


def generate_markdown(branch, year, month, ai_summary, output_dir):
    """Write a Hugo-compatible Markdown blog post. Return (file_path, full_md)."""
    month_name = datetime(year, month, 1).strftime('%B')
    now = datetime.now(timezone.utc).isoformat()

    file_dir = os.path.join(output_dir, str(year), f'{month:02d}')
    os.makedirs(file_dir, exist_ok=True)
    file_path = os.path.join(file_dir,
                             f'photon-{branch}-monthly-{year}-{month:02d}.md')

    front_matter = f"""---
title: "Photon OS {branch} Changelog: {month_name} {year}"
date: "{now}"
draft: false
author: "docs-lecturer-blogger"
tags: ["photon-os", "{branch}", "changelog", "security", "monthly"]
categories: ["changelog", "branch-{branch}"]
summary: "Monthly changelog for Photon OS {branch} — security fixes, package updates, breaking changes, and recommended actions for {month_name} {year}."
---
"""

    heading = (f'# Photon OS {branch} Changelog: '
               f'{month_name} {year}\n\n')
    footer = (f'\n---\n'
              f'*This changelog was generated from '
              f'[vmware/photon](https://github.com/vmware/photon) '
              f'commit history by an AI summarizer. '
              f'All commit hashes and CVE IDs are verifiable against the '
              f'source repository. If you find inaccuracies, please '
              f'[open an issue]'
              f'(https://github.com/dcasota/photonos-scripts/issues).*\n\n'
              f'**Generated**: {now} | '
              f'**Branch**: [{branch}]'
              f'(https://github.com/vmware/photon/tree/{branch}) | '
              f'**Period**: {year}-{month:02d}\n')

    full_md = front_matter + '\n' + heading + ai_summary + footer
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(full_md)

    print(f'Generated: {file_path}', file=sys.stderr)
    return file_path, full_md


def main():
    parser = argparse.ArgumentParser(
        description='Generate monthly AI summaries from photon_commits.db.')
    parser.add_argument('--db-path', default='photon_commits.db',
                        help='Path to SQLite database')
    parser.add_argument('--output-dir', default='content/blog',
                        help='Output directory for blog posts')
    parser.add_argument('--branches', nargs='+', default=DEFAULT_BRANCHES,
                        help='Branches to summarize')
    parser.add_argument('--since-year', type=int, default=2021,
                        help='Start year for summaries (default: 2021)')
    parser.add_argument('--months', default=None,
                        help='Specific month range YYYY-MM:YYYY-MM (optional)')
    parser.add_argument('--model', default='grok-4-0709',
                        help='xAI model identifier')
    parser.add_argument('--force', action='store_true',
                        help='Regenerate even if summary exists in DB')
    parser.add_argument('--check', action='store_true',
                        help='Report summaries table status without generating')
    parser.add_argument('--export', action='store_true',
                        help='Export all DB changelogs to files (no API call)')
    parser.add_argument('--sync-check', action='store_true',
                        help='Compare DB changelogs against files on disk')
    args = parser.parse_args()

    db_path = os.path.abspath(args.db_path)
    output_dir = os.path.abspath(args.output_dir)

    if args.check:
        status = check_summaries(db_path, args.branches)
        print(json.dumps(status, indent=2))
        return

    if args.sync_check:
        report = sync_check(db_path, args.branches)
        print(json.dumps(report, indent=2))
        return

    if args.export:
        if not os.path.exists(db_path):
            print(json.dumps({'error': f'Database not found: {db_path}'}))
            sys.exit(1)
        manifest = export_summaries(db_path, output_dir, args.branches)
        print(json.dumps(manifest, indent=2))
        return

    api_key = os.getenv('XAI_API_KEY')
    if not api_key:
        print(json.dumps({'error': 'XAI_API_KEY environment variable not set'}))
        sys.exit(1)

    if not os.path.exists(db_path):
        print(json.dumps({'error': f'Database not found: {db_path}'}))
        sys.exit(1)

    # Parse optional month range
    month_start = month_end = None
    if args.months:
        parts = args.months.split(':')
        s = datetime.strptime(parts[0], '%Y-%m')
        month_start = (s.year, s.month)
        if len(parts) > 1:
            e = datetime.strptime(parts[1], '%Y-%m')
            month_end = (e.year, e.month)
        else:
            month_end = month_start

    since_date = datetime(args.since_year, 1, 1, tzinfo=timezone.utc)

    conn, cur = schema_init_db(db_path)
    manifest = {'generated': [], 'skipped': [], 'errors': []}

    for branch in args.branches:
        print(f'Processing branch: {branch}', file=sys.stderr)
        cur.execute("""
            SELECT commit_hash, change_id, message, commit_datetime,
                   signed_off_by, reviewed_on, reviewed_by, tested_by, content
            FROM commits WHERE branch = ? ORDER BY commit_datetime ASC
        """, (branch,))
        rows = cur.fetchall()

        if not rows:
            print(f'No commits for {branch}, skipping.', file=sys.stderr)
            manifest['skipped'].append(branch)
            continue

        filtered = [r for r in rows
                    if datetime.fromisoformat(r[3]) >= since_date]

        groups = defaultdict(list)
        for row in filtered:
            commit = {
                'commit_hash': row[0], 'change_id': row[1],
                'message': row[2], 'commit_datetime': row[3],
                'signed_off_by': row[4], 'reviewed_on': row[5],
                'reviewed_by': row[6], 'tested_by': row[7],
                'content': row[8],
            }
            dt = datetime.fromisoformat(row[3])
            groups[(dt.year, dt.month)].append(commit)

        sorted_keys = sorted(groups.keys())
        if month_start:
            sorted_keys = [k for k in sorted_keys
                           if month_start <= k <= month_end]

        for year, month in tqdm(sorted_keys,
                                desc=f'Summarizing {branch}',
                                unit='month', file=sys.stderr):
            if not args.force and has_summary(cur, branch, year, month):
                print(f'Skipping {branch}/{year}-{month:02d} '
                      f'(already in DB, use --force to regenerate)',
                      file=sys.stderr)
                manifest['skipped'].append(f'{branch}/{year}-{month:02d}')
                continue

            commits = groups[(year, month)]
            try:
                summary = get_ai_summary(branch, year, month, commits,
                                         api_key, args.model)
                path, full_md = generate_markdown(branch, year, month,
                                                  summary, output_dir)
                store_summary(conn, branch, year, month, len(commits),
                              args.model, path, full_md)
                manifest['generated'].append(path)
            except Exception as exc:
                err = f'{branch}/{year}-{month:02d}: {exc}'
                print(f'ERROR: {err}', file=sys.stderr)
                manifest['errors'].append(err)

    conn.close()
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
