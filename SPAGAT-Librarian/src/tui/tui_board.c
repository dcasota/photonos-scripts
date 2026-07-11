#include "tui_common.h"
#include "spagat_m48.h"
#include <time.h>

/* M48-KanbanCVECard — map the pure-C branch enum to the ncurses
 * COLOR_PAIR indices declared in tui_common.h. Kept as a lookup table
 * so the mapping is one-touch to maintain and the render code stays
 * declarative. Indexed by SpagatM48BranchColor value. */
static const int M48_BRANCH_PAIR[M48_BRANCH_COLOR_COUNT] = {
    [M48_BRANCH_COLOR_40]       = COLOR_PAIR_BRANCH_40,
    [M48_BRANCH_COLOR_50]       = COLOR_PAIR_BRANCH_50,
    [M48_BRANCH_COLOR_SPECS_90] = COLOR_PAIR_BRANCH_SPECS_90,
    [M48_BRANCH_COLOR_SPECS_91] = COLOR_PAIR_BRANCH_SPECS_91,
    [M48_BRANCH_COLOR_60]       = COLOR_PAIR_BRANCH_60,
    [M48_BRANCH_COLOR_OTHER]    = COLOR_PAIR_BRANCH_OTHER,
};

void tui_draw_header(TUIState *state) {
    if (state->use_color) attron(COLOR_PAIR(COLOR_HEADER) | A_BOLD);

    mvhline(0, 0, ' ', state->term_width);
    /* Version + board-mode badge share the left slot. The board-mode
     * badge ([Board: Status] / [Board: Branch]) surfaces the current
     * view mode after the version, matching the operator scope for
     * M48-KanbanBranchView. Fixed offsets are preserved so the tests
     * can grep the emitted bytes deterministically. */
    int written = mvprintw(0, 2, "SPAGAT-Librarian v%s", SPAGAT_VERSION);
    (void)written;
    /* Column 20 leaves ~5 chars of visual padding after the version
     * string on standard terminals — the version itself is short. */
    mvprintw(0, 20, "[Board: %s]",
             board_mode_label(state->board_mode));

    if (state->current_project > 0) {
        Project proj;
        if (db_project_get(state->current_project, &proj)) {
            /* Nudged right of the board-mode badge so the two never
             * overlap on standard 80-col terminals. */
            mvprintw(0, 40, "[Project: %s]", proj.name);
        }
    }

    int selected = tui_count_selected(state);
    if (selected > 0) {
        mvprintw(0, state->term_width - 20, "[%d selected]", selected);
    }

    if (state->use_color) attroff(COLOR_PAIR(COLOR_HEADER) | A_BOLD);
}

void tui_draw_footer(TUIState *state) {
    int y = state->term_height - 1;

    if (state->use_color) attron(COLOR_PAIR(COLOR_HELP));
    mvhline(y, 0, ' ', state->term_width);
    if (state->settings && state->settings->active) {
        mvprintw(y, 1,
                 "[Settings] Up/Down:Move Enter:Details q/s:Close");
    } else if (state->hitl.active) {
        mvprintw(y, 1, "[HITL] A:Approve R:Reject D:Details j/k:Move v:Close q:Quit");
    } else {
        /* M48-KanbanBranchView — `b:View` inserted between `d:Del`
         * and `v:HITL` so the operator can discover the toggle
         * without opening the help panel. `g:Branch` replaces the
         * pre-M48 `b:Branch` quick-action binding (the letter `b`
         * is now reserved for the view toggle; see tui_input.c). */
        mvprintw(y, 1, "q:Quit a:Add e:Edit m:Move d:Del b:View "
                       "v:HITL g:Branch s:Settings ?:Help");
    }
    if (state->use_color) attroff(COLOR_PAIR(COLOR_HELP));
}

