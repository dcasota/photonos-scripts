#include "db.h"
#include "docx_writer.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(const char *prog)
{
    fprintf(stderr, "Usage: %s --db <path.db> [--import <scans-dir>] [--report <output.docx>]\n\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  --db <path>       SQLite database file (created if absent)\n");
    fprintf(stderr, "  --import <dir>    Import photonos-urlhealth-*.prn files from directory\n");
    fprintf(stderr, "  --report <path>   Generate .docx report\n");
    fprintf(stderr, "  --help            Show this help message\n");
}

int main(int argc, char **argv)
{
    const char *db_path = NULL;
    const char *import_dir = NULL;
    const char *report_path = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--db") == 0 && i + 1 < argc) {
            db_path = argv[++i];
        } else if (strcmp(argv[i], "--import") == 0 && i + 1 < argc) {
            import_dir = argv[++i];
        } else if (strcmp(argv[i], "--report") == 0 && i + 1 < argc) {
            report_path = argv[++i];
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    if (!db_path) {
        fprintf(stderr, "Error: --db is required\n");
        print_usage(argv[0]);
        return 1;
    }

    if (!import_dir && !report_path) {
        fprintf(stderr, "Error: at least one of --import or --report is required\n");
        print_usage(argv[0]);
        return 1;
    }

    /* Validate paths */
    if (db_path && strlen(db_path) >= MAX_PATH_LEN) {
        fprintf(stderr, "Error: database path too long\n");
        return 1;
    }
    if (import_dir && strlen(import_dir) >= MAX_PATH_LEN) {
        fprintf(stderr, "Error: import directory path too long\n");
        return 1;
    }
    if (report_path && strlen(report_path) >= MAX_PATH_LEN) {
        fprintf(stderr, "Error: report path too long\n");
        return 1;
    }

    /* Open database */
    db_t db;
    printf("Opening database: %s\n", db_path);
    if (db_open(&db, db_path) != 0)
        return 1;

    if (db_init_schema(&db) != 0) {
        db_close(&db);
        return 1;
    }

    int exit_code = 0;

    /* Import */
    if (import_dir) {
        printf("Importing from: %s\n", import_dir);
        int imported = db_import_directory(&db, import_dir);
        if (imported < 0) {
            fprintf(stderr, "Import failed\n");
            exit_code = 1;
        } else {
            printf("Successfully imported %d file(s)\n", imported);
        }
    }

    /* Report */
    if (report_path && exit_code == 0) {
        printf("Generating report: %s\n", report_path);

        timeline_data_t timeline;
        top_changed_data_t top_changed;
        least_changed_data_t least_changed;
        category_data_t categories;

        memset(&timeline, 0, sizeof(timeline));
        memset(&top_changed, 0, sizeof(top_changed));
        memset(&least_changed, 0, sizeof(least_changed));
        memset(&categories, 0, sizeof(categories));

        int qrc = 0;
        printf("  Querying timeline data...\n");
        qrc |= db_query_timeline(&db, &timeline);
        printf("  Timeline: %d data points\n", timeline.count);

        printf("  Querying top-changed 5.0 packages...\n");
        qrc |= db_query_top_changed_5(&db, &top_changed, 10);
        printf("  Top changed: %d packages\n", top_changed.count);

        printf("  Querying least-changed packages...\n");
        qrc |= db_query_least_changed(&db, &least_changed);
        printf("  Least changed: %d packages\n", least_changed.count);

        printf("  Querying source categories...\n");
        qrc |= db_query_categories(&db, &categories);
        printf("  Categories: %d groups, %d total packages\n", categories.count, categories.total);

        if (qrc != 0) {
            fprintf(stderr, "Warning: some queries failed, report may be incomplete\n");
        }

        if (docx_write_report(report_path, &timeline, &top_changed,
                              &least_changed, &categories) != 0) {
            fprintf(stderr, "Failed to write report\n");
            exit_code = 1;
        } else {
            printf("Report written: %s\n", report_path);
        }

        timeline_data_free(&timeline);
        top_changed_data_free(&top_changed);
        least_changed_data_free(&least_changed);
        category_data_free(&categories);
    }

    db_close(&db);
    return exit_code;
}
