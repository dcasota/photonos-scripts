#ifndef MIGRATE_H
#define MIGRATE_H

#include <stdbool.h>

/* M48-KanbanCVECard: v4 adds upstream_commit / backport_commit /
 * cve_ids columns to `items`. Old rows migrate cleanly with empty
 * defaults; the migration is idempotent on already-v4 schemas. */
#define SPAGAT_DB_VERSION 4

bool db_migrate_check_and_run(void);
int db_get_version(void);
bool db_set_version(int version);

#endif
