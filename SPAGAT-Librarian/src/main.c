#include "spagat.h"
#include "db/db.h"
#include "cli/cli.h"
#include "tui/tui.h"
#include "util/util.h"
#include "agent/agent.h"
#include "ai/ai.h"
#include "ai/tools_fs.h"
#include "ai/autonomy.h"
#include "ai/sysaware.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Defined in cli/cli_dispatch.c */
int cli_dispatch_db_command(int argc, char **argv);

static int run_tui(void) {
    char *db_path = get_db_path();
    
    if (!file_exists(db_path)) {
        fprintf(stderr, "Database not found. Run 'spagat-librarian init' first.\n");
        return 1;
    }
    
    if (!db_open(db_path)) {
        fprintf(stderr, "Failed to open database\n");
        return 1;
    }
    
    if (!db_init_schema()) {
        fprintf(stderr, "Failed to initialize/migrate database\n");
        db_close();
        return 1;
    }
    
    TUIState state;
    if (!tui_init(&state)) {
        db_close();
        return 1;
    }
    
    tui_run(&state);
    tui_cleanup(&state);
    db_close();
    
    return 0;
}

static int run_cli(int argc, char **argv) {
    char *db_path = get_db_path();
    const char *cmd = argv[1];
    
    /* ---- Pre-DB commands (no database needed) ---- */

    if (str_equals_ignore_case(cmd, "init")) {
        return cmd_init();
    }
    
    if (str_equals_ignore_case(cmd, "help") || 
        str_equals_ignore_case(cmd, "--help") ||
        str_equals_ignore_case(cmd, "-h")) {
        cli_print_usage();
        cli_ext_print_usage();
        return 0;
    }
    
    if (str_equals_ignore_case(cmd, "version") ||
        str_equals_ignore_case(cmd, "--version") ||
        str_equals_ignore_case(cmd, "-v")) {
        cli_print_version();
        return 0;
    }
    
    if (str_equals_ignore_case(cmd, "onboard")) {
        WorkspacePaths wp;
        if (!workspace_init(&wp)) {
            fprintf(stderr, "Failed to initialize workspace paths\n");
            return 1;
        }
        return workspace_onboard(&wp) ? 0 : 1;
    }
    
    if (str_equals_ignore_case(cmd, "workspace")) {
        WorkspacePaths wp;
        if (!workspace_get_paths(&wp)) {
            printf("Workspace: not initialized\n");
            printf("Run 'spagat-librarian onboard' to set up.\n");
        } else {
            printf("Workspace Status:\n");
            printf("  Base:      %s\n", wp.base_dir);
            printf("  Workspace: %s\n", wp.workspace_dir);
            printf("  Models:    %s\n", wp.models_dir);
            printf("  Config:    %s\n", wp.config_path);
            printf("  Ready:     %s\n",
                   workspace_is_initialized(&wp) ? "yes" : "no");
        }
        return 0;
    }

    if (str_equals_ignore_case(cmd, "autonomy")) {
        WorkspacePaths wp;
        if (!workspace_get_paths(&wp)) {
            fprintf(stderr, "Workspace not initialized.\n");
            return 1;
        }
        SpagatConfig cfg;
        config_load(wp.config_path, &cfg);
        if (argc >= 3 && str_equals_ignore_case(argv[2], "set") &&
            argc >= 4) {
            AutonomyLevel lvl = autonomy_level_from_string(argv[3]);
            if (lvl == AUTONOMY_NONE &&
                !str_equals_ignore_case(argv[3], "none")) {
                fprintf(stderr, "Invalid level: %s\n"
                        "Valid: none, observe, workspace, home, full\n",
                        argv[3]);
                return 1;
            }
            str_safe_copy(cfg.autonomy_mode,
                          autonomy_level_to_string(lvl),
                          sizeof(cfg.autonomy_mode));
            config_save(wp.config_path, &cfg);
            printf("Autonomy set to: %s\n",
                   autonomy_level_to_string(lvl));
            return 0;
        }
        AutonomyLevel lvl =
            autonomy_level_from_string(cfg.autonomy_mode);
        printf("Autonomy Configuration:\n");
        printf("  Level:                 %s\n",
               autonomy_level_to_string(lvl));
        printf("  Confirm destructive:   %s\n",
               cfg.confirm_destructive ? "yes" : "no");
        printf("  Session write limit:   %ld bytes\n",
               cfg.session_write_limit);
        printf("  Session file limit:    %d\n",
               cfg.session_file_limit);
        printf("  Tool calls/prompt:     %d\n",
               cfg.max_tool_calls_per_prompt);
        printf("  Tool calls/session:    %d\n",
               cfg.max_tool_calls_per_session);
        printf("  Shell timeout:         %ds\n",
               cfg.shell_timeout);
        return 0;
    }

    if (str_equals_ignore_case(cmd, "sysinfo")) {
        char buf[4096];
        if (argc >= 3) {
            sysinfo_category(argv[2], buf, sizeof(buf));
        } else {
            sysinfo_snapshot(buf, sizeof(buf));
        }
        printf("%s\n", buf);
        return 0;
    }

    if (str_equals_ignore_case(cmd, "sysaware")) {
        WorkspacePaths swp;
        if (!workspace_get_paths(&swp)) {
            fprintf(stderr, "Workspace not initialized.\n");
            return 1;
        }
        int nfacts = sysaware_update(swp.workspace_dir);
        printf("Sysaware: %d facts stored/updated.\n", nfacts);
        return 0;
    }

    if (str_equals_ignore_case(cmd, "subagent")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian subagent "
                            "<spawn|list|kill|output> [args]\n");
            return 1;
        } else if (str_equals_ignore_case(argv[2], "spawn") && argc >= 5) {
            return cmd_subagent_spawn(argv[3], argv[4]);
        } else if (str_equals_ignore_case(argv[2], "list")) {
            return cmd_subagent_list();
        } else if (str_equals_ignore_case(argv[2], "kill") && argc >= 4) {
            return cmd_subagent_kill(atoll(argv[3]));
        } else if (str_equals_ignore_case(argv[2], "output") && argc >= 4) {
            return cmd_subagent_output(atoll(argv[3]));
        } else {
            fprintf(stderr, "Usage: spagat-librarian subagent "
                            "<spawn|list|kill|output> [args]\n");
            return 1;
        }
    }

    if (str_equals_ignore_case(cmd, "fs")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian fs <config|allowed>\n");
            return 1;
        } else if (str_equals_ignore_case(argv[2], "config") ||
                   str_equals_ignore_case(argv[2], "allowed")) {
            FsConfig fscfg;
            fs_config_defaults(&fscfg);
            const FsConfig *active = fs_get_config();
            const FsConfig *cfg = active ? active : &fscfg;
            printf("Access mode: %s\n", cfg->access_mode);
            printf("Allowed paths:\n");
            for (int i = 0; i < cfg->allowed_count; i++)
                printf("  %s\n", cfg->allowed_paths[i]);
            printf("Denied paths:\n");
            for (int i = 0; i < cfg->denied_count; i++)
                printf("  %s\n", cfg->denied_paths[i]);
            printf("Read-only paths:\n");
            for (int i = 0; i < cfg->readonly_count; i++)
                printf("  %s\n", cfg->readonly_paths[i]);
            printf("Max read: %ld, Max write: %ld\n",
                   cfg->max_read_size, cfg->max_write_size);
            return 0;
        } else {
            fprintf(stderr, "Usage: spagat-librarian fs <config|allowed>\n");
            return 1;
        }
    }

    /* ---- DB-required commands ---- */

    if (!file_exists(db_path)) {
        fprintf(stderr, "Database not found. Run 'spagat-librarian init' first.\n");
        return 1;
    }
    
    if (!db_open(db_path)) {
        fprintf(stderr, "Failed to open database\n");
        return 1;
    }
    
    if (!db_init_schema()) {
        fprintf(stderr, "Failed to initialize/migrate database\n");
        db_close();
        return 1;
    }

    int result = cli_dispatch_db_command(argc, argv);

    db_close();
    return result;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        return run_tui();
    }
    
    return run_cli(argc, argv);
}
