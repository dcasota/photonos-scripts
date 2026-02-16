#include "cli.h"
#include "../db/db.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int cmd_project_add(const char *name, const char *description) {
    int64_t id;
    if (!db_project_add(name, description ? description : "", &id)) {
        fprintf(stderr, "Failed to create project '%s'\n", name);
        return 1;
    }
    printf("Created project #%lld: %s\n", (long long)id, name);
    return 0;
}

int cmd_project_list(void) {
    ProjectList list;
    if (!db_projects_list(&list)) {
        fprintf(stderr, "Failed to list projects\n");
        return 1;
    }
    
    printf("%-4s  %-20s  %s\n", "ID", "Name", "Description");
    printf("%-4s  %-20s  %s\n", "-", "-", "-");
    
    for (int i = 0; i < list.count; i++) {
        Project *p = &list.projects[i];
        printf("%-4lld  %-20s  %s\n", (long long)p->id, p->name, p->description);
    }
    
    db_projects_free(&list);
    return 0;
}

int cmd_project_delete(const char *name) {
    Project project;
    if (!db_project_get_by_name(name, &project)) {
        fprintf(stderr, "Project '%s' not found\n", name);
        return 1;
    }
    
    if (project.id == 0) {
        fprintf(stderr, "Cannot delete default project\n");
        return 1;
    }
    
    if (!db_project_delete(project.id)) {
        fprintf(stderr, "Failed to delete project\n");
        return 1;
    }
    
    printf("Deleted project '%s'\n", name);
    return 0;
}

int cmd_template_add(const char *name, const char *title, const char *desc, 
                     const char *tag, const char *status, const char *priority) {
    Template tmpl = {0};
    str_safe_copy(tmpl.name, name, sizeof(tmpl.name));
    str_safe_copy(tmpl.title, title ? title : "", sizeof(tmpl.title));
    str_safe_copy(tmpl.description, desc ? desc : "", sizeof(tmpl.description));
    str_safe_copy(tmpl.tag, tag ? tag : "", sizeof(tmpl.tag));
    tmpl.status = status ? status_from_string(status) : STATUS_BACKLOG;
    tmpl.priority = priority ? priority_from_string(priority) : PRIORITY_NONE;
    
    int64_t id;
    if (!db_template_add(&tmpl, &id)) {
        fprintf(stderr, "Failed to create template '%s'\n", name);
        return 1;
    }
    
    printf("Created template #%lld: %s\n", (long long)id, name);
    return 0;
}

int cmd_template_list(void) {
    TemplateList list;
    if (!db_templates_list(&list)) {
        fprintf(stderr, "Failed to list templates\n");
        return 1;
    }
    
    printf("%-4s  %-20s  %-14s  %-10s  %s\n", "ID", "Name", "Status", "Priority", "Title");
    printf("%-4s  %-20s  %-14s  %-10s  %s\n", "-", "-", "-", "-", "-");
    
    for (int i = 0; i < list.count; i++) {
        Template *t = &list.templates[i];
        printf("%-4lld  %-20s  %-14s  %-10s  %s\n",
               (long long)t->id, t->name, STATUS_NAMES[t->status],
               PRIORITY_NAMES[t->priority], t->title);
    }
    
    db_templates_free(&list);
    return 0;
}

int cmd_template_use(const char *name) {
    int64_t id;
    if (!db_item_from_template(name, &id)) {
        fprintf(stderr, "Failed to create item from template '%s'\n", name);
        return 1;
    }
    
    printf("Created item #%lld from template '%s'\n", (long long)id, name);
    return 0;
}

int cmd_dependency_add(int64_t from_id, int64_t to_id) {
    if (!db_dependency_add(from_id, to_id)) {
        fprintf(stderr, "Failed to add dependency\n");
        return 1;
    }
    printf("Item #%lld now depends on #%lld\n", (long long)from_id, (long long)to_id);
    return 0;
}

int cmd_dependency_remove(int64_t from_id, int64_t to_id) {
    if (!db_dependency_remove(from_id, to_id)) {
        fprintf(stderr, "Failed to remove dependency\n");
        return 1;
    }
    printf("Removed dependency: #%lld -> #%lld\n", (long long)from_id, (long long)to_id);
    return 0;
}

int cmd_dependency_list(int64_t item_id) {
    DependencyList blockers, blocking;
    if (!db_dependencies_get(item_id, &blockers, &blocking)) {
        fprintf(stderr, "Failed to get dependencies\n");
        return 1;
    }
    
    printf("Item #%lld dependencies:\n", (long long)item_id);
    
    if (blockers.count > 0) {
        printf("  Blocked by:\n");
        for (int i = 0; i < blockers.count; i++) {
            Item item;
            if (db_item_get(blockers.deps[i].to_id, &item)) {
                printf("    #%lld: %s\n", (long long)item.id, item.title);
            }
        }
    }
    
    if (blocking.count > 0) {
        printf("  Blocking:\n");
        for (int i = 0; i < blocking.count; i++) {
            Item item;
            if (db_item_get(blocking.deps[i].from_id, &item)) {
                printf("    #%lld: %s\n", (long long)item.id, item.title);
            }
        }
    }
    
    if (blockers.count == 0 && blocking.count == 0) {
        printf("  No dependencies\n");
    }
    
    db_dependencies_free(&blockers);
    db_dependencies_free(&blocking);
    return 0;
}

