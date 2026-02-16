#include "agent.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

bool sandbox_check_path(const WorkspacePaths *paths, const char *target_path) {
    if (!paths || !target_path) return false;

    /* Resolve the target path to eliminate symlinks and .. */
    char resolved[PATH_MAX];
    if (!realpath(target_path, resolved)) {
        /* Path doesn't exist yet - resolve the parent directory */
        char parent[PATH_MAX];
        str_safe_copy(parent, target_path, sizeof(parent));

        /* Find last slash to get parent directory */
        char *last_slash = strrchr(parent, '/');
        if (!last_slash) return false;

        *last_slash = '\0';

        if (!realpath(parent, resolved)) {
            fprintf(stderr, "Sandbox: cannot resolve path: %s\n",
                    target_path);
            return false;
        }

        /* Re-append the filename */
        size_t rlen = strlen(resolved);
        snprintf(resolved + rlen, sizeof(resolved) - rlen, "/%s",
                 last_slash + 1);
    }

    /* Resolve workspace directory */
    char resolved_workspace[PATH_MAX];
    if (!realpath(paths->workspace_dir, resolved_workspace)) {
        fprintf(stderr, "Sandbox: workspace not resolved: %s\n",
                paths->workspace_dir);
        return false;
    }

    /* Check if resolved path starts with workspace directory */
    size_t ws_len = strlen(resolved_workspace);
    if (strncmp(resolved, resolved_workspace, ws_len) != 0) {
        fprintf(stderr, "Sandbox: path outside workspace: %s\n",
                target_path);
        return false;
    }

    /* Ensure it's actually inside (not just a prefix match) */
    if (resolved[ws_len] != '/' && resolved[ws_len] != '\0') {
        fprintf(stderr, "Sandbox: path outside workspace: %s\n",
                target_path);
        return false;
    }

    return true;
}

bool sandbox_is_enabled(const SpagatConfig *config) {
    if (!config) return true; /* Default to enabled for safety */

    return config->restrict_to_workspace;
}
