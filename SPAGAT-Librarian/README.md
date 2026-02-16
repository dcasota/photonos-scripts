# SPAGAT-Librarian

**Supervised Package Analysis for Gitbased Autonomous Toolchains -- Librarian**

A CLI Kanban task manager and AI-powered development assistant for Photon OS, written in C.

Version 0.3.0

SPAGAT-Librarian combines a full-featured Kanban board with a local LLM agent. The Kanban side manages tasks through a 6-column workflow with an ncurses TUI and scriptable CLI. The AI side runs one of 5 selectable small language models locally via llama.cpp -- no API keys, no cloud, fully open source. Choose from Gemma-2, Gemma-3, Llama-3.2, Qwen2.5, or BitNet at build time with `LLM=`.

## Features

### Kanban Core

- 6-column Kanban board: Clarification, Won't Fix, Backlog, In Progress, Review, Ready
- ncurses TUI with vim-style navigation (h/j/k/l, 1-6 column jump)
- Color-coded priority indicators (Critical `!`, High `^`, Medium `-`, Low `v`)
- Due date indicators in TUI
- Comprehensive edit dialog with all fields (title, description, tag, status, priority, due date, git branch, project, parent task)
- Multi-select (Space to toggle, `*` to select all in column)
- Help dialog (`?` key)
- Full CLI for scripting and automation
- SQLite storage at `~/.spagat.db`
- Automatic database migration (v1 → v2 → v3)
- 5 priority levels: None, Low, Medium, High, Critical
- Due dates with filtering (today, this week, overdue)
- Dependencies between tasks
- Projects with add/list/delete
- Subtasks via parent_id
- Task templates
- Time tracking (start/stop)
- Session management (save/load cursor position and scroll state)
- Git branch linking per task
- Export to CSV and JSON
- Statistics by status, tag, and history
- History tracking (status transitions stored as single-character abbreviations)
- ASCII board view for CLI output

### AI Core

