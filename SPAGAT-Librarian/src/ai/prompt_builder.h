#ifndef PROMPT_BUILDER_H
#define PROMPT_BUILDER_H

#include "autonomy.h"
#include <stdbool.h>

#define PROMPT_MAX_SECTION 4096

typedef struct {
    char identity[PROMPT_MAX_SECTION];
    char tools[PROMPT_MAX_SECTION];
    char skills[PROMPT_MAX_SECTION];
    char system_context[2048];
    char rules[2048];
    char project_context[1024];
} SystemPromptBuilder;

/* Build the complete system prompt based on autonomy config */
int prompt_build(SystemPromptBuilder *b, const AutonomyConfig *cfg,
                 const char *workspace_dir);

/* Assemble all sections into a single string */
int prompt_assemble(const SystemPromptBuilder *b, char *output, int output_size);

/* Build tool descriptions based on registered tools and autonomy level */
int prompt_build_tools(char *output, int output_size,
                       const AutonomyConfig *cfg);

/* Load and inject skill content from workspace skills directory */
int prompt_build_skills(char *output, int output_size,
                        const char *skills_dir);

/* Build rules section based on autonomy level */
int prompt_build_rules(char *output, int output_size,
                       const AutonomyConfig *cfg);

#endif
