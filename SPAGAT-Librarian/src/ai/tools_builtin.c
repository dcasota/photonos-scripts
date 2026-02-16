#include "ai.h"
#include "autonomy.h"
#include "execpolicy.h"
#include "linux_sandbox.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <errno.h>

#define SHELL_OUTPUT_MAX  4096
#define SHELL_TRUNC_NOTE  256

/*
 * Built-in (legacy) tool handlers for SPAGAT-Librarian.
 * Split out of tools.c to keep file sizes manageable.
 *
 * These are referenced by tools.c via extern declarations and
 * registered during ai_tools_init_with_autonomy().
 */

/* Active autonomy pointer - owned by tools.c */
extern AutonomyConfig *active_autonomy;

/*
 * read_file: reads a file and returns its contents.
 * Input: file path
 * Output: file contents (truncated if too large)
 */
bool tool_read_file(const char *input, char *output, int output_size) {
    if (!input || !input[0]) {
        str_safe_copy(output, "Error: no file path provided", output_size);
        return false;
    }

    /* Sanitize: reject paths with .. */
    if (strstr(input, "..")) {
        str_safe_copy(output, "Error: path traversal not allowed",
                      output_size);
        return false;
    }

    FILE *fp = fopen(input, "r");
    if (!fp) {
        snprintf(output, output_size, "Error: cannot open '%s': %s",
                 input, strerror(errno));
        return false;
    }

    int pos = 0;
    int ch;
    while ((ch = fgetc(fp)) != EOF && pos < output_size - 2) {
        output[pos++] = (char)ch;
    }
    output[pos] = '\0';

    if (ch != EOF) {
        /* File was truncated */
        str_safe_copy(output + pos - 15, "\n...[truncated]",
                      output_size - pos + 15);
    }

    fclose(fp);
    return true;
}

/*
 * write_file: writes content to a file.
 * Input format: "path\ncontent" (first line is path, rest is content)
 */
bool tool_write_file(const char *input, char *output,
                     int output_size) {
    if (!input || !input[0]) {
        str_safe_copy(output, "Error: no input provided", output_size);
        return false;
    }

    /* Split on first newline */
    const char *newline = strchr(input, '\n');
    if (!newline) {
        str_safe_copy(output, "Error: format is 'path\\ncontent'",
                      output_size);
        return false;
    }

    /* Extract path */
    char path[512];
    size_t plen = (size_t)(newline - input);
    if (plen >= sizeof(path)) plen = sizeof(path) - 1;
    memcpy(path, input, plen);
    path[plen] = '\0';

    /* Sanitize path */
    if (strstr(path, "..")) {
        str_safe_copy(output, "Error: path traversal not allowed",
                      output_size);
        return false;
    }

    const char *content = newline + 1;

    FILE *fp = fopen(path, "w");
    if (!fp) {
        snprintf(output, output_size, "Error: cannot open '%s': %s",
                 path, strerror(errno));
        return false;
    }

    fputs(content, fp);
    fclose(fp);

    snprintf(output, output_size, "Written %zu bytes to %s",
             strlen(content), path);
    return true;
}

/*
 * list_dir: lists directory contents.
 * Input: directory path
 */
bool tool_list_dir(const char *input, char *output, int output_size) {
    if (!input || !input[0]) {
        str_safe_copy(output, "Error: no directory path provided",
                      output_size);
        return false;
    }

    if (strstr(input, "..")) {
        str_safe_copy(output, "Error: path traversal not allowed",
                      output_size);
        return false;
    }

    DIR *dir = opendir(input);
    if (!dir) {
        snprintf(output, output_size, "Error: cannot open '%s': %s",
                 input, strerror(errno));
        return false;
    }

    int pos = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && pos < output_size - 256) {
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0) {
            continue;
        }

        char type_ch = '-';
        char full[1024];
        snprintf(full, sizeof(full), "%s/%s", input, entry->d_name);
        struct stat st;
        if (stat(full, &st) == 0) {
            if (S_ISDIR(st.st_mode)) type_ch = 'd';
            else if (S_ISLNK(st.st_mode)) type_ch = 'l';
        }

        pos += snprintf(output + pos, output_size - pos, "%c %s\n",
                        type_ch, entry->d_name);
    }

    closedir(dir);
    return true;
}

