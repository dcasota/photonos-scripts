#ifndef AGENT_H
#define AGENT_H

#include "spagat.h"
#include <stdbool.h>

#define SPAGAT_WORKSPACE_DIR "workspace"
#define SPAGAT_MODELS_DIR "models"
#define SPAGAT_CONFIG_FILE "config.json"
#define SPAGAT_LOGS_DIR "logs"
#define SPAGAT_CREDENTIALS_DIR "credentials"

#define SPAGAT_PATH_MAX 1024

/* Workspace paths */
typedef struct {
    char base_dir[SPAGAT_PATH_MAX];       /* ~/.spagat */
    char workspace_dir[SPAGAT_PATH_MAX];  /* ~/.spagat/workspace */
    char models_dir[SPAGAT_PATH_MAX];     /* ~/.spagat/models */
    char config_path[SPAGAT_PATH_MAX];    /* ~/.spagat/config.json */
    char sessions_dir[SPAGAT_PATH_MAX];   /* ~/.spagat/workspace/sessions */
    char memory_dir[SPAGAT_PATH_MAX];     /* ~/.spagat/workspace/memory */
    char state_dir[SPAGAT_PATH_MAX];      /* ~/.spagat/workspace/state */
    char cron_dir[SPAGAT_PATH_MAX];       /* ~/.spagat/workspace/cron */
    char skills_dir[SPAGAT_PATH_MAX];     /* ~/.spagat/workspace/skills */
    char logs_dir[SPAGAT_PATH_MAX];       /* ~/.spagat/logs */
    char credentials_dir[SPAGAT_PATH_MAX]; /* ~/.spagat/credentials */
} WorkspacePaths;

/* Simple config (no cJSON dependency - hand-parsed) */
typedef struct {
    char provider[32];        /* "local" */
    int max_tokens;
    float temperature;
    int max_tool_iterations;
    bool restrict_to_workspace;
    /* Local provider (llama.cpp) */
    bool local_enabled;
    char local_engine[32];    /* "llama.cpp" */
    char local_model_path[512];
    char local_device[16];    /* "cpu", "gpu" */
    int local_n_gpu_layers;
    int local_n_ctx;          /* context size */
    float local_temperature;
    float local_top_p;
    /* Heartbeat */
    bool heartbeat_enabled;
    int heartbeat_interval;   /* minutes */
    /* Filesystem access (legacy, migrated to autonomy) */
    char fs_access_mode[16];  /* "workspace", "home", "full" */
    /* Autonomy */
    char autonomy_mode[16];   /* "none","observe","workspace","home","full" */
    bool confirm_destructive;
    long session_write_limit;
    int  session_file_limit;
    int  max_tool_calls_per_prompt;
    int  max_tool_calls_per_session;
    int  shell_timeout;
    /* Retry logic */
    int  max_retries;         /* max generation retries on failure (0=no retry) */
    int  retry_delay_ms;      /* delay between retries in ms */
    /* Per-project system prompt */
    char project_system_prompt[1024];
} SpagatConfig;

/* Cron job */
typedef struct {
    int64_t id;
    int64_t item_id;
    char cron_expression[64];
    int interval_minutes;
    char prompt[SPAGAT_MAX_DESC_LEN];
    time_t last_run;
    time_t next_run;
    bool enabled;
    bool one_time;
} CronJob;

typedef struct {
    CronJob *jobs;
    int count;
    int capacity;
} CronJobList;

/* Workspace management */
bool workspace_init(WorkspacePaths *paths);
bool workspace_get_paths(WorkspacePaths *paths);
bool workspace_ensure_dirs(const WorkspacePaths *paths);
bool workspace_is_initialized(const WorkspacePaths *paths);

/* Onboard (first-time setup) */
bool workspace_onboard(const WorkspacePaths *paths);
bool workspace_write_default_file(const char *path, const char *filename,
                                  const char *content);

/* Config */
bool config_load(const char *path, SpagatConfig *config);
bool config_save(const char *path, const SpagatConfig *config);
void config_set_defaults(SpagatConfig *config);

/* Sandbox */
bool sandbox_check_path(const WorkspacePaths *paths, const char *target_path);
bool sandbox_is_enabled(const SpagatConfig *config);

/* Scheduler (cron) */
bool scheduler_init(void);
bool scheduler_add_job(const CronJob *job, int64_t *out_id);
bool scheduler_remove_job(int64_t job_id);
bool scheduler_pause_job(int64_t job_id);
bool scheduler_resume_job(int64_t job_id);
bool scheduler_list_jobs(CronJobList *list);
void scheduler_free_jobs(CronJobList *list);
bool scheduler_check_due(CronJobList *due_jobs);
bool scheduler_update_last_run(int64_t job_id);

/* Heartbeat */
bool heartbeat_load(const char *heartbeat_path, char *content, int content_size);
bool heartbeat_process(const char *content);

#endif
