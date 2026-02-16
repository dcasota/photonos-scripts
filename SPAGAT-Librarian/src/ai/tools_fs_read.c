#define _XOPEN_SOURCE 700
#include "tools_fs.h"
#include "ai.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <fnmatch.h>
#include <ftw.h>
#include <sys/stat.h>
#include <time.h>

/* nftw callback state (nftw has no user_data parameter) */
static char nftw_buf[SPAGAT_MAX_RESPONSE_LEN];
static int nftw_pos, nftw_max, nftw_count, nftw_depth, nftw_baselen;
static int nftw_nexclude;
static const char *nftw_pattern;
static const char *nftw_excludes[32];

#define SKIP_DOT(e) ((e)[0] == '.' && (!(e)[1] || ((e)[1] == '.' && !(e)[2])))

static void parse_excludes(const char *opt) {
    nftw_nexclude = 0;
    if (strncmp(opt, "exclude=", 8) != 0) return;
    static char store[32][128];
    char tmp[1024];
    str_safe_copy(tmp, opt + 8, sizeof(tmp));
    char *tok = strtok(tmp, ",");
    while (tok && nftw_nexclude < 32) {
        str_safe_copy(store[nftw_nexclude], str_trim(tok), 128);
        nftw_excludes[nftw_nexclude] = store[nftw_nexclude];
        nftw_nexclude++;
        tok = strtok(NULL, ",");
    }
}

/* ---- read tool handlers ---- */

bool fs_tool_read_text_file(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    char path[FS_MAX_PATH_LEN];
    int head = 0, tail = 0;
    const char *rest = fs_next_line(input, path, sizeof(path));
    if (rest) {
        if (strncmp(rest, "head=", 5) == 0) head = atoi(rest + 5);
        else if (strncmp(rest, "tail=", 5) == 0) tail = atoi(rest + 5);
    }

    if (!fs_validate_path(cfg, path, false)) {
        snprintf(output, osize, "Error: access denied: %s", path);
        return false;
    }
    struct stat st;
    if (stat(path, &st)) {
        snprintf(output, osize, "Error: %s: %s", path, strerror(errno));
        return false;
    }
    if (st.st_size > cfg->max_read_size) {
        str_safe_copy(output, "Error: file too large", osize);
        return false;
    }

    FILE *fp = fopen(path, "r");
    if (!fp) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }

    /* Binary detection */
    unsigned char probe[512];
    size_t pn = fread(probe, 1, sizeof(probe), fp);
    bool binary = false;
    for (size_t i = 0; i < pn; i++)
        if (!probe[i]) { binary = true; break; }
    rewind(fp);

    int pos = 0;
    if (binary)
        pos += snprintf(output, osize, "[Warning: binary content detected]\n");

    if (tail > 0) {
        char **lines = NULL;
        int lcount = 0, lcap = 0;
        char *line = NULL;
        size_t lsz = 0;
        while (getline(&line, &lsz, fp) != -1) {
            if (lcount >= lcap) {
                lcap = lcap ? lcap * 2 : 256;
                lines = realloc(lines, sizeof(char *) * lcap);
            }
            lines[lcount++] = strdup(line);
        }
        free(line);
        int start = lcount - tail;
        if (start < 0) start = 0;
        for (int i = start; i < lcount && pos < osize - 2; i++)
            pos += snprintf(output + pos, osize - pos, "%s", lines[i]);
        for (int i = 0; i < lcount; i++) free(lines[i]);
        free(lines);
    } else if (head > 0) {
        char *line = NULL;
        size_t lsz = 0;
        int count = 0;
        while (count < head && getline(&line, &lsz, fp) != -1 && pos < osize - 2) {
            pos += snprintf(output + pos, osize - pos, "%s", line);
            count++;
        }
        free(line);
    } else {
        int ch;
        while ((ch = fgetc(fp)) != EOF && pos < osize - 2)
            output[pos++] = (char)ch;
        output[pos] = '\0';
    }

    fclose(fp);
    return true;
}

bool fs_tool_read_binary_file(const char *input, char *output, int osize) {
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
    if (stat(input, &st)) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    if (st.st_size > cfg->max_read_size) {
        str_safe_copy(output, "Error: file too large", osize);
        return false;
    }

    FILE *fp = fopen(input, "rb");
    if (!fp) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }
    unsigned char *data = malloc(st.st_size);
    if (!data) { fclose(fp); str_safe_copy(output, "Error: OOM", osize); return false; }
    size_t n = fread(data, 1, st.st_size, fp);
    fclose(fp);

    int pos = snprintf(output, osize, "size=%zu\n", n);
    fs_base64_encode(data, n, output + pos, osize - pos);
    free(data);
    return true;
}

