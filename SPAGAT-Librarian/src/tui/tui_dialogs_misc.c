#include "tui_common.h"
#include "spagat_m48.h"

int tui_edit_priority_field(int y, int x, int current_priority, int box_width) {
    int sel = current_priority;
    
    keypad(stdscr, TRUE);
    curs_set(0);
    
    int dropdown_height = PRIORITY_COUNT + 2;
    
    while (1) {
        mvhline(y, x, ' ', box_width);
        mvprintw(y, x, "[ %s ]", PRIORITY_DISPLAY[sel]);
        
        for (int i = 0; i < dropdown_height; i++) {
            mvhline(y + 1 + i, x, ' ', 20);
        }
        
        int dw = 20;
        int dh = PRIORITY_COUNT + 2;
        mvaddch(y + 1, x, ACS_ULCORNER);
        for (int i = 1; i < dw - 1; i++) mvaddch(y + 1, x + i, ACS_HLINE);
        mvaddch(y + 1, x + dw - 1, ACS_URCORNER);
        for (int i = 0; i < PRIORITY_COUNT; i++) {
            mvaddch(y + 2 + i, x, ACS_VLINE);
            if (i == sel) attron(A_REVERSE);
            mvprintw(y + 2 + i, x + 1, " %-16s ", PRIORITY_DISPLAY[i]);
            if (i == sel) attroff(A_REVERSE);
            mvaddch(y + 2 + i, x + dw - 1, ACS_VLINE);
        }
        mvaddch(y + 1 + dh - 1, x, ACS_LLCORNER);
        for (int i = 1; i < dw - 1; i++) mvaddch(y + 1 + dh - 1, x + i, ACS_HLINE);
        mvaddch(y + 1 + dh - 1, x + dw - 1, ACS_LRCORNER);
        
        refresh();
        
        int ch = getch();
        
        if (ch == '\n' || ch == '\r' || ch == KEY_ENTER || ch == 10 || ch == 13) {
            for (int i = 0; i < dropdown_height; i++) {
                mvhline(y + 1 + i, x, ' ', 21);
            }
            return sel;
        } else if (ch == 27) {
            for (int i = 0; i < dropdown_height; i++) {
                mvhline(y + 1 + i, x, ' ', 21);
            }
            return current_priority;
        } else if (ch == KEY_UP || ch == 259) {
            if (sel > 0) sel--;
        } else if (ch == KEY_DOWN || ch == 258) {
            if (sel < PRIORITY_COUNT - 1) sel++;
        } else if (ch >= '0' && ch <= '4') {
            sel = ch - '0';
        }
    }
}

