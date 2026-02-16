#include "db.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern sqlite3 *db_get_handle(void);

bool db_item_add_full(const Item *item, int64_t *out_id) {
    sqlite3 *db = db_get_handle();
    if (!db || !item) return false;
    
    const char *sql = 
        "INSERT INTO items (status, title, description, tag, history, priority, "
        "due_date, project_id, parent_id, git_branch, time_spent) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    char history[4] = {STATUS_ABBREV[item->status], '\0'};
    
    sqlite3_bind_text(stmt, 1, STATUS_NAMES[item->status], -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, item->title, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, item->description, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, item->tag, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, history, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 6, PRIORITY_NAMES[item->priority], -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 7, item->due_date);
    sqlite3_bind_int64(stmt, 8, item->project_id);
    sqlite3_bind_int64(stmt, 9, item->parent_id);
    sqlite3_bind_text(stmt, 10, item->git_branch, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 11, item->time_spent);
    
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE && out_id) {
        *out_id = sqlite3_last_insert_rowid(db);
    }
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_items_list_full(ItemList *list, int64_t project_id, ItemStatus *filter_statuses, int filter_count) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    
    char sql[1024];
    int offset = snprintf(sql, sizeof(sql),
        "SELECT id, status, title, description, tag, history, priority, "
        "due_date, project_id, parent_id, git_branch, time_spent, created_at, updated_at "
        "FROM items WHERE project_id = %lld", (long long)project_id);
    
    if (filter_count > 0) {
        offset += snprintf(sql + offset, sizeof(sql) - offset, " AND status IN (");
        for (int i = 0; i < filter_count && offset < (int)sizeof(sql) - 32; i++) {
            offset += snprintf(sql + offset, sizeof(sql) - offset, "%s'%s'",
                              i > 0 ? "," : "", STATUS_NAMES[filter_statuses[i]]);
        }
        snprintf(sql + offset, sizeof(sql) - offset, ")");
    }
    strncat(sql, " ORDER BY priority DESC, due_date ASC, id", sizeof(sql) - strlen(sql) - 1);
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (list->count >= list->capacity) {
            int new_cap = list->capacity ? list->capacity * 2 : 16;
            list->items = realloc(list->items, new_cap * sizeof(Item));
            list->capacity = new_cap;
        }
        Item *item = &list->items[list->count];
        
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

bool db_items_by_parent(ItemList *list, int64_t parent_id) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    
    const char *sql = 
        "SELECT id, status, title, description, tag, history, priority, "
        "due_date, project_id, parent_id, git_branch, time_spent, created_at, updated_at "
        "FROM items WHERE parent_id = ? ORDER BY id";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, parent_id);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (list->count >= list->capacity) {
            int new_cap = list->capacity ? list->capacity * 2 : 8;
            list->items = realloc(list->items, new_cap * sizeof(Item));
            list->capacity = new_cap;
        }
        Item *item = &list->items[list->count];
        
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

bool db_items_by_priority(ItemList *list, ItemPriority priority) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    
    const char *sql = 
        "SELECT id, status, title, description, tag, history, priority, "
        "due_date, project_id, parent_id, git_branch, time_spent, created_at, updated_at "
        "FROM items WHERE priority = ? ORDER BY due_date ASC, id";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, PRIORITY_NAMES[priority], -1, SQLITE_STATIC);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (list->count >= list->capacity) {
            int new_cap = list->capacity ? list->capacity * 2 : 16;
            list->items = realloc(list->items, new_cap * sizeof(Item));
            list->capacity = new_cap;
        }
        Item *item = &list->items[list->count];
        
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

bool db_items_due_before(ItemList *list, time_t deadline) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    
    const char *sql = 
        "SELECT id, status, title, description, tag, history, priority, "
        "due_date, project_id, parent_id, git_branch, time_spent, created_at, updated_at "
        "FROM items WHERE due_date > 0 AND due_date <= ? "
        "AND status NOT IN ('ready', 'wontfix') ORDER BY due_date ASC";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, deadline);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (list->count >= list->capacity) {
            int new_cap = list->capacity ? list->capacity * 2 : 16;
            list->items = realloc(list->items, new_cap * sizeof(Item));
            list->capacity = new_cap;
        }
        Item *item = &list->items[list->count];
        
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

bool db_stats_by_priority(StatList *list) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->entries = NULL;
    list->count = 0;
    
    const char *sql = "SELECT priority, COUNT(*) FROM items GROUP BY priority ORDER BY "
                      "CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 "
                      "WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        list->entries = realloc(list->entries, (list->count + 1) * sizeof(StatEntry));
        StatEntry *entry = &list->entries[list->count];
        
        const char *priority = (const char *)sqlite3_column_text(stmt, 0);
        str_safe_copy(entry->name, priority ? priority : "none", sizeof(entry->name));
        entry->count = sqlite3_column_int(stmt, 1);
        
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}
