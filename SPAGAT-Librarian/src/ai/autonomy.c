#include "autonomy.h"
#include "../util/util.h"
#include <fnmatch.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <time.h>

/* ---- Defaults ---- */

void autonomy_defaults(AutonomyConfig *cfg) {
    if (!cfg) return;
    cfg->level                = AUTONOMY_OBSERVE;
    cfg->confirm_destructive  = true;
    cfg->session_write_limit  = 1048576;   /* 1 MiB */
    cfg->session_file_limit   = 20;
    cfg->max_calls_per_prompt = 5;
    cfg->max_calls_per_session = 50;
    cfg->shell_timeout        = 10;
    cfg->write_cooldown_ms    = 500;
    cfg->session_bytes_written = 0;
    cfg->session_files_created = 0;
    cfg->session_tool_calls    = 0;
    cfg->prompt_tool_calls     = 0;
    cfg->last_write_time_ms    = 0;
    cfg->session_logged        = false;
}

/* ---- Level conversion ---- */

AutonomyLevel autonomy_level_from_string(const char *s) {
    if (!s) return AUTONOMY_OBSERVE;
    if (str_equals_ignore_case(s, "none"))      return AUTONOMY_NONE;
    if (str_equals_ignore_case(s, "observe"))   return AUTONOMY_OBSERVE;
    if (str_equals_ignore_case(s, "workspace")) return AUTONOMY_WORKSPACE;
    if (str_equals_ignore_case(s, "home"))      return AUTONOMY_HOME;
    if (str_equals_ignore_case(s, "full"))      return AUTONOMY_FULL;
    return AUTONOMY_OBSERVE;
}

const char *autonomy_level_to_string(AutonomyLevel level) {
    switch (level) {
    case AUTONOMY_NONE:      return "none";
    case AUTONOMY_OBSERVE:   return "observe";
    case AUTONOMY_WORKSPACE: return "workspace";
    case AUTONOMY_HOME:      return "home";
    case AUTONOMY_FULL:      return "full";
    }
    return "observe";
}

/* ---- Read-only tool allowlist for OBSERVE mode ---- */

static const char *observe_tools[] = {
    "read_text_file",
    "read_binary_file",
    "read_multiple_files",
    "list_directory",
    "list_directory_sizes",
    "directory_tree",
    "search_files",
    "get_file_info",
    "list_allowed_paths",
    "system_info",
    "disk_usage",
    "process_list",
    "shell",
    NULL
};

static bool is_observe_tool(const char *name) {
    for (int i = 0; observe_tools[i]; i++) {
        if (strcmp(name, observe_tools[i]) == 0)
            return true;
    }
    return false;
}

/* ---- Tool permission check ---- */

bool autonomy_check_tool(const AutonomyConfig *cfg, const char *tool_name,
                         bool is_write) {
    if (!cfg || !tool_name) return false;

    switch (cfg->level) {
    case AUTONOMY_NONE:
        return false;

    case AUTONOMY_OBSERVE:
        if (is_write) return false;
        return is_observe_tool(tool_name);

    case AUTONOMY_WORKSPACE:
    case AUTONOMY_HOME:
    case AUTONOMY_FULL:
        return true;
    }
    return false;
}

/* ---- Shell allowlist for OBSERVE mode ---- */

static const char *observe_shell_allow[] = {
    "ls", "cat", "head", "tail", "wc", "file", "stat", "find", "grep",
    "awk", "ps", "top", "df", "du", "free", "uptime", "uname",
    "hostname", "id", "whoami", "groups", "ip", "ss", "netstat",
    "ping", "dig", "nslookup", "traceroute", "systemctl status",
    "journalctl", "dmesg", "rpm", "tdnf list", "tdnf info",
    "git status", "git log", "git diff", "git branch",
    NULL
};

/* Workspace-level additional write commands */
static const char *workspace_write_allow[] = {
    "mkdir", "cp", "mv", "touch", "tee", "echo",
    NULL
};

/* Commands blocked at non-FULL levels (backgrounding / persistence) */
static const char *background_tokens[] = {
    "&", "nohup", "disown", "screen", "tmux",
    NULL
};

/* Escalation / network commands blocked at WORKSPACE and HOME */
static const char *escalation_cmds[] = {
    "su", "sudo", "chown", "setcap",
    NULL
};

