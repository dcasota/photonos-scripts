"""Tests for the shared SQLite database schema."""

import sqlite3
import tempfile
import os
import pytest

# Add skills to path
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '.factory', 'skills'))
from db_schema import init_db, COMMITS_SCHEMA, SUMMARIES_SCHEMA


def test_init_db_creates_tables():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = {row[0] for row in cur.fetchall()}
        assert 'commits' in tables
        assert 'summaries' in tables
        conn.close()
    finally:
        os.unlink(db_path)


def test_init_db_idempotent():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn1, _ = init_db(db_path)
        conn1.close()
        conn2, cur2 = init_db(db_path)
        cur2.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = {row[0] for row in cur2.fetchall()}
        assert 'commits' in tables
        assert 'summaries' in tables
        conn2.close()
    finally:
        os.unlink(db_path)


def test_commits_table_schema():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute("PRAGMA table_info(commits)")
        columns = {row[1] for row in cur.fetchall()}
        expected = {'id', 'branch', 'commit_hash', 'change_id', 'message',
                    'commit_datetime', 'signed_off_by', 'reviewed_on',
                    'reviewed_by', 'tested_by', 'content'}
        assert expected == columns
        conn.close()
    finally:
        os.unlink(db_path)


def test_summaries_table_schema():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute("PRAGMA table_info(summaries)")
        columns = {row[1] for row in cur.fetchall()}
        expected = {'id', 'branch', 'year', 'month', 'commit_count',
                    'model', 'file_path', 'changelog_md', 'generated_at'}
        assert expected == columns
        conn.close()
    finally:
        os.unlink(db_path)


def test_commits_unique_constraint():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute("INSERT INTO commits (branch, commit_hash, message) VALUES (?, ?, ?)",
                    ('5.0', 'abc123', 'test commit'))
        conn.commit()
        with pytest.raises(sqlite3.IntegrityError):
            cur.execute("INSERT INTO commits (branch, commit_hash, message) VALUES (?, ?, ?)",
                        ('5.0', 'abc123', 'duplicate'))
            conn.commit()
        conn.close()
    finally:
        os.unlink(db_path)


def test_summaries_unique_constraint():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute(
            "INSERT INTO summaries (branch, year, month, commit_count, model, changelog_md, generated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            ('5.0', 2024, 6, 10, 'grok-4', '# Test', '2024-06-01'))
        conn.commit()
        with pytest.raises(sqlite3.IntegrityError):
            cur.execute(
                "INSERT INTO summaries (branch, year, month, commit_count, model, changelog_md, generated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                ('5.0', 2024, 6, 10, 'grok-4', '# Dup', '2024-06-02'))
            conn.commit()
        conn.close()
    finally:
        os.unlink(db_path)
