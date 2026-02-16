# SPAGAT-Librarian AI-Assisted Development Proposal

This document proposes extending SPAGAT-Librarian from a standalone CLI/TUI Kanban task manager into an **offline-capable** AI-powered development assistant for Photon OS.

**Design Philosophy**:

1. **Offline-First**: All core AI functionality works without internet connectivity. Cloud services and communication channels are optional extensions.

2. **Performance**: The C implementation must be highly performant with minimal latency for real-time AI interactions.

3. **Security-Hardened**: Robust cybersecurity posture with input validation, sandboxing, memory safety, and defense-in-depth principles.

4. **Minimal Footprint**: Smallest possible binary size and memory usage. Target < 5MB base process, < 1s boot time.

5. **Balanced Dependencies**: Minimal external libraries to reduce attack surface and complexity, while including essential libraries to maximize intelligence capabilities. Every dependency must justify its inclusion.

---

## Current State

SPAGAT-Librarian v0.2.0 is a C-based Kanban task manager with AI capabilities:
- 6-column Kanban board (Clarification, Won't Fix, Backlog, In Progress, Review, Ready)
- ncurses TUI + CLI interfaces
- SQLite persistence
- Priority levels, due dates, dependencies
- Projects, subtasks, templates
- Time tracking, session management
- Git branch linking
- Local LLM inference via llama.cpp (Gemma-2-2B-IT in GGUF format)
- AI agent with tool use, memory, heartbeat, cron, and skills
- No access key or internet required after initial model download

---

## Feature Priorities

### Critical Priority (Offline Core)

| Feature | Description | Phase |
|---------|-------------|-------|
| **Local/Embedded LLM** | Offline inference using llama.cpp (Gemma-2-2B-IT) | Phase 1 |
| **Workspace Layout** | Structured directory for agent data (~/.spagat/workspace/) | Phase 1 |
| **Conversation History** | Store AI conversations per task in SQLite | Phase 1 |

### High Priority (Offline Core)

| Feature | Description | Phase |
|---------|-------------|-------|
| Streaming Responses | Real-time token streaming in TUI | Phase 1 |
| Checkpoints | Save/restore conversation state | Phase 1 |
| Per-Task Memory | MEMORY.md-style persistent memory per task | Phase 2 |
| Scheduled Tasks (Cron) | Cron-like AI task execution with heartbeat | Phase 2 |
| Heartbeat System | Periodic checks of HEARTBEAT.md for reminders | Phase 2 |
| Security Sandbox | Restrict agent to workspace directory | Phase 2 |
| Git Integration | AI-assisted commits, diffs, branch management | Phase 3 |
| Shell Command Execution | Run commands with AI guidance | Phase 3 |
| Container Isolation | Run AI agents in Docker/containers | Phase 3 |

### Medium Priority (Offline Core)

| Feature | Description | Phase |
|---------|-------------|-------|
| System Prompts | Configurable AI personality per project | Phase 1 |
| Retry Logic | Configurable retry attempts for failures | Phase 1 |
| IPC Messaging | Inter-process communication for agents | Phase 2 |
| Code Editor Integration | Launch $EDITOR with AI context | Phase 3 |
| File Browser | Navigate project files in TUI | Phase 3 |
| Skills Framework | SKILL.md files for extensibility | Phase 4 |
| Custom Commands | User-defined AI commands | Phase 4 |
| Tool Definitions | Define custom tools for AI | Phase 4 |
| Skill Installation | Local skill files | Phase 4 |

### Low Priority (Optional - Requires Internet)

| Feature | Description | Phase |
|---------|-------------|-------|
| Anthropic API Integration | Cloud API (Claude) | Phase 5 |
| OpenRouter API | Multi-model cloud gateway | Phase 5 |
| Google Gemini API | Cloud API | Phase 5 |
| xAI Grok API | Cloud API | Phase 5 |
| MCP Support | Model Context Protocol servers | Phase 5 |
| Web Search (DuckDuckGo) | Online search | Phase 5 |
| Web Search (Brave) | Online search | Phase 5 |
| Web Search (Google) | Online search | Phase 5 |
| Agent Swarms | Multi-agent collaboration | Phase 5 |
| Telegram Channel | Bot communication | Phase 5 |
| Discord Channel | Bot communication | Phase 5 |
| QQ Channel | Bot communication | Phase 5 |
| DingTalk Channel | Bot communication | Phase 5 |
| LINE Channel | Bot communication | Phase 5 |
| Feishu/Lark Channel | Bot communication | Phase 5 |
| WhatsApp Channel | Bot communication | Phase 5 |
| OneBot Channel | Bot communication | Phase 5 |

---

## Workspace Layout

SPAGAT-Librarian uses a structured workspace directory (inspired by **PicoClaw**) for AI agent data:

```
~/.spagat/
├── config.json           # Main configuration file
├── spagat.db             # SQLite database (items, projects, etc.)
├── models/               # Local LLM models
│   └── gemma-2-2b-it.Q4_K_M.gguf  # Quantized model file
└── workspace/            # AI agent workspace
    ├── sessions/         # Conversation sessions and history
    │   ├── <item_id>/    # Per-task conversation files
    │   │   ├── history.json
    │   │   └── context.md
    │   └── global/       # Global conversations
    ├── memory/           # Long-term memory
    │   ├── MEMORY.md     # Persistent agent memory
    │   └── facts.json    # Extracted facts/knowledge
    ├── state/            # Persistent state
    │   └── preferences.json
    ├── cron/             # Scheduled jobs
    │   └── jobs.db       # SQLite for cron entries
    ├── skills/           # Custom skills (local files)
    │   ├── code_review.md
    │   └── git_commit.md
    ├── tools/            # Tool configurations
    │   └── TOOLS.md      # Available tool descriptions
    ├── AGENT.md          # Agent behavior guide
    ├── HEARTBEAT.md      # Periodic task prompts
    ├── IDENTITY.md       # Agent identity/persona
    ├── SOUL.md           # Agent core directives
    └── USER.md           # User preferences and context
```

### Workspace Files Description

| File | Purpose |
|------|---------|
| `AGENT.md` | Defines agent behavior, capabilities, and constraints |
| `IDENTITY.md` | Agent persona, name, communication style |
| `SOUL.md` | Core directives, ethical guidelines, priorities |
| `USER.md` | User preferences, timezone, communication preferences |
| `MEMORY.md` | Long-term memory persisted across sessions |
| `HEARTBEAT.md` | Tasks to check periodically (reminders, monitoring) |
| `TOOLS.md` | Available tools and their descriptions for the agent |

### Initialization Command

```bash
spagat-librarian onboard    # Initialize workspace with default files
spagat-librarian workspace  # Show workspace status
```

---

## Embedded/Local LLM Support (Core Feature)

SPAGAT-Librarian runs AI models locally without internet connectivity, enabling fully offline operation.

### Supported Engines

| Engine | Language | Models | Notes |
|--------|----------|--------|-------|
| **llama.cpp** | C/C++ | GGUF models (Gemma, Llama, Mistral, etc.) | Native C API, MIT license, 95k+ GitHub stars, no access key |

### Recommended Model: Gemma-2-2B-IT

- **Parameters**: 2 billion (lightweight yet capable)
- **Memory**: 2-4 GB with quantization
- **Speed**: ~3 tokens/sec on 8-core CPU
- **Format**: `.gguf` (GGUF quantized, downloaded from HuggingFace)

### Configuration

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
    "model_path": "~/.spagat/models/gemma-2-2b-it.Q4_K_M.gguf",
    "device": "cpu",
    "n_gpu_layers": 0,
    "n_ctx": 2048,
    "temperature": 0.7,
    "top_p": 0.9
  },
  "heartbeat": {
    "enabled": true,
    "interval_minutes": 60
  }
}
```

### Device Options

| Device | Description |
|--------|-------------|
| `cpu` | CPU inference (default) |
| `gpu` | Use GPU acceleration if available (set n_gpu_layers > 0) |

### Setup Instructions

1. Run `make setup` (installs deps, builds llama.cpp, downloads model)
2. Or manually: `make deps && make llama && make model`
3. Configure model_path in `~/.spagat/config.json`
4. Or embed: `make MODEL=models/gemma-2-2b-it.Q4_K_M.gguf`
5. Run offline - no internet required after setup

### CLI Commands

```bash
# Download and setup local model (requires internet once)
spagat-librarian model download gemma-2-2b-it

