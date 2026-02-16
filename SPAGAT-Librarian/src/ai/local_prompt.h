#ifndef LOCAL_PROMPT_H
#define LOCAL_PROMPT_H

#include "ai.h"

void build_system_prompt(void);
int  format_prompt(const char *user_msg, const ConvHistory *history,
                   char *buf, int buf_size);

/* When true, format_prompt omits the system prompt (tool definitions).
 * Used by the tool-call follow-up loop to prevent the model from
 * repeating TOOL_CALL patterns. Reset after each call. */
extern bool skip_system_prompt;

#endif
