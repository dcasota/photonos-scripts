#include "cli.h"
#include "../db/db.h"
#include "../util/util.h"
#include "../agent/agent.h"
#include "../ai/ai.h"
#include "../ai/tools_fs.h"
#include "../ai/autonomy.h"
#include "../ai/sysaware.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * cli_dispatch_db_command  --  handle every CLI verb that requires
 * an open database.  Called from main.c after the DB has been opened
 * and the schema initialised.
 *
 * Returns the process exit code (0 = success).
 */
int cli_dispatch_db_command(int argc, char **argv) {
    const char *cmd = argv[1];
    int result = 0;

    if (str_equals_ignore_case(cmd, "add")) {
        if (argc == 2) {
            result = cmd_add_interactive();
        } else if (argc >= 5) {
            result = cmd_add(argc - 2, argv + 2);
        } else {
            fprintf(stderr, "Usage: spagat-librarian add <status> <title> <description> [tag]\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "show")) {
        result = cmd_show(argc - 2, argv + 2);
    }
    else if (str_equals_ignore_case(cmd, "list")) {
        result = cmd_list();
    }
    else if (str_equals_ignore_case(cmd, "tags")) {
        result = cmd_tags();
    }
    else if (str_equals_ignore_case(cmd, "stats")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian stats <status|tag|history> [filter]\n");
            result = 1;
        } else {
            result = cmd_stats(argc - 2, argv + 2);
        }
    }
    else if (str_equals_ignore_case(cmd, "delete")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian delete <id>\n");
            result = 1;
        } else {
            result = cmd_delete(atoll(argv[2]));
        }
    }
    else if (str_equals_ignore_case(cmd, "export")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian export <csv|json>\n");
            result = 1;
        } else {
            result = cmd_export(argv[2]);
        }
    }
    else if (str_equals_ignore_case(cmd, "project")) {
        if (argc < 3) {
            result = cmd_project_list();
        } else if (str_equals_ignore_case(argv[2], "add") && argc >= 4) {
            result = cmd_project_add(argv[3], argc > 4 ? argv[4] : NULL);
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_project_list();
        } else if (str_equals_ignore_case(argv[2], "delete") && argc >= 4) {
            result = cmd_project_delete(argv[3]);
        } else {
            fprintf(stderr, "Usage: spagat-librarian project <add|list|delete> [args]\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "template")) {
        if (argc < 3) {
            result = cmd_template_list();
        } else if (str_equals_ignore_case(argv[2], "add") && argc >= 4) {
            result = cmd_template_add(argv[3], 
                                      argc > 4 ? argv[4] : NULL,
                                      argc > 5 ? argv[5] : NULL,
                                      argc > 6 ? argv[6] : NULL,
                                      argc > 7 ? argv[7] : NULL,
                                      argc > 8 ? argv[8] : NULL);
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_template_list();
        } else if (str_equals_ignore_case(argv[2], "use") && argc >= 4) {
            result = cmd_template_use(argv[3]);
        } else {
            fprintf(stderr, "Usage: spagat-librarian template <add|list|use> [args]\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "depend") && argc >= 4) {
        result = cmd_dependency_add(atoll(argv[2]), atoll(argv[3]));
    }
    else if (str_equals_ignore_case(cmd, "undepend") && argc >= 4) {
        result = cmd_dependency_remove(atoll(argv[2]), atoll(argv[3]));
    }
    else if (str_equals_ignore_case(cmd, "deps") && argc >= 3) {
        result = cmd_dependency_list(atoll(argv[2]));
    }
    else if (str_equals_ignore_case(cmd, "subtasks") && argc >= 3) {
        result = cmd_subtasks(atoll(argv[2]));
    }
    else if (str_equals_ignore_case(cmd, "due")) {
        result = cmd_due(argc >= 3 ? argv[2] : "week");
    }
    else if (str_equals_ignore_case(cmd, "time")) {
        if (argc < 4) {
            fprintf(stderr, "Usage: spagat-librarian time <start|stop> <id>\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "start")) {
            result = cmd_time_start(atoll(argv[3]));
        } else if (str_equals_ignore_case(argv[2], "stop")) {
            result = cmd_time_stop(atoll(argv[3]));
        } else {
            fprintf(stderr, "Usage: spagat-librarian time <start|stop> <id>\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "session")) {
        if (argc < 4) {
            fprintf(stderr, "Usage: spagat-librarian session <save|load> <name>\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "save")) {
            result = cmd_session_save(argv[3]);
        } else if (str_equals_ignore_case(argv[2], "load")) {
            result = cmd_session_load(argv[3]);
        } else {
            fprintf(stderr, "Usage: spagat-librarian session <save|load> <name>\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "priority") && argc >= 3) {
        result = cmd_priority_list(argv[2]);
    }
    else if (str_equals_ignore_case(cmd, "agent")) {
        result = cmd_agent(argc - 2, argv + 2);
    }
    else if (str_equals_ignore_case(cmd, "ai")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian ai <id>\n"
                            "       spagat-librarian ai history <id>\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "history") && argc >= 4) {
            result = cmd_ai_history(atoll(argv[3]));
        } else {
            result = cmd_ai_chat(atoll(argv[2]));
        }
    }
    else if (str_equals_ignore_case(cmd, "model")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian model <list|test>\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_model_list();
        } else if (str_equals_ignore_case(argv[2], "test")) {
            result = cmd_model_test();
        } else {
            fprintf(stderr, "Unknown model command: %s\n", argv[2]);
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "checkpoint")) {
        if (argc < 4) {
            fprintf(stderr, "Usage: spagat-librarian checkpoint <save|list> <id> [name]\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "save")) {
            result = cmd_checkpoint_save(atoll(argv[3]),
                                         argc >= 5 ? argv[4] : NULL);
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_checkpoint_list(atoll(argv[3]));
        } else {
            fprintf(stderr, "Usage: spagat-librarian checkpoint <save|list> <id> [name]\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "cron")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian cron <list|add|pause|resume|delete> [args]\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_cron_list();
        } else if (str_equals_ignore_case(argv[2], "add")) {
            int interval = 0;
            const char *prompt = NULL;
            for (int i = 3; i < argc; i++) {
                if (str_equals_ignore_case(argv[i], "--interval") &&
                    i + 1 < argc) {
                    interval = atoi(argv[++i]);
                } else {
                    prompt = argv[i];
                }
            }
            if (interval <= 0 || !prompt) {
                fprintf(stderr, "Usage: spagat-librarian cron add "
                                "--interval <min> \"<prompt>\"\n");
                result = 1;
            } else {
                result = cmd_cron_add(interval, prompt);
            }
        } else if (str_equals_ignore_case(argv[2], "pause") && argc >= 4) {
            result = cmd_cron_pause(atoll(argv[3]));
        } else if (str_equals_ignore_case(argv[2], "resume") && argc >= 4) {
            result = cmd_cron_resume(atoll(argv[3]));
        } else if (str_equals_ignore_case(argv[2], "delete") && argc >= 4) {
            result = cmd_cron_delete(atoll(argv[3]));
        } else {
            fprintf(stderr, "Unknown cron command: %s\n", argv[2]);
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "memory")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian memory <set|get|list|clear> [args]\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "set") && argc >= 5) {
            result = cmd_memory_set(argv[3], argv[4]);
        } else if (str_equals_ignore_case(argv[2], "get") && argc >= 4) {
            result = cmd_memory_get(argv[3]);
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_memory_list();
        } else if (str_equals_ignore_case(argv[2], "clear")) {
            result = cmd_memory_clear();
        } else {
            fprintf(stderr, "Usage: spagat-librarian memory <set|get|list|clear> [args]\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "skill")) {
        if (argc < 3) {
            fprintf(stderr, "Usage: spagat-librarian skill <list|run> [name]\n");
            result = 1;
        } else if (str_equals_ignore_case(argv[2], "list")) {
            result = cmd_skill_list();
        } else if (str_equals_ignore_case(argv[2], "run") && argc >= 4) {
            result = cmd_skill_run(argv[3]);
        } else {
            fprintf(stderr, "Usage: spagat-librarian skill <list|run> [name]\n");
            result = 1;
        }
    }
    else if (str_equals_ignore_case(cmd, "status")) {
        result = cmd_status_full();
    }
    else if (is_numeric(cmd)) {
        int64_t id = atoll(cmd);
        if (argc == 2) {
            result = cmd_edit(id);
        } else {
            result = cmd_move(id, argv[2]);
        }
    }
    else {
        bool is_status = false;
        for (int i = 0; i < STATUS_COUNT; i++) {
            if (str_equals_ignore_case(cmd, STATUS_NAMES[i])) {
                is_status = true;
                break;
            }
        }
        
        if (is_status) {
            result = cmd_filter_status(argc - 1, argv + 1);
        } else {
            fprintf(stderr, "Unknown command: %s\n", cmd);
            cli_print_usage();
            result = 1;
        }
    }

    return result;
}