void tui_draw_box(int y, int x, int h, int w, const char *title) {
    /* Top border */
    mvaddch(y, x, ACS_ULCORNER);
    for (int i = 1; i < w - 1; i++) mvaddch(y, x + i, ACS_HLINE);
    mvaddch(y, x + w - 1, ACS_URCORNER);

    /* Centered title in top border */
    if (title && title[0]) {
        char label[128];
        snprintf(label, sizeof(label), " %s ", title);
        int llen = (int)strlen(label);
        int lx = x + (w - llen) / 2;
        if (lx < x + 1) lx = x + 1;
        attron(A_BOLD);
        mvprintw(y, lx, "%s", label);
        attroff(A_BOLD);
    }

    /* Side borders + clear interior */
    for (int i = 1; i < h - 1; i++) {
        mvaddch(y + i, x, ACS_VLINE);
        for (int j = 1; j < w - 1; j++) mvaddch(y + i, x + j, ' ');
        mvaddch(y + i, x + w - 1, ACS_VLINE);
    }

    /* Bottom border */
    mvaddch(y + h - 1, x, ACS_LLCORNER);
    for (int i = 1; i < w - 1; i++) mvaddch(y + h - 1, x + i, ACS_HLINE);
    mvaddch(y + h - 1, x + w - 1, ACS_LRCORNER);
}

/* Draw the column-title label plus box borders. `title_color_pair` is
 * the ncurses COLOR_PAIR to use for the title text when the column is
 * not the active one; when active, COLOR_COL_SEL wins so the operator
 * always sees the active column via the same highlight regardless of
 * board mode. Passing 0 for title_color_pair means "use COLOR_COL_TITLE"
 * (the historical status-view color).
 *
 * M48-KanbanBranchView: branch view supplies title_color_pair =
 * M48_BRANCH_PAIR[col] so column headers paint in the same palette
 * that the card branch badge uses on line 1. */
static void draw_column_box(int y, int x, int h, int w, bool active,
                            const char *title, int count, bool use_color,
                            int title_color_pair) {
    /* Top border */
    mvaddch(y, x, ACS_ULCORNER);
    for (int i = 1; i < w - 1; i++) mvaddch(y, x + i, ACS_HLINE);
    mvaddch(y, x + w - 1, ACS_URCORNER);

    /* Centered title with count */
    char label[64];
    snprintf(label, sizeof(label), " %s (%d) ", title, count);
    int llen = (int)strlen(label);
    int lx = x + (w - llen) / 2;
    if (lx < x + 1) lx = x + 1;

    int applied_pair = 0;
    if (active) {
        applied_pair = COLOR_COL_SEL;
    } else if (title_color_pair > 0) {
        applied_pair = title_color_pair;
    } else {
        applied_pair = COLOR_COL_TITLE;
    }
    if (use_color) attron(COLOR_PAIR(applied_pair) | A_BOLD);
    mvprintw(y, lx, "%s", label);
    if (use_color) attroff(COLOR_PAIR(applied_pair) | A_BOLD);

    /* Side borders */
    for (int i = 1; i < h - 1; i++) {
        mvaddch(y + i, x, ACS_VLINE);
        mvaddch(y + i, x + w - 1, ACS_VLINE);
    }

    /* Bottom border */
    mvaddch(y + h - 1, x, ACS_LLCORNER);
    for (int i = 1; i < w - 1; i++) mvaddch(y + h - 1, x + i, ACS_HLINE);
    mvaddch(y + h - 1, x + w - 1, ACS_LRCORNER);
}

/* M48-KanbanBranchView — return true iff the item belongs in the given
 * board column under the current board_mode.
 *
 *   BOARD_MODE_STATUS  → item->status matches col.
 *   BOARD_MODE_BRANCH  → branch_column_for(item->git_branch) matches col.
 *
 * Kept out of tui.h so the header stays small; used both by the
 * renderer (this TU) and by the input dispatcher (tui_input.c) via
 * a corresponding helper there. */
static bool item_belongs_in_column(const TUIState *state,
                                   const Item *item, int col) {
    if (state->board_mode == BOARD_MODE_BRANCH) {
        return branch_column_for(item->git_branch) == col;
    }
    return (int)item->status == col;
}

/* Draw all items filtered into the given column. Shared between the
 * Status view and the Branch view — the only per-mode difference is
 * how items are filtered into columns (see item_belongs_in_column())
 * and how the column-title label is chosen (see tui_draw_board()).
 *
 * Card body layout (line 1 + optional line 2) is identical between
 * modes so operator muscle memory carries across the `b` toggle. */
