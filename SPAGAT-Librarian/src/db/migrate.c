#include "migrate.h"
#include "db.h"
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>

static bool migrate_v1_to_v2(sqlite3 *db);
static bool migrate_v2_to_v3(sqlite3 *db);
static bool table_has_column(sqlite3 *db, const char *table, const char *column);
static bool ensure_version_table(sqlite3 *db);

int db_get_version(void) {
    sqlite3 *db = db_get_handle();
    if (!db) return -1;
    
    if (!ensure_version_table(db)) return -1;
    
    const char *sql = "SELECT value FROM db_meta WHERE key = 'schema_version'";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return 0;
    }
    
    int version = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        version = sqlite3_column_int(stmt, 0);
    }
    
    sqlite3_finalize(stmt);
    return version;
}

bool db_set_version(int version) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    if (!ensure_version_table(db)) return false;
    
    const char *sql = "INSERT OR REPLACE INTO db_meta (key, value) VALUES ('schema_version', ?)";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }
    
    sqlite3_bind_int(stmt, 1, version);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

static bool ensure_version_table(sqlite3 *db) {
    const char *sql = 
        "CREATE TABLE IF NOT EXISTS db_meta ("
        "  key TEXT PRIMARY KEY,"
        "  value TEXT"
        ")";
    
    char *err = NULL;
    int rc = sqlite3_exec(db, sql, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Failed to create db_meta table: %s\n", err);
        sqlite3_free(err);
        return false;
    }
    return true;
}

static bool table_has_column(sqlite3 *db, const char *table, const char *column) {
    char sql[256];
    snprintf(sql, sizeof(sql), "PRAGMA table_info(%s)", table);
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }
    
    bool found = false;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *col_name = (const char *)sqlite3_column_text(stmt, 1);
        if (col_name && strcmp(col_name, column) == 0) {
            found = true;
            break;
        }
    }
    
    sqlite3_finalize(stmt);
    return found;
}

static bool table_exists(sqlite3 *db, const char *table) {
    const char *sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }
    
    sqlite3_bind_text(stmt, 1, table, -1, SQLITE_STATIC);
    bool exists = (sqlite3_step(stmt) == SQLITE_ROW);
    sqlite3_finalize(stmt);
    
    return exists;
}

static int detect_schema_version(sqlite3 *db) {
    int version = db_get_version();
    if (version > 0) return version;
    
    if (!table_exists(db, "items")) {
        return 0;
    }
    
    if (table_has_column(db, "items", "priority")) {
        return 3;
    }
    
    if (table_has_column(db, "items", "title")) {
        return 2;
    }
    
    return 1;
}

static bool migrate_v1_to_v2(sqlite3 *db) {
    printf("Migrating database from version 1 to version 2...\n");
    printf("  Adding 'title' column to items table...\n");
    
    char *err = NULL;
    
    const char *add_column = "ALTER TABLE items ADD COLUMN title TEXT DEFAULT ''";
    if (sqlite3_exec(db, add_column, NULL, NULL, &err) != SQLITE_OK) {
        fprintf(stderr, "Failed to add title column: %s\n", err);
        sqlite3_free(err);
        return false;
    }
    
    printf("  Copying description to title for existing items...\n");
    const char *copy_data = "UPDATE items SET title = SUBSTR(description, 1, 127) WHERE title = '' OR title IS NULL";
    if (sqlite3_exec(db, copy_data, NULL, NULL, &err) != SQLITE_OK) {
        fprintf(stderr, "Failed to copy description to title: %s\n", err);
        sqlite3_free(err);
        return false;
    }
    
    printf("  Migration to version 2 complete.\n");
    return true;
}

