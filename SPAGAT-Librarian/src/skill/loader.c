#include "skill.h"
#include "../util/util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>

bool skill_init(const char *skills_dir) {
    if (!skills_dir || !skills_dir[0]) return false;

    struct stat st;
    if (stat(skills_dir, &st) != 0) {
        fprintf(stderr, "Skills directory does not exist: %s\n", skills_dir);
        return false;
    }

    if (!S_ISDIR(st.st_mode)) {
        fprintf(stderr, "Not a directory: %s\n", skills_dir);
        return false;
    }

    return true;
}

bool skill_parse_content(const char *content, char *name, int name_size,
                         char *description, int desc_size) {
    if (!content || !name || !description) return false;
    if (name_size < 1 || desc_size < 1) return false;

    name[0] = '\0';
    description[0] = '\0';

    const char *p = content;

    /* Skip leading whitespace / blank lines */
    while (*p == '\n' || *p == '\r' || *p == ' ' || *p == '\t') {
        p++;
    }

    /* Expect "# Skill Name" on the first non-blank line */
    if (!str_starts_with(p, "# ")) {
        return false;
    }

    p += 2; /* skip "# " */

    /* Extract name until end of line */
    const char *eol = strchr(p, '\n');
    if (!eol) {
        /* Single line file - name only */
        str_safe_copy(name, p, name_size);
        /* Trim trailing whitespace */
        char *end = name + strlen(name) - 1;
        while (end >= name && (*end == '\r' || *end == ' ' || *end == '\t')) {
            *end = '\0';
            end--;
        }
        return true;
    }

    /* Copy name */
    int name_len = (int)(eol - p);
    if (name_len >= name_size) name_len = name_size - 1;
    memcpy(name, p, name_len);
    name[name_len] = '\0';

    /* Trim trailing whitespace from name */
    char *end = name + strlen(name) - 1;
    while (end >= name && (*end == '\r' || *end == ' ' || *end == '\t')) {
        *end = '\0';
        end--;
    }

    /* Skip past the name line */
    p = eol + 1;

    /* Skip blank lines */
    while (*p == '\n' || *p == '\r') {
        p++;
    }

    /* Collect description until we hit "## " or end of content */
    int desc_pos = 0;
    while (*p && !str_starts_with(p, "## ")) {
        if (desc_pos < desc_size - 1) {
            description[desc_pos++] = *p;
        }
        p++;
    }
    description[desc_pos] = '\0';

    /* Trim trailing whitespace from description */
    end = description + strlen(description) - 1;
    while (end >= description && (*end == '\n' || *end == '\r' ||
           *end == ' ' || *end == '\t')) {
        *end = '\0';
        end--;
    }

    return name[0] != '\0';
}

bool skill_load(const char *filepath, Skill *skill) {
    if (!filepath || !skill) return false;

    memset(skill, 0, sizeof(Skill));
    str_safe_copy(skill->filepath, filepath, sizeof(skill->filepath));

    FILE *fp = fopen(filepath, "r");
    if (!fp) {
        fprintf(stderr, "Cannot open skill file: %s: %s\n",
                filepath, strerror(errno));
        return false;
    }

    /* Read entire file into content buffer */
    size_t total = 0;
    size_t nread;
    while (total < SKILL_MAX_CONTENT_LEN - 1 &&
           (nread = fread(skill->content + total, 1,
                          SKILL_MAX_CONTENT_LEN - 1 - total, fp)) > 0) {
        total += nread;
    }
    skill->content[total] = '\0';
    fclose(fp);

    if (total == 0) {
        fprintf(stderr, "Empty skill file: %s\n", filepath);
        return false;
    }

    /* Parse name and description from content */
    if (!skill_parse_content(skill->content, skill->name,
                             sizeof(skill->name), skill->description,
                             sizeof(skill->description))) {
        fprintf(stderr, "Failed to parse skill: %s\n", filepath);
        return false;
    }

    skill->loaded = true;
    return true;
}

bool skill_load_all(const char *skills_dir, SkillList *list) {
    if (!skills_dir || !list) return false;

    memset(list, 0, sizeof(SkillList));

    DIR *dir = opendir(skills_dir);
    if (!dir) {
        fprintf(stderr, "Cannot open skills directory: %s: %s\n",
                skills_dir, strerror(errno));
        return false;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && list->count < SKILL_MAX_SKILLS) {
        /* Only process .md files */
        const char *name = entry->d_name;
        size_t nlen = strlen(name);

        if (nlen < 4) continue;
        if (strcmp(name + nlen - 3, ".md") != 0) continue;

        /* Build full path */
        char filepath[1024];
        snprintf(filepath, sizeof(filepath), "%s/%s", skills_dir, name);

        /* Verify it's a regular file */
        struct stat st;
        if (stat(filepath, &st) != 0 || !S_ISREG(st.st_mode)) {
            continue;
        }

        /* Load the skill */
        if (skill_load(filepath, &list->skills[list->count])) {
            list->count++;
        }
    }

    closedir(dir);
    return true;
}

bool skill_get_by_name(const SkillList *list, const char *name, Skill *skill) {
    if (!list || !name || !skill) return false;

    for (int i = 0; i < list->count; i++) {
        if (str_equals_ignore_case(list->skills[i].name, name)) {
            memcpy(skill, &list->skills[i], sizeof(Skill));
            return true;
        }
    }

    return false;
}

bool skill_save(const char *filepath, const Skill *skill) {
    if (!filepath || !skill) return false;

    FILE *fp = fopen(filepath, "w");
    if (!fp) {
        fprintf(stderr, "Cannot write skill file: %s: %s\n",
                filepath, strerror(errno));
        return false;
    }

    /* If content is populated, write it directly */
    if (skill->content[0]) {
        fputs(skill->content, fp);
    } else {
        /* Generate content from name and description */
        fprintf(fp, "# %s\n\n", skill->name);
        if (skill->description[0]) {
            fprintf(fp, "%s\n", skill->description);
        }
    }

    fclose(fp);
    return true;
}

void skill_list_print(const SkillList *list) {
    if (!list || list->count == 0) {
        printf("No skills found.\n");
        return;
    }

    printf("Skills (%d):\n", list->count);
    for (int i = 0; i < list->count; i++) {
        const Skill *s = &list->skills[i];
        printf("  %-20s %s\n", s->name,
               s->description[0] ? s->description : "(no description)");
    }
}
