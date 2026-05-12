/* test_phase6f.c — unit tests for SHA helpers + cross-branch diff report. */
#include "pr_sha.h"
#include "pr_diff_report.h"
#include "pr_types.h"

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
    long _a = (long)(actual); long _e = (long)(expected);                      \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %ld got %ld\n",                \
                __FILE__, __LINE__, _e, _a);                                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* --- SHA helpers ---------------------------------------------------- */

static void test_sha_hex(void)
{
    fprintf(stderr, "[test_sha_hex]\n");
    /* Reference vectors from RFC 3174 / NIST: "abc" */
    char *s = pr_sha_hex(PR_SHA1, "abc", 3);
    EXPECT_STREQ(s, "A9993E364706816ABA3E25717850C26C9CD0D89D");
    free(s);

    s = pr_sha_hex(PR_SHA256, "abc", 3);
    EXPECT_STREQ(s,
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD");
    free(s);

    s = pr_sha_hex(PR_SHA512, "abc", 3);
    EXPECT_STREQ(s,
        "DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A"
        "2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F");
    free(s);
}

static void test_sha_file(void)
{
    fprintf(stderr, "[test_sha_file]\n");
    char tmpl[] = "/tmp/pr_sha_test_XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) { failures++; return; }
    const char *bytes = "abc";
    if (write(fd, bytes, 3) != 3) { failures++; close(fd); unlink(tmpl); return; }
    close(fd);

    char *s = pr_sha_file(PR_SHA256, tmpl);
    EXPECT_STREQ(s,
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD");
    free(s);
    unlink(tmpl);
}

/* --- diff_report ---------------------------------------------------- */

/* Test fixture: build a pr_task_list_t with a few known (Spec, Version,
 * SubRelease) tuples. Field ownership: every string is heap-alloc'd. */
static char *xs(const char *s) { return s ? strdup(s) : NULL; }

static void add_task(pr_task_list_t *L,
                     const char *spec, const char *version,
                     const char *subrel)
{
    pr_task_t t = {0};
    t.Spec       = xs(spec);
    t.Version    = xs(version);
    t.SubRelease = xs(subrel ? subrel : "");
    t.Name       = xs("");
    pr_task_list_add(L, &t);
}

static void test_diff_report(void)
{
    fprintf(stderr, "[test_diff_report]\n");

    pr_task_list_t a, b;
    pr_task_list_init(&a);
    pr_task_list_init(&b);

    /* hello: 2.10 vs 2.5     → emit (a > b) */
    /* dbus:  1.12 vs 1.13    → suppress (a < b) */
    /* kernel: 6.6 vs 6.6     → suppress (equal) */
    /* zlib: 1.3 vs <missing> → suppress (no counterpart in b) */
    /* foo SubRelease in a    → suppress (subrelease guard) */
    add_task(&a, "hello.spec",  "2.10",  NULL);
    add_task(&b, "hello.spec",  "2.5",   NULL);
    add_task(&a, "dbus.spec",   "1.12",  NULL);
    add_task(&b, "dbus.spec",   "1.13",  NULL);
    add_task(&a, "kernel.spec", "6.6",   NULL);
    add_task(&b, "kernel.spec", "6.6",   NULL);
    add_task(&a, "zlib.spec",   "1.3",   NULL);
    add_task(&a, "foo.spec",    "9.9",   "91");
    add_task(&b, "foo.spec",    "1.0",   NULL);

    char path[] = "/tmp/pr_diff_test_XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) { failures++; goto cleanup; }
    close(fd);

    int rc = pr_write_diff_report(&a, &b, "photon-5.0", "photon-6.0", path);
    EXPECT_INT(rc, 0);

    FILE *f = fopen(path, "rb");
    if (!f) { failures++; goto cleanup_path; }
    char buf[1024]; size_t n = fread(buf, 1, sizeof buf - 1, f); buf[n] = '\0';
    fclose(f);

    const char *expected =
        "Spec,photon-5.0,photon-6.0\n"
        "hello.spec,2.10,2.5\n";
    if (strcmp(buf, expected) != 0) {
        fprintf(stderr, "  FAIL: diff content mismatch\nGOT:\n%s\nEXPECTED:\n%s\n",
                buf, expected);
        failures++;
    }

cleanup_path:
    unlink(path);
cleanup:
    pr_task_list_free(&a);
    pr_task_list_free(&b);
}

int main(void)
{
    test_sha_hex();
    test_sha_file();
    test_diff_report();

    if (failures == 0) {
        fprintf(stderr, "test_phase6f: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase6f: %d failure(s)\n", failures);
    return 1;
}
