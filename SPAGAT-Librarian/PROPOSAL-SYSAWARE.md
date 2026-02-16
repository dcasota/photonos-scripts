# PROPOSAL: System-Aware Filesystem & Environment Intelligence

*Phase 3.5 Extension for SPAGAT-Librarian*
*Version: 1.0*
*Date: 2026-02-16*

---

## Summary

Extend SPAGAT-Librarian's AI agent with full filesystem access across `/` (not limited to workspace) and system environment awareness. This provides MCP Filesystem-equivalent capabilities as native built-in tools, plus a system context layer that lets the agent "learn" about its host environment -- all fully offline using only POSIX APIs.

---

## Motivation

The current tool framework (`src/ai/tools.c`) has 4 basic tools (`read_file`, `write_file`, `list_dir`, `shell`) with naive path traversal protection (`..` substring rejection) and workspace-only assumptions. This is insufficient for a system administration agent on Photon OS that needs to:

- Inspect system configurations (`/etc/`, `/proc/`, `/sys/`)
- Navigate the full filesystem to understand project layouts
- Edit configuration files outside the workspace
- Understand hardware capabilities, resource usage, and OS state
- Build persistent knowledge about its host over time

The MCP Filesystem Server (Anthropic's reference implementation) provides 14 tools for comprehensive filesystem operations. We replicate this functionality natively in C using POSIX APIs -- zero external dependencies, zero network, zero Node.js.

---

## Architecture

### Two New Modules

```
src/
├── ai/
│   ├── tools.c            # EXISTING: tool registry + 4 basic tools
│   ├── tools_fs.c         # NEW: 14 MCP-equivalent filesystem tools
│   └── tools_sysinfo.c    # NEW: system context snapshot + live tools
├── ai/
│   └── ai.h               # Updated: new tool declarations
└── util/
    └── journal.h           # EXISTING: logging (tools log operations)
```

### Access Control Model

Unlike MCP Filesystem which restricts to allowed directories, SPAGAT-Librarian uses a **tiered permission model** controlled via `config.json`:

```json
{
  "filesystem": {
    "access_mode": "full",
    "allowed_paths": ["/"],
    "denied_paths": [
      "/proc/kcore",
      "/dev/sd*",
      "/dev/nvme*",
      "/boot/efi"
    ],
    "read_only_paths": [
      "/proc",
      "/sys",
      "/boot"
    ],
    "max_file_size_read": 10485760,
    "max_file_size_write": 5242880,
    "max_search_depth": 20,
    "max_search_results": 1000
  }
}
```

| Mode | Behavior |
|------|----------|
| `workspace` | Original behavior: restrict to `~/.spagat/workspace/` only |
| `home` | Access `$HOME` and below |
| `full` | Access `/` with deny-list exclusions (default for Photon OS admin use) |

Path validation uses `realpath()` to resolve symlinks, then checks against allow/deny lists. Deny-list entries support glob patterns via `fnmatch()`.

---

## Filesystem Tools (MCP-Equivalent)

Full parity with the 14 tools from `@modelcontextprotocol/server-filesystem`:

### Read Operations (8 tools)

| Tool | MCP Equivalent | Input | Description |
|------|----------------|-------|-------------|
| `read_text_file` | `read_text_file` | `path` + optional `head`/`tail` (line counts) | Read file as UTF-8 text, with optional head/tail line limiting |
| `read_binary_file` | `read_media_file` | `path` | Read binary file, return base64-encoded content with size |
| `read_multiple_files` | `read_multiple_files` | `path1\npath2\n...` | Read multiple files in one call, partial failures don't abort |
| `list_directory` | `list_directory` | `path` | List entries with `[FILE]`/`[DIR]`/`[LINK]` prefixes |
| `list_directory_sizes` | `list_directory_with_sizes` | `path` + optional `sort_by` (name/size) | List with sizes, totals, and summary statistics |
| `directory_tree` | `directory_tree` | `path` + optional `exclude_patterns` | Recursive JSON tree structure with depth limiting |
| `search_files` | `search_files` | `path` + `pattern` + optional `exclude_patterns` | Recursive glob search using `fnmatch()` + `nftw()` |
| `get_file_info` | `get_file_info` | `path` | Full `stat()` metadata: size, permissions, timestamps, type, owner |

### Write Operations (4 tools)

| Tool | MCP Equivalent | Input | Description |
|------|----------------|-------|-------------|
| `write_file` | `write_file` | `path\ncontent` | Create or overwrite file (with size limit enforcement) |
| `edit_file` | `edit_file` | `path\nold_text\nnew_text` + optional `dry_run` | Find-and-replace with diff preview, preserves indentation |
| `create_directory` | `create_directory` | `path` | Recursive mkdir (`mkdir -p` equivalent), idempotent |
| `move_file` | `move_file` | `source\ndestination` | Move/rename via `rename()`, fails if destination exists |

### Management (2 tools)

| Tool | MCP Equivalent | Input | Description |
|------|----------------|-------|-------------|
| `delete_file` | *(not in MCP)* | `path` | Remove file or empty directory (with confirmation pattern) |
| `list_allowed_paths` | `list_allowed_directories` | *(none)* | Show current access control configuration |

### Tool Annotations

Each tool carries metadata for the LLM:

```c
typedef struct {
    char name[64];
    char description[256];
    ai_tool_handler_fn handler;
    bool read_only;       /* safe to call without side effects */
    bool idempotent;      /* safe to retry with same args */
    bool destructive;     /* may overwrite/delete data */
} AITool;
```

| Tool | read_only | idempotent | destructive |
|------|-----------|------------|-------------|
| `read_text_file` | true | - | - |
| `read_binary_file` | true | - | - |
| `read_multiple_files` | true | - | - |
| `list_directory` | true | - | - |
| `list_directory_sizes` | true | - | - |
| `directory_tree` | true | - | - |
| `search_files` | true | - | - |
| `get_file_info` | true | - | - |
| `list_allowed_paths` | true | - | - |
| `create_directory` | false | true | false |
| `write_file` | false | true | true |
| `edit_file` | false | false | true |
| `move_file` | false | false | false |
| `delete_file` | false | false | true |

---

## System Environment Tools

### Passive: System Context Snapshot

A structured text block gathered at agent startup and prepended to the system prompt. Refreshed per session or on `system_refresh` tool call.

**Sources (all from `/proc`, `/sys`, POSIX APIs):**

| Category | Source | Data |
|----------|--------|------|
| **OS** | `/etc/os-release`, `uname()` | Photon OS version, kernel, arch, hostname |
| **CPU** | `/proc/cpuinfo`, `/proc/loadavg` | Model, cores, threads, current load |
| **RAM** | `/proc/meminfo` | Total, free, available, swap, buffers/cached |
| **Storage** | `statvfs()` on `/`, `/home`, workspace | Total, used, free, filesystem type per mount |
| **Mounts** | `/proc/mounts` | All mounted filesystems and options |
| **Network** | `/sys/class/net/`, `getifaddrs()` | Interface names, IPs, MAC addresses, state |
| **Time** | `localtime()`, `/etc/localtime` | Current datetime, timezone, uptime from `/proc/uptime` |
| **User** | `getuid()`, `getpwuid()`, `getgroups()` | Current user, UID, groups, home dir |
| **Process** | `/proc/self/status` | Own PID, memory usage, threads |

**Example output injected into system prompt:**

```
[System Context - 2026-02-16 14:30:00 UTC]
OS: Photon OS 5.0 (Linux 6.1.75 x86_64)
Host: photon-dev
CPU: Intel Xeon E-2288G (8 cores, 16 threads), load: 0.42 0.38 0.35
RAM: 7.8 GiB total, 3.2 GiB available, 0 swap
Storage:
  /      ext4  48.0G total, 12.3G used (25%), 35.7G free
  /home  ext4  96.0G total, 24.1G used (25%), 71.9G free
Network: eth0 (192.168.1.100/24, UP), lo (127.0.0.1, UP)
User: admin (uid=1000), groups: wheel,docker
Uptime: 14d 6h 23m
```

### Active: Live System Tools (3 tools)

| Tool | Input | Description |
|------|-------|-------------|
| `system_info` | *(none)* or category name | Return current system context snapshot (all or specific category) |
| `disk_usage` | `path` | `statvfs()` on specific path: total, used, free, inodes |
| `process_list` | optional `sort_by` (cpu/mem/name) | Parse `/proc/*/stat` for top processes (PID, name, CPU%, MEM%, state) |

---

## Persistent Environment Learning

The agent builds knowledge over time using the existing memory system (`src/ai/memory.c`):

### Automatic Facts

On first run and periodically (via heartbeat), the agent stores discovered facts:

```
system.os = "Photon OS 5.0"
system.kernel = "6.1.75"
system.arch = "x86_64"
system.hostname = "photon-dev"
system.cpu_model = "Intel Xeon E-2288G"
system.cpu_cores = "8"
system.ram_total = "8192 MB"
system.disk_root_total = "48 GB"
system.timezone = "UTC"
```

### SYSTEM.md

A markdown file in the workspace that accumulates rich observations:

```
~/.spagat/workspace/SYSTEM.md
```

The agent can read and update this file to record:
- Installed packages and versions discovered during tasks
- Service configurations it has examined
- Network topology observations
- Performance baselines (average load, memory patterns)
- Custom notes about the environment

This file is loaded into context alongside MEMORY.md, giving the agent persistent environmental awareness across sessions.

### Learning Flow

```
┌─────────────────────────────────────────────┐
│              Agent Startup                   │
├─────────────────────────────────────────────┤
│  1. Gather system context snapshot           │
│  2. Load SYSTEM.md from workspace            │
│  3. Compare: detect changes since last run   │
│  4. Update memory keys + SYSTEM.md           │
│  5. Inject snapshot into system prompt       │
└─────────────────────────────────────────────┘
         ↓                           ↓
  [During conversation]       [Via heartbeat]
  Agent calls system_info,    Periodic refresh:
  disk_usage, process_list    re-gather snapshot,
  tools for live data         update SYSTEM.md
```

---

## Security Model

### Path Validation (Enhanced)

Replace the current naive `strstr(input, "..")` check with proper validation:

```c
bool fs_validate_path(const char *path, bool write_required) {
    /* 1. Resolve to absolute canonical path via realpath() */
    /* 2. Check against denied_paths (glob via fnmatch) */
    /* 3. If write_required, check not in read_only_paths */
    /* 4. Check against allowed_paths */
    /* 5. Verify file size limits for read/write */
    return true;
}
```

### Dangerous Operation Protection

| Protection | Implementation |
|------------|----------------|
| **Deny-list** | Block access to `/proc/kcore`, `/dev/sd*`, `/dev/nvme*`, `/boot/efi` |
| **Read-only enforcement** | `/proc`, `/sys`, `/boot` are read-only regardless of config |
| **Size limits** | Max 10MB read, 5MB write (configurable) |
| **Depth limits** | Max 20 levels for recursive search/tree (configurable) |
| **Binary detection** | `read_text_file` warns on binary content, `read_binary_file` for intentional binary reads |
| **Symlink resolution** | All paths resolved via `realpath()` before access check |
| **Delete safety** | `delete_file` requires the path to not be `/`, `/home`, `/etc`, or any mount point |
| **Audit logging** | All write/delete operations logged to journal with path, user, timestamp |

### Comparison with MCP Filesystem Security

| Feature | MCP Filesystem | SPAGAT-Librarian |
|---------|---------------|-------------------|
| Path restriction | Allowed directories list | Tiered: allow + deny + read-only lists |
| Symlink handling | `realpath()` resolution | `realpath()` resolution |
| Write protection | Not built-in (Docker `ro` mount) | Native read-only path list |
| Delete protection | Not included | Deny-list + mount point check |
| Size limits | Not enforced | Configurable per-operation |
| Audit logging | Not included | Journal log for all mutations |
| Glob deny patterns | Not included | `fnmatch()` for deny-list |

---

## Implementation Plan

### New Files

| File | Size Est. | Description |
|------|-----------|-------------|
| `src/ai/tools_fs.c` | ~12 KB | 14 filesystem tools + path validation |
| `src/ai/tools_sysinfo.c` | ~8 KB | System context snapshot + 3 live tools |
| `src/ai/tools_fs.h` | ~2 KB | Filesystem config struct, validation API |

### Modified Files

| File | Changes |
|------|---------|
| `src/ai/tools.c` | Call `tools_fs_init()` and `tools_sysinfo_init()` from `ai_tools_init()` |
| `src/ai/ai.h` | Add `AITool` annotation fields, new init/cleanup declarations |
| `src/agent/agent.h` | Add `FilesystemConfig` to `SpagatConfig` |
| `src/agent/onboard.c` | Generate default `SYSTEM.md`, update config defaults |
| `src/agent/workspace.c` | No changes (SYSTEM.md lives in workspace_dir) |
| `src/ai/local.c` | Prepend system context snapshot to system prompt |
| `Makefile` | Add `tools_fs.c`, `tools_sysinfo.c` to SOURCES |
| `CMakeLists.txt` | Add same |

### POSIX APIs Used (No New Dependencies)

| API | Purpose |
|-----|---------|
| `stat()`, `lstat()` | File metadata, type detection |
| `realpath()` | Canonical path resolution + symlink handling |
| `statvfs()` | Filesystem space info |
| `nftw()` | Recursive directory traversal (search, tree) |
| `fnmatch()` | Glob pattern matching for deny-list and search |
| `opendir()`, `readdir()` | Directory listing |
| `rename()` | Move/rename files |
| `mkdir()` | Create directories |
| `unlink()`, `rmdir()` | Delete files/directories |
| `uname()` | OS/kernel info |
| `getifaddrs()` | Network interface enumeration |
| `getpwuid()`, `getuid()` | User info |

All available on Photon OS with `_POSIX_C_SOURCE=200809L` + `_DEFAULT_SOURCE`. Zero new library dependencies.

---

## CLI Extensions

```bash
# System info
spagat-librarian sysinfo              # Print system context snapshot
spagat-librarian sysinfo cpu          # CPU info only
spagat-librarian sysinfo disk /home   # Disk usage for /home

# Filesystem config
spagat-librarian fs config            # Show current filesystem access config
spagat-librarian fs allowed           # List allowed/denied/read-only paths
```

---

## Success Criteria

1. All 14 MCP filesystem tool equivalents pass functional tests
2. Path validation blocks all denied paths and enforces read-only
3. System context snapshot gathers all categories in < 50ms
4. `SYSTEM.md` persists and grows across sessions
5. No new external dependencies (pure POSIX)
6. All tool operations logged to journal
7. Each new source file < 15 KB
8. Zero security regressions (no access to denied paths, no unbounded reads)

---

## Timeline

| Week | Deliverable |
|------|-------------|
| 1 | `tools_fs.h` + path validation + 8 read tools in `tools_fs.c` |
| 2 | 4 write tools + `delete_file` + `list_allowed_paths` |
| 3 | `tools_sysinfo.c` + system context snapshot + system prompt injection |
| 4 | SYSTEM.md learning + heartbeat integration + config + tests |

---

*This proposal extends PROPOSAL.md Phase 3 (Local Tools) with full filesystem access and Phase 3.5 (System Awareness) as a new capability layer.*
