-- SPAGAT-Librarian Database Schema

CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    status TEXT NOT NULL CHECK(status IN ('clarification', 'wontfix', 'backlog', 'progress', 'review', 'ready')),
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    tag TEXT DEFAULT '',
    history TEXT DEFAULT '',
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);
CREATE INDEX IF NOT EXISTS idx_items_tag ON items(tag);
CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at);
CREATE INDEX IF NOT EXISTS idx_items_updated ON items(updated_at);

-- Trigger to update updated_at on modification
CREATE TRIGGER IF NOT EXISTS update_items_timestamp 
AFTER UPDATE ON items
BEGIN
    UPDATE items SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

-- Configuration table for future extensibility
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Insert default config
INSERT OR IGNORE INTO config (key, value) VALUES ('version', '0.1.0');
INSERT OR IGNORE INTO config (key, value) VALUES ('created_at', strftime('%s', 'now'));
