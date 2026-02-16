#include "db.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern sqlite3 *db_get_handle(void);

bool db_project_add(const char *name, const char *description, int64_t *out_id) {
    sqlite3 *db = db_get_handle();
    if (!db || !name) return false;
    
    const char *sql = "INSERT INTO projects (name, description) VALUES (?, ?)";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, description ? description : "", -1, SQLITE_STATIC);
    
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE && out_id) {
        *out_id = sqlite3_last_insert_rowid(db);
    }
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_project_get(int64_t id, Project *project) {
    sqlite3 *db = db_get_handle();
    if (!db || !project) return false;
    
    const char *sql = "SELECT id, name, description, created_at FROM projects WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, id);
    
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    project->id = sqlite3_column_int64(stmt, 0);
    str_safe_copy(project->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(project->name));
    str_safe_copy(project->description, (const char *)sqlite3_column_text(stmt, 2), sizeof(project->description));
    project->created_at = sqlite3_column_int64(stmt, 3);
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_project_get_by_name(const char *name, Project *project) {
    sqlite3 *db = db_get_handle();
    if (!db || !project || !name) return false;
    
    const char *sql = "SELECT id, name, description, created_at FROM projects WHERE name = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    project->id = sqlite3_column_int64(stmt, 0);
    str_safe_copy(project->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(project->name));
    str_safe_copy(project->description, (const char *)sqlite3_column_text(stmt, 2), sizeof(project->description));
    project->created_at = sqlite3_column_int64(stmt, 3);
    
    sqlite3_finalize(stmt);
    return true;
}

bool db_project_delete(int64_t id) {
    sqlite3 *db = db_get_handle();
    if (!db || id == 0) return false;
    
    const char *sql = "DELETE FROM projects WHERE id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc == SQLITE_DONE) {
        const char *update_sql = "UPDATE items SET project_id = 0 WHERE project_id = ?";
        sqlite3_stmt *update_stmt;
        if (sqlite3_prepare_v2(db, update_sql, -1, &update_stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(update_stmt, 1, id);
            sqlite3_step(update_stmt);
            sqlite3_finalize(update_stmt);
        }
    }
    
    return rc == SQLITE_DONE;
}

bool db_projects_list(ProjectList *list) {
    sqlite3 *db = db_get_handle();
    if (!db || !list) return false;
    
    list->projects = NULL;
    list->count = 0;
    list->capacity = 0;
    
    const char *sql = "SELECT id, name, description, created_at FROM projects ORDER BY name";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (list->count >= list->capacity) {
            int new_cap = list->capacity ? list->capacity * 2 : 8;
            list->projects = realloc(list->projects, new_cap * sizeof(Project));
            list->capacity = new_cap;
        }
        Project *project = &list->projects[list->count];
        
        project->id = sqlite3_column_int64(stmt, 0);
        str_safe_copy(project->name, (const char *)sqlite3_column_text(stmt, 1), sizeof(project->name));
        str_safe_copy(project->description, (const char *)sqlite3_column_text(stmt, 2), sizeof(project->description));
        project->created_at = sqlite3_column_int64(stmt, 3);
        
        list->count++;
    }
    
    sqlite3_finalize(stmt);
    return true;
}

void db_projects_free(ProjectList *list) {
    if (list && list->projects) {
        free(list->projects);
        list->projects = NULL;
        list->count = 0;
        list->capacity = 0;
    }
}

bool db_dependency_add(int64_t from_id, int64_t to_id) {
    sqlite3 *db = db_get_handle();
    if (!db || from_id == to_id) return false;
    
    if (db_dependency_check_circular(from_id, to_id)) {
        fprintf(stderr, "Cannot add dependency: would create circular reference\n");
        return false;
    }
    
    const char *sql = "INSERT OR IGNORE INTO dependencies (from_id, to_id) VALUES (?, ?)";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, from_id);
    sqlite3_bind_int64(stmt, 2, to_id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_dependency_remove(int64_t from_id, int64_t to_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    const char *sql = "DELETE FROM dependencies WHERE from_id = ? AND to_id = ?";
    sqlite3_stmt *stmt;
    
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, from_id);
    sqlite3_bind_int64(stmt, 2, to_id);
    
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool db_dependencies_get(int64_t item_id, DependencyList *blockers, DependencyList *blocking) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;
    
    if (blockers) {
        blockers->deps = NULL;
        blockers->count = 0;
        blockers->capacity = 0;
        
        const char *sql = "SELECT from_id, to_id FROM dependencies WHERE from_id = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, item_id);
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                if (blockers->count >= blockers->capacity) {
                    int new_cap = blockers->capacity ? blockers->capacity * 2 : 4;
                    blockers->deps = realloc(blockers->deps, new_cap * sizeof(Dependency));
                    blockers->capacity = new_cap;
                }
                blockers->deps[blockers->count].from_id = sqlite3_column_int64(stmt, 0);
                blockers->deps[blockers->count].to_id = sqlite3_column_int64(stmt, 1);
                blockers->count++;
            }
            sqlite3_finalize(stmt);
        }
    }
    
    if (blocking) {
        blocking->deps = NULL;
        blocking->count = 0;
        blocking->capacity = 0;
        
        const char *sql = "SELECT from_id, to_id FROM dependencies WHERE to_id = ?";
        sqlite3_stmt *stmt;
        
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, item_id);
            
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                if (blocking->count >= blocking->capacity) {
                    int new_cap = blocking->capacity ? blocking->capacity * 2 : 4;
                    blocking->deps = realloc(blocking->deps, new_cap * sizeof(Dependency));
                    blocking->capacity = new_cap;
                }
                blocking->deps[blocking->count].from_id = sqlite3_column_int64(stmt, 0);
                blocking->deps[blocking->count].to_id = sqlite3_column_int64(stmt, 1);
                blocking->count++;
            }
            sqlite3_finalize(stmt);
        }
    }
    
    return true;
}

bool db_dependency_check_circular(int64_t from_id, int64_t to_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return true;
    
    const char *sql = 
        "WITH RECURSIVE chain(id) AS ("
        "  SELECT ? "
        "  UNION "
        "  SELECT d.to_id FROM dependencies d, chain c WHERE d.from_id = c.id"
        ") SELECT 1 FROM chain WHERE id = ? LIMIT 1";
    
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return true;
    
    sqlite3_bind_int64(stmt, 1, to_id);
    sqlite3_bind_int64(stmt, 2, from_id);
    
    bool circular = (sqlite3_step(stmt) == SQLITE_ROW);
    sqlite3_finalize(stmt);
    
    return circular;
}

void db_dependencies_free(DependencyList *list) {
    if (list && list->deps) {
        free(list->deps);
        list->deps = NULL;
        list->count = 0;
        list->capacity = 0;
    }
}
