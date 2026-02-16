#ifndef SUBAGENT_H
#define SUBAGENT_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

#define SUBAGENT_MAX 8
#define SUBAGENT_NAME_LEN 64
#define SUBAGENT_CMD_LEN 1024
#define SUBAGENT_OUTPUT_MAX 32768

typedef enum {
    SUBAGENT_PENDING  = 0,
    SUBAGENT_RUNNING  = 1,
    SUBAGENT_DONE     = 2,
    SUBAGENT_FAILED   = 3,
    SUBAGENT_KILLED   = 4
} SubagentStatus;

typedef struct {
    int64_t id;
    char name[SUBAGENT_NAME_LEN];
    char command[SUBAGENT_CMD_LEN];
    pid_t pid;
    SubagentStatus status;
    int exit_code;
    time_t started_at;
    time_t finished_at;
    int output_fd;         /* read end of pipe for output capture */
    char output_path[256]; /* temp file for captured output */
} Subagent;

typedef struct {
    Subagent agents[SUBAGENT_MAX];
    int count;
    int64_t next_id;
} SubagentManager;

/* Initialize subagent manager */
void subagent_init(SubagentManager *mgr);

/* Spawn a background shell task. Returns agent ID or -1 on error.
   The command is run via fork/exec with output redirected to a temp file.
   Max depth is 1 (subagents cannot spawn sub-subagents). */
int64_t subagent_spawn(SubagentManager *mgr, const char *name,
                       const char *command);

/* Check status of all running subagents (non-blocking waitpid) */
void subagent_poll(SubagentManager *mgr);

/* Kill a specific subagent by ID */
bool subagent_kill(SubagentManager *mgr, int64_t id);

/* Kill all running subagents */
void subagent_kill_all(SubagentManager *mgr);

/* Get a subagent by ID (returns NULL if not found) */
const Subagent *subagent_get(const SubagentManager *mgr, int64_t id);

/* Read captured output from a completed subagent.
   Caller must free() the returned string. Returns NULL on error. */
char *subagent_read_output(const Subagent *agent);

/* Print status of all subagents */
void subagent_list(const SubagentManager *mgr);

/* Cleanup: kill all and remove temp files */
void subagent_cleanup(SubagentManager *mgr);

#endif
