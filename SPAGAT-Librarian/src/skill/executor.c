#include "skill.h"
#include "../ai/ai.h"
#include "../agent/agent.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>

#define STEP_MAX_LEN 1024
#define STEP_MAX_STEPS 64

typedef enum {
    STEP_SHELL,
    STEP_PROMPT,
    STEP_FILE_READ,
    STEP_FILE_WRITE,
    STEP_UNKNOWN
} StepType;

typedef struct {
    StepType type;
    char command[STEP_MAX_LEN];
} SkillStep;

/* Parse step type from prefix */
static StepType parse_step_type(const char *line) {
    if (str_starts_with(line, "shell:")) return STEP_SHELL;
    if (str_starts_with(line, "prompt:")) return STEP_PROMPT;
    if (str_starts_with(line, "file:")) return STEP_FILE_READ;
    return STEP_UNKNOWN;
}

/* Get command part after the prefix */
static const char *step_get_command(const char *line) {
    const char *colon = strchr(line, ':');
    if (!colon) return line;

    const char *cmd = colon + 1;
    while (*cmd == ' ') cmd++;
    return cmd;
}

/* Execute a shell command using fork/execlp (no system()) */
static bool exec_shell_step(const char *command,
                            const SkillExecContext *ctx) {
    if (!command || !command[0]) return false;

    printf("  [shell] %s\n", command);

    /* Verify sandbox if enabled */
    if (ctx && ctx->sandbox_enabled) {
        /* Shell commands are restricted when sandbox is on */
        fprintf(stderr, "  Warning: shell commands may be restricted by "
                        "sandbox policy\n");
    }

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "  Failed to fork: %s\n", strerror(errno));
        return false;
    }

    if (pid == 0) {
        /* Child process */
        if (ctx && ctx->workspace_dir[0]) {
            if (chdir(ctx->workspace_dir) != 0) {
                _exit(1);
            }
        }
        execlp("/bin/sh", "sh", "-c", command, (char *)NULL);
        _exit(127); /* execlp failed */
    }

    /* Parent: wait for child */
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        fprintf(stderr, "  waitpid failed: %s\n", strerror(errno));
        return false;
    }

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        return true;
    }

    fprintf(stderr, "  Command exited with status %d\n",
            WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    return false;
}

/* Send a prompt to the AI provider */
static bool exec_prompt_step(const char *prompt) {
    if (!prompt || !prompt[0]) return false;

    printf("  [prompt] %s\n", prompt);

    AIProvider *provider = ai_get_provider();
    if (!provider || !provider->is_available || !provider->is_available()) {
        fprintf(stderr, "  AI provider not available\n");
        return false;
    }

    char response[SPAGAT_MAX_RESPONSE_LEN];
    response[0] = '\0';

    if (!provider->generate(prompt, NULL, response, sizeof(response),
                            NULL, NULL)) {
        fprintf(stderr, "  AI generation failed\n");
        return false;
    }

    printf("  [response] %s\n", response);
    return true;
}

/* Read a file and print its contents */
static bool exec_file_read_step(const char *filepath,
                                const SkillExecContext *ctx) {
    if (!filepath || !filepath[0]) return false;

    printf("  [file:read] %s\n", filepath);

    /* Build full path if workspace is set and path is relative */
    char full_path[SPAGAT_PATH_MAX];
    if (ctx && ctx->workspace_dir[0] && filepath[0] != '/') {
        snprintf(full_path, sizeof(full_path), "%.900s/%.100s",
                 ctx->workspace_dir, filepath);
    } else {
        str_safe_copy(full_path, filepath, sizeof(full_path));
    }

    /* Sandbox check */
    if (ctx && ctx->sandbox_enabled) {
        WorkspacePaths paths;
        if (workspace_get_paths(&paths)) {
            if (!sandbox_check_path(&paths, full_path)) {
                fprintf(stderr, "  Sandbox: access denied to %s\n",
                        full_path);
                return false;
            }
        }
    }

    FILE *fp = fopen(full_path, "r");
    if (!fp) {
        fprintf(stderr, "  Cannot read file: %s: %s\n",
                full_path, strerror(errno));
        return false;
    }

    char buf[4096];
    size_t nread;
    while ((nread = fread(buf, 1, sizeof(buf) - 1, fp)) > 0) {
        buf[nread] = '\0';
        printf("%s", buf);
    }

    fclose(fp);
    return true;
}

