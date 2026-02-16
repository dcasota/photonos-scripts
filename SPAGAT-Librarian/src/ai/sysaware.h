#ifndef SYSAWARE_H
#define SYSAWARE_H

#include <stdbool.h>

/* Store system facts as memory keys (system.os, system.kernel, etc.)
   Uses ai_memory_set(0, "system", key, value) for each fact.
   Returns number of facts stored. */
int sysaware_store_facts(void);

/* Compare current system snapshot against stored memory keys.
   Detects changes (new kernel, IP change, disk usage change, etc.)
   Writes change summary to `changes` buffer.
   Returns number of changes detected. */
int sysaware_detect_changes(char *changes, int changes_size);

/* Refresh SYSTEM.md in the workspace with current system info
   plus accumulated observations. The file is rewritten with:
   1. Current snapshot header
   2. Stored facts section
   3. Change history (appended, not overwritten)
   Returns true on success. */
bool sysaware_refresh_system_md(const char *workspace_dir);

/* Run the full sysaware cycle:
   1. Store facts
   2. Detect changes
   3. Refresh SYSTEM.md
   Meant to be called from heartbeat or on startup. */
int sysaware_update(const char *workspace_dir);

#endif
