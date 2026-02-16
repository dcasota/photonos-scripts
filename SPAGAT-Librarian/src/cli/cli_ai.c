#include "../ai/ai.h"
#include "../ai/local_prompt.h"
#include "../ai/autonomy.h"
#include "../ai/sysaware.h"
#include "../agent/agent.h"
#include "../util/util.h"
#include "../util/journal.h"
#include "cli.h"
#include "input_classify.h"
#include "agent_input.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TOOL_CALL_PREFIX "TOOL_CALL:"
#define TOOL_CALL_END    "END_TOOL_CALL"

static bool extract_tool_call(const char *response, char *tool_name,
                              int name_size, char *tool_input,
                              int input_size) {
    const char *start = strstr(response, TOOL_CALL_PREFIX);
    if (!start) return false;

    start += strlen(TOOL_CALL_PREFIX);
    while (*start == ' ') start++;

    /* Extract tool name (rest of line) */
    const char *nl = strchr(start, '\n');
    if (!nl) return false;

    size_t nlen = (size_t)(nl - start);
    if (nlen >= (size_t)name_size) nlen = name_size - 1;
    memcpy(tool_name, start, nlen);
    tool_name[nlen] = '\0';

    /* Trim trailing whitespace (\r, spaces, tabs) from tool name */
    size_t tlen = strlen(tool_name);
    while (tlen > 0 && (tool_name[tlen - 1] == ' ' ||
                        tool_name[tlen - 1] == '\r' ||
                        tool_name[tlen - 1] == '\t')) {
        tool_name[--tlen] = '\0';
    }

    /* Extract input (everything between name line and END_TOOL_CALL) */
    const char *input_start = nl + 1;
    const char *input_end = strstr(input_start, TOOL_CALL_END);
    if (!input_end) {
        str_safe_copy(tool_input, input_start, input_size);
    } else {
        size_t ilen = (size_t)(input_end - input_start);
        while (ilen > 0 && (input_start[ilen - 1] == '\n' ||
                            input_start[ilen - 1] == '\r'))
            ilen--;
        if (ilen >= (size_t)input_size) ilen = input_size - 1;
        memcpy(tool_input, input_start, ilen);
        tool_input[ilen] = '\0';
    }
    return true;
}

static void stream_to_stdout(const char *piece, void *user_data) {
    (void)user_data;
    printf("%s", piece);
    fflush(stdout);
}

static bool generate_with_tools(AIProvider *provider, const char *prompt,
                                ConvHistory *hist, char *response,
                                int resp_size, int64_t item_id,
                                const char *session_id, int max_iters) {
    char current_prompt[SPAGAT_MAX_PROMPT_LEN];
    str_safe_copy(current_prompt, prompt, sizeof(current_prompt));

    char last_tool[64] = {0};
    char last_result[SPAGAT_MAX_RESPONSE_LEN];
    last_result[0] = '\0';

    for (int iter = 0; iter < max_iters; iter++) {
        response[0] = '\0';

        /* First iteration: generate silently (might be a tool call).
         * Final iteration (no tool call): stream to stdout. */
        if (!provider->generate(current_prompt, hist, response,
                                resp_size, NULL, NULL)) {
            return false;
        }

        char tool_name[64], tool_input[SPAGAT_MAX_PROMPT_LEN];
        if (!extract_tool_call(response, tool_name, sizeof(tool_name),
                               tool_input, sizeof(tool_input))) {
            /* No tool call -- this is the final answer.  Print any
             * text before TOOL_CALL markers (model may have leaked
             * partial markers that didn't parse). */
            printf("%s", response);
            fflush(stdout);
            return true;
        }

        /* Detect repeated identical tool calls -- break the loop */
        if (iter > 0 && strcmp(tool_name, last_tool) == 0) {
            snprintf(response, resp_size, "%s", last_result);
            printf("%s", response);
            fflush(stdout);
            return true;
        }

        printf("[Using %s...]\n", tool_name);
        fflush(stdout);

        char tool_output[SPAGAT_MAX_RESPONSE_LEN];
        tool_output[0] = '\0';
        bool tool_ok = ai_tool_execute(tool_name, tool_input,
                                       tool_output, sizeof(tool_output));

        if (!tool_ok) {
            journal_log(JOURNAL_WARN, "tool %s failed: %.200s",
                        tool_name, tool_output);
        } else {
            journal_log(JOURNAL_DEBUG, "tool %s OK (%d bytes)",
                        tool_name, (int)strlen(tool_output));
        }

        str_safe_copy(last_tool, tool_name, sizeof(last_tool));

        ai_conv_add(item_id, session_id, "assistant", response, 0, NULL);

        char tool_msg[SPAGAT_MAX_RESPONSE_LEN + 128];
        snprintf(tool_msg, sizeof(tool_msg), "[Tool %s %s]\n%s",
                 tool_name, tool_ok ? "result" : "error", tool_output);
        ai_conv_add(item_id, session_id, "user", tool_msg, 0, NULL);

        if (hist) ai_conv_free_history(hist);
        memset(hist, 0, sizeof(*hist));

        if (tool_ok) {
            str_safe_copy(last_result, tool_output, sizeof(last_result));
            skip_system_prompt = true;
            snprintf(current_prompt, sizeof(current_prompt),
                     "[DATA]\n%s\n[/DATA]\n"
                     "[QUESTION] %s [/QUESTION]\n"
                     "Based on [DATA], answer [QUESTION] in one sentence.",
                     tool_output, prompt);
        } else {
            snprintf(current_prompt, sizeof(current_prompt),
                     "Your tool call '%s' failed with: %s\n"
                     "Try a different approach to answer: %s",
                     tool_name, tool_output, prompt);
        }
    }

    if (last_result[0]) {
        snprintf(response, resp_size, "%s", last_result);
        printf("%s", response);
        fflush(stdout);
    }
    return true;
}

