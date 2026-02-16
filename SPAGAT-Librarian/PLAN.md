# SPAGAT-Librarian - Implementation Plan

## Overview

SPAGAT-Librarian is a Photon OS CLI tool written entirely in **C** that provides a Kanban-style task management dashboard using **ncurses** for the textual user interface and **SQLite** as the persistent storage backend.

---

## Core Technologies

| Component | Technology |
|-----------|------------|
| Language | C (C11 standard) |
| TUI Library | ncurses |
| Database | SQLite3 |
| Build System | CMake or Makefile |

---

## Functional Requirements

### 1. Dual Operation Modes

#### 1.1 Interactive TUI Mode (default, no parameters)
- Launch ncurses-based Kanban dashboard
- Visual board with columns for each status
- Mouse and keyboard navigation support
- Real-time updates from SQLite database

#### 1.2 Command-Line Mode (with parameters)
- Scriptable interface for automation
- Compatible command syntax inspired by kanban.bash

### 2. Kanban Statuses (6 columns)

| Column | Description |
|--------|-------------|
| **In Clarification** | Items requiring more information or discussion |
| **Won't Fix/Implement** | Items explicitly rejected or deferred indefinitely |
| **In Backlog** | Items acknowledged but not yet scheduled |
| **In Progress** | Items currently being worked on |
| **In Review** | Items completed, awaiting review/approval |
| **Ready** | Items completed and ready for release/deployment |

### 3. Core Features (Migrated from kanban.bash)

#### 3.1 Item Management
- `add <status> <tag> <description>` - Add new item
- `<id>` - Edit item (opens $EDITOR)
- `<id> <status>` - Move item to different status
- `list` - List all items
- `<status> [status...]` - Filter items by status(es)
- `tags` - List all tags in use
- `csv` - Export/import functionality (for migration)

#### 3.2 Statistics
- `stats status [tag]` - Show status distribution
- `stats tag` - Show tag distribution  
- `stats history` - Show task transition history

#### 3.3 Board Display
- `show [status...]` - Display ASCII Kanban board
- Responsive layout based on terminal width
- Color support (with NOCOLOR=1 fallback)
- UTF-8 box drawing characters (with PLAIN=1 fallback)

### 4. Multi-Select and Batch Operations

- Select multiple items using checkboxes or shift+arrow
- Move selected items to a target status in batch
- Bulk status transitions with confirmation

### 5. SQLite Database Schema

```sql
CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    status TEXT NOT NULL,
    tag TEXT,
    description TEXT NOT NULL,
    history TEXT DEFAULT '',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE config (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX idx_items_status ON items(status);
CREATE INDEX idx_items_tag ON items(tag);
```

---

## Enhancement Features (Inspired by vibe-kanban)

The following features from vibe-kanban can enhance SPAGAT-Librarian:

### High Priority Enhancements

| Feature | Description | Complexity |
|---------|-------------|------------|
| **Task Templates** | Predefined task templates for common workflows | Medium |
| **Task Filtering & Search** | Quick filter/search across all items | Medium |
| **Task History Tracking** | Full audit log of all status changes with timestamps | Low |
| **Keyboard Shortcuts** | Vim-style navigation (hjkl) and quick actions | Low |
| **Task Dependencies** | Link tasks as blockers/dependencies | High |
| **Priority Levels** | Assign priority (Critical/High/Medium/Low) to items | Low |

### Medium Priority Enhancements

| Feature | Description | Complexity |
|---------|-------------|------------|
| **Multiple Boards/Projects** | Support for separate kanban boards per project | Medium |
| **Task Attempts/Subtasks** | Hierarchical tasks with parent-child relationships | High |
| **Due Dates & Deadlines** | Add optional due dates with visual indicators | Medium |
| **Swimlanes by Tag** | Group items by tag in horizontal swimlanes | Medium |
| **Custom Statuses** | User-configurable status columns | Medium |
| **Data Export** | Export board to JSON/CSV/Markdown formats | Low |

### Lower Priority Enhancements

| Feature | Description | Complexity |
|---------|-------------|------------|
| **Session Management** | Save/restore board view states | Medium |
| **Notifications** | Desktop notifications for overdue items | High |
| **Git Integration** | Link tasks to git branches/commits | High |
| **Time Tracking** | Track time spent in each status | Medium |
| **Workspaces** | Isolated work environments (like git worktrees) | High |
| **Remote SSH Support** | Open related files via SSH in editor | High |

---

## Architecture

