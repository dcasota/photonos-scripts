#include "ai.h"
#include "tools_fs.h"
#include "autonomy.h"
#include "execpolicy.h"
#include "sanitize.h"
#include "git_tools.h"
#include "../agent/agent.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define AI_MAX_TOOLS 64
#define AI_TOOL_NAME_LEN 64
#define AI_TOOL_DESC_LEN 256

/* Tool registration entry */
typedef struct {
    char name[AI_TOOL_NAME_LEN];
    char description[AI_TOOL_DESC_LEN];
    ai_tool_handler_fn handler;
    bool is_write;
} AITool;

static AITool tools[AI_MAX_TOOLS];
static int tool_count = 0;
static bool tools_initialized = false;
static AutonomyConfig stored_autonomy;

/* Non-static: shared with tools_builtin.c via extern */
AutonomyConfig *active_autonomy = NULL;

/* Built-in tool handlers (defined in tools_builtin.c) */
extern bool tool_read_file(const char *input, char *output, int output_size);
extern bool tool_write_file(const char *input, char *output, int output_size);
extern bool tool_list_dir(const char *input, char *output, int output_size);
extern bool tool_shell(const char *input, char *output, int output_size);

/* Register a tool */
bool ai_tool_register(const char *name, const char *description,
                      ai_tool_handler_fn handler) {
    if (!name || !handler) return false;
    if (tool_count >= AI_MAX_TOOLS) {
        fprintf(stderr, "ai: max tools reached (%d)\n", AI_MAX_TOOLS);
        return false;
    }

    /* Check for duplicate */
    for (int i = 0; i < tool_count; i++) {
        if (strcmp(tools[i].name, name) == 0) {
            tools[i].handler = handler;
            if (description) {
                str_safe_copy(tools[i].description, description,
                              sizeof(tools[i].description));
            }
            return true;
        }
    }

    /* Determine if this is a write tool */
    bool is_write = false;
    if (name) {
        const char *write_tools[] = {
            "write_file", "edit_file", "create_directory", "move_file",
            "delete_file", "git_commit", "git_add", "shell", NULL
        };
        for (int i = 0; write_tools[i]; i++) {
            if (strcmp(name, write_tools[i]) == 0) {
                is_write = true;
                break;
            }
        }
    }

    AITool *tool = &tools[tool_count];
    str_safe_copy(tool->name, name, sizeof(tool->name));
    str_safe_copy(tool->description, description ? description : "",
                  sizeof(tool->description));
    tool->handler = handler;
    tool->is_write = is_write;
    tool_count++;

    return true;
}

/* Execute a tool by name (with autonomy, rate limiting, audit) */
bool ai_tool_execute(const char *name, const char *input, char *output,
                     int output_size) {
    if (!name || !output || output_size < 1) return false;
    output[0] = '\0';

    /* Model output validation */
    if (active_autonomy) {
        char err[256];
        if (!autonomy_validate_tool_input(name, input, err, sizeof(err))) {
            snprintf(output, output_size, "Error: %s", err);
            journal_log(JOURNAL_WARN, "TOOL %s BLOCKED:validation %s",
                        name, err);
            return false;
        }
    }

    /* Find the tool */
    int idx = -1;
    for (int i = 0; i < tool_count; i++) {
        if (strcmp(tools[i].name, name) == 0) { idx = i; break; }
    }
    if (idx < 0) {
        snprintf(output, output_size, "Error: unknown tool '%s'", name);
        journal_log(JOURNAL_WARN, "TOOL %s BLOCKED:unknown", name);
        return false;
    }

    /* Autonomy level check */
    if (active_autonomy) {
        if (!autonomy_check_tool(active_autonomy, name, tools[idx].is_write)) {
            snprintf(output, output_size,
                     "Error: tool '%s' not permitted at autonomy level '%s'",
                     name, autonomy_level_to_string(active_autonomy->level));
            journal_log(JOURNAL_WARN, "TOOL %s BLOCKED:autonomy mode=%s",
                        name, autonomy_level_to_string(active_autonomy->level));
            return false;
        }

        /* Rate limiting */
        if (!autonomy_rate_check_tool(active_autonomy)) {
            snprintf(output, output_size,
                     "Error: tool call rate limit exceeded");
            journal_log(JOURNAL_WARN, "TOOL %s BLOCKED:rate_limit", name);
            return false;
        }
    }

    /* Sensitive path check for filesystem tools */
    if (input && input[0]) {
        char first_line[512];
        const char *nl = strchr(input, '\n');
        size_t len = nl ? (size_t)(nl - input) : strlen(input);
        if (len >= sizeof(first_line)) len = sizeof(first_line) - 1;
        memcpy(first_line, input, len);
        first_line[len] = '\0';

        if (autonomy_is_sensitive_path(first_line)) {
            snprintf(output, output_size,
                     "Error: access to '%s' blocked (sensitive path)",
                     first_line);
            journal_log(JOURNAL_WARN, "TOOL %s BLOCKED:sensitive path=%s",
                        name, first_line);
            return false;
        }
    }

    /* Write cooldown check (#127) */
    if (active_autonomy && tools[idx].is_write) {
        if (!autonomy_write_cooldown_check(active_autonomy)) {
            snprintf(output, output_size,
                     "Error: write cooldown not elapsed (wait %dms)",
                     active_autonomy->write_cooldown_ms);
            journal_log(JOURNAL_WARN, "TOOL %s BLOCKED:cooldown", name);
            return false;
        }
    }

    /* Audit log: before execution */
    const char *mode_str = active_autonomy ?
        autonomy_level_to_string(active_autonomy->level) : "unset";
    journal_log(JOURNAL_INFO, "TOOL %s input=\"%.100s\" mode=%s ALLOWED",
                name, input ? input : "", mode_str);

    /* Execute */
    bool result = tools[idx].handler(input, output, output_size);

    /* Post-execution: sanitize output before it gets stored */
    if (result && output[0]) {
        sanitize_redact_secrets(output, output_size);
    }

    return result;
}

