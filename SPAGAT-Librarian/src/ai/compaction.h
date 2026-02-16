#ifndef COMPACTION_H
#define COMPACTION_H

#include "ai.h"
#include <stdbool.h>

/* Check if conversation history needs compaction based on estimated tokens.
   Returns true if compaction is recommended. */
bool compaction_needed(const ConvHistory *history, int n_ctx,
                       int system_prompt_tokens);

/* Compact conversation history by summarizing oldest messages.
   Modifies the conversation DB: replaces oldest N messages with a single
   summary message. Returns number of messages compacted. */
int compaction_compact(int64_t item_id, const char *session_id,
                       ConvHistory *history, int target_messages);

/* Estimate token count for a string (rough: chars/4) */
int compaction_estimate_tokens(const char *text);

/* Estimate total tokens in conversation history */
int compaction_estimate_history_tokens(const ConvHistory *history);

#endif
