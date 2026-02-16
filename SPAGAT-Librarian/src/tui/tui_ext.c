#include "tui_common.h"
#include <time.h>

void tui_draw_priority_indicator(int y, int x, ItemPriority priority) {
    if (priority == PRIORITY_NONE) return;
    
    char indicator = ' ';
    int color = 0;
    
    switch (priority) {
        case PRIORITY_CRITICAL: indicator = '!'; color = COLOR_PAIR(COLOR_STATUS_1); break;
        case PRIORITY_HIGH:     indicator = '^'; color = COLOR_PAIR(COLOR_STATUS_1); break;
        case PRIORITY_MEDIUM:   indicator = '-'; color = COLOR_PAIR(COLOR_STATUS_2); break;
        case PRIORITY_LOW:      indicator = 'v'; color = COLOR_PAIR(COLOR_STATUS_3); break;
        default: break;
    }
    
    if (color) attron(color);
    mvaddch(y, x, indicator);
    if (color) attroff(color);
}

void tui_draw_due_indicator(int y, int x, time_t due_date) {
    if (due_date == 0) return;
    
    time_t now = time(NULL);
    int days = (due_date - now) / 86400;
    
    int color = 0;
    char indicator = ' ';
    
    if (days < 0) {
        indicator = '!';
        color = COLOR_PAIR(COLOR_STATUS_1) | A_BOLD;
    } else if (days == 0) {
        indicator = 'T';
        color = COLOR_PAIR(COLOR_STATUS_1);
    } else if (days <= 3) {
        indicator = '3';
        color = COLOR_PAIR(COLOR_STATUS_2);
    } else if (days <= 7) {
        indicator = 'W';
        color = COLOR_PAIR(COLOR_STATUS_3);
    }
    
    if (indicator != ' ') {
        if (color) attron(color);
        mvaddch(y, x, indicator);
        if (color) attroff(color);
    }
}

void tui_dialog_set_priority(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    int w = 35;
    int h = PRIORITY_COUNT + 4;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Set Priority for #%lld", (long long)item->id);
    
    for (int i = 0; i < PRIORITY_COUNT; i++) {
        mvprintw(y + 3 + i, x + 4, "%d. %s", i, PRIORITY_DISPLAY[i]);
    }
    
    refresh();
    timeout(-1);
    int ch = getch();
    timeout(100);
    
    if (ch >= '0' && ch <= '4') {
        Item edit_item;
        if (db_item_get(item->id, &edit_item)) {
            edit_item.priority = (ItemPriority)(ch - '0');
            db_item_update(&edit_item);
            tui_refresh_items(state);
        }
    }
    
    state->needs_refresh = true;
}