void tui_dialog_add(TUIState *state) {
    timeout(-1);
    echo();
    curs_set(1);

    /* M48-KanbanCVECard — extended form. Four new fields (Branch,
     * Upstream commit, Backport commit, CVE-IDs) sit between Tag and
     * the status footer. Each field is optional; validation lands
     * inline (invalid → row stays blank, no crash). */
    int w = 72;
    int h = 22;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;

    tui_draw_box(y, x, h, w, "Add New Item");

    const int label_col = x + 2;
    const int value_col = x + 20;

    mvprintw(y + 2,  label_col, "Title:");
    mvprintw(y + 4,  label_col, "Description:");
    mvprintw(y + 6,  label_col, "Tag:");
    mvprintw(y + 8,  label_col, "Branch:");
    mvprintw(y + 10, label_col, "Upstream commit:");
    mvprintw(y + 12, label_col, "Backport commit:");
    mvprintw(y + 14, label_col, "CVE-IDs:");
    mvprintw(y + 14, value_col + 32, "(comma-separated)");
    /* M48-KanbanBranchView — in Branch view current_col is a branch
     * column index, not a status. New items in either view default to
     * the Backlog status (matching the mid-column position operators
     * expect) so the preview + persisted status stay coherent. */
    ItemStatus new_status = (state->board_mode == BOARD_MODE_BRANCH)
        ? STATUS_BACKLOG
        : (ItemStatus)state->current_col;
    mvprintw(y + 16, label_col, "Status: %s", STATUS_DISPLAY[new_status]);
    mvprintw(y + h - 3, label_col,
             "Enter=next field, fill Title to save. Commits: 40 hex or empty.");
    refresh();

    char title[SPAGAT_MAX_TITLE_LEN] = {0};
    char desc[SPAGAT_MAX_DESC_LEN] = {0};
    char tag[SPAGAT_MAX_TAG_LEN] = {0};
    char branch[SPAGAT_MAX_BRANCH_LEN] = {0};
    char upstream[SPAGAT_MAX_COMMIT_LEN] = {0};
    char backport[SPAGAT_MAX_COMMIT_LEN] = {0};
    char cve_ids[SPAGAT_MAX_CVE_LIST_LEN] = {0};

    move(y + 2, value_col);
    getnstr(title, sizeof(title) - 1);
    str_trim(title);

    if (!title[0]) {
        /* Empty title cancels — matches prior behaviour. */
        noecho();
        curs_set(0);
        timeout(100);
        state->needs_refresh = true;
        return;
    }

    move(y + 4, value_col);
    getnstr(desc, sizeof(desc) - 1);
    str_trim(desc);

    move(y + 6, value_col);
    getnstr(tag, sizeof(tag) - 1);
    str_trim(tag);

    move(y + 8, value_col);
    getnstr(branch, sizeof(branch) - 1);
    str_trim(branch);

    move(y + 10, value_col);
    getnstr(upstream, sizeof(upstream) - 1);
    str_trim(upstream);
    if (!m48_validate_commit_sha(upstream)) {
        /* Silently drop an invalid SHA — operator gets an empty field
         * on the resulting card rather than a corrupt entry. Row 14
         * shows a hint about the format. */
        upstream[0] = '\0';
    }

    move(y + 12, value_col);
    getnstr(backport, sizeof(backport) - 1);
    str_trim(backport);
    if (!m48_validate_commit_sha(backport)) {
        backport[0] = '\0';
    }

    move(y + 14, value_col);
    getnstr(cve_ids, sizeof(cve_ids) - 1);
    str_trim(cve_ids);
    /* Validate at the token level via m48_parse_cve_ids; malformed
     * tokens are dropped, valid tokens survive verbatim. */
    if (cve_ids[0]) {
        SpagatCveList parsed;
        m48_parse_cve_ids(cve_ids, &parsed);
        /* If nothing survived, clear the field so it isn't stored. */
        if (parsed.count == 0) {
            cve_ids[0] = '\0';
        }
    }

    Item newitem;
    memset(&newitem, 0, sizeof(newitem));
    newitem.status = new_status;
    newitem.priority = PRIORITY_NONE;
    newitem.project_id = state->current_project;
    /* M48-KanbanBranchView — when adding from Branch view, seed the
     * new item's git_branch with the canonical branch of the focused
     * column (unless it's the Other bucket, which represents "not one
     * of the canonical branches" and has no single key). The operator
     * can still override in the Branch: text field above. */
    if (state->board_mode == BOARD_MODE_BRANCH &&
        !branch[0] &&
        state->current_col >= 0 &&
        state->current_col < BRANCH_COL_COUNT - 1 &&
        BRANCH_COL_KEYS[state->current_col]) {
        str_safe_copy(branch, BRANCH_COL_KEYS[state->current_col],
                      sizeof(branch));
    }
    str_safe_copy(newitem.title, title, sizeof(newitem.title));
    str_safe_copy(newitem.description, desc, sizeof(newitem.description));
    str_safe_copy(newitem.tag, tag, sizeof(newitem.tag));
    str_safe_copy(newitem.git_branch, branch, sizeof(newitem.git_branch));
    str_safe_copy(newitem.upstream_commit, upstream, sizeof(newitem.upstream_commit));
    str_safe_copy(newitem.backport_commit, backport, sizeof(newitem.backport_commit));
    str_safe_copy(newitem.cve_ids, cve_ids, sizeof(newitem.cve_ids));

    int64_t id;
    if (db_item_add_full(&newitem, &id)) {
        tui_refresh_items(state);
    }

    noecho();
    curs_set(0);
    timeout(100);
    state->needs_refresh = true;
}

void tui_dialog_move(TUIState *state) {
    int selected = tui_count_selected(state);
    if (selected == 0) {
        Item *item = tui_get_current_item(state);
        if (item) item->selected = true;
        selected = 1;
    }
    
    int w = 40;
    int h = STATUS_COUNT + 4;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    char move_title[64];
    snprintf(move_title, sizeof(move_title), "Move %d item(s) to", selected);
    tui_draw_box(y, x, h, w, move_title);
    
    for (int i = 0; i < STATUS_COUNT; i++) {
        mvprintw(y + 2 + i, x + 4, "%d. %s", i + 1, STATUS_DISPLAY[i]);
    }
    
    refresh();
    timeout(-1);
    int ch = getch();
    timeout(100);
    
    if (ch >= '1' && ch <= '6') {
        ItemStatus new_status = (ItemStatus)(ch - '1');
        
        for (int i = 0; i < state->items.count; i++) {
            if (state->items.items[i].selected) {
                db_item_set_status(state->items.items[i].id, new_status);
            }
        }
        
        tui_refresh_items(state);
        tui_clear_selection(state);
    }
    
    state->needs_refresh = true;
}

