#include "db.h"
#include "docx_writer.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) do { printf("  TEST: %s ... ", #name); } while(0)
#define PASS() do { printf("PASS\n"); tests_passed++; } while(0)
#define FAIL(msg) do { printf("FAIL: %s\n", msg); tests_failed++; } while(0)

static void test_schema_creation(void)
{
    TEST(schema_creation);
    const char *dbpath = "/tmp/test_schema.db";
    unlink(dbpath);

    db_t db;
    if (db_open(&db, dbpath) != 0) { FAIL("db_open"); return; }
    if (db_init_schema(&db) != 0) { FAIL("db_init_schema"); db_close(&db); unlink(dbpath); return; }

    /* Verify tables exist */
    if (!db_scan_file_exists(&db, "nonexistent.prn") &&
        db_scan_file_exists(&db, "nonexistent.prn") == 0) {
        PASS();
    } else {
        FAIL("scan_file_exists on empty db");
    }
    db_close(&db);
    unlink(dbpath);
}

static void test_dedup(void)
{
    TEST(duplicate_detection);
    const char *dbpath = "/tmp/test_dedup.db";
    unlink(dbpath);

    db_t db;
    db_open(&db, dbpath);
    db_init_schema(&db);

    long long id1 = db_insert_scan_file(&db, "test.prn", "5.0", "202603150144", "abc123", 12);
    if (id1 < 0) { FAIL("first insert"); db_close(&db); unlink(dbpath); return; }

    if (!db_scan_file_exists(&db, "test.prn")) { FAIL("should exist"); db_close(&db); unlink(dbpath); return; }

    /* Insert duplicate should fail (UNIQUE constraint) */
    long long id2 = db_insert_scan_file(&db, "test.prn", "5.0", "202603150144", "abc123", 12);
    if (id2 >= 0) { FAIL("duplicate should fail"); db_close(&db); unlink(dbpath); return; }

    PASS();
    db_close(&db);
    unlink(dbpath);
}

static void test_insert_packages(void)
{
    TEST(insert_packages);
    const char *dbpath = "/tmp/test_pkgs.db";
    unlink(dbpath);

    db_t db;
    db_open(&db, dbpath);
    db_init_schema(&db);

    long long scan_id = db_insert_scan_file(&db, "test-pkg.prn", "5.0", "202603150144", "sha256hash", 12);

    csv_data_t data;
    memset(&data, 0, sizeof(data));
    data.count = 2;
    data.rows = calloc(2, sizeof(csv_row_t));

    data.rows[0].spec = strdup("test.spec");
    data.rows[0].name = strdup("test");
    data.rows[0].url_health = strdup("200");
    data.rows[0].update_available = strdup("1.1");
    data.rows[0].update_download_name = strdup("test-1.1.tar.gz");

    data.rows[1].spec = strdup("foo.spec");
    data.rows[1].name = strdup("foo");
    data.rows[1].url_health = strdup("0");

    if (db_insert_packages(&db, scan_id, &data) != 0) {
        FAIL("insert_packages failed");
    } else {
        PASS();
    }

    csv_data_free(&data);
    db_close(&db);
    unlink(dbpath);
}