static void draw_column_cards(TUIState *state, int col,
                              int box_y, int box_h,
                              int content_y, int content_h,
                              int inner_x, int inner_w) {
    int card_idx = 0;            /* Logical card index in this column. */
    int y_used = 0;              /* Screen rows consumed inside content_h. */
    int scroll = state->scroll_offset[col];

    for (int i = 0; i < state->items.count; i++) {
        Item *item = &state->items.items[i];
        if (!item_belongs_in_column(state, item, col)) continue;

        /* Each card consumes 1 line normally, 2 lines if it has any
         * M48-payload (CVE-ID list or commit SHA). Cursor and scroll
         * are BOTH in card-index units (see tui_input.c); y_used
         * tracks the screen-row cost so we know when the column is
         * full. */
        bool two_line = m48_should_render_two_lines(item);
        int rows_used = two_line ? 2 : 1;

        if (card_idx < scroll) {
            card_idx++;
            continue;
        }

        int y = content_y + y_used;
        if (y >= box_y + box_h - 1) break;

        bool is_current = (col == state->current_col &&
                           (card_idx - scroll) == state->current_row);
        bool is_selected = item->selected;

        int priority_color = 0;
        switch (item->priority) {
            case PRIORITY_CRITICAL: priority_color = COLOR_PRI_CRIT; break;
            case PRIORITY_HIGH:     priority_color = COLOR_PRI_HIGH; break;
            case PRIORITY_MEDIUM:   priority_color = COLOR_PRI_MED; break;
            default: break;
        }

        char id_str[16];
        snprintf(id_str, sizeof(id_str), "%lld", (long long)item->id);

        /* ── Line 1: [sel][id] [branch] title ─────────────────
         * The branch tag is rendered in its own COLOR_PAIR so the
         * operator can spot the branch at a glance. Priority still
         * colors the id, and the current/selected overlay still
         * paints the title area. */
        mvprintw(y, inner_x, "%s", is_selected ? "*" : " ");

        if (priority_color && state->use_color) {
            attron(COLOR_PAIR(priority_color) | A_BOLD);
        }
        printw("%s", id_str);
        if (priority_color && state->use_color) {
            attroff(COLOR_PAIR(priority_color) | A_BOLD);
        }

        int consumed = 1 + (int)strlen(id_str);

        if (item->git_branch[0]) {
            SpagatM48BranchColor bc = m48_branch_color(item->git_branch);
            int pair = M48_BRANCH_PAIR[bc];
            /* Truncate the branch string if it would blow past inner_w. */
            int branch_max = inner_w - consumed - 3;  /* space + [] */
            if (branch_max < 1) branch_max = 1;
            char branch_disp[SPAGAT_MAX_BRANCH_LEN];
            int trunc =
                branch_max < (int)sizeof(branch_disp) - 1
                    ? branch_max
                    : (int)sizeof(branch_disp) - 1;
            snprintf(branch_disp, trunc + 1, "%s", item->git_branch);

            printw(" ");
            if (state->use_color) attron(COLOR_PAIR(pair) | A_BOLD);
            printw("[%s]", branch_disp);
            if (state->use_color) attroff(COLOR_PAIR(pair) | A_BOLD);
            consumed += 3 + (int)strlen(branch_disp);
        }

        if (is_current && is_selected) {
            if (state->use_color) attron(COLOR_PAIR(COLOR_SELECTED) | A_BOLD);
        } else if (is_current) {
            if (state->use_color) attron(COLOR_PAIR(COLOR_CURRENT));
        } else if (is_selected) {
            if (state->use_color) attron(COLOR_PAIR(COLOR_SELECTED));
        }

        int max_title = inner_w - consumed - 1;
        if (max_title < 1) max_title = 1;
        char title_part[128];
        snprintf(title_part,
                 max_title + 1 > (int)sizeof(title_part)
                     ? (int)sizeof(title_part)
                     : max_title + 1,
                 "%s", item->title);
        printw(" %s", title_part);
        consumed += 1 + (int)strlen(title_part);

        int pad = inner_w - consumed;
        for (int p = 0; p < pad; p++) addch(' ');

        if (is_current || is_selected) {
            if (state->use_color) attroff(COLOR_PAIR(COLOR_CURRENT) |
                                          COLOR_PAIR(COLOR_SELECTED) | A_BOLD);
        }

        /* ── Line 2: CVE-XXXX +N (abcd..) ─────────────────────
         * Rendered only for cards with M48-payload; skipped for
         * every legacy row. Same current/selected overlay applies
         * so a highlighted card still stands out on both lines. */
        if (two_line && (y + 1) < (box_y + box_h - 1)) {
            char line2[128];
            m48_format_card_line2(item, line2, sizeof(line2));

            if (is_current && is_selected) {
                if (state->use_color)
                    attron(COLOR_PAIR(COLOR_SELECTED) | A_BOLD);
            } else if (is_current) {
                if (state->use_color) attron(COLOR_PAIR(COLOR_CURRENT));
            } else if (is_selected) {
                if (state->use_color) attron(COLOR_PAIR(COLOR_SELECTED));
            } else if (state->use_color) {
                attron(A_DIM);
            }

            int max_line2 = inner_w - 1;
            if (max_line2 < 1) max_line2 = 1;
            mvprintw(y + 1, inner_x, "%.*s", max_line2, line2);
            int len2 = (int)strlen(line2);
            if (len2 > max_line2) len2 = max_line2;
            int pad2 = inner_w - len2;
            for (int p = 0; p < pad2; p++) addch(' ');

            if (is_current || is_selected) {
                if (state->use_color) attroff(COLOR_PAIR(COLOR_CURRENT) |
                                              COLOR_PAIR(COLOR_SELECTED) |
                                              A_BOLD);
            } else if (state->use_color) {
                attroff(A_DIM);
            }
        }

        card_idx++;
        y_used += rows_used;
        /* Stop drawing more cards once we've filled content_h. */
        if (y_used >= content_h) break;
    }
}

