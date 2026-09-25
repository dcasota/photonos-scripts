# LocalGate

Staging prototype: a local Ollama **decision layer** for [Claude Code](https://code.claude.com), following the Jev Engineering split without calling TypeSafe Jev.

- **Writer** stays on Anthropic (Claude Max 20x).
- **Judge** is a local 7B–8B Q4 model on an RTX 4070 laptop GPU (8 GB VRAM).
- **Exact rules** are code: denylist / allowlist in `~/.claude/hooks/local_jev_policy.json`.

This folder is experimental. It is not a Photon OS build script.

## Files

| File | Role |
|------|------|
| [README.md](README.md) | This file |
| [Jev-Engineering-Local-Claude-Code-Guide.md](Jev-Engineering-Local-Claude-Code-Guide.md) | Full playbook (hardware, Max 20x quota, hooks, operations) |
| [stage-local-jev.sh](stage-local-jev.sh) | Linux staging |
| [stage-local-jev.ps1](stage-local-jev.ps1) | Windows PowerShell staging |

The original Word document is the same playbook as the Markdown guide. Git stores the Markdown form so the text stays reviewable.

## What the staging scripts install

On the machine that runs Claude Code:

- Ollama env profile for 8 GB VRAM: one resident model, 4k context, flash attention, keep-alive `-1`
- `~/.claude/hooks/local_jev_gate.py` — `PreToolUse` gate
- `~/.claude/hooks/local_jev_policy.json` — thresholds and regex policy
- `~/.claude/local-jev.settings.json` — hook fragment to merge into Claude Code settings
- `~/.claude/CLAUDE-local-jev.md` — routing snippet for Max 20x
- Fixture: `ls` / `git status` allow; `rm -rf /`, `.env` write, `curl | sh` deny

The scripts **do not** set `ANTHROPIC_BASE_URL` and **do not** store API keys.

## Quick start

### Linux

```bash
chmod +x stage-local-jev.sh
./stage-local-jev.sh
```

### Windows (PowerShell)

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\stage-local-jev.ps1
```

Useful flags:

- Linux: `--model TAG`, `--context N`, `--skip-pull`, `--dry-run`
- Windows: `-Model`, `-Context`, `-SkipPull`, `-DryRun`

Default model: `qwen2.5:7b-instruct`.

Then:

1. Restart Ollama so the new environment variables load.
2. Restart Claude Code and run `/hooks`. Confirm `PreToolUse` points at `local_jev_gate.py`.
3. Optionally append `~/.claude/CLAUDE-local-jev.md` to `CLAUDE.md`.
4. Watch `~/.claude/hooks/local-jev.log`.

## Guardrails (4070 laptop + Max 20x)

- Treat the **laptop 4070 as 8 GB**, not the 12 GB desktop card.
- One model loaded. Do not pull a 14B onto the live hook path.
- Cap judge state at 2 000 characters. Never send the full Claude transcript.
- Hook timeout 3 s, fail **open** on Ollama errors.
- Fail **closed** on the denylist (secrets, recursive deletes, `curl | sh`) before any model call.
- Keep Claude Code on Anthropic. Do not point the writer at Ollama.
- Default writer: Sonnet. Opus/Fable only for hard design work. Mechanical subagents: Haiku.

## After install

Edit `~/.claude/hooks/local_jev_policy.json` to tighten patterns and thresholds. If warm hook p95 exceeds 2 s, restage with `--model llama3.2:3b`.

See the [full guide](Jev-Engineering-Local-Claude-Code-Guide.md) for the work split, Claude-native alternatives, and the daily model profile.
