/* test_phase6e.c — unit tests for HeapSort, Get-HighestJdkVersion,
 * pr_basename_from_url.
 */
#include "pr_heapsort.h"
#include "pr_jdk.h"
#include "pr_url_util.h"

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
#define EXPECT_NULL(actual) do {                                               \
    if ((actual) != NULL) {                                                    \
        fprintf(stderr, "  FAIL %s:%d: expected NULL\n", __FILE__, __LINE__);  \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --- HeapSort ------------------------------------------------------- */

static void test_heapsort_short(void)
{
    fprintf(stderr, "[test_heapsort_short]\n");
    /* All inputs ≤ 6 bytes — int64 key fits, sort matches strcmp. */
    char *a = strdup("v1.0");
    char *b = strdup("v0.5");
    char *c = strdup("v2.1");
    char *arr[] = { a, b, c };
    pr_heapsort_strings(arr, 3);
    /* Ascending → max is last. */
    EXPECT_STREQ(arr[2], "v2.1");
    EXPECT_STREQ(arr[0], "v0.5");
    free(a); free(b); free(c);
}

static void test_heapsort_single(void)
{
    fprintf(stderr, "[test_heapsort_single]\n");
    char *a = strdup("only");
    char *arr[] = { a };
    pr_heapsort_strings(arr, 1);
    EXPECT_STREQ(arr[0], "only");
    free(a);
}

/* --- Get-HighestJdkVersion ----------------------------------------- */

static void test_jdk_basic(void)
{
    fprintf(stderr, "[test_jdk_basic]\n");
    char *names[] = {
        (char *)"jdk-11.0.27+10",
        (char *)"jdk-11.0.28+6",
        (char *)"jdk-11.0.28-ga",     /* GA wins tie on patch */
        (char *)"jdk-11.0.27-ga",
        (char *)"openjdk-irrelevant", /* skipped — wrong prefix */
        (char *)"jdk-17.0.1+0",       /* skipped — major filter is jdk-11 */
    };
    char *w = pr_get_highest_jdk_version(names, 6, 11, "jdk-11");
    /* Among 11.0.27+10 / 11.0.28+6 / 11.0.28-ga / 11.0.27-ga:
     *   sort desc by major(=11), minor(=0), patch -> 28 > 27 first;
     *   among 28: ga vs +6 → ga wins (is_ga=1 sorts before is_ga=0).
     * Original "jdk-11.0.28-ga" → strip "jdk-" → "11.0.28-ga". */
    EXPECT_STREQ(w, "11.0.28-ga");
    free(w);
}

static void test_jdk_bare_major(void)
{
    fprintf(stderr, "[test_jdk_bare_major]\n");
    char *names[] = {
        (char *)"jdk-11",
        (char *)"jdk-11+28",
        (char *)"jdk-11.0+0",
    };
    char *w = pr_get_highest_jdk_version(names, 3, 11, "jdk-11");
    /* All major=11, minor=0, patch=0. Tiebreaker on Build:
     *   jdk-11+28 (build=28) > jdk-11.0+0 (build=0) > jdk-11 (build=0). */
    EXPECT_STREQ(w, "11+28");
    free(w);
}

static void test_jdk_no_match(void)
{
    fprintf(stderr, "[test_jdk_no_match]\n");
    char *names[] = { (char *)"openjdk-21", (char *)"jdk-17+1" };
    /* Both miss "jdk-11" prefix → NULL. */
    EXPECT_NULL(pr_get_highest_jdk_version(names, 2, 11, "jdk-11"));
}

/* --- pr_basename_from_url ------------------------------------------- */

static void test_basename_simple(void)
{
    fprintf(stderr, "[test_basename_simple]\n");
    char *b = pr_basename_from_url("https://example.invalid/foo/bar-1.0.tar.gz");
    EXPECT_STREQ(b, "bar-1.0.tar.gz"); free(b);
}

static void test_basename_sourceforge(void)
{
    fprintf(stderr, "[test_basename_sourceforge]\n");
    char *b = pr_basename_from_url(
        "https://sourceforge.net/projects/foo/files/foo-1.0.tar.gz/download");
    /* PS quirk: /download suffix → penultimate segment. */
    EXPECT_STREQ(b, "foo-1.0.tar.gz"); free(b);
}

static void test_basename_edge(void)
{
    fprintf(stderr, "[test_basename_edge]\n");
    EXPECT_NULL(pr_basename_from_url(NULL));
    EXPECT_NULL(pr_basename_from_url(""));

    char *b = pr_basename_from_url("noslash.tar.gz");
    EXPECT_STREQ(b, "noslash.tar.gz"); free(b);

    /* Trailing slash → empty basename (last segment is empty). */
    b = pr_basename_from_url("https://example.invalid/");
    EXPECT_STREQ(b, ""); free(b);
}

int main(void)
{
    test_heapsort_short();
    test_heapsort_single();
    test_jdk_basic();
    test_jdk_bare_major();
    test_jdk_no_match();
    test_basename_simple();
    test_basename_sourceforge();
    test_basename_edge();

    if (failures == 0) {
        fprintf(stderr, "test_phase6e: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase6e: %d failure(s)\n", failures);
    return 1;
}
