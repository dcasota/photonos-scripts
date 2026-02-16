#include "agent.h"
#include "../ai/sysaware.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bool heartbeat_load(const char *heartbeat_path, char *content,
                    int content_size) {
    if (!heartbeat_path || !content || content_size <= 0) return false;

    content[0] = '\0';

    if (!file_exists(heartbeat_path)) {
        return false;
    }

    FILE *fp = fopen(heartbeat_path, "r");
    if (!fp) {
        fprintf(stderr, "Cannot open heartbeat file: %s\n", heartbeat_path);
        return false;
    }

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    if (size <= 0) {
        fclose(fp);
        return false;
    }

    /* Clamp to buffer size */
    long read_size = size;
    if (read_size >= (long)content_size) {
        read_size = (long)content_size - 1;
    }

    size_t bytes_read = fread(content, 1, (size_t)read_size, fp);
    fclose(fp);

    content[bytes_read] = '\0';
    return bytes_read > 0;
}

bool heartbeat_process(const char *content) {
    if (!content || !content[0]) return false;

    int task_count = 0;
    const char *line = content;

    while (line && *line) {
        /* Find end of current line */
        const char *eol = strchr(line, '\n');
        size_t line_len = eol ? (size_t)(eol - line) : strlen(line);

        /* Skip empty lines and comments */
        if (line_len > 0) {
            /* Trim leading whitespace */
            const char *trimmed = line;
            size_t trimmed_len = line_len;
            while (trimmed_len > 0 &&
                   (*trimmed == ' ' || *trimmed == '\t')) {
                trimmed++;
                trimmed_len--;
            }

            /* Check for task lines (starting with "- ") */
            if (trimmed_len >= 2 && trimmed[0] == '-' && trimmed[1] == ' ') {
                /* Skip comment lines (starting with "# -") */
                const char *orig_trimmed = line;
                while (orig_trimmed < trimmed &&
                       (*orig_trimmed == ' ' || *orig_trimmed == '\t')) {
                    orig_trimmed++;
                }

                /* Not inside a comment block */
                if (trimmed[0] == '-') {
                    char task[SPAGAT_MAX_DESC_LEN];
                    size_t task_len = trimmed_len - 2;
                    if (task_len >= sizeof(task)) {
                        task_len = sizeof(task) - 1;
                    }
                    memcpy(task, trimmed + 2, task_len);
                    task[task_len] = '\0';

                    /* Remove trailing whitespace */
                    while (task_len > 0 &&
                           (task[task_len - 1] == ' ' ||
                            task[task_len - 1] == '\t' ||
                            task[task_len - 1] == '\r')) {
                        task_len--;
                        task[task_len] = '\0';
                    }

                    if (task[0]) {
                        printf("Heartbeat task: %s\n", task);
                        task_count++;
                    }
                }
            }
        }

        /* Move to next line */
        if (eol) {
            line = eol + 1;
        } else {
            break;
        }
    }

    if (task_count > 0) {
        printf("Heartbeat: %d task(s) found\n", task_count);
    }

    /* Refresh SYSTEM.md on each heartbeat (#75) */
    WorkspacePaths wp;
    if (workspace_get_paths(&wp)) {
        sysaware_update(wp.workspace_dir);
    }

    return task_count > 0;
}
