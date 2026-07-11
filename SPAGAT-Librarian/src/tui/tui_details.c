/*
 * tui_details.c — M48-KanbanCVECard read-only details popup (pure render).
 *
 * Renders the full drill-down for an Item into the current ncurses
 * SCREEN. This TU carries NO calls to db_item_get / tui_get_current_item
 * so the offscreen-ncurses unit test can link it directly (see
 * tests/m48_details_popup_full_test.c). The blocking wrapper that pulls
 * the current item from the TUIState + spins on getch() lives in
 * tui_details_open.c.
 */

#include "tui_common.h"
#include "spagat_m48.h"

/* Word-wrap `text` to `max_width` columns, printing each line at
 * (y+row, x). Stops when `max_rows` lines have been emitted. Returns
 * the number of rows actually printed. Whitespace at the wrap point
 * is elided; embedded newlines force a wrap. */
static int wrap_and_print(int y, int x, int max_width, int max_rows,
                          const char *text) {
    if (!text || !*text) return 0;
    int rows = 0;
    const char *p = text;
    while (*p && rows < max_rows) {
        /* Skip leading whitespace on each line. */
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;

        /* Find the end of this line's slice. */
        const char *line_start = p;
        const char *last_space = NULL;
        int col = 0;
        while (*p && *p != '\n' && col < max_width) {
            if (*p == ' ' || *p == '\t') last_space = p;
            p++;
            col++;
        }

        int slice_len;
        if (*p == '\n') {
            slice_len = (int)(p - line_start);
            p++;  /* consume the newline. */
        } else if (*p == '\0' || col < max_width) {
            slice_len = (int)(p - line_start);
        } else if (last_space) {
            slice_len = (int)(last_space - line_start);
            p = last_space + 1;
        } else {
            /* No space to break on — hard-wrap. */
            slice_len = col;
        }
        mvprintw(y + rows, x, "%.*s", slice_len, line_start);
        rows++;
    }
    return rows;
}

void tui_details_render_into(const Item *view, int term_w, int term_h) {
    if (!view) return;

    /* Parse CVE list up front so we can size the popup and later
     * emit one row per CVE. */
    SpagatCveList cves;
    m48_parse_cve_ids(view->cve_ids, &cves);

    /* Sizing:
     *   base rows: 12 (header + 8 label rows + separator + close hint)
     *   + 1 per CVE beyond the first (first shares the "CVEs fixed:" row)
     *   + N rows for wrapped description
     * Cap to term height so we never over-run the screen. */
    int desc_rows = 6;
    int cve_rows = cves.count > 0 ? cves.count : 1;
    int h = 12 + cve_rows + desc_rows;
    if (h > term_h - 2) h = term_h - 2;
    int w = 66;
    if (w > term_w - 2) w = term_w - 2;
    int bx = (term_w - w) / 2;
    int by = (term_h - h) / 2;
    if (by < 0) by = 0;
    if (bx < 0) bx = 0;

    tui_draw_box(by, bx, h, w, "Item Details");

    const int label_col = bx + 2;
    const int value_col = bx + 20;
    int row = 2;

    mvprintw(by + row, label_col, "ID:");
    mvprintw(by + row, value_col, "%lld", (long long)view->id);
    row++;

    mvprintw(by + row, label_col, "Title:");
    /* Truncate to the popup width so a long title doesn't spill. */
    mvprintw(by + row, value_col, "%.*s",
             w - (value_col - bx) - 2, view->title);
    row++;

    mvprintw(by + row, label_col, "Status:");
    mvprintw(by + row, value_col, "%s", STATUS_DISPLAY[view->status]);
    row++;

    mvprintw(by + row, label_col, "Priority:");
    mvprintw(by + row, value_col, "%s", PRIORITY_DISPLAY[view->priority]);
    row++;

    mvprintw(by + row, label_col, "Branch:");
    if (view->git_branch[0]) {
        SpagatM48BranchColor bc = m48_branch_color(view->git_branch);
        (void)bc;  /* color palette not applied in details popup for readability */
        mvprintw(by + row, value_col, "%s", view->git_branch);
    } else {
        mvprintw(by + row, value_col, "(none)");
    }
    row++;

    mvprintw(by + row, label_col, "Upstream commit:");
    if (view->upstream_commit[0]) {
        mvprintw(by + row, value_col, "%.*s",
                 w - (value_col - bx) - 2, view->upstream_commit);
    } else {
        mvprintw(by + row, value_col, "(none)");
    }
    row++;

    mvprintw(by + row, label_col, "Backport commit:");
    if (view->backport_commit[0]) {
        mvprintw(by + row, value_col, "%.*s",
                 w - (value_col - bx) - 2, view->backport_commit);
    } else {
        mvprintw(by + row, value_col, "(none)");
    }
    row++;

    mvprintw(by + row, label_col, "CVEs fixed:");
    if (cves.count == 0) {
        mvprintw(by + row, value_col, "(none)");
        row++;
    } else {
        for (int i = 0; i < cves.count && row < h - 2; i++) {
            mvprintw(by + row, value_col, "%s", cves.entries[i].id);
            row++;
        }
        /* Show a "+N more (truncated)" tail if parsing overflowed. */
        if (cves.total_parsed > cves.count && row < h - 2) {
            mvprintw(by + row, value_col, "(+%d more not shown)",
                     cves.total_parsed - cves.count);
            row++;
        }
        if (cves.had_invalid && row < h - 2) {
            mvprintw(by + row, value_col, "(malformed CVE-IDs skipped)");
            row++;
        }
    }

    /* Separator before Description. */
    if (row < h - 3) {
        mvaddch(by + row, bx, ACS_LTEE);
        for (int i = 1; i < w - 1; i++)
            mvaddch(by + row, bx + i, ACS_HLINE);
        mvaddch(by + row, bx + w - 1, ACS_RTEE);
        row++;
    }

    if (row < h - 2) {
        mvprintw(by + row, label_col, "Description:");
        row++;
        int wrap_max = w - 4;
        int wrap_budget = h - row - 2;
        if (wrap_budget < 0) wrap_budget = 0;
        wrap_and_print(by + row, label_col, wrap_max, wrap_budget,
                       view->description[0] ? view->description : "(none)");
    }

    /* Footer hint. */
    attron(A_BOLD);
    mvprintw(by + h - 2, bx + 2, "[q/Esc] close");
    attroff(A_BOLD);

    refresh();
}
