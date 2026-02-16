#include "db.h"
#include "migrate.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static sqlite3 *db = NULL;

static const char *SCHEMA_SQL =
    "CREATE TABLE IF NOT EXISTS items ("
    "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  status TEXT NOT NULL,"
    "  title TEXT NOT NULL,"
    "  description TEXT DEFAULT '',"
    "  tag TEXT DEFAULT '',"
    "  history TEXT DEFAULT '',"
    "  created_at INTEGER DEFAULT (strftime('%s', 'now')),"
    "  updated_at INTEGER DEFAULT (strftime('%s', 'now'))"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);"
    "CREATE INDEX IF NOT EXISTS idx_items_tag ON items(tag);";

bool db_open(const char *path) {
    if (db) return true;
    
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open database: %s\n", sqlite3_errmsg(db));
        sqlite3_close(db);
        db = NULL;
        return false;
    }
    
    sqlite3_exec(db, "PRAGMA foreign_keys = ON;", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    
    return true;
}

void db_close(void) {
    if (db) {
        sqlite3_close(db);
        db = NULL;
    }
}

bool db_init_schema(void) {
    if (!db) return false;
    
    char *err = NULL;
    int rc = sqlite3_exec(db, SCHEMA_SQL, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Schema error: %s\n", err);
        sqlite3_free(err);
        return false;
    }
    
    if (!db_migrate_check_and_run()) {
        fprintf(stderr, "Database migration failed\n");
        return false;
    }
    
    return true;
}

sqlite3 *db_get_handle(void) {
    return db;
}

bool db_item_add(const char *status, const char *title, const char *description, const char *tag, int64_t *out_id) {
    if (!db || !status || !title) return false;
    
    const char *sql = "INSERT INTO items (status, title, description, tag, history) VALUES (?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Prepare error: %s\n", sqlite3_errmsg(db));
        return false;
    }
    
    ItemStatus st = status_from_string(status);
    char history[4] = {STATUS_ABBREV[st], '\0'};
    
    sqlite3_bind_text(stmt, 1, status, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, title, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, description ? description : "", -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, tag ? tag : "", -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, history, -1, SQLITE_STATIC);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        fprintf(stderr, "Insert error: %s\n", sqlite3_errmsg(db));
        return false;
    }
    
    if (out_id) *out_id = sqlite3_last_insert_rowid(db);
    return true;
}