int cmd_agent(int argc, char **argv) {
    /* Parse --autonomy= flag before ai_init (#85) */
    const char *autonomy_override = NULL;
    int arg_start = 0;
    for (int i = 0; i < argc; i++) {
        if (strncmp(argv[i], "--autonomy=", 11) == 0) {
            autonomy_override = argv[i] + 11;
        }
    }

    if (!ai_init()) {
        fprintf(stderr, "Failed to initialize AI provider\n");
        return 1;
    }

    /* Apply session autonomy override (#85) */
    if (autonomy_override) {
        AutonomyLevel lvl = autonomy_level_from_string(autonomy_override);
        if (lvl == AUTONOMY_NONE &&
            !str_equals_ignore_case(autonomy_override, "none")) {
            fprintf(stderr, "Invalid autonomy level: %s\n", autonomy_override);
            fprintf(stderr, "Valid: none, observe, workspace, home, full\n");
            ai_cleanup();
            return 1;
        }
        /* Reinitialize tools with overridden autonomy */
        ai_tools_cleanup();
        AutonomyConfig acfg;
        autonomy_defaults(&acfg);
        acfg.level = lvl;
        ai_tools_init_with_autonomy(&acfg);
        journal_log(JOURNAL_INFO, "SESSION autonomy override: %s",
                    autonomy_level_to_string(lvl));
        printf("Autonomy override: %s (session only)\n",
               autonomy_level_to_string(lvl));
    }

    /* Run sysaware update on agent start (#73, #74) */
    WorkspacePaths wp;
    if (workspace_get_paths(&wp)) {
        sysaware_update(wp.workspace_dir);
    }

    AIProvider *provider = ai_get_provider();
    if (!provider || !provider->is_available ||
        !provider->is_available()) {
        fprintf(stderr, "AI provider not available\n");
        ai_cleanup();
        return 1;
    }

    int result = 0;

    if (argc >= 2 && str_equals_ignore_case(argv[arg_start], "-m")) {
        char response[SPAGAT_MAX_RESPONSE_LEN];
        response[0] = '\0';
        if (provider->generate(argv[arg_start + 1], NULL, response,
                               sizeof(response), NULL, NULL)) {
            printf("%s\n", response);
        } else {
            fprintf(stderr, "AI generation failed\n");
            result = 1;
        }
    } else {
        char session_id[SPAGAT_MAX_SESSION_ID_LEN];
        ai_generate_session_id(session_id, sizeof(session_id));

        printf("SPAGAT Agent (type 'exit' to quit)\n");
        printf("Provider: %s\n",
               provider->get_name ? provider->get_name() : "unknown");
        printf("Tip: type commands directly (ls, df, dmesg...)"
               " or ask questions.\n"
               "     Prefix ! to force shell, ? to force AI."
               "  Ctrl-L: autonomy level.\n\n");

        char input[SPAGAT_MAX_PROMPT_LEN];
        while (1) {
            AgentInputResult ir = agent_read_line("> ", input,
                                                  sizeof(input));
            if (ir == AINPUT_EOF) break;
            if (ir == AINPUT_CTRL_L) {
                agent_show_autonomy_picker();
                continue;
            }

            if (str_equals_ignore_case(input, "exit") ||
                str_equals_ignore_case(input, "quit")) {
                break;
            }
            if (input[0] == '\0') continue;

            /* Prefix escapes: ! forces shell, ? forces LLM */
            const char *effective = input;
            InputMode forced = INPUT_LLM;
            bool mode_forced = false;
            if (input[0] == '!' && input[1]) {
                effective = input + 1;
                forced = INPUT_SHELL;
                mode_forced = true;
            } else if (input[0] == '?' && input[1]) {
                effective = input + 1;
                while (*effective == ' ') effective++;
                forced = INPUT_LLM;
                mode_forced = true;
            }

            InputMode mode = mode_forced ? forced
                                         : classify_input(effective);

            if (mode == INPUT_SHELL) {
                char shell_out[SPAGAT_MAX_RESPONSE_LEN];
                shell_out[0] = '\0';
                bool ok = ai_tool_execute("shell", effective,
                                          shell_out,
                                          sizeof(shell_out));
                if (ok) {
                    printf("%s\n", shell_out);
                } else {
                    fprintf(stderr, "%s\n", shell_out);
                }
                continue;
            }

            ai_conv_add(0, session_id, "user", effective, 0, NULL);

            ConvHistory hist;
            ai_conv_get_history(0, session_id, &hist);

            char response[SPAGAT_MAX_RESPONSE_LEN];
            response[0] = '\0';

            if (generate_with_tools(provider, effective, &hist,
                                    response, sizeof(response),
                                    0, session_id, 5)) {
                printf("\n\n");
                ai_conv_add(0, session_id, "assistant",
                            response, 0, NULL);
            } else {
                fprintf(stderr, "Generation failed\n\n");
            }

            ai_conv_free_history(&hist);
        }
    }

    ai_cleanup();
    return result;
}

