#ifndef UTIL_H
#define UTIL_H

#include <stdbool.h>
#include <stddef.h>

char *str_trim(char *str);
char *str_duplicate(const char *str);
bool str_starts_with(const char *str, const char *prefix);
bool str_equals_ignore_case(const char *a, const char *b);
void str_safe_copy(char *dest, const char *src, size_t dest_size);
bool is_numeric(const char *str);
char *get_db_path(void);
char *get_editor(void);
bool file_exists(const char *path);
bool env_is_set(const char *name);

/* M48-KanbanBranchView — canonical Photon branch column layout for
 * the Branch view. Order is deliberate: 4.0 (oldest LTS) leftmost,
 * 6.0 rightmost, subrelease specs sandwiched between 5.0 and 6.0.
 * Kept in lock-step with SpagatM48BranchColor / spagat_appliance_config
 * `[targets].eligible_branches` so the branch badge color on line 1
 * of the card matches the column-header color in Branch view.
 *
 *   [0] "4.0"           — Photon 4.0 mainline
 *   [1] "5.0"           — Photon 5.0 mainline
 *   [2] "5.0/SPECS/90"  — 5.0 SPECS subrelease 90
 *   [3] "5.0/SPECS/91"  — 5.0 SPECS subrelease 91 (current)
 *   [4] "6.0"           — Photon 6.0 mainline
 *   [5] "Other"         — fallback bucket for any git_branch not in
 *                         [0..4] plus rows with an empty git_branch
 */
#define BRANCH_COL_COUNT 6
#define BRANCH_COL_OTHER_INDEX (BRANCH_COL_COUNT - 1)

extern const char *BRANCH_COL_DISPLAY[BRANCH_COL_COUNT];
extern const char *BRANCH_COL_KEYS[BRANCH_COL_COUNT];

/* Returns the branch-view column index [0..BRANCH_COL_COUNT-1] for a
 * given item's git_branch. Case-insensitive; unknown / empty / NULL all
 * map to BRANCH_COL_OTHER_INDEX so the "Other" fallback bucket is truly
 * exhaustive. Kept in lock-step with m48_branch_color() — anything that
 * maps to M48_BRANCH_COLOR_OTHER also lands in the Other column. */
int branch_column_for(const char *git_branch);

#endif
