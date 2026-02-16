"""
Shared database schema and helpers for photon_commits.db.

Used by both importer.py and summarizer.py to ensure the full schema
is always present regardless of which script runs first.
"""

import sqlite3

COMMITS_SCHEMA = """
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
"""

SUMMARIES_SCHEMA = """
CREATE TABLE IF NOT EXISTS summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    branch TEXT NOT NULL,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    commit_count INTEGER NOT NULL,
    model TEXT NOT NULL,
    file_path TEXT,
    changelog_md TEXT NOT NULL,
    generated_at TEXT NOT NULL,
    UNIQUE(branch, year, month)
)
"""


def init_db(db_path):
    """Open the database and ensure both tables exist. Returns (conn, cursor)."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute(COMMITS_SCHEMA)
    cur.execute(SUMMARIES_SCHEMA)
    conn.commit()
    return conn, cur
