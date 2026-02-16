# SPAGAT-Librarian Architecture

## Overview

SPAGAT-Librarian is a Kanban task manager written in C11 with POSIX extensions, targeting Linux (Photon OS). It provides a terminal user interface (TUI) via ncurses and a command-line interface (CLI) for scripting. The system integrates local AI inference via llama.cpp (linked at compile time through a C++ bridge), an agent workspace with scheduling, sandboxing, subagent delegation, and a skill execution framework -- all backed by a single SQLite database file. A 5-layer security model governs all AI tool execution.

Version: 0.3.0

## Directory Structure

```
SPAGAT-Librarian/
├── include/
│   └── spagat.h                # Core types: ItemStatus (6), ItemPriority (5), Item,
│                                #   ItemList, Project, ProjectList, Dependency, Template, Session
├── src/
│   ├── main.c                  # Entry point, argument routing to CLI or TUI
│   ├── cli/
│   │   ├── cli.h               # CLI function declarations (all layers)
│   │   ├── cli.c               # Core CLI: init, add, show, list, edit, move,
│   │   │                       #   delete, tags, stats, filter, export, board
│   │   ├── cli_ext.c           # Extended CLI: project, template, depend, undepend,
│   │   │                       #   deps, subtasks, due, time, session, priority
│   │   ├── cli_ai.c            # AI CLI: agent entry, tool call extraction,
│   │   │                       #   generate_with_tools loop, ai chat, ai history
│   │   ├── cli_ai_cmds.c       # AI command implementations: model, checkpoint,
│   │   │                       #   cron, memory, skill, status, onboard, workspace
│   │   ├── cli_ai_subagent.c   # Subagent CLI: spawn, list, kill, output
│   │   └── cli_dispatch.c      # DB-command dispatcher for structured commands
│   ├── db/
│   │   ├── db.h                # Database function declarations (CRUD, stats, sessions)
│   │   ├── db.c                # Core SQLite: open, close, init_schema, item CRUD, stats
│   │   ├── db_ext.c            # Extended queries: priority filter, due dates,
│   │   │                       #   dependencies, subtasks, time tracking, sessions
│   │   ├── db_project.c        # Project CRUD operations
│   │   ├── db_template.c       # Template CRUD operations
│   │   ├── migrate.h           # Migration declarations (SPAGAT_DB_VERSION = 3)
│   │   └── migrate.c           # Schema migration v1 -> v2 -> v3
│   ├── tui/
│   │   ├── tui.h               # TUIState struct and public interface
│   │   ├── tui_common.h        # Internal TUI types, 15 color pair constants,
│   │   │                       #   forward declarations for all TUI functions
│   │   ├── tui.c               # TUI init (ncurses, colors), main event loop, cleanup
│   │   ├── tui_board.c         # Board rendering: header, footer, 6 columns, help dialog
│   │   ├── tui_input.c         # Keyboard input, vim-style navigation, text editing,
│   │   │                       #   status/priority dropdowns
│   │   ├── tui_dialogs.c       # Dialog windows: add, edit, delete, move, search
│   │   ├── tui_dialogs_misc.c  # Additional dialogs: priority, due date, parent,
│   │   │                       #   dependency, git branch, time tracking, project,
│   │   │                       #   template selection, swimlane toggle
│   │   └── tui_ext.c           # Priority/due indicators, extended edit fields
│   ├── ai/
│   │   ├── ai.h                # AI interface: ConvMessage, ConvHistory, Checkpoint,
│   │   │                       #   AIProvider, tool handler typedefs, sysinfo/git decls
│   │   ├── local.c             # llama.cpp provider: model loading via llama_bridge,
│   │   │                       #   context creation, sampler chain, token generation
│   │   │                       #   with retry, config parsing, journal log redirect
│   │   ├── local_prompt.h      # System prompt builder, prompt formatter declarations
│   │   ├── local_prompt.c      # System prompt construction, chat template formatting,
│   │   │                       #   conversation history assembly with prompt_builder
│   │   ├── llama_bridge.h      # C-linkage wrapper API: opaque handles, tokenize,
│   │   │                       #   decode, sample, chat template, log callback
│   │   ├── llama_bridge.cpp    # C++ bridge: dual API support (new + old/BitNet),
│   │   │                       #   selected via LLAMA_OLD_API compile flag
│   │   ├── conversation.c      # Conversation SQLite table, message CRUD,
│   │   │                       #   checkpoint save/load with hand-written JSON
│   │   ├── streaming.c         # Token streaming: AIStreamContext, stream to ncurses
│   │   │                       #   WINDOW or buffer, Esc cancellation
│   │   ├── memory.c            # Agent memory: agent_memory SQLite table
│   │   │                       #   (project_id, scope, key, value), MEMORY.md file I/O
│   │   ├── tools.c             # Tool registry (max 64), autonomy-gated execution,
│   │   │                       #   rate limiting, sensitive path check, audit logging,
│   │   │                       #   output sanitization, execpolicy initialization
│   │   ├── tools_builtin.c     # Legacy 4 tools: read_file, write_file, list_dir, shell
│   │   ├── tools_fs.h          # FsConfig struct, path validation, 14 fs tool declarations
│   │   ├── tools_fs.c          # Filesystem config, validation, path resolution,
│   │   │                       #   base64 encoding, helper utilities, tool registration
│   │   ├── tools_fs_read.c     # Read tools: read_text_file, read_binary_file,
│   │   │                       #   read_multiple_files, list_directory, list_directory_sizes,
│   │   │                       #   directory_tree, search_files, get_file_info, list_allowed_paths
│   │   ├── tools_fs_write.c    # Write tools: write_file, edit_file, create_directory,
│   │   │                       #   move_file, delete_file
│   │   ├── tools_sysinfo.c     # System info tools: system_info (full snapshot),
│   │   │                       #   disk_usage, process_list; reads /proc, uname, statvfs
│   │   ├── git_tools.h         # Git tool init declaration
│   │   ├── git_tools.c         # 7 git tools via fork/exec: git_status, git_diff,
│   │   │                       #   git_log, git_branch, git_commit, git_add, git_show;
│   │   │                       #   10-second timeout per command
│   │   ├── autonomy.h          # AutonomyLevel enum (5 levels), AutonomyConfig struct,
│   │   │                       #   rate limiting, cooldown, shell allowlist declarations
│   │   ├── autonomy.c          # Autonomy level definitions, tool permission matrix,
│   │   │                       #   observe-mode allowlist, rate limiting, cooldown,
│   │   │                       #   sensitive path detection, session logging
│   │   ├── execpolicy.h        # PolicyDecision enum, PolicyResult struct,
│   │   │                       #   rule evaluation declarations
│   │   ├── execpolicy.c        # Prefix-based command rules: allow/prompt/forbidden
│   │   │                       #   lists, file-based rule loading
│   │   ├── sanitize.h          # Secret redaction declarations
│   │   ├── sanitize.c          # Regex-free secret detection: API keys, passwords,
│   │   │                       #   tokens; in-place [REDACTED] replacement
│   │   ├── prompt_builder.h    # SystemPromptBuilder struct (6 sections), assembly decls
│   │   ├── prompt_builder.c    # Dynamic system prompt construction: identity, tools,
│   │   │                       #   skills, system context, rules, project context;
│   │   │                       #   autonomy-level-aware rule generation
│   │   ├── compaction.h        # Compaction API: threshold check, compact, token estimation
│   │   ├── compaction.c        # Heuristic conversation compaction: token estimation
│   │   │                       #   (chars/4), 75% threshold, oldest-message summarization,
│   │   │                       #   DB replacement of compacted messages
│   │   ├── linux_sandbox.h     # Landlock + Seccomp declarations
│   │   ├── linux_sandbox.c     # Landlock LSM filesystem restrictions, Seccomp-BPF
│   │   │                       #   syscall filter (blocks ptrace, mount, reboot, etc.),
│   │   │                       #   combined shell child sandboxing
│   │   ├── sysaware.h          # System awareness: fact storage, change detection,
│   │   │                       #   SYSTEM.md refresh declarations
│   │   ├── sysaware.c          # Auto-detect and store system facts via agent_memory
│   │   │                       #   (system.os, system.kernel, system.hostname, etc.),
│   │   │                       #   change detection vs stored values, SYSTEM.md generation
│   │   ├── embedded_model.h    # Conditional symbols for objcopy-embedded GGUF,
│   │   │                       #   memfd_create bridge declarations
│   │   └── embedded_model.c    # memfd_create via syscall wrapper, writes embedded GGUF
│   │                           #   data to anonymous fd, returns /proc/self/fd/N path
│   ├── agent/
│   │   ├── agent.h             # WorkspacePaths (11 path buffers), SpagatConfig
│   │   │                       #   (provider, autonomy, retry, per-project prompt),
│   │   │                       #   CronJob, CronJobList
│   │   ├── workspace.c         # Workspace init from $SPAGAT_HOME or ~/.spagat,
│   │   │                       #   recursive mkdir for all subdirs including logs/
│   │   ├── onboard.c           # First-time setup: writes 7 default .md files,
│   │   │                       #   config_set_defaults, initial config_save
│   │   ├── config_io.c         # config_load / config_save: hand-rolled JSON
│   │   │                       #   parser/serializer for SpagatConfig (no cJSON)
│   │   ├── scheduler.c         # Cron scheduler: SQLite cron_jobs table CRUD,
│   │   │                       #   due-job checking with interval_minutes
│   │   ├── sandbox.c           # Security sandbox: realpath()-based path validation,
│   │   │                       #   restricts file access to workspace dir
│   │   ├── heartbeat.c         # HEARTBEAT.md: load file, parse "- " prefixed task lines
│   │   ├── subagent.h          # SubagentManager, Subagent struct (pid, status,
│   │   │                       #   output capture), max 8 concurrent, max depth 1
│   │   └── subagent.c          # Subagent lifecycle: fork/exec spawn, non-blocking
│   │                           #   poll (waitpid), kill, output capture via temp files
│   ├── skill/
│   │   ├── skill.h             # Skill, SkillList (max 32), SkillExecContext types
│   │   ├── loader.c            # Load SKILL.md files from skills directory
│   │   │                       #   (opendir/readdir, parse name/description/steps)
│   │   └── executor.c          # Execute skill steps: shell: (system()),
│   │                           #   prompt: (ai_generate), file: (write to workspace)
│   └── util/
│       ├── util.h              # String utilities, path helpers, env check declarations
│       ├── util.c              # str_trim, str_safe_copy, str_duplicate, str_starts_with,
│       │                       #   str_equals_ignore_case, get_db_path, file_exists,
│       │                       #   env_is_set, is_numeric, get_editor
│       ├── journal.h           # JournalLevel enum, self-rotating log declarations
│       └── journal.c           # Self-rotating log to ~/.spagat/logs/spagat.log,
│                               #   2 MB max per file, 3 rotated files, raw write mode
├── sql/
│   └── schema.sql              # Reference SQL schema (not used at runtime)
├── models/                     # Downloaded GGUF model files (not tracked)
├── skills/                     # Example SKILL.md files
├── CMakeLists.txt              # CMake build configuration
├── Makefile                    # GNU Make build configuration (primary)
└── spagat.spec                 # RPM spec file for Photon OS packaging
```

