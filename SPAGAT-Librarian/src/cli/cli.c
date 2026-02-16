#include "cli.h"
#include "../db/db.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

void cli_print_usage(void) {
    printf("SPAGAT-Librarian v%s - Kanban Task Manager\n\n", SPAGAT_VERSION);
    printf("Usage:\n");
    printf("  spagat-librarian                           Launch TUI dashboard\n");
    printf("  spagat-librarian init                      Initialize database\n");
    printf("  spagat-librarian add                       Add item interactively\n");
    printf("  spagat-librarian add <status> <tag> <desc> Add new item\n");
    printf("  spagat-librarian <id>                      Edit item\n");
    printf("  spagat-librarian <id> <status>             Move item to status\n");
    printf("  spagat-librarian show [status...]          Display board\n");
    printf("  spagat-librarian list                      List all items\n");
    printf("  spagat-librarian <status> [status...]      List items by status\n");
    printf("  spagat-librarian tags                      List all tags\n");
    printf("  spagat-librarian stats <type> [filter]     Show statistics\n");
    printf("  spagat-librarian delete <id>               Delete item\n");
    printf("  spagat-librarian export <csv|json>         Export data\n");
    printf("\nStatuses:\n");
    printf("  clarification  wontfix  backlog  progress  review  ready\n");
    printf("\nEnvironment:\n");
    printf("  NOCOLOR=1      Disable colors\n");
    printf("  PLAIN=1        Use ASCII instead of UTF-8\n");
    printf("  EDITOR         Editor for editing items\n");
    printf("  SPAGAT_DB      Custom database path\n");
}

void cli_print_version(void) {
    printf("SPAGAT-Librarian v%s\n", SPAGAT_VERSION);
}

int cmd_init(void) {
    char *path = get_db_path();
    
    if (file_exists(path)) {
        printf("Database already exists at %s\n", path);
        return 0;
    }
    
    if (!db_open(path)) {
        fprintf(stderr, "Failed to create database\n");
        return 1;
    }
    
    if (!db_init_schema()) {
        fprintf(stderr, "Failed to initialize schema\n");
        db_close();
        return 1;
    }
    
    printf("Initialized database at %s\n", path);
    db_close();
    return 0;
}

int cmd_add(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "Usage: spagat-librarian add <status> <title> <description> [tag]\n");
        return 1;
    }
    
    const char *status = argv[0];
    const char *title = argv[1];
    const char *description = argv[2];
    const char *tag = argc > 3 ? argv[3] : "";
    
    if (status_from_string(status) == STATUS_BACKLOG && 
        !str_equals_ignore_case(status, "backlog")) {
        fprintf(stderr, "Invalid status: %s\n", status);
        return 1;
    }
    
    int64_t id;
    if (!db_item_add(status, title, description, tag, &id)) {
        fprintf(stderr, "Failed to add item\n");
        return 1;
    }
    
    printf("Added item #%lld\n", (long long)id);
    return 0;
}

int cmd_add_interactive(void) {
    char title[SPAGAT_MAX_TITLE_LEN];
    char description[SPAGAT_MAX_DESC_LEN];
    char status[32];
    char tag[SPAGAT_MAX_TAG_LEN];
    
    printf("Enter title:\n> ");
    if (!fgets(title, sizeof(title), stdin)) return 1;
    str_trim(title);
    
    if (!title[0]) {
        fprintf(stderr, "Title cannot be empty\n");
        return 1;
    }
    
    printf("Enter description:\n> ");
    if (!fgets(description, sizeof(description), stdin)) return 1;
    str_trim(description);
    
    printf("Enter status (clarification/wontfix/backlog/progress/review/ready):\n> ");
    if (!fgets(status, sizeof(status), stdin)) return 1;
    str_trim(status);
    
    if (!status[0]) strcpy(status, "backlog");
    
    printf("Enter tag:\n> ");
    if (!fgets(tag, sizeof(tag), stdin)) return 1;
    str_trim(tag);
    
    int64_t id;
    if (!db_item_add(status, title, description, tag, &id)) {
        fprintf(stderr, "Failed to add item\n");
        return 1;
    }
    
    printf("Added item #%lld\n", (long long)id);
    return 0;
}

