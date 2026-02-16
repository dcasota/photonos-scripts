/*
 * git_tools.c - Git integration as AI tools.
 *
 * Uses fork/exec to call the git CLI (no libgit2 dependency).
 * Each tool captures stdout+stderr with a 10-second timeout.
 */

#ifdef __linux__

#include "git_tools.h"
#include "ai.h"
#include "../util/util.h"
#include <sys/wait.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>

/* Maximum arguments for the git command line */
#define GIT_MAX_ARGS 32

/*
 * Run a git command via fork/exec, capture output.
 * argv:       NULL-terminated argument array starting with "git".
 * cwd:        working directory (NULL = inherit).
 * output:     buffer for captured stdout+stderr.
 * output_size: size of output buffer.
 * Returns true on exit code 0.
 */
static bool git_exec(const char **argv, const char *cwd,
                     char *output, int output_size) {
    int pipefd[2];
    if (pipe(pipefd) == -1) {
        snprintf(output, output_size, "Error: pipe: %s", strerror(errno));
        return false;
    }

    pid_t pid = fork();
    if (pid == -1) {
        close(pipefd[0]);
        close(pipefd[1]);
        snprintf(output, output_size, "Error: fork: %s", strerror(errno));
        return false;
    }

    if (pid == 0) {
        /* Child */
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[1]);

        if (cwd && chdir(cwd) != 0)
            _exit(127);

        alarm(10);

        execvp("git", (char *const *)argv);
        _exit(127);
    }

    /* Parent */
    close(pipefd[1]);

    int pos = 0;
    char buf[1024];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) {
        int space = output_size - pos - 1;
        int copy = (int)n < space ? (int)n : space;
        if (copy > 0) {
            memcpy(output + pos, buf, copy);
            pos += copy;
        }
    }
    output[pos] = '\0';
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
        int rc = WEXITSTATUS(status);
        int remaining = output_size - pos - 1;
        if (remaining > 32)
            snprintf(output + pos, remaining, "\n[exit code: %d]", rc);
        return false;
    }

    return true;
}

/* Helper: skip leading/trailing whitespace in-place for parsing */
static const char *skip_ws(const char *s) {
    if (!s) return "";
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    return s;
}

/* ---- Tool handlers ---- */

static bool tool_git_status(const char *input, char *output,
                            int output_size) {
    const char *cwd = NULL;
    if (input && *input) {
        const char *p = skip_ws(input);
        if (*p) cwd = p;
    }

    const char *argv[] = {"git", "status", "--porcelain", NULL};
    return git_exec(argv, cwd, output, output_size);
}

static bool tool_git_diff(const char *input, char *output,
                          int output_size) {
    const char *argv[GIT_MAX_ARGS];
    int argc = 0;
    argv[argc++] = "git";
    argv[argc++] = "diff";

    if (input && strstr(input, "staged"))
        argv[argc++] = "--staged";

    /* Append any remaining path/flags (simple single-token) */
    if (input && *input) {
        const char *p = skip_ws(input);
        if (*p && !strstr(p, "staged"))
            argv[argc++] = p;
    }

    argv[argc] = NULL;
    return git_exec(argv, NULL, output, output_size);
}

static bool tool_git_log(const char *input, char *output,
                         int output_size) {
    const char *argv[GIT_MAX_ARGS];
    int argc = 0;
    argv[argc++] = "git";
    argv[argc++] = "log";
    argv[argc++] = "--oneline";

    bool has_n = false;
    bool has_all = false;

    if (input && *input) {
        const char *p = skip_ws(input);
        if (strstr(p, "--all"))   has_all = true;
        if (strstr(p, "-n"))      has_n = true;

        /* Parse -n <number> */
        if (has_n) {
            const char *npos = strstr(p, "-n");
            if (npos) {
                argv[argc++] = "-n";
                const char *num = skip_ws(npos + 2);
                if (*num >= '0' && *num <= '9') {
                    static char nbuf[16];
                    str_safe_copy(nbuf, num, sizeof(nbuf));
                    /* Truncate at first space */
                    char *sp = strchr(nbuf, ' ');
                    if (sp) *sp = '\0';
                    argv[argc++] = nbuf;
                }
            }
        }

        if (has_all) argv[argc++] = "--all";
    }

    if (!has_n) {
        argv[argc++] = "-20";
    }

    argv[argc] = NULL;
    return git_exec(argv, NULL, output, output_size);
}

static bool tool_git_branch(const char *input, char *output,
                            int output_size) {
    (void)input;
    const char *argv[] = {"git", "branch", "-a", NULL};
    return git_exec(argv, NULL, output, output_size);
}

static bool tool_git_commit(const char *input, char *output,
                            int output_size) {
    if (!input || !*input) {
        str_safe_copy(output, "Error: commit message required", output_size);
        return false;
    }

    const char *msg = skip_ws(input);
    if (!*msg) {
        str_safe_copy(output, "Error: empty commit message", output_size);
        return false;
    }

    /* Return confirmation prompt instead of executing directly */
    snprintf(output, output_size, "CONFIRM: git commit -m \"%s\"", msg);
    return true;
}

static bool tool_git_add(const char *input, char *output,
                         int output_size) {
    if (!input || !*input) {
        str_safe_copy(output, "Error: file paths required", output_size);
        return false;
    }

    const char *argv[GIT_MAX_ARGS];
    int argc = 0;
    argv[argc++] = "git";
    argv[argc++] = "add";

    /* Parse space-separated file paths */
    static char pathbuf[4096];
    str_safe_copy(pathbuf, input, sizeof(pathbuf));
    char *tok = strtok(pathbuf, " \t\n");
    while (tok && argc < GIT_MAX_ARGS - 1) {
        argv[argc++] = tok;
        tok = strtok(NULL, " \t\n");
    }

    argv[argc] = NULL;
    return git_exec(argv, NULL, output, output_size);
}

static bool tool_git_show(const char *input, char *output,
                          int output_size) {
    const char *ref = "HEAD";
    if (input && *input) {
        const char *p = skip_ws(input);
        if (*p) ref = p;
    }

    const char *argv[] = {"git", "show", ref, NULL};
    return git_exec(argv, NULL, output, output_size);
}

/* ---- Registration ---- */

void git_tools_init(void) {
    ai_tool_register("git_status",
        "Show working tree status. Input: optional directory path.",
        tool_git_status);

    ai_tool_register("git_diff",
        "Show diff of changes. Input: optional flags/path "
        "(include \"staged\" for --staged).",
        tool_git_diff);

    ai_tool_register("git_log",
        "Show recent commits. Input: optional flags like \"-n 5\" or \"--all\".",
        tool_git_log);

    ai_tool_register("git_branch",
        "List all branches (local + remote). Input: empty.",
        tool_git_branch);

    ai_tool_register("git_commit",
        "Commit staged changes. Input: commit message. "
        "Returns CONFIRM: prompt for approval.",
        tool_git_commit);

    ai_tool_register("git_add",
        "Stage files. Input: file paths (space-separated) or \".\" for all.",
        tool_git_add);

    ai_tool_register("git_show",
        "Show commit details. Input: commit ref or HEAD.",
        tool_git_show);
}

#else /* !__linux__ */

#include "git_tools.h"

void git_tools_init(void) {
    /* Git tools require fork/exec - not available on non-Linux */
}

#endif /* __linux__ */
