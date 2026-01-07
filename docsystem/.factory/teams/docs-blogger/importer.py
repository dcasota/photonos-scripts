import os
import subprocess
import sqlite3
import re
from datetime import datetime

# Database file
DB_FILE = 'photon_commits.db'

# Repo details
REPO_URL = 'https://github.com/vmware/photon.git'
REPO_DIR = 'photon'
BRANCHES = ['3.0', '4.0', '5.0', '6.0', 'common', 'master']

# Install sqlite if not available
try:
    import sqlite3
except ImportError:
    subprocess.run(['tdnf', 'install', '-y', 'sqlite'], check=True)
    import sqlite3

# Install tqdm if not available
try:
    from tqdm import tqdm
except ImportError:
    try:
        subprocess.run(['pip3', 'install', 'tqdm'], check=True)
    except FileNotFoundError:
        subprocess.run(['tdnf', 'install', '-y', 'python3-pip'], check=True)
        subprocess.run(['pip3', 'install', 'tqdm'], check=True)
    from tqdm import tqdm

def run_command(cmd, cwd=None):
    """Run a subprocess command and return output as string, handling encoding issues."""
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, check=True)
    try:
        stdout = result.stdout.decode('utf-8')
    except UnicodeDecodeError:
        stdout = result.stdout.decode('latin-1')
    return stdout.strip()

def parse_commit_output(output):
    """Parse git show output to extract required fields."""
    lines = output.split('\n')
    
    # Find commit date
    commit_date_str = None
    for line in lines:
        if line.startswith('CommitDate:'):
            commit_date_str = line.split(':', 1)[1].strip()
            break
    
    # Parse date to ISO
    commit_datetime = None
    if commit_date_str:
        dt = datetime.strptime(commit_date_str, '%a %b %d %H:%M:%S %Y %z')
        commit_datetime = dt.isoformat()
    
    # Extract message and diff
    message_lines = []
    diff_lines = []
    in_message = False
    in_diff = False
    for line in lines:
        if line.startswith('diff '):
            in_message = False
            in_diff = True
            diff_lines.append(line)
        elif in_diff:
            diff_lines.append(line)
        elif line.startswith('    '):
            in_message = True
            message_lines.append(line[4:])  # Remove indent
        else:
            in_message = False
    
    full_message = '\n'.join(message_lines).strip()
    content = '\n'.join(diff_lines).strip()
    
    # Parse footers from full message using regex
    change_ids = re.findall(r'Change-Id:\s*(I[a-f0-9]+)', full_message)
    signed_off_bys = re.findall(r'Signed-off-by:\s*(.+)', full_message)
    reviewed_ons = re.findall(r'Reviewed-on:\s*(.+)', full_message)
    reviewed_bys = re.findall(r'Reviewed-by:\s*(.+)', full_message)
    tested_bys = re.findall(r'Tested-by:\s*(.+)', full_message)
    
    # Join multiples (though Change-Id and Reviewed-on are usually single)
    change_id = ', '.join(change_ids) if change_ids else None
    signed_off_by = ', '.join(signed_off_bys) if signed_off_bys else None
    reviewed_on = ', '.join(reviewed_ons) if reviewed_ons else None
    reviewed_by = ', '.join(reviewed_bys) if reviewed_bys else None
    tested_by = ', '.join(tested_bys) if tested_bys else None
    
    # Remove footers from message body (optional, but cleans it up)
    # Find the start of footers (first footer line)
    footer_start = min([full_message.find(key) for key in ['Change-Id:', 'Signed-off-by:', 'Reviewed-on:', 'Reviewed-by:', 'Tested-by:'] if full_message.find(key) != -1], default=-1)
    if footer_start != -1:
        message_body = full_message[:footer_start].strip()
    else:
        message_body = full_message
    
    return {
        'message': message_body,
        'commit_datetime': commit_datetime,
        'change_id': change_id,
        'signed_off_by': signed_off_by,
        'reviewed_on': reviewed_on,
        'reviewed_by': reviewed_by,
        'tested_by': tested_by,
        'content': content
    }

# Setup repo
if not os.path.exists(REPO_DIR):
    run_command(['git', 'clone', REPO_URL])
os.chdir(REPO_DIR)
run_command(['git', 'fetch', '--all'])

# Mark the repo as safe to avoid dubious ownership issues
repo_path = os.getcwd()
run_command(['git', 'config', '--global', '--add', 'safe.directory', repo_path])

# Setup database
conn = sqlite3.connect(f'../{DB_FILE}')  # Relative to original dir
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

# Process each branch
for branch in BRANCHES:
    print(f'Processing branch: {branch}')
    run_command(['git', 'checkout', '-B', branch, f'origin/{branch}'])
    
    # Get all commit hashes from oldest to newest
    all_hashes = run_command(['git', 'rev-list', '--reverse', 'HEAD']).split('\n')
    commit_hashes = [h for h in all_hashes if h]
    
    # Get existing commits for this branch to skip
    cur.execute("SELECT commit_hash FROM commits WHERE branch = ?", (branch,))
    existing = set(row[0] for row in cur.fetchall())
    
    # Filter to only new commits
    new_commits = [h for h in commit_hashes if h not in existing]
    
    # Progress bar for new commits
    for commit_hash in tqdm(new_commits, desc=f"Importing {branch} commits", unit="commit"):
        # Get full commit details
        output = run_command(['git', 'show', '--pretty=fuller', '-p', commit_hash])
        parsed = parse_commit_output(output)
        
        # Insert into DB
        cur.execute('''
        INSERT OR IGNORE INTO commits 
        (branch, commit_hash, change_id, message, commit_datetime, signed_off_by, reviewed_on, reviewed_by, tested_by, content)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (branch, commit_hash, parsed['change_id'], parsed['message'], parsed['commit_datetime'],
              parsed['signed_off_by'], parsed['reviewed_on'], parsed['reviewed_by'], parsed['tested_by'], parsed['content']))
    
    conn.commit()

conn.close()
print('Processing complete. Data stored in photon_commits.db')
