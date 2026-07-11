#include "tui_common.h"
#include "spagat_m48.h"

/* M48-KanbanBranchView — item→column filter mirrors the one in
 * tui_board.c::item_belongs_in_column so the input dispatcher and
 * the renderer agree on what "current column" means under both
 * board modes. */
static bool input_item_belongs_in_column(const TUIState *state,
                                         const Item *item, int col) {
    if (state->board_mode == BOARD_MODE_BRANCH) {
        return branch_column_for(item->git_branch) == col;
    }
    return (int)item->status == col;
}

/* M48-KanbanCVECard — compute how many cards fit above the fold when
 * cards can render as either 1 or 2 lines. Walks the items list from
 * the given scroll offset until the summed rows_used exceeds
 * content_h. Returns the count of card slots that fit; the caller
 * uses it to cap `current_row` so the cursor never lands off-screen.
 *
 * M48-KanbanBranchView: filter is now board_mode-aware so branch view
 * scroll bounds are computed against branch-column membership, not
 * status. */
static int m48_visible_card_count(const TUIState *state, int col,
                                  int scroll, int content_h) {
    int skipped = 0;
    int y_used = 0;
    int visible = 0;
    for (int i = 0; i < state->items.count; i++) {
        const Item *item = &state->items.items[i];
        if (!input_item_belongs_in_column(state, item, col)) continue;
        if (skipped < scroll) { skipped++; continue; }
        int rows_used = m48_should_render_two_lines(item) ? 2 : 1;
        if (y_used + rows_used > content_h) break;
        y_used += rows_used;
        visible++;
    }
    if (visible < 1) visible = 1;  /* Always leave room for the cursor. */
    return visible;
}

Item *tui_get_current_item(TUIState *state) {
    int target_row = state->current_row + state->scroll_offset[state->current_col];
    int row = 0;
    for (int i = 0; i < state->items.count; i++) {
        Item *item = &state->items.items[i];
        if (!input_item_belongs_in_column(state, item, state->current_col)) {
            continue;
        }

        if (row == target_row) {
            return item;
        }
        row++;
    }
    return NULL;
}

/* Current mode's active column count — status view uses 6 status
 * columns; branch view uses the 5 canonical + Other = 6 columns. */