/*
 * shell: executes a shell command in a sandboxed manner.
 * Uses fork()/execlp() - no system().
 * Input: command string
 *
 * Restrictions:
 * - Cannot use rm -rf /
 * - Cannot modify system directories
 * - Timeout after 10 seconds
 */
bool tool_shell(const char *input, char *output, int output_size) {
    if (!input || !input[0]) {
        str_safe_copy(output, "Error: no command provided", output_size);
        return false;
    }

    /* Autonomy shell check */
    if (active_autonomy) {
        ShellDecision sd = autonomy_check_shell(active_autonomy, input);
        if (sd == SHELL_DENY) {
            snprintf(output, output_size,
                     "Error: command not permitted at autonomy level '%s'",
                     autonomy_level_to_string(active_autonomy->level));
            journal_log(JOURNAL_WARN, "SHELL BLOCKED:autonomy cmd=\"%.100s\"",
                        input);
            return false;
        }
    }

    /* Execution policy check */
    PolicyResult pr = execpolicy_evaluate(input);
    if (pr.decision == POLICY_FORBIDDEN) {
        snprintf(output, output_size,
                 "Error: command forbidden by policy: %s", pr.justification);
        journal_log(JOURNAL_WARN, "SHELL BLOCKED:policy cmd=\"%.100s\" reason=%s",
                    input, pr.justification);
        return false;
    }
    if (pr.decision == POLICY_PROMPT) {
        /* For now, log the prompt decision; TUI approval is in cli_ai.c */
        journal_log(JOURNAL_INFO, "SHELL PROMPT cmd=\"%.100s\" reason=%s",
                    input, pr.justification);
    }

    int timeout = 10;
    if (active_autonomy) {
        timeout = active_autonomy->shell_timeout;
        if (active_autonomy->level == AUTONOMY_OBSERVE && timeout > 5)
            timeout = 5;
    }

    int pipefd[2];
    if (pipe(pipefd) == -1) {
        snprintf(output, output_size, "Error: pipe failed: %s",
                 strerror(errno));
        return false;
    }

    pid_t pid = fork();
    if (pid == -1) {
        close(pipefd[0]);
        close(pipefd[1]);
        snprintf(output, output_size, "Error: fork failed: %s",
                 strerror(errno));
        return false;
    }

    if (pid == 0) {
        /* Child process */
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[1]);

        /* Hardening: process limits */
        struct rlimit rl;
        rl.rlim_cur = 32;
        rl.rlim_max = 32;
        setrlimit(RLIMIT_NPROC, &rl);

        /* Timeout */
        alarm(timeout);

        /* Apply OS sandbox if available */
        sandbox_apply_shell_restrictions(NULL);

        execlp("/bin/sh", "sh", "-c", input, (char *)NULL);
        _exit(127);
    }

    /* Parent process */
    close(pipefd[1]);

    /* Read output with size cap.  Reserve space for truncation notice. */
    int pos = 0;
    int cap = output_size - SHELL_TRUNC_NOTE - 1;
    if (cap > SHELL_OUTPUT_MAX) cap = SHELL_OUTPUT_MAX;
    long total_bytes = 0;
    char buf[1024];
    ssize_t nr;
    bool truncated = false;
    while ((nr = read(pipefd[0], buf, sizeof(buf))) > 0) {
        total_bytes += nr;
        if (!truncated) {
            int space = cap - pos;
            int copy = (int)nr < space ? (int)nr : space;
            if (copy > 0) {
                memcpy(output + pos, buf, copy);
                pos += copy;
            }
            if (pos >= cap) truncated = true;
        }
    }
    output[pos] = '\0';
    close(pipefd[0]);

    if (truncated) {
        snprintf(output + pos, SHELL_TRUNC_NOTE,
                 "\n\n[OUTPUT TRUNCATED: showing first %d of %ld bytes. "
                 "Re-run with a filter, e.g. | grep -i error, "
                 "| tail -50, or --level=err,warn]",
                 pos, total_bytes);
    }

    int status = 0;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
        int exit_code = WEXITSTATUS(status);
        int remaining = output_size - pos - 1;
        if (remaining > 32) {
            snprintf(output + pos, remaining, "\n[exit code: %d]",
                     exit_code);
        }
        return false;
    }

    return true;
}