# List available local models
spagat-librarian model list

# Test local model
spagat-librarian model test

# Use local model for agent (offline)
spagat-librarian agent -m "Hello"
```

### Implementation Architecture

```
┌─────────────────────────────────────────────────┐
│                  ai/local.c                      │
├─────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────┐   │
│  │  Dynamic Library Loading                  │   │
│  │  - dlopen("libllama.so")                 │   │
│  │  - Resolve llama_* function pointers     │   │
│  └──────────────────────────────────────────┘   │
│                      ↓                           │
│  ┌──────────────────────────────────────────┐   │
│  │  Model Initialization                     │   │
│  │  - llama_backend_init()                  │   │
│  │  - llama_model_load_from_file(path)      │   │
│  │  - llama_init_from_model(model, params)  │   │
│  └──────────────────────────────────────────┘   │
│                      ↓                           │
│  ┌──────────────────────────────────────────┐   │
│  │  Token Generation                         │   │
│  │  - Tokenize prompt via llama_tokenize()  │   │
│  │  - Decode with llama_decode()            │   │
│  │  - Sample via llama_sampler_sample()     │   │
│  │  - Detokenize with llama_token_to_piece()│   │
│  │  - Stream tokens to TUI callback         │   │
│  └──────────────────────────────────────────┘   │
│                      ↓                           │
│  ┌──────────────────────────────────────────┐   │
│  │  Cleanup                                  │   │
│  │  - llama_free(ctx)                       │   │
│  │  - llama_model_free(model)               │   │
│  │  - llama_backend_free()                  │   │
│  │  - dlclose()                             │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Prompt Format (Gemma-IT)

