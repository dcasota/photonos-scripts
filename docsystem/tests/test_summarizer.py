"""Tests for the Photon OS monthly summarizer skill."""

import os
import sys
import tempfile
import sqlite3
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '.factory', 'skills'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '.factory', 'skills', 'photon-summarize'))
from db_schema import init_db


def test_summarizer_module_exists():
    summarizer_path = os.path.join(
        os.path.dirname(__file__), '..', '.factory', 'skills', 'photon-summarize', 'summarizer.py')
    assert os.path.isfile(summarizer_path), "summarizer.py not found"


def test_summaries_table_stores_changelog():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        changelog = "# Photon 5.0 Monthly Summary: June 2024\n\n## TL;DR\nSecurity fixes.\n"
        cur.execute(
            "INSERT INTO summaries (branch, year, month, commit_count, model, file_path, changelog_md, generated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            ('5.0', 2024, 6, 42, 'grok-4-0709',
             'content/blog/2024/06/photon-5.0-monthly-2024-06.md',
             changelog, '2024-07-01T00:00:00'))
        conn.commit()
        cur.execute("SELECT changelog_md FROM summaries WHERE branch='5.0' AND year=2024 AND month=6")
        row = cur.fetchone()
        assert row is not None
        assert '## TL;DR' in row[0]
        conn.close()
    finally:
        os.unlink(db_path)


def test_summaries_unique_per_branch_month():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute(
            "INSERT INTO summaries (branch, year, month, commit_count, model, changelog_md, generated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            ('5.0', 2024, 6, 42, 'grok-4', '# First', '2024-07-01'))
        conn.commit()
        with pytest.raises(sqlite3.IntegrityError):
            cur.execute(
                "INSERT INTO summaries (branch, year, month, commit_count, model, changelog_md, generated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                ('5.0', 2024, 6, 42, 'grok-4', '# Duplicate', '2024-07-02'))
            conn.commit()
        conn.close()
    finally:
        os.unlink(db_path)


def test_different_branches_same_month():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        for branch in ('3.0', '4.0', '5.0'):
            cur.execute(
                "INSERT INTO summaries (branch, year, month, commit_count, model, changelog_md, generated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (branch, 2024, 6, 10, 'grok-4', f'# {branch}', '2024-07-01'))
        conn.commit()
        cur.execute("SELECT COUNT(*) FROM summaries WHERE year=2024 AND month=6")
        assert cur.fetchone()[0] == 3
        conn.close()
    finally:
        os.unlink(db_path)
