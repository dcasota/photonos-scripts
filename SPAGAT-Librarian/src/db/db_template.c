#include "db.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern sqlite3 *db_get_handle(void);

bool db_template_add(const Template *tmpl, int64_t *out_id) {
    sqlite3 *db = db_get_handle();
    if (!db || !tmpl) return false;
    
    const char *sql = 
        "INSERT INTO templates (name, title, description, tag, status, priority) "
        "VALUES (?, ?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    sqlite3_bind_text(stmt, 1, tmpl->name, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, tmpl->title, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, tmpl->description, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, tmpl->tag, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 5, STATUS_NAMES[tmpl->status], -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 6, PRIORITY_NAMES[tmpl->priority], -1, SQLITE_STATIC);
    
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE && out_id) {
        *out_id = sqlite3_last_insert_rowid(db);
    }
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_template_get(int64_t id, Template *tmpl) {
    sqlite3 *db = db_get_handle();
    if (!db || !tmpl) return false;
    
    const char *sql = "SELECT id, name, title, description, tag, status, priority FROM templates WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, id);
    
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    tmpl->id = sqlite3_column_int64(stmt, 0);
    str_safe_copy(tmpl->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(tmpl->name));
    str_safe_copy(tmpl->title, (const char *)sqlite3_column_text(stmt, 2), sizeof(tmpl->title));
    str_safe_copy(tmpl->description, (const char *)sqlite3_column_text(stmt, 3), sizeof(tmpl->description));
    str_safe_copy(tmpl->tag, (const char *)sqlite3_column_text(stmt, 4), sizeof(tmpl->tag));
    tmpl->status = status_from_string((const char *)sqlite3_column_text(stmt, 5));
    tmpl->priority = priority_from_string((const char *)sqlite3_column_text(stmt, 6));
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_template_get_by_name(const char *name, Template *tmpl) {
    sqlite3 *db = db_get_handle();
    if (!db || !tmpl || !name) return false;
    
    const char *sql = "SELECT id, name, title, description, tag, status, priority FROM templates WHERE name = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    tmpl->id = sqlite3_column_int64(stmt, 0);
    str_safe_copy(tmpl->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(tmpl->name));
    str_safe_copy(tmpl->title, (const char *)sqlite3_column_text(stmt, 2), sizeof(tmpl->title));
    str_safe_copy(tmpl->description, (const char *)sqlite3_column_text(stmt, 3), sizeof(tmpl->description));
    str_safe_copy(tmpl->tag, (const char *)sqlite3_column_text(stmt, 4), sizeof(tmpl->tag));
    tmpl->status = status_from_string((const char *)sqlite3_column_text(stmt, 5));
    tmpl->priority = priority_from_string((const char *)sqlite3_column_text(stmt, 6));
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_template_delete(int64_t id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    const char *sql = "DELETE FROM templates WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_templates_list(TemplateList *list) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->templates = NULL;
    list->count = 0;
    list->capacity = 0;
    
    const char *sql = "SELECT id, name, title, description, tag, status, priority FROM templates ORDER BY name";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (list->count >= list->capacity) {
            int new_cap = list->capacity ? list->capacity * 2 : 8;
            list->templates = realloc(list->templates, new_cap * sizeof(Template));
            list->capacity = new_cap;
        }
        Template *tmpl = &list->templates[list->count];
        
        tmpl->id = sqlite3_column_int64(stmt, 0);
        str_safe_copy(tmpl->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(tmpl->name));
        str_safe_copy(tmpl->title, (const char *)sqlite3_column_text(stmt, 2), sizeof(tmpl->title));
        str_safe_copy(tmpl->description, (const char *)sqlite3_column_text(stmt, 3), sizeof(tmpl->description));
        str_safe_copy(tmpl->tag, (const char *)sqlite3_column_text(stmt, 4), sizeof(tmpl->tag));
        tmpl->status = status_from_string((const char *)sqlite3_column_text(stmt, 5));
        tmpl->priority = priority_from_string((const char *)sqlite3_column_text(stmt, 6));
        
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

void db_templates_free(TemplateList *list) {
    if (list && list->templates) {
        free(list->templates);
        list->templates = NULL;
        list->count = 0;
        list->capacity = 0;
    }
}

bool db_item_from_template(const char *template_name, int64_t *out_id) {
    Template tmpl;
    if (!db_template_get_by_name(template_name, &tmpl)) {
        return false;
    }
    
    Item item = {0};
    item.status = tmpl.status;
    item.priority = tmpl.priority;
    str_safe_copy(item.title, tmpl.title, sizeof(item.title));
    str_safe_copy(item.description, tmpl.description, sizeof(item.description));
    str_safe_copy(item.tag, tmpl.tag, sizeof(item.tag));
    
    return db_item_add_full(&item, out_id);
}

bool db_session_save(const Session *session) {
    sqlite3 *db = db_get_handle();
    if (!db || !session) return false;
    
    char scroll_str[128] = {0};
    int offset = 0;
    for (int i = 0; i < STATUS_COUNT && offset < (int)sizeof(scroll_str) - 12; i++) {
        offset += snprintf(scroll_str + offset, sizeof(scroll_str) - offset, 
                          "%s%d", i > 0 ? "," : "", session->scroll_offsets[i]);
    }
    
    const char *sql = 
        "INSERT OR REPLACE INTO sessions (name, current_project, current_col, current_row, "
        "scroll_offsets, swimlane_mode, saved_at) VALUES (?, ?, ?, ?, ?, ?, strftime('%s', 'now'))";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    sqlite3_bind_text(stmt, 1, session->name, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, session->current_project);
    sqlite3_bind_int(stmt, 3, session->current_col);
    sqlite3_bind_int(stmt, 4, session->current_row);
    sqlite3_bind_text(stmt, 5, scroll_str, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 6, session->swimlane_mode ? 1 : 0);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_session_load(const char *name, Session *session) {
    sqlite3 *db = db_get_handle();
    if (!db || !session || !name) return false;
    
    const char *sql = 
        "SELECT id, name, current_project, current_col, current_row, scroll_offsets, "
        "swimlane_mode, saved_at FROM sessions WHERE name = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    session->id = sqlite3_column_int64(stmt, 0);
    str_safe_copy(session->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(session->name));
    session->current_project = sqlite3_column_int(stmt, 2);
    session->current_col = sqlite3_column_int(stmt, 3);
    session->current_row = sqlite3_column_int(stmt, 4);
    
    const char *scroll_str = (const char *)sqlite3_column_text(stmt, 5);
    if (scroll_str) {
        int idx = 0;
        char *copy = strdup(scroll_str);
        char *token = strtok(copy, ",");
        while (token && idx < STATUS_COUNT) {
            session->scroll_offsets[idx++] = atoi(token);
            token = strtok(NULL, ",");
        }
        free(copy);
    }
    
    session->swimlane_mode = sqlite3_column_int(stmt, 6) != 0;
    session->saved_at = sqlite3_column_int64(stmt, 7);
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_session_delete(const char *name) {
    sqlite3 *db = db_get_handle();
    if (!db || !name) return false;
    
    const char *sql = "DELETE FROM sessions WHERE name = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_time_start(int64_t item_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    const char *check_sql = "SELECT id FROM time_entries WHERE item_id = ? AND ended_at = 0";
    sqlite3_stmt *check_stmt;
    if (sqlite3_prepare_v2(db, check_sql, -1, &check_stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(check_stmt, 1, item_id);
        if (sqlite3_step(check_stmt) == SQLITE_ROW) {
            sqlite3_finalize(check_stmt);
            return true;
        }
        sqlite3_finalize(check_stmt);
    }
    
    const char *sql = "INSERT INTO time_entries (item_id, started_at) VALUES (?, strftime('%s', 'now'))";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, item_id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_time_stop(int64_t item_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    const char *sql = 
        "UPDATE time_entries SET ended_at = strftime('%s', 'now') "
        "WHERE item_id = ? AND ended_at = 0";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, item_id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc == SQLITE_DONE) {
        const char *update_sql = 
            "UPDATE items SET time_spent = ("
            "  SELECT COALESCE(SUM(ended_at - started_at), 0) FROM time_entries "
            "  WHERE item_id = ? AND ended_at > 0"
            ") WHERE id = ?";
        sqlite3_stmt *update_stmt;
        if (sqlite3_prepare_v2(db, update_sql, -1, &update_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(update_stmt, 1, item_id);
            sqlite3_bind_int64(update_stmt, 2, item_id);
            sqlite3_step(update_stmt);
            sqlite3_finalize(update_stmt);
        }
    }
    
    return rc == SQLITE_DONE;
}

time_t db_time_get_total(int64_t item_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return 0;
    
    const char *sql = 
        "SELECT COALESCE(SUM(CASE WHEN ended_at > 0 THEN ended_at - started_at "
        "ELSE strftime('%s', 'now') - started_at END), 0) "
        "FROM time_entries WHERE item_id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return 0;
    sqlite3_bind_int64(stmt, 1, item_id);
    
    time_t total = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        total = sqlite3_column_int64(stmt, 0);
    }
    sqlite3_finalize(stmt);
    
    return total;
}
