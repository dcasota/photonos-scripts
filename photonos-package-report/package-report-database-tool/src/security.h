#ifndef SECURITY_H
#define SECURITY_H

#include <stddef.h>

#define MAX_PATH_LEN 4096
#define MAX_FIELD_LEN 8192
#define MAX_LINE_LEN 65536
#define MAX_FILE_SIZE (50 * 1024 * 1024)  /* 50 MB */
#define MAX_IMPORT_FILES 10000
#define MAX_ROWS_PER_FILE 100000

/* Validate and resolve a path; returns 0 on success, -1 on error.
   resolved must be at least MAX_PATH_LEN bytes. */
int secure_resolve_path(const char *input, char *resolved, size_t resolved_sz);

/* Check path does not escape base_dir via traversal. Returns 0 if safe. */
int secure_check_path_prefix(const char *resolved, const char *base_dir);

/* Validate a filename contains no path separators or traversal. Returns 0 if safe. */
int secure_validate_filename(const char *filename);

/* Sanitize a string for XML output (escape &, <, >, ", ').
   Returns newly allocated string; caller must free. */
char *secure_xml_escape(const char *input);

/* Safe string copy with truncation. Always NUL-terminates. */
void secure_strncpy(char *dst, const char *src, size_t dst_sz);

#endif
