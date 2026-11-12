#include "db.h"
#include "docx_writer.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

static void print_usage(const char *prog)
{
    fprintf(stderr, "Usage: %s --db <path.db> [--import <scans-dir>] [--report <output.docx>] [--chart-png <path>]\n\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  --db <path>         SQLite database file (created if absent)\n");
    fprintf(stderr, "  --import <dir>      Import photonos-urlhealth-*.prn files from directory\n");
    fprintf(stderr, "  --report <path>     Generate .docx report\n");
    fprintf(stderr, "  --chart-png <path>  M127: embed this PNG as Section 1's timeline\n");
    fprintf(stderr, "                      (typically pre-rendered by the workflow's\n");
    fprintf(stderr, "                      gen-timeline-chart.py step). When unset or\n");
    fprintf(stderr, "                      unreadable, falls back to the OOXML c:chart.\n");
    fprintf(stderr, "  --help              Show this help message\n");
}

/* Check one path option with secure_cli_path(). Returns buf holding the
   checked path, or NULL if the option was not given. Exits with a message
   for a refused path. */
static const char *checked_path(const char *opt, const char *raw, char *buf, size_t buf_sz)
{
    if (!raw)
        return NULL;
    if (secure_cli_path(raw, buf, buf_sz) != 0) {
        fprintf(stderr, "Error: %s: use a path of at most %d characters from "
                "[A-Za-z0-9/._-+~@:,] without '..' components\n", opt, MAX_PATH_LEN - 1);
        exit(1);
    }
    return buf;
}

int main(int argc, char **argv)
{
    const char *db_arg = NULL;
    const char *import_arg = NULL;
    const char *report_arg = NULL;
    const char *chart_arg = NULL;
    static char db_buf[MAX_PATH_LEN], import_buf[MAX_PATH_LEN];
    static char report_buf[MAX_PATH_LEN], chart_buf[MAX_PATH_LEN];

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--db") == 0 && i + 1 < argc) {
            db_arg = argv[++i];
        } else if (strcmp(argv[i], "--import") == 0 && i + 1 < argc) {
            import_arg = argv[++i];
        } else if (strcmp(argv[i], "--report") == 0 && i + 1 < argc) {
            report_arg = argv[++i];
        } else if (strcmp(argv[i], "--chart-png") == 0 && i + 1 < argc) {
            chart_arg = argv[++i];
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    if (!db_arg) {
        fprintf(stderr, "Error: --db is required\n");
        print_usage(argv[0]);
        return 1;
    }

    if (!import_arg && !report_arg) {
        fprintf(stderr, "Error: at least one of --import or --report is required\n");
        print_usage(argv[0]);
        return 1;
    }

    /* Validate paths */
    const char *db_path = checked_path("--db", db_arg, db_buf, sizeof db_buf);
    const char *import_dir = checked_path("--import", import_arg, import_buf, sizeof import_buf);
    const char *report_path = checked_path("--report", report_arg, report_buf, sizeof report_buf);
    const char *chart_png = checked_path("--chart-png", chart_arg, chart_buf, sizeof chart_buf);

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
        /* If report_path is a directory, generate report-<datetime>.docx inside it */
        char resolved_report[MAX_PATH_LEN];
        struct stat st_rp;
        const char *final_report = report_path;
        if (stat(report_path, &st_rp) == 0 && S_ISDIR(st_rp.st_mode)) {
            time_t now = time(NULL);
            struct tm *tm = gmtime(&now);
            int rl = snprintf(resolved_report, sizeof(resolved_report),
                              "%s/report-%04d%02d%02d%02d%02d.docx",
                              report_path,
                              tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday,
                              tm->tm_hour, tm->tm_min);
            if (rl < 0 || (size_t)rl >= sizeof(resolved_report)) {
                fprintf(stderr, "Error: report path too long\n");
                db_close(&db);
                return 1;
            }
            final_report = resolved_report;
        }
        printf("Generating report: %s\n", final_report);

        timeline_data_t timeline;
        top_changed_data_t top_changed;
        least_changed_data_t least_changed;
        category_data_t categories;
        category_drift_data_t drift;

        memset(&timeline, 0, sizeof(timeline));
        memset(&top_changed, 0, sizeof(top_changed));
        memset(&least_changed, 0, sizeof(least_changed));
        memset(&categories, 0, sizeof(categories));
        memset(&drift, 0, sizeof(drift));

        int qrc = 0;
        printf("  Querying timeline data...\n");
        qrc |= db_query_timeline(&db, &timeline);
        printf("  Timeline: %d data points\n", timeline.count);

        printf("  Querying top-changed packages (all branches)...\n");
        qrc |= db_query_top_changed(&db, &top_changed, 10);
        printf("  Top changed: %d packages\n", top_changed.count);

        printf("  Querying least-changed packages...\n");
        qrc |= db_query_least_changed(&db, &least_changed);
        printf("  Least changed: %d packages\n", least_changed.count);

        printf("  Querying source categories (branch 5.0)...\n");
        qrc |= db_query_categories_branch(&db, &categories, "5.0");
        printf("  Categories: %d groups, %d total packages\n", categories.count, categories.total);

        printf("  Querying category drift...\n");
        qrc |= db_query_category_drift(&db, &drift);
        printf("  Category drift: %d points, %d categories, %d branches\n",
               drift.count, drift.ncategories, drift.nbranches);

        if (qrc != 0) {
            fprintf(stderr, "Warning: some queries failed, report may be incomplete\n");
        }

        if (docx_write_report(final_report, &timeline, &top_changed,
                              &least_changed, &categories, &drift,
                              chart_png) != 0) {
            fprintf(stderr, "Failed to write report\n");
            exit_code = 1;
        } else {
            printf("Report written: %s\n", final_report);
        }

        timeline_data_free(&timeline);
        top_changed_data_free(&top_changed);
        least_changed_data_free(&least_changed);
        category_data_free(&categories);
        category_drift_data_free(&drift);
    }

    db_close(&db);
    return exit_code;
}