void tui_dialog_delete(TUIState *state) {
    int selected = tui_count_selected(state);
    Item *current_item = tui_get_current_item(state);
    
    if (selected == 0 && current_item) {
        current_item->selected = true;
        selected = 1;
    }
    
    if (selected == 0) return;
    
    int w = 60;
    int h = 6 + selected;
    if (h > 20) h = 20;
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    
    char del_title[64];
    snprintf(del_title, sizeof(del_title), "Delete %d item(s)?", selected);
    tui_draw_box(y, x, h, w, del_title);
    
    int line = 2;
    for (int i = 0; i < state->items.count && line < h - 2; i++) {
        if (state->items.items[i].selected) {
            char title_truncated[50];
            strncpy(title_truncated, state->items.items[i].title, sizeof(title_truncated) - 1);
            title_truncated[sizeof(title_truncated) - 1] = '\0';
            mvprintw(y + line, x + 4, "- %s", title_truncated);
            line++;
        }
    }
    
    mvprintw(y + h - 2, x + 2, "Press 'y' to confirm, any other to cancel");
    
    refresh();
    timeout(-1);
    int ch = getch();
    timeout(100);
    
    if (ch == 'y' || ch == 'Y') {
        int deleted_col = state->current_col;
        int deleted_row = state->current_row;
        
        for (int i = state->items.count - 1; i >= 0; i--) {
            if (state->items.items[i].selected) {
                db_item_delete(state->items.items[i].id);
            }
        }
        tui_refresh_items(state);
        
        int new_count = state->item_counts[deleted_col];
        if (new_count == 0) {
            state->current_row = 0;
        } else if (deleted_row >= new_count) {
            state->current_row = new_count - 1;
        } else if (deleted_row > 0) {
            state->current_row = deleted_row - 1;
        }
        
        if (state->scroll_offset[deleted_col] > 0 && 
            state->scroll_offset[deleted_col] >= new_count) {
            state->scroll_offset[deleted_col] = new_count > 0 ? new_count - 1 : 0;
        }
    }
    
    tui_clear_selection(state);
    state->needs_refresh = true;
}

void tui_dialog_search(TUIState *state) {
    timeout(-1);
    echo();
    curs_set(1);
    
    int w = 50;
    int h = 3;
    int x = (state->term_width - w) / 2;
    int y = state->term_height / 2 - 1;
    
    tui_draw_box(y, x, h, w, "Search");
    mvprintw(y + 1, x + 2, "> ");
    refresh();
    
    char query[128] = {0};
    move(y + 1, x + 4);
    getnstr(query, sizeof(query) - 1);
    str_trim(query);
    
    noecho();
    curs_set(0);
    timeout(100);
    
    if (query[0]) {
        for (int i = 0; i < state->items.count; i++) {
            Item *item = &state->items.items[i];
            if (strstr(item->title, query) || strstr(item->description, query) || strstr(item->tag, query)) {
                /* M48-KanbanBranchView — jump to the column that
                 * contains this item in the CURRENT board mode.
                 * Status view: the column IS the status. Branch view:
                 * the column is derived from git_branch (Other bucket
                 * catches empty / unrecognised branches). Row counting
                 * uses the same filter so the highlight lands on the
                 * matched card in either view. */
                int target_col;
                if (state->board_mode == BOARD_MODE_BRANCH) {
                    target_col = branch_column_for(item->git_branch);
                } else {
                    target_col = (int)item->status;
                }
                state->current_col = target_col;

                int row = 0;
                for (int j = 0; j < i; j++) {
                    Item *prior = &state->items.items[j];
                    int prior_col;
                    if (state->board_mode == BOARD_MODE_BRANCH) {
                        prior_col = branch_column_for(prior->git_branch);
                    } else {
                        prior_col = (int)prior->status;
                    }
                    if (prior_col == target_col) row++;
                }
                state->current_row = row;
                state->scroll_offset[state->current_col] = 0;
                break;
            }
        }
    }
    
    state->needs_refresh = true;
}