```
<start_of_turn>user
{user_message}<end_of_turn>
<start_of_turn>model
{assistant_response}<end_of_turn>
```

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 4 GB | 8 GB |
| Storage | 3 GB | 5 GB |
| GPU | Optional | CUDA/Metal for acceleration |

---

## Technical Architecture

### Database Schema Extensions

```sql
-- AI Conversations
CREATE TABLE conversations (
    id INTEGER PRIMARY KEY,
    item_id INTEGER,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,  -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,
    tokens_used INTEGER DEFAULT 0,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

-- Checkpoints
CREATE TABLE checkpoints (
    id INTEGER PRIMARY KEY,
    item_id INTEGER,
    name TEXT,
    conversation_state TEXT NOT NULL,  -- JSON blob
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

-- Scheduled AI Tasks (Cron)
CREATE TABLE cron_jobs (
    id INTEGER PRIMARY KEY,
    item_id INTEGER,
    cron_expression TEXT,           -- Standard cron or NULL for one-time
    interval_minutes INTEGER,       -- For recurring without cron
    prompt TEXT NOT NULL,
    last_run INTEGER DEFAULT 0,
    next_run INTEGER,
    enabled INTEGER DEFAULT 1,
    one_time INTEGER DEFAULT 0,     -- 1 for reminders, 0 for recurring
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL
);

-- Agent Memory (key-value store)
CREATE TABLE agent_memory (
    id INTEGER PRIMARY KEY,
    project_id INTEGER DEFAULT 0,
    scope TEXT DEFAULT 'global',    -- 'global', 'project', 'task'
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    updated_at INTEGER DEFAULT (strftime('%s', 'now')),
    UNIQUE(project_id, scope, key),
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

-- Tool Invocations (audit log)
CREATE TABLE tool_calls (
    id INTEGER PRIMARY KEY,
    conversation_id INTEGER NOT NULL,
    tool_name TEXT NOT NULL,
    input TEXT,  -- JSON
    output TEXT,  -- JSON
    status TEXT DEFAULT 'pending',
    duration_ms INTEGER,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
```

### New Source Files

```
src/
├── ai/
│   ├── ai.h              # AI interface declarations
│   ├── local.c           # Local/embedded LLM (llama.cpp integration) [CORE]
│   ├── embedded_model.h  # Zero-copy GGUF embedding header
│   ├── embedded_model.c  # Zero-copy GGUF embedding implementation
│   ├── conversation.c    # Conversation management
│   ├── checkpoint.c      # Checkpoint save/restore
│   ├── streaming.c       # Token streaming handler
│   ├── memory.c          # MEMORY.md and agent_memory table
│   ├── tools.c           # Tool definitions and execution
│   ├── anthropic.c       # Anthropic API client [OPTIONAL]
│   ├── openrouter.c      # OpenRouter client [OPTIONAL]
│   ├── gemini.c          # Google Gemini client [OPTIONAL]
│   └── xai.c             # xAI Grok client [OPTIONAL]
├── cli/
│   ├── cli_ai.c          # 19 AI CLI commands (agent, model, ai, checkpoint, cron, memory, skill, etc.)
│   └── cli_ext.c         # Extended CLI commands
├── agent/
│   ├── agent.h           # Agent interface
│   ├── workspace.c       # Workspace directory management
│   ├── onboard.c         # Initialize workspace with defaults
│   ├── heartbeat.c       # Periodic HEARTBEAT.md processing
│   ├── scheduler.c       # Cron job scheduler
│   ├── sandbox.c         # Security sandbox (restrict_to_workspace)
│   └── subagent.c        # Spawn independent subagents
├── db/
│   ├── db_ext.c          # Extended database operations
│   ├── db_project.c      # Project database operations
│   └── db_template.c     # Template database operations
├── tui/
│   └── tui_ext.c         # TUI extensions (priority/due indicators)
├── channel/              # [OPTIONAL - Phase 5]
│   ├── channel.h         # Channel abstraction
│   ├── terminal.c        # Terminal/TUI channel [CORE]
│   ├── gateway.c         # Gateway mode entry point
│   ├── telegram.c        # Telegram bot
│   ├── discord.c         # Discord bot
│   └── webhook.c         # HTTP webhook (LINE, etc.)
└── skill/
    ├── skill.h           # Skill framework
    ├── loader.c          # Load SKILL.md files
    └── executor.c        # Execute skill commands
```

