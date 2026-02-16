#include "agent.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>

static WorkspacePaths cached_paths;
static bool paths_cached = false;

/* Recursively create directories (equivalent to mkdir -p) */
static bool mkdir_recursive(const char *path) {
    char tmp[SPAGAT_PATH_MAX];
    char *p = NULL;
    size_t len;

    str_safe_copy(tmp, path, sizeof(tmp));
    len = strlen(tmp);
    if (len == 0) return false;

    /* Remove trailing slash */
    if (tmp[len - 1] == '/') {
        tmp[len - 1] = '\0';
    }

    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
                fprintf(stderr, "mkdir failed for %s: %s\n", tmp,
                        strerror(errno));
                return false;
            }
            *p = '/';
        }
    }

    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "mkdir failed for %s: %s\n", tmp, strerror(errno));
        return false;
    }

    return true;
}

bool workspace_init(WorkspacePaths *paths) {
    if (!paths) return false;

    memset(paths, 0, sizeof(WorkspacePaths));

    /* Determine base directory.
     * Cap at 900 so derived paths (base + /workspace/sessions = ~28 chars)
     * are guaranteed to fit in SPAGAT_PATH_MAX (1024). */
    char base[900];
    const char *spagat_home = getenv("SPAGAT_HOME");
    if (spagat_home && spagat_home[0]) {
        if (strlen(spagat_home) >= sizeof(base)) {
            fprintf(stderr, "SPAGAT_HOME path too long\n");
            return false;
        }
        str_safe_copy(base, spagat_home, sizeof(base));
    } else {
        const char *home = getenv("HOME");
        if (!home || !home[0]) {
            fprintf(stderr, "HOME environment variable not set\n");
            return false;
        }
        if (strlen(home) + 9 >= sizeof(base)) {
            fprintf(stderr, "HOME path too long\n");
            return false;
        }
        snprintf(base, sizeof(base), "%s/.spagat", home);
    }
    str_safe_copy(paths->base_dir, base, sizeof(paths->base_dir));

    /* Build workspace_dir into a local buffer first, then copy */
    char ws[960];
    snprintf(ws, sizeof(ws), "%s/%s", base, SPAGAT_WORKSPACE_DIR);
    str_safe_copy(paths->workspace_dir, ws, sizeof(paths->workspace_dir));

    snprintf(paths->models_dir, sizeof(paths->models_dir),
             "%s/%s", base, SPAGAT_MODELS_DIR);
    snprintf(paths->config_path, sizeof(paths->config_path),
             "%s/%s", base, SPAGAT_CONFIG_FILE);
    snprintf(paths->sessions_dir, sizeof(paths->sessions_dir),
             "%s/sessions", ws);
    snprintf(paths->memory_dir, sizeof(paths->memory_dir),
             "%s/memory", ws);
    snprintf(paths->state_dir, sizeof(paths->state_dir),
             "%s/state", ws);
    snprintf(paths->cron_dir, sizeof(paths->cron_dir),
             "%s/cron", ws);
    snprintf(paths->skills_dir, sizeof(paths->skills_dir),
             "%s/skills", ws);
    snprintf(paths->logs_dir, sizeof(paths->logs_dir),
             "%s/%s", base, SPAGAT_LOGS_DIR);
    snprintf(paths->credentials_dir, sizeof(paths->credentials_dir),
             "%s/%s", base, SPAGAT_CREDENTIALS_DIR);

    /* Cache for later retrieval */
    memcpy(&cached_paths, paths, sizeof(WorkspacePaths));
    paths_cached = true;

    return true;
}

bool workspace_get_paths(WorkspacePaths *paths) {
    if (!paths) return false;

    if (paths_cached) {
        memcpy(paths, &cached_paths, sizeof(WorkspacePaths));
        return true;
    }

    return workspace_init(paths);
}

bool workspace_ensure_dirs(const WorkspacePaths *paths) {
    if (!paths) return false;

    const char *dirs[] = {
        paths->base_dir,
        paths->workspace_dir,
        paths->models_dir,
        paths->sessions_dir,
        paths->memory_dir,
        paths->state_dir,
        paths->cron_dir,
        paths->skills_dir,
        paths->logs_dir,
        paths->credentials_dir,
    };

    int n = (int)(sizeof(dirs) / sizeof(dirs[0]));

    for (int i = 0; i < n; i++) {
        if (!mkdir_recursive(dirs[i])) {
            fprintf(stderr, "Failed to create directory: %s\n", dirs[i]);
            return false;
        }
    }

    return true;
}

bool workspace_is_initialized(const WorkspacePaths *paths) {
    if (!paths) return false;

    char agent_md[960];
    snprintf(agent_md, sizeof(agent_md), "%.940s/AGENT.md",
             paths->workspace_dir);

    return file_exists(agent_md);
}