void tui_dialog_set_due_date(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    timeout(-1);
    echo();
    curs_set(1);
    
    int w = 50;
    int h = 8;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Set Due Date for #%lld", (long long)item->id);
    mvprintw(y + 3, x + 2, "Date (YYYY-MM-DD): ");
    mvprintw(y + 5, x + 2, "Leave empty to clear, 'today', 'tomorrow', '+N'");
    refresh();
    
    char date_str[32] = {0};
    move(y + 3, x + 21);
    getnstr(date_str, sizeof(date_str) - 1);
    str_trim(date_str);
    
    noecho();
    curs_set(0);
    timeout(100);
    
    Item edit_item;
    if (!db_item_get(item->id, &edit_item)) {
        state->needs_refresh = true;
        return;
    }
    
    if (date_str[0] == '\0') {
        edit_item.due_date = 0;
    } else if (str_equals_ignore_case(date_str, "today")) {
        time_t now = time(NULL);
        struct tm *tm = localtime(&now);
        tm->tm_hour = 23;
        tm->tm_min = 59;
        tm->tm_sec = 59;
        edit_item.due_date = mktime(tm);
    } else if (str_equals_ignore_case(date_str, "tomorrow")) {
        edit_item.due_date = time(NULL) + 86400;
    } else if (date_str[0] == '+') {
        int days = atoi(date_str + 1);
        edit_item.due_date = time(NULL) + days * 86400;
    } else {
        struct tm tm = {0};
        if (sscanf(date_str, "%d-%d-%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday) == 3) {
            tm.tm_year -= 1900;
            tm.tm_mon -= 1;
            tm.tm_hour = 23;
            tm.tm_min = 59;
            tm.tm_sec = 59;
            edit_item.due_date = mktime(&tm);
        }
    }
    
    db_item_update(&edit_item);
    tui_refresh_items(state);
    state->needs_refresh = true;
}

void tui_dialog_set_parent(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    timeout(-1);
    echo();
    curs_set(1);
    
    int w = 45;
    int h = 6;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Set Parent for #%lld", (long long)item->id);
    mvprintw(y + 3, x + 2, "Parent ID (0 = none): ");
    refresh();
    
    char id_str[16] = {0};
    move(y + 3, x + 24);
    getnstr(id_str, sizeof(id_str) - 1);
    str_trim(id_str);
    
    noecho();
    curs_set(0);
    timeout(100);
    
    if (id_str[0]) {
        int64_t parent_id = atoll(id_str);
        
        if (parent_id == item->id) {
            state->needs_refresh = true;
            return;
        }
        
        Item edit_item;
        if (db_item_get(item->id, &edit_item)) {
            edit_item.parent_id = parent_id;
            db_item_update(&edit_item);
            tui_refresh_items(state);
        }
    }
    
    state->needs_refresh = true;
}

void tui_dialog_add_dependency(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    timeout(-1);
    echo();
    curs_set(1);
    
    int w = 50;
    int h = 6;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Add Dependency for #%lld", (long long)item->id);
    mvprintw(y + 3, x + 2, "Depends on ID: ");
    refresh();
    
    char id_str[16] = {0};
    move(y + 3, x + 17);
    getnstr(id_str, sizeof(id_str) - 1);
    str_trim(id_str);
    
    noecho();
    curs_set(0);
    timeout(100);
    
    if (id_str[0]) {
        int64_t to_id = atoll(id_str);
        if (to_id != item->id) {
            db_dependency_add(item->id, to_id);
        }
    }
    
    state->needs_refresh = true;
}

void tui_dialog_git_branch(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    timeout(-1);
    echo();
    curs_set(1);
    
    int w = 55;
    int h = 6;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Git Branch for #%lld", (long long)item->id);
    mvprintw(y + 3, x + 2, "Branch: ");
    
    Item edit_item;
    if (db_item_get(item->id, &edit_item)) {
        mvprintw(y + 3, x + 10, "%s", edit_item.git_branch);
    }
    refresh();
    
    char branch[SPAGAT_MAX_BRANCH_LEN] = {0};
    move(y + 3, x + 10);
    getnstr(branch, sizeof(branch) - 1);
    str_trim(branch);
    
    noecho();
    curs_set(0);
    timeout(100);
    
    if (db_item_get(item->id, &edit_item)) {
        str_safe_copy(edit_item.git_branch, branch, sizeof(edit_item.git_branch));
        db_item_update(&edit_item);
    }
    
    state->needs_refresh = true;
}

void tui_dialog_time_tracking(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    int w = 45;
    int h = 8;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    time_t total = db_time_get_total(item->id);
    int hours = total / 3600;
    int minutes = (total % 3600) / 60;
    
    mvprintw(y + 1, x + 2, "Time Tracking for #%lld", (long long)item->id);
    mvprintw(y + 3, x + 2, "Total time: %dh %dm", hours, minutes);
    mvprintw(y + 5, x + 2, "1=Start  2=Stop  Any=Cancel");
    
    refresh();
    timeout(-1);
    int ch = getch();
    timeout(100);
    
    if (ch == '1') {
        db_time_start(item->id);
    } else if (ch == '2') {
        db_time_stop(item->id);
    }
    
    state->needs_refresh = true;
}

void tui_toggle_swimlane_mode(TUIState *state) {
    state->swimlane_mode = !state->swimlane_mode;
    state->needs_refresh = true;
}

void tui_dialog_select_project(TUIState *state) {
    ProjectList list;
    if (!db_projects_list(&list)) return;
    
    int w = 50;
    int h = list.count + 4;
    if (h > 20) h = 20;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Select Project");
    
    int display_count = (list.count < h - 3) ? list.count : h - 3;
    for (int i = 0; i < display_count; i++) {
        bool is_current = (list.projects[i].id == state->current_project);
        if (is_current) attron(A_REVERSE);
        mvprintw(y + 3 + i, x + 4, "%d. %s", i, list.projects[i].name);
        if (is_current) attroff(A_REVERSE);
    }
    
    refresh();
    timeout(-1);
    int ch = getch();
    timeout(100);
    
    if (ch >= '0' && ch <= '9') {
        int idx = ch - '0';
        if (idx < list.count) {
            state->current_project = list.projects[idx].id;
            tui_refresh_items(state);
        }
    }
    
    db_projects_free(&list);
    state->needs_refresh = true;
}

void tui_dialog_select_template(TUIState *state) {
    TemplateList list;
    if (!db_templates_list(&list)) return;
    
    if (list.count == 0) {
        db_templates_free(&list);
        return;
    }
    
    int w = 50;
    int h = list.count + 4;
    if (h > 20) h = 20;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    for (int i = 0; i < h; i++) {
        mvhline(y + i, x, ' ', w);
    }
    
    mvprintw(y + 1, x + 2, "Create from Template");
    
    int display_count = (list.count < h - 3) ? list.count : h - 3;
    for (int i = 0; i < display_count; i++) {
        mvprintw(y + 3 + i, x + 4, "%d. %s", i, list.templates[i].name);
    }
    
    refresh();
    timeout(-1);
    int ch = getch();
    timeout(100);
    
    if (ch >= '0' && ch <= '9') {
        int idx = ch - '0';
        if (idx < list.count) {
            int64_t id;
            if (db_item_from_template(list.templates[idx].name, &id)) {
                tui_refresh_items(state);
            }
        }
    }
    
    db_templates_free(&list);
    state->needs_refresh = true;
}
