#include "../ai/ai.h"
#include "../agent/subagent.h"
#include "../util/util.h"
#include "cli.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- Subagent commands (#135) ---- */

static SubagentManager subagent_mgr;
static bool subagent_mgr_ready = false;

static void ensure_subagent_mgr(void) {
    if (!subagent_mgr_ready) {
        subagent_init(&subagent_mgr);
        subagent_mgr_ready = true;
    }
}

int cmd_subagent_spawn(const char *name, const char *command) {
    ensure_subagent_mgr();
    int64_t id = subagent_spawn(&subagent_mgr, name, command);
    if (id >= 0) {
        printf("Subagent spawned: id=%lld name='%s'\n", (long long)id, name);
        return 0;
    }
    fprintf(stderr, "Failed to spawn subagent\n");
    return 1;
}

int cmd_subagent_list(void) {
    ensure_subagent_mgr();
    subagent_poll(&subagent_mgr);
    subagent_list(&subagent_mgr);
    return 0;
}

int cmd_subagent_kill(int64_t id) {
    ensure_subagent_mgr();
    if (subagent_kill(&subagent_mgr, id)) {
        printf("Subagent %lld killed.\n", (long long)id);
        return 0;
    }
    fprintf(stderr, "Failed to kill subagent %lld\n", (long long)id);
    return 1;
}

int cmd_subagent_output(int64_t id) {
    ensure_subagent_mgr();
    subagent_poll(&subagent_mgr);
    const Subagent *sa = subagent_get(&subagent_mgr, id);
    if (!sa) {
        fprintf(stderr, "Subagent %lld not found\n", (long long)id);
        return 1;
    }
    if (sa->status == SUBAGENT_RUNNING) {
        printf("Subagent %lld is still running.\n", (long long)id);
        return 0;
    }
    char *output = subagent_read_output(sa);
    if (output) {
        printf("%s", output);
        free(output);
    } else {
        printf("(no output)\n");
    }
    return 0;
}
