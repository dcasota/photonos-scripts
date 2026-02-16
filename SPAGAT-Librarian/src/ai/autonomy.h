#ifndef AUTONOMY_H
#define AUTONOMY_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    AUTONOMY_NONE      = 0,
    AUTONOMY_OBSERVE   = 1,
    AUTONOMY_WORKSPACE = 2,
    AUTONOMY_HOME      = 3,
    AUTONOMY_FULL      = 4
} AutonomyLevel;

typedef struct {
    AutonomyLevel level;
    bool confirm_destructive;
    long session_write_limit;
    int  session_file_limit;
    int  max_calls_per_prompt;
    int  max_calls_per_session;
    int  shell_timeout;
    int  write_cooldown_ms;
    /* Runtime counters (not persisted) */
    long session_bytes_written;
    int  session_files_created;
    int  session_tool_calls;
    int  prompt_tool_calls;
    /* Timestamp of last write tool (for cooldown enforcement) */
    long last_write_time_ms;
    bool session_logged;
} AutonomyConfig;

/* Initialize with defaults (observe mode) */
void autonomy_defaults(AutonomyConfig *cfg);

/* Parse level from string */
AutonomyLevel autonomy_level_from_string(const char *s);
const char *autonomy_level_to_string(AutonomyLevel level);

/* Check if a tool is permitted at current level */
bool autonomy_check_tool(const AutonomyConfig *cfg, const char *tool_name,
                         bool is_write);

/* Check if a shell command is permitted at current level */
typedef enum { SHELL_ALLOW, SHELL_PROMPT, SHELL_DENY } ShellDecision;
ShellDecision autonomy_check_shell(const AutonomyConfig *cfg,
                                   const char *command);

/* Rate limiting: returns false if limit exceeded */
bool autonomy_rate_check_tool(AutonomyConfig *cfg);
bool autonomy_rate_check_write(AutonomyConfig *cfg, long bytes);
bool autonomy_rate_check_file(AutonomyConfig *cfg);
void autonomy_rate_reset_prompt(AutonomyConfig *cfg);

/* Validate model output before tool execution */
bool autonomy_validate_tool_input(const char *tool_name, const char *input,
                                  char *error, int error_size);

/* Write cooldown: returns false if too soon after last write */
bool autonomy_write_cooldown_check(AutonomyConfig *cfg);

/* Log session start (called once per session) */
void autonomy_log_session_start(AutonomyConfig *cfg);

/* Check if memory writes are allowed (append-only in observe) */
bool autonomy_memory_write_allowed(const AutonomyConfig *cfg, bool is_append);

/* Sensitive path check (hardcoded, cannot be overridden) */
bool autonomy_is_sensitive_path(const char *path);

/* Shell allowlist for observe mode */
bool autonomy_shell_is_allowlisted(const char *command);

#endif
