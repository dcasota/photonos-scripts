#ifndef CSV_PARSER_H
#define CSV_PARSER_H

#include <stddef.h>

#define CSV_SCHEMA_OLD  5   /* Spec, Source0 original, Modified Source0, UrlHealth, UpdateAvailable */
#define CSV_SCHEMA_NEW 12   /* + UpdateURL, HealthUpdateURL, Name, SHAName, UpdateDownloadName, warning, ArchivationDate */

typedef struct {
    char *spec;
    char *source0_original;
    char *modified_source0;
    char *url_health;
    char *update_available;
    char *update_url;
    char *health_update_url;
    char *name;
    char *sha_name;
    char *update_download_name;
    char *warning;
    char *archivation_date;
} csv_row_t;

typedef struct {
    csv_row_t *rows;
    int count;
    int capacity;
    int schema_version;  /* CSV_SCHEMA_OLD or CSV_SCHEMA_NEW */
} csv_data_t;

/* Parse a .prn file. Auto-detects encoding (UTF-16LE/UTF-8) and schema.
   Returns 0 on success, -1 on error. Caller must call csv_data_free(). */
int csv_parse_file(const char *filepath, csv_data_t *out);

/* Free all memory in csv_data_t */
void csv_data_free(csv_data_t *data);

/* Convert UTF-16LE buffer to UTF-8. Returns malloc'd string; caller frees. */
char *utf16le_to_utf8(const unsigned char *buf, size_t byte_len);

#endif