bool fs_tool_read_multiple(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no paths", osize);
        return false;
    }
    char path[FS_MAX_PATH_LEN];
    int pos = 0;
    const char *cursor = input;
    while (cursor && *cursor && pos < osize - 128) {
        cursor = fs_next_line(cursor, path, sizeof(path));
        pos += snprintf(output + pos, osize - pos, "=== %s ===\n", path);
        if (!fs_validate_path(cfg, path, false)) {
            pos += snprintf(output + pos, osize - pos, "Error: access denied\n\n");
        } else {
            FILE *fp = fopen(path, "r");
            if (!fp) {
                pos += snprintf(output + pos, osize - pos, "Error: %s\n\n",
                                strerror(errno));
            } else {
                int ch;
                while ((ch = fgetc(fp)) != EOF && pos < osize - 4)
                    output[pos++] = (char)ch;
                output[pos] = '\0';
                pos += snprintf(output + pos, osize - pos, "\n\n");
                fclose(fp);
            }
        }
    }
    return true;
}

bool fs_tool_list_directory(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    if (!fs_validate_path(cfg, input, false)) {
        snprintf(output, osize, "Error: access denied: %s", input);
        return false;
    }

    DIR *dir = opendir(input);
    if (!dir) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }

    /* Collect and sort entries */
    char **names = NULL, **tags = NULL;
    int count = 0, cap = 0;
    struct dirent *ent;
    while ((ent = readdir(dir))) {
        if (SKIP_DOT(ent->d_name)) continue;
        if (count >= cap) {
            cap = cap ? cap * 2 : 64;
            names = realloc(names, sizeof(char *) * cap);
            tags = realloc(tags, sizeof(char *) * cap);
        }
        char fullpath[FS_MAX_PATH_LEN + 256];
        struct stat st;
        snprintf(fullpath, sizeof(fullpath), "%s/%s", input, ent->d_name);
        const char *tag = "[FILE]";
        if (lstat(fullpath, &st) == 0) {
            if (S_ISDIR(st.st_mode)) tag = "[DIR]";
            else if (S_ISLNK(st.st_mode)) tag = "[LINK]";
        }
        names[count] = strdup(ent->d_name);
        tags[count] = strdup(tag);
        count++;
    }
    closedir(dir);

    /* Bubble sort by name */
    for (int i = 0; i < count - 1; i++)
        for (int j = i + 1; j < count; j++)
            if (strcmp(names[i], names[j]) > 0) {
                char *t = names[i]; names[i] = names[j]; names[j] = t;
                t = tags[i]; tags[i] = tags[j]; tags[j] = t;
            }

    int pos = 0;
    for (int i = 0; i < count && pos < osize - 128; i++)
        pos += snprintf(output + pos, osize - pos, "%s %s\n", tags[i], names[i]);

    for (int i = 0; i < count; i++) { free(names[i]); free(tags[i]); }
    free(names);
    free(tags);
    return true;
}

bool fs_tool_list_sizes(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    char dirpath[FS_MAX_PATH_LEN];
    bool sort_by_size = false;
    const char *rest = fs_next_line(input, dirpath, sizeof(dirpath));
    if (rest && strstr(rest, "sort=size")) sort_by_size = true;

    if (!fs_validate_path(cfg, dirpath, false)) {
        snprintf(output, osize, "Error: access denied: %s", dirpath);
        return false;
    }

    DIR *dir = opendir(dirpath);
    if (!dir) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }

    typedef struct { char name[256]; long size; bool is_dir; } Entry;
    Entry *entries = NULL;
    int count = 0, cap = 0;
    long total = 0;
    struct dirent *ent;

    while ((ent = readdir(dir))) {
        if (SKIP_DOT(ent->d_name)) continue;
        if (count >= cap) {
            cap = cap ? cap * 2 : 64;
            entries = realloc(entries, sizeof(Entry) * cap);
        }
        char fullpath[FS_MAX_PATH_LEN + 256];
        struct stat st;
        snprintf(fullpath, sizeof(fullpath), "%s/%s", dirpath, ent->d_name);
        entries[count].size = 0;
        entries[count].is_dir = false;
        if (stat(fullpath, &st) == 0) {
            entries[count].size = (long)st.st_size;
            entries[count].is_dir = S_ISDIR(st.st_mode);
            total += entries[count].size;
        }
        str_safe_copy(entries[count].name, ent->d_name, sizeof(entries[count].name));
        count++;
    }
    closedir(dir);

    /* Sort */
    for (int i = 0; i < count - 1; i++)
        for (int j = i + 1; j < count; j++) {
            bool swap = sort_by_size
                ? entries[i].size < entries[j].size
                : strcmp(entries[i].name, entries[j].name) > 0;
            if (swap) { Entry t = entries[i]; entries[i] = entries[j]; entries[j] = t; }
        }

    int pos = 0;
    char sbuf[32];
    for (int i = 0; i < count && pos < osize - 128; i++) {
        fs_human_size(entries[i].size, sbuf, sizeof(sbuf));
        pos += snprintf(output + pos, osize - pos, "%-8s %s%s\n",
                        sbuf, entries[i].name, entries[i].is_dir ? "/" : "");
    }
    fs_human_size(total, sbuf, sizeof(sbuf));
    snprintf(output + pos, osize - pos, "\n%d entries, %s total", count, sbuf);
    free(entries);
    return true;
}