static void test_queries(void)
{
    TEST(report_queries);
    const char *dbpath = "/tmp/test_queries.db";
    unlink(dbpath);

    db_t db;
    db_open(&db, dbpath);
    db_init_schema(&db);

    /* Insert two scans for branch 5.0 */
    long long s1 = db_insert_scan_file(&db, "scan1.prn", "5.0", "202301010000", "sha1", 12);
    long long s2 = db_insert_scan_file(&db, "scan2.prn", "5.0", "202402010000", "sha2", 12);

    csv_data_t d1, d2;
    memset(&d1, 0, sizeof(d1));
    memset(&d2, 0, sizeof(d2));
    d1.count = 1;
    d1.rows = calloc(1, sizeof(csv_row_t));
    d1.rows[0].spec = strdup("pkg.spec");
    d1.rows[0].name = strdup("pkg");
    d1.rows[0].url_health = strdup("200");
    d1.rows[0].update_available = strdup("1.0");
    d1.rows[0].update_download_name = strdup("pkg-1.0.tar.gz");
    d1.rows[0].source0_original = strdup("https://github.com/test/pkg/archive/1.0.tar.gz");
    db_insert_packages(&db, s1, &d1);

    d2.count = 1;
    d2.rows = calloc(1, sizeof(csv_row_t));
    d2.rows[0].spec = strdup("pkg.spec");
    d2.rows[0].name = strdup("pkg");
    d2.rows[0].url_health = strdup("200");
    d2.rows[0].update_available = strdup("2.0");
    d2.rows[0].update_download_name = strdup("pkg-2.0.tar.gz");
    d2.rows[0].source0_original = strdup("https://github.com/test/pkg/archive/2.0.tar.gz");
    db_insert_packages(&db, s2, &d2);

    /* Test timeline query */
    timeline_data_t tl;
    if (db_query_timeline(&db, &tl) != 0 || tl.count == 0) {
        FAIL("timeline query empty");
    } else {
        /* Test categories query */
        category_data_t cat;
        if (db_query_categories(&db, &cat) != 0 || cat.count == 0) {
            FAIL("categories query empty");
        } else {
            int found_github = 0;
            for (int i = 0; i < cat.count; i++) {
                if (strcmp(cat.items[i].category, "github.com") == 0)
                    found_github = 1;
            }
            if (found_github)
                PASS();
            else
                FAIL("github.com category not found");
            category_data_free(&cat);
        }
        timeline_data_free(&tl);
    }

    csv_data_free(&d1);
    csv_data_free(&d2);
    db_close(&db);
    unlink(dbpath);
}

static void test_docx_generation(void)
{
    TEST(docx_generation);
    const char *docxpath = "/tmp/test_output.docx";
    unlink(docxpath);

    /* Create minimal test data */
    timeline_data_t tl;
    memset(&tl, 0, sizeof(tl));
    tl.count = 2;
    tl.points = calloc(2, sizeof(timeline_point_t));
    secure_strncpy(tl.points[0].branch, "5.0", sizeof(tl.points[0].branch));
    secure_strncpy(tl.points[0].scan_datetime, "202301", sizeof(tl.points[0].scan_datetime));
    tl.points[0].qualifying_count = 42;
    secure_strncpy(tl.points[1].branch, "5.0", sizeof(tl.points[1].branch));
    secure_strncpy(tl.points[1].scan_datetime, "202402", sizeof(tl.points[1].scan_datetime));
    tl.points[1].qualifying_count = 55;

    top_changed_data_t tc;
    memset(&tc, 0, sizeof(tc));

    least_changed_data_t lc;
    memset(&lc, 0, sizeof(lc));

    category_data_t cat;
    memset(&cat, 0, sizeof(cat));
    cat.count = 2;
    cat.total = 100;
    cat.items = calloc(2, sizeof(category_t));
    secure_strncpy(cat.items[0].category, "github.com", sizeof(cat.items[0].category));
    cat.items[0].count = 70;
    cat.items[0].percentage = 70.0;
    secure_strncpy(cat.items[1].category, "Other", sizeof(cat.items[1].category));
    cat.items[1].count = 30;
    cat.items[1].percentage = 30.0;

    category_drift_data_t drift;
    memset(&drift, 0, sizeof(drift));

    int rc = docx_write_report(docxpath, &tl, &tc, &lc, &cat, &drift);
    if (rc != 0) {
        FAIL("docx_write_report failed");
    } else {
        FILE *f = fopen(docxpath, "rb");
        if (!f) { FAIL("output file not created"); }
        else {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            fclose(f);
            if (sz > 100)
                PASS();
            else
                FAIL("output file too small");
        }
    }

    free(tl.points);
    free(cat.items);
    unlink(docxpath);
}

int main(void)
{
    printf("=== DB Tests ===\n");
    test_schema_creation();
    test_dedup();
    test_insert_packages();
    test_queries();
    test_docx_generation();

    printf("\nResults: %d passed, %d failed\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
