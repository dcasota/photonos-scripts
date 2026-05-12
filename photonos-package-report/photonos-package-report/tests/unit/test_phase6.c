/* test_phase6.c — unit tests for Phase 6a.
 *
 * Coverage:
 *   - pr_state_init / pr_state_free zero-cost lifecycle
 *   - PR_PRN_HEADER bytes match the PS L 5068 literal
 *   - pr_prn_strip drops rows that don't contain a `<spec>.spec`
 *   - pr_prn_open writes the header, append+close round-trips, rows
 *     are sorted ascending and filtered.
 *   - check_urlhealth() returns a row with exactly 11 commas (12
 *     columns) starting with the spec basename.
 *
 * Live HTTP is skipped unless PR_TEST_NETWORK=1.
 */
#include "pr_check_urlhealth.h"
#include "pr_prn.h"
#include "pr_state.h"
#include "pr_types.h"
#include "source0_lookup.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures = 0;

#define EXPECT_STREQ(actual, expected) do {                                    \
    const char *_a = (actual);                                                 \
    const char *_e = (expected);                                               \
    if (_a == NULL || strcmp(_a, _e) != 0) {                                   \
        fprintf(stderr, "  FAIL %s:%d: expected '%s' got '%s'\n",              \
                __FILE__, __LINE__, _e, _a ? _a : "(null)");                   \
        failures++;                                                            \
    }                                                                          \
} while (0)
#define EXPECT_INT(actual, expected) do {                                      \
    long _a = (long)(actual);                                                  \
    long _e = (long)(expected);                                                \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %ld got %ld\n",                \
                __FILE__, __LINE__, _e, _a);                                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --- pr_state lifecycle --------------------------------------------- */
static void test_state(void)
{
    fprintf(stderr, "[test_state]\n");
    pr_state_t s;
    pr_state_init(&s);
    /* All fields point at heap "" — non-NULL, length 0. */
    EXPECT_STREQ(s.Source0,            "");
    EXPECT_STREQ(s.version,            "");
    EXPECT_STREQ(s.UpdateAvailable,    "");
    EXPECT_STREQ(s.UpdateURL,          "");
    EXPECT_STREQ(s.HealthUpdateURL,    "");
    EXPECT_STREQ(s.UpdateDownloadName, "");
    EXPECT_STREQ(s.SHAValue,           "");
    EXPECT_STREQ(s.Warning,            "");
    EXPECT_STREQ(s.ArchivationDate,    "");
    pr_state_free(&s);
}

/* --- header constant ------------------------------------------------- */
static void test_header_literal(void)
{
    fprintf(stderr, "[test_header_literal]\n");
    EXPECT_STREQ(PR_PRN_HEADER,
        "Spec,Source0 original,Modified Source0 for url health check,"
        "UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,"
        "UpdateDownloadName,warning,ArchivationDate");
}

/* --- prn_strip ------------------------------------------------------- */
static void test_strip(void)
{
    fprintf(stderr, "[test_strip]\n");
    /* Row that starts with garbage and then has a spec basename. */
    const char *r = pr_prn_strip("WARN:: hello.spec,a,b,200,...");
    /* The PS regex strips the "WARN:: " prefix and keeps from the spec. */
    if (r == NULL) { failures++; fprintf(stderr, "  FAIL: strip returned NULL on a valid row\n"); }
    else if (strncmp(r, "hello.spec,", 11) != 0) {
        fprintf(stderr, "  FAIL: strip kept '%s'\n", r); failures++;
    }
    /* Row with no `.spec` at all → NULL. */
    if (pr_prn_strip("just,some,comma,data") != NULL) {
        fprintf(stderr, "  FAIL: strip kept a row with no .spec\n"); failures++;
    }
}

/* --- writer round-trip ---------------------------------------------- */
static void test_writer_roundtrip(void)
{
    fprintf(stderr, "[test_writer_roundtrip]\n");
    char tmpl[] = "/tmp/test_phase6_prn_XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) { failures++; return; }
    close(fd);

    pr_prn_t *p = pr_prn_open(tmpl);
    if (!p) { failures++; unlink(tmpl); return; }

    /* Three rows, intentionally unsorted, one a non-match. */
    char *rows[] = {
        (char *)"zsh.spec,,,200,,,,,zsh,,,,",
        (char *)"NOT A ROW WITH SPEC",
        (char *)"abseil-cpp.spec,,,200,,,,,abseil-cpp,,,,",
        (char *)"hello.spec,,,200,,,,,hello,,,,",
    };
    if (pr_prn_append_rows(p, rows, 4) != 0) failures++;
    pr_prn_close(p);

    /* Read back. */
    FILE *r = fopen(tmpl, "rb");
    if (!r) { failures++; unlink(tmpl); return; }
    char line[1024];
    int  lineno = 0;
    const char *expected[] = {
        "Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName,warning,ArchivationDate",
        "abseil-cpp.spec,,,200,,,,,abseil-cpp,,,,",
        "hello.spec,,,200,,,,,hello,,,,",
        "zsh.spec,,,200,,,,,zsh,,,,",
    };
    while (fgets(line, sizeof line, r)) {
        size_t n = strlen(line);
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = '\0';
        if (lineno >= 4) {
            fprintf(stderr, "  FAIL: extra line: %s\n", line); failures++;
            break;
        }
        if (strcmp(line, expected[lineno]) != 0) {
            fprintf(stderr, "  FAIL line %d: expected '%s' got '%s'\n",
                    lineno, expected[lineno], line);
            failures++;
        }
        lineno++;
    }
    if (lineno != 4) {
        fprintf(stderr, "  FAIL: got %d lines, expected 4\n", lineno);
        failures++;
    }
    fclose(r);
    unlink(tmpl);
}

/* --- check_urlhealth row shape -------------------------------------- */
static int count_commas(const char *s)
{
    int n = 0;
    for (; *s; s++) if (*s == ',') n++;
    return n;
}

static void test_check_urlhealth_shape(void)
{
    fprintf(stderr, "[test_check_urlhealth_shape]\n");

    /* Minimal task. */
    pr_task_t t;
    memset(&t, 0, sizeof t);
    t.Spec    = (char *)"hello.spec";
    t.Source0 = (char *)"https://example.invalid/hello-%{version}.tar.gz";
    t.Name    = (char *)"hello";
    t.Version = (char *)"2.10";
    t.url     = (char *)"";

    char *row = check_urlhealth(&t, NULL);
    if (!row) { failures++; fprintf(stderr, "  FAIL: NULL row\n"); return; }
    EXPECT_INT(count_commas(row), 11);  /* 12 cols → 11 commas */
    /* Starts with the spec basename. */
    if (strncmp(row, "hello.spec,", 11) != 0) {
        fprintf(stderr, "  FAIL: row prefix '%s'\n", row); failures++;
    }
    free(row);
}

int main(void)
{
    test_state();
    test_header_literal();
    test_strip();
    test_writer_roundtrip();
    test_check_urlhealth_shape();

    if (failures == 0) {
        fprintf(stderr, "test_phase6: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase6: %d failure(s)\n", failures);
    return 1;
}
