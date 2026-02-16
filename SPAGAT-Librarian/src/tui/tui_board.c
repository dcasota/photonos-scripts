#include "tui_common.h"
#include <time.h>

void tui_draw_header(TUIState *state) {
    if (state->use_color) attron(COLOR_PAIR(COLOR_HEADER) | A_BOLD);
    
    mvhline(0, 0, ' ', state->term_width);
    mvprintw(0, 2, "SPAGAT-Librarian v%s", SPAGAT_VERSION);
    
    if (state->current_project > 0) {
        Project proj;
        if (db_project_get(state->current_project, &proj)) {
            mvprintw(0, 30, "[Project: %s]", proj.name);
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
    mvprintw(y, 1, "q:Quit a:Add e:Edit m:Move d:Del ?:Help");
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

static void draw_column_box(int y, int x, int h, int w, bool active,
                            const char *title, int count, bool use_color) {
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

    if (active) {
        if (use_color) attron(COLOR_PAIR(COLOR_COL_SEL) | A_BOLD);
    } else {
        if (use_color) attron(COLOR_PAIR(COLOR_COL_TITLE) | A_BOLD);
    }
    mvprintw(y, lx, "%s", label);
    if (use_color) attroff(COLOR_PAIR(COLOR_COL_SEL) | COLOR_PAIR(COLOR_COL_TITLE) | A_BOLD);

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

void tui_draw_board(TUIState *state) {
    int box_y = 2;
    int box_h = state->term_height - 3;
    if (box_h < 4) box_h = 4;
    int content_y = box_y + 1;
    int content_h = box_h - 2;

    for (int col = 0; col < STATUS_COUNT; col++) {
        int x = col * state->col_width;
        int w = state->col_width;
        /* Last column takes remaining width */
        if (col == STATUS_COUNT - 1) w = state->term_width - x;
        bool is_active_col = (col == state->current_col);

        draw_column_box(box_y, x, box_h, w, is_active_col,
                       STATUS_DISPLAY[col], state->item_counts[col],
                       state->use_color);

        /* Inner content area: 1 char inside each side border */
        int inner_x = x + 1;
        int inner_w = w - 2;
        if (inner_w < 3) inner_w = 3;

        int row = 0;
        int scroll = state->scroll_offset[col];

        for (int i = 0; i < state->items.count && row - scroll < content_h; i++) {
            Item *item = &state->items.items[i];
            if ((int)item->status != col) continue;

            if (row < scroll) { row++; continue; }

            int y = content_y + (row - scroll);
            if (y >= box_y + box_h - 1) break;

            bool is_current = (col == state->current_col &&
                               (row - scroll) == state->current_row);
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

            int max_title = inner_w - 2 - (int)strlen(id_str);
            if (max_title < 1) max_title = 1;
            char title_part[128];
            snprintf(title_part, max_title + 1 > (int)sizeof(title_part) ?
                     (int)sizeof(title_part) : max_title + 1,
                     "%s", item->title);

            mvprintw(y, inner_x, "%s", is_selected ? "*" : " ");

            if (priority_color && state->use_color) {
                attron(COLOR_PAIR(priority_color) | A_BOLD);
            }
            printw("%s", id_str);
            if (priority_color && state->use_color) {
                attroff(COLOR_PAIR(priority_color) | A_BOLD);
            }

            if (is_current && is_selected) {
                if (state->use_color) attron(COLOR_PAIR(COLOR_SELECTED) | A_BOLD);
            } else if (is_current) {
                if (state->use_color) attron(COLOR_PAIR(COLOR_CURRENT));
            } else if (is_selected) {
                if (state->use_color) attron(COLOR_PAIR(COLOR_SELECTED));
            }

            printw(" %s", title_part);

            int printed = 1 + (int)strlen(id_str) + 1 + (int)strlen(title_part);
            int pad = inner_w - printed;
            for (int p = 0; p < pad; p++) addch(' ');

            if (is_current || is_selected) {
                if (state->use_color) attroff(COLOR_PAIR(COLOR_CURRENT) |
                                              COLOR_PAIR(COLOR_SELECTED) | A_BOLD);
            }

            row++;
        }
    }
}

void tui_draw_help(TUIState *state) {
    int w = 60;
    int h = 30;
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
    mvprintw(y + row++, x + 4, "a         - Add new item");
    mvprintw(y + row++, x + 4, "Enter/e   - Edit item (all fields)");
    mvprintw(y + row++, x + 4, "m         - Move selected");
    mvprintw(y + row++, x + 4, "d         - Delete selected");
    mvprintw(y + row++, x + 4, "Space     - Toggle selection");
    mvprintw(y + row++, x + 4, "*         - Select all in column");
    mvprintw(y + row++, x + 4, "/         - Search");
    row++;
    mvprintw(y + row++, x + 2, "Quick Actions (single field):");
    mvprintw(y + row++, x + 4, "p         - Set priority     P - Select project");
    mvprintw(y + row++, x + 4, "u         - Set due date     T - Create from template");
    mvprintw(y + row++, x + 4, "t         - Time tracking    S - Toggle swimlane");
    mvprintw(y + row++, x + 4, "s         - Set parent       b - Git branch");
    mvprintw(y + row++, x + 4, "x         - Add dependency");
    row++;
    mvprintw(y + row++, x + 2, "Priority (shown by ID color):");
    mvprintw(y + row++, x + 4, "Violet=Critical  Red=High  Yellow=Medium");
    row++;
    mvprintw(y + row++, x + 2, "Press any key to close...");
    
    if (state->use_color) attroff(COLOR_PAIR(COLOR_HEADER));
    
    refresh();
    timeout(-1);
    getch();
    timeout(100);
    state->needs_refresh = true;
}
