/* pr_pool.h — fixed-size pthread worker pool.
 *
 * Mirrors photonos-package-report.ps1 L 5054 (`ForEach-Object -Parallel
 * -ThrottleLimit $ThrottleLimit`) — the PS author uses runspaces; the
 * C port uses POSIX threads. The default `-ThrottleLimit` is 20
 * (PS L 5214 hard cap).
 *
 * Submit-order is preserved across the pool: `pr_pool_join` returns
 * results in the order tasks were submitted, mirroring how PS's
 * ConcurrentBag-then-sort flow yields stable output (PS L 5052-5078).
 *
 * The pool is single-use: create, submit N tasks, join (which destroys
 * and frees the pool). Re-creating is cheap.
 *
 * Tasks take a `void *arg` and return a `void *result`. Lifecycle of
 * `arg` and `result` is caller-managed.
 */
#ifndef PR_POOL_H
#define PR_POOL_H

#include <stddef.h>

typedef void *(*pr_task_fn)(void *arg);

typedef struct pr_pool pr_pool_t;

/* Create a pool with `n_workers` threads. Returns NULL on failure.
 * `n_workers` is clamped to [1, 256]. */
pr_pool_t *pr_pool_create(int n_workers);

/* Submit a task. Not thread-safe; the caller must submit all tasks
 * before any worker starts processing them. Returns 0 on success. */
int pr_pool_submit(pr_pool_t *pool, pr_task_fn fn, void *arg);

/* Run all submitted tasks across the worker threads and return when
 * every task has completed. Returns a heap array of `void *` results
 * in submission order. Sets *out_n to the array length. Destroys the
 * pool. The caller must free() the returned array (results themselves
 * are caller-managed).
 *
 * Returns NULL on internal error. */
void **pr_pool_run(pr_pool_t *pool, size_t *out_n);

#endif /* PR_POOL_H */