### TUI Extensions

New keyboard shortcuts for AI features:

| Key | Action |
|-----|--------|
| `c` | Open AI conversation for current task |
| `C` | Create checkpoint |
| `A` | Ask AI about current task |
| `g` | AI-assisted git operations |
| `!` | Execute shell command with AI |
| `H` | View/edit HEARTBEAT.md |
| `M` | View/edit MEMORY.md |

### CLI Extensions

```bash
# Workspace Management
spagat-librarian onboard              # Initialize workspace with defaults
spagat-librarian workspace            # Show workspace status
spagat-librarian workspace reset      # Reset to defaults

# Model Management
spagat-librarian model download <name>  # Download model (one-time internet)
spagat-librarian model list             # List local models
spagat-librarian model test             # Test current model

# AI Conversation (offline)
spagat-librarian agent                # Interactive agent mode
spagat-librarian agent -m "..."       # One-shot AI query
spagat-librarian ai <id>              # Start AI chat for task
spagat-librarian ai <id> "<prompt>"   # One-shot AI query for task
spagat-librarian ai history <id>      # Show conversation history

# Checkpoints
spagat-librarian checkpoint save <id> [name]
spagat-librarian checkpoint list <id>
spagat-librarian checkpoint restore <id> <checkpoint_id>

# Scheduled Tasks / Reminders
spagat-librarian cron list
spagat-librarian cron add "<cron>" "<prompt>" [--task <id>]
spagat-librarian cron add --interval 30 "<prompt>"  # Every 30 min
spagat-librarian cron add --once "+10m" "<prompt>"  # One-time in 10 min
spagat-librarian cron pause <job_id>
spagat-librarian cron resume <job_id>
spagat-librarian cron delete <job_id>

# Agent Memory
spagat-librarian memory set <key> <value>
spagat-librarian memory get <key>
spagat-librarian memory list
spagat-librarian memory clear

# Skills (local)
spagat-librarian skill list
spagat-librarian skill run <skill_name>
spagat-librarian skill edit <skill_name>

# Status
spagat-librarian status               # Show overall status
```

---

## Heartbeat System

The heartbeat system periodically checks `HEARTBEAT.md` and executes any pending tasks (offline):

```
┌─────────────────────────────────────────┐
│           Heartbeat Flow                │
├─────────────────────────────────────────┤
│                                         │
│  Timer triggers (every N minutes)       │
│                  ↓                       │
│  Read HEARTBEAT.md                      │
│                  ↓                       │
│  Parse tasks with context               │
│                  ↓                       │
│  For each task:                         │
│    ├─ Spawn subagent (local LLM)        │
│    ├─ Subagent executes independently   │
│    └─ Result logged/displayed           │
│                  ↓                       │
│  Continue to next heartbeat             │
│                                         │
└─────────────────────────────────────────┘
```

Example `HEARTBEAT.md`:

```markdown
# Heartbeat Tasks

## Daily Standup Reminder
- Every day at 9:00 AM, remind me to write standup notes

## Check Task Status
- Every 30 minutes, summarize tasks in "In Progress" column

## Memory Cleanup
- Weekly on Sunday, summarize and compress MEMORY.md
```

---

## Phase 6: Taskter-Inspired Features

