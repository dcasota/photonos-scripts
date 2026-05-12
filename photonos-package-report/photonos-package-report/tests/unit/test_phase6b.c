/* test_phase6b.c — unit tests for Parse-Version + Compare-VersionStrings.
 *
 * Covers all 6 Parse-Version variants and all 8 Compare rules.
 */
#include "pr_version.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define EXPECT_INT(actual, expected) do {                                      \
    long _a = (long)(actual);                                                  \
    long _e = (long)(expected);                                                \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %ld got %ld\n",                \
                __FILE__, __LINE__, _e, _a);                                   \
        failures++;                                                            \
    }                                                                          \
} while (0)
#define EXPECT_STREQ(actual, expected) do {                                    \
    const char *_a = (actual);                                                 \
    const char *_e = (expected);                                               \
    if (_a == NULL || strcmp(_a, _e) != 0) {                                   \
        fprintf(stderr, "  FAIL %s:%d: expected '%s' got '%s'\n",              \
                __FILE__, __LINE__, _e, _a ? _a : "(null)");                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

static void test_parse_date_version(void)
{
    fprintf(stderr, "[test_parse_date_version]\n");
    pr_version_t v = {0};
    pr_version_parse("20240101-1.2", &v);
    EXPECT_INT(v.type, PR_VER_DATE_VERSION);
    EXPECT_INT(v.date, 20240101);
    EXPECT_STREQ(v.version_number, "1.2");
    pr_version_free(&v);
}

static void test_parse_version_date(void)
{
    fprintf(stderr, "[test_parse_version_date]\n");
    pr_version_t v = {0};
    pr_version_parse("1.2.20240101", &v);
    EXPECT_INT(v.type, PR_VER_VERSION_DATE);
    EXPECT_INT(v.date, 20240101);
    EXPECT_STREQ(v.version_number, "1.2");
    pr_version_free(&v);
}

static void test_parse_quarterly(void)
{
    fprintf(stderr, "[test_parse_quarterly]\n");
    pr_version_t v = {0};
    pr_version_parse("2024.Q1.7", &v);
    EXPECT_INT(v.type, PR_VER_STANDARD);
    EXPECT_INT(v.n_components, 3);
    EXPECT_INT(v.components[0], 2024);
    EXPECT_INT(v.components[1], 1);
    EXPECT_INT(v.components[2], 7);
    pr_version_free(&v);
}

static void test_parse_standard(void)
{
    fprintf(stderr, "[test_parse_standard]\n");
    pr_version_t v = {0};
    pr_version_parse("1.2.3.4", &v);
    EXPECT_INT(v.type, PR_VER_STANDARD);
    EXPECT_INT(v.n_components, 4);
    EXPECT_INT(v.components[0], 1);
    EXPECT_INT(v.components[1], 2);
    EXPECT_INT(v.components[2], 3);
    EXPECT_INT(v.components[3], 4);
    pr_version_free(&v);

    /* hyphen normalised to dot. */
    pr_version_t v2 = {0};
    pr_version_parse("2.10-1", &v2);
    EXPECT_INT(v2.type, PR_VER_STANDARD);
    EXPECT_INT(v2.n_components, 3);
    EXPECT_INT(v2.components[0], 2);
    EXPECT_INT(v2.components[1], 10);
    EXPECT_INT(v2.components[2], 1);
    pr_version_free(&v2);
}

static void test_parse_letter_embed(void)
{
    fprintf(stderr, "[test_parse_letter_embed]\n");
    pr_version_t v = {0};
    pr_version_parse("1.9.15p5", &v);
    EXPECT_INT(v.type, PR_VER_STANDARD);
    EXPECT_INT(v.n_components, 4);
    EXPECT_INT(v.components[0], 1);
    EXPECT_INT(v.components[1], 9);
    EXPECT_INT(v.components[2], 15);
    EXPECT_INT(v.components[3], 5);
    pr_version_free(&v);
}

static void test_parse_integer(void)
{
    fprintf(stderr, "[test_parse_integer]\n");
    pr_version_t v = {0};
    pr_version_parse("018", &v);
    EXPECT_INT(v.type, PR_VER_INTEGER);
    EXPECT_INT(v.int_value, 18);  /* leading zeros trimmed */
    pr_version_free(&v);

    pr_version_t v2 = {0};
    pr_version_parse("0", &v2);
    EXPECT_INT(v2.type, PR_VER_INTEGER);
    EXPECT_INT(v2.int_value, 0);
    pr_version_free(&v2);
}

static void test_parse_decimal(void)
{
    fprintf(stderr, "[test_parse_decimal]\n");

    /* PS-quirk preserved (CLAUDE.md invariant #2): the PS author's
     * comment in front of Case 5 says "Decimal numeric (e.g., 0.91)",
     * but the earlier `^\d+(\.\d+)+$` (Case 3 / StandardVersion) ALSO
     * matches "0.91", so PS classifies it as StandardVersion with
     * components [0, 91]. We mirror that. */
    pr_version_t v = {0};
    pr_version_parse("0.91", &v);
    EXPECT_INT(v.type, PR_VER_STANDARD);
    EXPECT_INT(v.n_components, 2);
    EXPECT_INT(v.components[0], 0);
    EXPECT_INT(v.components[1], 91);
    pr_version_free(&v);

    /* A genuine Case 5 hit needs a shape that bypasses Cases 1-4. PS
     * normalises '-' to '.', strips leading zeros, then calls
     * double.TryParse — scientific notation hits this branch. */
    pr_version_t v2 = {0};
    pr_version_parse("5e2", &v2);
    EXPECT_INT(v2.type, PR_VER_DECIMAL);
    if (v2.dec_value < 499.9 || v2.dec_value > 500.1) {
        fprintf(stderr, "  FAIL: 5e2 dec_value = %.4f\n", v2.dec_value); failures++;
    }
    pr_version_free(&v2);

    /* String fallback when nothing parses. */
    pr_version_t v3 = {0};
    pr_version_parse("not-a-version", &v3);
    EXPECT_INT(v3.type, PR_VER_STRING);
    EXPECT_STREQ(v3.str_value, "not-a-version");
    pr_version_free(&v3);
}

/* --- Compare rules -------------------------------------------------- */

#define EXPECT_CMP(a, b, expected) do {                                        \
    int _c = pr_version_compare((a), (b));                                     \
    if (_c != (expected)) {                                                    \
        fprintf(stderr, "  FAIL %s:%d: cmp('%s','%s') = %d, expected %d\n",    \
                __FILE__, __LINE__, (a), (b), _c, (expected));                 \
        failures++;                                                            \
    }                                                                          \
} while (0)

