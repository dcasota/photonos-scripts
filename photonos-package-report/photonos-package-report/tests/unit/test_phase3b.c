/* test_phase3b.c — unit tests for per-spec hook dispatch.
 *
 * Assertions:
 *   • pr_hook_dispatch_count == 3 (the demo hooks: inih, open-vm-tools,
 *     samba-client). Updates as more hooks land.
 *   • Dispatch table is sorted by `spec` strcmp ordering (required for
 *     bsearch correctness).
 *   • pr_hooks_find("inih.spec")          returns non-NULL.
 *   • pr_hooks_find("open-vm-tools.spec") returns non-NULL.
 *   • pr_hooks_find("samba-client.spec")  returns non-NULL.
 *   • pr_hooks_find("definitely-not-real.spec") returns NULL.
 *   • pr_hooks_find(NULL) returns NULL (no crash).
 *   • pr_hooks_run on a task with a known Spec invokes the right hook
 *     and returns 0 (the demo bodies are no-op stubs).
 *   • pr_hooks_run on a task with NULL Spec returns 0 (no crash).
 */
#include "pr_hook.h"
#include "pr_types.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int failures = 0;

#define EXPECT(cond) do {                                                  \
    if (!(cond)) {                                                         \
        fprintf(stderr, "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);  \
        failures++;                                                        \
    }                                                                      \
} while (0)

static void test_dispatch_table(void)
{
    fprintf(stderr, "[test_dispatch_table]\n");

    /* We baseline at 3 in this PR; bump as future PRs add hooks. */
    EXPECT(pr_hook_dispatch_count == 3);

    /* Sorted by `spec` strcmp order. */
    for (size_t i = 1; i < pr_hook_dispatch_count; i++) {
        const char *a = pr_hook_dispatch[i - 1].spec;
        const char *b = pr_hook_dispatch[i].spec;
        if (strcmp(a, b) >= 0) {
            fprintf(stderr, "  FAIL: dispatch not sorted: %s vs %s\n", a, b);
            failures++;
        }
    }
}

static void test_lookup(void)
{
    fprintf(stderr, "[test_lookup]\n");

    EXPECT(pr_hooks_find("inih.spec")          != NULL);
    EXPECT(pr_hooks_find("open-vm-tools.spec") != NULL);
    EXPECT(pr_hooks_find("samba-client.spec")  != NULL);

    /* Negative case. */
    EXPECT(pr_hooks_find("definitely-not-real.spec") == NULL);

    /* NULL key — must not crash. */
    EXPECT(pr_hooks_find(NULL) == NULL);
}

static void test_run(void)
{
    fprintf(stderr, "[test_run]\n");

    /* Build a minimal pr_task_t and dispatch through it. */
    pr_task_t t;
    memset(&t, 0, sizeof t);
    t.Spec = (char *)"inih.spec";
    EXPECT(pr_hooks_run(&t, NULL) == 0);

    /* Unknown spec → no-op, returns 0. */
    t.Spec = (char *)"unknown.spec";
    EXPECT(pr_hooks_run(&t, NULL) == 0);

    /* NULL Spec — must not crash. */
    t.Spec = NULL;
    EXPECT(pr_hooks_run(&t, NULL) == 0);
}

int main(void)
{
    test_dispatch_table();
    test_lookup();
    test_run();

    if (failures == 0) {
        fprintf(stderr, "test_phase3b: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase3b: %d failure(s)\n", failures);
    return 1;
}
