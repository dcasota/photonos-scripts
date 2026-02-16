#ifndef CLI_H
#define CLI_H

#include "spagat.h"

void cli_print_usage(void);
void cli_print_version(void);
void cli_ext_print_usage(void);

int cmd_init(void);
int cmd_add(int argc, char **argv);
int cmd_add_interactive(void);
int cmd_show(int argc, char **argv);
int cmd_list(void);
int cmd_edit(int64_t id);
int cmd_move(int64_t id, const char *new_status);
int cmd_delete(int64_t id);
int cmd_tags(void);
int cmd_stats(int argc, char **argv);
int cmd_filter_status(int argc, char **argv);
int cmd_export(const char *format);

int cmd_project_add(const char *name, const char *description);
int cmd_project_list(void);
int cmd_project_delete(const char *name);
int cmd_template_add(const char *name, const char *title, const char *desc,
                     const char *tag, const char *status, const char *priority);
int cmd_template_list(void);
int cmd_template_use(const char *name);
int cmd_dependency_add(int64_t from_id, int64_t to_id);
int cmd_dependency_remove(int64_t from_id, int64_t to_id);
int cmd_dependency_list(int64_t item_id);
int cmd_subtasks(int64_t parent_id);
int cmd_due(const char *when);
int cmd_time_start(int64_t item_id);
int cmd_time_stop(int64_t item_id);
int cmd_session_save(const char *name);
int cmd_session_load(const char *name);
int cmd_priority_list(const char *priority);

int cmd_agent(int argc, char **argv);
int cmd_ai_chat(int64_t item_id);
int cmd_ai_history(int64_t item_id);
int cmd_model_list(void);
int cmd_model_test(void);
int cmd_checkpoint_save(int64_t item_id, const char *name);
int cmd_checkpoint_list(int64_t item_id);
int cmd_cron_list(void);
int cmd_cron_add(int interval, const char *prompt);
int cmd_cron_pause(int64_t job_id);
int cmd_cron_resume(int64_t job_id);
int cmd_cron_delete(int64_t job_id);
int cmd_memory_set(const char *key, const char *value);
int cmd_memory_get(const char *key);
int cmd_memory_list(void);
int cmd_memory_clear(void);
int cmd_skill_list(void);
int cmd_skill_run(const char *name);
int cmd_status_full(void);

/* Subagent commands (#135) */
int cmd_subagent_spawn(const char *name, const char *command);
int cmd_subagent_list(void);
int cmd_subagent_kill(int64_t id);
int cmd_subagent_output(int64_t id);

/* DB-command dispatcher (cli_dispatch.c) */
int cli_dispatch_db_command(int argc, char **argv);

#endif
