# AGENT

The SPAGAT-Librarian AI agent turns a plain-language operator gesture
into a small, auditable action against the local host. It does one
thing well:

> Read the gesture, pick the right skill(s), draft an LLM prompt, show
> the result, and only then — with the operator's consent — run the
> concrete command.

Everything the agent does happens inside a single `spagat-librarian`
process on the operator's own machine. There is no remote coordinator,
no scheduler pushing tasks in, and no persistent daemon. The agent
exits when the TUI is closed or when the `ai` subcommand returns.

## What the agent understands

An **operator gesture** is a natural-language sentence the operator
types into the TUI's AI panel or passes to `spagat-librarian ai
"..."`. Examples:

- "Summarise disk-usage growth over the last week."
- "Why did the `sshd` service restart in the last hour?"
- "Which package brought in the latest openssl update?"
- "Draft a firewall rule that lets port 8080 through only from 10.0.0.0/8."

The agent parses the gesture, matches it against the skill index (see
[SKILLS.md](SKILLS.md)), loads one or two relevant skills into the LLM
prompt, and returns either an answer or a proposed command.

## The five autonomy tiers

The agent runs at one of five autonomy tiers, controlled by
`SPAGAT_AGENT_AUTONOMY` or `[agent] autonomy = "..."` in the config
file. Every tier above `observe` prompts the operator before executing
a write.

| Tier         | Reads                    | Writes                       |
| ------------ | ------------------------ | ---------------------------- |
| `none`       | (LLM only, no tools)     | never                        |
| `observe`    | anywhere readable        | never                        |
| `workspace`  | anywhere readable        | inside `$PWD`, on prompt     |
| `home`       | anywhere readable        | inside `$HOME`, on prompt    |
| `full`       | anywhere readable        | anywhere the user has access, on prompt |

`observe` is the default. In `observe`, the agent will happily read
files, tail logs, and run `git status`, but any command it drafts that
would write to the filesystem or the network is shown as a suggestion
only.

Output is sandboxed and sanitised before being echoed back to the TUI:
API keys, SSH fingerprints, and obvious credential shapes are redacted
so a screen recording or a session log does not leak them.

## Three worked examples

### Example 1 — "summarise disk usage growth"

Gesture:

```
> summarise disk usage growth over the last 7 days for /var
```

What the agent does:

1. Matches the `logs` and `performance` skills.
2. Runs a read-only tool call: `du -sh /var` and `df -h /var`.
3. Reads `/var/log/journal` window sizes as a rough growth proxy.
4. Composes an LLM prompt: system context + the two skill files + the
   collected numbers.
5. Prints a two-paragraph human summary. Under `observe`, that is it —
   nothing is written or changed.

### Example 2 — "why did service X restart"

Gesture:

```
> why did the docker service restart in the last hour?
```

What the agent does:

1. Matches the `systemctl` and `logs` skills.
2. Runs `systemctl status docker` and
   `journalctl -u docker --since "1 hour ago" --no-pager`.
3. Feeds both outputs and the two skill files into the LLM.
4. Prints a diagnosis: what triggered the restart, whether it was
   clean, and one suggested follow-up. Follow-ups that would *change*
   the system (for example "run `systemctl reset-failed docker`") are
   shown as suggested commands, not executed, unless the autonomy tier
   is `workspace` or higher and the operator confirms.

### Example 3 — "draft a firewall rule"

Gesture:

```
> draft an iptables rule that lets port 8080 through only from 10.0.0.0/8
```

What the agent does:

1. Matches the `iptables` skill.
2. Reads the current `iptables -L -n -v` output (read-only, allowed at
   `observe`).
3. Drafts the exact rule as a fenced code block:

   ```
   iptables -A INPUT -p tcp --dport 8080 -s 10.0.0.0/8 -j ACCEPT
   iptables -A INPUT -p tcp --dport 8080 -j DROP
   ```

4. Shows the diff between the current chain and the proposed chain.
5. **Never** runs the rule at `observe` — the operator copies it out
   and runs it by hand. At higher tiers, the agent asks for
   confirmation and then executes.

## The five safety invariants

1. **Consent before write.** The agent never modifies the filesystem
   or the network unless the autonomy tier is above `observe` **and**
   the operator answers `y` to a confirmation prompt for that specific
   command.
2. **Least-authority path filter.** At `workspace`, writes outside
   `$PWD` are rejected before the command runs. At `home`, writes
   outside `$HOME` are rejected.
3. **Output sanitisation.** Every LLM output pass is filtered for API
   keys, SSH fingerprints, and password patterns; matches are replaced
   with `[REDACTED]` in the TUI and the journal.
4. **Journal every action.** Every gesture, every command the agent
   proposes, and every command actually executed is written to
   `$XDG_STATE_HOME/spagat/logs/spagat.log`. The journal self-rotates
   at ~2 MB with three retained files.
5. **No remote coordinator.** The agent has no channel back to any
   fleet manager, scheduler, or upstream server. Its only outbound
   traffic is to whichever LLM you configured (or none, if you use
   `llama.cpp` locally).

## Turning the agent off

If you only want the kanban board and not the AI parts:

```toml
[llm]
mode = "off"

[agent]
autonomy = "none"
```

The TUI and CLI work exactly as before; the AI panel is hidden.
