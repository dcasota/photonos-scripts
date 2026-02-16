#include "agent.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Default file contents */
static const char *DEFAULT_AGENT_MD =
    "# SPAGAT-Librarian Agent\n"
    "\n"
    "You are SPAGAT-Librarian, an AI assistant for task management on Photon OS.\n"
    "\n"
    "## Capabilities\n"
    "- Manage Kanban board tasks (add, move, delete, list)\n"
    "- Run scheduled maintenance via cron jobs\n"
    "- Process heartbeat tasks periodically\n"
    "- Work fully offline with local models\n";

static const char *DEFAULT_IDENTITY_MD =
    "# Agent Identity\n"
    "\n"
    "Name: SPAGAT-Librarian\n"
    "Role: Task Management AI\n"
    "Style: Concise, helpful\n";

static const char *DEFAULT_SOUL_MD =
    "# Agent Soul\n"
    "\n"
    "Core directives:\n"
    "1. Help user manage tasks efficiently\n"
    "2. Work offline\n"
    "3. Respect workspace sandbox\n";

static const char *DEFAULT_USER_MD =
    "# User Preferences\n"
    "\n"
    "(Edit this file to customize your experience)\n";

static const char *DEFAULT_MEMORY_MD =
    "# Agent Memory\n"
    "\n"
    "(Persistent memory stored here)\n";

static const char *DEFAULT_HEARTBEAT_MD =
    "# Heartbeat Tasks\n"
    "\n"
    "(Define periodic tasks here)\n"
    "# Format: one task per line, prefixed with '- '\n"
    "# Example:\n"
    "# - Review overdue tasks in backlog\n"
    "# - Check for items stuck in progress > 7 days\n";

static const char *DEFAULT_TOOLS_MD =
    "# Available Tools\n"
    "\n"
    "## Basic\n"
    "- read_file: Read contents of a file in workspace\n"
    "- write_file: Write contents to a file in workspace\n"
    "- list_dir: List directory contents in workspace\n"
    "- shell: Execute a shell command (sandboxed)\n"
    "\n"
    "## Filesystem (full / access)\n"
    "- read_text_file: Read text file. path[\\nhead=N|tail=N]\n"
    "- read_binary_file: Read binary as base64. path\n"
    "- read_multiple_files: Read many files. path1\\npath2\n"
    "- list_directory: List dir entries. path\n"
    "- list_directory_sizes: List with sizes. path[\\nsort=size]\n"
    "- directory_tree: Recursive tree. path[\\nexclude=p1,p2]\n"
    "- search_files: Glob search. path\\npattern\n"
    "- get_file_info: File stat. path\n"
    "- write_file: Write file. path\\ncontent\n"
    "- edit_file: Edit file. path\\nold\\nnew\n"
    "- create_directory: Mkdir. path\n"
    "- move_file: Move. src\\ndst\n"
    "- delete_file: Delete. path\n"
    "- list_allowed_paths: Show access config\n"
    "\n"
    "## System\n"
    "- system_info: System snapshot or category (os/cpu/ram/storage/network/time/user)\n"
    "- disk_usage: Disk usage for path\n"
    "- process_list: Top processes. sort=mem|sort=name\n";

static const char *DEFAULT_SYSTEM_MD =
    "# System Environment\n"
    "\n"
    "This file accumulates observations about the host system.\n"
    "The agent reads and updates it to maintain persistent environment awareness.\n"
    "\n"
    "## Discovered Information\n"
    "\n"
    "(Will be populated automatically on first agent run)\n";

bool workspace_write_default_file(const char *path, const char *filename,
                                  const char *content) {
    if (!path || !filename || !content) return false;

    char filepath[1024];
    snprintf(filepath, sizeof(filepath), "%s/%s", path, filename);

    /* Don't overwrite existing files */
    if (file_exists(filepath)) {
        return true;
    }

    FILE *fp = fopen(filepath, "w");
    if (!fp) {
        fprintf(stderr, "Cannot write %s: ", filepath);
        perror("");
        return false;
    }

    size_t len = strlen(content);
    size_t written = fwrite(content, 1, len, fp);
    fclose(fp);

    if (written != len) {
        fprintf(stderr, "Short write to %s\n", filepath);
        return false;
    }

    return true;
}

bool workspace_onboard(const WorkspacePaths *paths) {
    if (!paths) return false;

    /* Ensure all directories exist */
    if (!workspace_ensure_dirs(paths)) {
        fprintf(stderr, "Failed to create workspace directories\n");
        return false;
    }

    /* Write workspace markdown files */
    bool ok = true;

    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "AGENT.md", DEFAULT_AGENT_MD);
    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "IDENTITY.md", DEFAULT_IDENTITY_MD);
    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "SOUL.md", DEFAULT_SOUL_MD);
    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "USER.md", DEFAULT_USER_MD);
    ok = ok && workspace_write_default_file(paths->memory_dir,
                                            "MEMORY.md", DEFAULT_MEMORY_MD);
    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "HEARTBEAT.md", DEFAULT_HEARTBEAT_MD);
    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "TOOLS.md", DEFAULT_TOOLS_MD);
    ok = ok && workspace_write_default_file(paths->workspace_dir,
                                            "SYSTEM.md", DEFAULT_SYSTEM_MD);

    /* Write default config */
    if (!file_exists(paths->config_path)) {
        SpagatConfig config;
        config_set_defaults(&config);
        ok = ok && config_save(paths->config_path, &config);
    }

    if (ok) {
        printf("Workspace initialized at %s\n", paths->workspace_dir);
    } else {
        fprintf(stderr, "Workspace initialization had errors\n");
    }

    return ok;
}

void config_set_defaults(SpagatConfig *config) {
    if (!config) return;

    memset(config, 0, sizeof(SpagatConfig));

    str_safe_copy(config->provider, "local", sizeof(config->provider));
    config->max_tokens = 512;
    config->temperature = 0.7f;
    config->max_tool_iterations = 5;
    config->restrict_to_workspace = true;

    config->local_enabled = true;
    str_safe_copy(config->local_engine, "llama.cpp",
                  sizeof(config->local_engine));
    str_safe_copy(config->local_model_path, "",
                  sizeof(config->local_model_path));
    str_safe_copy(config->local_device, "cpu", sizeof(config->local_device));
    config->local_n_gpu_layers = 0;
    config->local_n_ctx = 4096;
    config->local_temperature = 0.7f;
    config->local_top_p = 0.9f;

    config->heartbeat_enabled = true;
    config->heartbeat_interval = 60;

    str_safe_copy(config->fs_access_mode, "full",
                  sizeof(config->fs_access_mode));

    /* Autonomy defaults */
    str_safe_copy(config->autonomy_mode, "observe",
                  sizeof(config->autonomy_mode));
    config->confirm_destructive = true;
    config->session_write_limit = 1048576;
    config->session_file_limit = 20;
    config->max_tool_calls_per_prompt = 5;
    config->max_tool_calls_per_session = 50;
    config->shell_timeout = 10;

    /* Retry logic (#8) */
    config->max_retries = 2;
    config->retry_delay_ms = 500;

    /* Per-project system prompt (#28) */
    config->project_system_prompt[0] = '\0';
}
