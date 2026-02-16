#define _XOPEN_SOURCE 700
#include "tools_fs.h"
#include "ai.h"
#include "../util/util.h"
#include "../util/journal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fnmatch.h>
#include <libgen.h>
#include <sys/stat.h>
#include <time.h>

static FsConfig active_cfg;
static bool cfg_ready;

static const char *B64 =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int fs_base64_encode(const unsigned char *in, size_t len,
                     char *out, int out_size) {
    int pos = 0;
    size_t i;
    for (i = 0; i + 2 < len && pos + 4 < out_size; i += 3) {
        out[pos++] = B64[in[i] >> 2];
        out[pos++] = B64[((in[i] & 3) << 4) | (in[i+1] >> 4)];
        out[pos++] = B64[((in[i+1] & 0xF) << 2) | (in[i+2] >> 6)];
        out[pos++] = B64[in[i+2] & 0x3F];
    }
    if (i < len && pos + 4 < out_size) {
        out[pos++] = B64[in[i] >> 2];
        if (i + 1 < len) {
            out[pos++] = B64[((in[i] & 3) << 4) | (in[i+1] >> 4)];
            out[pos++] = B64[(in[i+1] & 0xF) << 2];
        } else {
            out[pos++] = B64[(in[i] & 3) << 4];
            out[pos++] = '=';
        }
        out[pos++] = '=';
    }
    if (pos < out_size) out[pos] = '\0';
    return pos;
}

void fs_human_size(long bytes, char *buf, int buf_size) {
    if (bytes >= 1073741824L)
        snprintf(buf, buf_size, "%.1f GB", (double)bytes / 1073741824.0);
    else if (bytes >= 1048576L)
        snprintf(buf, buf_size, "%.1f MB", (double)bytes / 1048576.0);
    else if (bytes >= 1024L)
        snprintf(buf, buf_size, "%.1f KB", (double)bytes / 1024.0);
    else
        snprintf(buf, buf_size, "%ld B", bytes);
}

void fs_iso_time(time_t t, char *buf, int buf_size) {
    struct tm tm;
    gmtime_r(&t, &tm);
    strftime(buf, buf_size, "%Y-%m-%dT%H:%M:%SZ", &tm);
}

bool fs_resolve_path(const char *path, char *out, int out_size) {
    char *resolved = realpath(path, NULL);
    if (resolved) {
        str_safe_copy(out, resolved, out_size);
        free(resolved);
        return true;
    }
    /* For new files, resolve parent dir */
    char dir_copy[FS_MAX_PATH_LEN], base_copy[FS_MAX_PATH_LEN];
    str_safe_copy(dir_copy, path, sizeof(dir_copy));
    str_safe_copy(base_copy, path, sizeof(base_copy));
    char *parent = realpath(dirname(dir_copy), NULL);
    if (!parent) return false;
    snprintf(out, out_size, "%s/%s", parent, basename(base_copy));
    free(parent);
    return true;
}

bool fs_is_under(const char *path, const char *prefix) {
    if (prefix[0] == '/' && prefix[1] == '\0')
        return path[0] == '/';
    size_t n = strlen(prefix);
    return strncmp(path, prefix, n) == 0 && (path[n] == '\0' || path[n] == '/');
}

bool fs_mkdirs(const char *path) {
    char tmp[FS_MAX_PATH_LEN];
    str_safe_copy(tmp, path, sizeof(tmp));
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755) == 0 || errno == EEXIST;
}

const char *fs_next_line(const char *input, char *buf, int buf_size) {
    const char *nl = strchr(input, '\n');
    if (nl) {
        size_t len = (size_t)(nl - input);
        if (len >= (size_t)buf_size) len = buf_size - 1;
        memcpy(buf, input, len);
        buf[len] = '\0';
        return nl + 1;
    }
    str_safe_copy(buf, input, buf_size);
    return NULL;
}

/* ---- public ---- */

const FsConfig *fs_get_active_cfg(void) {
    return &active_cfg;
}

