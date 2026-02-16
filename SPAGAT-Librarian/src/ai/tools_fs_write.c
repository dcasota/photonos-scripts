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
#include <sys/stat.h>
#include <time.h>
#include <sys/stat.h>

/* ---- write tool handlers ---- */

bool fs_tool_write_file(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no input", osize);
        return false;
    }
    const char *nl = strchr(input, '\n');
    if (!nl) {
        str_safe_copy(output, "Error: need path and content", osize);
        return false;
    }
    char path[FS_MAX_PATH_LEN];
    size_t plen = (size_t)(nl - input);
    if (plen >= sizeof(path)) plen = sizeof(path) - 1;
    memcpy(path, input, plen);
    path[plen] = '\0';

    const char *content = nl + 1;
    size_t clen = strlen(content);
    if ((long)clen > cfg->max_write_size) {
        str_safe_copy(output, "Error: content too large", osize);
        return false;
    }
    if (!fs_validate_path(cfg, path, true)) {
        snprintf(output, osize, "Error: access denied: %s", path);
        return false;
    }

    /* Create parent directories if needed */
    char dir_copy[FS_MAX_PATH_LEN];
    str_safe_copy(dir_copy, path, sizeof(dir_copy));
    char *slash = strrchr(dir_copy, '/');
    if (slash) {
        *slash = '\0';
        if (dir_copy[0] && !file_exists(dir_copy)) fs_mkdirs(dir_copy);
    }

    FILE *fp = fopen(path, "w");
    if (!fp) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    fwrite(content, 1, clen, fp);
    fclose(fp);

    if (journal_is_open())
        journal_log(JOURNAL_INFO, "fs: write_file %s (%zu bytes)", path, clen);
    snprintf(output, osize, "Wrote %zu bytes to %s", clen, path);
    return true;
}

bool fs_tool_edit_file(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no input", osize);
        return false;
    }
    const char *nl1 = strchr(input, '\n');
    const char *nl2 = nl1 ? strchr(nl1 + 1, '\n') : NULL;
    if (!nl1 || !nl2) {
        str_safe_copy(output, "Error: need path, old_text, new_text (3 lines)", osize);
        return false;
    }

    char path[FS_MAX_PATH_LEN];
    size_t plen = (size_t)(nl1 - input);
    if (plen >= sizeof(path)) plen = sizeof(path) - 1;
    memcpy(path, input, plen);
    path[plen] = '\0';

    size_t old_len = (size_t)(nl2 - nl1 - 1);
    char *old_text = malloc(old_len + 1);
    memcpy(old_text, nl1 + 1, old_len);
    old_text[old_len] = '\0';

    const char *rest_after = nl2 + 1;
    bool dry_run = false;
    const char *nl3 = strchr(rest_after, '\n');
    size_t new_len;
    char *new_text;
    if (nl3) {
        new_len = (size_t)(nl3 - rest_after);
        new_text = malloc(new_len + 1);
        memcpy(new_text, rest_after, new_len);
        new_text[new_len] = '\0';
        if (strstr(nl3 + 1, "dry_run=true")) dry_run = true;
    } else {
        new_len = strlen(rest_after);
        new_text = malloc(new_len + 1);
        memcpy(new_text, rest_after, new_len);
        new_text[new_len] = '\0';
    }

    if (!fs_validate_path(cfg, path, !dry_run)) {
        free(old_text); free(new_text);
        snprintf(output, osize, "Error: access denied: %s", path);
        return false;
    }

    FILE *fp = fopen(path, "r");
    if (!fp) {
        free(old_text); free(new_text);
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    fseek(fp, 0, SEEK_END);
    long fsize = ftell(fp);
    rewind(fp);
    char *file_content = malloc(fsize + 1);
    fread(file_content, 1, fsize, fp);
    file_content[fsize] = '\0';
    fclose(fp);

    char *match = strstr(file_content, old_text);
    if (!match) {
        free(old_text); free(new_text); free(file_content);
        str_safe_copy(output, "Error: old_text not found", osize);
        return false;
    }

    size_t before = (size_t)(match - file_content);
    size_t after = (size_t)fsize - before - old_len;
    size_t total = before + new_len + after;
    char *result = malloc(total + 1);
    memcpy(result, file_content, before);
    memcpy(result + before, new_text, new_len);
    memcpy(result + before + new_len, file_content + before + old_len, after);
    result[total] = '\0';

    if (dry_run) {
        snprintf(output, osize, "[dry_run] Would replace %zu -> %zu bytes in %s",
                 old_len, new_len, path);
    } else {
        fp = fopen(path, "w");
        if (!fp) {
            free(old_text); free(new_text); free(file_content); free(result);
            snprintf(output, osize, "Error: %s", strerror(errno));
            return false;
        }
        fwrite(result, 1, total, fp);
        fclose(fp);
        if (journal_is_open())
            journal_log(JOURNAL_INFO, "fs: edit_file %s", path);
        snprintf(output, osize, "Edited %s: replaced %zu -> %zu bytes",
                 path, old_len, new_len);
    }

    free(old_text);
    free(new_text);
    free(file_content);
    free(result);
    return true;
}

