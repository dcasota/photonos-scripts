#ifndef UTIL_H
#define UTIL_H

#include <stdbool.h>
#include <stddef.h>

char *str_trim(char *str);
char *str_duplicate(const char *str);
bool str_starts_with(const char *str, const char *prefix);
bool str_equals_ignore_case(const char *a, const char *b);
void str_safe_copy(char *dest, const char *src, size_t dest_size);
bool is_numeric(const char *str);
char *get_db_path(void);
char *get_editor(void);
bool file_exists(const char *path);
bool env_is_set(const char *name);

#endif