Inspired by [Taskter](https://github.com/tomatyss/taskter) (Rust-based CLI Kanban for AI agents), the following features extend SPAGAT-Librarian with agent-task integration, improved TUI, and external tool interoperability.

### 6.1 Bordered Column TUI (IMPLEMENTED)

Each status column is rendered as a distinct bordered box using ncurses ACS line-drawing characters. The column title and item count are centered in the top border. The active column's title is highlighted. This replaces the previous plain-text column headers and provides much clearer visual separation, especially with 6 status columns on wide terminals.

### 6.2 Agent-to-Task Assignment

Bind AI agents to specific Kanban tasks for autonomous execution. When an agent is assigned to a task, it receives the task title and description as context, executes using its configured tools, and updates the task status on completion (move to Done) or failure (move back to Backlog with a comment).

| Component | Description |
|-----------|-------------|
| `task assign --task-id <id> --agent-id <id>` | Assign an agent to a task |
| `task unassign --task-id <id>` | Remove agent assignment |
| `task execute --task-id <id>` | Execute the assigned agent on the task |
| TUI: `a` on task | Assign agent from a picker dialog |
| TUI: `r` on task | Unassign agent |
| TUI: `x` on task | Execute assigned agent |
| Task indicator | `*` prefix for assigned, `>` for actively running |

**Database extension**:
```sql
ALTER TABLE items ADD COLUMN agent_id INTEGER DEFAULT NULL;
ALTER TABLE items ADD COLUMN agent_comment TEXT DEFAULT NULL;
```

### 6.3 MCP Server over stdio

Expose SPAGAT-Librarian's tools as an MCP (Model Context Protocol) server over stdio, allowing external MCP clients (VS Code, Cursor, Claude Desktop, other agents) to interact with the Kanban board and agent tools programmatically.

```bash
spagat-librarian mcp serve    # Start MCP server on stdio
```

**Supported MCP methods**:
- `initialize` / `shutdown` / `ping`
- `tools/list` -- enumerate all registered tools
- `tools/call` -- execute a tool (list_directory, read_text_file, shell, etc.)
- `tasks/list` -- list Kanban tasks with status filters
- `tasks/add` / `tasks/update` / `tasks/move` -- modify board
- `agent/chat` -- send a prompt to the local LLM

**Protocol**: JSON-RPC with `Content-Length` framing (standard MCP stdio transport). Line-delimited mode available via environment variable for compatibility.

**Implementation**: ~500 LOC in `src/mcp/mcp_server.c`. Parse JSON-RPC from stdin, dispatch to existing tool/CLI functions, serialize response to stdout. No new dependencies -- hand-rolled JSON parsing (consistent with existing `config_io.c` approach).

### 6.4 OKR Tracking (Objectives & Key Results)

Add goal tracking alongside the Kanban board. OKRs provide a higher-level view of project progress that the AI agent can reference when prioritizing tasks.

```bash
spagat-librarian okr add -o "Ship v1.0" -k "All critical bugs fixed" -k "README complete"
spagat-librarian okr list
spagat-librarian okr progress <okr_id> <key_result_index> <percent>
```

**Database extension**:
```sql
CREATE TABLE okrs (
    id INTEGER PRIMARY KEY,
    project_id INTEGER DEFAULT 0,
    objective TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);

CREATE TABLE key_results (
    id INTEGER PRIMARY KEY,
    okr_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    progress REAL DEFAULT 0.0,  -- 0.0 to 1.0
    FOREIGN KEY (okr_id) REFERENCES okrs(id) ON DELETE CASCADE
);
```

**TUI**: `O` key opens an OKR popup showing objectives with progress bars for each key result. The AI agent can update progress via a `update_okr` tool.

### 6.5 run_python Tool

Add inline Python execution alongside the existing `shell` tool. Useful for data processing, calculations, and file transformations that are awkward in shell.

```
TOOL_CALL: run_python
import os; print(os.listdir('.'))
END_TOOL_CALL
```

**Implementation**: Fork/exec the system Python interpreter with `-c` flag. Same timeout, output truncation, autonomy checks, and sandboxing as `tool_shell`. ~50 LOC in `tools_builtin.c`.

### 6.6 Operation Logs Viewer in TUI

Add a popup (`L` key) showing the journal log (`~/.spagat/logs/spagat.log`) from inside the TUI. Scrollable with up/down keys. Currently, logs are only accessible by manually reading the log file.

**Implementation**: Read last N lines of the journal file into a buffer, display in a centered popup using the existing `tui_draw_help` pattern. ~80 LOC in `tui_dialogs_misc.c`.

### 6.7 Task Comments / Agent Feedback

Allow agents to leave comments on tasks after execution. Comments persist as a conversation thread visible in the task detail view. When an agent fails a task, the error is automatically added as a comment.

**Database extension**:
```sql
CREATE TABLE task_comments (
    id INTEGER PRIMARY KEY,
    item_id INTEGER NOT NULL,
    author TEXT NOT NULL,  -- 'user' or 'agent'
    content TEXT NOT NULL,
    created_at INTEGER DEFAULT (strftime('%s', 'now')),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);
```

**TUI**: `c` key on a task opens a comment popup showing the thread. `C` adds a new user comment.

### 6.8 Cron-based Agent Scheduler

Extend the existing heartbeat/cron system to support agent-task scheduling. Agents assigned to tasks can be scheduled to run at specific times or intervals using cron expressions, enabling autonomous task execution.

```bash
spagat-librarian cron add "0 9 * * *" "execute task 5" --task 5
spagat-librarian cron add --interval 60 "check task 3 status" --task 3
```

When the scheduler fires, it:
1. Loads the task context (title, description, comments)
2. Spawns the assigned agent with that context
3. Runs the agent's tool loop
4. Updates the task status and adds a comment with the result

This is already partially implemented in `heartbeat.c` and `scheduler.c`. The extension wires cron jobs to specific task-agent pairs rather than free-form prompts.

### 6.9 Layered Configuration

Support 4-layer configuration merging (inspired by Taskter's config system):

1. **Code defaults** -- works out of the box
2. **Global config** -- `~/.spagat/config.json`
3. **Environment variables** -- `SPAGAT__SECTION__KEY` format (e.g., `SPAGAT__LOCAL__N_CTX=4096`)
4. **CLI flags** -- per-run overrides (e.g., `--autonomy=full`)

Currently only layers 1, 2, and 4 are implemented. Layer 3 (environment variables) adds ops-friendly configuration without editing files, useful for Docker/container deployments.

### Priority Matrix

| Feature | Priority | Effort | Phase |
|---------|----------|--------|-------|
| 6.1 Bordered Column TUI | Critical | Done | Implemented |
| 6.2 Agent-to-Task Assignment | High | Medium (~300 LOC) | Phase 6 |
| 6.3 MCP Server | High | Medium (~500 LOC) | Phase 6 |
| 6.7 Task Comments | High | Low (~150 LOC) | Phase 6 |
| 6.5 run_python Tool | Medium | Low (~50 LOC) | Phase 6 |
| 6.6 Logs Viewer in TUI | Medium | Low (~80 LOC) | Phase 6 |
| 6.4 OKR Tracking | Medium | Medium (~300 LOC) | Phase 6 |
| 6.8 Cron Agent Scheduler | Medium | Medium (~200 LOC) | Phase 6 |
| 6.9 Layered Configuration | Low | Low (~100 LOC) | Phase 6 |

### References

- [Taskter](https://github.com/tomatyss/taskter) -- Rust CLI Kanban for AI agents (MIT license)
- [MCP Specification](https://modelcontextprotocol.io/) -- Model Context Protocol for tool interop
- [ratatui](https://ratatui.rs/) -- Rust TUI framework used by Taskter (bordered Box widget inspiration)

---

## Implementation Phases (Offline-First)

### Phase 1: Core Offline AI (Weeks 1-4) - IMPLEMENTED
**Internet Required**: Only for initial model download

- [x] Local LLM integration (llama.cpp)
- [x] Workspace directory structure
- [x] `onboard` command to initialize workspace
- [x] Conversations table and CRUD
- [x] Basic CLI chat interface (agent command)
- [x] Token streaming in ncurses
- [x] System prompts (AGENT.md, IDENTITY.md, SOUL.md)

Note: Model download is handled by `make model` rather than a dedicated CLI command. `model list` and `model test` commands work.

### Phase 2: Memory & Scheduling (Weeks 5-8) - IMPLEMENTED
**Internet Required**: No

- [x] Checkpoint save/restore
- [x] Conversation history viewer (ai history command)
- [x] MEMORY.md persistence
- [x] IDENTITY.md and SOUL.md loading (via onboard)
- [x] Cron job scheduler
- [x] HEARTBEAT.md parser and executor
- [x] Security sandbox (restrict_to_workspace)

### Phase 3: Local Tools (Weeks 9-12) - PARTIALLY IMPLEMENTED
**Internet Required**: No

- [x] Define tool schema (read_file, write_file, list_dir, shell)
- [x] Tool execution framework
- [ ] Git integration (AI-assisted commits, diffs, branch management)
- [x] Shell command execution (via shell tool)
- [ ] Code editor integration
- [ ] File browser in TUI
- [ ] Container isolation (Docker)

### Phase 4: Skills & Extensions (Weeks 13-16) - PARTIALLY IMPLEMENTED
**Internet Required**: No

- [x] SKILL.md parser
- [x] Skill execution engine
- [x] Local skill management (skill list/run)
- [ ] Custom commands
- [x] Per-project memory storage (agent_memory has project_id field)
- [ ] System prompt customization per project

### Phase 5: Online Features (Optional, Weeks 17+) - NOT IMPLEMENTED
**Internet Required**: Yes

- [ ] Anthropic API client
- [ ] OpenRouter API client
- [ ] Google Gemini API client
- [ ] xAI Grok API client
- [ ] MCP server support
- [ ] Web search (DuckDuckGo, Brave, Google)
- [ ] Gateway mode entry point
- [ ] Telegram bot integration
- [ ] Discord bot integration
- [ ] Other communication channels
- [ ] Agent swarms

---

## Dependencies

### Required (Offline Core)

| Library | Purpose | Package (Photon OS) |
|---------|---------|---------------------|
| ncurses | TUI interface | `ncurses-devel` |
| SQLite | Database | `sqlite-devel` |
| llama.cpp | Local LLM inference | Built from source (`make llama`) |

### Optional (Online Features - Phase 5)

| Library | Purpose | Package |
|---------|---------|---------|
| libcurl | HTTP client for cloud APIs | `curl-devel` |
| OpenSSL | TLS for HTTPS | `openssl-devel` |
| Docker CLI | Container runtime | `docker` |
| libgit2 | Git operations | `libgit2-devel` |

---

## Implementation Principles

### Performance Requirements

- **Response Latency**: < 500ms first token in TUI
- **Boot Time**: < 1s startup time
- **Memory Efficiency**: < 5MB RAM for base process (excluding LLM model)
- **Binary Size**: Target < 2MB stripped binary for core features
- **Code Size**: Each source file < 15KB for maintainability

### Security Hardening

| Principle | Implementation |
|-----------|----------------|
| **Input Validation** | Sanitize all user input and AI-generated commands before execution |
| **Memory Safety** | Use bounded string operations (snprintf, strncpy), clear sensitive data after use |
| **Least Privilege** | Security sandbox restricts file access to workspace directory |
| **Defense in Depth** | Container isolation, input validation, output sanitization |
| **No Secrets in Logs** | Never log API keys, tokens, or sensitive user data |
| **Secure Defaults** | Offline mode, sandbox enabled, minimal permissions by default |

### Dependency Philosophy

**Goal**: Balance between minimal dependencies (security, size) and maximum intelligence (capability).

| Category | Approach |
|----------|----------|
| **Essential** | Include if critical for core functionality (SQLite, ncurses, llama.cpp) |
| **Justified** | Include only if benefit significantly outweighs cost |
| **Avoided** | Prefer standard library or custom implementation for simple tasks |
| **Optional** | Cloud/network libraries only compiled when Phase 5 features enabled |

**Dependency Audit Criteria**:
1. Is it actively maintained?
2. What is the security track record?
3. Can we vendor/embed it to reduce supply chain risk?
4. Is there a simpler alternative?
5. Does it add significant binary size?

### Code Quality Standards

- **C Standard**: C11 with POSIX extensions
- **Compiler Warnings**: `-Wall -Wextra -Werror` clean
- **Static Analysis**: Pass cppcheck, Coverity, or similar
- **Memory Checking**: Valgrind clean (no leaks, no errors)
- **Fuzzing**: Critical input parsing functions fuzz-tested

---

## Security Considerations

1. **Security Sandbox**: `restrict_to_workspace` limits file access to workspace directory
2. **Local-First**: Sensitive data never leaves the device by default
3. **Container Isolation**: Agents can run in sandboxed containers
4. **Input Sanitization**: Validate all AI-generated commands before execution
5. **Secrets in Memory**: Clear sensitive data after use (explicit_bzero)
6. **API Key Storage** (Phase 5): Never log or expose API keys if cloud features enabled
7. **Secure IPC**: Validate all inter-process messages
8. **Command Injection Prevention**: Whitelist allowed commands, escape shell arguments

---

## Configuration (Offline-First)

`~/.spagat/config.json`:

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
    "model_path": "~/.spagat/models/gemma-2-2b-it.Q4_K_M.gguf",
    "device": "cpu",
    "n_gpu_layers": 0,
    "n_ctx": 2048,
    "temperature": 0.7,
    "top_p": 0.9
  },
  "heartbeat": {
    "enabled": true,
    "interval_minutes": 60
  }
}
```

### Extended Configuration (Phase 5 - Optional)

```json
{
  "providers": {
    "anthropic": {
      "enabled": false,
      "api_key": "",
      "api_base": "https://api.anthropic.com/v1"
    },
    "openrouter": {
      "enabled": false,
      "api_key": "",
      "api_base": "https://openrouter.ai/api/v1"
    },
    "gemini": {
      "enabled": false,
      "api_key": "",
      "api_base": "https://generativelanguage.googleapis.com/v1beta"
    },
    "xai": {
      "enabled": false,
      "api_key": "",
      "api_base": "https://api.x.ai/v1"
    }
  },
  "channels": {
    "telegram": {
      "enabled": false,
      "token": "",
      "allow_from": []
    },
    "discord": {
      "enabled": false,
      "token": "",
      "allow_from": []
    }
  },
  "tools": {
    "web": {
      "duckduckgo": { "enabled": false, "max_results": 5 },
      "brave": { "enabled": false, "api_key": "", "max_results": 5 },
      "google": { "enabled": false, "api_key": "", "cx": "", "max_results": 5 }
    }
  }
}
```

---

## Comparison Matrix

| Feature | SPAGAT-Librarian | Taskter | claude-ws | nanoclaw | PicoClaw |
|---------|------------------|---------|-----------|----------|----------|
| Language | C | Rust | TypeScript | TypeScript | Go |
| Interface | TUI/CLI | TUI/CLI | Web | WhatsApp/CLI | CLI/Gateway |
| Database | SQLite | JSON files | SQLite | SQLite | Files |
| Memory Footprint | <5MB | <10MB | >1GB | >100MB | <10MB |
| **Offline Capable** | **Yes (Core)** | Partial (Ollama) | No | No | No |
| Local LLM | Yes (llama.cpp) | Yes (Ollama) | No | No | No |
| Streaming | Yes | Yes | Socket.io | SDK Native | Yes |
| Checkpoints | Yes | No | Yes | No | No |
| Workspace Layout | Yes | .taskter/ | No | No | Yes |
| Container Isolation | Yes | Docker | No | Yes | No |
| Heartbeat System | Yes | No | No | No | Yes |
| Scheduled Tasks | Yes | Yes (cron) | No | Yes | Yes |
| Memory System | Yes | No | CLAUDE.md | CLAUDE.md | MEMORY.md |
| Cloud APIs | Optional | Gemini/OpenAI | Required | Required | Required |
| Multi-channel | Optional | No | No | Yes | Yes |
| Agent-Task Binding | Proposed | Yes | No | No | No |
| MCP Server | Proposed | Yes (stdio) | No | No | No |
| OKR Tracking | Proposed | Yes | No | No | No |
| Bordered TUI | **Yes** | Yes (ratatui) | N/A | N/A | No |
| Tool Catalog | 14+ tools | 10 tools | N/A | N/A | ~5 tools |
| Multi-Provider | 1 (local) | 3 (Gemini/OpenAI/Ollama) | 1 | 1 | 1 |

---

## Success Metrics

1. **Offline Operation**: 100% core functionality without internet
2. **Response Latency**: < 500ms first token in TUI (local LLM)
3. **Memory Efficiency**: < 5MB RAM for base process (excluding model)
4. **Model Memory**: < 4GB for Gemma-2B quantized
5. **Boot Time**: < 1s startup time
6. **Binary Size**: < 2MB stripped binary (core features)
7. **Code Size**: Each source file < 15KB
8. **Security**: Zero critical/high vulnerabilities in static analysis
9. **Dependencies**: < 5 required external libraries for core

---

## References

### Core (Offline)
- [llama.cpp](https://github.com/ggml-org/llama.cpp) - LLM inference in C/C++ (MIT license)
- [Gemma-2-2B-IT GGUF](https://huggingface.co/QuantFactory/gemma-2-2b-it-GGUF) - Quantized model on HuggingFace
- [Google Gemma-2-2B-IT](https://huggingface.co/google/gemma-2-2b-it) - Lightweight instruction-tuned model
- [PicoClaw](https://github.com/sipeed/picoclaw) - Ultra-lightweight Go AI assistant with workspace layout

### Optional (Online - Phase 5)
- [Anthropic API Documentation](https://docs.anthropic.com/en/api)
- [OpenRouter API](https://openrouter.ai/docs) - Multi-model API gateway
- [Google Gemini API](https://ai.google.dev/docs) - Google AI Studio
- [xAI Grok API](https://docs.x.ai/api) - xAI Grok models
- [Google Custom Search API](https://developers.google.com/custom-search/v1/overview)

### Inspiration
- [claude-ws](https://github.com/Claude-Workspace/claude-ws) - Web-based Claude Kanban workspace
- [nanoclaw](https://github.com/qwibitai/nanoclaw) - WhatsApp Claude assistant with container isolation

---

## License

This proposal extends SPAGAT-Librarian under the same license terms.

---

*Document Version: 3.2 (Offline-First, llama.cpp, Taskter-inspired)*
*Created: 2026-02-15*
*Updated: 2026-02-16*
*Author: SPAGAT-Librarian Development Team*