static void print_bar(int count, int max_count, int max_width) {
    int width = max_count > 0 ? (count * max_width) / max_count : 0;
    if (width < 1 && count > 0) width = 1;
    for (int i = 0; i < width; i++) {
        printf("%s", env_is_set("PLAIN") ? "#" : "\xe2\x96\x86");
    }
}

static void print_board_line(bool use_utf8) {
    if (use_utf8) {
        printf("\xe2\x94\x80");
    } else {
        printf("-");
    }
}

static void print_board_corner(bool use_utf8, bool left) {
    if (use_utf8) {
        printf(left ? "\xe2\x94\x8c" : "\xe2\x94\x90");
    } else {
        printf("+");
    }
}

int cmd_show(int argc, char **argv) {
    bool use_color = !env_is_set("NOCOLOR");
    bool use_utf8 = !env_is_set("PLAIN");
    
    ItemStatus filter[STATUS_COUNT];
    int filter_count = 0;
    
    for (int i = 0; i < argc && filter_count < STATUS_COUNT; i++) {
        ItemStatus s = status_from_string(argv[i]);
        filter[filter_count++] = s;
    }
    
    ItemList list;
    if (!db_items_list(&list, filter_count > 0 ? filter : NULL, filter_count)) {
        fprintf(stderr, "Failed to load items\n");
        return 1;
    }
    
    int cols_to_show = filter_count > 0 ? filter_count : STATUS_COUNT;
    int col_width = 20;
    
    for (int c = 0; c < cols_to_show; c++) {
        print_board_corner(use_utf8, true);
        for (int i = 0; i < col_width - 2; i++) print_board_line(use_utf8);
        print_board_corner(use_utf8, false);
        printf("  ");
    }
    printf("\n");
    
    for (int c = 0; c < cols_to_show; c++) {
        ItemStatus st = filter_count > 0 ? filter[c] : (ItemStatus)c;
        const char *name = STATUS_DISPLAY[st];
        
        printf("|");
        if (use_color) printf("\033[1m");
        int pad = (col_width - 2 - (int)strlen(name)) / 2;
        for (int i = 0; i < pad; i++) printf(" ");
        printf("%s", name);
        for (int i = 0; i < col_width - 2 - pad - (int)strlen(name); i++) printf(" ");
        if (use_color) printf("\033[0m");
        printf("|  ");
    }
    printf("\n");
    
    for (int c = 0; c < cols_to_show; c++) {
        printf("|");
        for (int i = 0; i < col_width - 2; i++) printf(" ");
        printf("|  ");
    }
    printf("\n");
    
    int max_items = 0;
    for (int c = 0; c < cols_to_show; c++) {
        ItemStatus st = filter_count > 0 ? filter[c] : (ItemStatus)c;
        int cnt = 0;
        for (int i = 0; i < list.count; i++) {
            if (list.items[i].status == st) cnt++;
        }
        if (cnt > max_items) max_items = cnt;
    }
    
    for (int row = 0; row < max_items; row++) {
        for (int c = 0; c < cols_to_show; c++) {
            ItemStatus st = filter_count > 0 ? filter[c] : (ItemStatus)c;
            
            int found = 0;
            int idx = 0;
            for (int i = 0; i < list.count; i++) {
                if (list.items[i].status == st) {
                    if (found == row) {
                        idx = i;
                        break;
                    }
                    found++;
                }
            }
            
            printf("|");
            if (found == row && row < list.count) {
                Item *item = &list.items[idx];
                char line[160];
                snprintf(line, sizeof(line), " %lld %s", (long long)item->id, item->title);
                line[col_width - 3] = '\0';
                
                if (use_color) {
                    printf("\033[36m%s\033[0m", line);
                } else {
                    printf("%s", line);
                }
                for (int i = strlen(line); i < col_width - 2; i++) printf(" ");
            } else {
                for (int i = 0; i < col_width - 2; i++) printf(" ");
            }
            printf("|  ");
        }
        printf("\n");
    }
    
    db_items_free(&list);
    return 0;
}

