/*
 * subagent.c - Subagent spawn/kill pattern for SPAGAT
 *
 * Allows the main agent to fork background shell tasks, poll their
 * status, capture output, and kill them on demand.
 * Max depth is 1: subagents cannot spawn sub-subagents.
 */

#include "subagent.h"

#ifdef __linux__

#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

static const char *status_str(SubagentStatus s)
{
    switch (s) {
    case SUBAGENT_PENDING:  return "PENDING";
    case SUBAGENT_RUNNING:  return "RUNNING";
    case SUBAGENT_DONE:     return "DONE";
    case SUBAGENT_FAILED:   return "FAILED";
    case SUBAGENT_KILLED:   return "KILLED";
    }
    return "UNKNOWN";
}

static Subagent *find_by_id(SubagentManager *mgr, int64_t id)
{
    for (int i = 0; i < mgr->count; i++) {
        if (mgr->agents[i].id == id)
            return &mgr->agents[i];
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Public API                                                         */
/* ------------------------------------------------------------------ */

void subagent_init(SubagentManager *mgr)
{
    if (!mgr) return;
    memset(mgr, 0, sizeof(*mgr));
    mgr->next_id = 1;
}

int64_t subagent_spawn(SubagentManager *mgr, const char *name,
                       const char *command)
{
    if (!mgr || !name || !command)
        return -1;

    if (mgr->count >= SUBAGENT_MAX) {
        fprintf(stderr, "subagent: max agents reached (%d)\n",
                SUBAGENT_MAX);
        return -1;
    }

    /* Prevent recursive spawning via environment marker */
    if (getenv("SPAGAT_SUBAGENT")) {
        fprintf(stderr, "subagent: sub-subagent spawning is not allowed\n");
        return -1;
    }

    int64_t id = mgr->next_id++;
    Subagent *ag = &mgr->agents[mgr->count];
    memset(ag, 0, sizeof(*ag));

    ag->id = id;
    snprintf(ag->name, SUBAGENT_NAME_LEN, "%s", name);
    snprintf(ag->command, SUBAGENT_CMD_LEN, "%s", command);

    /* Build temp output path */
    snprintf(ag->output_path, sizeof(ag->output_path),
             "/tmp/spagat-subagent-%ld.out", (long)id);

    /* Open output file (truncate/create) */
    int out_fd = open(ag->output_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (out_fd < 0) {
        fprintf(stderr, "subagent: cannot create output file %s: %s\n",
                ag->output_path, strerror(errno));
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "subagent: fork failed: %s\n", strerror(errno));
        close(out_fd);
        unlink(ag->output_path);
        return -1;
    }

    if (pid == 0) {
        /* ---- child ---- */

        /* Redirect stdout and stderr to temp file */
        dup2(out_fd, STDOUT_FILENO);
        dup2(out_fd, STDERR_FILENO);
        close(out_fd);

        /* Mark as subagent so children cannot recurse */
        setenv("SPAGAT_SUBAGENT", "1", 1);

        /* Auto-kill after 5 minutes */
        alarm(300);

        execl("/bin/sh", "sh", "-c", command, (char *)NULL);
        _exit(127);
    }

    /* ---- parent ---- */
    close(out_fd);

    ag->pid = pid;
    ag->status = SUBAGENT_RUNNING;
    ag->started_at = time(NULL);
    ag->output_fd = -1; /* not used; output goes to file */
    mgr->count++;

    return id;
}

void subagent_poll(SubagentManager *mgr)
{
    if (!mgr) return;

    for (int i = 0; i < mgr->count; i++) {
        Subagent *ag = &mgr->agents[i];
        if (ag->status != SUBAGENT_RUNNING)
            continue;

        int wstatus = 0;
        pid_t ret = waitpid(ag->pid, &wstatus, WNOHANG);
        if (ret == 0) {
            /* still running */
            continue;
        }
        if (ret < 0) {
            /* waitpid error – mark failed */
            ag->status = SUBAGENT_FAILED;
            ag->exit_code = -1;
            ag->finished_at = time(NULL);
            continue;
        }

        /* Process exited */
        ag->finished_at = time(NULL);
        if (WIFEXITED(wstatus)) {
            ag->exit_code = WEXITSTATUS(wstatus);
            ag->status = (ag->exit_code == 0) ? SUBAGENT_DONE
                                               : SUBAGENT_FAILED;
        } else if (WIFSIGNALED(wstatus)) {
            ag->exit_code = -WTERMSIG(wstatus);
            ag->status = SUBAGENT_FAILED;
        } else {
            ag->exit_code = -1;
            ag->status = SUBAGENT_FAILED;
        }
    }
}

bool subagent_kill(SubagentManager *mgr, int64_t id)
{
    if (!mgr) return false;

    Subagent *ag = find_by_id(mgr, id);
    if (!ag) return false;
    if (ag->status != SUBAGENT_RUNNING) return false;

    /* Graceful termination attempt */
    kill(ag->pid, SIGTERM);
    usleep(100000); /* 100 ms */

    /* Check if still alive */
    int wstatus = 0;
    pid_t ret = waitpid(ag->pid, &wstatus, WNOHANG);
    if (ret == 0) {
        /* Still running – force kill */
        kill(ag->pid, SIGKILL);
        waitpid(ag->pid, &wstatus, 0);
    }

    ag->status = SUBAGENT_KILLED;
    ag->finished_at = time(NULL);
    if (WIFEXITED(wstatus))
        ag->exit_code = WEXITSTATUS(wstatus);
    else
        ag->exit_code = -1;

    return true;
}

void subagent_kill_all(SubagentManager *mgr)
{
    if (!mgr) return;
    for (int i = 0; i < mgr->count; i++) {
        if (mgr->agents[i].status == SUBAGENT_RUNNING)
            subagent_kill(mgr, mgr->agents[i].id);
    }
}

const Subagent *subagent_get(const SubagentManager *mgr, int64_t id)
{
    if (!mgr) return NULL;
    for (int i = 0; i < mgr->count; i++) {
        if (mgr->agents[i].id == id)
            return &mgr->agents[i];
    }
    return NULL;
}

char *subagent_read_output(const Subagent *agent)
{
    if (!agent || agent->output_path[0] == '\0')
        return NULL;

    FILE *fp = fopen(agent->output_path, "r");
    if (!fp)
        return NULL;

    char *buf = malloc(SUBAGENT_OUTPUT_MAX);
    if (!buf) {
        fclose(fp);
        return NULL;
    }

    size_t n = fread(buf, 1, SUBAGENT_OUTPUT_MAX - 1, fp);
    fclose(fp);

    buf[n] = '\0';
    return buf;
}

void subagent_list(const SubagentManager *mgr)
{
    if (!mgr) return;

    if (mgr->count == 0) {
        printf("No subagents.\n");
        return;
    }

    time_t now = time(NULL);

    for (int i = 0; i < mgr->count; i++) {
        const Subagent *ag = &mgr->agents[i];

        if (ag->status == SUBAGENT_RUNNING) {
            long elapsed = (long)(now - ag->started_at);
            printf("[%ld] %-16s %-8s pid=%-8d (running %lds)\n",
                   (long)ag->id, ag->name, status_str(ag->status),
                   (int)ag->pid, elapsed);
        } else {
            long duration = 0;
            if (ag->finished_at > ag->started_at)
                duration = (long)(ag->finished_at - ag->started_at);
            printf("[%ld] %-16s %-8s exit=%-4d  (took %lds)\n",
                   (long)ag->id, ag->name, status_str(ag->status),
                   ag->exit_code, duration);
        }
    }
}

void subagent_cleanup(SubagentManager *mgr)
{
    if (!mgr) return;

    subagent_kill_all(mgr);

    for (int i = 0; i < mgr->count; i++) {
        if (mgr->agents[i].output_path[0] != '\0')
            unlink(mgr->agents[i].output_path);
    }

    memset(mgr->agents, 0, sizeof(mgr->agents));
    mgr->count = 0;
}

#else /* !__linux__ */

/* ------------------------------------------------------------------ */
/* Stubs for non-Linux platforms                                      */
/* ------------------------------------------------------------------ */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void subagent_init(SubagentManager *mgr)
{
    if (!mgr) return;
    memset(mgr, 0, sizeof(*mgr));
    mgr->next_id = 1;
}

int64_t subagent_spawn(SubagentManager *mgr, const char *name,
                       const char *command)
{
    (void)mgr; (void)name; (void)command;
    fprintf(stderr, "subagent: not supported on this platform\n");
    return -1;
}

void subagent_poll(SubagentManager *mgr)
{
    (void)mgr;
}

bool subagent_kill(SubagentManager *mgr, int64_t id)
{
    (void)mgr; (void)id;
    return false;
}

void subagent_kill_all(SubagentManager *mgr)
{
    (void)mgr;
}

const Subagent *subagent_get(const SubagentManager *mgr, int64_t id)
{
    (void)mgr; (void)id;
    return NULL;
}

char *subagent_read_output(const Subagent *agent)
{
    (void)agent;
    return NULL;
}

void subagent_list(const SubagentManager *mgr)
{
    (void)mgr;
    printf("Subagents not supported on this platform.\n");
}

void subagent_cleanup(SubagentManager *mgr)
{
    if (mgr) {
        memset(mgr->agents, 0, sizeof(mgr->agents));
        mgr->count = 0;
    }
}

#endif /* __linux__ */
