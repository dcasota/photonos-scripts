#include "ai.h"
#include "../db/db.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Schema for agent memory */
static const char *MEMORY_SCHEMA_SQL =
    "CREATE TABLE IF NOT EXISTS agent_memory ("
    "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  project_id INTEGER DEFAULT 0,"
    "  scope TEXT NOT NULL,"
    "  key TEXT NOT NULL,"
    "  value TEXT NOT NULL,"
    "  updated_at INTEGER DEFAULT (strftime('%s', 'now')),"
    "  UNIQUE(project_id, scope, key)"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_mem_project_scope "
    "ON agent_memory(project_id, scope);";

static bool mem_schema_initialized = false;

static bool ensure_mem_schema(void) {
    if (mem_schema_initialized) return true;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    char *err = NULL;
    int rc = sqlite3_exec(db, MEMORY_SCHEMA_SQL, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "ai: memory schema error: %s\n", err);
        sqlite3_free(err);
        return false;
    }

    mem_schema_initialized = true;
    return true;
}

bool ai_memory_init(void) {
    return ensure_mem_schema();
}

bool ai_memory_set(int64_t project_id, const char *scope, const char *key,
                   const char *value) {
    if (!scope || !key || !value) return false;
    if (!ensure_mem_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "INSERT OR REPLACE INTO agent_memory "
        "(project_id, scope, key, value, updated_at) "
        "VALUES (?, ?, ?, ?, strftime('%s', 'now'))";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "ai: memory set error: %s\n", sqlite3_errmsg(db));
        return false;
    }

    sqlite3_bind_int64(stmt, 1, project_id);
    sqlite3_bind_text(stmt, 2, scope, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, key, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, value, -1, SQLITE_STATIC);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}

bool ai_memory_get(int64_t project_id, const char *scope, const char *key,
                   char *value_buf, int buf_size) {
    if (!scope || !key || !value_buf || buf_size < 1) return false;
    if (!ensure_mem_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    value_buf[0] = '\0';

    const char *sql =
        "SELECT value FROM agent_memory "
        "WHERE project_id = ? AND scope = ? AND key = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, project_id);
    sqlite3_bind_text(stmt, 2, scope, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, key, -1, SQLITE_STATIC);

    bool found = false;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *val = (const char *)sqlite3_column_text(stmt, 0);
        str_safe_copy(value_buf, val, buf_size);
        found = true;
    }

    sqlite3_finalize(stmt);
    return found;
}

bool ai_memory_print_all(int64_t project_id, const char *scope) {
    if (!scope) return false;
    if (!ensure_mem_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "SELECT key, value FROM agent_memory "
        "WHERE project_id = ? AND scope = ? ORDER BY key";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, project_id);
    sqlite3_bind_text(stmt, 2, scope, -1, SQLITE_STATIC);

    int count = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *key = (const char *)sqlite3_column_text(stmt, 0);
        const char *value = (const char *)sqlite3_column_text(stmt, 1);
        printf("  %s = %s\n", key, value);
        count++;
    }

    sqlite3_finalize(stmt);

    if (count == 0) {
        printf("  (empty)\n");
    }

    return true;
}

bool ai_memory_delete(int64_t project_id, const char *scope,
                      const char *key) {
    if (!scope || !key) return false;
    if (!ensure_mem_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "DELETE FROM agent_memory "
        "WHERE project_id = ? AND scope = ? AND key = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, project_id);
    sqlite3_bind_text(stmt, 2, scope, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, key, -1, SQLITE_STATIC);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}

bool ai_memory_clear(int64_t project_id, const char *scope) {
    if (!scope) return false;
    if (!ensure_mem_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "DELETE FROM agent_memory WHERE project_id = ? AND scope = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, project_id);
    sqlite3_bind_text(stmt, 2, scope, -1, SQLITE_STATIC);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}

bool ai_memory_load_file(const char *path) {
    if (!path) return false;
    if (!ensure_mem_schema()) return false;

    FILE *fp = fopen(path, "r");
    if (!fp) return false;

    sqlite3 *db = db_get_handle();
    if (!db) {
        fclose(fp);
        return false;
    }

    /* Parse MEMORY.md format:
     * ## scope_name
     * - key: value
     * - key: value
     */
    char line[1024];
    char current_scope[128];
    current_scope[0] = '\0';

    while (fgets(line, sizeof(line), fp)) {
        char *trimmed = str_trim(line);

        /* Section header: ## scope */
        if (str_starts_with(trimmed, "## ")) {
            str_safe_copy(current_scope, trimmed + 3,
                          sizeof(current_scope));
            /* Trim trailing whitespace from scope */
            char *end = current_scope + strlen(current_scope) - 1;
            while (end > current_scope && (*end == '\n' || *end == '\r' ||
                   *end == ' ')) {
                *end = '\0';
                end--;
            }
            continue;
        }

        /* Key-value: - key: value */
        if (current_scope[0] && str_starts_with(trimmed, "- ")) {
            char *kv = trimmed + 2;
            char *colon = strchr(kv, ':');
            if (!colon) continue;

            /* Extract key */
            char key[128];
            size_t klen = (size_t)(colon - kv);
            if (klen >= sizeof(key)) klen = sizeof(key) - 1;
            memcpy(key, kv, klen);
            key[klen] = '\0';

            /* Extract value (skip ': ') */
            char *val = colon + 1;
            while (*val == ' ') val++;

            ai_memory_set(0, current_scope, str_trim(key), str_trim(val));
        }
    }

    fclose(fp);
    return true;
}

bool ai_memory_save_file(const char *path) {
    if (!path) return false;
    if (!ensure_mem_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    FILE *fp = fopen(path, "w");
    if (!fp) return false;

    fprintf(fp, "# Agent Memory\n\n");

    /* Get distinct scopes */
    const char *scope_sql =
        "SELECT DISTINCT scope FROM agent_memory ORDER BY scope";
    sqlite3_stmt *scope_stmt;

    if (sqlite3_prepare_v2(db, scope_sql, -1, &scope_stmt, NULL)
        != SQLITE_OK) {
        fclose(fp);
        return false;
    }

    while (sqlite3_step(scope_stmt) == SQLITE_ROW) {
        const char *scope =
            (const char *)sqlite3_column_text(scope_stmt, 0);

        fprintf(fp, "## %s\n\n", scope);

        /* Get all key-value pairs in this scope */
        const char *kv_sql =
            "SELECT key, value FROM agent_memory "
            "WHERE scope = ? ORDER BY key";
        sqlite3_stmt *kv_stmt;

        if (sqlite3_prepare_v2(db, kv_sql, -1, &kv_stmt, NULL)
            == SQLITE_OK) {
            sqlite3_bind_text(kv_stmt, 1, scope, -1, SQLITE_STATIC);

            while (sqlite3_step(kv_stmt) == SQLITE_ROW) {
                const char *key =
                    (const char *)sqlite3_column_text(kv_stmt, 0);
                const char *value =
                    (const char *)sqlite3_column_text(kv_stmt, 1);
                fprintf(fp, "- %s: %s\n", key, value);
            }

            sqlite3_finalize(kv_stmt);
        }

        fprintf(fp, "\n");
    }

    sqlite3_finalize(scope_stmt);
    fclose(fp);
    return true;
}