/* Status board: 6 columns keyed by ItemStatus. Historical default,
 * behavior verbatim except the shared draw_column_cards() handles
 * the per-card render. */
static void draw_status_board(TUIState *state) {
    int box_y = 2;
    int box_h = state->term_height - 3;
    if (box_h < 4) box_h = 4;
    int content_y = box_y + 1;
    int content_h = box_h - 2;
    int col_count = BOARD_COL_COUNT_STATUS;
    int base_width = state->term_width / col_count;
    if (base_width < 12) base_width = 12;

    for (int col = 0; col < col_count; col++) {
        int x = col * base_width;
        int w = base_width;
        /* Last column takes remaining width so no gap at the right edge. */
        if (col == col_count - 1) w = state->term_width - x;
        bool is_active_col = (col == state->current_col);

        draw_column_box(box_y, x, box_h, w, is_active_col,
                        STATUS_DISPLAY[col], state->item_counts[col],
                        state->use_color, 0 /* no per-column title color */);

        int inner_x = x + 1;
        int inner_w = w - 2;
        if (inner_w < 3) inner_w = 3;

        draw_column_cards(state, col, box_y, box_h,
                          content_y, content_h, inner_x, inner_w);
    }
}

/* Branch board: 6 columns keyed by canonical Photon branch (4.0 /
 * 5.0 / 5.0/SPECS/90 / 5.0/SPECS/91 / 6.0) plus a trailing "Other"
 * bucket for anything unrecognised or empty. Column-title color
 * matches the per-card branch badge palette so the operator sees a
 * consistent color for a given branch across both surfaces. */
static void draw_branch_board(TUIState *state) {
    int box_y = 2;
    int box_h = state->term_height - 3;
    if (box_h < 4) box_h = 4;
    int content_y = box_y + 1;
    int content_h = box_h - 2;
    int col_count = BOARD_COL_COUNT_BRANCH;
    int base_width = state->term_width / col_count;
    if (base_width < 12) base_width = 12;

    for (int col = 0; col < col_count; col++) {
        int x = col * base_width;
        int w = base_width;
        if (col == col_count - 1) w = state->term_width - x;
        bool is_active_col = (col == state->current_col);

        /* Column title color mirrors the branch-badge palette so the
         * operator can see "5.0/SPECS/91 (12)" in magenta at the top
         * of the same column that contains magenta-badged cards. The
         * Other bucket gets the OTHER (white) badge color. */
        int title_pair = 0;
        switch (col) {
            case 0: title_pair = COLOR_PAIR_BRANCH_40;       break;
            case 1: title_pair = COLOR_PAIR_BRANCH_50;       break;
            case 2: title_pair = COLOR_PAIR_BRANCH_SPECS_90; break;
            case 3: title_pair = COLOR_PAIR_BRANCH_SPECS_91; break;
            case 4: title_pair = COLOR_PAIR_BRANCH_60;       break;
            case 5: title_pair = COLOR_PAIR_BRANCH_OTHER;    break;
            default: title_pair = COLOR_COL_TITLE;           break;
        }

        draw_column_box(box_y, x, box_h, w, is_active_col,
                        BRANCH_COL_DISPLAY[col], state->item_counts[col],
                        state->use_color, title_pair);

        int inner_x = x + 1;
        int inner_w = w - 2;
        if (inner_w < 3) inner_w = 3;

        draw_column_cards(state, col, box_y, box_h,
                          content_y, content_h, inner_x, inner_w);
    }
}

