#include "compaction.h"
#include "ai.h"
#include "../util/util.h"
#include "../db/db.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Context compaction for SPAGAT-Librarian.
 *
 * Uses a heuristic approach (no LLM summarization) because:
 * 1. The LLM may not be initialized when compaction is needed
 * 2. A 2B model's summaries are unreliable for preserving tool call context
 *
 * Strategy: extract key information from oldest messages (user questions,
 * tool calls, results) into a condensed summary, replace them with a
 * single system message in the conversation DB.
 */

#define COMPACTION_MAX_SUMMARY 500
#define COMPACTION_EXCERPT_LEN 100

/*
 * Estimate token count for a string.
 * Rough approximation: 1 token ~= 4 characters.
 */
int compaction_estimate_tokens(const char *text) {
    if (!text) return 0;
    return (int)(strlen(text) / 4);
}

/*
 * Estimate total tokens in conversation history.
 */
int compaction_estimate_history_tokens(const ConvHistory *history) {
    if (!history) return 0;

    int total = 0;
    for (int i = 0; i < history->count; i++) {
        if (history->messages[i].content) {
            total += compaction_estimate_tokens(history->messages[i].content);
        }
        /* Add overhead for role markers and formatting */
        total += 4;
    }

    return total;
}

/*
 * Check if conversation history needs compaction.
 * Returns true if estimated total tokens exceed 75% of n_ctx.
 */
bool compaction_needed(const ConvHistory *history, int n_ctx,
                       int system_prompt_tokens) {
    if (!history || n_ctx <= 0) return false;

    int history_tokens = compaction_estimate_history_tokens(history);
    int total = system_prompt_tokens + history_tokens;

    /* Compact when usage exceeds 75% of context window */
    return total > (int)((double)n_ctx * 0.75);
}

/*
 * Build a condensed summary from a range of messages.
 * Extracts key information:
 * - User messages: first COMPACTION_EXCERPT_LEN chars
 * - Assistant messages: first COMPACTION_EXCERPT_LEN chars, note TOOL_CALL
 * - Tool results (system role with tool output): tool name + success/fail
 *
 * Cap total summary at COMPACTION_MAX_SUMMARY chars.
 */
