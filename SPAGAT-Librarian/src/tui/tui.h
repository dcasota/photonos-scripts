#ifndef TUI_H
#define TUI_H

#include "spagat.h"
#include "appliance/hitl.h"
#include "appliance/settings.h"
#include "spagat_board_mode.h"
#include <stdbool.h>

typedef struct {
    int term_width;
    int term_height;
    int col_width;
    int current_col;
    int current_row;
    /* Scroll + count arrays are sized to the widest board layout so
     * both modes address the same backing storage. Toggling the mode
     * preserves per-column scroll offsets so the state is sticky. */
    int scroll_offset[BOARD_COL_COUNT_MAX];
    bool use_color;
    bool use_utf8;
    bool running;
    bool needs_refresh;
    bool swimlane_mode;
    int64_t current_project;
    ItemList items;
    int item_counts[BOARD_COL_COUNT_MAX];
    HitlState hitl;  /* T7.16.f5 / #338 operator HITL approval overlay */
    /* ADR-0055.f9 read-only Settings mode. NULL until the operator
     * presses `s` for the first time; freed by tui_cleanup. */
    spagat_settings_ctx_t *settings;
    /* M48-KanbanBranchView — active board layout. Defaults to
     * BOARD_MODE_STATUS in tui_init(); the `b` keypress toggles.
     * Session-only; never written to appliance-config.toml. */
    BoardMode board_mode;
} TUIState;

bool tui_init(TUIState *state);
void tui_cleanup(TUIState *state);
void tui_run(TUIState *state);

void tui_draw_board(TUIState *state);
void tui_draw_header(TUIState *state);
void tui_draw_footer(TUIState *state);
void tui_draw_help(TUIState *state);

void tui_handle_input(TUIState *state);
void tui_refresh_items(TUIState *state);

void tui_move_cursor_left(TUIState *state);
void tui_move_cursor_right(TUIState *state);
void tui_move_cursor_up(TUIState *state);
void tui_move_cursor_down(TUIState *state);

/* M48-KanbanBranchView — flip between Status and Branch board layouts
 * and reset the cursor to (0, 0). Session-only; NOT persisted. */
void tui_toggle_board_mode(TUIState *state);

void tui_toggle_select(TUIState *state);
void tui_select_all_in_column(TUIState *state);
void tui_clear_selection(TUIState *state);
int tui_count_selected(TUIState *state);

void tui_dialog_add(TUIState *state);
void tui_dialog_move(TUIState *state);
void tui_dialog_edit(TUIState *state);
void tui_dialog_details(TUIState *state);
void tui_dialog_delete(TUIState *state);
void tui_dialog_search(TUIState *state);

Item *tui_get_current_item(TUIState *state);

#endif
