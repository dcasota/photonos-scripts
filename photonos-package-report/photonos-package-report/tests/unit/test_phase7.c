/* test_phase7.c — unit tests for the pthread worker pool. */
#include "pr_pool.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define EXPECT_INT(actual, expected) do {                                      \
    long _a = (long)(actual); long _e = (long)(expected);                      \
    if (_a != _e) {                                                            \
        fprintf(stderr, "  FAIL %s:%d: expected %ld got %ld\n",                \
                __FILE__, __LINE__, _e, _a);                                   \
        failures++;                                                            \
    }                                                                          \
} while (0)

/* Task that echoes its arg as the result. */
static void *echo_task(void *arg) { return arg; }

static void test_pool_order(void)
{
    fprintf(stderr, "[test_pool_order]\n");
    pr_pool_t *p = pr_pool_create(4);
    long expected[64];
    for (long i = 0; i < 64; i++) {
        expected[i] = i;
        pr_pool_submit(p, echo_task, (void *)expected[i]);
    }
    size_t n = 0;
    void **r = pr_pool_run(p, &n);
    EXPECT_INT(n, 64);
    /* Results must arrive in submission order despite parallel exec. */
    for (size_t i = 0; i < n; i++) {
        long v = (long)r[i];
        if (v != (long)i) {
            fprintf(stderr, "  FAIL: result[%zu] = %ld, expected %zu\n", i, v, i);
            failures++;
        }
    }
    free(r);
}

/* Race test: many workers increment a shared counter via mutex. */
static pthread_mutex_t G_MU = PTHREAD_MUTEX_INITIALIZER;
static long            G_COUNTER;

static void *inc_task(void *arg)
{
    long iters = (long)arg;
    for (long i = 0; i < iters; i++) {
        pthread_mutex_lock(&G_MU);
        G_COUNTER++;
        pthread_mutex_unlock(&G_MU);
    }
    return NULL;
}

static void test_pool_race(void)
{
    fprintf(stderr, "[test_pool_race]\n");
    G_COUNTER = 0;
    pr_pool_t *p = pr_pool_create(8);
    /* 8 tasks × 1000 increments = 8000 total. */
    for (int i = 0; i < 8; i++) pr_pool_submit(p, inc_task, (void *)(long)1000);
    size_t n = 0;
    void **r = pr_pool_run(p, &n);
    free(r);
    EXPECT_INT(G_COUNTER, 8000);
}

static void test_pool_single_worker(void)
{
    fprintf(stderr, "[test_pool_single_worker]\n");
    /* ThrottleLimit=1 fast path: pool still works, just sequentially. */
    pr_pool_t *p = pr_pool_create(1);
    for (long i = 0; i < 8; i++) pr_pool_submit(p, echo_task, (void *)i);
    size_t n = 0;
    void **r = pr_pool_run(p, &n);
    EXPECT_INT(n, 8);
    for (size_t i = 0; i < n; i++) EXPECT_INT((long)r[i], (long)i);
    free(r);
}

static void test_pool_empty(void)
{
    fprintf(stderr, "[test_pool_empty]\n");
    pr_pool_t *p = pr_pool_create(4);
    size_t n = 42;
    void **r = pr_pool_run(p, &n);
    EXPECT_INT(n, 0);
    if (r != NULL) { fprintf(stderr, "  FAIL: empty pool returned non-NULL\n"); failures++; }
}

int main(void)
{
    test_pool_order();
    test_pool_race();
    test_pool_single_worker();
    test_pool_empty();

    if (failures == 0) {
        fprintf(stderr, "test_phase7: ALL PASSED\n");
        return 0;
    }
    fprintf(stderr, "test_phase7: %d failure(s)\n", failures);
    return 1;
}