- **5 selectable LLMs** via `LLM=` build flag (see [LLM Selection](#llm-selection) below)
- **llama.cpp integration** via a C++ bridge (`llama_bridge.cpp`) — typed, ABI-safe C-linkage wrapper with opaque handles; no struct-by-value crossing the C/C++ boundary
- **Embedded model support**: objcopy embeds the GGUF into the binary, memfd_create provides zero-copy loading at runtime
- **Chat template**: 3-strategy resolution: (1) model's own template via `lb_model_chat_template`, (2) auto-detect from GGUF metadata via `lb_chat_apply_template_model`, (3) hardcoded Llama-3/BitNet fallback (`{Role}: {content}<|eot_id|>`)
- **Dual API bridge**: `llama_bridge.cpp` supports both the new llama.cpp API (ggml-org, 2025+) and the older API used by BitNet's fork, selected at build time via `-DLLAMA_OLD_API=1`
- **Context-aware system prompt**: compact prompt (~300 chars) for small context models (<=2048 tokens), full prompt (~1500 chars) for larger contexts
- **Token streaming** to stdout in real-time during agent chat, and to ncurses WINDOW or buffer in TUI mode; cancellable with Esc

#### Tools

- **14 MCP-equivalent filesystem tools**: `read_text_file`, `read_binary_file`, `read_multiple`, `list_directory`, `list_sizes`, `directory_tree`, `search_files`, `get_file_info`, `write_file`, `edit_file`, `create_directory`, `move_file`, `delete_file`, `list_allowed`
- **7 git tools**: `git_status`, `git_diff`, `git_log`, `git_branch`, `git_commit`, `git_add`, `git_show` (fork/exec with 10 s timeout, no libgit2)
- **3 system info tools**: `system_info` (7 categories: os/cpu/ram/storage/network/time/user), `process_list`, `disk_usage`
- **4 legacy built-in tools**: `read_file`, `write_file`, `list_dir`, `shell` (retained for backward compatibility)
- **Tool call loop**: `TOOL_CALL:` / `END_TOOL_CALL` markers, max 5 iterations per prompt turn
- **Configurable retry logic** for LLM generation failures (max retries + delay)

#### Security (5-layer model)

1. **5-tier autonomy model** — `none`, `observe`, `workspace`, `home`, `full` — controls which tools are available, which shell commands are allowed, write byte/file limits, call rate limits per prompt and per session, and write cooldown enforcement
2. **Execution policy engine** — per-command allow / prompt / forbidden rules with justification; loadable from external rule files
3. **Output sanitization** — automatic secret redaction (private keys, AWS credentials, passwords, tokens, base64 blobs) in model output before persisting to conversation DB or MEMORY.md
4. **Landlock LSM + Seccomp-BPF OS-level sandboxing** — applied after `fork()`, before `exec()` in shell children; Landlock restricts filesystem paths, Seccomp blocks dangerous syscalls (ptrace, mount, reboot, kexec_load, etc.)
5. **Filesystem access control** — configurable allowed/denied/readonly/write-only path lists with max read/write sizes, search depth, and search result limits

#### Agent Intelligence

- **Structured prompt builder** — assembles identity, tool descriptions, skill content, system context, rules, and project context into a single system prompt based on the active autonomy level
- **Context compaction** — estimates token usage (chars/4 heuristic) and summarizes oldest conversation messages when approaching the model's context window limit
- **System awareness** — auto-stores system facts (OS, kernel, IPs, disk, etc.) as memory keys, detects changes between sessions, and refreshes `SYSTEM.md` in the workspace with current snapshot + change history
- **Subagent spawn/kill** — fork/exec background tasks with output capture to temp files; max 8 concurrent subagents; depth limited to 1 (no sub-subagents)
- **Per-project system prompts** — configurable in `config.json`
- **Session-level autonomy override** — `--autonomy=<level>` flag on `agent` command

#### Infrastructure

- **Journal logging system** — self-rotating 2 MB log files (3 rotations kept) at `~/.spagat/logs/spagat.log`; 4 levels: DEBUG, INFO, WARN, ERROR
- **Workspace directory** at `~/.spagat/` with structured layout (workspace/, models/, logs/, credentials/, sessions/, memory/, state/, cron/, skills/)
- **7 default workspace files** created by `onboard`: AGENT.md, IDENTITY.md, SOUL.md, USER.md, MEMORY.md, HEARTBEAT.md, TOOLS.md
- **Conversation history** stored in SQLite (per task or global) with checkpoint save/restore
- **Agent memory**: key-value store in SQLite with MEMORY.md file support
- **Cron scheduler**: SQLite-based job CRUD with interval_minutes, pause/resume/delete
- **Heartbeat system**: reads HEARTBEAT.md and parses scheduled tasks
- **8 Photon OS skill files**: tdnf, systemctl, iptables, network, docker, logs, users, performance

## LLM Selection

| Name | Model | HuggingFace Repo | Size | Ctx | Notes |
|------|-------|-------------------|------|-----|-------|
| `gemma2` | Gemma-2 2B IT (Q4_K_M) | `bartowski/gemma-2-2b-it-GGUF` | 1.7 GB | 1024 | Default, compact |
| `llama` | Llama-3.2 1B Instruct (Q4_K_M) | `bartowski/Llama-3.2-1B-Instruct-GGUF` | 0.8 GB | 8192 | Fast, large context |
| `bitnet` | BitNet b1.58 2B 4T (i2_s) | `microsoft/bitnet-b1.58-2B-4T-gguf` | 1.2 GB | 2048 | Experimental*; requires bitnet.cpp |
| `qwen` | Qwen2.5 1.5B Instruct (Q4_K_M) | `bartowski/Qwen2.5-1.5B-Instruct-GGUF` | 1.0 GB | 4096 | Multilingual |
| `gemma3` | Gemma-3 1B IT (Q4_K_M) | `bartowski/google_gemma-3-1b-it-GGUF` | 0.8 GB | 8192 | Newest, large context |

\* BitNet uses native 1-bit quantization (`i2_s`), which is **not** compatible with standard llama.cpp. Use `make bitnet` to build bitnet.cpp separately. BitNet's `libllama.so` replaces the standard one and uses an older llama.cpp API; the bridge handles this transparently via `LLAMA_OLD_API`.

**Known limitation**: BitNet b1.58 2B 4T is a native 1-bit model with limited instruction-following capability. While it loads and runs correctly, its responses to complex prompts (especially tool-calling instructions) are unreliable -- the model tends to produce generic text completions instead of following the chat format. For reliable agent functionality, use one of the instruction-tuned models (Gemma-2, Gemma-3, Llama-3.2, or Qwen2.5). BitNet is included as an experimental option for users interested in 1-bit inference research.

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 4 GB | 8 GB |
| Storage | 3 GB (with model) | 5 GB |
| GPU | Not required | Optional (n_gpu_layers) |

## Quick Start

### Kanban only (no AI)

```bash
# Install build dependencies
tdnf install -y gcc make sqlite-devel ncurses-devel

# Build
make

# Initialize database
./spagat-librarian init

# Launch TUI
./spagat-librarian

# Or use CLI
./spagat-librarian add backlog "My first task" "Description here" "tag"
./spagat-librarian list
```

### Full setup with AI

```bash
# Install all prerequisites, build llama.cpp, download Gemma-3 1B IT
make setup LLM=gemma3

# Build with embedded model (zero-copy at runtime)
make MODEL=models/google_gemma-3-1b-it-Q4_K_M.gguf LLM=gemma3

# Initialize and onboard the agent workspace
./spagat-librarian init
./spagat-librarian onboard

# Chat with the agent
./spagat-librarian agent
./spagat-librarian agent -m "Summarize my backlog"

# Chat in context of a specific task
./spagat-librarian ai 5
```

## Building

### Prerequisites

On Photon OS, install build dependencies:

```bash
tdnf install -y gcc libstdc++ make cmake sqlite-devel ncurses-devel binutils git curl
```

Or use the Makefile target:

```bash
make deps
```

### Build targets

```bash
make                # Build release binary
make debug          # Build with debug symbols (-g -O0)
make release        # Build optimized (-O2)
make install        # Install to /usr/bin/
make clean          # Remove build artifacts
make distclean      # Remove build artifacts + downloaded deps/models
```

### LLM & Model targets

```bash
make models                 # List available LLMs with sizes and ctx
make model LLM=<name>       # Download specific model GGUF from HuggingFace
make model-all              # Download all 5 models
make llama                  # Clone, build, and install llama.cpp (libllama.so)
make bitnet                 # Clone and build bitnet.cpp (for BitNet models only)
make setup                  # All-in-one: deps + llama + model (default LLM)
make setup LLM=gemma3       # All-in-one with specific model
```

### Embedded model

To embed the GGUF model directly into the binary (uses objcopy to create an ELF object, memfd_create for zero-copy loading):

```bash
make MODEL=models/google_gemma-3-1b-it-Q4_K_M.gguf LLM=gemma3
```

Without `MODEL=`, the binary loads the model from the path specified in `~/.spagat/config.json`.

### CMake alternative

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make

# With embedded model:
cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DEMBED_MODEL=path/to/model.gguf \
    -DLLM_CTX_SIZE=8192
make
```

### RPM packaging

An RPM spec file (`spagat.spec`) is included for Photon OS packaging.

## TUI Keyboard Shortcuts

### Navigation

| Key | Action |
|-----|--------|
| `h` / Left | Previous column |
| `l` / Right | Next column |
| `k` / Up | Previous item |
| `j` / Down | Next item |
| `1`-`6` | Jump to column |

### Actions

| Key | Action |
|-----|--------|
| `a` | Add new item |
| `Enter` / `e` | Edit item |
| `m` | Move selected items |
| `d` | Delete selected items |
| `Space` | Toggle selection |
| `*` | Select all in column |
| `Esc` | Clear selection |
| `/` | Search |
| `?` | Help |
| `r` | Refresh |
| `q` | Quit |

## CLI Commands

### General

```bash
spagat-librarian init                    # Initialize database
spagat-librarian help                    # Show help
spagat-librarian version                 # Show version
```

### Task management

```bash
spagat-librarian add <status> <title> <description> [tag]
spagat-librarian show <id>
spagat-librarian list
spagat-librarian edit <id>
spagat-librarian move <id> <status>
spagat-librarian delete <id>
```

### Organization

```bash
spagat-librarian tags                    # List all tags
spagat-librarian filter <status>...      # Filter by status
spagat-librarian priority <level>        # Filter by priority
spagat-librarian due today|week|overdue  # Filter by due date
spagat-librarian board                   # ASCII board view
```

### Projects, templates, dependencies

```bash
spagat-librarian project add|list|delete
spagat-librarian template add|list|use
spagat-librarian depend <id> <id>        # Add dependency
spagat-librarian undepend <id> <id>      # Remove dependency
spagat-librarian deps <id>               # Show dependencies
spagat-librarian subtasks <id>           # Show subtasks
```

### Time tracking and sessions

```bash
spagat-librarian time start <id>
spagat-librarian time stop <id>
spagat-librarian session save <name>
spagat-librarian session load <name>
```

### Export and statistics

```bash
spagat-librarian export csv > tasks.csv
spagat-librarian export json > tasks.json
spagat-librarian stats status            # Items per status
spagat-librarian stats tag               # Items per tag
spagat-librarian stats history           # Status transitions
```

### AI and agent commands

```bash
spagat-librarian onboard                 # First-time workspace setup
spagat-librarian workspace               # Show workspace info
spagat-librarian agent                   # Interactive agent chat
spagat-librarian agent -m "..."          # Single-message agent query
spagat-librarian agent --autonomy=<level> # Override autonomy for session
spagat-librarian ai <id>                 # Chat in context of task
spagat-librarian ai history <id>         # Show conversation history
spagat-librarian model list              # List available models
spagat-librarian model test              # Test model loading
spagat-librarian checkpoint save|list    # Save/list conversation checkpoints
spagat-librarian status                  # Show AI system status
spagat-librarian sysinfo [category]      # System info (os/cpu/ram/storage/network/time/user)
spagat-librarian sysaware                # Run system awareness cycle
spagat-librarian fs <config|allowed>     # Show filesystem access config / allowed paths
```

### Subagent commands

```bash
spagat-librarian subagent spawn <name> <command>   # Spawn background task
spagat-librarian subagent list                     # List all subagents
spagat-librarian subagent kill <id>                # Kill a subagent
spagat-librarian subagent output <id>              # Read subagent output
```

### Cron scheduler

```bash
spagat-librarian cron list
spagat-librarian cron add <interval_minutes> <command>
spagat-librarian cron pause <id>
spagat-librarian cron resume <id>
spagat-librarian cron delete <id>
```

### Agent memory

```bash
spagat-librarian memory set <key> <value>
spagat-librarian memory get <key>
spagat-librarian memory list
spagat-librarian memory clear
```

### Skills

```bash
spagat-librarian skill list
spagat-librarian skill run <name>
```

## Statuses

| Status | Abbreviation | Description |
|--------|--------------|-------------|
| Clarification | C | Needs more information |
| Won't Fix | W | Rejected or deferred |
| Backlog | B | Planned but not started |
| In Progress | P | Currently being worked on |
| Review | V | Awaiting review |
| Ready | R | Done and verified |

## Configuration

The AI configuration file is located at `~/.spagat/config.json`:

```json
{
  "provider": "local",
  "max_tokens": 512,
  "temperature": 0.7,
  "max_tool_iterations": 5,
  "restrict_to_workspace": true,
  "local": {
    "enabled": true,
    "engine": "llama.cpp",
    "model_path": "",
    "device": "cpu",
    "n_gpu_layers": 0,
    "n_ctx": 8192,
    "temperature": 0.7,
    "top_p": 0.9
  },
  "heartbeat": {
    "enabled": true,
    "interval_minutes": 60
  },
  "autonomy": {
    "mode": "observe",
    "confirm_destructive": true,
    "session_write_limit": 1048576,
    "session_file_limit": 50,
    "max_tool_calls_per_prompt": 5,
    "max_tool_calls_per_session": 200,
    "shell_timeout": 30,
    "write_cooldown_ms": 500
  },
  "retry": {
    "max_retries": 2,
    "retry_delay_ms": 1000
  },
  "project_system_prompt": ""
}
```

When `model_path` is empty and the binary was built with an embedded model, the embedded model is used automatically. The `project_system_prompt` field allows injecting additional context into the system prompt for project-specific workflows.

### Autonomy Levels

| Level | Description |
|-------|-------------|
| `none` | AI cannot use any tools or execute commands |
| `observe` | Read-only tools + allowlisted shell commands; memory writes are append-only |
| `workspace` | Full tools within `~/.spagat/workspace/`; destructive ops require confirmation |
| `home` | Tools within home directory; shell commands evaluated by execution policy |
| `full` | Unrestricted tool access (use with caution) |

Set per-session via CLI: `spagat-librarian agent --autonomy=workspace`

## Environment Variables

| Variable | Effect |
|----------|--------|
| `NOCOLOR` | Disable colors in TUI and CLI |
| `PLAIN` | Use ASCII instead of UTF-8 box drawing |
| `EDITOR` | External editor for `edit` command |
| `SPAGAT_HOME` | Override `~/.spagat` workspace location |

## File Structure

```
include/
└── spagat.h                        # Core types (Item, ItemStatus, ItemPriority, Project, Template, Session)
src/
├── main.c                          # Entry point, argument routing
├── cli/
│   ├── cli.h                       # CLI command declarations
│   ├── cli.c                       # Core CLI commands
│   ├── cli_ext.c                   # Extended CLI (projects, templates, deps, time, sessions)
│   ├── cli_ai.c                    # AI CLI commands (agent, model, checkpoint, memory, skill)
│   ├── cli_ai_cmds.c              # Additional AI commands (sysinfo, sysaware, fs, autonomy)
│   ├── cli_ai_subagent.c          # Subagent CLI commands (spawn, list, kill, output)
│   └── cli_dispatch.c             # DB-command dispatcher
├── db/
│   ├── db.h / db.c                # Core SQLite operations
│   ├── db_ext.c                   # Extended queries (priority, due, deps, subtasks)
│   ├── db_project.c               # Project CRUD
│   ├── db_template.c              # Template CRUD
│   └── migrate.h / migrate.c     # Schema migration (v1 → v2 → v3)
├── tui/
│   ├── tui.h / tui.c             # TUI init, main loop
│   ├── tui_common.h               # Internal TUI types, color constants
│   ├── tui_board.c                # Board rendering, help dialog
│   ├── tui_input.c                # Input handling, cursor movement
│   ├── tui_dialogs.c             # Add/edit/delete/move/search dialogs
│   ├── tui_dialogs_misc.c        # Miscellaneous dialogs
│   └── tui_ext.c                 # Priority/due indicators, extended edit fields
├── ai/
│   ├── ai.h                       # AI interface declarations (provider, conv, checkpoint, memory, tools)
│   ├── local.c                    # llama.cpp provider (init, generation loop, template)
│   ├── local_prompt.h / local_prompt.c  # System prompt (compact/full), 3-strategy chat template
│   ├── llama_bridge.h / llama_bridge.cpp  # C++ bridge to llama.cpp (dual API: new + old/BitNet)
│   ├── conversation.c             # Conversation DB, checkpoint save/load
│   ├── streaming.c                # Token streaming to ncurses or buffer
│   ├── memory.c                   # Agent memory (SQLite + MEMORY.md)
│   ├── tools.c                    # Tool framework (registry, dispatch, call loop)
│   ├── tools_builtin.c           # Legacy tools (read_file, write_file, list_dir, shell)
│   ├── tools_fs.h                 # Filesystem tool types and config (FsConfig)
│   ├── tools_fs.c                 # Filesystem tool init, path validation, helpers
│   ├── tools_fs_read.c           # 9 read-only FS tools (read_text, read_binary, read_multiple, list_dir, list_sizes, dir_tree, search, file_info, list_allowed)
│   ├── tools_fs_write.c          # 5 write FS tools (write_file, edit_file, create_dir, move, delete)
│   ├── tools_sysinfo.c           # 3 system info tools (system_info, disk_usage, process_list)
│   ├── git_tools.h / git_tools.c # 7 git tools via fork/exec
│   ├── autonomy.h / autonomy.c   # 5-tier autonomy model, rate limiting, cooldown
│   ├── execpolicy.h / execpolicy.c  # Execution policy engine (allow/prompt/forbidden)
│   ├── sanitize.h / sanitize.c   # Output sanitization (secret redaction)
│   ├── prompt_builder.h / prompt_builder.c  # Structured system prompt builder
│   ├── compaction.h / compaction.c  # Context window compaction
│   ├── linux_sandbox.h / linux_sandbox.c  # Landlock + Seccomp-BPF sandboxing
│   ├── sysaware.h / sysaware.c   # System awareness (facts, change detection, SYSTEM.md)
│   └── embedded_model.h / embedded_model.c  # GGUF embedding via objcopy + memfd_create
├── agent/
│   ├── agent.h                    # Workspace paths, config struct, cron types
│   ├── workspace.c                # Workspace directory management
│   ├── onboard.c                  # First-time setup, config load/save
│   ├── config_io.c               # Config JSON read/write
│   ├── scheduler.c                # Cron job scheduler (SQLite)
│   ├── sandbox.c                  # Path validation sandbox
│   ├── heartbeat.c                # HEARTBEAT.md parser
│   ├── subagent.h                 # Subagent types (max 8, status enum)
│   └── subagent.c                 # Subagent spawn/kill/poll (fork/exec)
├── skill/
│   ├── skill.h                    # Skill types
│   ├── loader.c                   # SKILL.md file loader
│   └── executor.c                 # Skill step executor (shell:/prompt:/file:)
└── util/
    ├── util.h / util.c            # String helpers, path helpers
    └── journal.h / journal.c      # Self-rotating log (2 MB, 3 files)
skills/
├── tdnf.md                        # Package management skill
├── systemctl.md                   # Service management skill
├── iptables.md                    # Firewall skill
├── network.md                     # Network diagnostics skill
├── docker.md                      # Container management skill
├── logs.md                        # Log analysis skill
├── users.md                       # User administration skill
└── performance.md                 # Performance tuning skill
models/                             # Downloaded GGUF model files
sql/
└── schema.sql                     # Reference SQL schema
```

## Known Issues

### BitNet b1.58 2B 4T — poor instruction-following

BitNet b1.58 2B 4T builds and runs correctly (the 1-bit GGUF loads, tokenization works, generation produces tokens), but the model does not reliably follow instructions or chat formatting. When given a system prompt with tool-calling instructions, the model produces generic text completions (e.g., unrelated content about binary trees) instead of following the `TOOL_CALL:` / `END_TOOL_CALL` format or answering the user's question directly.

**Root cause**: BitNet b1.58 2B 4T is a native 1-bit model trained from scratch on 4 trillion tokens. While Microsoft reports benchmark performance comparable to full-precision models of similar size, the model's instruction-following and chat capabilities are significantly weaker than purpose-built instruction-tuned models like Gemma or Llama. The simple `{Role}: {content}<|eot_id|>` chat format it uses provides minimal structural guidance compared to the richer templates used by instruction-tuned models.

**Technical details**:
- The BitNet GGUF's chat template (a Jinja string with `capitalize` + `<|eot_id|>`) is not recognized by any of the heuristic pattern matchers in the old llama.cpp API's `llama_chat_apply_template_internal()` function (it doesn't contain `<|start_header_id|>`, `BITNET`, or other recognized markers)
- The bridge falls through to Strategy 3 (hardcoded `System: ... <|eot_id|> User: ... <|eot_id|> Assistant:` format), which matches the intended template
- Even with a compact system prompt (~300 chars) designed for the 2048-token context window, the model does not produce coherent instruction-following output

**Recommendation**: Use one of the four instruction-tuned models for agent functionality. BitNet is retained as an experimental option for users interested in 1-bit inference research and benchmarking.

### llama.cpp API compatibility

The C++ bridge (`llama_bridge.cpp`) supports two distinct llama.cpp API versions:

- **New API** (ggml-org, 2025+): Uses `llama_model_load_from_file`, `llama_init_from_model`, `llama_model_get_vocab`, `llama_vocab_bos/eos`, `llama_memory_clear`, `llama_batch_get_one(tokens, n)`. Used by standard `make llama` builds.
- **Old API** (BitNet fork, Eddie-Wang1120/llama.cpp): Uses `llama_load_model_from_file`, `llama_new_context_with_model`, no `llama_vocab` type, `llama_token_bos/eos(model)`, `llama_kv_cache_clear`, `llama_batch_get_one(tokens, n, pos, seq)`. Used by `make bitnet` builds.

The correct API is selected at build time via the `BITNET_BUILD=1` Makefile variable, which passes `-DLLAMA_OLD_API=1` to the C++ compiler. The `make setup` target handles this automatically when option 5 (BitNet) is selected.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation.

## License

See LICENSE file for details.
