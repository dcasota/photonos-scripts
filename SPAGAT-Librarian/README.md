# SPAGAT-Librarian CLI

A standalone, terminal-based **kanban + LLM + AI-agent** for sysadmin operations.

SPAGAT-Librarian is a single C binary that gives an operator three tools in one
process:

1. A **6-column kanban board** for tracking day-to-day operational work
   (In Clarification, Won't Fix, In Backlog, In Progress, In Review, Ready)
   with an ncurses TUI and a scriptable CLI over the same SQLite store.
2. A **local or frontier LLM bridge** for on-the-terminal chat, code review,
   log summarisation, and script drafting. Runs fully offline via `llama.cpp`
   with a GGUF model, or against a frontier API (Anthropic, Google Gemini,
   xAI, or OpenAI) when a key is present in the environment.
3. An **AI agent** that reads a natural-language gesture from the operator,
   picks one or more of the pre-loaded sysadmin skill files (tdnf, systemctl,
   iptables, network, docker, logs, users, performance), composes an LLM
   prompt, and presents the result — always in an "observe first, act after
   consent" default posture.

## No appliance required

This CLI is the standalone form of the same v0.3 console that also ships
inside the SpagatLibrarian Appliance. Everything documented under `docs/public/`
runs on a plain Linux host — Photon OS 5.0, Fedora, and Debian are the
verified platforms — with nothing more than `ncurses`, `sqlite3`, and
(optionally) `llama.cpp` on the box. State lives under `$XDG_STATE_HOME`,
configuration lives under `$XDG_CONFIG_HOME`, and frontier LLM keys come
from environment variables. There is no daemon, no container runtime
dependency, and no privileged mount point.

## Quick example

```bash
# 1. Build and install (see INSTALL.md for platform notes).
git clone https://github.com/dcasota/photonos-scripts.git
cd photonos-scripts/SPAGAT-Librarian
make && sudo make install

# 2. Create your first kanban card and open the TUI.
spagat-librarian add "Investigate disk pressure on /var" --priority high
spagat-librarian     # opens the TUI at the board view; F1 for help
```

That is enough to have a working single-user kanban. To turn on the LLM
side, export one of the environment variables in
[CONFIGURATION.md](CONFIGURATION.md) and press `F4` in the TUI, or run
`spagat-librarian ai "your prompt"` from the shell.

## Where to go next

| Topic                                                      | File                               |
| ---------------------------------------------------------- | ---------------------------------- |
| Build from source, install the RPM, per-distro packages    | [INSTALL.md](INSTALL.md)           |
| Config file, environment variables, LLM provider selection | [CONFIGURATION.md](CONFIGURATION.md) |
| The 8 pre-loaded sysadmin skills and how to add your own   | [SKILLS.md](SKILLS.md)             |
| The AI agent: gesture -> skill -> LLM -> action            | [AGENT.md](AGENT.md)               |
| Embedding, C API surface, JSON event input, state override | [INTEGRATION.md](INTEGRATION.md)   |

## License

C source, released under the terms in the repository-root `LICENSE` file.