static int build_summary(const ConvMessage *messages, int count,
                         char *summary, int summary_size) {
    if (!messages || count <= 0 || !summary || summary_size < 1) return 0;

    int pos = 0;
    int limit = summary_size < COMPACTION_MAX_SUMMARY
                ? summary_size : COMPACTION_MAX_SUMMARY;

    pos += snprintf(summary + pos, limit - pos,
                    "[Conversation summary: ");

    for (int i = 0; i < count && pos < limit - 32; i++) {
        const ConvMessage *msg = &messages[i];
        if (!msg->content) continue;

        if (strcmp(msg->role, "user") == 0) {
            /* Extract first COMPACTION_EXCERPT_LEN chars of user message */
            char excerpt[COMPACTION_EXCERPT_LEN + 1];
            size_t clen = strlen(msg->content);
            size_t elen = clen < COMPACTION_EXCERPT_LEN
                          ? clen : COMPACTION_EXCERPT_LEN;
            memcpy(excerpt, msg->content, elen);
            excerpt[elen] = '\0';

            /* Replace newlines with spaces */
            for (size_t j = 0; j < elen; j++) {
                if (excerpt[j] == '\n') excerpt[j] = ' ';
            }

            pos += snprintf(summary + pos, limit - pos,
                            "User: %s%s ",
                            excerpt, clen > COMPACTION_EXCERPT_LEN ? "..." : ".");

        } else if (strcmp(msg->role, "assistant") == 0) {
            /* Note if it contained TOOL_CALL */
            bool has_tool = (strstr(msg->content, "TOOL_CALL:") != NULL);

            char excerpt[COMPACTION_EXCERPT_LEN + 1];
            size_t clen = strlen(msg->content);
            size_t elen = clen < COMPACTION_EXCERPT_LEN
                          ? clen : COMPACTION_EXCERPT_LEN;
            memcpy(excerpt, msg->content, elen);
            excerpt[elen] = '\0';

            for (size_t j = 0; j < elen; j++) {
                if (excerpt[j] == '\n') excerpt[j] = ' ';
            }

            if (has_tool) {
                pos += snprintf(summary + pos, limit - pos,
                                "Assistant used tool. ");
            } else {
                pos += snprintf(summary + pos, limit - pos,
                                "Assistant: %s%s ",
                                excerpt,
                                clen > COMPACTION_EXCERPT_LEN ? "..." : ".");
            }

        } else if (strcmp(msg->role, "system") == 0) {
            /* Tool results come back as system messages */
            /* Check if this looks like a tool result */
            bool success = (strstr(msg->content, "Error:") == NULL &&
                            strstr(msg->content, "error:") == NULL);

            /* Try to identify tool name from content prefix */
            char tool_hint[64];
            tool_hint[0] = '\0';
            if (str_starts_with(msg->content, "[Tool ")) {
                const char *start = msg->content + 6;
                const char *end = strchr(start, ']');
                if (end && (end - start) < (int)sizeof(tool_hint)) {
                    size_t tlen = (size_t)(end - start);
                    memcpy(tool_hint, start, tlen);
                    tool_hint[tlen] = '\0';
                }
            }

            if (tool_hint[0]) {
                pos += snprintf(summary + pos, limit - pos,
                                "Tool %s %s. ",
                                tool_hint, success ? "OK" : "failed");
            } else {
                pos += snprintf(summary + pos, limit - pos,
                                "Result: %s. ",
                                success ? "OK" : "error");
            }
        }
    }

    /* Close summary bracket */
    if (pos < limit - 2) {
        pos += snprintf(summary + pos, limit - pos, "]");
    }

    return pos;
}

/*
 * Delete conversation messages by ID range from the database.
 */
static bool delete_messages(int64_t item_id, const char *session_id,
                            const ConvMessage *messages, int count) {
    if (!messages || count <= 0) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "DELETE FROM conversations WHERE id = ? "
        "AND item_id = ? AND session_id = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    bool ok = true;
    for (int i = 0; i < count; i++) {
        sqlite3_reset(stmt);
        sqlite3_bind_int64(stmt, 1, messages[i].id);
        sqlite3_bind_int64(stmt, 2, item_id);
        sqlite3_bind_text(stmt, 3, session_id, -1, SQLITE_STATIC);

        if (sqlite3_step(stmt) != SQLITE_DONE) {
            ok = false;
            break;
        }
    }

    sqlite3_finalize(stmt);
    return ok;
}

/*
 * Compact conversation history by summarizing oldest messages.
 *
 * Keeps the most recent `target_messages` messages intact. Older messages
 * are replaced with a single summary message.
 *
 * Returns number of messages compacted, or -1 on error.
 */
int compaction_compact(int64_t item_id, const char *session_id,
                       ConvHistory *history, int target_messages) {
    if (!session_id || !history) return -1;
    if (history->count <= target_messages) return 0;

    int to_compact = history->count - target_messages;
    if (to_compact <= 0) return 0;

    /* Build summary from the oldest messages */
    char summary[COMPACTION_MAX_SUMMARY + 64];
    build_summary(history->messages, to_compact,
                  summary, sizeof(summary));

    /* Delete the old messages from conversation DB */
    if (!delete_messages(item_id, session_id,
                         history->messages, to_compact)) {
        return -1;
    }

    /* Insert the summary as a single system message */
    int64_t summary_id;
    if (!ai_conv_add(item_id, session_id, "system", summary, 0,
                     &summary_id)) {
        return -1;
    }

    /* Rebuild the in-memory history:
     * Re-fetch from DB to get correct ordering with the new summary */
    ai_conv_free_history(history);
    if (!ai_conv_get_history(item_id, session_id, history)) {
        return -1;
    }

    return to_compact;
}
