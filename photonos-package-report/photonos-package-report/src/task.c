/* task.c — pr_task_t / pr_task_list_t lifecycle helpers.
 *
 * Mirrors the PS PSCustomObject + List<PSCustomObject> usage in
 * photonos-package-report.ps1 L 254 (List creation) and L 345-372
 * (per-spec PSCustomObject construction).
 *
 * In PS the GC handles strings; in C we own them. Every pr_task_t string
 * field is malloc'd (or "" duplicated). content is a NULL-terminated array
 * of malloc'd line strings.
 */
#include "pr_types.h"

#include <stdlib.h>
#include <string.h>

void pr_task_free(pr_task_t *t)
{
    if (t == NULL) return;
    if (t->content) {
        for (size_t i = 0; i < t->content_lines; i++) free(t->content[i]);
        free(t->content);
    }
    free(t->Spec);
    free(t->Version);
    free(t->Name);
    free(t->SubRelease);
    free(t->SpecRelativePath);
    free(t->Source0);
    free(t->url);
    free(t->SHAName);
    free(t->srcname);
    free(t->gem_name);
    free(t->group);
    free(t->extra_version);
    free(t->main_version);
    free(t->upstreamversion);
    free(t->dialogsubversion);
    free(t->subversion);
    free(t->byaccdate);
    free(t->libedit_release);
    free(t->libedit_version);
    free(t->ncursessubversion);
    free(t->cpan_name);
    free(t->xproto_ver);
    free(t->_url_src);
    free(t->_repo_ver);
    free(t->commit_id);
    memset(t, 0, sizeof *t);
}

void pr_task_list_init(pr_task_list_t *list)
{
    list->items = NULL;
    list->count = 0;
    list->cap   = 0;
}

void pr_task_list_free(pr_task_list_t *list)
{
    if (list == NULL) return;
    for (size_t i = 0; i < list->count; i++) pr_task_free(&list->items[i]);
    free(list->items);
    list->items = NULL;
    list->count = list->cap = 0;
}

int pr_task_list_add(pr_task_list_t *list, pr_task_t *task)
{
    if (list->count == list->cap) {
        size_t newcap = list->cap == 0 ? 64 : list->cap * 2;
        pr_task_t *p = (pr_task_t *)realloc(list->items, newcap * sizeof *p);
        if (p == NULL) return -1;
        list->items = p;
        list->cap   = newcap;
    }
    /* Move semantics: copy struct, then zero the source so it does NOT
     * own the strings anymore. The caller must not free task->X after
     * this returns. */
    list->items[list->count++] = *task;
    memset(task, 0, sizeof *task);
    return 0;
}
