/* test_phase1.c — Phase 1 unit tests.
 *
 * Covers convert_to_boolean (PS L 111-118), test_disk_space (PS L 133-160),
 * and a smoke check of invoke_git_with_timeout (PS L 163-231).
 *
 * Each assertion explicitly references the PS source line it validates so
 * a future reader can verify the C port still matches PS semantics.
 */
#include "photonos_package_report.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int failed = 0;
#define CHECK(name, cond) do {                                                 \
    if (cond) { printf("  ok    %s\n", name); }                                \
    else      { printf("  FAIL  %s\n", name); failed++; }                      \
} while (0)

static void test_convert_to_boolean(void)
{
    printf("== convert_to_boolean (PS L 111-118) ==\n");
    /* PS rule: $true / true / 1 → true */
    CHECK("'$true' -> 1",  convert_to_boolean("$true")  == 1);
    CHECK("'true'  -> 1",  convert_to_boolean("true")   == 1);
    CHECK("'1'     -> 1",  convert_to_boolean("1")      == 1);
    /* PS rule: $false / false / 0 → false */
    CHECK("'$false' -> 0", convert_to_boolean("$false") == 0);
    CHECK("'false'  -> 0", convert_to_boolean("false")  == 0);
    CHECK("'0'      -> 0", convert_to_boolean("0")      == 0);
    /* Case-insensitive: PS -eq on strings is OrdinalIgnoreCase */
    CHECK("'TRUE'   -> 1", convert_to_boolean("TRUE")   == 1);
    CHECK("'False'  -> 0", convert_to_boolean("False")  == 0);
    /* [bool] cast fallback: any non-empty value is true */
    CHECK("'yes'    -> 1", convert_to_boolean("yes")    == 1);
    /* Null / empty → false (PS [bool]$null / [bool]"" === $false) */
    CHECK("NULL     -> 0", convert_to_boolean(NULL)     == 0);
    CHECK("''       -> 0", convert_to_boolean("")       == 0);
}

static void test_test_disk_space(void)
{
    printf("== test_disk_space (PS L 133-160) ==\n");
    /* Requiring 0 MB on a known-existing path should always succeed. */
    CHECK("0 MB on /tmp -> 1",   test_disk_space("/tmp", 0L, "smoke") == 1);
    /* Non-existent path: PS catches and returns true ("- proceeding"). */
    CHECK("nonexistent -> 1",    test_disk_space("/no/such/path", 100L, "neg") == 1);
    /* Requiring 1 PB should fail on any sane filesystem. */
    long pet = 1024L * 1024L * 1024L; /* 1 PB in MB */
    CHECK("1 PB on /tmp -> 0",   test_disk_space("/tmp", pet, "PB") == 0);
}

static void test_invoke_git_with_timeout(void)
{
    printf("== invoke_git_with_timeout (PS L 163-231) ==\n");
    /* Smoke: `git --version` is universally available where git is on PATH. */
    char *out = NULL;
    int rc = invoke_git_with_timeout("--version", "/tmp", 30, &out);
    CHECK("git --version rc==0", rc == 0);
    if (out) {
        CHECK("git --version stdout starts with 'git version '",
              strncmp(out, "git version ", 12) == 0);
        free(out);
    }

    /* Negative: a nonsense subcommand should exit non-zero. */
    char *out2 = NULL;
    int rc2 = invoke_git_with_timeout("not-a-real-subcommand", "/tmp", 30, &out2);
    CHECK("git not-a-real-subcommand rc!=0", rc2 != 0);
    free(out2);
}

int main(void)
{
    test_convert_to_boolean();
    test_test_disk_space();
    test_invoke_git_with_timeout();
    if (failed) {
        printf("\n%d failure(s)\n", failed);
        return 1;
    }
    printf("\nall phase-1 tests passed\n");
    return 0;
}
