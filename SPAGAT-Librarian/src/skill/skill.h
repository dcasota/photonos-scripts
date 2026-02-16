#ifndef SKILL_H
#define SKILL_H

#include "spagat.h"
#include <stdbool.h>

#define SKILL_MAX_NAME_LEN 64
#define SKILL_MAX_DESC_LEN 256
#define SKILL_MAX_CONTENT_LEN 4096
#define SKILL_MAX_SKILLS 32

typedef struct {
    char name[SKILL_MAX_NAME_LEN];
    char description[SKILL_MAX_DESC_LEN];
    char filepath[512];
    char content[SKILL_MAX_CONTENT_LEN];
    bool loaded;
} Skill;

typedef struct {
    Skill skills[SKILL_MAX_SKILLS];
    int count;
} SkillList;

/* Skill management */
bool skill_init(const char *skills_dir);
bool skill_load(const char *filepath, Skill *skill);
bool skill_load_all(const char *skills_dir, SkillList *list);
bool skill_get_by_name(const SkillList *list, const char *name, Skill *skill);
bool skill_save(const char *filepath, const Skill *skill);
void skill_list_print(const SkillList *list);

/* Skill parsing (SKILL.md format)
 * Format:
 * # Skill Name
 * Description text
 * ## Steps
 * 1. Step one
 * 2. Step two
 */
bool skill_parse_content(const char *content, char *name, int name_size,
                         char *description, int desc_size);

/* Skill execution context */
typedef struct {
    char workspace_dir[1024];
    bool sandbox_enabled;
} SkillExecContext;

/* Skill execution */
bool skill_execute(const Skill *skill, const SkillExecContext *ctx);

#endif
