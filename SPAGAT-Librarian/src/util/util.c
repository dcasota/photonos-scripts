#include "util.h"
#include "spagat.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <unistd.h>

const char *STATUS_NAMES[] = {
    "clarification",
    "wontfix",
    "backlog",
    "progress",
    "review",
    "ready"
};

const char *STATUS_DISPLAY[] = {
    "In Clarification",
    "Won't Fix",
    "In Backlog",
    "In Progress",
    "In Review",
    "Ready"
};

const char STATUS_ABBREV[] = {
    'C', 'W', 'B', 'P', 'V', 'R'
};

const char *PRIORITY_NAMES[] = {
    "none",
    "low",
    "medium",
    "high",
    "critical"
};

const char *PRIORITY_DISPLAY[] = {
    "-",
    "Low",
    "Medium",
    "High",
    "Critical"
};

ItemStatus status_from_string(const char *str) {
    if (!str) return STATUS_BACKLOG;
    for (int i = 0; i < STATUS_COUNT; i++) {
        if (str_equals_ignore_case(str, STATUS_NAMES[i])) {
            return (ItemStatus)i;
        }
    }
    if (str_equals_ignore_case(str, "todo")) return STATUS_BACKLOG;
    if (str_equals_ignore_case(str, "doing")) return STATUS_PROGRESS;
    if (str_equals_ignore_case(str, "done")) return STATUS_READY;
    if (str_equals_ignore_case(str, "hold")) return STATUS_CLARIFICATION;
    return STATUS_BACKLOG;
}

const char *status_to_string(ItemStatus status) {
    if (status >= 0 && status < STATUS_COUNT) {
        return STATUS_NAMES[status];
    }
    return STATUS_NAMES[STATUS_BACKLOG];
}

const char *status_to_display(ItemStatus status) {
    if (status >= 0 && status < STATUS_COUNT) {
        return STATUS_DISPLAY[status];
    }
    return STATUS_DISPLAY[STATUS_BACKLOG];
}

ItemPriority priority_from_string(const char *str) {
    if (!str) return PRIORITY_NONE;
    for (int i = 0; i < PRIORITY_COUNT; i++) {
        if (str_equals_ignore_case(str, PRIORITY_NAMES[i])) {
            return (ItemPriority)i;
        }
    }
    return PRIORITY_NONE;
}

const char *priority_to_string(ItemPriority priority) {
    if (priority >= 0 && priority < PRIORITY_COUNT) {
        return PRIORITY_NAMES[priority];
    }
    return PRIORITY_NAMES[PRIORITY_NONE];
}

const char *priority_to_display(ItemPriority priority) {
    if (priority >= 0 && priority < PRIORITY_COUNT) {
        return PRIORITY_DISPLAY[priority];
    }
    return PRIORITY_DISPLAY[PRIORITY_NONE];
}

char *str_trim(char *str) {
    if (!str) return NULL;
    
    while (isspace((unsigned char)*str)) str++;
    
    if (*str == 0) return str;
    
    char *end = str + strlen(str) - 1;
    while (end > str && isspace((unsigned char)*end)) end--;
    
    end[1] = '\0';
    return str;
}

char *str_duplicate(const char *str) {
    if (!str) return NULL;
    size_t len = strlen(str) + 1;
    char *dup = malloc(len);
    if (dup) memcpy(dup, str, len);
    return dup;
}

bool str_starts_with(const char *str, const char *prefix) {
    if (!str || !prefix) return false;
    return strncmp(str, prefix, strlen(prefix)) == 0;
}

bool str_equals_ignore_case(const char *a, const char *b) {
    if (!a || !b) return false;
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return false;
        a++;
        b++;
    }
    return *a == *b;
}

void str_safe_copy(char *dest, const char *src, size_t dest_size) {
    if (!dest || dest_size == 0) return;
    if (!src) {
        dest[0] = '\0';
        return;
    }
    size_t src_len = strlen(src);
    size_t copy_len = (src_len < dest_size - 1) ? src_len : dest_size - 1;
    memcpy(dest, src, copy_len);
    dest[copy_len] = '\0';
}

bool is_numeric(const char *str) {
    if (!str || !*str) return false;
    while (*str) {
        if (!isdigit((unsigned char)*str)) return false;
        str++;
    }
    return true;
}

char *get_db_path(void) {
    static char path[1024];
    
    char *custom = getenv("SPAGAT_DB");
    if (custom && custom[0]) {
        str_safe_copy(path, custom, sizeof(path));
        return path;
    }
    
    char *home = getenv("HOME");
    if (!home || !home[0]) {
        home = "/tmp";
    }
    snprintf(path, sizeof(path), "%s/.spagat.db", home);
    
    return path;
}

char *get_editor(void) {
    char *editor = getenv("EDITOR");
    if (editor && editor[0]) return editor;
    
    editor = getenv("VISUAL");
    if (editor && editor[0]) return editor;
    
    return "vi";
}

bool file_exists(const char *path) {
    if (!path) return false;
    return access(path, F_OK) == 0;
}

bool env_is_set(const char *name) {
    if (!name) return false;
    char *val = getenv(name);
    return val && val[0] && val[0] != '0';
}