bool db_item_get(int64_t id, Item *item) {
    if (!db || !item) return false;
    
    const char *sql = 
        "SELECT id, status, title, description, tag, history, priority, due_date, "
        "project_id, parent_id, git_branch, time_spent, created_at, updated_at "
        "FROM items WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    sqlite3_bind_int64(stmt, 1, id);
    
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    item->id = sqlite3_column_int64(stmt, 0);
    item->status = status_from_string((const char *)sqlite3_column_text(stmt, 1));
    str_safe_copy(item->title, (const char *)sqlite3_column_text(stmt, 2), sizeof(item->title));
    str_safe_copy(item->description, (const char *)sqlite3_column_text(stmt, 3), sizeof(item->description));
    str_safe_copy(item->tag, (const char *)sqlite3_column_text(stmt, 4), sizeof(item->tag));
    str_safe_copy(item->history, (const char *)sqlite3_column_text(stmt, 5), sizeof(item->history));
    item->priority = priority_from_string((const char *)sqlite3_column_text(stmt, 6));
    item->due_date = sqlite3_column_int64(stmt, 7);
    item->project_id = sqlite3_column_int64(stmt, 8);
    item->parent_id = sqlite3_column_int64(stmt, 9);
    str_safe_copy(item->git_branch, (const char *)sqlite3_column_text(stmt, 10), sizeof(item->git_branch));
    item->time_spent = sqlite3_column_int64(stmt, 11);
    item->created_at = sqlite3_column_int64(stmt, 12);
    item->updated_at = sqlite3_column_int64(stmt, 13);
    item->selected = false;
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_item_update(const Item *item) {
    if (!db || !item) return false;
    
    const char *sql = 
        "UPDATE items SET status = ?, title = ?, description = ?, tag = ?, history = ?, "
        "priority = ?, due_date = ?, project_id = ?, parent_id = ?, git_branch = ?, "
        "updated_at = strftime('%s', 'now') WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    sqlite3_bind_text(stmt, 1, STATUS_NAMES[item->status], -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, item->title, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, item->description, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, item->tag, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, item->history, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 6, PRIORITY_NAMES[item->priority], -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 7, item->due_date);
    sqlite3_bind_int64(stmt, 8, item->project_id);
    sqlite3_bind_int64(stmt, 9, item->parent_id);
    sqlite3_bind_text(stmt, 10, item->git_branch, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 11, item->id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_item_delete(int64_t id) {
    if (!db) return false;
    
    const char *sql = "DELETE FROM items WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    sqlite3_bind_int64(stmt, 1, id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_item_set_status(int64_t id, ItemStatus new_status) {
    Item item;
    if (!db_item_get(id, &item)) return false;
    
    ItemStatus old_status = item.status;
    item.status = new_status;
    
    size_t hlen = strlen(item.history);
    if (hlen < sizeof(item.history) - 1) {
        item.history[hlen] = STATUS_ABBREV[new_status];
        item.history[hlen + 1] = '\0';
    }
    
    if (db_item_update(&item)) {
        printf("%s -> %s\n", STATUS_DISPLAY[old_status], STATUS_DISPLAY[new_status]);
        return true;
    }
    return false;
}

static void ensure_list_capacity(ItemList *list, int needed) {
    if (list->capacity >= needed) return;
    int new_cap = list->capacity ? list->capacity * 2 : 16;
    while (new_cap < needed) new_cap *= 2;
    list->items = realloc(list->items, new_cap * sizeof(Item));
    list->capacity = new_cap;
}

bool db_items_list(ItemList *list, ItemStatus *filter_statuses, int filter_count) {
    if (!db || !list) return false;
    
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    
    char sql[512];
    int offset = 0;
    if (filter_count > 0) {
        offset = snprintf(sql, sizeof(sql), 
            "SELECT id, status, title, description, tag, history, priority, due_date, "
            "project_id, parent_id, git_branch, time_spent, created_at, updated_at "
            "FROM items WHERE status IN (");
        for (int i = 0; i < filter_count && offset < (int)sizeof(sql) - 32; i++) {
            offset += snprintf(sql + offset, sizeof(sql) - offset, "%s'%s'",
                              i > 0 ? "," : "", STATUS_NAMES[filter_statuses[i]]);
        }
        snprintf(sql + offset, sizeof(sql) - offset, ") ORDER BY id");
    } else {
        snprintf(sql, sizeof(sql), 
            "SELECT id, status, title, description, tag, history, priority, due_date, "
            "project_id, parent_id, git_branch, time_spent, created_at, updated_at "
            "FROM items ORDER BY id");
    }
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_list_capacity(list, list->count + 1);
        Item *item = &list->items[list->count];
        memset(item, 0, sizeof(Item));
        
        item->id = sqlite3_column_int64(stmt, 0);
        item->status = status_from_string((const char *)sqlite3_column_text(stmt, 1));
        str_safe_copy(item->title, (const char *)sqlite3_column_text(stmt, 2), sizeof(item->title));
        str_safe_copy(item->description, (const char *)sqlite3_column_text(stmt, 3), sizeof(item->description));
        str_safe_copy(item->tag, (const char *)sqlite3_column_text(stmt, 4), sizeof(item->tag));
        str_safe_copy(item->history, (const char *)sqlite3_column_text(stmt, 5), sizeof(item->history));
        item->priority = priority_from_string((const char *)sqlite3_column_text(stmt, 6));
        item->due_date = sqlite3_column_int64(stmt, 7);
        item->project_id = sqlite3_column_int64(stmt, 8);
        item->parent_id = sqlite3_column_int64(stmt, 9);
        str_safe_copy(item->git_branch, (const char *)sqlite3_column_text(stmt, 10), sizeof(item->git_branch));
        item->time_spent = sqlite3_column_int64(stmt, 11);
        item->created_at = sqlite3_column_int64(stmt, 12);
        item->updated_at = sqlite3_column_int64(stmt, 13);
        item->selected = false;
        
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

void db_items_free(ItemList *list) {
    if (list && list->items) {
        free(list->items);
        list->items = NULL;
        list->count = 0;
        list->capacity = 0;
    }
}

static void ensure_stat_capacity(StatList *list, int needed) {
    if (list->count >= needed) return;
    int new_cap = list->count ? list->count * 2 : 16;
    while (new_cap < needed) new_cap *= 2;
    list->entries = realloc(list->entries, new_cap * sizeof(StatEntry));
}

bool db_stats_by_status(StatList *list, const char *tag_filter) {
    if (!db || !list) return false;
    
    list->entries = NULL;
    list->count = 0;
    
    const char *sql = tag_filter && tag_filter[0] 
        ? "SELECT status, COUNT(*) FROM items WHERE tag = ? GROUP BY status ORDER BY COUNT(*) DESC"
        : "SELECT status, COUNT(*) FROM items GROUP BY status ORDER BY COUNT(*) DESC";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    if (tag_filter && tag_filter[0]) {
        sqlite3_bind_text(stmt, 1, tag_filter, -1, SQLITE_STATIC);
    }
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_stat_capacity(list, list->count + 1);
        StatEntry *entry = &list->entries[list->count];
        str_safe_copy(entry->name, (const char *)sqlite3_column_text(stmt, 0), sizeof(entry->name));
        entry->count = sqlite3_column_int(stmt, 1);
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_stats_by_tag(StatList *list, const char *status_filter) {
    if (!db || !list) return false;
    
    list->entries = NULL;
    list->count = 0;
    
    const char *sql = status_filter && status_filter[0]
        ? "SELECT tag, COUNT(*) FROM items WHERE status = ? AND tag != '' GROUP BY tag ORDER BY COUNT(*) DESC"
        : "SELECT tag, COUNT(*) FROM items WHERE tag != '' GROUP BY tag ORDER BY COUNT(*) DESC";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    if (status_filter && status_filter[0]) {
        sqlite3_bind_text(stmt, 1, status_filter, -1, SQLITE_STATIC);
    }
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_stat_capacity(list, list->count + 1);
        StatEntry *entry = &list->entries[list->count];
        str_safe_copy(entry->name, (const char *)sqlite3_column_text(stmt, 0), sizeof(entry->name));
        entry->count = sqlite3_column_int(stmt, 1);
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_stats_history(StatList *list) {
    if (!db || !list) return false;
    
    list->entries = NULL;
    list->count = 0;
    
    const char *sql = "SELECT history, COUNT(*) FROM items WHERE history != '' GROUP BY history ORDER BY COUNT(*) DESC LIMIT 20";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_stat_capacity(list, list->count + 1);
        StatEntry *entry = &list->entries[list->count];
        str_safe_copy(entry->name, (const char *)sqlite3_column_text(stmt, 0), sizeof(entry->name));
        entry->count = sqlite3_column_int(stmt, 1);
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_tags_list(StatList *list) {
    if (!db || !list) return false;
    
    list->entries = NULL;
    list->count = 0;
    
    const char *sql = "SELECT DISTINCT tag FROM items WHERE tag != '' ORDER BY tag";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_stat_capacity(list, list->count + 1);
        StatEntry *entry = &list->entries[list->count];
        str_safe_copy(entry->name, (const char *)sqlite3_column_text(stmt, 0), sizeof(entry->name));
        entry->count = 0;
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

void db_stats_free(StatList *list) {
    if (list && list->entries) {
        free(list->entries);
        list->entries = NULL;
        list->count = 0;
    }
}