static const char *network_cmds[] = {
    "curl", "wget", "scp", "ssh", "nc",
    NULL
};

static const char *interactive_cmds[] = {
    "bash", "sh -i", "python", "perl", "ruby",
    NULL
};

/* Extract the first token (command name) from a command string */
static void first_token(const char *cmd, char *buf, int buf_size) {
    if (!cmd || !buf || buf_size < 2) {
        if (buf && buf_size > 0) buf[0] = '\0';
        return;
    }
    /* Skip leading whitespace */
    while (*cmd == ' ' || *cmd == '\t') cmd++;
    int i = 0;
    while (cmd[i] && cmd[i] != ' ' && cmd[i] != '\t' &&
           cmd[i] != '\n' && i < buf_size - 1) {
        buf[i] = cmd[i];
        i++;
    }
    buf[i] = '\0';
}

/* Check if command starts with a multi-word prefix (e.g. "systemctl status") */
static bool cmd_starts_with(const char *cmd, const char *prefix) {
    if (!cmd || !prefix) return false;
    /* Skip leading whitespace */
    while (*cmd == ' ' || *cmd == '\t') cmd++;
    size_t plen = strlen(prefix);
    if (strncmp(cmd, prefix, plen) != 0) return false;
    /* Must be end of string or followed by whitespace */
    char ch = cmd[plen];
    return (ch == '\0' || ch == ' ' || ch == '\t' || ch == '\n');
}

static bool list_contains_cmd(const char **list, const char *cmd) {
    char tok[128];
    first_token(cmd, tok, sizeof(tok));
    for (int i = 0; list[i]; i++) {
        /* Multi-word entries use prefix matching */
        if (strchr(list[i], ' ')) {
            if (cmd_starts_with(cmd, list[i])) return true;
        } else {
            if (strcmp(tok, list[i]) == 0) return true;
        }
    }
    return false;
}

static bool has_background_token(const char *cmd) {
    if (!cmd) return false;
    for (int i = 0; background_tokens[i]; i++) {
        if (strstr(cmd, background_tokens[i]))
            return true;
    }
    return false;
}

/* Check for "chmod +s" specifically */
static bool has_chmod_setuid(const char *cmd) {
    if (!cmd) return false;
    char tok[128];
    first_token(cmd, tok, sizeof(tok));
    if (strcmp(tok, "chmod") != 0) return false;
    return strstr(cmd, "+s") != NULL;
}

bool autonomy_shell_is_allowlisted(const char *command) {
    if (!command) return false;
    return list_contains_cmd(observe_shell_allow, command);
}

ShellDecision autonomy_check_shell(const AutonomyConfig *cfg,
                                   const char *command) {
    if (!cfg || !command) return SHELL_DENY;

    switch (cfg->level) {
    case AUTONOMY_NONE:
        return SHELL_DENY;

    case AUTONOMY_OBSERVE:
        if (autonomy_shell_is_allowlisted(command))
            return SHELL_ALLOW;
        return SHELL_DENY;

    case AUTONOMY_WORKSPACE:
        /* Block backgrounding */
        if (has_background_token(command)) return SHELL_DENY;
        /* Block escalation */
        if (list_contains_cmd(escalation_cmds, command)) return SHELL_DENY;
        if (has_chmod_setuid(command)) return SHELL_DENY;
        /* Block network */
        if (list_contains_cmd(network_cmds, command)) return SHELL_DENY;
        /* Block interactive shells */
        if (list_contains_cmd(interactive_cmds, command)) return SHELL_DENY;
        /* Allow observe + write allowlist */
        if (autonomy_shell_is_allowlisted(command)) return SHELL_ALLOW;
        if (list_contains_cmd(workspace_write_allow, command)) return SHELL_ALLOW;
        return SHELL_DENY;

    case AUTONOMY_HOME:
        /* Block backgrounding */
        if (has_background_token(command)) return SHELL_DENY;
        /* Block escalation */
        if (list_contains_cmd(escalation_cmds, command)) return SHELL_DENY;
        if (has_chmod_setuid(command)) return SHELL_DENY;
        /* Allow observe + write */
        if (autonomy_shell_is_allowlisted(command)) return SHELL_ALLOW;
        if (list_contains_cmd(workspace_write_allow, command)) return SHELL_ALLOW;
        /* Wider scope: prompt for unknowns instead of deny */
        return SHELL_PROMPT;

    case AUTONOMY_FULL:
        return SHELL_ALLOW;
    }

    return SHELL_DENY;
}

