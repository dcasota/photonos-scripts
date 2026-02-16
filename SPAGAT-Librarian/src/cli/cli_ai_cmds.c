#include "../ai/ai.h"
#include "../ai/autonomy.h"
#include "../ai/sanitize.h"
#include "../agent/agent.h"
#include "../skill/skill.h"
#include "../util/util.h"
#include "cli.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int cmd_checkpoint_save(int64_t item_id, const char *name) {
    const char *cp_name = name ? name : "checkpoint";
    int64_t cp_id = 0;
    if (ai_checkpoint_save(item_id, cp_name, &cp_id)) {
        printf("Checkpoint saved: id=%lld name='%s'\n",
               (long long)cp_id, cp_name);
        return 0;
    }
    fprintf(stderr, "Failed to save checkpoint\n");
    return 1;
}

int cmd_checkpoint_list(int64_t item_id) {
    Checkpoint *checkpoints = NULL;
    int count = 0;
    if (!ai_checkpoint_list(item_id, &checkpoints, &count)) {
        fprintf(stderr, "Failed to list checkpoints\n");
        return 1;
    }

    if (count == 0) {
        printf("No checkpoints for task %lld.\n", (long long)item_id);
    } else {
        printf("Checkpoints for task %lld:\n", (long long)item_id);
        for (int i = 0; i < count; i++) {
            char time_buf[32];
            struct tm *tm = localtime(&checkpoints[i].created_at);
            strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M", tm);
            printf("  [%lld] %s (%s)\n",
                   (long long)checkpoints[i].id,
                   checkpoints[i].name, time_buf);
        }
    }

    ai_checkpoint_free(checkpoints, count);
    return 0;
}

int cmd_cron_list(void) {
    if (!scheduler_init()) {
        fprintf(stderr, "Failed to initialize scheduler\n");
        return 1;
    }

    CronJobList jobs;
    if (!scheduler_list_jobs(&jobs)) {
        fprintf(stderr, "Failed to list cron jobs\n");
        return 1;
    }

    if (jobs.count == 0) {
        printf("No cron jobs.\n");
    } else {
        printf("Cron Jobs (%d):\n", jobs.count);
        for (int i = 0; i < jobs.count; i++) {
            CronJob *j = &jobs.jobs[i];
            printf("  [%lld] every %d min: \"%s\" %s\n",
                   (long long)j->id, j->interval_minutes,
                   j->prompt,
                   j->enabled ? "(active)" : "(paused)");
        }
    }

    scheduler_free_jobs(&jobs);
    return 0;
}

int cmd_cron_add(int interval, const char *prompt) {
    if (!scheduler_init()) {
        fprintf(stderr, "Failed to initialize scheduler\n");
        return 1;
    }

    CronJob job;
    memset(&job, 0, sizeof(job));
    job.interval_minutes = interval;
    str_safe_copy(job.prompt, prompt, sizeof(job.prompt));
    job.enabled = true;

    int64_t job_id = 0;
    if (scheduler_add_job(&job, &job_id)) {
        printf("Cron job added: id=%lld interval=%d min\n",
               (long long)job_id, interval);
        return 0;
    }

    fprintf(stderr, "Failed to add cron job\n");
    return 1;
}

int cmd_cron_pause(int64_t job_id) {
    if (!scheduler_init()) return 1;
    if (scheduler_pause_job(job_id)) {
        printf("Cron job %lld paused.\n", (long long)job_id);
        return 0;
    }
    fprintf(stderr, "Failed to pause cron job\n");
    return 1;
}

int cmd_cron_resume(int64_t job_id) {
    if (!scheduler_init()) return 1;
    if (scheduler_resume_job(job_id)) {
        printf("Cron job %lld resumed.\n", (long long)job_id);
        return 0;
    }
    fprintf(stderr, "Failed to resume cron job\n");
    return 1;
}

int cmd_cron_delete(int64_t job_id) {
    if (!scheduler_init()) return 1;
    if (scheduler_remove_job(job_id)) {
        printf("Cron job %lld deleted.\n", (long long)job_id);
        return 0;
    }
    fprintf(stderr, "Failed to delete cron job\n");
    return 1;
}

int cmd_memory_set(const char *key, const char *value) {
    /* Session isolation (#125): check autonomy level for memory writes */
    WorkspacePaths wp;
    if (workspace_get_paths(&wp)) {
        SpagatConfig cfg;
        config_set_defaults(&cfg);
        config_load(wp.config_path, &cfg);
        AutonomyConfig acfg;
        autonomy_defaults(&acfg);
        acfg.level = autonomy_level_from_string(cfg.autonomy_mode);
        if (!autonomy_memory_write_allowed(&acfg, true)) {
            fprintf(stderr, "Memory writes not permitted at autonomy "
                            "level '%s'\n",
                    autonomy_level_to_string(acfg.level));
            return 1;
        }
    }

    if (ai_memory_set(0, "user", key, value)) {
        printf("Memory set: %s = %s\n", key, value);
        return 0;
    }
    fprintf(stderr, "Failed to set memory\n");
    return 1;
}

int cmd_memory_get(const char *key) {
    char value[512];
    if (ai_memory_get(0, "user", key, value, sizeof(value))) {
        printf("%s = %s\n", key, value);
    } else {
        printf("Key '%s' not found.\n", key);
    }
    return 0;
}

