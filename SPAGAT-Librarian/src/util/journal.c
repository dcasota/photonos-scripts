#include "journal.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <time.h>
#include <sys/stat.h>
#include <errno.h>

static FILE *log_fp = NULL;
static char log_path[1024];

static bool mkdir_p(const char *path) {
    char tmp[1024];
    str_safe_copy(tmp, path, sizeof(tmp));
    size_t len = strlen(tmp);
    if (len == 0) return false;
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';

    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return false;
            *p = '/';
        }
    }
    return mkdir(tmp, 0755) == 0 || errno == EEXIST;
}

static long file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return (long)st.st_size;
}

static void rotate(void) {
    if (!log_fp) return;
    fclose(log_fp);
    log_fp = NULL;

    /* Rotate: .log.2 -> delete, .log.1 -> .log.2, .log -> .log.1 */
    char old_path[1100], new_path[1100];
    for (int i = JOURNAL_MAX_FILES - 1; i >= 1; i--) {
        snprintf(old_path, sizeof(old_path), "%s.%d", log_path, i);
        snprintf(new_path, sizeof(new_path), "%s.%d", log_path, i + 1);
        rename(old_path, new_path);
    }
    snprintf(new_path, sizeof(new_path), "%s.1", log_path);
    rename(log_path, new_path);

    log_fp = fopen(log_path, "a");
}

bool journal_open(const char *base_dir) {
    if (log_fp) return true;

    char logs_dir[1024];
    snprintf(logs_dir, sizeof(logs_dir), "%.980s/logs", base_dir);
    if (!mkdir_p(logs_dir)) return false;

    snprintf(log_path, sizeof(log_path), "%.1000s/spagat.log", logs_dir);

    if (file_size(log_path) >= JOURNAL_MAX_SIZE)
        rotate();

    log_fp = fopen(log_path, "a");
    return log_fp != NULL;
}

void journal_close(void) {
    if (log_fp) {
        fclose(log_fp);
        log_fp = NULL;
    }
}

bool journal_is_open(void) {
    return log_fp != NULL;
}

static const char *level_str(JournalLevel level) {
    switch (level) {
    case JOURNAL_DEBUG: return "DEBUG";
    case JOURNAL_INFO:  return "INFO";
    case JOURNAL_WARN:  return "WARN";
    case JOURNAL_ERROR: return "ERROR";
    }
    return "???";
}

void journal_log(JournalLevel level, const char *fmt, ...) {
    if (!log_fp) return;

    /* Check rotation */
    if (file_size(log_path) >= JOURNAL_MAX_SIZE)
        rotate();
    if (!log_fp) return;

    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", tm);

    fprintf(log_fp, "[%s] %s: ", ts, level_str(level));

    va_list ap;
    va_start(ap, fmt);
    vfprintf(log_fp, fmt, ap);
    va_end(ap);

    if (fmt[0] && fmt[strlen(fmt) - 1] != '\n')
        fputc('\n', log_fp);

    fflush(log_fp);
}

void journal_write_raw(const char *text) {
    if (!log_fp || !text) return;

    if (file_size(log_path) >= JOURNAL_MAX_SIZE)
        rotate();
    if (!log_fp) return;

    fputs(text, log_fp);
    fflush(log_fp);
}
