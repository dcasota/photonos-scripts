/* git_with_timeout.c — Invoke-GitWithTimeout.
 * Mirrors photonos-package-report.ps1 L 163-231.
 *
 * PS source (verbatim, structurally):
 *
 *   function Invoke-GitWithTimeout {
 *       param(
 *           [string]$Arguments,
 *           [string]$WorkingDirectory = (Get-Location).Path,
 *           [int]$TimeoutSeconds = 14400 # 4 hours
 *       )
 *       try {
 *           $psi = New-Object System.Diagnostics.ProcessStartInfo
 *           $psi.FileName = "git"
 *           $psi.Arguments = $Arguments
 *           $psi.WorkingDirectory = $WorkingDirectory
 *           ...
 *           $process.Start() | Out-Null
 *           $process.BeginOutputReadLine()
 *           $process.BeginErrorReadLine()
 *           $completed = $process.WaitForExit($TimeoutSeconds * 1000)
 *           if (-not $completed) {
 *               try { $process.Kill() } catch {}
 *               Write-Warning "Git command timed out after $TimeoutSeconds seconds: git $Arguments"
 *               throw "Git operation timed out"
 *           }
 *           $process.WaitForExit()  # let async handlers finish
 *           if ($process.ExitCode -ne 0) {
 *               if (-not [string]::IsNullOrWhiteSpace($stderr)) {
 *                   Write-Warning "Git stderr: $stderr"
 *               }
 *               throw "Git command failed with exit code $($process.ExitCode): $stderr"
 *           }
 *           return $stdout
 *       }
 *       catch {
 *           Write-Warning "Git command failed: git $Arguments - Error: $_"
 *           throw
 *       }
 *   }
 *
 * C equivalent: posix_spawn the `git` binary with redirected stdout/stderr
 * pipes, drain them in a polling loop, enforce wall-clock timeout via
 * clock_gettime, kill+reap on timeout. Mirrors PS structure 1:1.
 */
#include "photonos_package_report.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <poll.h>
#include <spawn.h>

extern char **environ;

/* Tokenise space-separated git args into argv[]. PS just hands the whole
 * argument string to ProcessStartInfo.Arguments which uses Win32 quoting
 * rules. On Linux, posix_spawn needs an argv array. We split on unquoted
 * whitespace and unwrap matched double-quotes, mirroring the simplest
 * subset the PS script uses in practice.
 */
static char **split_git_args(const char *arguments, int *out_argc)
{
    /* "git" + tokens + NULL */
    size_t cap = 16;
    char **argv = calloc(cap, sizeof(char *));
    if (!argv) return NULL;
    int argc = 0;
    argv[argc++] = strdup("git");

    const char *p = arguments ? arguments : "";
    while (*p) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;

        char buf[8192];
        size_t bi = 0;
        int in_quote = 0;
        while (*p && (in_quote || (*p != ' ' && *p != '\t'))) {
            if (*p == '"') { in_quote = !in_quote; p++; continue; }
            if (bi + 1 < sizeof buf) buf[bi++] = *p;
            p++;
        }
        buf[bi] = '\0';
        if (argc + 1 >= (int)cap) {
            cap *= 2;
            char **n = realloc(argv, cap * sizeof(char *));
            if (!n) { /* leak in failure path is acceptable here */ return NULL; }
            argv = n;
        }
        argv[argc++] = strdup(buf);
    }
    argv[argc] = NULL;
    *out_argc = argc;
    return argv;
}

static void free_argv(char **argv)
{
    if (!argv) return;
    for (int i = 0; argv[i]; i++) free(argv[i]);
    free(argv);
}

/* Append n bytes of `src` to a growable buffer `*dst` (size `*len`, cap `*cap`). */
static int append_buf(char **dst, size_t *len, size_t *cap, const char *src, size_t n)
{
    if (*len + n + 1 > *cap) {
        size_t nc = (*cap ? *cap * 2 : 4096);
        while (nc < *len + n + 1) nc *= 2;
        char *nb = realloc(*dst, nc);
        if (!nb) return -1;
        *dst = nb;
        *cap = nc;
    }
    memcpy(*dst + *len, src, n);
    *len += n;
    (*dst)[*len] = '\0';
    return 0;
}

