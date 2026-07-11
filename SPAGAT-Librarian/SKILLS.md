# SKILLS

The skill panel is a library of short, LLM-consumable Markdown files that
teach the agent how to drive one Linux subsystem. Each file is a plain
`.md` document — no runtime, no plug-in ABI, no code. The agent loads
the file into its prompt, uses the commands and notes as a cheat sheet,
and asks the LLM to produce a concrete command or explanation.

## The eight built-in skills

Every install ships with eight sysadmin skill files under
`/usr/share/spagat/skills/` (or the source-tree `skills/` directory in
a native build):

| Skill         | Covers                                                      |
| ------------- | ----------------------------------------------------------- |
| `tdnf`        | Photon OS package manager (Tiny DNF)                        |
| `systemctl`   | systemd service and unit management                         |
| `iptables`    | Firewall rules and packet-filter tables                     |
| `network`     | Interfaces, routes, DNS, `ip(8)` cheatsheet                 |
| `docker`      | Container lifecycle, image queries, log tailing             |
| `logs`        | `journalctl` and file-based log inspection                  |
| `users`       | Users, groups, sudo, passwd, `chage` cadence                |
| `performance` | `top`, `iostat`, `sar`, `dmesg`, quick triage recipes       |

Each file follows the same shape:

```markdown
# <name> - <one-line summary>

<why-you-would-use-it prose>

## Commands
### <verb group>
- <what it does>: `<command>`
...

## Notes
- <caveats, flags, safety>
```

Open one to see it — for example `/usr/share/spagat/skills/tdnf.md`.

## Invoking a skill

There are two ways to run a skill.

### 1. From the TUI

Press `F2` to open the skill picker. Arrow keys navigate; `Enter`
loads the highlighted skill into the current LLM chat context. From
there you type a question in plain language and the LLM answers using
that skill's cheat sheet.

Or, at the TUI prompt, type the colon-command directly:

```
:skill tdnf
```

### 2. From the shell (non-interactive)

```bash
spagat-librarian ai --skill tdnf "how do I upgrade only kernel packages?"
```

The output is written to stdout; no state is changed unless the agent
autonomy tier is above `observe` and the operator confirms the write.

## Adding your own skill

Drop a Markdown file into `$XDG_CONFIG_HOME/spagat/skills/`:

```bash
mkdir -p ~/.config/spagat/skills
cat > ~/.config/spagat/skills/postgres.md <<'EOF'
# postgres - PostgreSQL admin

Common PostgreSQL admin recipes for a single-node install.

## Commands
### Connect
- Local, as superuser: `sudo -u postgres psql`
- With a DSN: `psql "postgresql://user:pass@host:5432/dbname"`

### Inspect
- List databases: `\l`
- List tables:    `\dt`
- Explain plan:   `EXPLAIN ANALYZE <sql>;`

## Notes
- Config: /etc/postgresql/16/main/postgresql.conf
- Logs:   /var/log/postgresql/
EOF
```

Restart the TUI (or re-open the skill picker) and `postgres` appears in
the list. Files in `$XDG_CONFIG_HOME/spagat/skills/` shadow files with
the same name in `/usr/share/spagat/skills/`, so you can override a
built-in skill with a local edit without touching the system copy.

## Search order

1. `$SPAGAT_SKILLS_DIR` (if set)
2. `$XDG_CONFIG_HOME/spagat/skills/`
3. `/usr/share/spagat/skills/`

The first match by base filename wins.

## What a skill file may contain

- Prose paragraphs (loaded verbatim into the LLM context).
- Bulleted or numbered lists of commands.
- Fenced code blocks (bash, sql, toml, etc.).
- Local file-path hints ("Config: `/etc/foo`").

What a skill file must **not** contain:

- Executable code that the console runs directly. Skills are context
  documents; only the agent, via the LLM, ever synthesises a command
  to run — and only when the autonomy tier permits it.
- Secrets, keys, or credentials of any kind. Skills go into the LLM
  prompt; assume that anything in a skill is visible to the LLM
  provider.