**File count**: 24 headers + 50 source files (.c/.cpp) = 74 files total.

## Layers

The codebase is organized into ten layers. Each layer is self-contained in its own `src/` subdirectory with dedicated header files. The layers build upward: higher layers may depend on lower layers, never the reverse.

### Layer 1: Core Types (`include/spagat.h`)

Defines the fundamental data structures shared across all layers:

- **ItemStatus**: Enum with 6 Kanban statuses -- Clarification, Won't Fix, Backlog, In Progress, Review, Ready.
- **ItemPriority**: Enum with 5 priority levels -- None, Low, Medium, High, Critical.
- **Item**: Task struct with id, project_id, parent_id, status, priority, title, description, tag, history, git_branch, due_date, timestamps, time_spent, selected.
- **ItemList**: Dynamic array of Items (items pointer, count, capacity).
- **Project**: Project struct with id, name, description, created_at.
- **ProjectList**: Dynamic array of Projects.
- **Dependency**: Directed edge (from_id, to_id) between items.
- **DependencyList**: Dynamic array of Dependencies.
- **Template**: Reusable item template with name, title, description, tag, status, priority.
- **TemplateList**: Dynamic array of Templates.
- **Session**: TUI session state with name, current_project, cursor position, scroll_offsets, swimlane_mode.
- **Constants**: STATUS_NAMES, STATUS_DISPLAY, STATUS_ABBREV, PRIORITY_NAMES, PRIORITY_DISPLAY arrays.
- **Conversion functions**: `status_from_string`, `status_to_string`, `priority_from_string`, etc.

### Layer 2: Database (`src/db/`)

SQLite-based persistence with automatic schema migration. All database operations go through this layer.

**db.c / db.h** -- Core operations:
- `db_open()` / `db_close()`: Connection management.
- `db_init_schema()`: Creates tables and triggers migration check.
- `db_item_add()`, `db_item_get()`, `db_item_update()`, `db_item_delete()`: Item CRUD.
- `db_item_set_status()`: Status change with history tracking.
- `db_items_list()` / `db_items_list_full()`: List items with optional status/project filter.
- `db_stats_*()`: Statistics queries (by status, tag, priority, history).

