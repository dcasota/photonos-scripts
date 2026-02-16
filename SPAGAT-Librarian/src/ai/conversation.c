#include "ai.h"
#include "../db/db.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Schema for AI conversations and checkpoints */
static const char *AI_SCHEMA_SQL =
    "CREATE TABLE IF NOT EXISTS conversations ("
    "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  item_id INTEGER DEFAULT 0,"
    "  session_id TEXT NOT NULL,"
    "  role TEXT NOT NULL,"
    "  content TEXT NOT NULL,"
    "  tokens_used INTEGER DEFAULT 0,"
    "  created_at INTEGER DEFAULT (strftime('%s', 'now'))"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_conv_item_session "
    "ON conversations(item_id, session_id);"
    "CREATE TABLE IF NOT EXISTS checkpoints ("
    "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  item_id INTEGER DEFAULT 0,"
    "  name TEXT NOT NULL,"
    "  state_json TEXT NOT NULL,"
    "  created_at INTEGER DEFAULT (strftime('%s', 'now'))"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_cp_item ON checkpoints(item_id);";

static bool schema_initialized = false;

static bool ensure_schema(void) {
    if (schema_initialized) return true;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    char *err = NULL;
    int rc = sqlite3_exec(db, AI_SCHEMA_SQL, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "ai: schema error: %s\n", err);
        sqlite3_free(err);
        return false;
    }

    schema_initialized = true;
    return true;
}

/* Ensure capacity in history list */
static void ensure_history_capacity(ConvHistory *history, int needed) {
    if (history->capacity >= needed) return;
    int new_cap = history->capacity ? history->capacity * 2 : 16;
    while (new_cap < needed) new_cap *= 2;
    history->messages = realloc(history->messages,
                                new_cap * sizeof(ConvMessage));
    history->capacity = new_cap;
}

bool ai_conv_add(int64_t item_id, const char *session_id, const char *role,
                 const char *content, int tokens, int64_t *out_id) {
    if (!session_id || !role || !content) return false;
    if (!ensure_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "INSERT INTO conversations (item_id, session_id, role, content, "
        "tokens_used) VALUES (?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "ai: prepare error: %s\n", sqlite3_errmsg(db));
        return false;
    }

    sqlite3_bind_int64(stmt, 1, item_id);
    sqlite3_bind_text(stmt, 2, session_id, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, role, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 4, content, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 5, tokens);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        fprintf(stderr, "ai: insert error: %s\n", sqlite3_errmsg(db));
        return false;
    }

    if (out_id) *out_id = sqlite3_last_insert_rowid(db);
    return true;
}

bool ai_conv_get_history(int64_t item_id, const char *session_id,
                         ConvHistory *history) {
    if (!session_id || !history) return false;
    if (!ensure_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    history->messages = NULL;
    history->count = 0;
    history->capacity = 0;

    const char *sql =
        "SELECT id, item_id, session_id, role, content, tokens_used, "
        "created_at FROM conversations "
        "WHERE item_id = ? AND session_id = ? ORDER BY created_at ASC, id ASC";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, item_id);
    sqlite3_bind_text(stmt, 2, session_id, -1, SQLITE_STATIC);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_history_capacity(history, history->count + 1);
        ConvMessage *msg = &history->messages[history->count];
        memset(msg, 0, sizeof(ConvMessage));

        msg->id = sqlite3_column_int64(stmt, 0);
        msg->item_id = sqlite3_column_int64(stmt, 1);
        str_safe_copy(msg->session_id,
                      (const char *)sqlite3_column_text(stmt, 2),
                      sizeof(msg->session_id));
        str_safe_copy(msg->role,
                      (const char *)sqlite3_column_text(stmt, 3),
                      sizeof(msg->role));
        msg->content = str_duplicate(
            (const char *)sqlite3_column_text(stmt, 4));
        msg->tokens_used = sqlite3_column_int(stmt, 5);
        msg->created_at = sqlite3_column_int64(stmt, 6);

        history->count++;
    }

    sqlite3_finalize(stmt);
    return true;
}

void ai_conv_free_message(ConvMessage *msg) {
    if (!msg) return;
    free(msg->content);
    msg->content = NULL;
}

void ai_conv_free_history(ConvHistory *history) {
    if (!history) return;
    for (int i = 0; i < history->count; i++) {
        ai_conv_free_message(&history->messages[i]);
    }
    free(history->messages);
    history->messages = NULL;
    history->count = 0;
    history->capacity = 0;
}

