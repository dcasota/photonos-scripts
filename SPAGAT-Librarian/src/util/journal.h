#ifndef JOURNAL_H
#define JOURNAL_H

#include <stdbool.h>

#define JOURNAL_MAX_SIZE (2 * 1024 * 1024) /* 2 MB per log file */
#define JOURNAL_MAX_FILES 3                /* keep 3 rotated files */

/* Log levels */
typedef enum {
    JOURNAL_DEBUG = 0,
    JOURNAL_INFO  = 1,
    JOURNAL_WARN  = 2,
    JOURNAL_ERROR = 3
} JournalLevel;

/* Open the journal log at ~/.spagat/logs/spagat.log
 * Creates directories as needed.  Rotates if over max size. */
bool journal_open(const char *base_dir);

/* Close the journal file */
void journal_close(void);

/* Write a formatted log entry with timestamp and level */
void journal_log(JournalLevel level, const char *fmt, ...)
    __attribute__((format(printf, 2, 3)));

/* Write raw text (used for llama.cpp callback which provides its own format) */
void journal_write_raw(const char *text);

/* Check if journal is open */
bool journal_is_open(void);

#endif