**db_ext.c** -- Extended queries:
- Priority filtering, due date queries, dependency resolution.
- Subtask listing (parent_id relationships).
- Time tracking (time_spent accumulation).
- Session save/load (serializes TUI state).

**db_project.c** -- Project CRUD: add, get, get_by_name, delete, list.

**db_template.c** -- Template CRUD: add, get, get_by_name, delete, list, instantiate item from template.

**migrate.c / migrate.h** -- Schema versioning:
- `db_migrate_check_and_run()`: Detects version via db_meta, applies migrations sequentially.
- `migrate_v1_to_v2()`: Adds title column, copies description to title.
- `migrate_v2_to_v3()`: Adds project_id, parent_id, priority, git_branch, due_date, time_spent to items; creates projects, templates, dependencies, sessions, conversations, checkpoints, cron_jobs, agent_memory, tool_calls tables.

### Layer 3: TUI (`src/tui/`)

ncurses-based interactive Kanban board, split into logical modules.

**tui.c / tui.h** -- Initialization and lifecycle:
- `tui_init()`: Initialize ncurses, color pairs, TUIState struct.
- `tui_run()`: Main event loop (draw board, handle input, refresh).
- `tui_cleanup()`: Restore terminal state.
- `tui_refresh_items()`: Reload items from database.
- TUIState holds: terminal dimensions, column width, cursor position, scroll offsets per column, color/UTF-8 flags, current project, item list with per-status counts.

**tui_common.h** -- Internal shared definitions:
- 15 color pair constants: COLOR_HEADER, COLOR_SELECTED, COLOR_CURRENT, COLOR_STATUS_0 through COLOR_STATUS_5, COLOR_HELP, COLOR_PRI_CRIT, COLOR_PRI_HIGH, COLOR_PRI_MED, COLOR_COL_TITLE, COLOR_COL_SEL.
- Forward declarations for all TUI functions used across modules.
- `tui_edit_text_field()`, `tui_edit_status_field()`, `tui_edit_priority_field()`, `tui_format_history()`.

**tui_board.c** -- Rendering:
- `tui_draw_header()`: Title bar with version and selection count.
- `tui_draw_footer()`: Keyboard shortcut hints.
- `tui_draw_board()`: 6-column Kanban board with colored items.
- `tui_draw_help()`: Help overlay dialog.

**tui_input.c** -- Input handling:
- `tui_handle_input()`: Main keyboard event dispatcher.
- Vim-style navigation: h/j/k/l for left/down/up/right.
- `tui_toggle_select()`, `tui_select_all_in_column()`, `tui_clear_selection()`: Multi-select.

**tui_dialogs.c** -- Primary dialog windows:
- `tui_dialog_add()`: Create new item.
- `tui_dialog_edit()`: Edit existing item (all fields).
- `tui_dialog_delete()`: Confirm and delete items.
- `tui_dialog_move()`: Batch move items to new status.
- `tui_dialog_search()`: Find items by title/description/tag.

**tui_dialogs_misc.c** -- Secondary dialog windows:
- `tui_dialog_set_priority()`, `tui_dialog_set_due_date()`, `tui_dialog_set_parent()`.
- `tui_dialog_add_dependency()`, `tui_dialog_git_branch()`, `tui_dialog_time_tracking()`.
- `tui_toggle_swimlane_mode()`, `tui_dialog_select_project()`, `tui_dialog_select_template()`.

**tui_ext.c** -- Extended TUI features:
- `tui_draw_priority_indicator()`: Color-coded priority markers.
- `tui_draw_due_indicator()`: Due date proximity markers.

### Layer 4: CLI (`src/cli/`)

Scriptable command-line interface, split into six files by domain.

**cli.h** -- All CLI function declarations (12 core + 10 extended + 19 AI + 4 subagent + 1 dispatcher).

**cli.c** -- Core commands (12):
- `init`, `add`, `show`, `list`, `edit`, `move`, `delete`, `tags`, `stats`, `filter`, `export`, `board`.

**cli_ext.c** -- Extended commands (10):
- `project`, `template`, `depend`/`undepend`, `deps`, `subtasks`, `due`, `time`, `session`, `priority`.

**cli_ai.c** -- AI core (agent entry, tool loop):
- `cmd_agent()`: Agent entry point with `--autonomy=` flag parsing.
- `cmd_ai_chat()`, `cmd_ai_history()`: AI conversation commands.
- `extract_tool_call()`: Parses `TOOL_CALL:`/`END_TOOL_CALL` markers from model output.
- `generate_with_tools()`: Iterative tool call loop (max 5 iterations per prompt) with real-time token streaming to stdout via `stream_to_stdout` callback.

**cli_ai_cmds.c** -- AI management commands:
- `model list|test`, `checkpoint save|list`, `cron list|add|pause|resume|delete`.
- `memory set|get|list|clear`, `skill list|run`, `status` (full report), `onboard`, `workspace`.

**cli_ai_subagent.c** -- Subagent commands:
- `cmd_subagent_spawn()`, `cmd_subagent_list()`, `cmd_subagent_kill()`, `cmd_subagent_output()`.

**cli_dispatch.c** -- DB-command dispatcher:
- `cli_dispatch_db_command()`: Routes structured AI-generated DB commands to appropriate handlers.

### Layer 5: AI Inference (`src/ai/` -- inference subsystem)

Local AI inference via llama.cpp, conversation persistence, token streaming, and context management.

**llama_bridge.h / llama_bridge.cpp** -- C++ bridge with pure C API:
- Compiled as C++17 against llama.h directly, exposing only pointer-and-scalar parameters.
- Opaque handles: `lb_model`, `lb_context`, `lb_vocab`, `lb_sampler`.
- Operations: `lb_backend_init/free`, `lb_model_load/free`, `lb_context_create/free`.
- Tokenization: `lb_tokenize`, `lb_token_to_piece`.
- Generation: `lb_decode_tokens`, `lb_sampler_create/free`, `lb_sampler_sample`.
- Chat template: `lb_chat_apply_template` (explicit template string) and `lb_chat_apply_template_model` (auto-detect from GGUF metadata) for model-native prompt formatting.
- Logging: `lb_log_set` redirects all llama.cpp output to a callback.
- **Dual API support**: When compiled with `-DLLAMA_OLD_API=1` (BitNet builds), uses the older llama.cpp function names (`llama_load_model_from_file`, `llama_new_context_with_model`, `llama_kv_cache_clear`, etc.). Without this flag, uses the new API (`llama_model_load_from_file`, `llama_init_from_model`, `llama_memory_clear`, etc.). In old API mode, the `lb_vocab` type is mapped to `llama_model*` via pointer casts since the old API has no separate vocab type.
- This approach eliminates all struct-by-value ABI issues vs the old dlopen approach.

