import os
import sqlite3
import requests
from datetime import datetime, timezone
from collections import defaultdict
from tqdm import tqdm
import json

# Database file
DB_FILE = 'photon_commits.db'

# Branches
BRANCHES = ['3.0', '4.0', '5.0', '6.0', 'common', 'master']

# Branch start dates
BRANCH_START_DATES = {
    '3.0': datetime(2019, 2, 7, tzinfo=timezone.utc),
    '4.0': datetime(2021, 2, 25, tzinfo=timezone.utc),
    '5.0': datetime(2023, 5, 2, tzinfo=timezone.utc),
    '6.0': datetime(2024, 6, 26, tzinfo=timezone.utc),
    'common': datetime(2024, 12, 29, tzinfo=timezone.utc),
    'master': datetime(2015, 1, 1, tzinfo=timezone.utc)  # Approximate start for master
}

# Output directory
OUTPUT_DIR = 'summaries'

# XAI API details
XAI_API_URL = 'https://api.x.ai/v1/chat/completions'
XAI_API_KEY = os.getenv('XAI_API_KEY')
if not XAI_API_KEY:
    raise ValueError("XAI_API_KEY environment variable not set. Please set it to use the Grok API.")

# Batch size to avoid token limits
BATCH_SIZE = 20  # Reduced to handle potential token issues

def query_grok(prompt, model="grok-4-0709", max_tokens=2048):
    """Helper to query Grok API."""
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.7,
        "max_tokens": max_tokens
    }
    headers = {
        "Authorization": f"Bearer {XAI_API_KEY}",
        "Content-Type": "application/json"
    }
    try:
        response = requests.post(XAI_API_URL, headers=headers, json=payload)
        response.raise_for_status()
        result = response.json()
        return result['choices'][0]['message']['content'].strip()
    except requests.exceptions.HTTPError as e:
        print(f"API error: {response.text}")  # Added for debugging
        raise

def get_ai_summary(branch, year, month, commits):
    """Query Grok API for deep dive summary, handling large number of commits with batching."""
    if len(commits) <= BATCH_SIZE:
        return get_single_summary(branch, year, month, commits)
    else:
        # Batch commits
        sub_summaries = []
        for i in range(0, len(commits), BATCH_SIZE):
            batch = commits[i:i + BATCH_SIZE]
            sub_summary = get_single_summary(branch, year, month, batch, is_batch=True)
            sub_summaries.append(sub_summary)
        
        # Combine sub-summaries
        sep = '\n\n'
        combined_subs = sep.join(sub_summaries)
        combine_prompt = f"""
Summarize the following sub-summaries into a comprehensive deep dive for Photon OS branch '{branch}' in {year}-{month:02d}.
Focus on:
- Key commits and their purposes.
- Associated PRs (if inferable from Reviewed-on or Change-ID).
- Security updates (e.g., vulnerability fixes, package updates).
- User impact (e.g., new features, bug fixes, breaking changes).

Be detailed but concise. Structure the response with sections for Overview, Security Updates, User Impact, and Notable Commits.

Sub-summaries:
{combined_subs}
"""
        return query_grok(combine_prompt)

def get_single_summary(branch, year, month, commits, is_batch=False):
    """Get summary for a single batch or small set."""
    batch_label = " (batch)" if is_batch else ""
    commits_str = ''
    for commit in commits:
        commits_str += f"Commit Hash: {commit['commit_hash']}\n"
        commits_str += f"Date: {commit['commit_datetime']}\n"
        commits_str += f"Change-ID: {commit.get('change_id', 'N/A')}\n"
        commits_str += f"Message: {commit['message']}\n"
        commits_str += f"Signed-off-by: {commit.get('signed_off_by', 'N/A')}\n"
        commits_str += f"Reviewed-on: {commit.get('reviewed_on', 'N/A')}\n"
        commits_str += f"Reviewed-by: {commit.get('reviewed_by', 'N/A')}\n"
        commits_str += f"Tested-by: {commit.get('tested_by', 'N/A')}\n"
        commits_str += f"Content (diff): {commit['content'][:100]}...\n\n"  # Further reduced truncate

    prompt = f"""
Provide a comprehensive deep dive into the following commits for Photon OS branch '{branch}' in {year}-{month:02d}{batch_label}.
Focus on:
- Key commits and their purposes.
- Associated PRs (if inferable from Reviewed-on or Change-ID).
- Security updates (e.g., vulnerability fixes, package updates).
- User impact (e.g., new features, bug fixes, breaking changes).

Be detailed but concise. Structure the response with sections for Overview, Security Updates, User Impact, and Notable Commits.

Commits:
{commits_str}
"""
    return query_grok(prompt)

def generate_markdown(branch, year, month, ai_summary):
    """Generate Hugo-compatible Markdown file."""
    now = datetime.now().isoformat()
    file_dir = os.path.join(OUTPUT_DIR, branch)
    os.makedirs(file_dir, exist_ok=True)
    file_path = os.path.join(file_dir, f"{year}-{month:02d}.md")

    front_matter = f"""---
title: "Photon OS {branch} Development Summary - {year}-{month:02d}"
date: "{now}"
draft: false
categories: ["development", "photon-os"]
tags: ["{branch}", "monthly-summary"]
---

"""

    content = f"# Development Summary for {year}-{month:02d}\n\n{ai_summary}\n"

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(front_matter + content)

    print(f"Generated summary: {file_path}")

# Connect to database
conn = sqlite3.connect(DB_FILE)
cur = conn.cursor()

# Process each branch
for branch in BRANCHES:
    print(f'Processing branch: {branch}')
    
    start_date = BRANCH_START_DATES.get(branch, datetime(2015, 1, 1, tzinfo=timezone.utc))
    
    # Query all commits for the branch, ordered by datetime
    cur.execute("""
    SELECT commit_hash, change_id, message, commit_datetime, signed_off_by, reviewed_on, reviewed_by, tested_by, content
    FROM commits WHERE branch = ? ORDER BY commit_datetime ASC
    """, (branch,))
    rows = cur.fetchall()
    
    if not rows:
        print(f"No commits found for branch {branch}. Skipping.")
        continue
    
    # Filter commits after start date
    filtered_rows = [row for row in rows if datetime.fromisoformat(row[3]) >= start_date]
    
    # Group by year-month
    groups = defaultdict(list)
    for row in filtered_rows:
        commit = {
            'commit_hash': row[0],
            'change_id': row[1],
            'message': row[2],
            'commit_datetime': row[3],
            'signed_off_by': row[4],
            'reviewed_on': row[5],
            'reviewed_by': row[6],
            'tested_by': row[7],
            'content': row[8]
        }
        dt = datetime.fromisoformat(row[3])
        key = (dt.year, dt.month)
        groups[key].append(commit)
    
    # Process each monthly group
    sorted_keys = sorted(groups.keys())
    for year, month in tqdm(sorted_keys, desc=f"Summarizing {branch} months", unit="month"):
        commits = groups[(year, month)]
        ai_summary = get_ai_summary(branch, year, month, commits)
        generate_markdown(branch, year, month, ai_summary)

conn.close()
print('Summary generation complete.')