static int current_board_col_count(const TUIState *state) {
    return board_col_count(state->board_mode);
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
    if (state->current_col < current_board_col_count(state) - 1) {
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
    /* M48-KanbanCVECard: content_h is the interior of the column
     * box (box_h - 2), and box_h = term_height - 3. So content_h =
     * term_height - 5. We ask m48_visible_card_count() how many
     * cards actually fit under that budget at the current scroll. */
    int content_h = state->term_height - 5;
    if (content_h < 1) content_h = 1;
    int scroll = state->scroll_offset[state->current_col];
    int visible_cards = m48_visible_card_count(state, state->current_col,
                                                scroll, content_h);
    int current_abs = state->current_row + scroll;

    if (current_abs < max_row) {
        if (state->current_row < visible_cards - 1) {
            state->current_row++;
        } else {
            state->scroll_offset[state->current_col]++;
        }
        state->needs_refresh = true;
    }
}

/* tui_toggle_board_mode is defined in src/tui/tui_board_mode.c — the
 * TU is deliberately ncurses-free so unit tests can link it without
 * pulling the full tui_input.c web of DB + dialog dependencies. */

void tui_toggle_select(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (item) {
        item->selected = !item->selected;
        state->needs_refresh = true;
    }
}

void tui_select_all_in_column(TUIState *state) {
    /* M48-KanbanBranchView — respect current board mode so `*` in
     * Branch view selects every item in the current branch column,
     * matching the visible highlight. */
    for (int i = 0; i < state->items.count; i++) {
        if (input_item_belongs_in_column(state,
                                         &state->items.items[i],
                                         state->current_col)) {
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

    /* ADR-0055.f9 — Settings overlay is modal (like HITL). Handle it
     * first so a stray kanban keypress doesn't leak underneath. */
    if (state->settings && state->settings->active) {
        int exit_now = spagat_settings_handle_key(state->settings, ch);
        state->needs_refresh = true;
        (void)exit_now; /* Toggle already flipped `active` if needed. */
        return;
    }

    /* T7.16.f5 / #338 — HITL overlay takes precedence for A/R/D/j/k
     * keys when active. `v` toggles in/out from either side; `q`
     * still quits the whole TUI for operator escape consistency. */
    if (state->hitl.active) {
        switch (ch) {
            case 'v':
            case 'V':
                hitl_toggle(&state->hitl);
                state->needs_refresh = true;
                return;
            case 'A':
                /* Refresh first to absorb any verdicts that landed
                 * since the last poll tick, then decide. */
                hitl_refresh(&state->hitl);
                hitl_decide(&state->hitl, true);
                state->needs_refresh = true;
                return;
            case 'R':
                hitl_refresh(&state->hitl);
                hitl_decide(&state->hitl, false);
                state->needs_refresh = true;
                return;
            case 'D':
                tui_hitl_show_details(&state->hitl, state->term_height,
                                      state->term_width);
                state->needs_refresh = true;
                return;
            case 'j':
            case KEY_DOWN:
                hitl_cursor_down(&state->hitl);
                state->needs_refresh = true;
                return;
            case 'k':
            case KEY_UP:
                hitl_cursor_up(&state->hitl);
                state->needs_refresh = true;
                return;
            case 'q':
            case 'Q':
                state->running = false;
                return;
            case KEY_RESIZE:
                getmaxyx(stdscr, state->term_height, state->term_width);
                state->col_width =
                    state->term_width / current_board_col_count(state);
                if (state->col_width < 12) state->col_width = 12;
                state->needs_refresh = true;
                return;
            default:
                /* Swallow all other keys while overlay is active so a
                 * stray 'd' (kanban delete) doesn't fire underneath. */
                return;
        }
    }

    /* Toggle into the overlay from the kanban side. Uses lowercase
     * 'v' to avoid colliding with existing kanban bindings (A/R/D
     * are all already taken by add/refresh/delete). */
    if (ch == 'v' || ch == 'V') {
        hitl_toggle(&state->hitl);
        if (state->hitl.active) hitl_refresh(&state->hitl);
        state->needs_refresh = true;
        return;
    }

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
            
        case '1': case '2': case '3': case '4': case '5': case '6': {
            int req = ch - '1';
            int max_col = current_board_col_count(state) - 1;
            if (req > max_col) req = max_col;
            state->current_col = req;
            state->current_row = 0;
            state->needs_refresh = true;
            break;
        }
            
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
            
        /* M48-KanbanCVECard: Enter opens the read-only details popup
         * (full CVE list, full 40-hex commits, description). `e`/`E`
         * still opens the full edit dialog for round-trip editing. */
        case KEY_ENTER:
        case '\n':
        case '\r':
            tui_dialog_details(state);
            break;

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
            /* M48-KanbanBranchView: column width tracks the currently
             * active board mode so a resize while in Branch view lays
             * out to 6 branch columns, not 6 status columns. */
            state->col_width =
                state->term_width / current_board_col_count(state);
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
            
        /* M48-KanbanBranchView — `b` now toggles the Kanban board
         * between Status view (6 status columns, default) and Branch
         * view (5 canonical Photon branches + Other). Session-only,
         * not persisted to appliance-config.toml. Guarded so an
         * accidental `b` during an active HITL / Settings overlay
         * doesn't toggle a hidden board underneath — the overlay
         * handlers above already returned before reaching here so
         * this is a belt-and-braces check. The git-branch quick
         * action moves to `g` (Git). */
        case 'b':
            if (!state->hitl.active &&
                !(state->settings && state->settings->active)) {
                tui_toggle_board_mode(state);
            }
            break;

        case 'g':
        case 'G':
            tui_dialog_git_branch(state);
            break;

        case 'x':
            tui_dialog_add_dependency(state);
            break;

        /* ADR-0055.f9 — `s` toggles read-only Settings mode. The old
         * `s = set_parent` binding moves to `y` (yank-as-child) to
         * free the top-bar menu key documented in ADR-0055 §5. Load
         * lazily on first press to avoid touching the config file at
         * TUI startup. */
        case 's':
            if (!state->settings) {
                state->settings = spagat_settings_load(
                    spagat_settings_effective_path());
            }
            if (state->settings) {
                spagat_settings_toggle(state->settings);
                state->needs_refresh = true;
            }
            break;

        case 'y':
        case 'Y':
            tui_dialog_set_parent(state);
            break;

        case 'S':
            tui_toggle_swimlane_mode(state);
            break;
    }
}
