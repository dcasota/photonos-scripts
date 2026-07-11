# CONFIGURATION

SPAGAT-Librarian follows the XDG Base Directory spec. Configuration lives
under `$XDG_CONFIG_HOME`, state lives under `$XDG_STATE_HOME`, and every
knob has an environment-variable override for scripting.

## File layout

| Purpose               | Default path                                                   | Notes                                             |
| --------------------- | -------------------------------------------------------------- | ------------------------------------------------- |
| Config file           | `$XDG_CONFIG_HOME/spagat/config.toml` (`~/.config/spagat/...`) | Optional; every key has an env override           |
| Kanban database       | `$XDG_STATE_HOME/spagat/spagat.db` (`~/.local/state/spagat/...`) | SQLite; override with `SPAGAT_DB`               |
| Journal / logs        | `$XDG_STATE_HOME/spagat/logs/spagat.log`                       | Self-rotating (three files of ~2 MB each)         |
| Custom skill files    | `$XDG_CONFIG_HOME/spagat/skills/*.md`                          | See [SKILLS.md](SKILLS.md)                        |
| Local GGUF models     | Anywhere; you pass the absolute path in the env var            | See "Offline LLM" below                           |
| System skill files    | `/usr/share/spagat/skills/*.md` (from RPM)                     | Read-only; ships the eight defaults               |

None of these paths are hard-coded to `/etc`, `/run`, or `/var` for
appliance state. Everything is per-user.

## config.toml

A minimal `~/.config/spagat/config.toml`:

```toml
[ui]
# ncurses colour scheme: "auto", "dark", or "light".
theme = "auto"

[llm]
# "local"    -> use llama.cpp with the model at local_model_path
# "frontier" -> use a frontier API, key resolved from env vars
# "off"      -> disable the LLM panel entirely
mode = "frontier"

[llm.local]
model_path = "/home/alice/models/llama-3-8b-instruct.Q4_K_M.gguf"
backend    = "llama.cpp"

[agent]
# One of: none | observe | workspace | home | full
# Default is "observe" — the agent may read but never writes without consent.
autonomy = "observe"
```

Every key in this file can be overridden by an environment variable, and
the file itself is optional — a fresh install with only env vars set
works.

## Environment variables

### Paths

| Variable          | Default                                     | Effect                                    |
| ----------------- | ------------------------------------------- | ----------------------------------------- |
| `SPAGAT_DB`       | `$XDG_STATE_HOME/spagat/spagat.db`          | Override the SQLite kanban store path     |
| `SPAGAT_CONFIG`   | `$XDG_CONFIG_HOME/spagat/config.toml`       | Override the config file location         |
| `SPAGAT_SKILLS_DIR` | `$XDG_CONFIG_HOME/spagat/skills`          | Extra directory searched before the system defaults |
| `SPAGAT_JOURNAL`  | `$XDG_STATE_HOME/spagat/logs/spagat.log`    | Override the journal path                 |

### Local (offline) LLM via llama.cpp

| Variable                        | Example                                              | Effect                                             |
| ------------------------------- | ---------------------------------------------------- | -------------------------------------------------- |
| `SPAGAT_LLM_LOCAL_MODEL_PATH`   | `/home/alice/models/llama-3-8b-instruct.Q4_K_M.gguf` | GGUF model file                                    |
| `SPAGAT_LLM_LOCAL_BACKEND`      | `llama.cpp`                                          | Selects the local backend implementation           |
| `SPAGAT_LLM_LOCAL_CONTEXT_SIZE` | `4096`                                               | Context window (tokens); optional                  |
| `SPAGAT_LLM_LOCAL_THREADS`      | `8`                                                  | CPU threads; optional                              |

### Frontier LLM via env-var keys

Set exactly one of these to use a frontier API. Only one at a time —
SPAGAT-Librarian never merges providers, and it never reads keys from
disk or from any mounted volume.

| Variable                | Provider          |
| ----------------------- | ----------------- |
| `SPAGAT_ANTHROPIC_KEY`  | Anthropic Claude  |
| `SPAGAT_GEMINI_KEY`     | Google Gemini     |
| `SPAGAT_XAI_KEY`        | xAI               |
| `SPAGAT_OPENAI_KEY`     | OpenAI            |

If more than one is set, resolution order is
**Anthropic > Gemini > xAI > OpenAI**, and the binary logs which one it
picked at the first LLM call. To pin a specific provider, unset the
others in your shell profile.

Optional model overrides:

| Variable                     | Example                       |
| ---------------------------- | ----------------------------- |
| `SPAGAT_ANTHROPIC_MODEL`     | `claude-opus-4-7`             |
| `SPAGAT_GEMINI_MODEL`        | `gemini-2.5-pro`              |
| `SPAGAT_XAI_MODEL`           | `grok-4`                      |
| `SPAGAT_OPENAI_MODEL`        | `gpt-4o`                      |

### Agent autonomy

The agent has five autonomy tiers:

| Value        | Effect                                                              |
| ------------ | ------------------------------------------------------------------- |
| `none`       | LLM chat only, no tool use                                          |
| `observe`    | Read-only tools (fs read, git status, system info). **Default.**    |
| `workspace`  | Read + write inside `$PWD` and below                                |
| `home`       | Read + write inside `$HOME`                                         |
| `full`       | Read + write anywhere the invoking user has access                  |

Set with `SPAGAT_AGENT_AUTONOMY=<value>` or `[agent] autonomy = "..."`
in `config.toml`. Every autonomy tier above `observe` prompts the
operator before executing a write. See [AGENT.md](AGENT.md).

## Running as a background service (optional)

If you want to run `spagat-librarian` non-interactively (for example
under a systemd user unit or a container init), it accepts a generic
`--systemd` flag that emits `sd_notify(READY=1)` on start-up. This flag
is optional and completely provider-agnostic — no vendored unit files
ship with the CLI.

## Precedence

Config values resolve in this order (highest wins):

1. Command-line flag
2. Environment variable
3. `config.toml`
4. Compiled-in default