void fs_config_defaults(FsConfig *cfg) {
    memset(cfg, 0, sizeof(*cfg));
    str_safe_copy(cfg->access_mode, "full", sizeof(cfg->access_mode));
    str_safe_copy(cfg->allowed_paths[0], "/", FS_MAX_PATH_LEN);
    cfg->allowed_count = 1;
    str_safe_copy(cfg->denied_paths[0], "/proc/kcore", FS_MAX_PATH_LEN);
    str_safe_copy(cfg->denied_paths[1], "/dev/sd*", FS_MAX_PATH_LEN);
    str_safe_copy(cfg->denied_paths[2], "/dev/nvme*", FS_MAX_PATH_LEN);
    str_safe_copy(cfg->denied_paths[3], "/boot/efi", FS_MAX_PATH_LEN);
    cfg->denied_count = 4;
    str_safe_copy(cfg->readonly_paths[0], "/proc", FS_MAX_PATH_LEN);
    str_safe_copy(cfg->readonly_paths[1], "/sys", FS_MAX_PATH_LEN);
    str_safe_copy(cfg->readonly_paths[2], "/boot", FS_MAX_PATH_LEN);
    cfg->readonly_count = 3;
    cfg->max_read_size = 10L * 1024 * 1024;
    cfg->max_write_size = 5L * 1024 * 1024;
    cfg->max_search_depth = 20;
    cfg->max_search_results = 1000;
}

bool fs_validate_path(const FsConfig *cfg, const char *path,
                      bool write_required) {
    if (!cfg || !path || !*path) return false;
    char resolved[FS_MAX_PATH_LEN];
    if (!fs_resolve_path(path, resolved, sizeof(resolved))) return false;

    /* Deny list always applies */
    for (int i = 0; i < cfg->denied_count; i++)
        if (fnmatch(cfg->denied_paths[i], resolved, 0) == 0) return false;

    /* Read-only paths block writes */
    if (write_required)
        for (int i = 0; i < cfg->readonly_count; i++)
            if (fs_is_under(resolved, cfg->readonly_paths[i])) return false;

    /* If write_paths is configured, writes must be within those paths */
    if (write_required && cfg->write_count > 0) {
        bool in_write_path = false;
        for (int i = 0; i < cfg->write_count; i++) {
            if (fs_is_under(resolved, cfg->write_paths[i])) {
                in_write_path = true;
                break;
            }
        }
        if (!in_write_path) return false;
    }

    /* Check allowed paths for reads (and writes if no write_paths) */
    for (int i = 0; i < cfg->allowed_count; i++)
        if (fs_is_under(resolved, cfg->allowed_paths[i])) return true;

    return false;
}

const FsConfig *fs_get_config(void) {
    return cfg_ready ? &active_cfg : NULL;
}

void tools_fs_init(const FsConfig *cfg) {
    if (!cfg) return;
    memcpy(&active_cfg, cfg, sizeof(active_cfg));
    cfg_ready = true;

    ai_tool_register("read_text_file",
        "Read text file. Input: path[\\nhead=N|tail=N]",
        fs_tool_read_text_file);
    ai_tool_register("read_binary_file",
        "Read binary file as base64. Input: path",
        fs_tool_read_binary_file);
    ai_tool_register("read_multiple_files",
        "Read multiple files. Input: path1\\npath2\\n...",
        fs_tool_read_multiple);
    ai_tool_register("list_directory",
        "List directory entries. Input: path",
        fs_tool_list_directory);
    ai_tool_register("list_directory_sizes",
        "List with sizes. Input: path[\\nsort=size]",
        fs_tool_list_sizes);
    ai_tool_register("directory_tree",
        "Recursive tree. Input: path[\\nexclude=p1,p2]",
        fs_tool_directory_tree);
    ai_tool_register("search_files",
        "Glob search. Input: path\\npattern[\\nexclude=p1,p2]",
        fs_tool_search_files);
    ai_tool_register("get_file_info",
        "File stat info. Input: path",
        fs_tool_get_file_info);
    ai_tool_register("write_file",
        "Write file. Input: path\\ncontent",
        fs_tool_write_file);
    ai_tool_register("edit_file",
        "Edit file. Input: path\\nold_text\\nnew_text[\\ndry_run=true]",
        fs_tool_edit_file);
    ai_tool_register("create_directory",
        "Create directory (mkdir -p). Input: path",
        fs_tool_create_directory);
    ai_tool_register("move_file",
        "Move/rename file. Input: source\\ndestination",
        fs_tool_move_file);
    ai_tool_register("delete_file",
        "Delete file or empty dir. Input: path",
        fs_tool_delete_file);
    ai_tool_register("list_allowed_paths",
        "Show filesystem access configuration.",
        fs_tool_list_allowed);
}
