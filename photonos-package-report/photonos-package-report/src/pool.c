/* pool.c — fixed-size pthread worker pool.
 * Mirrors PS `ForEach-Object -Parallel -ThrottleLimit N` semantics.
 *
 * Lifecycle:
 *   1. pr_pool_create(N) — spawn nothing yet; allocate state.
 *   2. pr_pool_submit() repeatedly — pushes tasks into an internal queue.
 *   3. pr_pool_run() — spawns N worker threads, each pulls from the
 *      queue until empty, writes its result to the shared results
 *      array indexed by submission order. Returns the results array.
 *      Pool is destroyed before return.
 */
#include "pr_pool.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    pr_task_fn fn;
    void      *arg;
} task_t;

struct pr_pool {
    int            n_workers;
    size_t         n_tasks;
    size_t         tasks_cap;
    task_t        *tasks;
    /* Submission-order results. */
    void         **results;
    /* Pull index — workers atomically advance this. */
    size_t         next_idx;
    pthread_mutex_t mu;
};

pr_pool_t *pr_pool_create(int n_workers)
{
    if (n_workers < 1)   n_workers = 1;
    if (n_workers > 256) n_workers = 256;
    pr_pool_t *p = (pr_pool_t *)calloc(1, sizeof *p);
    if (!p) return NULL;
    p->n_workers = n_workers;
    pthread_mutex_init(&p->mu, NULL);
    return p;
}

int pr_pool_submit(pr_pool_t *pool, pr_task_fn fn, void *arg)
{
    if (pool == NULL || fn == NULL) return -1;
    if (pool->n_tasks == pool->tasks_cap) {
        size_t nc = pool->tasks_cap == 0 ? 64 : pool->tasks_cap * 2;
        task_t *np = (task_t *)realloc(pool->tasks, nc * sizeof *np);
        if (!np) return -1;
        pool->tasks    = np;
        pool->tasks_cap = nc;
    }
    pool->tasks[pool->n_tasks].fn  = fn;
    pool->tasks[pool->n_tasks].arg = arg;
    pool->n_tasks++;
    return 0;
}

static void *worker_main(void *arg)
{
    pr_pool_t *pool = (pr_pool_t *)arg;
    for (;;) {
        pthread_mutex_lock(&pool->mu);
        if (pool->next_idx >= pool->n_tasks) {
            pthread_mutex_unlock(&pool->mu);
            break;
        }
        size_t idx = pool->next_idx++;
        pthread_mutex_unlock(&pool->mu);

        task_t *t = &pool->tasks[idx];
        void *r = t->fn(t->arg);
        pool->results[idx] = r;
    }
    return NULL;
}

void **pr_pool_run(pr_pool_t *pool, size_t *out_n)
{
    if (pool == NULL || out_n == NULL) return NULL;
    *out_n = pool->n_tasks;
    if (pool->n_tasks == 0) {
        free(pool->tasks);
        pthread_mutex_destroy(&pool->mu);
        free(pool);
        return NULL;
    }

    pool->results = (void **)calloc(pool->n_tasks, sizeof *pool->results);
    if (!pool->results) {
        free(pool->tasks);
        pthread_mutex_destroy(&pool->mu);
        free(pool);
        return NULL;
    }

    int n = pool->n_workers;
    if ((size_t)n > pool->n_tasks) n = (int)pool->n_tasks;

    pthread_t *threads = (pthread_t *)calloc((size_t)n, sizeof *threads);
    if (!threads) {
        free(pool->results); free(pool->tasks);
        pthread_mutex_destroy(&pool->mu);
        free(pool);
        return NULL;
    }

    for (int i = 0; i < n; i++) {
        pthread_create(&threads[i], NULL, worker_main, pool);
    }
    for (int i = 0; i < n; i++) {
        pthread_join(threads[i], NULL);
    }
    free(threads);

    void **results = pool->results;
    free(pool->tasks);
    pthread_mutex_destroy(&pool->mu);
    free(pool);
    return results;
}