bool fs_tool_create_directory(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    if (!fs_validate_path(cfg, input, true)) {
        snprintf(output, osize, "Error: access denied: %s", input);
        return false;
    }
    if (fs_mkdirs(input)) {
        if (journal_is_open())
            journal_log(JOURNAL_INFO, "fs: create_directory %s", input);
        snprintf(output, osize, "Created: %s", input);
        return true;
    }
    snprintf(output, osize, "Error: %s", strerror(errno));
    return false;
}

bool fs_tool_move_file(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no input", osize);
        return false;
    }
    char src[FS_MAX_PATH_LEN], dst[FS_MAX_PATH_LEN];
    const char *rest = fs_next_line(input, src, sizeof(src));
    if (!rest) {
        str_safe_copy(output, "Error: need source and destination", osize);
        return false;
    }
    str_safe_copy(dst, rest, sizeof(dst));

    if (!fs_validate_path(cfg, src, true)) {
        snprintf(output, osize, "Error: source denied: %s", src);
        return false;
    }
    if (!fs_validate_path(cfg, dst, true)) {
        snprintf(output, osize, "Error: destination denied: %s", dst);
        return false;
    }
    if (file_exists(dst)) {
        snprintf(output, osize, "Error: destination exists: %s", dst);
        return false;
    }
    if (rename(src, dst)) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    if (journal_is_open())
        journal_log(JOURNAL_INFO, "fs: move_file %s -> %s", src, dst);
    snprintf(output, osize, "Moved %s -> %s", src, dst);
    return true;
}

bool fs_tool_delete_file(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    static const char *protected_paths[] = {
        "/", "/home", "/etc", "/var", "/usr", "/boot", "/tmp", NULL
    };
    char resolved[FS_MAX_PATH_LEN];
    if (!fs_resolve_path(input, resolved, sizeof(resolved))) {
        str_safe_copy(output, "Error: cannot resolve path", osize);
        return false;
    }
    for (int i = 0; protected_paths[i]; i++) {
        if (strcmp(resolved, protected_paths[i]) == 0) {
            str_safe_copy(output, "Error: protected path", osize);
            return false;
        }
    }
    if (!fs_validate_path(cfg, input, true)) {
        snprintf(output, osize, "Error: access denied: %s", input);
        return false;
    }

    struct stat st;
    if (lstat(input, &st)) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    int rc = S_ISDIR(st.st_mode) ? rmdir(input) : unlink(input);
    if (rc) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    if (journal_is_open())
        journal_log(JOURNAL_INFO, "fs: delete_file %s", input);
    snprintf(output, osize, "Deleted: %s", input);
    return true;
}

bool fs_tool_get_file_info(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    if (!fs_validate_path(cfg, input, false)) {
        snprintf(output, osize, "Error: access denied: %s", input);
        return false;
    }

    struct stat st;
    if (lstat(input, &st)) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }

    const char *type = "file";
    if (S_ISDIR(st.st_mode)) type = "dir";
    else if (S_ISLNK(st.st_mode)) type = "link";
    else if (S_ISBLK(st.st_mode)) type = "block";
    else if (S_ISCHR(st.st_mode)) type = "char";
    else if (S_ISFIFO(st.st_mode)) type = "fifo";
    else if (S_ISSOCK(st.st_mode)) type = "socket";

    char mt[32], at[32], ct[32], sz[32];
    fs_iso_time(st.st_mtime, mt, sizeof(mt));
    fs_iso_time(st.st_atime, at, sizeof(at));
    fs_iso_time(st.st_ctime, ct, sizeof(ct));
    fs_human_size((long)st.st_size, sz, sizeof(sz));

    snprintf(output, osize,
             "%s\ntype: %s  size: %ld (%s)  perm: %04o  uid: %d  gid: %d\n"
             "modified: %s\naccessed: %s\nchanged:  %s",
             input, type, (long)st.st_size, sz,
             (unsigned)(st.st_mode & 07777),
             (int)st.st_uid, (int)st.st_gid, mt, at, ct);
    return true;
}

bool fs_tool_list_allowed(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    (void)input;
    int pos = 0;
    pos += snprintf(output + pos, osize - pos, "Access mode: %s\n",
                    cfg->access_mode);
    pos += snprintf(output + pos, osize - pos, "Allowed:\n");
    for (int i = 0; i < cfg->allowed_count && pos < osize - 64; i++)
        pos += snprintf(output + pos, osize - pos, "  %s\n",
                        cfg->allowed_paths[i]);
    pos += snprintf(output + pos, osize - pos, "Denied:\n");
    for (int i = 0; i < cfg->denied_count && pos < osize - 64; i++)
        pos += snprintf(output + pos, osize - pos, "  %s\n",
                        cfg->denied_paths[i]);
    pos += snprintf(output + pos, osize - pos, "Read-only:\n");
    for (int i = 0; i < cfg->readonly_count && pos < osize - 64; i++)
        pos += snprintf(output + pos, osize - pos, "  %s\n",
                        cfg->readonly_paths[i]);
    return true;
}
