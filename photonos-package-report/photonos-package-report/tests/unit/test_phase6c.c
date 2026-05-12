/* test_phase6c.c — unit tests for Get-LatestName + git_tags parser.
 *
 * Covers PS L 1907-1949 (Get-LatestName) and PS L 2441-2444 (tag-list
 * post-processing).
 */
#include "pr_latest.h"
#include "pr_git_tags.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
#define EXPECT_SZ(actual, expected) do {                                       \
    long _a = (long)(actual); long _e = (long)(expected);                      \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %ld got %ld\n",                \
                __FILE__, __LINE__, _e, _a);                                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --- Get-LatestName -------------------------------------------------- */

static void test_latest_empty(void)
{
    fprintf(stderr, "[test_latest_empty]\n");
    char *out = pr_get_latest_name(NULL, 0);
    EXPECT_STREQ(out, "");
    free(out);

    /* all-blank input. */
    char *blanks[] = { (char *)"", (char *)"   ", (char *)"\t\n" };
    out = pr_get_latest_name(blanks, 3);
    EXPECT_STREQ(out, "");
    free(out);
}

static void test_latest_version_like(void)
{
    fprintf(stderr, "[test_latest_version_like]\n");
    char *names[] = {
        (char *)"1.2.3",
        (char *)"1.10.0",  /* numeric > 1.2.* */
        (char *)"1.9",
    };
    char *out = pr_get_latest_name(names, 3);
    EXPECT_STREQ(out, "1.10.0");
    free(out);

    /* hyphen-separated still matches `^\d+([.-]Q?\d+)*$`. */
    char *names2[] = {
        (char *)"2-10",
        (char *)"3-1",
        (char *)"1-5",
    };
    out = pr_get_latest_name(names2, 3);
    EXPECT_STREQ(out, "3-1");
    free(out);

    /* Quarterly. */
    char *names3[] = {
        (char *)"2023.Q4.5",
        (char *)"2024.Q1.0",
        (char *)"2023.Q1.99",
    };
    out = pr_get_latest_name(names3, 3);
    EXPECT_STREQ(out, "2024.Q1.0");
    free(out);
}

static void test_latest_non_version(void)
{
    fprintf(stderr, "[test_latest_non_version]\n");
    /* No name matches `^\d+([.-]Q?\d+)*$`. PS falls back to lex sort
     * + Select-Object -Last 1. */
    char *names[] = {
        (char *)"v1.0",
        (char *)"release-2023",
        (char *)"abc",
    };
    char *out = pr_get_latest_name(names, 3);
    /* lex order: "abc" < "release-2023" < "v1.0" → last is "v1.0". */
    EXPECT_STREQ(out, "v1.0");
    free(out);
}

static void test_latest_mixed(void)
{
    fprintf(stderr, "[test_latest_mixed]\n");
    /* When ANY version-like name exists, only those are considered. */
    char *names[] = {
        (char *)"v1.99",   /* skipped — has 'v' */
        (char *)"1.2.3",   /* selected */
        (char *)"release", /* skipped */
        (char *)"1.10",    /* selected — winner */
    };
    char *out = pr_get_latest_name(names, 4);
    EXPECT_STREQ(out, "1.10");
    free(out);
}

/* --- pr_parse_tag_list ----------------------------------------------- */

static void test_parse_basic(void)
{
    fprintf(stderr, "[test_parse_basic]\n");
    const char *git = "v1.0\nv1.1\n\n  v1.2  \r\nrelease-2023\n";
    char **names = NULL; size_t n = 0;
    int rc = pr_parse_tag_list(git, NULL, &names, &n);
    EXPECT_SZ(rc, 0);
    EXPECT_SZ(n, 4);
    if (n == 4) {
        EXPECT_STREQ(names[0], "v1.0");
        EXPECT_STREQ(names[1], "v1.1");
        EXPECT_STREQ(names[2], "v1.2");          /* spaces stripped */
        EXPECT_STREQ(names[3], "release-2023");
    }
    pr_git_tags_free(names, n);
}

static void test_parse_regex_filter(void)
{
    fprintf(stderr, "[test_parse_regex_filter]\n");
    const char *git = "v1.0\nfoo\nv2.0\nbar\n";
    char **names = NULL; size_t n = 0;
    int rc = pr_parse_tag_list(git, "^v\\d", &names, &n);
    EXPECT_SZ(rc, 0);
    EXPECT_SZ(n, 2);
    if (n == 2) {
        EXPECT_STREQ(names[0], "v1.0");
        EXPECT_STREQ(names[1], "v2.0");
    }
    pr_git_tags_free(names, n);
}

static void test_parse_empty_input(void)
{
    fprintf(stderr, "[test_parse_empty_input]\n");
    char **names = (char **)0x1; size_t n = 42;
    int rc = pr_parse_tag_list("", NULL, &names, &n);
    EXPECT_SZ(rc, 0);
    EXPECT_SZ(n, 0);
    pr_git_tags_free(names, n);

    /* NULL input. */
    char **n2 = (char **)0x1; size_t cnt2 = 42;
    rc = pr_parse_tag_list(NULL, NULL, &n2, &cnt2);
    EXPECT_SZ(rc, 0);
    EXPECT_SZ(cnt2, 0);
    /* names is NULL on empty/null input */
}

int main(void)
{
    test_latest_empty();
    test_latest_version_like();
    test_latest_non_version();
    test_latest_mixed();
    test_parse_basic();
    test_parse_regex_filter();
    test_parse_empty_input();

    if (failures == 0) {
        fprintf(stderr, "test_phase6c: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase6c: %d failure(s)\n", failures);
    return 1;
}