/* List available tools: writes description to output buffer */
int ai_tools_list(char *output, int output_size) {
    if (!output || output_size < 1) return 0;

    int pos = 0;
    for (int i = 0; i < tool_count && pos < output_size - 128; i++) {
        pos += snprintf(output + pos, output_size - pos,
            "- %s: %s\n", tools[i].name, tools[i].description);
    }

    return tool_count;
}

/* Get tool count */
int ai_tools_count(void) {
    return tool_count;
}

/* Initialize tools gated by autonomy level */
void ai_tools_init_with_autonomy(const AutonomyConfig *acfg) {
    if (tools_initialized) return;

    /* Copy autonomy config so we own the lifetime */
    if (acfg) {
        memcpy(&stored_autonomy, acfg, sizeof(stored_autonomy));
        active_autonomy = &stored_autonomy;
    }

    /* Initialize execution policy engine */
    execpolicy_init();

    AutonomyLevel level = acfg ? acfg->level : AUTONOMY_FULL;

    if (level == AUTONOMY_NONE) {
        tools_initialized = true;
        return;
    }

    /* Legacy basic tools (always available if not NONE) */
    ai_tool_register("read_file",
        "Read the contents of a file. Input: file path.",
        tool_read_file);

    ai_tool_register("list_dir",
        "List directory contents. Input: directory path.",
        tool_list_dir);

    /* Write tools only at WORKSPACE+ */
    if (level >= AUTONOMY_WORKSPACE) {
        ai_tool_register("write_file",
            "Write content to a file. Input: path (first line) then content.",
            tool_write_file);
    }

    /* Shell at OBSERVE+ (filtered by autonomy_check_shell) */
    if (level >= AUTONOMY_OBSERVE) {
        ai_tool_register("shell",
            "Execute a shell command. Input: command string.",
            tool_shell);
    }

    /* Filesystem tools (MCP-equivalent) */
    FsConfig fscfg;
    fs_config_defaults(&fscfg);

    /* Configure write paths based on autonomy level */
    if (level == AUTONOMY_WORKSPACE) {
        WorkspacePaths wp;
        if (workspace_get_paths(&wp)) {
            str_safe_copy(fscfg.write_paths[0], wp.workspace_dir,
                          sizeof(fscfg.write_paths[0]));
            fscfg.write_count = 1;
        }
    } else if (level == AUTONOMY_HOME) {
        const char *home = getenv("HOME");
        if (home) {
            str_safe_copy(fscfg.write_paths[0], home,
                          sizeof(fscfg.write_paths[0]));
            fscfg.write_count = 1;
        }
    }
    /* FULL: write_count stays 0, meaning unrestricted writes */

    tools_fs_init(&fscfg);

    /* System info tools */
    tools_sysinfo_init();

    /* Git tools at WORKSPACE+ */
    if (level >= AUTONOMY_WORKSPACE) {
        git_tools_init();
    }

    tools_initialized = true;
}

/* Initialize built-in tools (backward compat: full autonomy) */
void ai_tools_init(void) {
    if (tools_initialized) return;

    AutonomyConfig acfg;
    autonomy_defaults(&acfg);
    acfg.level = AUTONOMY_FULL;
    ai_tools_init_with_autonomy(&acfg);
}

/* Cleanup tools */
void ai_tools_cleanup(void) {
    tool_count = 0;
    tools_initialized = false;
    active_autonomy = NULL;
    execpolicy_reset();
}
