/*
 * tui_details_open.c — M48-KanbanCVECard details popup wrapper.
 *
 * Pulls the current item out of the TUIState, fetches a fresh copy
 * from sqlite (so a just-landed Rust event ingest is reflected), then
 * calls the pure render function in tui_details.c and spins on getch()
 * for the operator's close keystroke.
 *
 * Kept split from tui_details.c so the render TU is safe to link into
 * the offscreen-ncurses unit test (m48_details_popup_full_test.c)
 * without dragging in db_item_get / tui_get_current_item.
 */

#include "tui_common.h"

void tui_dialog_details(TUIState *state) {
    Item *item = tui_get_current_item(state);
    if (!item) return;

    Item view;
    if (!db_item_get(item->id, &view)) return;

    tui_details_render_into(&view, state->term_width, state->term_height);

    timeout(-1);
    int ch;
    do {
        ch = getch();
    } while (ch != 27 && ch != 'q' && ch != 'Q' &&
             ch != '\n' && ch != '\r' && ch != KEY_ENTER);
    timeout(100);
    state->needs_refresh = true;
}
