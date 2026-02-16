#include "prompt_builder.h"
#include "ai.h"
#include "autonomy.h"
#include "../util/util.h"
#include "../agent/agent.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>

/*
 * Structured system prompt builder for SPAGAT-Librarian.
 *
 * Assembles the system prompt from independent sections (identity, tools,
 * skills, system context, rules, project context) so that each section
 * can be built/tested separately and the prompt adapts to the current
 * autonomy level.
 */

/* Default identity when no IDENTITY.md exists */
static const char *DEFAULT_IDENTITY =
    "You are SPAGAT-Librarian, an AI assistant for Photon OS system "
    "administration.";

/* ---- Section builders ---- */

/*
 * Build the identity section.
 * Loads IDENTITY.md from workspace_dir if it exists, otherwise uses
 * the default identity string.
 */
static int build_identity(char *output, int output_size,
                          const char *workspace_dir) {
    if (!output || output_size < 1) return 0;
    output[0] = '\0';

    if (workspace_dir && workspace_dir[0]) {
        char path[1024];
        snprintf(path, sizeof(path), "%s/IDENTITY.md", workspace_dir);

        FILE *fp = fopen(path, "r");
        if (fp) {
            int pos = 0;
            int ch;
            while ((ch = fgetc(fp)) != EOF && pos < output_size - 2) {
                output[pos++] = (char)ch;
            }
            output[pos] = '\0';
            fclose(fp);
            return pos;
        }
    }

    /* Fall back to default */
    str_safe_copy(output, DEFAULT_IDENTITY, (size_t)output_size);
    return (int)strlen(output);
}

/*
 * Build tool descriptions.
 * Lists only tools that are registered AND permitted at the current
 * autonomy level. Includes TOOL_CALL format instructions and a worked
 * example.
 */
int prompt_build_tools(char *output, int output_size,
                       const AutonomyConfig *cfg) {
    if (!output || output_size < 1) return 0;

    int pos = 0;

    /* Header with TOOL_CALL format */
    pos += snprintf(output + pos, output_size - pos,
        "To use a tool, output EXACTLY:\n"
        "TOOL_CALL: tool_name\n"
        "input\n"
        "END_TOOL_CALL\n\n");

    /* List registered tools that are permitted */
    if (cfg && cfg->level == AUTONOMY_NONE) {
        pos += snprintf(output + pos, output_size - pos,
            "No tools are available.\n");
    } else {
        /* Get the full tool list from the registry */
        char tool_list[PROMPT_MAX_SECTION];
        int count = ai_tools_list(tool_list, sizeof(tool_list));

        if (count > 0 && pos < output_size - 1) {
            int space = output_size - pos;
            int tlen = (int)strlen(tool_list);
            if (tlen >= space) tlen = space - 1;
            memcpy(output + pos, tool_list, tlen);
            pos += tlen;
            output[pos] = '\0';
        }
    }

    /* Worked example */
    if (cfg && cfg->level >= AUTONOMY_OBSERVE && pos < output_size - 256) {
        pos += snprintf(output + pos, output_size - pos,
            "\nExample - user asks 'list files here':\n"
            "TOOL_CALL: list_directory\n"
            ".\n"
            "END_TOOL_CALL\n");
    }

    return pos;
}

/*
 * Build skills section.
 * Reads all .md files from skills_dir, extracts the first section
 * (name + description from the first heading and paragraph), and
 * concatenates them as skill context.
 */
int prompt_build_skills(char *output, int output_size,
                        const char *skills_dir) {
    if (!output || output_size < 1) return 0;
    output[0] = '\0';

    if (!skills_dir || !skills_dir[0]) return 0;

    DIR *dir = opendir(skills_dir);
    if (!dir) return 0;

    int pos = 0;
    struct dirent *entry;

    while ((entry = readdir(dir)) != NULL && pos < output_size - 256) {
        /* Only process .md files */
        const char *name = entry->d_name;
        size_t nlen = strlen(name);
        if (nlen < 4 || strcmp(name + nlen - 3, ".md") != 0) continue;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;

        char filepath[1024];
        snprintf(filepath, sizeof(filepath), "%s/%s", skills_dir, name);

        FILE *fp = fopen(filepath, "r");
        if (!fp) continue;

        /* Read the first section: first heading line + first paragraph */
        char line[512];
        char skill_name[128];
        char skill_desc[512];
        skill_name[0] = '\0';
        skill_desc[0] = '\0';
        int desc_pos = 0;
        bool found_heading = false;
        bool in_desc = false;

        while (fgets(line, sizeof(line), fp)) {
            /* Strip trailing newline */
            size_t llen = strlen(line);
            while (llen > 0 && (line[llen - 1] == '\n' ||
                                line[llen - 1] == '\r')) {
                line[--llen] = '\0';
            }

            if (!found_heading && line[0] == '#') {
                /* Extract heading text after # */
                char *text = line;
                while (*text == '#' || *text == ' ') text++;
                str_safe_copy(skill_name, text, sizeof(skill_name));
                found_heading = true;
                in_desc = true;
                continue;
            }

            if (in_desc) {
                /* Empty line after description ends the section */
                if (llen == 0 && desc_pos > 0) break;
                if (line[0] == '#') break; /* Next heading */
                if (llen > 0 && desc_pos < (int)sizeof(skill_desc) - 2) {
                    if (desc_pos > 0) {
                        skill_desc[desc_pos++] = ' ';
                    }
                    int space = (int)sizeof(skill_desc) - desc_pos - 1;
                    int copy = (int)llen < space ? (int)llen : space;
                    memcpy(skill_desc + desc_pos, line, copy);
                    desc_pos += copy;
                    skill_desc[desc_pos] = '\0';
                }
            }
        }

        fclose(fp);

        /* Append to output if we got something */
        if (skill_name[0] && pos < output_size - 128) {
            if (skill_desc[0]) {
                pos += snprintf(output + pos, output_size - pos,
                    "- %s: %s\n", skill_name, skill_desc);
            } else {
                pos += snprintf(output + pos, output_size - pos,
                    "- %s\n", skill_name);
            }
        }
    }

    closedir(dir);
    return pos;
}

