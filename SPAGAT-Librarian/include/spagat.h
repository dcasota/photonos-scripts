#ifndef SPAGAT_H
#define SPAGAT_H

#include <stdint.h>
#include <stdbool.h>
#include <time.h>

#define SPAGAT_VERSION "0.2.0"
#define SPAGAT_DB_NAME ".spagat.db"
#define SPAGAT_MAX_TITLE_LEN 128
#define SPAGAT_MAX_DESC_LEN 512
#define SPAGAT_MAX_TAG_LEN 64
#define SPAGAT_MAX_HISTORY_LEN 256
#define SPAGAT_MAX_PROJECT_LEN 64
#define SPAGAT_MAX_BRANCH_LEN 128
#define SPAGAT_MAX_TEMPLATE_NAME_LEN 64

typedef enum {
    STATUS_CLARIFICATION = 0,
    STATUS_WONTFIX,
    STATUS_BACKLOG,
    STATUS_PROGRESS,
    STATUS_REVIEW,
    STATUS_READY,
    STATUS_COUNT
} ItemStatus;

typedef enum {
    PRIORITY_NONE = 0,
    PRIORITY_LOW,
    PRIORITY_MEDIUM,
    PRIORITY_HIGH,
    PRIORITY_CRITICAL,
    PRIORITY_COUNT
} ItemPriority;

extern const char *STATUS_NAMES[];
extern const char *STATUS_DISPLAY[];
extern const char STATUS_ABBREV[];
extern const char *PRIORITY_NAMES[];
extern const char *PRIORITY_DISPLAY[];

typedef struct {
    int64_t id;
    int64_t project_id;
    int64_t parent_id;
    ItemStatus status;
    ItemPriority priority;
    char title[SPAGAT_MAX_TITLE_LEN];
    char description[SPAGAT_MAX_DESC_LEN];
    char tag[SPAGAT_MAX_TAG_LEN];
    char history[SPAGAT_MAX_HISTORY_LEN];
    char git_branch[SPAGAT_MAX_BRANCH_LEN];
    time_t due_date;
    time_t created_at;
    time_t updated_at;
    time_t time_spent;
    bool selected;
} Item;

typedef struct {
    Item *items;
    int count;
    int capacity;
} ItemList;

typedef struct {
    int64_t id;
    char name[SPAGAT_MAX_PROJECT_LEN];
    char description[SPAGAT_MAX_DESC_LEN];
    time_t created_at;
} Project;

typedef struct {
    Project *projects;
    int count;
    int capacity;
} ProjectList;

typedef struct {
    int64_t from_id;
    int64_t to_id;
} Dependency;

typedef struct {
    Dependency *deps;
    int count;
    int capacity;
} DependencyList;

typedef struct {
    int64_t id;
    char name[SPAGAT_MAX_TEMPLATE_NAME_LEN];
    char title[SPAGAT_MAX_TITLE_LEN];
    char description[SPAGAT_MAX_DESC_LEN];
    char tag[SPAGAT_MAX_TAG_LEN];
    ItemStatus status;
    ItemPriority priority;
} Template;

typedef struct {
    Template *templates;
    int count;
    int capacity;
} TemplateList;

typedef struct {
    int64_t id;
    char name[SPAGAT_MAX_PROJECT_LEN];
    int current_project;
    int current_col;
    int current_row;
    int scroll_offsets[STATUS_COUNT];
    bool swimlane_mode;
    time_t saved_at;
} Session;

ItemStatus status_from_string(const char *str);
const char *status_to_string(ItemStatus status);
const char *status_to_display(ItemStatus status);
ItemPriority priority_from_string(const char *str);
const char *priority_to_string(ItemPriority priority);
const char *priority_to_display(ItemPriority priority);

#endif
