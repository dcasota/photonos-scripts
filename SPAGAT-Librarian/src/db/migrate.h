#ifndef MIGRATE_H
#define MIGRATE_H

#include <stdbool.h>

#define SPAGAT_DB_VERSION 3

bool db_migrate_check_and_run(void);
int db_get_version(void);
bool db_set_version(int version);

#endif