/* Parse steps from skill content (after ## Steps section) */
static int parse_steps(const char *content, SkillStep *steps, int max_steps) {
    if (!content || !steps) return 0;

    int count = 0;

    /* Find "## Steps" section */
    const char *section = strstr(content, "## Steps");
    if (!section) {
        section = strstr(content, "## steps");
    }
    if (!section) return 0;

    /* Move past the header line */
    const char *p = strchr(section, '\n');
    if (!p) return 0;
    p++;

    /* Parse numbered steps: "1. shell: command" */
    while (*p && count < max_steps) {
        /* Skip whitespace */
        while (*p == ' ' || *p == '\t') p++;

        /* Skip blank lines */
        if (*p == '\n' || *p == '\r') {
            p++;
            continue;
        }

        /* Stop at next section header */
        if (str_starts_with(p, "## ") || str_starts_with(p, "# ")) {
            break;
        }

        /* Skip the number prefix "1. " or "- " */
        if ((*p >= '0' && *p <= '9') || *p == '-') {
            while (*p && *p != '.' && *p != ' ' && *p != '\n') p++;
            if (*p == '.') p++;
            while (*p == ' ') p++;
        }

        /* Extract line */
        const char *eol = strchr(p, '\n');
        if (!eol) eol = p + strlen(p);

        int line_len = (int)(eol - p);
        if (line_len > 0 && line_len < STEP_MAX_LEN) {
            char line[STEP_MAX_LEN];
            memcpy(line, p, line_len);
            line[line_len] = '\0';

            /* Trim trailing whitespace */
            char *end = line + strlen(line) - 1;
            while (end >= line && (*end == '\r' || *end == ' ' ||
                   *end == '\t')) {
                *end = '\0';
                end--;
            }

            if (line[0]) {
                steps[count].type = parse_step_type(line);
                str_safe_copy(steps[count].command,
                              step_get_command(line),
                              sizeof(steps[count].command));
                count++;
            }
        }

        p = (*eol) ? eol + 1 : eol;
    }

    return count;
}

bool skill_execute(const Skill *skill, const SkillExecContext *ctx) {
    if (!skill || !skill->loaded) {
        fprintf(stderr, "Skill not loaded\n");
        return false;
    }

    printf("Executing skill: %s\n", skill->name);
    if (skill->description[0]) {
        printf("  %s\n\n", skill->description);
    }

    /* Parse steps */
    SkillStep steps[STEP_MAX_STEPS];
    int step_count = parse_steps(skill->content, steps, STEP_MAX_STEPS);

    if (step_count == 0) {
        printf("  No executable steps found.\n");
        return true;
    }

    printf("  Found %d step(s)\n\n", step_count);

    bool all_ok = true;
    for (int i = 0; i < step_count; i++) {
        printf("  Step %d/%d:\n", i + 1, step_count);

        bool ok = false;
        switch (steps[i].type) {
        case STEP_SHELL:
            ok = exec_shell_step(steps[i].command, ctx);
            break;
        case STEP_PROMPT:
            ok = exec_prompt_step(steps[i].command);
            break;
        case STEP_FILE_READ:
            ok = exec_file_read_step(steps[i].command, ctx);
            break;
        case STEP_FILE_WRITE:
        case STEP_UNKNOWN:
            printf("  [skip] Unknown step type\n");
            ok = true; /* Don't fail on unknown steps */
            break;
        }

        if (!ok) {
            fprintf(stderr, "  Step %d failed\n", i + 1);
            all_ok = false;
            /* Continue with remaining steps */
        }
        printf("\n");
    }

    printf("Skill '%s' %s.\n", skill->name,
           all_ok ? "completed successfully" : "completed with errors");

    return all_ok;
}
