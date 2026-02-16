#include "agent.h"
#include "../db/db.h"
#include "../util/util.h"
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *SCHEDULER_SCHEMA =
    "CREATE TABLE IF NOT EXISTS cron_jobs ("
    "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  item_id INTEGER DEFAULT 0,"
    "  cron_expression TEXT DEFAULT '',"
    "  interval_minutes INTEGER DEFAULT 0,"
    "  prompt TEXT DEFAULT '',"
    "  last_run INTEGER DEFAULT 0,"
    "  next_run INTEGER DEFAULT 0,"
    "  enabled INTEGER DEFAULT 1,"
    "  one_time INTEGER DEFAULT 0"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_cron_enabled ON cron_jobs(enabled);"
    "CREATE INDEX IF NOT EXISTS idx_cron_next_run ON cron_jobs(next_run);";

static time_t calculate_next_run(const CronJob *job) {
    time_t now = time(NULL);

    if (job->one_time && job->last_run > 0) {
        return 0; /* Already ran, no next run */
    }

    if (job->interval_minutes > 0) {
        time_t base = job->last_run > 0 ? job->last_run : now;
        return base + (time_t)job->interval_minutes * 60;
    }

    /* Fallback: 1 hour from now */
    return now + 3600;
}

static void ensure_jobs_capacity(CronJobList *list, int needed) {
    if (list->capacity >= needed) return;
    int new_cap = list->capacity ? list->capacity * 2 : 8;
    while (new_cap < needed) new_cap *= 2;
    list->jobs = realloc(list->jobs, (size_t)new_cap * sizeof(CronJob));
    list->capacity = new_cap;
}

static void read_job_row(sqlite3_stmt *stmt, CronJob *job) {
    memset(job, 0, sizeof(CronJob));

    job->id = sqlite3_column_int64(stmt, 0);
    job->item_id = sqlite3_column_int64(stmt, 1);

    const char *cron_expr = (const char *)sqlite3_column_text(stmt, 2);
    str_safe_copy(job->cron_expression, cron_expr ? cron_expr : "",
                  sizeof(job->cron_expression));

    job->interval_minutes = sqlite3_column_int(stmt, 3);

    const char *prompt = (const char *)sqlite3_column_text(stmt, 4);
    str_safe_copy(job->prompt, prompt ? prompt : "", sizeof(job->prompt));

    job->last_run = sqlite3_column_int64(stmt, 5);
    job->next_run = sqlite3_column_int64(stmt, 6);
    job->enabled = sqlite3_column_int(stmt, 7) != 0;
    job->one_time = sqlite3_column_int(stmt, 8) != 0;
}

bool scheduler_init(void) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;

    char *err = NULL;
    int rc = sqlite3_exec(db, SCHEDULER_SCHEMA, NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Scheduler schema error: %s\n", err);
        sqlite3_free(err);
        return false;
    }

    return true;
}

bool scheduler_add_job(const CronJob *job, int64_t *out_id) {
    if (!job) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql =
        "INSERT INTO cron_jobs (item_id, cron_expression, interval_minutes, "
        "prompt, last_run, next_run, enabled, one_time) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Scheduler prepare error: %s\n",
                sqlite3_errmsg(db));
        return false;
    }

    time_t next = calculate_next_run(job);

    sqlite3_bind_int64(stmt, 1, job->item_id);
    sqlite3_bind_text(stmt, 2, job->cron_expression, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 3, job->interval_minutes);
    sqlite3_bind_text(stmt, 4, job->prompt, -1, SQLITE_STATIC);
    sqlite3_bind_int64(stmt, 5, job->last_run);
    sqlite3_bind_int64(stmt, 6, next);
    sqlite3_bind_int(stmt, 7, job->enabled ? 1 : 0);
    sqlite3_bind_int(stmt, 8, job->one_time ? 1 : 0);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        fprintf(stderr, "Scheduler insert error: %s\n",
                sqlite3_errmsg(db));
        return false;
    }

    if (out_id) *out_id = sqlite3_last_insert_rowid(db);
    return true;
}

bool scheduler_remove_job(int64_t job_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql = "DELETE FROM cron_jobs WHERE id = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;

    sqlite3_bind_int64(stmt, 1, job_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}

bool scheduler_pause_job(int64_t job_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql = "UPDATE cron_jobs SET enabled = 0 WHERE id = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;

    sqlite3_bind_int64(stmt, 1, job_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}

bool scheduler_resume_job(int64_t job_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;

    const char *sql = "UPDATE cron_jobs SET enabled = 1 WHERE id = ?";
    sqlite3_stmt *stmt;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;

    sqlite3_bind_int64(stmt, 1, job_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}

bool scheduler_list_jobs(CronJobList *list) {
    if (!list) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    list->jobs = NULL;
    list->count = 0;
    list->capacity = 0;

    const char *sql =
        "SELECT id, item_id, cron_expression, interval_minutes, prompt, "
        "last_run, next_run, enabled, one_time FROM cron_jobs ORDER BY id";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_jobs_capacity(list, list->count + 1);
        read_job_row(stmt, &list->jobs[list->count]);
        list->count++;
    }

    sqlite3_finalize(stmt);
    return true;
}

void scheduler_free_jobs(CronJobList *list) {
    if (list && list->jobs) {
        free(list->jobs);
        list->jobs = NULL;
        list->count = 0;
        list->capacity = 0;
    }
}

bool scheduler_check_due(CronJobList *due_jobs) {
    if (!due_jobs) return false;

    sqlite3 *db = db_get_handle();
    if (!db) return false;

    due_jobs->jobs = NULL;
    due_jobs->count = 0;
    due_jobs->capacity = 0;

    time_t now = time(NULL);

    const char *sql =
        "SELECT id, item_id, cron_expression, interval_minutes, prompt, "
        "last_run, next_run, enabled, one_time "
        "FROM cron_jobs WHERE enabled = 1 AND next_run <= ? AND next_run > 0 "
        "ORDER BY next_run";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;

    sqlite3_bind_int64(stmt, 1, now);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ensure_jobs_capacity(due_jobs, due_jobs->count + 1);
        read_job_row(stmt, &due_jobs->jobs[due_jobs->count]);
        due_jobs->count++;
    }

    sqlite3_finalize(stmt);
    return true;
}

bool scheduler_update_last_run(int64_t job_id) {
    sqlite3 *db = db_get_handle();
    if (!db) return false;

    /* First get the job to calculate next run */
    const char *select_sql =
        "SELECT id, item_id, cron_expression, interval_minutes, prompt, "
        "last_run, next_run, enabled, one_time FROM cron_jobs WHERE id = ?";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, select_sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, job_id);

    CronJob job;
    if (sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return false;
    }

    read_job_row(stmt, &job);
    sqlite3_finalize(stmt);

    /* Update last_run to now */
    time_t now = time(NULL);
    job.last_run = now;

    /* Calculate next run */
    time_t next = calculate_next_run(&job);

    /* If one_time and already ran, disable */
    int new_enabled = job.enabled ? 1 : 0;
    if (job.one_time) {
        new_enabled = 0;
        next = 0;
    }

    const char *update_sql =
        "UPDATE cron_jobs SET last_run = ?, next_run = ?, enabled = ? "
        "WHERE id = ?";

    if (sqlite3_prepare_v2(db, update_sql, -1, &stmt, NULL) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, now);
    sqlite3_bind_int64(stmt, 2, next);
    sqlite3_bind_int(stmt, 3, new_enabled);
    sqlite3_bind_int64(stmt, 4, job_id);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return rc == SQLITE_DONE;
}