int cmd_ai_chat(int64_t item_id) {
    if (!ai_init()) {
        fprintf(stderr, "Failed to initialize AI provider\n");
        return 1;
    }

    AIProvider *provider = ai_get_provider();
    if (!provider || !provider->is_available ||
        !provider->is_available()) {
        fprintf(stderr, "AI provider not available\n");
        ai_cleanup();
        return 1;
    }

    char session_id[SPAGAT_MAX_SESSION_ID_LEN];
    snprintf(session_id, sizeof(session_id), "task_%lld",
             (long long)item_id);

    printf("AI Chat for task %lld (type 'exit' to quit)\n\n",
           (long long)item_id);

    char input[SPAGAT_MAX_PROMPT_LEN];
    while (1) {
        printf("> ");
        fflush(stdout);
        if (!fgets(input, sizeof(input), stdin)) break;

        char *nl = strchr(input, '\n');
        if (nl) *nl = '\0';

        if (str_equals_ignore_case(input, "exit") ||
            str_equals_ignore_case(input, "quit")) {
            break;
        }
        if (input[0] == '\0') continue;

        ai_conv_add(item_id, session_id, "user", input, 0, NULL);

        ConvHistory hist;
        ai_conv_get_history(item_id, session_id, &hist);

        char response[SPAGAT_MAX_RESPONSE_LEN];
        response[0] = '\0';

        if (generate_with_tools(provider, input, &hist, response,
                                sizeof(response), item_id,
                                session_id, 5)) {
            printf("\n\n");
            ai_conv_add(item_id, session_id, "assistant",
                        response, 0, NULL);
        } else {
            fprintf(stderr, "Generation failed\n\n");
        }

        ai_conv_free_history(&hist);
    }

    ai_cleanup();
    return 0;
}

int cmd_ai_history(int64_t item_id) {
    ConvHistory hist;
    char session_buf[SPAGAT_MAX_SESSION_ID_LEN];
    snprintf(session_buf, sizeof(session_buf), "task_%lld",
             (long long)item_id);

    if (!ai_conv_get_history(item_id, session_buf, &hist)) {
        fprintf(stderr, "Failed to load conversation history\n");
        return 1;
    }

    if (hist.count == 0) {
        printf("No conversation history for task %lld.\n",
               (long long)item_id);
    } else {
        printf("Conversation history for task %lld (%d messages):\n\n",
               (long long)item_id, hist.count);
        for (int i = 0; i < hist.count; i++) {
            printf("[%s] %s\n\n", hist.messages[i].role,
                   hist.messages[i].content ?
                   hist.messages[i].content : "");
        }
    }

    ai_conv_free_history(&hist);
    return 0;
}

int cmd_model_list(void) {
    WorkspacePaths wp;
    if (!workspace_get_paths(&wp)) {
        fprintf(stderr, "Workspace not initialized\n");
        return 1;
    }
    printf("Models directory: %s\n", wp.models_dir);
    return 0;
}

int cmd_model_test(void) {
    if (!ai_init()) {
        fprintf(stderr, "Failed to initialize AI provider\n");
        return 1;
    }

    AIProvider *provider = ai_get_provider();
    if (!provider) {
        fprintf(stderr, "No AI provider configured\n");
        ai_cleanup();
        return 1;
    }

    printf("Provider: %s\n",
           provider->get_name ? provider->get_name() : "unknown");
    printf("Available: %s\n",
           (provider->is_available && provider->is_available())
           ? "yes" : "no");

    int result = 0;
    if (provider->is_available && provider->is_available()) {
        char response[SPAGAT_MAX_RESPONSE_LEN];
        response[0] = '\0';
        printf("Testing generation...\n");
        if (provider->generate("Say hello in one sentence.",
                               NULL, response, sizeof(response),
                               NULL, NULL)) {
            printf("Response: %s\n", response);
        } else {
            fprintf(stderr, "Generation test failed\n");
            result = 1;
        }
    }

    ai_cleanup();
    return result;
}