static bool migrate_v2_to_v3(sqlite3 *db) {
    printf("Migrating database from version 2 to version 3...\n");
    char *err = NULL;
    
    const char *migrations[] = {
        "ALTER TABLE items ADD COLUMN priority TEXT DEFAULT 'none'",
        "ALTER TABLE items ADD COLUMN due_date INTEGER DEFAULT 0",
        "ALTER TABLE items ADD COLUMN project_id INTEGER DEFAULT 0",
        "ALTER TABLE items ADD COLUMN parent_id INTEGER DEFAULT 0",
        "ALTER TABLE items ADD COLUMN git_branch TEXT DEFAULT ''",
        "ALTER TABLE items ADD COLUMN time_spent INTEGER DEFAULT 0",
        
        "CREATE TABLE IF NOT EXISTS projects ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  name TEXT NOT NULL UNIQUE,"
        "  description TEXT DEFAULT '',"
        "  created_at INTEGER DEFAULT (strftime('%s', 'now'))"
        ")",
        
        "CREATE TABLE IF NOT EXISTS dependencies ("
        "  from_id INTEGER NOT NULL,"
        "  to_id INTEGER NOT NULL,"
        "  PRIMARY KEY (from_id, to_id),"
        "  FOREIGN KEY (from_id) REFERENCES items(id) ON DELETE CASCADE,"
        "  FOREIGN KEY (to_id) REFERENCES items(id) ON DELETE CASCADE"
        ")",
        
        "CREATE TABLE IF NOT EXISTS templates ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  name TEXT NOT NULL UNIQUE,"
        "  title TEXT DEFAULT '',"
        "  description TEXT DEFAULT '',"
        "  tag TEXT DEFAULT '',"
        "  status TEXT DEFAULT 'backlog',"
        "  priority TEXT DEFAULT 'none'"
        ")",
        
        "CREATE TABLE IF NOT EXISTS sessions ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  name TEXT NOT NULL UNIQUE,"
        "  current_project INTEGER DEFAULT 0,"
        "  current_col INTEGER DEFAULT 2,"
        "  current_row INTEGER DEFAULT 0,"
        "  scroll_offsets TEXT DEFAULT '',"
        "  swimlane_mode INTEGER DEFAULT 0,"
        "  saved_at INTEGER DEFAULT (strftime('%s', 'now'))"
        ")",
        
        "CREATE TABLE IF NOT EXISTS time_entries ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  item_id INTEGER NOT NULL,"
        "  started_at INTEGER NOT NULL,"
        "  ended_at INTEGER DEFAULT 0,"
        "  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE"
        ")",
        
        "INSERT OR IGNORE INTO projects (id, name, description) VALUES (0, 'Default', 'Default project')",
        
        NULL
    };
    
    for (int i = 0; migrations[i] != NULL; i++) {
        if (sqlite3_exec(db, migrations[i], NULL, NULL, &err) != SQLITE_OK) {
            if (strstr(err, "duplicate column") == NULL && 
                strstr(err, "already exists") == NULL) {
                fprintf(stderr, "Migration failed: %s\nSQL: %s\n", err, migrations[i]);
                sqlite3_free(err);
                return false;
            }
            sqlite3_free(err);
            err = NULL;
        }
    }
    
    printf("  Migration to version 3 complete.\n");
    return true;
}

bool db_migrate_check_and_run(void) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    int current_version = detect_schema_version(db);
    
    if (current_version == SPAGAT_DB_VERSION) {
        db_set_version(SPAGAT_DB_VERSION);
        return true;
    }
    
    if (current_version == 0) {
        db_set_version(SPAGAT_DB_VERSION);
        return true;
    }
    
    printf("Database schema version %d detected, current version is %d.\n", 
           current_version, SPAGAT_DB_VERSION);
    
    if (current_version < 2) {
        if (!migrate_v1_to_v2(db)) {
            return false;
        }
        current_version = 2;
    }
    
    if (current_version < 3) {
        if (!migrate_v2_to_v3(db)) {
            return false;
        }
        current_version = 3;
    }
    
    if (!db_set_version(SPAGAT_DB_VERSION)) {
        fprintf(stderr, "Failed to update schema version.\n");
        return false;
    }
    
    printf("Database migration complete.\n");
    return true;
}
