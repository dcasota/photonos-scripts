#include "tui_common.h"

void tui_dialog_edit(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;
    
    Item edit_item;
    if (!db_item_get(item->id, &edit_item)) return;
    
    timeout(-1);
    keypad(stdscr, TRUE);
    curs_set(0);
    
    int w = 75;
    int h = 32;
    int bx = (state->term_width - w) / 2;
    int by = (state->term_height - h) / 2;
    if (by < 0) by = 0;
    if (bx < 0) bx = 0;
    
    char title[SPAGAT_MAX_TITLE_LEN];
    char desc[SPAGAT_MAX_DESC_LEN];
    char tag[SPAGAT_MAX_TAG_LEN];
    char git_branch[SPAGAT_MAX_BRANCH_LEN];
    char due_str[32] = {0};
    int new_status = edit_item.status;
    int new_priority = edit_item.priority;
    int64_t new_parent_id = edit_item.parent_id;
    time_t new_due_date = edit_item.due_date;
    
    str_safe_copy(title, edit_item.title, sizeof(title));
    str_safe_copy(desc, edit_item.description, sizeof(desc));
    str_safe_copy(tag, edit_item.tag, sizeof(tag));
    str_safe_copy(git_branch, edit_item.git_branch, sizeof(git_branch));
    
    if (edit_item.due_date > 0) {
        struct tm *tm = localtime(&edit_item.due_date);
        snprintf(due_str, sizeof(due_str), "%04d-%02d-%02d", 
                 tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
    }
    
    int current_field = 0;
    const int NUM_FIELDS = 9;
    
    while (1) {
        char box_title[64];
        snprintf(box_title, sizeof(box_title),
                 "Edit Item #%lld", (long long)edit_item.id);
        tui_draw_box(by, bx, h, w, box_title);
        
        int row = 2;
        const int label_col = bx + 2;
        const int value_col = bx + 18;
        const int field_width = w - 20;
        
        mvprintw(by + row, label_col, "%s Title:", current_field == 0 ? ">" : " ");
        mvprintw(by + row, value_col, "%.50s", title);
        if (current_field == 0) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Description:", current_field == 1 ? ">" : " ");
        mvprintw(by + row, value_col, "%.50s", desc);
        if (current_field == 1) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Tag:", current_field == 2 ? ">" : " ");
        mvprintw(by + row, value_col, "%.30s", tag);
        if (current_field == 2) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Status:", current_field == 3 ? ">" : " ");
        mvprintw(by + row, value_col, "[ %s ]", STATUS_DISPLAY[new_status]);
        if (current_field == 3) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Priority:", current_field == 4 ? ">" : " ");
        mvprintw(by + row, value_col, "[ %s ]", PRIORITY_DISPLAY[new_priority]);
        if (current_field == 4) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Due Date:", current_field == 5 ? ">" : " ");
        if (due_str[0]) {
            mvprintw(by + row, value_col, "%s", due_str);
        } else {
            mvprintw(by + row, value_col, "(none)");
        }
        if (current_field == 5) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Parent ID:", current_field == 6 ? ">" : " ");
        if (new_parent_id > 0) {
            mvprintw(by + row, value_col, "%lld", (long long)new_parent_id);
        } else {
            mvprintw(by + row, value_col, "(none - top level)");
        }
        if (current_field == 6) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Git Branch:", current_field == 7 ? ">" : " ");
        if (git_branch[0]) {
            mvprintw(by + row, value_col, "%.40s", git_branch);
        } else {
            mvprintw(by + row, value_col, "(none)");
        }
        if (current_field == 7) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        mvprintw(by + row, label_col, "%s Project:", current_field == 8 ? ">" : " ");
        if (edit_item.project_id > 0) {
            Project proj;
            if (db_project_get(edit_item.project_id, &proj)) {
                mvprintw(by + row, value_col, "%s", proj.name);
            } else {
                mvprintw(by + row, value_col, "(ID: %lld)", (long long)edit_item.project_id);
            }
        } else {
            mvprintw(by + row, value_col, "(default)");
        }
        if (current_field == 8) mvchgat(by + row, value_col, field_width, A_UNDERLINE, 0, NULL);
        row += 2;
        
        /* Separator using ACS tee + hline */
        mvaddch(by + row, bx, ACS_LTEE);
        for (int i = 1; i < w - 1; i++) mvaddch(by + row, bx + i, ACS_HLINE);
        mvaddch(by + row, bx + w - 1, ACS_RTEE);
        row++;
        
        attron(A_DIM);
        mvprintw(by + row, label_col, "Time Spent:");
        time_t total_time = db_time_get_total(edit_item.id);
        int hours = total_time / 3600;
        int minutes = (total_time % 3600) / 60;
        mvprintw(by + row, value_col, "%dh %dm", hours, minutes);
        row++;
        
        mvprintw(by + row, label_col, "Dependencies:");
        DependencyList blockers, blocking;
        if (db_dependencies_get(edit_item.id, &blockers, &blocking)) {
            if (blockers.count > 0) {
                mvprintw(by + row, value_col, "Blocked by: ");
                int px = value_col + 12;
                for (int i = 0; i < blockers.count && i < 5; i++) {
                    mvprintw(by + row, px, "#%lld ", (long long)blockers.deps[i].to_id);
                    px += 6;
                }
            } else {
                mvprintw(by + row, value_col, "(none)");
            }
            row++;
            if (blocking.count > 0) {
                mvprintw(by + row, label_col, "Blocking:");
                int px = value_col;
                for (int i = 0; i < blocking.count && i < 5; i++) {
                    mvprintw(by + row, px, "#%lld ", (long long)blocking.deps[i].from_id);
                    px += 6;
                }
            }
            db_dependencies_free(&blockers);
            db_dependencies_free(&blocking);
        } else {
            mvprintw(by + row, value_col, "(none)");
        }
        row++;
        
        char history_str[256];
        tui_format_history(edit_item.history, history_str, sizeof(history_str));
        mvprintw(by + row, label_col, "History:");
        mvprintw(by + row, value_col, "%.50s", history_str[0] ? history_str : "(none)");
        attroff(A_DIM);
        row += 2;
        
        /* Footer separator using ACS tee + hline */
        mvaddch(by + h - 3, bx, ACS_LTEE);
        for (int i = 1; i < w - 1; i++) mvaddch(by + h - 3, bx + i, ACS_HLINE);
        mvaddch(by + h - 3, bx + w - 1, ACS_RTEE);

        attron(A_BOLD);
        mvprintw(by + h - 2, bx + 2, "Up/Down=navigate  Enter=edit  S=save  Esc=cancel");
        attroff(A_BOLD);
        
        refresh();
        
        int ch = getch();
        
        if (ch == 27) {
            break;
        } else if (ch == KEY_UP || ch == 259) {
            current_field = (current_field - 1 + NUM_FIELDS) % NUM_FIELDS;
        } else if (ch == KEY_DOWN || ch == 258 || ch == '\t') {
            current_field = (current_field + 1) % NUM_FIELDS;
        } else if (ch == '\n' || ch == '\r' || ch == KEY_ENTER || ch == 10 || ch == 13) {
            mvhline(by + h - 1, bx + 2, ' ', w - 4);
            
            if (current_field == 0) {
                mvprintw(by + h - 1, bx + 2, "Editing title. Enter=done");
                refresh();
                tui_edit_text_field(by + 3, value_col, field_width, title, sizeof(title));
                curs_set(0);
                keypad(stdscr, TRUE);
            } else if (current_field == 1) {
                mvprintw(by + h - 1, bx + 2, "Editing description. Enter=done");
                refresh();
                tui_edit_text_field(by + 5, value_col, field_width, desc, sizeof(desc));
                curs_set(0);
                keypad(stdscr, TRUE);
            } else if (current_field == 2) {
                mvprintw(by + h - 1, bx + 2, "Editing tag. Enter=done");
                refresh();
                tui_edit_text_field(by + 7, value_col, field_width, tag, sizeof(tag));
                curs_set(0);
                keypad(stdscr, TRUE);
            } else if (current_field == 3) {
                mvprintw(by + h - 1, bx + 2, "Up/Down=change, Enter=done");
                refresh();
                new_status = tui_edit_status_field(by + 9, value_col, new_status, field_width);
                keypad(stdscr, TRUE);
            } else if (current_field == 4) {
                mvprintw(by + h - 1, bx + 2, "Up/Down=change, Enter=done");
                refresh();
                new_priority = tui_edit_priority_field(by + 11, value_col, new_priority, field_width);
                keypad(stdscr, TRUE);
            } else if (current_field == 5) {
                mvprintw(by + h - 1, bx + 2, "Format: YYYY-MM-DD, 'today', 'tomorrow', '+N' (days), empty=clear");
                refresh();
                char input[32] = {0};
                str_safe_copy(input, due_str, sizeof(input));
                tui_edit_text_field(by + 13, value_col, 12, input, sizeof(input));
                str_trim(input);
                
                if (input[0] == '\0') {
                    new_due_date = 0;
                    due_str[0] = '\0';
                } else if (str_equals_ignore_case(input, "today")) {
                    time_t now = time(NULL);
                    struct tm *tm = localtime(&now);
                    tm->tm_hour = 23; tm->tm_min = 59; tm->tm_sec = 59;
                    new_due_date = mktime(tm);
                    snprintf(due_str, sizeof(due_str), "%04d-%02d-%02d",
                             tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
                } else if (str_equals_ignore_case(input, "tomorrow")) {
                    new_due_date = time(NULL) + 86400;
                    struct tm *tm = localtime(&new_due_date);
                    snprintf(due_str, sizeof(due_str), "%04d-%02d-%02d",
                             tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
                } else if (input[0] == '+') {
                    int days = atoi(input + 1);
                    new_due_date = time(NULL) + days * 86400;
                    struct tm *tm = localtime(&new_due_date);
                    snprintf(due_str, sizeof(due_str), "%04d-%02d-%02d",
                             tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday);
                } else {
                    struct tm tm = {0};
                    if (sscanf(input, "%d-%d-%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday) == 3) {
                        tm.tm_year -= 1900;
                        tm.tm_mon -= 1;
                        tm.tm_hour = 23; tm.tm_min = 59; tm.tm_sec = 59;
                        new_due_date = mktime(&tm);
                        str_safe_copy(due_str, input, sizeof(due_str));
                    }
                }
                curs_set(0);
                keypad(stdscr, TRUE);
            } else if (current_field == 6) {
                mvprintw(by + h - 1, bx + 2, "Enter parent item ID (0=none)");
                refresh();
                char input[24] = {0};
                if (new_parent_id > 0) {
                    snprintf(input, sizeof(input), "%lld", (long long)new_parent_id);
                }
                tui_edit_text_field(by + 15, value_col, 20, input, sizeof(input));
                str_trim(input);
                new_parent_id = input[0] ? atoll(input) : 0;
                if (new_parent_id == edit_item.id) new_parent_id = 0;
                curs_set(0);
                keypad(stdscr, TRUE);
            } else if (current_field == 7) {
                mvprintw(by + h - 1, bx + 2, "Editing git branch. Enter=done");
                refresh();
                tui_edit_text_field(by + 17, value_col, field_width, git_branch, sizeof(git_branch));
                curs_set(0);
                keypad(stdscr, TRUE);
            } else if (current_field == 8) {
                mvprintw(by + h - 1, bx + 2, "Project selection (read-only, use 'P' key on board)");
                refresh();
                timeout(1500);
                getch();
                timeout(-1);
            }
        } else if (ch == 's' || ch == 'S') {
            goto save_and_exit;
        }
    }
    
    curs_set(0);
    timeout(100);
    state->needs_refresh = true;
    return;

save_and_exit:
    str_trim(title);
    str_trim(desc);
    str_trim(tag);
    str_trim(git_branch);
    
    if (!title[0]) {
        curs_set(0);
        timeout(100);
        state->needs_refresh = true;
        return;
    }
    
    bool changed = false;
    if (strcmp(title, edit_item.title) != 0) {
        str_safe_copy(edit_item.title, title, sizeof(edit_item.title));
        changed = true;
    }
    if (strcmp(desc, edit_item.description) != 0) {
        str_safe_copy(edit_item.description, desc, sizeof(edit_item.description));
        changed = true;
    }
    if (strcmp(tag, edit_item.tag) != 0) {
        str_safe_copy(edit_item.tag, tag, sizeof(edit_item.tag));
        changed = true;
    }
    if (strcmp(git_branch, edit_item.git_branch) != 0) {
        str_safe_copy(edit_item.git_branch, git_branch, sizeof(edit_item.git_branch));
        changed = true;
    }
    if (new_status != (int)edit_item.status) {
        size_t hlen = strlen(edit_item.history);
        if (hlen < sizeof(edit_item.history) - 1) {
            edit_item.history[hlen] = STATUS_ABBREV[new_status];
            edit_item.history[hlen + 1] = '\0';
        }
        edit_item.status = (ItemStatus)new_status;
        changed = true;
    }
    if (new_priority != (int)edit_item.priority) {
        edit_item.priority = (ItemPriority)new_priority;
        changed = true;
    }
    if (new_due_date != edit_item.due_date) {
        edit_item.due_date = new_due_date;
        changed = true;
    }
    if (new_parent_id != edit_item.parent_id) {
        edit_item.parent_id = new_parent_id;
        changed = true;
    }
    
    if (changed) {
        db_item_update(&edit_item);
    }
    
    tui_refresh_items(state);
    curs_set(0);
    timeout(100);
    state->needs_refresh = true;
}
