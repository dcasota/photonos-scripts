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
        /* M48-KanbanCVECard branch badges. Order MUST match the
         * SpagatM48BranchColor enum in include/spagat_m48.h — the render
         * code walks the enum value straight to init_pair index. */
        init_pair(COLOR_PAIR_BRANCH_40,       COLOR_BLUE,    -1);
        init_pair(COLOR_PAIR_BRANCH_50,       COLOR_GREEN,   -1);
        init_pair(COLOR_PAIR_BRANCH_SPECS_90, COLOR_YELLOW,  -1);
        init_pair(COLOR_PAIR_BRANCH_SPECS_91, COLOR_MAGENTA, -1);
        init_pair(COLOR_PAIR_BRANCH_60,       COLOR_CYAN,    -1);
        init_pair(COLOR_PAIR_BRANCH_OTHER,    COLOR_WHITE,   -1);
    }
    
    /* M48-KanbanBranchView — default to Status view; the operator can
     * flip to Branch view with `b`. Board mode is session-only; NOT
     * persisted to appliance-config.toml on toggle. */
    state->board_mode = BOARD_MODE_STATUS;

    getmaxyx(stdscr, state->term_height, state->term_width);
    state->col_width = state->term_width / board_col_count(state->board_mode);
    if (state->col_width < 12) state->col_width = 12;

    state->running = true;
    state->needs_refresh = true;
    state->current_col = STATUS_BACKLOG;
    state->current_row = 0;

    /* T7.16.f5 / #338 — initialise the HITL approval overlay state.
     * Overlay is inactive until the operator presses `v`. */
    hitl_init(&state->hitl);

    /* Settings context is lazily loaded on first `s` press so we do
     * not touch the config file at startup (may not exist on first
     * run). */
    state->settings = NULL;

    tui_refresh_items(state);

    return true;
}

void tui_cleanup(TUIState *state) {
    db_items_free(&state->items);
    if (state->settings) {
        spagat_settings_free(state->settings);
        state->settings = NULL;
    }
    endwin();
}

void tui_refresh_items(TUIState *state) {
    db_items_free(&state->items);
    db_items_list(&state->items, NULL, 0);

    /* M48-KanbanBranchView — item_counts must reflect the currently
     * active board mode. In Status view each slot counts items whose
     * status equals the slot; in Branch view each slot counts items
     * whose git_branch resolves to the slot (Other-bucket receives
     * every non-canonical branch and every empty branch). Recomputed
     * on refresh AND on `b` toggle (see tui_toggle_board_mode). */
    for (int i = 0; i < BOARD_COL_COUNT_MAX; i++) {
        state->item_counts[i] = 0;
    }
    if (state->board_mode == BOARD_MODE_BRANCH) {
        for (int i = 0; i < state->items.count; i++) {
            int col = branch_column_for(state->items.items[i].git_branch);
            state->item_counts[col]++;
        }
    } else {
        for (int i = 0; i < state->items.count; i++) {
            state->item_counts[state->items.items[i].status]++;
        }
    }

    state->needs_refresh = true;
}

void tui_run(TUIState *state) {
    int hitl_poll_counter = 0;
    while (state->running) {
        /* Tail the HITL inbox every ~10 frames (~1 s at the 100 ms
         * input timeout). Trigger a redraw if anything new arrived
         * AND the overlay is visible. */
        if (hitl_poll_counter++ >= 10) {
            hitl_poll_counter = 0;
            int added = hitl_refresh(&state->hitl);
            if (added > 0 && state->hitl.active) {
                state->needs_refresh = true;
            }
        }

        if (state->needs_refresh) {
            clear();
            tui_draw_header(state);
            tui_draw_board(state);
            if (state->hitl.active) {
                tui_hitl_draw(&state->hitl, state->term_height,
                              state->term_width);
            }
            /* ADR-0055.f9 Settings overlay renders on top of the
             * kanban, same layering rule the HITL overlay uses. */
            if (state->settings && state->settings->active) {
                spagat_settings_draw(state->settings);
            }
            tui_draw_footer(state);
            refresh();
            state->needs_refresh = false;
        }

        tui_handle_input(state);
    }
}