static int tree_callback(const char *fpath, const struct stat *sb,
                         int typeflag, struct FTW *ftwbuf) {
    (void)sb;
    if (ftwbuf->level > nftw_depth) return 0;

    const char *relative = fpath + nftw_baselen;
    if (*relative == '/') relative++;
    if (!*relative) return 0;

    const char *name = fpath + ftwbuf->base;
    for (int i = 0; i < nftw_nexclude; i++)
        if (fnmatch(nftw_excludes[i], name, 0) == 0) return 0;

    int indent = ftwbuf->level - 1;
    if (indent < 0) indent = 0;

    if (nftw_pos < nftw_max - 128) {
        for (int i = 0; i < indent; i++)
            nftw_pos += snprintf(nftw_buf + nftw_pos, nftw_max - nftw_pos, "  ");
        nftw_pos += snprintf(nftw_buf + nftw_pos, nftw_max - nftw_pos,
                             "%s%s\n", name,
                             (typeflag == FTW_D || typeflag == FTW_DP) ? "/" : "");
    }
    nftw_count++;
    return 0;
}

bool fs_tool_directory_tree(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no path", osize);
        return false;
    }
    char dirpath[FS_MAX_PATH_LEN];
    nftw_nexclude = 0;
    const char *rest = fs_next_line(input, dirpath, sizeof(dirpath));
    if (rest) parse_excludes(rest);

    if (!fs_validate_path(cfg, dirpath, false)) {
        snprintf(output, osize, "Error: access denied: %s", dirpath);
        return false;
    }

    nftw_pos = 0;
    nftw_max = (int)sizeof(nftw_buf);
    nftw_count = 0;
    nftw_depth = cfg->max_search_depth;
    nftw_baselen = (int)strlen(dirpath);
    nftw_buf[0] = '\0';

    if (nftw(dirpath, tree_callback, 64, FTW_PHYS)) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }

    int pos = snprintf(output, osize, "%s/\n", dirpath);
    int remaining = osize - pos;
    if (remaining > 1) {
        int cp = nftw_pos < remaining - 1 ? nftw_pos : remaining - 1;
        memcpy(output + pos, nftw_buf, cp);
        output[pos + cp] = '\0';
    }
    return true;
}

static int search_callback(const char *fpath, const struct stat *sb,
                            int typeflag, struct FTW *ftwbuf) {
    (void)sb;
    const FsConfig *cfg = fs_get_active_cfg();
    if (ftwbuf->level > nftw_depth || nftw_count >= cfg->max_search_results)
        return 0;
    if (typeflag == FTW_D || typeflag == FTW_DP) return 0;

    const char *name = fpath + ftwbuf->base;
    for (int i = 0; i < nftw_nexclude; i++)
        if (fnmatch(nftw_excludes[i], name, 0) == 0) return 0;

    if (fnmatch(nftw_pattern, name, 0) == 0) {
        if (nftw_pos < nftw_max - 128)
            nftw_pos += snprintf(nftw_buf + nftw_pos, nftw_max - nftw_pos,
                                 "%s\n", fpath);
        nftw_count++;
    }
    return 0;
}

bool fs_tool_search_files(const char *input, char *output, int osize) {
    const FsConfig *cfg = fs_get_active_cfg();
    if (!input || !*input) {
        str_safe_copy(output, "Error: no input", osize);
        return false;
    }
    char dirpath[FS_MAX_PATH_LEN], pattern[256];
    nftw_nexclude = 0;
    const char *rest = fs_next_line(input, dirpath, sizeof(dirpath));
    if (!rest) {
        str_safe_copy(output, "Error: need path and pattern", osize);
        return false;
    }
    rest = fs_next_line(rest, pattern, sizeof(pattern));
    if (rest) parse_excludes(rest);

    if (!fs_validate_path(cfg, dirpath, false)) {
        snprintf(output, osize, "Error: access denied: %s", dirpath);
        return false;
    }

    nftw_pos = 0;
    nftw_max = (int)sizeof(nftw_buf);
    nftw_count = 0;
    nftw_depth = cfg->max_search_depth;
    nftw_pattern = pattern;
    nftw_buf[0] = '\0';

    if (nftw(dirpath, search_callback, 64, FTW_PHYS)) {
        snprintf(output, osize, "Error: %s", strerror(errno));
        return false;
    }

    int pos = snprintf(output, osize, "Found %d:\n", nftw_count);
    int remaining = osize - pos;
    if (remaining > 1) {
        int cp = nftw_pos < remaining - 1 ? nftw_pos : remaining - 1;
        memcpy(output + pos, nftw_buf, cp);
        output[pos + cp] = '\0';
    }
    return true;
}


