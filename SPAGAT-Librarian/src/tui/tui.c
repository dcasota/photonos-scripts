#include "tui_common.h"

bool tui_init(TUIState *state) {
    memset(state, 0, sizeof(TUIState));
    
    set_escdelay(0);
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);
    curs_set(0);
    timeout(100);
    
    state->use_color = has_colors() && !env_is_set("NOCOLOR");
    state->use_utf8 = !env_is_set("PLAIN");
    
    if (state->use_color) {
        start_color();
        use_default_colors();
        init_pair(COLOR_HEADER, COLOR_WHITE, COLOR_BLUE);
        init_pair(COLOR_SELECTED, COLOR_BLACK, COLOR_YELLOW);
        init_pair(COLOR_CURRENT, COLOR_BLACK, COLOR_CYAN);
        init_pair(COLOR_STATUS_0, COLOR_MAGENTA, -1);
        init_pair(COLOR_STATUS_1, COLOR_RED, -1);
        init_pair(COLOR_STATUS_2, COLOR_YELLOW, -1);
        init_pair(COLOR_STATUS_3, COLOR_GREEN, -1);
        init_pair(COLOR_STATUS_4, COLOR_CYAN, -1);
        init_pair(COLOR_STATUS_5, COLOR_BLUE, -1);
        init_pair(COLOR_HELP, COLOR_WHITE, COLOR_BLACK);
        init_pair(COLOR_PRI_CRIT, COLOR_MAGENTA, -1);
        init_pair(COLOR_PRI_HIGH, COLOR_RED, -1);
        init_pair(COLOR_PRI_MED, COLOR_YELLOW, -1);
        init_pair(COLOR_COL_TITLE, COLOR_WHITE, COLOR_BLACK);
        init_pair(COLOR_COL_SEL, COLOR_BLACK, COLOR_WHITE);
    }
    
    getmaxyx(stdscr, state->term_height, state->term_width);
    state->col_width = state->term_width / STATUS_COUNT;
    if (state->col_width < 12) state->col_width = 12;
    
    state->running = true;
    state->needs_refresh = true;
    state->current_col = STATUS_BACKLOG;
    state->current_row = 0;
    
    tui_refresh_items(state);
    
    return true;
}

void tui_cleanup(TUIState *state) {
    db_items_free(&state->items);
    endwin();
}

void tui_refresh_items(TUIState *state) {
    db_items_free(&state->items);
    db_items_list(&state->items, NULL, 0);
    
    for (int i = 0; i < STATUS_COUNT; i++) {
        state->item_counts[i] = 0;
    }
    for (int i = 0; i < state->items.count; i++) {
        state->item_counts[state->items.items[i].status]++;
    }
    
    state->needs_refresh = true;
}

void tui_run(TUIState *state) {
    while (state->running) {
        if (state->needs_refresh) {
            clear();
            tui_draw_header(state);
            tui_draw_board(state);
            tui_draw_footer(state);
            refresh();
            state->needs_refresh = false;
        }
        
        tui_handle_input(state);
    }
}