/*
 * Build rules section based on autonomy level.
 */
int prompt_build_rules(char *output, int output_size,
                       const AutonomyConfig *cfg) {
    if (!output || output_size < 1) return 0;
    output[0] = '\0';

    if (!cfg) return 0;

    const char *rules = NULL;

    switch (cfg->level) {
    case AUTONOMY_NONE:
        rules = "You have no tools. Only answer questions from your "
                "knowledge.";
        break;
    case AUTONOMY_OBSERVE:
        rules = "You can only READ files and run read-only commands. "
                "Never suggest writing or modifying anything.";
        break;
    case AUTONOMY_WORKSPACE:
        rules = "You can read the full filesystem but can only WRITE "
                "within the workspace directory.";
        break;
    case AUTONOMY_HOME:
        rules = "You can read the full filesystem and write within "
                "the user's home directory.";
        break;
    case AUTONOMY_FULL:
        rules = "You have full filesystem access. Be careful with "
                "destructive operations.";
        break;
    default:
        rules = "Unknown autonomy level. Exercise caution.";
        break;
    }

    str_safe_copy(output, rules, (size_t)output_size);
    return (int)strlen(output);
}

/*
 * Load project context from AGENT.md or USER.md if they exist.
 */
static int build_project_context(char *output, int output_size,
                                 const char *workspace_dir) {
    if (!output || output_size < 1) return 0;
    output[0] = '\0';

    if (!workspace_dir || !workspace_dir[0]) return 0;

    /* Try AGENT.md first, then USER.md */
    const char *candidates[] = { "AGENT.md", "USER.md", NULL };

    for (int i = 0; candidates[i]; i++) {
        char path[1024];
        snprintf(path, sizeof(path), "%s/%s", workspace_dir, candidates[i]);

        FILE *fp = fopen(path, "r");
        if (!fp) continue;

        int pos = 0;
        int ch;
        while ((ch = fgetc(fp)) != EOF && pos < output_size - 2) {
            output[pos++] = (char)ch;
        }
        output[pos] = '\0';
        fclose(fp);

        if (pos > 0) return pos;
    }

    return 0;
}

/*
 * Build the complete system prompt based on autonomy config.
 * Populates all sections of the SystemPromptBuilder.
 */
int prompt_build(SystemPromptBuilder *b, const AutonomyConfig *cfg,
                 const char *workspace_dir) {
    if (!b) return -1;

    memset(b, 0, sizeof(SystemPromptBuilder));

    int total = 0;
    int n;

    /* Identity */
    n = build_identity(b->identity, sizeof(b->identity), workspace_dir);
    if (n > 0) total += n;

    /* Tools */
    n = prompt_build_tools(b->tools, sizeof(b->tools), cfg);
    if (n > 0) total += n;

    /* Skills */
    if (workspace_dir && workspace_dir[0]) {
        char skills_dir[1024];
        snprintf(skills_dir, sizeof(skills_dir), "%s/skills", workspace_dir);
        n = prompt_build_skills(b->skills, sizeof(b->skills), skills_dir);
        if (n > 0) total += n;
    }

    /* System context */
    n = sysinfo_snapshot(b->system_context, sizeof(b->system_context));
    if (n > 0) total += n;

    /* Rules */
    n = prompt_build_rules(b->rules, sizeof(b->rules), cfg);
    if (n > 0) total += n;

    /* Project context */
    n = build_project_context(b->project_context,
                              sizeof(b->project_context), workspace_dir);
    if (n > 0) total += n;

    return total;
}

/*
 * Assemble all non-empty sections into a single string with headers.
 * Returns total length written.
 */
int prompt_assemble(const SystemPromptBuilder *b, char *output,
                    int output_size) {
    if (!b || !output || output_size < 1) return 0;

    int pos = 0;

    /* Identity (no header, it IS the identity) */
    if (b->identity[0]) {
        pos += snprintf(output + pos, output_size - pos,
            "%s\n\n", b->identity);
    }

    /* Tools */
    if (b->tools[0] && pos < output_size - 64) {
        pos += snprintf(output + pos, output_size - pos,
            "## Available Tools\n%s\n", b->tools);
    }

    /* Skills */
    if (b->skills[0] && pos < output_size - 64) {
        pos += snprintf(output + pos, output_size - pos,
            "## Skills\n%s\n", b->skills);
    }

    /* System context */
    if (b->system_context[0] && pos < output_size - 64) {
        pos += snprintf(output + pos, output_size - pos,
            "## System\n%s\n", b->system_context);
    }

    /* Rules */
    if (b->rules[0] && pos < output_size - 64) {
        pos += snprintf(output + pos, output_size - pos,
            "## Rules\n%s\n", b->rules);
    }

    /* Project context */
    if (b->project_context[0] && pos < output_size - 64) {
        pos += snprintf(output + pos, output_size - pos,
            "## Project\n%s\n", b->project_context);
    }

    return pos;
}
