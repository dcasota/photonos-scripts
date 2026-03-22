#ifndef DB_H
#define DB_H

#include <sqlite3.h>
#include "csv_parser.h"

typedef struct {
    sqlite3 *handle;
} db_t;

/* Open (or create) the database at path. Returns 0 on success. */
int db_open(db_t *db, const char *path);

/* Close the database. */
void db_close(db_t *db);

/* Create tables and indexes if they don't exist. */
int db_init_schema(db_t *db);

/* Check if a scan file was already imported. Returns 1 if exists, 0 if not. */
int db_scan_file_exists(db_t *db, const char *filename);

/* Insert a scan file record. Returns the new row id, or -1 on error. */
long long db_insert_scan_file(db_t *db, const char *filename, const char *branch,
                              const char *scan_datetime, const char *file_sha256,
                              int schema_version);

/* Insert all package rows for a scan file. Uses a transaction. Returns 0 on success. */
int db_insert_packages(db_t *db, long long scan_file_id, const csv_data_t *data);

/* Import a single .prn file. Parses filename, checks dedup, parses CSV, inserts.
   Returns: 0 = imported, 1 = skipped (duplicate), -1 = error */
int db_import_file(db_t *db, const char *filepath);

/* Import all photonos-urlhealth-*.prn from a directory. Returns count imported. */
int db_import_directory(db_t *db, const char *dirpath);

/* Timeline query result */
typedef struct {
    char branch[16];
    char scan_datetime[16];
    int qualifying_count;
} timeline_point_t;

typedef struct {
    timeline_point_t *points;
    int count;
} timeline_data_t;

/* Query timeline data: count of packages per (branch, scan_datetime) where
   url_health='200' AND update_available is a version (not empty/pinned/(same version))
   AND update_download_name matches name-*.tar.* */
int db_query_timeline(db_t *db, timeline_data_t *out);
void timeline_data_free(timeline_data_t *data);

/* Top-changed package result (all branches) */
typedef struct {
    char name[256];
    int changes_2023;
    int changes_2024;
    int changes_2025;
    int changes_2026;
    int total;
    char branches[128];
} top_changed_t;

typedef struct {
    top_changed_t *items;
    int count;
} top_changed_data_t;

int db_query_top_changed(db_t *db, top_changed_data_t *out, int limit);
void top_changed_data_free(top_changed_data_t *data);

/* Least-changed package result */
typedef struct {
    char name[256];
    char branches[128];
    int total_changes;
} least_changed_t;

typedef struct {
    least_changed_t *items;
    int count;
} least_changed_data_t;

int db_query_least_changed(db_t *db, least_changed_data_t *out);
void least_changed_data_free(least_changed_data_t *data);

/* Category distribution result */
typedef struct {
    char category[64];
    int count;
    double percentage;
} category_t;

typedef struct {
    category_t *items;
    int count;
    int total;
} category_data_t;

int db_query_categories(db_t *db, category_data_t *out);
void category_data_free(category_data_t *data);

/* Category drift over time per branch */
typedef struct {
    char branch[16];
    char scan_datetime[16];
    char category[64];
    double percentage;
} category_drift_point_t;

typedef struct {
    category_drift_point_t *points;
    int count;
    char categories[32][64];
    int ncategories;
    char branches[16][16];
    int nbranches;
} category_drift_data_t;

int db_query_category_drift(db_t *db, category_drift_data_t *out);
void category_drift_data_free(category_drift_data_t *data);

#endif
