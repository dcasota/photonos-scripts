#include "local_prompt.h"
#include "llama_bridge.h"
#include "../agent/agent.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * System prompt construction and chat-template formatting for the
 * local llama.cpp provider.  Split out of local.c to keep file sizes
 * manageable.
 *
 * Externs referenced from local.c (no longer static there):
 *   model, sys_prompt, sys_prompt_ready, cfg_project_prompt, cfg_n_ctx
 */

extern lb_model  *model;
extern char       sys_prompt[8192];
extern bool       sys_prompt_ready;
extern char       cfg_project_prompt[1024];
extern int        cfg_n_ctx;

bool skip_system_prompt = false;

static const char SHELL_COMMANDS[] =
    "tdnf, systemctl, journalctl, dmesg, ip, ss, iptables, df, free, "
    "top, ps, lsblk, mount, fdisk, docker, crictl, networkctl, "
    "hostnamectl, timedatectl, useradd, chmod, chown, find, grep, "
    "awk, sed, tar, curl, git";

static void build_system_prompt_compact(void) {
    snprintf(sys_prompt, sizeof(sys_prompt),
        "You are SPAGAT, a helpful assistant.\n"
        "You can use tools. Format:\n"
        "TOOL_CALL: tool_name\ninput\nEND_TOOL_CALL\n\n"
        "Tools: system_info, list_directory, read_text_file, "
        "shell, write_file\n"
        "To run shell commands use the 'shell' tool.\n"
        "Common commands: %s\n"
        "For large output, filter first (e.g. dmesg --level=err,warn).\n"
        "Example: TOOL_CALL: shell\ndmesg --level=err,warn\nEND_TOOL_CALL\n"
        "Example: TOOL_CALL: system_info\ntime\nEND_TOOL_CALL\n"
        "Answer directly when no tool is needed.",
        SHELL_COMMANDS);
    sys_prompt_ready = true;
}

static void build_system_prompt_full(void) {
    int pos = 0;
    int sz = (int)sizeof(sys_prompt);

    pos += snprintf(sys_prompt + pos, sz - pos,
        "You are SPAGAT-Librarian, an AI assistant with direct filesystem access.\n"
        "IMPORTANT: When the user asks about files, directories, or the system, "
        "you MUST use a tool. Never guess or make up file listings.\n\n"
        "To use a tool, output EXACTLY:\n"
        "TOOL_CALL: tool_name\n"
        "input\n"
        "END_TOOL_CALL\n\n"
        "Key tools:\n"
        "- list_directory: list files. Input: directory path (use . for current dir)\n"
        "- read_text_file: read a file. Input: file path\n"
        "- get_file_info: file details. Input: file path\n"
        "- search_files: find files. Input: path\\npattern\n"
        "- directory_tree: recursive listing. Input: path\n"
        "- write_file: write file. Input: path\\ncontent\n"
        "- system_info: system details. Input: category (os|cpu|ram|storage|network|time|user) or empty for all\n"
        "- disk_usage: disk space. Input: path\n"
        "- process_list: running processes. Input: empty\n"
        "- shell: run a command. Input: command string\n"
        "  Common commands: %s\n"
        "  For large output, filter first (e.g. dmesg --level=err,warn).\n\n"
        "Rules:\n"
        "- Call ONE tool per response, then STOP and wait.\n"
        "- After you receive the tool result, answer in plain text.\n"
        "- NEVER put the tool result back as tool input.\n"
        "- To run shell commands, ALWAYS use the 'shell' tool.\n\n"
        "Example - user asks 'what time is it':\n"
        "TOOL_CALL: system_info\n"
        "time\n"
        "END_TOOL_CALL\n\n"
        "Example - user asks 'check dmesg for errors':\n"
        "TOOL_CALL: shell\n"
        "dmesg --level=err,warn\n"
        "END_TOOL_CALL\n\n"
        "Example - user asks 'list files here':\n"
        "TOOL_CALL: list_directory\n"
        ".\n"
        "END_TOOL_CALL\n", SHELL_COMMANDS);

    char sysinfo[1024];
    int n = sysinfo_snapshot(sysinfo, sizeof(sysinfo));
    if (n > 0)
        pos += snprintf(sys_prompt + pos, sz - pos, "\n%s\n", sysinfo);

    if (cfg_project_prompt[0] && pos < sz - 128) {
        pos += snprintf(sys_prompt + pos, sz - pos,
            "\n## Project Instructions\n%s\n", cfg_project_prompt);
    }

    sys_prompt_ready = (pos > 0);
}