/* JSON escape: escape quotes and backslashes in content */
static char *json_escape(const char *src) {
    if (!src) return str_duplicate("");

    /* Count extra chars needed */
    size_t extra = 0;
    for (const char *p = src; *p; p++) {
        if (*p == '"' || *p == '\\' || *p == '\n' || *p == '\r' ||
            *p == '\t') {
            extra++;
        }
    }

    size_t src_len = strlen(src);
    char *escaped = malloc(src_len + extra + 1);
    if (!escaped) return str_duplicate("");

    char *d = escaped;
    for (const char *p = src; *p; p++) {
        switch (*p) {
        case '"':  *d++ = '\\'; *d++ = '"';  break;
        case '\\': *d++ = '\\'; *d++ = '\\'; break;
        case '\n': *d++ = '\\'; *d++ = 'n';  break;
        case '\r': *d++ = '\\'; *d++ = 'r';  break;
        case '\t': *d++ = '\\'; *d++ = 't';  break;
        default:   *d++ = *p;                 break;
        }
    }
    *d = '\0';

    return escaped;
}

/* JSON unescape: reverse of json_escape */
static char *json_unescape(const char *src, size_t len) {
    if (!src) return str_duplicate("");

    char *unescaped = malloc(len + 1);
    if (!unescaped) return str_duplicate("");

    char *d = unescaped;
    for (size_t i = 0; i < len; i++) {
        if (src[i] == '\\' && i + 1 < len) {
            switch (src[i + 1]) {
            case '"':  *d++ = '"';  i++; break;
            case '\\': *d++ = '\\'; i++; break;
            case 'n':  *d++ = '\n'; i++; break;
            case 'r':  *d++ = '\r'; i++; break;
            case 't':  *d++ = '\t'; i++; break;
            default:   *d++ = src[i];    break;
            }
        } else {
            *d++ = src[i];
        }
    }
    *d = '\0';

    return unescaped;
}

/* Serialize history to JSON string */
static char *serialize_history(const ConvHistory *history) {
    if (!history || history->count == 0) return str_duplicate("[]");

    /* Estimate buffer size (extra 16 for safety margin) */
    size_t est = 16;
    for (int i = 0; i < history->count; i++) {
        est += strlen(history->messages[i].content) * 2 + 128;
    }

    char *json = malloc(est);
    if (!json) return str_duplicate("[]");

    size_t pos = 0;
    json[pos++] = '[';

    for (int i = 0; i < history->count; i++) {
        const ConvMessage *msg = &history->messages[i];
        char *escaped = json_escape(msg->content);

        if (i > 0 && pos < est - 1) {
            json[pos++] = ',';
        }
        int wrote = snprintf(json + pos, est - pos,
            "{\"role\":\"%s\",\"content\":\"%s\"}",
            msg->role, escaped);
        if (wrote > 0) pos += (size_t)wrote;

        free(escaped);
    }

    if (pos < est - 1) {
        json[pos++] = ']';
    }
    json[pos] = '\0';
    return json;
}

/* Find next JSON string value after a key */
static const char *find_json_value(const char *json, const char *key,
                                    size_t *out_len) {
    char search[128];
    snprintf(search, sizeof(search), "\"%s\":\"", key);

    const char *found = strstr(json, search);
    if (!found) return NULL;

    const char *val_start = found + strlen(search);
    const char *val_end = val_start;

    /* Find closing quote, handling escapes */
    while (*val_end) {
        if (*val_end == '\\' && *(val_end + 1)) {
            val_end += 2;
            continue;
        }
        if (*val_end == '"') break;
        val_end++;
    }

    *out_len = (size_t)(val_end - val_start);
    return val_start;
}

/* Deserialize JSON string to history */
static bool deserialize_history(const char *json, ConvHistory *history) {
    if (!json || !history) return false;

    history->messages = NULL;
    history->count = 0;
    history->capacity = 0;

    /* Parse array of {role, content} objects */
    const char *p = json;

    /* Find opening bracket */
    while (*p && *p != '[') p++;
    if (!*p) return false;
    p++;

    while (*p) {
        /* Find opening brace */
        while (*p && *p != '{') {
            if (*p == ']') return true; /* End of array */
            p++;
        }
        if (!*p) break;

        /* Extract role */
        size_t role_len = 0;
        const char *role_val = find_json_value(p, "role", &role_len);
        if (!role_val) break;

        /* Extract content */
        size_t content_len = 0;
        const char *content_val = find_json_value(p, "content", &content_len);
        if (!content_val) break;

        /* Add message */
        ensure_history_capacity(history, history->count + 1);
        ConvMessage *msg = &history->messages[history->count];
        memset(msg, 0, sizeof(ConvMessage));

        if (role_len >= sizeof(msg->role)) role_len = sizeof(msg->role) - 1;
        memcpy(msg->role, role_val, role_len);
        msg->role[role_len] = '\0';

        msg->content = json_unescape(content_val, content_len);

        history->count++;

        /* Move past this object */
        const char *close = strchr(p, '}');
        if (!close) break;
        p = close + 1;
    }

    return true;
}