```
SPAGAT-Librarian/
├── src/
│   ├── main.c              # Entry point, argument parsing
│   ├── tui/
│   │   ├── tui.h           # TUI public interface
│   │   ├── tui.c           # ncurses initialization/cleanup
│   │   ├── board.c         # Kanban board rendering
│   │   ├── input.c         # Keyboard/mouse input handling
│   │   ├── dialogs.c       # Modal dialogs (add/edit/move)
│   │   └── colors.c        # Color scheme management
│   ├── db/
│   │   ├── db.h            # Database public interface
│   │   ├── db.c            # SQLite connection management
│   │   ├── items.c         # Item CRUD operations
│   │   └── stats.c         # Statistics queries
│   ├── cli/
│   │   ├── cli.h           # CLI public interface
│   │   ├── commands.c      # Command implementations
│   │   └── parser.c        # Argument parsing
│   └── util/
│       ├── util.h          # Utility functions
│       ├── config.c        # Configuration management
│       └── strings.c       # String manipulation helpers
├── include/
│   └── spagat.h            # Public header with types/constants
├── sql/
│   └── schema.sql          # Database schema
├── tests/
│   └── test_*.c            # Unit tests
├── CMakeLists.txt          # Build configuration
├── Makefile                # Alternative build system
└── README.md               # Documentation
```

---

## Command-Line Interface

```
SPAGAT-Librarian - Kanban Task Manager for Photon OS

Usage:
  spagat-librarian                         # Launch TUI dashboard
  spagat-librarian init                    # Initialize database
  spagat-librarian add <status> <tag> <desc>  # Add new item
  spagat-librarian <id>                    # Edit item
  spagat-librarian <id> <status>           # Move item to status
  spagat-librarian show [status...]        # Display board
  spagat-librarian list                    # List all items
  spagat-librarian <status>                # List items by status
  spagat-librarian tags                    # List all tags
  spagat-librarian stats <type> [filter]   # Show statistics
  spagat-librarian export <format>         # Export to csv/json
  spagat-librarian import <file>           # Import from csv

Statuses:
  clarification  wontfix  backlog  progress  review  ready

Environment Variables:
  NOCOLOR=1      Disable colors
  PLAIN=1        Use ASCII instead of UTF-8 box drawing
  EDITOR         Editor for item editing (default: vi)

Examples:
  spagat-librarian add backlog feature "Implement dark mode"
  spagat-librarian 42 progress
  spagat-librarian show progress review
  spagat-librarian stats status feature
```

---

## TUI Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `h/j/k/l` or arrows | Navigate |
| `Enter` | Edit selected item |
| `Space` | Toggle item selection |
| `a` | Add new item |
| `m` | Move selected items |
| `d` | Delete selected items |
| `/` | Search/filter |
| `1-6` | Jump to column |
| `Tab` | Next column |
| `Shift+Tab` | Previous column |
| `r` | Refresh board |
| `?` | Show help |
| `q` | Quit |

---

## Build Requirements

### Dependencies
- GCC or Clang (C11 support)
- ncurses development library
- SQLite3 development library
- CMake 3.10+ (optional)

### Photon OS Installation
```bash
tdnf install -y gcc ncurses-devel sqlite-devel cmake make
```

### Build Commands
```bash
# Using CMake
mkdir build && cd build
cmake ..
make

# Using Makefile
make
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
- [ ] Project setup with build system
- [ ] SQLite database layer
- [ ] Basic CLI commands (init, add, list, show)
- [ ] Item CRUD operations

### Phase 2: TUI Core (Week 3-4)
- [ ] ncurses initialization and cleanup
- [ ] Board rendering with 6 columns
- [ ] Basic keyboard navigation
- [ ] Item display and selection

### Phase 3: Item Management (Week 5-6)
- [ ] Multi-select functionality
- [ ] Batch move operations
- [ ] Item editing with $EDITOR
- [ ] Status transitions with history

### Phase 4: Statistics & Polish (Week 7-8)
- [ ] Statistics commands
- [ ] Color themes
- [ ] Responsive layout
- [ ] Error handling and edge cases

### Phase 5: Enhancements (Week 9+)
- [ ] Task templates
- [ ] Search/filter functionality
- [ ] Priority levels
- [ ] Due dates
- [ ] Export/import features

---

## Testing Strategy

1. **Unit Tests**: Test database operations, string utilities
2. **Integration Tests**: Test CLI commands end-to-end
3. **TUI Tests**: Manual testing with different terminal sizes
4. **Regression Tests**: Ensure kanban.bash compatibility

---

## License

To be determined (consider AGPL-3.0 for compatibility with kanban.bash inspiration)

---

## References

- [kanban.bash](https://github.com/coderofsalvation/kanban.bash) - Original inspiration for CLI interface
- [vibe-kanban](https://github.com/BloopAI/vibe-kanban) - Feature inspiration for enhancements
- [ncurses documentation](https://invisible-island.net/ncurses/)
- [SQLite C Interface](https://www.sqlite.org/c3ref/intro.html)
