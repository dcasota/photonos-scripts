/* state.c — pr_state_t lifecycle. */
#include "pr_state.h"

#include <stdlib.h>
#include <string.h>

static char *new_empty(void)
{
    char *s = (char *)malloc(1);
    if (s) s[0] = '\0';
    return s;
}

void pr_state_init(pr_state_t *s)
{
    if (s == NULL) return;
    s->Source0            = new_empty();
    s->version            = new_empty();
    s->UpdateAvailable    = new_empty();
    s->UpdateURL          = new_empty();
    s->HealthUpdateURL    = new_empty();
    s->UpdateDownloadName = new_empty();
    s->SHAValue           = new_empty();
    s->Warning            = new_empty();
    s->ArchivationDate    = new_empty();
}

void pr_state_free(pr_state_t *s)
{
    if (s == NULL) return;
    free(s->Source0);
    free(s->version);
    free(s->UpdateAvailable);
    free(s->UpdateURL);
    free(s->HealthUpdateURL);
    free(s->UpdateDownloadName);
    free(s->SHAValue);
    free(s->Warning);
    free(s->ArchivationDate);
    memset(s, 0, sizeof *s);
}