/* ---- Sensitive path check ---- */

static const char *sensitive_exact[] = {
    "/etc/shadow",
    "/etc/gshadow",
    "/proc/kcore",
    NULL
};

static const char *sensitive_glob[] = {
    "/etc/ssl/private/*",
    "/etc/pki/tls/private/*",
    "*.pem",
    "*_rsa",
    "*_ecdsa",
    "*_ed25519",
    "*.key",
    "/dev/sd*",
    "/dev/nvme*",
    "/boot/efi/*",
    NULL
};

bool autonomy_is_sensitive_path(const char *path) {
    if (!path) return false;

    for (int i = 0; sensitive_exact[i]; i++) {
        if (strcmp(path, sensitive_exact[i]) == 0)
            return true;
    }

    for (int i = 0; sensitive_glob[i]; i++) {
        if (fnmatch(sensitive_glob[i], path, 0) == 0)
            return true;
    }

    return false;
}

/* ---- Input validation ---- */

bool autonomy_validate_tool_input(const char *tool_name, const char *input,
                                  char *error, int error_size) {
    if (!tool_name || !error || error_size < 1) return false;

    size_t name_len = strlen(tool_name);
    if (name_len > 64) {
        str_safe_copy(error, "tool name exceeds 64 characters", error_size);
        return false;
    }

    if (!input) {
        /* NULL input is acceptable for some tools */
        return true;
    }

    size_t input_len = strlen(input);
    if (input_len > 16384) {
        str_safe_copy(error, "tool input exceeds 16384 bytes", error_size);
        return false;
    }

    /* Empty input is valid for tools like system_info that need no args */

    return true;
}

/* ---- Rate limiting ---- */

bool autonomy_rate_check_tool(AutonomyConfig *cfg) {
    if (!cfg) return false;

    cfg->prompt_tool_calls++;
    cfg->session_tool_calls++;

    if (cfg->max_calls_per_prompt > 0 &&
        cfg->prompt_tool_calls > cfg->max_calls_per_prompt)
        return false;

    if (cfg->max_calls_per_session > 0 &&
        cfg->session_tool_calls > cfg->max_calls_per_session)
        return false;

    return true;
}

bool autonomy_rate_check_write(AutonomyConfig *cfg, long bytes) {
    if (!cfg) return false;
    if (bytes < 0) return false;

    cfg->session_bytes_written += bytes;

    if (cfg->session_write_limit > 0 &&
        cfg->session_bytes_written > cfg->session_write_limit)
        return false;

    return true;
}

bool autonomy_rate_check_file(AutonomyConfig *cfg) {
    if (!cfg) return false;

    cfg->session_files_created++;

    if (cfg->session_file_limit > 0 &&
        cfg->session_files_created > cfg->session_file_limit)
        return false;

    return true;
}

void autonomy_rate_reset_prompt(AutonomyConfig *cfg) {
    if (!cfg) return;
    cfg->prompt_tool_calls = 0;
}

/* ---- Write cooldown ---- */

static long current_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

bool autonomy_write_cooldown_check(AutonomyConfig *cfg) {
    if (!cfg || cfg->write_cooldown_ms <= 0) return true;

    long now = current_time_ms();
    if (cfg->last_write_time_ms > 0) {
        long elapsed = now - cfg->last_write_time_ms;
        if (elapsed < cfg->write_cooldown_ms) return false;
    }
    cfg->last_write_time_ms = now;
    return true;
}

/* ---- Session start logging ---- */

void autonomy_log_session_start(AutonomyConfig *cfg) {
    if (!cfg || cfg->session_logged) return;
    cfg->session_logged = true;
    /* Caller is responsible for the actual journal_log call;
       this just tracks whether it's been done. */
}

/* ---- Memory write policy ---- */

bool autonomy_memory_write_allowed(const AutonomyConfig *cfg, bool is_append) {
    if (!cfg) return true;
    switch (cfg->level) {
    case AUTONOMY_NONE:
        return false;
    case AUTONOMY_OBSERVE:
        return is_append;   /* append-only in observe mode */
    default:
        return true;
    }
}
