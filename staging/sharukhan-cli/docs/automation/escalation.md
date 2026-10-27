# The escalation

[← sharukhan overview](../../README.md)

**Who this is for:** The maintainer deciding on or reviewing an escalation: budgets, confinement and the MCP server.

## The escalation: `sharukhan escalate` and `sharukhan mcp`

A PR the sync could not rebase, or whose checks failed, can be handed to
Claude. The model gets only sharukhan's own tools, works under token budgets,
and nothing it says is believed: sharukhan reruns its own checks on whatever
it proposes, and a proposal becomes a candidate only through `sync decide`.

### Before the first escalation: `escalate preflight`

```bash
sharukhan escalate preflight
```

It checks the API key without spending a token (set, shaped like an
Anthropic key, accepted by `GET /v1/models`) and prints the budgets and the
price weights. The key comes from `MC_ANTHROPIC_KEY_FILE` (a root-owned 0600
file, written by `service install --escalation-key-from-env`) or else from
`ANTHROPIC_API_KEY`. It is passed to `curl` on stdin and to `claude` in its
environment only; it is never printed, logged or stored elsewhere.

### One escalation, the queue, the ledger

```bash
sharukhan escalate --run 7 --pr 23     # one attempt for PR #23 of run 7
sharukhan escalate queue --run 7       # every refused or failed PR of run 7, parents first
sharukhan escalate ledger              # the last 30 attempts: tokens, turns, cost, outcome
```

The queue skips a PR waiting on an undecided parent, one with a verified
proposal and one out of attempts. A run or day budget, a rate limit or a
missing key stops the queue; `sync auto` admits it again on its next tick. A
parked PR is one notification, not one per tick. `MC_ESCALATE=off` leaves a
stopped run to a person.

Outcomes in the ledger: `verified` (sharukhan's own verify passes the
proposal), `proposed` (it does not), `no-proposal`, `budget`, `parked`,
`failed`, `interrupted` (its process died; counts as an attempt) and `void`
(invalidated by a sharukhan defect; not an attempt).

### Taking a verified proposal

```bash
sharukhan escalate ledger | head -3
sharukhan sync decide 7 23 candidate refs/heads/sync/7/proposal/<branch>
sharukhan sync body --set 7 23 proposed     # the description it proposed, if it passes the lint
sharukhan sync resume 7
```

### Budgets and price weights

Tokens are counted by price relative to uncached input: input and output 1,
cache read 0.1, cache write 1.25 (5-minute cache) or 2.0 (1-hour cache).

| Setting | Default | Meaning |
|---|---|---|
| `MC_ESC_TOKENS_PER_ESCALATION` | `150000` | weighted tokens of one attempt; the stream is stopped when exceeded |
| `MC_ESC_TOKENS_PER_RUN` | `500000` | weighted tokens of all attempts of one sync run |
| `MC_ESC_TOKENS_PER_DAY` | `1000000` | weighted tokens per day |
| `MC_ESC_ATTEMPTS` | `2` | failed attempts per PR and run before it is parked for a person |
| `MC_ESC_MAX_TURNS` | `25` | turns per attempt |
| `MC_ESC_MODEL` / `MC_ESC_FALLBACK_MODEL` | `opus` / `sonnet` | models |
| `MC_ESC_WEIGHT_CACHE_READ` | `0.1` | price weight |
| `MC_ESC_WEIGHT_CACHE_WRITE_5M` / `_1H` | `1.25` / `2.0` | price weights |
| `MC_ESCALATE` | `auto` | `auto` or `off`; anything else is an error |

### How the model is confined

* `claude --bare -p --tools ""`: no built-in tool (no shell, files, web or
  sub-agents); the only tools are `mcp__sharukhan__*`.
* A private empty working directory and `HOME`, an environment of `PATH`,
  `HOME`, the key and `DISABLE_AUTOUPDATER` only.
* The MCP server is started under `env -i` with only the settings its own work
  needs, so it never sees the key.
* `verify` runs the spec tools in read-only, capability-free containers without
  network; only a directory the caller names is writable.

### The MCP server: `sharukhan mcp`

```bash
sharukhan mcp --run 7 --pr 23                       # escalation profile (default)
sharukhan mcp --run 7 --pr 23 --profile readonly    # read tools only
```

A stdio JSON-RPC server bound to one sync run and PR. Its tools:

| Tool | Profile | What it returns or does |
|---|---|---|
| `subject` | both | the run, the PR, the stage that stopped, its refusal, the revisions |
| `pr_diff` | both | the PR's own change, paginated |
| `upstream_diff` | both | what upstream changed in one path between the old and the new base |
| `file_at` / `list_files` | both | a file, or a directory listing, at a named revision |
| `log_excerpt` | both | lines of a stage log of this run |
| `rules` / `findings` | both | the project's rules; recorded findings |
| `propose_patch` | escalation | commits a diff on the proposal ref `refs/heads/sync/<run>/proposal/<branch>`; nothing is pushed |
| `verify` | escalation | sharukhan's checks on the proposal |
| `propose_description` | escalation | writes `PUBLISH/<n>.proposed`, linted |

Results are redacted (keys and tokens) and paginated.

---

[← sharukhan overview](../../README.md)