void tui_draw_board(TUIState *state) {
    if (state->board_mode == BOARD_MODE_BRANCH) {
        draw_branch_board(state);
    } else {
        draw_status_board(state);
    }
}

void tui_draw_help(TUIState *state) {
    int w = 68;   /* M48-KanbanCVECard: widened for badge palette hint. */
    int h = 40;   /* M48-KanbanBranchView: +5 rows for the Views section. */
    int x = (state->term_width - w) / 2;
    int y = (state->term_height - h) / 2;
    if (y < 0) y = 0;
    if (x < 0) x = 0;

    tui_draw_box(y, x, h, w, "SPAGAT-Librarian Help");

    if (state->use_color) attron(COLOR_PAIR(COLOR_HEADER));

    int row = 2;
    mvprintw(y + row++, x + 2, "Navigation:");
    mvprintw(y + row++, x + 4, "h/l/k/j   - Move cursor (or arrow keys)");
    mvprintw(y + row++, x + 4, "1-6       - Jump to column");
    row++;
    mvprintw(y + row++, x + 2, "Basic Actions:");
    mvprintw(y + row++, x + 4, "a         - Add new item (title/desc/tag/branch/commits/CVEs)");
    mvprintw(y + row++, x + 4, "Enter     - Details popup (full CVE list + commits + description)");
    mvprintw(y + row++, x + 4, "e         - Edit item (all fields)");
    mvprintw(y + row++, x + 4, "m         - Move selected");
    mvprintw(y + row++, x + 4, "d         - Delete selected");
    mvprintw(y + row++, x + 4, "Space     - Toggle selection");
    mvprintw(y + row++, x + 4, "*         - Select all in column");
    mvprintw(y + row++, x + 4, "/         - Search");
    row++;
    mvprintw(y + row++, x + 2, "Views:");
    mvprintw(y + row++, x + 4, "b            Toggle between Status board and Branch board");
    mvprintw(y + row++, x + 4, "Status view  6 columns by patch lifecycle status (default)");
    mvprintw(y + row++, x + 4, "Branch view  5 columns by Photon branch");
    mvprintw(y + row++, x + 4, "             (4.0/5.0/SPECS/90/91/6.0) + Other");
    row++;
    mvprintw(y + row++, x + 2, "Quick Actions (single field):");
    mvprintw(y + row++, x + 4, "p         - Set priority     P - Select project");
    mvprintw(y + row++, x + 4, "u         - Set due date     T - Create from template");
    mvprintw(y + row++, x + 4, "t         - Time tracking    S - Toggle swimlane");
    mvprintw(y + row++, x + 4, "y         - Set parent       g - Git branch");
    mvprintw(y + row++, x + 4, "x         - Add dependency");
    row++;
    mvprintw(y + row++, x + 2, "HITL Approval (T7.16.f5 / #338):");
    mvprintw(y + row++, x + 4, "v         - Toggle HITL overlay (approval queue)");
    mvprintw(y + row++, x + 4, "  A/R/D in overlay - Approve / Reject / Details");
    row++;
    mvprintw(y + row++, x + 2, "Priority (shown by ID color):");
    mvprintw(y + row++, x + 4, "Violet=Critical  Red=High  Yellow=Medium");
    row++;
    mvprintw(y + row++, x + 2, "M48 Card badges (branch color, line 2):");
    mvprintw(y + row++, x + 4, "Blue=4.0  Green=5.0  Yellow=5.0/SPECS/90");
    mvprintw(y + row++, x + 4, "Magenta=5.0/SPECS/91  Cyan=6.0  White=other");
    row++;
    mvprintw(y + row++, x + 2, "Press any key to close...");

    if (state->use_color) attroff(COLOR_PAIR(COLOR_HEADER));

    refresh();
    timeout(-1);
    getch();
    timeout(100);
    state->needs_refresh = true;
}