**local.c** -- llama.cpp provider:
- Uses `llama_bridge` (linked at compile time) instead of dlopen.
- Model loading with configurable `n_ctx` (default from `SPAGAT_DEFAULT_N_CTX` compile-time define, fallback 2048).
- Sampler chain construction (temperature, top_p, top_k, seed).
- Token-by-token generation with streaming callback and retry logic (configurable max_retries, retry_delay_ms).
- **Context-aware generation cap**: `max_gen` is clamped to `n_ctx - prompt_tokens`, preventing attempts to generate beyond the context window.
- **Secondary EOS detection**: In addition to checking the model's EOS token ID, scans generated text for literal EOS strings (`<|eot_id|>`, `<|end_of_text|>`, `<end_of_turn>`) as a safety net for models whose GGUF metadata may have incorrect EOS token configuration.
- Config parsing from JSON string (model path, device, GPU layers, n_ctx, temperature, top_p).
- All llama.cpp log output redirected to journal via `lb_log_set()`.

**local_prompt.h / local_prompt.c** -- System prompt building:
- `build_system_prompt()`: Constructs the system prompt. Uses a compact prompt (~300 chars) for small context windows (<=2048 tokens, e.g., BitNet) and a full prompt (~1500 chars with tool descriptions and examples) for larger contexts (>=4096 tokens).
- `format_prompt()`: 3-strategy chat template resolution: (1) model's own template via `lb_model_chat_template` (new API only), (2) auto-detect from GGUF metadata via `lb_chat_apply_template_model` (passes model pointer, works with old API), (3) hardcoded Llama-3/BitNet fallback format (`{Role}: {content}<|eot_id|>`). All strategies are logged to journal for debugging.

**conversation.c** -- Conversation persistence:
- SQLite conversations table: message CRUD keyed by item_id and session_id.
- Checkpoint save: serializes ConvHistory to JSON (hand-written serializer, no cJSON).
- Checkpoint load: parses JSON state back into ConvHistory.

**streaming.c** -- Token streaming:
- `AIStreamContext`: Manages streaming state.
- Can stream tokens to an ncurses WINDOW (TUI mode) or a character buffer (CLI mode).
- Supports Esc key cancellation during generation.

**memory.c** -- Agent memory:
- SQLite agent_memory table with (project_id, scope, key, value) tuples.
- MEMORY.md file import/export for human-readable persistence.

