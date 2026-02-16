#include "tui_common.h"

Item *tui_get_current_item(TUIState *state) {
    int target_row = state->current_row + state->scroll_offset[state->current_col];
    int row = 0;
    for (int i = 0; i < state->items.count; i++) {
        Item *item = &state->items.items[i];
        if ((int)item->status != state->current_col) continue;
        
        if (row == target_row) {
            return item;
        }
        row++;
    }
    return NULL;
}

void tui_move_cursor_left(TUIState *state) {
    if (state->current_col > 0) {
        state->current_col--;
        state->current_row = 0;
        state->scroll_offset[state->current_col] = 0;
        state->needs_refresh = true;
    }
}

void tui_move_cursor_right(TUIState *state) {
    if (state->current_col < STATUS_COUNT - 1) {
        state->current_col++;
        state->current_row = 0;
        state->scroll_offset[state->current_col] = 0;
        state->needs_refresh = true;
    }
}

void tui_move_cursor_up(TUIState *state) {
    if (state->current_row > 0) {
        state->current_row--;
        state->needs_refresh = true;
    } else if (state->scroll_offset[state->current_col] > 0) {
        state->scroll_offset[state->current_col]--;
        state->needs_refresh = true;
    }
}

void tui_move_cursor_down(TUIState *state) {
    int max_row = state->item_counts[state->current_col] - 1;
    int visible_rows = state->term_height - 6;
    int current_abs = state->current_row + state->scroll_offset[state->current_col];
    
    if (current_abs < max_row) {
        if (state->current_row < visible_rows - 1) {
            state->current_row++;
        } else {
            state->scroll_offset[state->current_col]++;
        }
        state->needs_refresh = true;
    }
}

void tui_toggle_select(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (item) {
        item->selected = !item->selected;
        state->needs_refresh = true;
    }
}

void tui_select_all_in_column(TUIState *state) {
    for (int i = 0; i < state->items.count; i++) {
        if ((int)state->items.items[i].status == state->current_col) {
            state->items.items[i].selected = true;
        }
    }
    state->needs_refresh = true;
}

void tui_clear_selection(TUIState *state) {
    for (int i = 0; i < state->items.count; i++) {
        state->items.items[i].selected = false;
    }
    state->needs_refresh = true;
}

int tui_count_selected(TUIState *state) {
    int count = 0;
    for (int i = 0; i < state->items.count; i++) {
        if (state->items.items[i].selected) count++;
    }
    return count;
}

bool tui_edit_text_field(int y, int x, int max_width, char *buf, int buf_size) {
    int len = strlen(buf);
    int pos = len;
    
    keypad(stdscr, TRUE);
    curs_set(1);
    
    while (1) {
        move(y, x);
        for (int i = 0; i < max_width; i++) addch(' ');
        mvprintw(y, x, "%.*s", max_width - 1, buf);
        move(y, x + (pos < max_width - 1 ? pos : max_width - 1));
        refresh();
        
        int ch = getch();
        
        if (ch == '\n' || ch == '\r' || ch == KEY_ENTER || ch == 27 || ch == 10 || ch == 13) {
            return true;
        } else if (ch == KEY_BACKSPACE || ch == 127 || ch == 8) {
            if (pos > 0) {
                memmove(&buf[pos - 1], &buf[pos], len - pos + 1);
                pos--;
                len--;
            }
        } else if (ch == KEY_DC) {
            if (pos < len) {
                memmove(&buf[pos], &buf[pos + 1], len - pos);
                len--;
            }
        } else if (ch == KEY_LEFT || ch == 260) {
            if (pos > 0) pos--;
        } else if (ch == KEY_RIGHT || ch == 261) {
            if (pos < len) pos++;
        } else if (ch == KEY_HOME) {
            pos = 0;
        } else if (ch == KEY_END) {
            pos = len;
        } else if (ch >= 32 && ch < 127 && len < buf_size - 1) {
            memmove(&buf[pos + 1], &buf[pos], len - pos + 1);
            buf[pos] = ch;
            pos++;
            len++;
        }
    }
}