static void test_compare(void)
{
    fprintf(stderr, "[test_compare]\n");

    /* Rule 1: Both date-based. */
    EXPECT_CMP("20240101-1.2", "20231231-9.9",  1);
    EXPECT_CMP("20231231-1.2", "20240101-1.2", -1);
    EXPECT_CMP("20240101-1.2", "20240101-1.2",  0);
    /* same date, lex VersionNumber */
    EXPECT_CMP("20240101-1.3", "20240101-1.2",  1);

    /* Rule 2: Date-based vs not. */
    EXPECT_CMP("20240101-1.2", "1.2.3",  1);
    EXPECT_CMP("1.2.3",        "1.2.20240101", -1);

    /* Rule 3: Both StandardVersion. */
    EXPECT_CMP("1.2.3",  "1.2.4", -1);
    EXPECT_CMP("1.2.3",  "1.2.3",  0);
    EXPECT_CMP("1.2.3",  "1.2",    1);    /* extra component as zero */
    EXPECT_CMP("1.10",   "1.9",    1);    /* numeric, not lex */
    EXPECT_CMP("2.10-1", "2.10",   1);    /* hyphen → dot, extra 1 */

    /* Rule 4: Both Integer. */
    EXPECT_CMP("018", "017",  1);
    EXPECT_CMP("000", "0",    0);

    /* Rule 5: Both Decimal. */
    EXPECT_CMP("0.91", "0.9",   1);
    EXPECT_CMP("0.91", "0.91",  0);

    /* Rule 7: Standard vs Integer compares Components[0] vs Integer. */
    EXPECT_CMP("3.2.1", "2",  1);
    EXPECT_CMP("2.2.1", "3", -1);
    EXPECT_CMP("2.2.1", "2",  0);  /* tied on first component */
}

int main(void)
{
    test_parse_date_version();
    test_parse_version_date();
    test_parse_quarterly();
    test_parse_standard();
    test_parse_letter_embed();
    test_parse_integer();
    test_parse_decimal();
    test_compare();

    if (failures == 0) {
        fprintf(stderr, "test_phase6b: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase6b: %d failure(s)\n", failures);
    return 1;
}
