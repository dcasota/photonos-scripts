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
import string
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from db_schema import init_db as schema_init_db

REPO_URL = 'https://github.com/vmware/photon.git'
DEFAULT_BRANCHES = ['3.0', '4.0', '5.0', '6.0', 'common', 'master']

# Checks for values taken from the command line (and for commit hashes read
# back from git). Each check returns the value rebuilt only from characters
# of a fixed table, so nothing else reaches git or the file system; a value
# that does not pass is refused with ValueError, never silently altered.
_ALNUM = string.ascii_letters + string.digits

# Branch names: the conservative subset of git refnames used by vmware/photon
# (3.0, 5.0, common, master, ...).
_BRANCH_CHARS = _ALNUM + '._-/'

# Hex digits of a git object name (SHA-1: 40, SHA-256: 64).
_HEX_CHARS = string.hexdigits

# Characters that occur in git date expressions: 2021-01-01,
# 2021-01-01T00:00:00+02:00, "2 weeks ago", 2021/01/01, "Jan 1, 2021".
_DATE_CHARS = _ALNUM + ' -:+./,'

# Characters allowed in --db-path and --repo-dir.
_PATH_CHARS = _ALNUM + '/._-+@,=~ '


def _rebuild(raw, table):
    """Return raw rebuilt from table, or None if a character is not in it."""
    out = []
    for ch in raw:
        for allowed in table:
            if ch == allowed:
                out.append(allowed)
                break
        else:
            return None
    return ''.join(out)


def checked_branch(raw):
    """Return a branch name that is safe as a git argument."""
    name = _rebuild(raw, _BRANCH_CHARS) if isinstance(raw, str) else None
    if (not name or name[0] not in _ALNUM or '..' in name or '//' in name
            or name.endswith(('/', '.', '.lock'))):
        raise ValueError(f'unsafe branch name {raw!r}: use letters, digits '
                         f'and . _ - /, starting with a letter or digit')
    return name


def checked_commit(raw):
    """Return a full git object name (40 or 64 hex digits)."""
    name = _rebuild(raw, _HEX_CHARS) if isinstance(raw, str) else None
    if not name or len(name) not in (40, 64):
        raise ValueError(f'not a full git commit hash: {raw!r}')
    return name


def checked_since(raw):
    """Return a git date expression for --since."""
    value = _rebuild(raw, _DATE_CHARS) if isinstance(raw, str) else None
    if not value or value[0] not in _ALNUM:
        raise ValueError(f'unsupported --since-date {raw!r}: use e.g. 2021-01-01')
    return value


def checked_path(raw, option):
    """Return raw as a normalised absolute path built from _PATH_CHARS."""
    if not isinstance(raw, str) or not raw:
        raise ValueError(f'{option}: empty path')
    path = _rebuild(os.path.abspath(raw), _PATH_CHARS)
    if path is None:
        raise ValueError(f'{option}: unsupported character in {raw!r}; '
                         f'use letters, digits and / . _ - + @ , = ~ space')
    return path

try:
    from tqdm import tqdm
except ImportError:
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'tqdm'],
                   check=True, capture_output=True)
    from tqdm import tqdm


def trust_repo(repo_dir):
    """Let git work in repo_dir even if another user owns it, for this run only.

    The checkout may belong to a different user (a CI container, a shared
    work tree). Instead of appending a safe.directory entry to the user's
    ~/.gitconfig on every run, pass it to the git processes this script
    starts through GIT_CONFIG_COUNT/KEY/VALUE, which git treats like a -c
    option on the command line.
    """
    count = os.environ.get('GIT_CONFIG_COUNT', '0')
    index = int(count) if count.isdigit() else 0
    os.environ[f'GIT_CONFIG_KEY_{index}'] = 'safe.directory'
    os.environ[f'GIT_CONFIG_VALUE_{index}'] = repo_dir
    os.environ['GIT_CONFIG_COUNT'] = str(index + 1)


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
    """Create both commits and summaries tables via shared schema."""
    conn, _ = schema_init_db(db_path)
    return conn


def check_db(db_path, branches):
    """Report database status without importing. Returns JSON-serialisable dict."""
    status = {'db_path': db_path, 'exists': os.path.exists(db_path),
              'branches': {}, 'summaries': {}}
    if not status['exists']:
        for b in branches:
            status['branches'][b] = {'commits': 0, 'latest': None}
            status['summaries'][b] = {'count': 0}
        return status

    conn, cur = schema_init_db(db_path)
    for branch in branches:
        cur.execute(
            'SELECT COUNT(*), MAX(commit_datetime) FROM commits WHERE branch = ?',
            (branch,))
        row = cur.fetchone()
        status['branches'][branch] = {
            'commits': row[0] or 0,
            'latest': row[1],
        }
        cur.execute(
            'SELECT COUNT(*) FROM summaries WHERE branch = ?',
            (branch,))
        status['summaries'][branch] = {
            'count': cur.fetchone()[0] or 0,
        }
    conn.close()
    return status


def import_commits(db_path, repo_dir, branches, since_date=None):
    """Clone/update repo and import commits into the database.

    Every value that reaches git is checked first (checked_* above): branch
    names must look like refnames and cannot be taken for options, commit
    hashes must be full hex object names, and --since-date is passed as
    --since=<date> so it is always the option's value.
    """
    repo_dir = checked_path(repo_dir, '--repo-dir')
    db_path = checked_path(db_path, '--db-path')
    if since_date:
        since_date = checked_since(since_date)

    if not os.path.exists(repo_dir):
        print(f'Cloning {REPO_URL} into {repo_dir} ...', file=sys.stderr)
        run_command(['git', 'clone', REPO_URL, repo_dir])

    run_command(['git', 'fetch', '--all'], cwd=repo_dir)
    trust_repo(repo_dir)

    conn = init_db(db_path)
    cur = conn.cursor()

    result = {'branches': {}, 'total_new': 0}

    for raw_branch in branches:
        branch = checked_branch(raw_branch)
        print(f'Processing branch: {branch}', file=sys.stderr)
        run_command(['git', 'checkout', '-B', branch, f'origin/{branch}'], cwd=repo_dir)

        rev_list_cmd = ['git', 'rev-list', '--reverse', 'HEAD']
        if since_date:
            rev_list_cmd.append(f'--since={since_date}')
        all_hashes = run_command(rev_list_cmd, cwd=repo_dir).split('\n')
        commit_hashes = [h for h in all_hashes if h]

        cur.execute('SELECT commit_hash FROM commits WHERE branch = ?', (branch,))
        existing = set(row[0] for row in cur.fetchall())
        new_commits = [h for h in commit_hashes if h not in existing]

        for raw_hash in tqdm(new_commits,
                             desc=f'Importing {branch}',
                             unit='commit',
                             file=sys.stderr):
            commit_hash = checked_commit(raw_hash)
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

    try:
        db_path = checked_path(args.db_path, '--db-path')
        branches = [checked_branch(b) for b in args.branches]
        if args.check:
            status = check_db(db_path, branches)
            print(json.dumps(status, indent=2))
            return
        repo_dir = checked_path(args.repo_dir, '--repo-dir')
        since_date = checked_since(args.since_date) if args.since_date else None
    except ValueError as exc:
        parser.error(str(exc))

    result = import_commits(db_path, repo_dir, branches, since_date)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