int cmd_memory_list(void) {
    printf("Agent memory (user scope):\n");
    if (!ai_memory_print_all(0, "user")) {
        fprintf(stderr, "Failed to list memory\n");
        return 1;
    }
    return 0;
}

int cmd_memory_clear(void) {
    if (ai_memory_clear(0, "user")) {
        printf("Memory cleared.\n");
        return 0;
    }
    fprintf(stderr, "Failed to clear memory\n");
    return 1;
}

int cmd_skill_list(void) {
    WorkspacePaths wp;
    if (!workspace_get_paths(&wp) || !skill_init(wp.skills_dir)) {
        fprintf(stderr, "Skills directory not available. "
                        "Run 'onboard' first.\n");
        return 1;
    }

    SkillList slist;
    if (!skill_load_all(wp.skills_dir, &slist)) {
        fprintf(stderr, "Failed to load skills\n");
        return 1;
    }

    /* Print skills with config value redaction (#132) */
    printf("Skills (%d):\n", slist.count);
    for (int i = 0; i < slist.count; i++) {
        const Skill *s = &slist.skills[i];
        printf("  [%d] %s", i + 1, s->name);
        if (s->description[0])
            printf(" - %s", s->description);

        /* Check for config: lines in content and redact values */
        const char *cfg_line = strstr(s->content, "config:");
        if (!cfg_line) cfg_line = strstr(s->content, "Config:");
        if (cfg_line) {
            printf(" (has config");
            /* Scan for key=value patterns after config: */
            const char *p = strchr(cfg_line, '\n');
            if (p) p++;
            while (p && *p && *p != '#' && *p != '\n') {
                const char *eq = strchr(p, '=');
                const char *eol = strchr(p, '\n');
                if (eq && (!eol || eq < eol)) {
                    char key[64];
                    size_t klen = (size_t)(eq - p);
                    if (klen > 0 && klen < sizeof(key)) {
                        memcpy(key, p, klen);
                        key[klen] = '\0';
                        char *trimmed_key = str_trim(key);
                        if (trimmed_key[0] && trimmed_key[0] != '#') {
                            char redacted[32];
                            const char *val_start = eq + 1;
                            size_t vlen = eol ?
                                (size_t)(eol - val_start) : strlen(val_start);
                            char val[128];
                            if (vlen >= sizeof(val)) vlen = sizeof(val) - 1;
                            memcpy(val, val_start, vlen);
                            val[vlen] = '\0';
                            sanitize_redact_value(str_trim(val), redacted,
                                                  sizeof(redacted));
                            printf(", %s=%s", trimmed_key, redacted);
                        }
                    }
                }
                p = eol ? eol + 1 : NULL;
            }
            printf(")");
        }
        printf("\n");
    }
    return 0;
}

int cmd_skill_run(const char *name) {
    WorkspacePaths wp;
    if (!workspace_get_paths(&wp) || !skill_init(wp.skills_dir)) {
        fprintf(stderr, "Skills directory not available\n");
        return 1;
    }

    SkillList slist;
    if (!skill_load_all(wp.skills_dir, &slist)) {
        fprintf(stderr, "Failed to load skills\n");
        return 1;
    }

    Skill skill;
    if (!skill_get_by_name(&slist, name, &skill)) {
        fprintf(stderr, "Skill not found: %s\n", name);
        return 1;
    }

    SpagatConfig cfg;
    config_set_defaults(&cfg);
    config_load(wp.config_path, &cfg);

    SkillExecContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    str_safe_copy(ctx.workspace_dir, wp.workspace_dir,
                  sizeof(ctx.workspace_dir));
    ctx.sandbox_enabled = sandbox_is_enabled(&cfg);

    if (!ai_init()) {
        fprintf(stderr, "Warning: AI provider not available "
                        "for prompt steps\n");
    }

    int result = skill_execute(&skill, &ctx) ? 0 : 1;
    ai_cleanup();
    return result;
}

int cmd_status_full(void) {
    printf("SPAGAT-Librarian v%s\n\n", SPAGAT_VERSION);

    WorkspacePaths wp;
    if (workspace_get_paths(&wp)) {
        printf("Workspace: %s (%s)\n", wp.base_dir,
               workspace_is_initialized(&wp) ? "initialized" : "not set up");
    } else {
        printf("Workspace: not configured\n");
    }

    if (ai_init()) {
        AIProvider *provider = ai_get_provider();
        if (provider) {
            printf("AI Provider: %s (%s)\n",
                   provider->get_name ? provider->get_name() : "unknown",
                   (provider->is_available && provider->is_available())
                   ? "available" : "not available");
        } else {
            printf("AI Provider: none\n");
        }
        ai_cleanup();
    } else {
        printf("AI Provider: not configured\n");
    }

    if (scheduler_init()) {
        CronJobList jobs;
        if (scheduler_list_jobs(&jobs)) {
            int active = 0;
            for (int i = 0; i < jobs.count; i++) {
                if (jobs.jobs[i].enabled) active++;
            }
            printf("Cron Jobs: %d total, %d active\n",
                   jobs.count, active);
            scheduler_free_jobs(&jobs);
        }
    }

    return 0;
}
