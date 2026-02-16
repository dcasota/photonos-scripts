#ifndef TOOLS_FS_H
#define TOOLS_FS_H

#include <stdbool.h>
#include <stddef.h>
#include <time.h>

#define FS_MAX_PATHS 16
#define FS_MAX_PATH_LEN 512

typedef struct {
    char access_mode[16];
    char allowed_paths[FS_MAX_PATHS][FS_MAX_PATH_LEN];
    int  allowed_count;
    char denied_paths[FS_MAX_PATHS][FS_MAX_PATH_LEN];
    int  denied_count;
    char readonly_paths[FS_MAX_PATHS][FS_MAX_PATH_LEN];
    int  readonly_count;
    /* Write-path separation: if write_count > 0, writes are restricted
       to these paths only, regardless of allowed_paths */
    char write_paths[FS_MAX_PATHS][FS_MAX_PATH_LEN];
    int  write_count;
    long max_read_size;
    long max_write_size;
    int  max_search_depth;
    int  max_search_results;
} FsConfig;

void fs_config_defaults(FsConfig *cfg);

bool fs_validate_path(const FsConfig *cfg, const char *path,
                      bool write_required);

void tools_fs_init(const FsConfig *cfg);

const FsConfig *fs_get_config(void);

/* Internal helpers (used by tools_fs_read.c and tools_fs_write.c) */
const FsConfig *fs_get_active_cfg(void);
bool fs_resolve_path(const char *path, char *out, int out_size);
bool fs_is_under(const char *path, const char *prefix);
bool fs_mkdirs(const char *path);
const char *fs_next_line(const char *input, char *buf, int buf_size);
int fs_base64_encode(const unsigned char *in, size_t len, char *out, int out_size);
void fs_human_size(long bytes, char *buf, int buf_size);
void fs_iso_time(time_t t, char *buf, int buf_size);

/* Tool handlers (registered in tools_fs_init, defined in tools_fs_read.c / tools_fs_write.c) */
bool fs_tool_read_text_file(const char *input, char *output, int osize);
bool fs_tool_read_binary_file(const char *input, char *output, int osize);
bool fs_tool_read_multiple(const char *input, char *output, int osize);
bool fs_tool_list_directory(const char *input, char *output, int osize);
bool fs_tool_list_sizes(const char *input, char *output, int osize);
bool fs_tool_directory_tree(const char *input, char *output, int osize);
bool fs_tool_search_files(const char *input, char *output, int osize);
bool fs_tool_get_file_info(const char *input, char *output, int osize);
bool fs_tool_list_allowed(const char *input, char *output, int osize);
bool fs_tool_write_file(const char *input, char *output, int osize);
bool fs_tool_edit_file(const char *input, char *output, int osize);
bool fs_tool_create_directory(const char *input, char *output, int osize);
bool fs_tool_move_file(const char *input, char *output, int osize);
bool fs_tool_delete_file(const char *input, char *output, int osize);

#endif
