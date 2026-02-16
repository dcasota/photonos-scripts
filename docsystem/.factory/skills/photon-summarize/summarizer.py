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
import argparse
from datetime import datetime, timezone
from collections import defaultdict

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


def query_grok(prompt, api_key, model='grok-4-0709', max_tokens=4096):
    """Send a prompt to the xAI/Grok API and return the response text."""
    payload = {
        'model': model,
        'messages': [
            {'role': 'system', 'content': 'You are a helpful assistant.'},
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
Provide a comprehensive monthly development summary for Photon OS branch \
'{branch}' in {year}-{month:02d}{batch_label}.

Structure your response with EXACTLY these sections:

## Overview
Summarise the month's activity: number of commits, major themes, key contributors.

## Infrastructure & Build Changes
Build system, CI/CD, toolchain, and packaging changes.

## Core System Updates
Kernel, package manager (tdnf), and core component changes.

## Security & Vulnerability Fixes
CVE patches, security hardening, and vulnerability fixes. List CVE IDs where available.

## Container & Runtime Updates
Container technology, Docker, Kubernetes, and runtime changes.

## Package Management
Package additions, version bumps, and removals.

## Network & Storage Updates
Networking stack, storage drivers, and filesystem changes.

## Pull Request Analysis
Significant PR merges inferred from Reviewed-on / Change-ID metadata.

## User Impact Assessment
### Production Systems
Changes affecting production deployments.
### Development Workflows
Changes affecting developers and contributors.
### Recommended Actions
Steps users should consider taking.

## Looking Ahead
Preview of upcoming development focus areas based on trends.

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
Combine the following sub-summaries into a single comprehensive monthly \
development summary for Photon OS branch '{branch}' in {year}-{month:02d}.

Keep the mandatory section structure: Overview, Infrastructure & Build \
Changes, Core System Updates, Security & Vulnerability Fixes, Container \
& Runtime Updates, Package Management, Network & Storage Updates, Pull \
Request Analysis, User Impact Assessment (with Production Systems, \
Development Workflows, Recommended Actions sub-sections), Looking Ahead.

Sub-summaries:
{chr(10).join(sub_summaries)}
"""
    return query_grok(combine_prompt, api_key, model)


def generate_markdown(branch, year, month, ai_summary, output_dir):
    """Write a Hugo-compatible Markdown blog post and return the file path."""
    month_name = datetime(year, month, 1).strftime('%B')
    now = datetime.now(timezone.utc).isoformat()

    file_dir = os.path.join(output_dir, str(year), f'{month:02d}')
    os.makedirs(file_dir, exist_ok=True)
    file_path = os.path.join(file_dir,
                             f'photon-{branch}-monthly-{year}-{month:02d}.md')

    front_matter = f"""---
title: "Photon OS {branch} Monthly Summary: {month_name} {year}"
date: "{now}"
draft: false
author: "docs-lecturer-blogger"
tags: ["photon-os", "{branch}", "monthly-summary", "development"]
categories: ["development-updates", "branch-{branch}"]
summary: "Comprehensive monthly summary of Photon OS {branch} development activities including commits, pull requests, security updates, and user impact analysis."
---
"""

    heading = (f'# Photon OS {branch} Monthly Summary: '
               f'{month_name} {year}\n\n')
    footer = (f'\n---\n**Monthly Summary Generated**: {now} '
              f'by docs-lecturer-blogger\n'
              f'**Repository**: https://github.com/vmware/photon\n'
              f'**Branch**: {branch}\n'
              f'**Period**: {year}-{month:02d}\n')

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(front_matter + '\n' + heading + ai_summary + footer)

    print(f'Generated: {file_path}', file=sys.stderr)
    return file_path


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
    args = parser.parse_args()

    api_key = os.getenv('XAI_API_KEY')
    if not api_key:
        print(json.dumps({'error': 'XAI_API_KEY environment variable not set'}))
        sys.exit(1)

    db_path = os.path.abspath(args.db_path)
    output_dir = os.path.abspath(args.output_dir)

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

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
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
            commits = groups[(year, month)]
            try:
                summary = get_ai_summary(branch, year, month, commits,
                                         api_key, args.model)
                path = generate_markdown(branch, year, month, summary,
                                         output_dir)
                manifest['generated'].append(path)
            except Exception as exc:
                err = f'{branch}/{year}-{month:02d}: {exc}'
                print(f'ERROR: {err}', file=sys.stderr)
                manifest['errors'].append(err)

    conn.close()
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