int cmd_subtasks(int64_t parent_id) {
    ItemList list;
    if (!db_items_by_parent(&list, parent_id)) {
        fprintf(stderr, "Failed to get subtasks\n");
        return 1;
    }
    
    if (list.count == 0) {
        printf("No subtasks for item #%lld\n", (long long)parent_id);
    } else {
        printf("Subtasks for #%lld:\n", (long long)parent_id);
        for (int i = 0; i < list.count; i++) {
            Item *item = &list.items[i];
            printf("  #%-4lld  %-14s  %s\n", (long long)item->id, 
                   STATUS_NAMES[item->status], item->title);
        }
    }
    
    db_items_free(&list);
    return 0;
}

int cmd_due(const char *when) {
    time_t deadline;
    time_t now = time(NULL);
    
    if (str_equals_ignore_case(when, "today")) {
        struct tm *tm = localtime(&now);
        tm->tm_hour = 23;
        tm->tm_min = 59;
        tm->tm_sec = 59;
        deadline = mktime(tm);
    } else if (str_equals_ignore_case(when, "tomorrow")) {
        deadline = now + 86400 * 2;
    } else if (str_equals_ignore_case(when, "week")) {
        deadline = now + 86400 * 7;
    } else if (str_equals_ignore_case(when, "overdue")) {
        deadline = now;
    } else {
        deadline = now + 86400 * 30;
    }
    
    ItemList list;
    if (!db_items_due_before(&list, deadline)) {
        fprintf(stderr, "Failed to get due items\n");
        return 1;
    }
    
    if (list.count == 0) {
        printf("No items due %s\n", when);
    } else {
        printf("Items due %s:\n", when);
        for (int i = 0; i < list.count; i++) {
            Item *item = &list.items[i];
            char date_str[32] = "none";
            if (item->due_date > 0) {
                struct tm *tm = localtime(&item->due_date);
                strftime(date_str, sizeof(date_str), "%Y-%m-%d", tm);
            }
            printf("  #%-4lld  %-10s  %-14s  %s\n", (long long)item->id,
                   date_str, STATUS_NAMES[item->status], item->title);
        }
    }
    
    db_items_free(&list);
    return 0;
}

int cmd_time_start(int64_t item_id) {
    if (!db_time_start(item_id)) {
        fprintf(stderr, "Failed to start timer\n");
        return 1;
    }
    printf("Timer started for item #%lld\n", (long long)item_id);
    return 0;
}

int cmd_time_stop(int64_t item_id) {
    if (!db_time_stop(item_id)) {
        fprintf(stderr, "Failed to stop timer\n");
        return 1;
    }
    
    time_t total = db_time_get_total(item_id);
    int hours = total / 3600;
    int minutes = (total % 3600) / 60;
    
    printf("Timer stopped for item #%lld. Total time: %dh %dm\n",
           (long long)item_id, hours, minutes);
    return 0;
}

int cmd_session_save(const char *name) {
    Session session = {0};
    str_safe_copy(session.name, name, sizeof(session.name));
    
    if (!db_session_save(&session)) {
        fprintf(stderr, "Failed to save session '%s'\n", name);
        return 1;
    }
    printf("Session '%s' saved\n", name);
    return 0;
}

int cmd_session_load(const char *name) {
    Session session;
    if (!db_session_load(name, &session)) {
        fprintf(stderr, "Session '%s' not found\n", name);
        return 1;
    }
    printf("Session '%s' loaded (col=%d, row=%d, swimlane=%s)\n",
           session.name, session.current_col, session.current_row,
           session.swimlane_mode ? "on" : "off");
    return 0;
}

int cmd_priority_list(const char *priority) {
    ItemPriority p = priority_from_string(priority);
    
    ItemList list;
    if (!db_items_by_priority(&list, p)) {
        fprintf(stderr, "Failed to get items\n");
        return 1;
    }
    
    printf("Items with %s priority:\n", PRIORITY_DISPLAY[p]);
    for (int i = 0; i < list.count; i++) {
        Item *item = &list.items[i];
        printf("  #%-4lld  %-14s  %s\n", (long long)item->id,
               STATUS_NAMES[item->status], item->title);
    }
    
    db_items_free(&list);
    return 0;
}

void cli_ext_print_usage(void) {
    printf("\nExtended Commands:\n");
    printf("  project add <name> [desc]              Create project\n");
    printf("  project list                           List projects\n");
    printf("  project delete <name>                  Delete project\n");
    printf("  template add <name> [title] [options]  Create template\n");
    printf("  template list                          List templates\n");
    printf("  template use <name>                    Create item from template\n");
    printf("  depend <from_id> <to_id>               Add dependency\n");
    printf("  undepend <from_id> <to_id>             Remove dependency\n");
    printf("  deps <id>                              Show dependencies\n");
    printf("  subtasks <id>                          List subtasks\n");
    printf("  due <today|tomorrow|week|overdue>      Show due items\n");
    printf("  time start <id>                        Start timer\n");
    printf("  time stop <id>                         Stop timer\n");
    printf("  session save <name>                    Save session\n");
    printf("  session load <name>                    Load session\n");
    printf("  priority <critical|high|medium|low>    List by priority\n");
}
