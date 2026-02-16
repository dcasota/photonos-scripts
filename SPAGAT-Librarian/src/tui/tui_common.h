#ifndef TUI_COMMON_H
#define TUI_COMMON_H

#include "tui.h"
#include "../db/db.h"
#include "../util/util.h"
#include <ncurses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define COLOR_HEADER    1
#define COLOR_SELECTED  2
#define COLOR_CURRENT   3
#define COLOR_STATUS_0  4
#define COLOR_STATUS_1  5
#define COLOR_STATUS_2  6
#define COLOR_STATUS_3  7
#define COLOR_STATUS_4  8
#define COLOR_STATUS_5  9
#define COLOR_HELP      10
#define COLOR_PRI_CRIT  11
#define COLOR_PRI_HIGH  12
#define COLOR_PRI_MED   13
#define COLOR_COL_TITLE 14
#define COLOR_COL_SEL   15

void tui_draw_header(TUIState *state);
void tui_draw_footer(TUIState *state);
void tui_draw_board(TUIState *state);
void tui_draw_help(TUIState *state);

/* Draw a bordered box at (y,x) with size h*w.  Optional centered title. */
void tui_draw_box(int y, int x, int h, int w, const char *title);

Item *tui_get_current_item(TUIState *state);
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

void tui_handle_input(TUIState *state);

bool tui_edit_text_field(int y, int x, int max_width, char *buf, int buf_size);
int tui_edit_status_field(int y, int x, int current_status, int box_width);
int tui_edit_priority_field(int y, int x, int current_priority, int box_width);
void tui_format_history(const char *history, char *out, int out_size);

void tui_draw_priority_indicator(int y, int x, ItemPriority priority);
void tui_draw_due_indicator(int y, int x, time_t due_date);
void tui_dialog_set_priority(TUIState *state);
void tui_dialog_set_due_date(TUIState *state);
void tui_dialog_set_parent(TUIState *state);
void tui_dialog_add_dependency(TUIState *state);
void tui_dialog_git_branch(TUIState *state);
void tui_dialog_time_tracking(TUIState *state);
void tui_toggle_swimlane_mode(TUIState *state);
void tui_dialog_select_project(TUIState *state);
void tui_dialog_select_template(TUIState *state);

#endif
