#ifndef TUI_H
#define TUI_H

#include "spagat.h"
#include <stdbool.h>

typedef struct {
    int term_width;
    int term_height;
    int col_width;
    int current_col;
    int current_row;
    int scroll_offset[STATUS_COUNT];
    bool use_color;
    bool use_utf8;
    bool running;
    bool needs_refresh;
    bool swimlane_mode;
    int64_t current_project;
    ItemList items;
    int item_counts[STATUS_COUNT];
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

void tui_toggle_select(TUIState *state);
void tui_select_all_in_column(TUIState *state);
void tui_clear_selection(TUIState *state);
int tui_count_selected(TUIState *state);

void tui_dialog_add(TUIState *state);
void tui_dialog_move(TUIState *state);
void tui_dialog_edit(TUIState *state);
void tui_dialog_delete(TUIState *state);
void tui_dialog_search(TUIState *state);

Item *tui_get_current_item(TUIState *state);

#endif