int cmd_list(void) {
    bool use_color = !env_is_set("NOCOLOR");
    
    ItemList list;
    if (!db_items_list(&list, NULL, 0)) {
        fprintf(stderr, "Failed to load items\n");
        return 1;
    }
    
    printf("%-4s  %-14s  %-20s  %-12s  %s\n", "id", "status", "title", "tag", "history");
    printf("%-4s  %-14s  %-20s  %-12s  %s\n", "-", "-", "-", "-", "-");
    
    for (int i = 0; i < list.count; i++) {
        Item *item = &list.items[i];
        char title_short[21];
        str_safe_copy(title_short, item->title, sizeof(title_short));
        
        if (use_color) printf("\033[33m");
        printf("%-4lld", (long long)item->id);
        if (use_color) printf("\033[0m");
        
        printf("  %-14s  %-20s  %-12s  %s\n",
               STATUS_NAMES[item->status],
               title_short,
               item->tag,
               item->history);
    }
    
    db_items_free(&list);
    return 0;
}

int cmd_edit(int64_t id) {
    Item item;
    if (!db_item_get(id, &item)) {
        fprintf(stderr, "Item #%lld not found\n", (long long)id);
        return 1;
    }
    
    char tmpfile[256];
    snprintf(tmpfile, sizeof(tmpfile), "/tmp/spagat_%lld.txt", (long long)id);
    
    FILE *f = fopen(tmpfile, "w");
    if (!f) {
        fprintf(stderr, "Failed to create temp file\n");
        return 1;
    }
    fprintf(f, "%s", item.description);
    fclose(f);
    
    const char *editor = get_editor();
    pid_t pid = fork();
    if (pid == 0) {
        execlp(editor, editor, tmpfile, (char *)NULL);
        _exit(1);
    } else if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
    } else {
        fprintf(stderr, "Failed to launch editor\n");
        remove(tmpfile);
        return 1;
    }
    
    f = fopen(tmpfile, "r");
    if (f) {
        char new_desc[SPAGAT_MAX_DESC_LEN] = {0};
        (void)fread(new_desc, 1, sizeof(new_desc) - 1, f);
        fclose(f);
        
        str_trim(new_desc);
        if (new_desc[0] && strcmp(new_desc, item.description) != 0) {
            str_safe_copy(item.description, new_desc, sizeof(item.description));
            if (db_item_update(&item)) {
                printf("Updated item #%lld\n", (long long)id);
            }
        }
    }
    
    remove(tmpfile);
    return 0;
}

int cmd_move(int64_t id, const char *new_status) {
    ItemStatus st = status_from_string(new_status);
    
    if (!db_item_set_status(id, st)) {
        fprintf(stderr, "Failed to move item #%lld\n", (long long)id);
        return 1;
    }
    
    return 0;
}

int cmd_delete(int64_t id) {
    if (!db_item_delete(id)) {
        fprintf(stderr, "Failed to delete item #%lld\n", (long long)id);
        return 1;
    }
    printf("Deleted item #%lld\n", (long long)id);
    return 0;
}

int cmd_tags(void) {
    StatList list;
    if (!db_tags_list(&list)) {
        fprintf(stderr, "Failed to load tags\n");
        return 1;
    }
    
    for (int i = 0; i < list.count; i++) {
        printf("%s\n", list.entries[i].name);
    }
    
    db_stats_free(&list);
    return 0;
}

