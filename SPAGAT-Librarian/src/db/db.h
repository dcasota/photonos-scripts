#ifndef DB_H
#define DB_H

#include "spagat.h"
#include <stdbool.h>

typedef struct sqlite3 sqlite3;

bool db_open(const char *path);
void db_close(void);
bool db_init_schema(void);
sqlite3 *db_get_handle(void);

bool db_item_add(const char *status, const char *title, const char *description, const char *tag, int64_t *out_id);
bool db_item_add_full(const Item *item, int64_t *out_id);
bool db_item_get(int64_t id, Item *item);
bool db_item_update(const Item *item);
bool db_item_delete(int64_t id);
bool db_item_set_status(int64_t id, ItemStatus new_status);
bool db_item_update_history(int64_t id, ItemStatus old_status, ItemStatus new_status);

bool db_items_list(ItemList *list, ItemStatus *filter_statuses, int filter_count);
bool db_items_list_full(ItemList *list, int64_t project_id, ItemStatus *filter_statuses, int filter_count);
bool db_items_by_tag(ItemList *list, const char *tag);
bool db_items_by_parent(ItemList *list, int64_t parent_id);
bool db_items_by_priority(ItemList *list, ItemPriority priority);
bool db_items_due_before(ItemList *list, time_t deadline);
void db_items_free(ItemList *list);

bool db_project_add(const char *name, const char *description, int64_t *out_id);
bool db_project_get(int64_t id, Project *project);
bool db_project_get_by_name(const char *name, Project *project);
bool db_project_delete(int64_t id);
bool db_projects_list(ProjectList *list);
void db_projects_free(ProjectList *list);

bool db_dependency_add(int64_t from_id, int64_t to_id);
bool db_dependency_remove(int64_t from_id, int64_t to_id);
bool db_dependencies_get(int64_t item_id, DependencyList *blockers, DependencyList *blocking);
bool db_dependency_check_circular(int64_t from_id, int64_t to_id);
void db_dependencies_free(DependencyList *list);

bool db_template_add(const Template *tmpl, int64_t *out_id);
bool db_template_get(int64_t id, Template *tmpl);
bool db_template_get_by_name(const char *name, Template *tmpl);
bool db_template_delete(int64_t id);
bool db_templates_list(TemplateList *list);
void db_templates_free(TemplateList *list);
bool db_item_from_template(const char *template_name, int64_t *out_id);

bool db_session_save(const Session *session);
bool db_session_load(const char *name, Session *session);
bool db_session_delete(const char *name);

bool db_time_start(int64_t item_id);
bool db_time_stop(int64_t item_id);
time_t db_time_get_total(int64_t item_id);

typedef struct {
    char name[64];
    int count;
} StatEntry;

typedef struct {
    StatEntry *entries;
    int count;
} StatList;

bool db_stats_by_status(StatList *list, const char *tag_filter);
bool db_stats_by_tag(StatList *list, const char *status_filter);
bool db_stats_by_priority(StatList *list);
bool db_stats_history(StatList *list);
bool db_tags_list(StatList *list);
void db_stats_free(StatList *list);

#endif