int tui_edit_status_field(int y, int x, int current_status, int box_width) {
    int sel = current_status;
    
    keypad(stdscr, TRUE);
    curs_set(0);
    
    int dropdown_height = STATUS_COUNT + 2;
    
    while (1) {
        mvhline(y, x, ' ', box_width);
        mvprintw(y, x, "[ %s ]", STATUS_DISPLAY[sel]);
        
        for (int i = 0; i < dropdown_height; i++) {
            mvhline(y + 1 + i, x, ' ', 25);
        }
        
        int dw = 25;
        mvaddch(y + 1, x, ACS_ULCORNER);
        for (int i = 1; i < dw - 1; i++) mvaddch(y + 1, x + i, ACS_HLINE);
        mvaddch(y + 1, x + dw - 1, ACS_URCORNER);
        for (int i = 0; i < STATUS_COUNT; i++) {
            mvaddch(y + 2 + i, x, ACS_VLINE);
            if (i == sel) {
                attron(A_REVERSE);
            }
            mvprintw(y + 2 + i, x + 1, " %-21s ", STATUS_DISPLAY[i]);
            if (i == sel) {
                attroff(A_REVERSE);
            }
            mvaddch(y + 2 + i, x + dw - 1, ACS_VLINE);
        }
        mvaddch(y + 2 + STATUS_COUNT, x, ACS_LLCORNER);
        for (int i = 1; i < dw - 1; i++) mvaddch(y + 2 + STATUS_COUNT, x + i, ACS_HLINE);
        mvaddch(y + 2 + STATUS_COUNT, x + dw - 1, ACS_LRCORNER);
        
        refresh();
        
        int ch = getch();
        
        if (ch == '\n' || ch == '\r' || ch == KEY_ENTER || ch == 10 || ch == 13) {
            for (int i = 0; i < dropdown_height; i++) {
                mvhline(y + 1 + i, x, ' ', 26);
            }
            return sel;
        } else if (ch == 27) {
            for (int i = 0; i < dropdown_height; i++) {
                mvhline(y + 1 + i, x, ' ', 26);
            }
            return current_status;
        } else if (ch == KEY_UP || ch == 259) {
            if (sel > 0) sel--;
        } else if (ch == KEY_DOWN || ch == 258) {
            if (sel < STATUS_COUNT - 1) sel++;
        } else if (ch >= '1' && ch <= '6') {
            sel = ch - '1';
        }
    }
}

void tui_format_history(const char *history, char *out, int out_size) {
    out[0] = '\0';
    int pos = 0;
    
    for (int i = 0; history[i] && pos < out_size - 30; i++) {
        int status_idx = -1;
        switch (history[i]) {
            case 'C': status_idx = STATUS_CLARIFICATION; break;
            case 'W': status_idx = STATUS_WONTFIX; break;
            case 'B': status_idx = STATUS_BACKLOG; break;
            case 'P': status_idx = STATUS_PROGRESS; break;
            case 'V': status_idx = STATUS_REVIEW; break;
            case 'R': status_idx = STATUS_READY; break;
            default: continue;
        }
        if (status_idx < 0) continue;
        if (pos > 0) {
            pos += snprintf(out + pos, out_size - pos, " -> ");
        }
        pos += snprintf(out + pos, out_size - pos, "%s", STATUS_DISPLAY[status_idx]);
    }
}

void tui_handle_input(TUIState *state) {
    int ch = getch();
    
    if (ch == ERR) return;
    
    switch (ch) {
        case 'q':
        case 'Q':
            state->running = false;
            break;
            
        case 'h':
        case KEY_LEFT:
            tui_move_cursor_left(state);
            break;
            
        case 'l':
        case KEY_RIGHT:
            tui_move_cursor_right(state);
            break;
            
        case 'k':
        case KEY_UP:
            tui_move_cursor_up(state);
            break;
            
        case 'j':
        case KEY_DOWN:
            tui_move_cursor_down(state);
            break;
            
        case '1': case '2': case '3': case '4': case '5': case '6':
            state->current_col = ch - '1';
            state->current_row = 0;
            state->needs_refresh = true;
            break;
            
        case ' ':
            tui_toggle_select(state);
            tui_move_cursor_down(state);
            break;
            
        case 'a':
        case 'A':
            tui_dialog_add(state);
            break;
            
        case 'm':
        case 'M':
            tui_dialog_move(state);
            break;
            
        case KEY_ENTER:
        case '\n':
        case '\r':
        case 'e':
        case 'E':
            tui_dialog_edit(state);
            break;
            
        case 'd':
        case 'D':
        case KEY_DC:
            tui_dialog_delete(state);
            break;
            
        case '/':
            tui_dialog_search(state);
            break;
            
        case '?':
            tui_draw_help(state);
            break;
            
        case 'r':
        case 'R':
            tui_refresh_items(state);
            break;
            
        case '*':
            tui_select_all_in_column(state);
            break;
            
        case 27:
            tui_clear_selection(state);
            break;
            
        case KEY_RESIZE:
            getmaxyx(stdscr, state->term_height, state->term_width);
            state->col_width = state->term_width / STATUS_COUNT;
            if (state->col_width < 12) state->col_width = 12;
            state->needs_refresh = true;
            break;
            
        case 'p':
            tui_dialog_set_priority(state);
            break;
            
        case 'u':
            tui_dialog_set_due_date(state);
            break;
            
        case 'P':
            tui_dialog_select_project(state);
            break;
            
        case 't':
            tui_dialog_time_tracking(state);
            break;
            
        case 'T':
            tui_dialog_select_template(state);
            break;
            
        case 'b':
            tui_dialog_git_branch(state);
            break;
            
        case 'x':
            tui_dialog_add_dependency(state);
            break;
            
        case 's':
            tui_dialog_set_parent(state);
            break;
            
        case 'S':
            tui_toggle_swimlane_mode(state);
            break;
    }
}