int invoke_git_with_timeout(const char *arguments,
                            const char *working_directory,
                            int timeout_seconds,
                            char **out_stdout)
{
    /* PS default: 14400 seconds (4 hours), L 167 */
    if (timeout_seconds <= 0) timeout_seconds = 14400;
    if (out_stdout) *out_stdout = NULL;

    /* Set up stdout / stderr pipes */
    int outpipe[2] = {-1, -1};
    int errpipe[2] = {-1, -1};
    if (pipe(outpipe) != 0 || pipe(errpipe) != 0) {
        fprintf(stderr, "WARNING: Git command failed: git %s - Error: pipe(): %s\n",
                arguments ? arguments : "", strerror(errno));
        if (outpipe[0] >= 0) { close(outpipe[0]); close(outpipe[1]); }
        if (errpipe[0] >= 0) { close(errpipe[0]); close(errpipe[1]); }
        return -1;
    }

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addclose(&fa, outpipe[0]);
    posix_spawn_file_actions_addclose(&fa, errpipe[0]);
    posix_spawn_file_actions_adddup2 (&fa, outpipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2 (&fa, errpipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fa, outpipe[1]);
    posix_spawn_file_actions_addclose(&fa, errpipe[1]);

    /* posix_spawn lacks WorkingDirectory portably; chdir in the parent
     * around the spawn under a critical section would race with other
     * threads. Use a fork() + chdir() + execvp() in the child instead. */
    int gargc = 0;
    char **gargv = split_git_args(arguments, &gargc);
    if (!gargv) {
        fprintf(stderr, "WARNING: Git command failed: git %s - Error: argv build failed\n",
                arguments ? arguments : "");
        close(outpipe[0]); close(outpipe[1]); close(errpipe[0]); close(errpipe[1]);
        posix_spawn_file_actions_destroy(&fa);
        return -1;
    }

    posix_spawn_file_actions_destroy(&fa);  /* unused below; we fork manually for chdir() */

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "WARNING: Git command failed: git %s - Error: fork(): %s\n",
                arguments, strerror(errno));
        free_argv(gargv);
        close(outpipe[0]); close(outpipe[1]); close(errpipe[0]); close(errpipe[1]);
        return -1;
    }
    if (pid == 0) {
        /* Child */
        close(outpipe[0]);
        close(errpipe[0]);
        dup2(outpipe[1], STDOUT_FILENO);
        dup2(errpipe[1], STDERR_FILENO);
        close(outpipe[1]);
        close(errpipe[1]);
        if (working_directory && *working_directory) {
            if (chdir(working_directory) != 0) {
                fprintf(stderr, "chdir(%s): %s\n", working_directory, strerror(errno));
                _exit(127);
            }
        }
        execvp("git", gargv);
        fprintf(stderr, "execvp(git): %s\n", strerror(errno));
        _exit(127);
    }

    /* Parent: close write ends, drain read ends with timeout. */
    close(outpipe[1]);
    close(errpipe[1]);

    /* O_NONBLOCK so we can poll with a deadline. */
    fcntl(outpipe[0], F_SETFL, fcntl(outpipe[0], F_GETFL, 0) | O_NONBLOCK);
    fcntl(errpipe[0], F_SETFL, fcntl(errpipe[0], F_GETFL, 0) | O_NONBLOCK);

    char *stdout_buf = NULL; size_t out_len = 0, out_cap = 0;
    char *stderr_buf = NULL; size_t err_len = 0, err_cap = 0;

    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);

    int timed_out = 0;
    int reaped = 0;
    int wstatus = 0;
    int exit_code = -1;

    struct pollfd pfd[2];
    while (!reaped) {
        pfd[0].fd = outpipe[0]; pfd[0].events = POLLIN;
        pfd[1].fd = errpipe[0]; pfd[1].events = POLLIN;

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long elapsed = (long)(now.tv_sec - start.tv_sec);
        if (elapsed >= timeout_seconds) {
            timed_out = 1;
            kill(pid, SIGKILL);
            /* drain any remaining output so child exits cleanly */
        }

        int pr = poll(pfd, 2, 200);  /* 200ms tick */
        if (pr > 0) {
            char chunk[4096];
            for (int i = 0; i < 2; i++) {
                if (pfd[i].revents & (POLLIN | POLLHUP)) {
                    ssize_t n = read(pfd[i].fd, chunk, sizeof chunk);
                    if (n > 0) {
                        if (i == 0) append_buf(&stdout_buf, &out_len, &out_cap, chunk, n);
                        else        append_buf(&stderr_buf, &err_len, &err_cap, chunk, n);
                    }
                }
            }
        }

        int wr = waitpid(pid, &wstatus, WNOHANG);
        if (wr == pid) {
            reaped = 1;
            if (WIFEXITED(wstatus)) exit_code = WEXITSTATUS(wstatus);
            else                    exit_code = 128 + (WIFSIGNALED(wstatus) ? WTERMSIG(wstatus) : 0);
        } else if (wr < 0 && errno != EINTR) {
            break;
        }

        if (timed_out && reaped) break;
    }

    /* Final drain after reap */
    char chunk[4096];
    ssize_t n;
    while ((n = read(outpipe[0], chunk, sizeof chunk)) > 0)
        append_buf(&stdout_buf, &out_len, &out_cap, chunk, n);
    while ((n = read(errpipe[0], chunk, sizeof chunk)) > 0)
        append_buf(&stderr_buf, &err_len, &err_cap, chunk, n);
    close(outpipe[0]);
    close(errpipe[0]);
    free_argv(gargv);

    if (timed_out) {
        fprintf(stderr, "WARNING: Git command timed out after %d seconds: git %s\n",
                timeout_seconds, arguments ? arguments : "");
        free(stdout_buf);
        free(stderr_buf);
        return -2;
    }

    if (exit_code != 0) {
        /* PS warns when stderr non-empty/non-whitespace. */
        int has_err = 0;
        for (size_t i = 0; i < err_len; i++) {
            if (stderr_buf[i] != ' ' && stderr_buf[i] != '\t' &&
                stderr_buf[i] != '\n' && stderr_buf[i] != '\r') { has_err = 1; break; }
        }
        if (has_err) {
            fprintf(stderr, "WARNING: Git stderr: %s\n", stderr_buf);
        }
        fprintf(stderr, "WARNING: Git command failed: git %s - Error: Git command failed with exit code %d: %s\n",
                arguments ? arguments : "", exit_code, stderr_buf ? stderr_buf : "");
        free(stdout_buf);
        free(stderr_buf);
        return exit_code;
    }

    free(stderr_buf);
    if (out_stdout) *out_stdout = stdout_buf;
    else            free(stdout_buf);
    return 0;
}
