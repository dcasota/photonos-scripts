/*
 * tui_board_mode.c — M48-KanbanBranchView board-mode toggle.
 *
 * Deliberately isolated from tui_input.c so the pure toggle can be
 * exercised by unit tests without pulling in ncurses / the DB /
 * every kanban dialog. Only touches state fields; no I/O; no
 * ncurses calls. The dispatch in tui_input.c::tui_handle_input()
 * calls this on `b`.
 *
 * Behaviour contract (mirrors the operator scope for the landing):
 *   1. Flip state->board_mode via board_mode_next().
 *   2. Reset the cursor to (col=0, row=0) so the operator always
 *      lands oriented after a toggle (see the "cursor safety" note
 *      in the M48-KanbanBranchView spec).
 *   3. Preserve state->scroll_offset[] verbatim so per-column read
 *      progress survives the toggle.
 *   4. Rebuild state->item_counts[] against the new mode so the
 *      column-header count reflects the current filter without a DB
 *      re-query.
 *   5. Recompute state->col_width to tile term_width evenly across
 *      the new column count (subject to a 12-char minimum).
 *   6. Set needs_refresh so the outer run loop redraws on the next
 *      tick.
 *
 * Session-only: NEVER writes to disk / appliance-config.toml.
 */

#include "tui.h"
#include "../util/util.h"

void tui_toggle_board_mode(TUIState *state) {
    if (!state) return;

    state->board_mode = board_mode_next(state->board_mode);
    state->current_col = 0;
    state->current_row = 0;

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
            int s = (int)state->items.items[i].status;
            if (s < 0 || s >= BOARD_COL_COUNT_MAX) continue;
            state->item_counts[s]++;
        }
    }

    if (state->term_width > 0) {
        state->col_width =
            state->term_width / board_col_count(state->board_mode);
        if (state->col_width < 12) state->col_width = 12;
    }

    state->needs_refresh = true;
}