bool ai_checkpoint_save(int64_t item_id, const char *name, int64_t *out_id) {
    if (!name) return false;
    if (!ensure_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    /* Get current conversation history for this item */
    /* Use latest session for the item */
    const char *session_sql =
        "SELECT session_id FROM conversations WHERE item_id = ? "
        "ORDER BY created_at DESC LIMIT 1";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, session_sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, item_id);

    char session_id[SPAGAT_MAX_SESSION_ID_LEN];
    session_id[0] = '\0';

    if (sqlite3_step(stmt) == SQLITE_ROW) {
        str_safe_copy(session_id,
                      (const char *)sqlite3_column_text(stmt, 0),
                      sizeof(session_id));
    }
    sqlite3_finalize(stmt);

    if (!session_id[0]) {
        fprintf(stderr, "ai: no conversation to checkpoint\n");
        return false;
    }

    ConvHistory history;
    if (!ai_conv_get_history(item_id, session_id, &history)) {
        return false;
    }

    char *state_json = serialize_history(&history);
    ai_conv_free_history(&history);

    if (!state_json) return false;

    /* Insert checkpoint */
    const char *sql =
        "INSERT INTO checkpoints (item_id, name, state_json) VALUES (?, ?, ?)";

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        free(state_json);
        return false;
    }

    sqlite3_bind_int64(stmt, 1, item_id);
    sqlite3_bind_text(stmt, 2, name, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, state_json, -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    free(state_json);

    if (rc != SQLITE_DONE) return false;

    if (out_id) *out_id = sqlite3_last_insert_rowid(db);
    return true;
}

bool ai_checkpoint_load(int64_t checkpoint_id, ConvHistory *history) {
    if (!history) return false;
    if (!ensure_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql = "SELECT state_json FROM checkpoints WHERE id = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, checkpoint_id);

    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }

    const char *state_json = (const char *)sqlite3_column_text(stmt, 0);
    bool ok = deserialize_history(state_json, history);

    sqlite3_finalize(stmt);
    return ok;
}

bool ai_checkpoint_list(int64_t item_id, Checkpoint **checkpoints,
                        int *count) {
    if (!checkpoints || !count) return false;
    if (!ensure_schema()) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    *checkpoints = NULL;
    *count = 0;

    const char *sql =
        "SELECT id, item_id, name, state_json, created_at "
        "FROM checkpoints WHERE item_id = ? ORDER BY created_at DESC";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, item_id);

    int capacity = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        if (*count >= capacity) {
            int new_cap = capacity ? capacity * 2 : 8;
            *checkpoints = realloc(*checkpoints,
                                   new_cap * sizeof(Checkpoint));
            capacity = new_cap;
        }

        Checkpoint *cp = &(*checkpoints)[*count];
        memset(cp, 0, sizeof(Checkpoint));

        cp->id = sqlite3_column_int64(stmt, 0);
        cp->item_id = sqlite3_column_int64(stmt, 1);
        str_safe_copy(cp->name,
                      (const char *)sqlite3_column_text(stmt, 2),
                      sizeof(cp->name));
        cp->state_json = str_duplicate(
            (const char *)sqlite3_column_text(stmt, 3));
        cp->created_at = sqlite3_column_int64(stmt, 4);

        (*count)++;
    }

    sqlite3_finalize(stmt);
    return true;
}

void ai_checkpoint_free(Checkpoint *checkpoints, int count) {
    if (!checkpoints) return;
    for (int i = 0; i < count; i++) {
        free(checkpoints[i].state_json);
    }
    free(checkpoints);
}

void ai_generate_session_id(char *buf, int buf_size) {
    if (!buf || buf_size < 1) return;

    time_t now = time(NULL);
    unsigned int seed = (unsigned int)now ^ (unsigned int)getpid();
    int r1 = rand_r(&seed);
    int r2 = rand_r(&seed);

    snprintf(buf, buf_size, "ses_%lx_%04x%04x",
             (unsigned long)now, r1 & 0xFFFF, r2 & 0xFFFF);
}
