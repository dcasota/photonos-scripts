#!/usr/bin/env python3
"""
Photon OS commit importer.

Clones or updates the vmware/photon repository and imports commit history
for specified branches into a local SQLite database.

Can be run standalone or invoked by the photon-import Factory skill.
"""

import os
import sys
import subprocess
import sqlite3
import re
import json
import argparse
from datetime import datetime

REPO_URL = 'https://github.com/vmware/photon.git'
DEFAULT_BRANCHES = ['3.0', '4.0', '5.0', '6.0', 'common', 'master']

try:
    from tqdm import tqdm
except ImportError:
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'tqdm'],
                   check=True, capture_output=True)
    from tqdm import tqdm


def run_command(cmd, cwd=None):
    """Run a subprocess command and return output as string."""
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, check=True)
    try:
        return result.stdout.decode('utf-8').strip()
    except UnicodeDecodeError:
        return result.stdout.decode('latin-1').strip()


def parse_commit_output(output):
    """Parse git show output to extract required fields."""
    lines = output.split('\n')

    commit_date_str = None
    for line in lines:
        if line.startswith('CommitDate:'):
            commit_date_str = line.split(':', 1)[1].strip()
            break

    commit_datetime = None
    if commit_date_str:
        dt = datetime.strptime(commit_date_str, '%a %b %d %H:%M:%S %Y %z')
        commit_datetime = dt.isoformat()

    message_lines = []
    diff_lines = []
    in_diff = False
    for line in lines:
        if line.startswith('diff '):
            in_diff = True
            diff_lines.append(line)
        elif in_diff:
            diff_lines.append(line)
        elif line.startswith('    '):
            message_lines.append(line[4:])

    full_message = '\n'.join(message_lines).strip()
    content = '\n'.join(diff_lines).strip()

    change_ids = re.findall(r'Change-Id:\s*(I[a-f0-9]+)', full_message)
    signed_off_bys = re.findall(r'Signed-off-by:\s*(.+)', full_message)
    reviewed_ons = re.findall(r'Reviewed-on:\s*(.+)', full_message)
    reviewed_bys = re.findall(r'Reviewed-by:\s*(.+)', full_message)
    tested_bys = re.findall(r'Tested-by:\s*(.+)', full_message)

    change_id = ', '.join(change_ids) if change_ids else None
    signed_off_by = ', '.join(signed_off_bys) if signed_off_bys else None
    reviewed_on = ', '.join(reviewed_ons) if reviewed_ons else None
    reviewed_by = ', '.join(reviewed_bys) if reviewed_bys else None
    tested_by = ', '.join(tested_bys) if tested_bys else None

    footer_keys = ['Change-Id:', 'Signed-off-by:', 'Reviewed-on:',
                   'Reviewed-by:', 'Tested-by:']
    positions = [full_message.find(k) for k in footer_keys
                 if full_message.find(k) != -1]
    footer_start = min(positions) if positions else -1
    message_body = full_message[:footer_start].strip() if footer_start != -1 else full_message

    return {
        'message': message_body,
        'commit_datetime': commit_datetime,
        'change_id': change_id,
        'signed_off_by': signed_off_by,
        'reviewed_on': reviewed_on,
        'reviewed_by': reviewed_by,
        'tested_by': tested_by,
        'content': content,
    }


def init_db(db_path):
    """Create the commits table if it does not exist."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS commits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            branch TEXT NOT NULL,
            commit_hash TEXT NOT NULL,
            change_id TEXT,
            message TEXT,
            commit_datetime TEXT,
            signed_off_by TEXT,
            reviewed_on TEXT,
            reviewed_by TEXT,
            tested_by TEXT,
            content TEXT,
            UNIQUE(branch, commit_hash)
        )
    ''')
    conn.commit()
    return conn


def check_db(db_path, branches):
    """Report database status without importing. Returns JSON-serialisable dict."""
    status = {'db_path': db_path, 'exists': os.path.exists(db_path), 'branches': {}}
    if not status['exists']:
        for b in branches:
            status['branches'][b] = {'count': 0, 'latest': None}
        return status

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    for branch in branches:
        cur.execute(
            'SELECT COUNT(*), MAX(commit_datetime) FROM commits WHERE branch = ?',
            (branch,))
        row = cur.fetchone()
        status['branches'][branch] = {
            'count': row[0] or 0,
            'latest': row[1],
        }
    conn.close()
    return status


def import_commits(db_path, repo_dir, branches, since_date=None):
    """Clone/update repo and import commits into the database."""
    repo_dir = os.path.abspath(repo_dir)
    db_path = os.path.abspath(db_path)

    if not os.path.exists(repo_dir):
        print(f'Cloning {REPO_URL} into {repo_dir} ...', file=sys.stderr)
        run_command(['git', 'clone', REPO_URL, repo_dir])

    run_command(['git', 'fetch', '--all'], cwd=repo_dir)
    run_command(['git', 'config', '--global', '--add', 'safe.directory', repo_dir])

    conn = init_db(db_path)
    cur = conn.cursor()

    result = {'branches': {}, 'total_new': 0}

    for branch in branches:
        print(f'Processing branch: {branch}', file=sys.stderr)
        run_command(['git', 'checkout', '-B', branch, f'origin/{branch}'], cwd=repo_dir)

        rev_list_cmd = ['git', 'rev-list', '--reverse', 'HEAD']
        if since_date:
            rev_list_cmd.extend(['--since', since_date])
        all_hashes = run_command(rev_list_cmd, cwd=repo_dir).split('\n')
        commit_hashes = [h for h in all_hashes if h]

        cur.execute('SELECT commit_hash FROM commits WHERE branch = ?', (branch,))
        existing = set(row[0] for row in cur.fetchall())
        new_commits = [h for h in commit_hashes if h not in existing]

        for commit_hash in tqdm(new_commits,
                                desc=f'Importing {branch}',
                                unit='commit',
                                file=sys.stderr):
            output = run_command(
                ['git', 'show', '--pretty=fuller', '-p', commit_hash],
                cwd=repo_dir)
            parsed = parse_commit_output(output)
            cur.execute('''
                INSERT OR IGNORE INTO commits
                (branch, commit_hash, change_id, message, commit_datetime,
                 signed_off_by, reviewed_on, reviewed_by, tested_by, content)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (branch, commit_hash, parsed['change_id'], parsed['message'],
                  parsed['commit_datetime'], parsed['signed_off_by'],
                  parsed['reviewed_on'], parsed['reviewed_by'],
                  parsed['tested_by'], parsed['content']))

        conn.commit()
        result['branches'][branch] = {'new': len(new_commits), 'skipped': len(existing)}
        result['total_new'] += len(new_commits)

    conn.close()
    return result


def main():
    parser = argparse.ArgumentParser(
        description='Import vmware/photon commit history into SQLite.')
    parser.add_argument('--db-path', default='photon_commits.db',
                        help='Path to SQLite database (default: photon_commits.db)')
    parser.add_argument('--repo-dir', default='photon',
                        help='Path to local clone of vmware/photon (default: photon)')
    parser.add_argument('--branches', nargs='+', default=DEFAULT_BRANCHES,
                        help='Branches to import (default: all)')
    parser.add_argument('--since-date', default=None,
                        help='Only import commits since this date (ISO or git date format)')
    parser.add_argument('--check', action='store_true',
                        help='Report DB status without importing')
    args = parser.parse_args()

    if args.check:
        status = check_db(args.db_path, args.branches)
        print(json.dumps(status, indent=2))
        return

    result = import_commits(args.db_path, args.repo_dir, args.branches, args.since_date)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
