# INTEGRATION

SPAGAT-Librarian is a small C binary with a stable-ish CLI, a SQLite
store, and a tiny public C-ABI. That is enough surface to drive it from
a shell, embed it into another tool, or feed it a stream of events from
an existing incident-response or dashboard system.

This document covers three integration patterns:

1. **Shell / CLI** — call `spagat-librarian` from another script.
2. **Library** — link the console core as a library (`libspagat-console`).
3. **Event input** — pipe a JSON stream of kanban operations into the
   binary and let it maintain the board.

## Pattern 1 — shell

Every kanban operation available in the TUI is also a subcommand:

```bash
spagat-librarian add "Rotate the TLS certificate" --priority high --tag ops
spagat-librarian list --status backlog --json
spagat-librarian move <id> --to progress
spagat-librarian close <id>
```

The `--json` flag on read commands produces one JSON object per line
(NDJSON), so you can pipe the output into `jq`, a log shipper, or
another tool.

Return codes follow the usual convention: `0` on success, `2` on user
error, `1` on internal error. The binary always writes structured error
messages to stderr; stdout is reserved for data.

## Pattern 2 — library

The console core builds as `libspagat-console` (both a static
`libspagat-console.a` and a shared `libspagat-console.so`) so a
third-party tool can link the kanban and skill engine directly.

The public C-ABI is a small set of opaque handles and functions
declared in a public shim header
`include/spagat.h`. In outline:

```c
#include <spagat.h>

/* Open (or create) a kanban store at the given path. */
spagat_db_t *db = spagat_db_open("/home/alice/.local/state/spagat/spagat.db");

/* Add a card. */
spagat_item_id_t id = spagat_item_add(db, &(spagat_item_new_t){
    .title      = "Investigate disk pressure",
    .priority   = SPAGAT_PRIORITY_HIGH,
    .status     = SPAGAT_STATUS_BACKLOG,
    .tag        = "ops",
});

/* Move it. */
spagat_item_set_status(db, id, SPAGAT_STATUS_PROGRESS);

/* Iterate all cards in one column. */
spagat_item_iter_t *it = spagat_item_iter_open(db, SPAGAT_STATUS_PROGRESS);
const spagat_item_t *item;
while ((item = spagat_item_iter_next(it)) != NULL) {
    printf("%lld  %s\n", (long long)item->id, item->title);
}
spagat_item_iter_close(it);

spagat_db_close(db);
```

Only the symbols and types declared in `spagat.h` are considered public
API — anything in the `src/` tree is subject to change without notice.
The shim header intentionally exposes a narrow surface (open / close /
add / edit / move / query) so downstream code does not have to track
internal refactors.

Build against the shared library:

```bash
gcc my_tool.c -lspagat-console -lsqlite3 -o my_tool
```

## Pattern 3 — event input over stdin

For tools that already emit events (a dashboard, an alert manager, an
issue tracker), the CLI accepts a stream of NDJSON operations on
stdin. This is a **minimal, local event schema** — it is not a
cross-tool contract, just a script-friendly way to drive the board.

Feed events with the `stream` subcommand:

```bash
tail -F my-events.ndjson | spagat-librarian stream
```

Each line is one JSON object with an `op` field.

### `op: "add"` — create a card

```json
{
  "op":       "add",
  "title":    "Investigate disk pressure on /var",
  "priority": "high",
  "status":   "backlog",
  "tag":      "ops",
  "description": "df -h shows /var at 92%"
}
```

Optional fields: `priority` (`none`|`low`|`medium`|`high`|`critical`),
`status` (`clarification`|`wontfix`|`backlog`|`progress`|`review`|`ready`),
`tag` (short string), `description` (long text), `due_date`
(RFC 3339 UTC).

The response, written to stdout, is one JSON object with the new card
id:

```json
{ "op": "add", "ok": true, "id": 1042 }
```

### `op: "move"` — change a card's column

```json
{ "op": "move", "id": 1042, "to": "progress" }
```

### `op: "close"` — mark a card ready

```json
{ "op": "close", "id": 1042 }
```

Equivalent to `move` with `"to": "ready"`.

### `op: "edit"` — update fields on a card

```json
{
  "op":       "edit",
  "id":       1042,
  "title":    "Investigate disk pressure on /var (updated)",
  "priority": "critical"
}
```

Only the fields present in the object are updated.

### Error responses

```json
{ "op": "add", "ok": false, "error": "priority must be one of none|low|medium|high|critical" }
```

Errors do not terminate the stream — the binary reads the next line
and keeps going. Fatal I/O errors (SQLite failure, EOF on a broken
pipe) exit with code 1.

## Persisting state elsewhere

The default kanban store is `$XDG_STATE_HOME/spagat/spagat.db`. Two
overrides are supported:

```bash
# Absolute path, per-invocation:
SPAGAT_DB=/mnt/shared/team-ops.db spagat-librarian list

# Or globally, in ~/.config/spagat/config.toml:
[state]
db_path = "/mnt/shared/team-ops.db"
```

The store is a plain SQLite 3 database. Standard SQLite tools work:

```bash
sqlite3 /mnt/shared/team-ops.db ".schema"
sqlite3 /mnt/shared/team-ops.db "select id,title,status from items where status='progress';"
```

If you host the DB on a shared filesystem, keep in mind SQLite's usual
single-writer constraint — either serialise writers, or split into
per-user files that a periodic job merges.