int cmd_stats(int argc, char **argv) {
    if (argc < 1) {
        fprintf(stderr, "Usage: spagat-librarian stats <status|tag|history> [filter]\n");
        return 1;
    }
    
    const char *type = argv[0];
    const char *filter = argc > 1 ? argv[1] : NULL;
    
    StatList list;
    bool ok = false;
    
    if (str_equals_ignore_case(type, "status")) {
        ok = db_stats_by_status(&list, filter);
    } else if (str_equals_ignore_case(type, "tag")) {
        ok = db_stats_by_tag(&list, filter);
    } else if (str_equals_ignore_case(type, "history")) {
        ok = db_stats_history(&list);
    } else {
        fprintf(stderr, "Unknown stats type: %s\n", type);
        return 1;
    }
    
    if (!ok) {
        fprintf(stderr, "Failed to load statistics\n");
        return 1;
    }
    
    int max_count = 0;
    for (int i = 0; i < list.count; i++) {
        if (list.entries[i].count > max_count) max_count = list.entries[i].count;
    }
    
    for (int i = 0; i < list.count; i++) {
        printf("%16s %4d ", list.entries[i].name, list.entries[i].count);
        print_bar(list.entries[i].count, max_count, 20);
        printf("\n");
    }
    
    db_stats_free(&list);
    return 0;
}

int cmd_filter_status(int argc, char **argv) {
    bool use_color = !env_is_set("NOCOLOR");
    
    ItemStatus filter[STATUS_COUNT];
    int filter_count = 0;
    
    for (int i = 0; i < argc && filter_count < STATUS_COUNT; i++) {
        filter[filter_count++] = status_from_string(argv[i]);
    }
    
    ItemList list;
    if (!db_items_list(&list, filter, filter_count)) {
        fprintf(stderr, "Failed to load items\n");
        return 1;
    }
    
    printf("%-4s  %-14s  %-20s  %-12s  %s\n", "id", "status", "title", "tag", "history");
    printf("%-4s  %-14s  %-20s  %-12s  %s\n", "-", "-", "-", "-", "-");
    
    for (int i = 0; i < list.count; i++) {
        Item *item = &list.items[i];
        char title_short[21];
        str_safe_copy(title_short, item->title, sizeof(title_short));
        
        if (use_color) printf("\033[33m");
        printf("%-4lld", (long long)item->id);
        if (use_color) printf("\033[0m");
        
        printf("  %-14s  %-20s  %-12s  %s\n",
               STATUS_NAMES[item->status],
               title_short,
               item->tag,
               item->history);
    }
    
    db_items_free(&list);
    return 0;
}

int cmd_export(const char *format) {
    ItemList list;
    if (!db_items_list(&list, NULL, 0)) {
        fprintf(stderr, "Failed to load items\n");
        return 1;
    }
    
    if (str_equals_ignore_case(format, "csv")) {
        printf("id,status,title,description,tag,history,created_at,updated_at\n");
        for (int i = 0; i < list.count; i++) {
            Item *item = &list.items[i];
            printf("%lld,\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",%lld,%lld\n",
                   (long long)item->id,
                   STATUS_NAMES[item->status],
                   item->title,
                   item->description,
                   item->tag,
                   item->history,
                   (long long)item->created_at,
                   (long long)item->updated_at);
        }
    } else if (str_equals_ignore_case(format, "json")) {
        printf("[\n");
        for (int i = 0; i < list.count; i++) {
            Item *item = &list.items[i];
            printf("  {\"id\": %lld, \"status\": \"%s\", \"title\": \"%s\", \"description\": \"%s\", \"tag\": \"%s\", \"history\": \"%s\"}%s\n",
                   (long long)item->id,
                   STATUS_NAMES[item->status],
                   item->title,
                   item->description,
                   item->tag,
                   item->history,
                   i < list.count - 1 ? "," : "");
        }
        printf("]\n");
    } else {
        fprintf(stderr, "Unknown format: %s (use csv or json)\n", format);
        db_items_free(&list);
        return 1;
    }
    
    db_items_free(&list);
    return 0;
}