void build_system_prompt(void) {
    if (cfg_n_ctx <= 2048)
        build_system_prompt_compact();
    else
        build_system_prompt_full();
}

static int try_apply_template(const char *tmpl,
                              const lb_chat_message *msgs, int n_msg,
                              char *buf, int buf_size) {
    int32_t len = lb_chat_apply_template(tmpl, msgs, n_msg, 1,
                                          buf, buf_size);
    if (len > 0 && len < buf_size) {
        buf[len] = '\0';
        return len;
    }
    return 0;
}

int format_prompt(const char *user_msg, const ConvHistory *history,
                  char *buf, int buf_size) {
    if (!sys_prompt_ready) build_system_prompt();

    bool use_sys = sys_prompt_ready && !skip_system_prompt;
    skip_system_prompt = false;

    int n_msg = (history ? history->count : 0) + 1;
    if (use_sys) n_msg++;
    lb_chat_message *msgs = calloc(n_msg, sizeof(lb_chat_message));
    if (!msgs) goto fallback;

    {
        int idx = 0;
        if (use_sys) {
            msgs[idx].role = "system";
            msgs[idx].content = sys_prompt;
            idx++;
        }
        if (history) {
            for (int i = 0; i < history->count; i++) {
                msgs[idx].role = history->messages[i].role;
                msgs[idx].content = history->messages[i].content;
                idx++;
            }
        }
        msgs[idx].role = "user";
        msgs[idx].content = user_msg;
    }

    /* Strategy 1: use model's own chat template (new API) */
    {
        const char *tmpl = model ? lb_model_chat_template(model) : NULL;
        if (tmpl) {
            int len = try_apply_template(tmpl, msgs, n_msg, buf, buf_size);
            if (len > 0) {
                journal_log(JOURNAL_DEBUG, "prompt: strategy 1 (model template), %d chars", len);
                free(msgs);
                return len;
            }
        }
    }

    /* Strategy 2: let llama.cpp auto-detect template from model metadata
     * (works with old API where model stores tokenizer info internally) */
    if (model) {
        int32_t len = lb_chat_apply_template_model(
            model, NULL, msgs, n_msg, 1, buf, buf_size);
        if (len > 0 && len < buf_size) {
            buf[len] = '\0';
            journal_log(JOURNAL_DEBUG, "prompt: strategy 2 (auto-detect), %d chars", (int)len);
            free(msgs);
            return len;
        }
    }

    free(msgs);

    journal_log(JOURNAL_DEBUG, "prompt: strategy 3 (hardcoded fallback)");
fallback:
    /* Strategy 3: generic Llama-3/BitNet format as hardcoded fallback.
     * Format: {Role}: {content}<|eot_id|> ... Assistant: */
    {
        int pos = 0;
        if (use_sys) {
            pos += snprintf(buf + pos, buf_size - pos,
                "System: %s<|eot_id|>", sys_prompt);
        }
        if (history) {
            for (int i = 0; i < history->count && pos < buf_size - 256; i++) {
                const ConvMessage *msg = &history->messages[i];
                if (strcmp(msg->role, "user") == 0) {
                    pos += snprintf(buf + pos, buf_size - pos,
                        "User: %s<|eot_id|>", msg->content);
                } else if (strcmp(msg->role, "assistant") == 0) {
                    pos += snprintf(buf + pos, buf_size - pos,
                        "Assistant: %s<|eot_id|>", msg->content);
                } else if (strcmp(msg->role, "system") == 0) {
                    pos += snprintf(buf + pos, buf_size - pos,
                        "System: %s<|eot_id|>", msg->content);
                }
            }
        }
        pos += snprintf(buf + pos, buf_size - pos,
            "User: %s<|eot_id|>Assistant: ", user_msg);
        return pos;
    }
}
