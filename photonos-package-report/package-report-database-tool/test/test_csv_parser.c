#include "csv_parser.h"
#include "security.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) do { printf("  TEST: %s ... ", #name); } while(0)
#define PASS() do { printf("PASS\n"); tests_passed++; } while(0)
#define FAIL(msg) do { printf("FAIL: %s\n", msg); tests_failed++; } while(0)

static void test_utf16le_to_utf8(void)
{
    TEST(utf16le_to_utf8_basic);
    /* "AB" in UTF-16LE with BOM: FF FE 41 00 42 00 */
    unsigned char buf[] = {0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00};
    char *out = utf16le_to_utf8(buf, sizeof(buf));
    if (out && strcmp(out, "AB") == 0)
        PASS();
    else
        FAIL("Expected 'AB'");
    free(out);
}

static void test_utf16le_empty(void)
{
    TEST(utf16le_to_utf8_bom_only);
    unsigned char buf[] = {0xFF, 0xFE};
    char *out = utf16le_to_utf8(buf, sizeof(buf));
    if (out && strlen(out) == 0)
        PASS();
    else
        FAIL("Expected empty string");
    free(out);
}

static void test_parse_utf8_12col(void)
{
    TEST(parse_utf8_12col_file);
    /* Create a temp file with 12-column header */
    const char *tmpfile = "/tmp/test_parse_12col.prn";
    FILE *f = fopen(tmpfile, "w");
    if (!f) { FAIL("Cannot create temp file"); return; }
    fprintf(f, "Spec,Source0 original,Modified Source0,UrlHealth,UpdateAvailable,"
               "UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName,warning,ArchivationDate\n");
    fprintf(f, "test.spec,http://example.com/test-1.0.tar.gz,http://example.com/test-1.0.tar.gz,"
               "200,1.1,http://example.com/test-1.1.tar.gz,200,test,ABCD,test-1.1.tar.gz,,\n");
    fprintf(f, "foo.spec,http://example.com/foo-2.0.tar.gz,,0,,,,foo,,,Info: VMware internal,\n");
    fclose(f);

    csv_data_t data;
    int rc = csv_parse_file(tmpfile, &data);
    if (rc != 0) { FAIL("parse returned error"); remove(tmpfile); return; }
    if (data.schema_version != CSV_SCHEMA_NEW) { FAIL("wrong schema version"); csv_data_free(&data); remove(tmpfile); return; }
    if (data.count != 2) { FAIL("expected 2 rows"); csv_data_free(&data); remove(tmpfile); return; }

    if (!data.rows[0].spec || strcmp(data.rows[0].spec, "test.spec") != 0) {
        FAIL("row 0 spec mismatch"); csv_data_free(&data); remove(tmpfile); return;
    }
    if (!data.rows[0].update_download_name || strcmp(data.rows[0].update_download_name, "test-1.1.tar.gz") != 0) {
        FAIL("row 0 update_download_name mismatch"); csv_data_free(&data); remove(tmpfile); return;
    }
    if (!data.rows[1].warning || strstr(data.rows[1].warning, "VMware") == NULL) {
        FAIL("row 1 warning mismatch"); csv_data_free(&data); remove(tmpfile); return;
    }

    csv_data_free(&data);
    remove(tmpfile);
    PASS();
}

static void test_parse_5col(void)
{
    TEST(parse_utf8_5col_file);
    const char *tmpfile = "/tmp/test_parse_5col.prn";
    FILE *f = fopen(tmpfile, "w");
    if (!f) { FAIL("Cannot create temp file"); return; }
    fprintf(f, "Spec,Source0 original,Recent Source0 modified,UrlHealth,UpdateAvailable\n");
    fprintf(f, "acl.spec,http://example.com/acl.tar.gz,http://example.com/acl-2.0.tar.gz,200,2.1\n");
    fclose(f);

    csv_data_t data;
    int rc = csv_parse_file(tmpfile, &data);
    if (rc != 0) { FAIL("parse returned error"); remove(tmpfile); return; }
    if (data.schema_version != CSV_SCHEMA_OLD) { FAIL("wrong schema version"); csv_data_free(&data); remove(tmpfile); return; }
    if (data.count != 1) { FAIL("expected 1 row"); csv_data_free(&data); remove(tmpfile); return; }
    if (!data.rows[0].name || strcmp(data.rows[0].name, "acl") != 0) {
        FAIL("derived name mismatch"); csv_data_free(&data); remove(tmpfile); return;
    }

    csv_data_free(&data);
    remove(tmpfile);
    PASS();
}

static void test_empty_file(void)
{
    TEST(parse_empty_file);
    const char *tmpfile = "/tmp/test_empty.prn";
    FILE *f = fopen(tmpfile, "w");
    if (!f) { FAIL("could not create empty tmp file"); return; }
    fclose(f);

    csv_data_t data;
    int rc = csv_parse_file(tmpfile, &data);
    if (rc != 0)
        PASS();
    else {
        FAIL("should fail on empty file");
        csv_data_free(&data);
    }
    remove(tmpfile);
}

static void test_xml_escape(void)
{
    TEST(xml_escape);
    char *esc = secure_xml_escape("test <&> \"hello'");
    if (esc && strcmp(esc, "test &lt;&amp;&gt; &quot;hello&apos;") == 0)
        PASS();
    else
        FAIL("escape mismatch");
    free(esc);
}

static void test_validate_filename(void)
{
    TEST(validate_filename);
    if (secure_validate_filename("photonos-urlhealth-5.0_202603150144.prn") == 0 &&
        secure_validate_filename("../evil.prn") != 0 &&
        secure_validate_filename("path/file.prn") != 0 &&
        secure_validate_filename("") != 0)
        PASS();
    else
        FAIL("validation mismatch");
}

int main(void)
{
    printf("=== CSV Parser Tests ===\n");
    test_utf16le_to_utf8();
    test_utf16le_empty();
    test_parse_utf8_12col();
    test_parse_5col();
    test_empty_file();
    test_xml_escape();
    test_validate_filename();

    printf("\nResults: %d passed, %d failed\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
