"""Tests for the Photon OS commit importer skill."""

import os
import sys
import json
import tempfile
import sqlite3
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '.factory', 'skills'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '.factory', 'skills', 'photon-import'))
from db_schema import init_db


def test_importer_module_exists():
    importer_path = os.path.join(
        os.path.dirname(__file__), '..', '.factory', 'skills', 'photon-import', 'importer.py')
    assert os.path.isfile(importer_path), "importer.py not found"


def test_db_schema_shared_with_summarizer():
    """Both importer and summarizer use the same db_schema.py."""
    schema_path = os.path.join(
        os.path.dirname(__file__), '..', '.factory', 'skills', 'db_schema.py')
    assert os.path.isfile(schema_path), "Shared db_schema.py not found"


def test_init_db_creates_both_tables():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        tables = [row[0] for row in cur.fetchall()]
        assert 'commits' in tables
        assert 'summaries' in tables
        conn.close()
    finally:
        os.unlink(db_path)


def test_insert_and_query_commit():
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        conn, cur = init_db(db_path)
        cur.execute(
            "INSERT INTO commits (branch, commit_hash, message, commit_datetime) "
            "VALUES (?, ?, ?, ?)",
            ('5.0', 'deadbeef', 'Fix CVE-2024-12345 in openssl', '2024-06-15T10:30:00'))
        conn.commit()
        cur.execute("SELECT branch, commit_hash, message FROM commits WHERE branch = '5.0'")
        row = cur.fetchone()
        assert row == ('5.0', 'deadbeef', 'Fix CVE-2024-12345 in openssl')
        conn.close()
    finally:
        os.unlink(db_path)