**compaction.h / compaction.c** -- Context compaction:
- Token estimation: heuristic `chars / 4` approximation.
- `compaction_needed()`: Checks if conversation tokens exceed 75% of n_ctx (minus system prompt).
- `compaction_compact()`: Heuristic summarization of oldest messages (no LLM summarization -- a 2B model's summaries are unreliable for preserving tool call context). Replaces compacted messages with a single summary in the DB.

**embedded_model.h / embedded_model.c** -- Embedded model support:
- References objcopy-generated symbols (`_binary_model_gguf_start`, `_binary_model_gguf_end`).
- `memfd_create()` via direct syscall wrapper (no glibc wrapper dependency).
- Writes embedded GGUF data to anonymous file descriptor.
- Returns `/proc/self/fd/N` path for llama.cpp to load -- zero-copy from binary.

### Layer 6: AI Tools (`src/ai/` -- tool subsystem)

Tool registration, execution, filesystem access, git integration, and system information gathering.

**tools.c** -- Tool registry and executor:
- Registry: max 64 tools, each with name, description, handler, is_write flag.
- Execution pipeline: input validation → tool lookup → autonomy check → rate limiting → sensitive path check → write cooldown → audit log → execute handler → output sanitization.
- `ai_tools_init_with_autonomy()`: Initializes tools gated by autonomy level. At NONE: no tools. At OBSERVE+: read-only + shell. At WORKSPACE+: adds write tools and git tools.
- Configures FsConfig write paths based on autonomy level (workspace-only, home, or unrestricted).

**tools_builtin.c** -- 4 legacy tools:
- `read_file`, `write_file`, `list_dir`, `shell` -- retained for backward compatibility.

**tools_fs.h / tools_fs.c / tools_fs_read.c / tools_fs_write.c** -- 14 filesystem tools:
- Read tools (9): `read_text_file` (head/tail support), `read_binary_file` (base64), `read_multiple_files`, `list_directory`, `list_directory_sizes` (sort=size), `directory_tree` (recursive, exclude patterns), `search_files` (glob), `get_file_info` (stat), `list_allowed_paths`.
- Write tools (5): `write_file`, `edit_file` (old_text/new_text with dry_run), `create_directory` (mkdir -p), `move_file`, `delete_file`.
- FsConfig: allowed/denied/readonly/write path lists, max read/write sizes, search depth/result limits.
- Path validation via `realpath()`, denied path glob matching (fnmatch), write-path separation.

**tools_sysinfo.c** -- 3 system information tools:
- `system_info`: Full snapshot (OS, kernel, CPU, memory, disk, network via uname/statvfs/proc).
- `disk_usage`: Filesystem usage summary via statvfs.
- `process_list`: Running processes from /proc.
- `sysinfo_snapshot()` / `sysinfo_category()`: Internal helpers for sysaware.

**git_tools.h / git_tools.c** -- 7 git tools:
- `git_status`, `git_diff`, `git_log`, `git_branch`, `git_commit`, `git_add`, `git_show`.
- Implementation: fork/exec calling the git CLI (no libgit2 dependency), stdout+stderr capture, 10-second timeout per command via `alarm()`.
- Conditionally compiled (`#ifdef __linux__`).

**Total tool count**: 14 fs + 7 git + 3 sysinfo + 4 legacy = 28 registered tools (some overlap: legacy `read_file` and fs `read_text_file` coexist).

### Layer 7: AI Security (`src/ai/` -- security subsystem)

Five-layer security model governing all AI tool execution. See dedicated section below.

**autonomy.h / autonomy.c** -- Autonomy levels and capability gating.
**execpolicy.h / execpolicy.c** -- Command execution policy rules.
**sanitize.h / sanitize.c** -- Output secret redaction.
**linux_sandbox.h / linux_sandbox.c** -- OS-level Landlock + Seccomp sandboxing.
**prompt_builder.h / prompt_builder.c** -- Autonomy-aware system prompt construction.

### Layer 8: Agent (`src/agent/`)

Workspace management, configuration, scheduling, sandboxing, heartbeat, and subagent delegation.

**agent.h** -- Public interface:
- `WorkspacePaths`: 11 path buffers (1024 bytes each) for base, workspace, models, config, sessions, memory, state, cron, skills, logs, credentials directories.
- `SpagatConfig`: Provider settings, llama.cpp settings, heartbeat, autonomy settings (mode, confirm_destructive, session_write_limit, session_file_limit, max_tool_calls_per_prompt, max_tool_calls_per_session, shell_timeout), retry logic (max_retries, retry_delay_ms), per-project system prompt.
- `CronJob` / `CronJobList`: Scheduled job definitions with interval_minutes, prompt, enable/disable, one-time flag.

**workspace.c** -- Workspace initialization:
- Resolves base directory from `$SPAGAT_HOME` environment variable, falls back to `~/.spagat`.
- `workspace_init()` / `workspace_get_paths()`: Populate WorkspacePaths struct.
- `workspace_ensure_dirs()`: Recursive mkdir for all subdirectories (including logs/, credentials/).
- `workspace_is_initialized()`: Check for config.json existence.

**onboard.c** -- First-time setup:
- Writes 7 default markdown files to workspace (AGENT.md, IDENTITY.md, SOUL.md, USER.md, MEMORY.md, HEARTBEAT.md, README.md).
- `config_set_defaults()`: Populates SpagatConfig with sensible defaults (observe mode, max_retries=2, retry_delay_ms=500).

**config_io.c** -- Configuration I/O:
- `config_load()` / `config_save()`: Hand-rolled JSON serializer and parser. No cJSON dependency -- the parser handles string, integer, float, and boolean fields with explicit key matching. Handles all autonomy, retry, and per-project prompt fields.

**scheduler.c** -- Cron scheduler:
- SQLite cron_jobs table: CRUD operations for scheduled jobs.
- `scheduler_check_due()`: Finds jobs where current time exceeds next_run.
- `scheduler_update_last_run()`: Advances next_run by interval_minutes after execution.
- Supports pause/resume via enabled flag and one-time jobs.

**sandbox.c** -- Application-level sandbox:
- `sandbox_check_path()`: Resolves target path via `realpath()`, verifies it starts with workspace base directory.
- `sandbox_is_enabled()`: Checks config restrict_to_workspace flag.

**heartbeat.c** -- Heartbeat processing:
- `heartbeat_load()`: Reads HEARTBEAT.md from workspace.
- `heartbeat_process()`: Parses lines prefixed with `"- "` as task entries.

**subagent.h / subagent.c** -- Background task delegation:
- `SubagentManager`: Manages up to 8 concurrent subagents.
- `subagent_spawn()`: Fork/exec with output redirected to a temp file. Max depth 1 (subagents cannot spawn sub-subagents).
- `subagent_poll()`: Non-blocking status check via `waitpid(WNOHANG)`.
- `subagent_kill()` / `subagent_kill_all()`: Signal-based termination.
- `subagent_read_output()`: Read captured stdout/stderr from completed agent.
- Status tracking: PENDING → RUNNING → DONE/FAILED/KILLED.

### Layer 9: Skills (`src/skill/`)

Markdown-defined automation skills loaded from the workspace.

**skill.h** -- Types:
- `Skill`: name, description, filepath, content, loaded flag. Max 32 skills.
- `SkillList`: Fixed-size array of Skill structs.
- `SkillExecContext`: workspace_dir path and sandbox_enabled flag.

**loader.c** -- Skill loading:
- Scans skills directory via `opendir()` / `readdir()`.
- Parses SKILL.md format: `# Name` heading, description paragraph, `## Steps` section with numbered steps.
- `skill_load_all()`: Loads all .md files from skills directory into SkillList.

**executor.c** -- Skill execution:
- Iterates parsed steps and dispatches by prefix:
  - `shell:` -- Executes command via `system()`.
  - `prompt:` -- Sends text to `ai_generate()` for AI processing.
  - `file:` -- Writes content to a file in the workspace directory.
- Respects sandbox restrictions when sandbox_enabled is set.

### Layer 10: Utilities (`src/util/`)

Common helper functions used across all layers.

**util.h / util.c**:
- `str_trim()`: Remove leading/trailing whitespace.
- `str_safe_copy()`: Bounded string copy (prevents buffer overflows).
- `str_duplicate()`: Heap-allocated string copy.
- `str_starts_with()`: Prefix check.
- `str_equals_ignore_case()`: Case-insensitive string comparison.
- `get_db_path()`: Returns path to `~/.spagat.db`.
- `get_editor()`: Returns `$EDITOR` or fallback.
- `file_exists()`: Check file existence.
- `env_is_set()`: Check whether environment variable is set and non-empty.
- `is_numeric()`: Check if string represents a number.

**journal.h / journal.c** -- Self-rotating log:
- `journal_open()`: Opens `~/.spagat/logs/spagat.log`, creates directories as needed.
- `journal_log()`: Writes formatted entry with timestamp and level (DEBUG/INFO/WARN/ERROR).
- `journal_write_raw()`: Writes pre-formatted text (used for llama.cpp callback output).
- Auto-rotation: 2 MB max per file, keeps 3 rotated files.

## Security Architecture

SPAGAT-Librarian implements a 5-layer security model for AI tool execution. Each layer acts as an independent gate -- a tool call must pass all five layers to execute.

### Security Layer 1: Autonomy Levels (Capability Gate)

**File**: `autonomy.h` / `autonomy.c`

Controls which categories of tools are available based on a configured autonomy level:

| Level       | Value | Read Tools | Write Tools | Shell       | Git Tools |
|-------------|-------|------------|-------------|-------------|-----------|
| `none`      | 0     | ✗          | ✗           | ✗           | ✗         |
| `observe`   | 1     | ✓          | ✗           | allowlisted | ✗         |
| `workspace` | 2     | ✓          | ✓ (workspace) | ✓         | ✓         |
| `home`      | 3     | ✓          | ✓ (home)    | ✓           | ✓         |
| `full`      | 4     | ✓          | ✓ (any)     | ✓           | ✓         |

Additional autonomy controls:
- **Rate limiting**: `max_calls_per_prompt` (default 5), `max_calls_per_session` (default 50).
- **Write limits**: `session_write_limit` (1 MiB), `session_file_limit` (20 files).
- **Write cooldown**: Minimum interval between write operations (default 500ms).
- **Sensitive path hardcoded blocklist**: Always denied regardless of level.
- **Observe-mode shell allowlist**: Only specific read-only commands permitted.
- **Tool input validation**: Model output is validated before execution.
- **Memory write control**: Append-only in observe mode.

### Security Layer 2: Execution Policy (Command Gate)

**File**: `execpolicy.h` / `execpolicy.c`

Prefix-based rule engine for shell command evaluation:

- **`POLICY_ALLOW`**: Command prefix matches allow rules (e.g., `ls`, `cat`, `git status`).
- **`POLICY_PROMPT`**: Command requires human confirmation before execution.
- **`POLICY_FORBIDDEN`**: Command prefix matches forbidden rules (e.g., `rm -rf /`, `shutdown`, `mkfs`).
- Rules loaded from file (format: `allow: cmd1 cmd2` / `prompt: cmd3` / `forbidden: cmd4`).
- Each evaluation returns a `PolicyResult` with decision + justification string.

### Security Layer 3: Human Approval (Intent Gate)

For commands classified as `POLICY_PROMPT` by the execution policy, the TUI presents a confirmation dialog. The user must explicitly approve or deny the operation. This gate is bypassed in non-interactive (CLI pipe) mode where stdin is not a terminal.

### Security Layer 4: OS Sandbox (Kernel Gate)

**File**: `linux_sandbox.h` / `linux_sandbox.c`

Applied to shell child processes after `fork()`, before `exec()`:

- **Landlock LSM**: Restricts filesystem access to specified write paths. If `write_paths` is NULL, the process is fully read-only. Checks kernel support via `sandbox_landlock_available()`.
- **Seccomp-BPF**: Blocks dangerous syscalls: `ptrace`, `mount`, `umount2`, `reboot`, `sethostname`, `setdomainname`, `init_module`, `delete_module`, `kexec_load`, `pivot_root`, `swapon`, `swapoff`. Checks kernel support via `sandbox_seccomp_available()`.
- `sandbox_apply_shell_restrictions()`: Combined application of both mechanisms.

### Security Layer 5: Output Sanitization (Persistence Gate)

**File**: `sanitize.h` / `sanitize.c`

Applied to all tool output before it is stored in the conversation database or MEMORY.md:

- `sanitize_redact_secrets()`: Detects API keys, passwords, tokens, and other sensitive patterns in text. Replaces them in-place with `[REDACTED]`.
- `sanitize_contains_secret()`: Quick check for sensitive data presence.
- `sanitize_redact_value()`: Targeted redaction for display purposes.

### Security Data Flow

```
  Model requests tool call
       |
       v
  [Layer 1] Autonomy Check ──── tool allowed at this level? ──── BLOCKED
       |
       v
  [Layer 1] Rate Limiting ───── calls/writes within budget? ──── BLOCKED
       |
       v
  [Layer 1] Sensitive Path ──── hardcoded blocklist check ────── BLOCKED
       |
       v
  [Layer 1] Write Cooldown ──── minimum interval elapsed? ────── BLOCKED
       |
       v
  [Layer 2] Exec Policy ─────── shell command prefix rules ──── BLOCKED/PROMPT
       |
       v
  [Layer 3] Human Approval ──── TUI confirmation dialog ─────── DENIED
       |
       v
  [Layer 4] OS Sandbox ──────── Landlock + Seccomp on fork ──── KILLED
       |
       v
       EXECUTE TOOL
       |
       v
  [Layer 5] Output Sanitize ─── redact secrets from result ──── (modified output)
       |
       v
  Store result in conversation DB
```

## System Awareness

**File**: `sysaware.h` / `sysaware.c`

Automatic system fact collection and change detection:

- **Fact storage**: `sysaware_store_facts()` detects system properties and stores them as agent memory keys under scope `"system"`:
  - `system.os`: OS name and version (from `/etc/os-release`).
  - `system.kernel`: Kernel version (from `uname`).
  - `system.hostname`: Machine hostname.
  - `system.cpu`: CPU model.
  - `system.memory`: Total RAM.
  - `system.disk`: Root filesystem usage.
  - Additional hardware/network facts as available.

- **Change detection**: `sysaware_detect_changes()` compares current system snapshot against stored memory values. Detects kernel updates, IP changes, disk usage changes, etc. Returns a change summary.

- **SYSTEM.md refresh**: `sysaware_refresh_system_md()` rewrites `SYSTEM.md` in the workspace with:
  1. Current system snapshot header.
  2. Stored facts section.
  3. Change history (appended, not overwritten).

- **Integration**: `sysaware_update()` runs the full cycle (store → detect → refresh). Called from heartbeat or on startup. The system info tools (`system_info`, `disk_usage`, `process_list`) also use the same data gathering functions.

## Data Flow

```
                         +------------------+
                         |   User Input     |
                         +--------+---------+
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
             +----------+               +----------+
             |   TUI    |               |   CLI    |
             | (ncurses)|               | (argv)   |
             +----+-----+               +----+-----+
                  |                          |
                  +------------+-------------+
                               |
              +----------------+----------------+
              |                |                |
              v                v                v
       +-----------+    +-----------+    +-----------+
       | Database  |    |    AI     |    |   Agent   |
       |  Layer    |    |  Layer    |    |   Layer   |
       +-----+-----+   +-----+-----+   +-----+-----+
             |               |               |
             v               |               v
       +-----------+         |         +-----------+
       |  SQLite   |         |         | Workspace |
       |~/.spagat  |         |         | ~/.spagat/|
       |  .db      |         |         +-----------+
       +-----------+         |              |
                             v              v
                   +-------------------+  +-----------+
                   |   llama_bridge    |  |   Skill   |
                   |   (C++ bridge)    |  |   Layer   |
                   +--------+----------+  +-----------+
                            |
                            v
                   +-------------------+
                   |    libllama.so    |
                   | (linked, not      |
                   |  dlopen'd)        |
                   +-------------------+
```

Detailed flow for an AI chat session with tool use:

```
  User types "spagat-librarian agent --autonomy=workspace"
       |
       v
  main.c -> run_cli() -> cmd_agent() [parses --autonomy= flag]
       |
       v
  cli_ai.c: ai_tools_init_with_autonomy(WORKSPACE)
       |  - execpolicy_init()
       |  - registers tools gated by level
       |  - tools_fs_init() with write_paths=[workspace_dir]
       |  - tools_sysinfo_init()
       |  - git_tools_init()
       |
       v
  User types a prompt
       |
       v
  local_prompt.c: build_system_prompt() via prompt_builder
       |  - identity, tools listing, skills, rules (autonomy-aware)
       |
       v
  local_prompt.c: format_prompt() with chat template
       |
       v
  local.c: lb_model_load() -> lb_context_create() -> generation loop
       |  - lb_decode_tokens() + lb_sampler_sample() per token
       |  - streaming callback to terminal
       |  - retry on failure (max_retries with delay)
       |
       v
  cli_ai.c: extract_tool_call() [TOOL_CALL:/END_TOOL_CALL markers]
       |
       v
  tools.c: ai_tool_execute() [5-layer security pipeline]
       |
       v
  Tool result fed back -> reload history -> re-prompt (max 5 iterations)
       |
       v
  conversation.c: persist messages + sanitized tool results to DB
```

## Database Schema (v3)

11 tables in a single SQLite file (`~/.spagat.db`):

```sql
-- Core item storage
CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER DEFAULT 0,
    parent_id INTEGER DEFAULT 0,
    status TEXT NOT NULL,
    priority TEXT DEFAULT 'none',
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    tag TEXT DEFAULT '',
    history TEXT DEFAULT '',
    git_branch TEXT DEFAULT '',
    due_date INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    time_spent INTEGER DEFAULT 0
);

-- Schema version tracking
CREATE TABLE db_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Project organization
CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT DEFAULT '',
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Reusable item templates
CREATE TABLE templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    title TEXT DEFAULT '',
    description TEXT DEFAULT '',
    tag TEXT DEFAULT '',
    status TEXT DEFAULT 'backlog',
    priority TEXT DEFAULT 'none'
);

-- Directed dependency edges between items
CREATE TABLE dependencies (
    from_id INTEGER NOT NULL,
    to_id INTEGER NOT NULL,
    PRIMARY KEY (from_id, to_id)
);

-- TUI session persistence
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    current_project INTEGER DEFAULT 0,
    current_col INTEGER DEFAULT 0,
    current_row INTEGER DEFAULT 0,
    scroll_offsets TEXT DEFAULT '',
    swimlane_mode INTEGER DEFAULT 0,
    saved_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- AI conversation messages
CREATE TABLE conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER DEFAULT 0,
    session_id TEXT DEFAULT '',
    role TEXT NOT NULL,
    content TEXT DEFAULT '',
    tokens_used INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- AI conversation checkpoints (named snapshots)
CREATE TABLE checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER DEFAULT 0,
    name TEXT DEFAULT '',
    conversation_state TEXT DEFAULT '',
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Scheduled jobs
CREATE TABLE cron_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER DEFAULT 0,
    cron_expression TEXT DEFAULT '',
    interval_minutes INTEGER DEFAULT 0,
    prompt TEXT DEFAULT '',
    last_run INTEGER DEFAULT 0,
    next_run INTEGER DEFAULT 0,
    enabled INTEGER DEFAULT 1,
    one_time INTEGER DEFAULT 0
);

-- Agent key-value memory store
CREATE TABLE agent_memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER DEFAULT 0,
    scope TEXT DEFAULT '',
    key TEXT NOT NULL,
    value TEXT DEFAULT '',
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Tool execution audit log
CREATE TABLE tool_calls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER DEFAULT 0,
    tool_name TEXT NOT NULL,
    input TEXT DEFAULT '',
    output TEXT DEFAULT '',
    status TEXT DEFAULT '',
    duration_ms INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);
```

### Migration History

- **v1**: Original schema -- items table with status, description, tag, history, timestamps.
- **v2**: Added title column to items, migrated description content to title.
- **v3**: Added project_id, parent_id, priority, git_branch, due_date, time_spent to items. Created projects, templates, dependencies, sessions, conversations, checkpoints, cron_jobs, agent_memory, tool_calls tables.

## Build System

### Makefile (primary, recommended for Photon OS)

GNU Make with LLM model selection and embedded model support:

```
make                           # Build release binary
make debug                     # Build with -g and sanitizers
make clean                     # Remove build artifacts
make distclean                 # Remove artifacts + downloaded deps/models
make install                   # Install to /usr/local/bin
```

**Prerequisite targets**:
```
make deps                      # Install OS packages (gcc, cmake, sqlite, ncurses, git, curl)
make llama                     # Clone, build & install llama.cpp (libllama.so)
make bitnet                    # Clone & build bitnet.cpp (for BitNet models only)
make model LLM=<name>          # Download GGUF model from HuggingFace
make model-all                 # Download all 5 models
make models                    # List available LLMs
make setup                     # deps + llama + model (all-in-one)
```

**LLM selection** via `LLM=` flag (5 models):

| LLM=    | Model                          | Size   | Default ctx | Note                     |
|---------|--------------------------------|--------|-------------|--------------------------|
| gemma2  | Google Gemma-2 2B IT (Q4_K_M)  | 1.7 GB | 1024        | Default                  |
| llama   | Meta Llama-3.2 1B (Q4_K_M)     | 0.8 GB | 8192        | Fast, large context      |
| bitnet  | MS BitNet b1.58 2B 4T (i2_s)   | 1.2 GB | 2048        | Experimental; requires bitnet.cpp; poor instruction-following |
| qwen    | Alibaba Qwen2.5 1.5B (Q4_K_M)  | 1.0 GB | 4096        | Multilingual             |
| gemma3  | Google Gemma-3 1B IT (Q4_K_M)  | 0.8 GB | 8192        | Newest                   |

**Embedded model workflow**:
1. `make model LLM=<name>` downloads a GGUF model file.
2. `make MODEL=models/<file>.gguf LLM=<name>` builds with embedded model.
3. When `MODEL=` is set, defines `SPAGAT_EMBED_MODEL` and `SPAGAT_DEFAULT_N_CTX=$(LLM_CTX_SIZE)`.
4. `objcopy` converts the GGUF into an ELF object with symbols `_binary_model_gguf_start` and `_binary_model_gguf_end`.
5. At runtime, `embedded_model.c` writes the data to an anonymous fd via `memfd_create()` and passes `/proc/self/fd/N` to llama.cpp.

**Linking**: The binary links directly against `libllama` and `libstdc++` (not dlopen). Also links ncurses and sqlite3.

**BitNet special case**: BitNet b1.58 uses i2_s quantization incompatible with standard llama.cpp. The `make bitnet` target clones Microsoft's bitnet.cpp (which includes a forked llama.cpp with i2_s support), builds it as shared libraries (`libllama.so` from `build/3rdparty/llama.cpp/src/` and `libggml.so` from `build/3rdparty/llama.cpp/ggml/src/`), installs them to `/usr/lib/` (replacing standard llama.cpp), and installs all required headers (`llama.h`, `ggml.h`, `ggml-alloc.h`, `ggml-backend.h`). The BitNet fork uses an older llama.cpp API, so the bridge is compiled with `-DLLAMA_OLD_API=1` (set automatically when `BITNET_BUILD=1`). Additional build dependencies: `clang`, `clang-devel`, `python`. **Note**: BitNet b1.58 2B 4T has limited instruction-following capability; see Known Issues in README.md.

### CMakeLists.txt (alternative)

CMake 3.10+ build with the same feature set:
- `EMBED_MODEL` and `LLM_CTX_SIZE` cache variables.
- C11 + C++17 standards.
- pkg-config for sqlite3 and ncurses.
- Same objcopy + memfd_create embedded model pipeline.

### spagat.spec

RPM spec file for packaging on Photon OS. Defines build requirements, install paths, and package metadata.

## Workspace Layout

The agent workspace resides at `$SPAGAT_HOME` (default: `~/.spagat/`):

```
~/.spagat/
├── config.json              # Hand-parsed JSON configuration
├── models/                  # Downloaded GGUF model files
├── logs/                    # Self-rotating journal logs
│   ├── spagat.log           # Current log (max 2 MB)
│   ├── spagat.log.1         # Previous rotation
│   └── spagat.log.2         # Oldest rotation
├── credentials/             # Credential storage directory
└── workspace/
    ├── AGENT.md             # Agent identity and capabilities
    ├── IDENTITY.md          # Agent identity config
    ├── SOUL.md              # Core directives
    ├── USER.md              # User preferences
    ├── MEMORY.md            # Human-readable memory export
    ├── HEARTBEAT.md         # Periodic task definitions
    ├── SYSTEM.md            # Auto-generated system information
    ├── sessions/            # Saved TUI session data
    ├── memory/              # Memory exports
    ├── state/               # Agent state files
    ├── cron/                # Cron job working directory
    └── skills/              # SKILL.md files (user-defined automations)
```

### Configuration

Configuration (`config.json`) is parsed by a hand-rolled JSON parser in `config_io.c`. Fields:

**Provider settings**:
- `provider`: AI provider name (currently "local" only).
- `max_tokens`, `temperature`: Generation parameters.
- `max_tool_iterations`: Max tool calls per generation (default 5).
- `restrict_to_workspace`: Legacy sandbox flag.

**Local provider (llama.cpp)**:
- `local_enabled`, `local_engine`: Engine selection ("llama.cpp").
- `local_model_path`: Path to external GGUF model file.
- `local_device`: "cpu" or "gpu".
- `local_n_gpu_layers`, `local_n_ctx`: GPU offload and context size.
- `local_temperature`, `local_top_p`: Sampling parameters.

**Autonomy**:
- `autonomy_mode`: One of "none", "observe", "workspace", "home", "full".
- `confirm_destructive`: Require confirmation for destructive operations (boolean).
- `session_write_limit`: Maximum bytes written per session.
- `session_file_limit`: Maximum files created per session.
- `max_tool_calls_per_prompt`: Rate limit per prompt cycle.
- `max_tool_calls_per_session`: Rate limit per session.
- `shell_timeout`: Shell command timeout in seconds.

**Retry logic**:
- `max_retries`: Maximum generation retries on failure (default 2, 0=no retry).
- `retry_delay_ms`: Delay between retries in milliseconds (default 500).

**Heartbeat**:
- `heartbeat_enabled`, `heartbeat_interval`: Heartbeat check interval in minutes.

**Per-project**:
- `project_system_prompt`: Custom system prompt injected for the current project.
- `fs_access_mode`: Legacy field (migrated to autonomy).

## Dependencies

### Build-time

- **gcc** (C11 + C++17 support via g++)
- **ncurses-devel**: Terminal UI library.
- **sqlite-devel**: Database library.
- **llama.cpp**: Fetched by `make deps`, built as shared library. Headers required at compile time for the C++ bridge.
- **binutils**: `objcopy` for embedded model support.
- **cmake**: For building llama.cpp.
- **git, curl**: For fetching dependencies and models.

### Runtime

- **libncurses**: TUI rendering.
- **libsqlite3**: Database operations.
- **libllama.so**: AI inference (linked at compile time, required for AI features).
- **libstdc++**: C++ runtime for llama_bridge.
- **libpthread**: Threading support (via llama.cpp).
- **git** (optional): Required for git tools (called via fork/exec).

Install on Photon OS:
```
tdnf install gcc libstdc++ ncurses-devel sqlite-devel make cmake binutils git curl
```

## Key Design Decisions

1. **Single SQLite database file**: All data in `~/.spagat.db`. No server, no network, simple backup (copy one file).

2. **C++ bridge instead of dlopen**: The llama_bridge (C++17) includes `llama.h` directly and exposes a pointer-and-scalar-only C API. This eliminates all struct-by-value ABI issues that plagued the old dlopen approach. The binary is linked against libllama.so at compile time, making AI a build-time dependency.

3. **5-layer security model**: Autonomy levels (capability gate) → execution policy (command gate) → human approval (intent gate) → OS sandbox (kernel gate) → output sanitization (persistence gate). Each layer is independent and cannot be bypassed by the others.

4. **Per-model context sizes at compile time**: When building with an embedded model, `SPAGAT_DEFAULT_N_CTX` is set via `-D` flag to match the model's optimal context window (1024 for Gemma-2, 8192 for Llama-3.2, etc.). This avoids runtime misconfiguration.

5. **Journal logging for all llama.cpp output**: All llama.cpp log messages are redirected via `lb_log_set()` to a self-rotating journal at `~/.spagat/logs/spagat.log` (2 MB max, 3 rotated files). This keeps the TUI clean while preserving diagnostics.

6. **objcopy + memfd_create for embedded model**: The GGUF model is embedded in the binary via `objcopy`. At runtime, `memfd_create()` (invoked via raw syscall to avoid glibc version requirements) creates an anonymous file descriptor. The model data is written there and llama.cpp loads from `/proc/self/fd/N`. This enables a single self-contained binary.

7. **Hand-rolled JSON parser**: Configuration and checkpoint serialization use a custom JSON parser/serializer in `config_io.c` and `conversation.c`. No cJSON or other JSON library dependency.

8. **Each source file under 15KB**: Enforced convention for maintainability. Functionality is split across files (e.g., cli.c / cli_ext.c / cli_ai.c / cli_ai_cmds.c / cli_ai_subagent.c / cli_dispatch.c) rather than growing large monolithic files.

9. **Heuristic context compaction**: Uses `chars/4` token estimation and oldest-message summarization rather than LLM-based summarization, because a 2B model's summaries are unreliable for preserving tool call context.

10. **Vim-style TUI navigation**: h/j/k/l keys for cursor movement, familiar to terminal users.

11. **Automatic schema migration**: On every database open, the migration system checks db_meta for the current version and applies any pending migrations (v1→v2→v3) sequentially and transparently.

12. **Offline-first**: All core features (task management, TUI, CLI, export) work without internet. AI inference runs locally via llama.cpp. No cloud API calls.

13. **C11 with POSIX extensions, Linux only**: Uses POSIX APIs (realpath, opendir, memfd_create syscall, /proc filesystem, fork/exec, Landlock, Seccomp). Targets Linux, specifically Photon OS.

14. **Dual llama.cpp API support**: The C++ bridge uses compile-time `#if LLAMA_OLD_API` conditionals to support both the new llama.cpp API (ggml-org, 2025+) and the older API used by BitNet's fork. This allows a single bridge codebase to work with both standard and BitNet builds. The old API lacks a separate `llama_vocab` type, so the bridge maps vocab operations through `llama_model*` pointer casts.

15. **Context-aware prompt scaling**: The system prompt adapts to the model's context window size. Models with <=2048 tokens get a compact prompt (~300 chars) with minimal tool descriptions; models with larger contexts get the full prompt (~1500 chars) with detailed tool documentation and examples. This prevents small models from wasting their limited context budget on instructions they can't follow effectively.

16. **Real-time token streaming**: Agent chat sessions stream tokens directly to stdout via a callback during generation, so the user sees output immediately rather than waiting for the entire response to complete. This is especially important for slower models (e.g., BitNet on CPU) where full generation can take minutes.
