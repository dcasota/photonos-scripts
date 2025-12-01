# CodingAI-installers.sh User Manual

## Overview

`CodingAI-installers.sh` is a comprehensive installer script for setting up various AI-powered coding assistants and development tools on Photon OS. The script automates the installation of multiple CLI-based AI coding agents and related tools.

## Prerequisites

The script automatically installs the following prerequisites:
- `curl`
- `git`
- `nodejs`
- `tar`
- `uv` (Python package manager from Astral)

## Installed Tools

### Security Tools

| Tool | Command | Documentation |
|------|---------|---------------|
| **Snyk CLI** | `snyk` | https://docs.snyk.io/developer-tools/snyk-cli/install-or-update-the-snyk-cli |

### AI Coding Assistants

| Tool | Command | Documentation |
|------|---------|---------------|
| **Factory AI Droid CLI** | `droid` | https://docs.factory.ai/guides/building/droid-exec-tutorial |
| **OpenAI Codex CLI** | `codex` | https://developers.openai.com/codex/cli/ |
| **Grok CLI** | `grok` | https://github.com/superagent-ai/grok-cli |
| **Coderabbit CLI** | `coderabbit --cwd` | https://www.coderabbit.ai/cli |
| **Google Gemini CLI** | `gemini` | https://github.com/google-gemini/gemini-cli |
| **Anthropic Claude Code** | `claude` | https://github.com/anthropics/claude-code |
| **Microsoft Copilot CLI** | `copilot` | https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli |
| **Cursor CLI** | `cursor-agent` | https://cursor.com/cli |
| **Ampcode CLI** | `amp` | https://ampcode.com/manual |
| **OpenCode CLI** | `opencode` | https://opencode.ai/ |
| **KiloCode CLI** | `kilocode` | https://kilocode.ai/docs/cli |
| **Cline CLI** | `cline` | https://docs.cline.bot/ |
| **Windsurf** | `windsurf` | https://windsurf.com/download/editor?os=linux |

### Workflow & DevOps Tools

| Tool | Command | Documentation |
|------|---------|---------------|
| **n8n Workflow Tool** | Browser: `http://localhost:5678` | https://docs.n8n.io/ |
| **Cloud Foundry CLI** | `cf` | https://github.com/cloudfoundry/cli/wiki/V8-CLI-Installation-Guide |

## Usage

### Running the Installer

```bash
chmod +x CodingAI-installers.sh
./CodingAI-installers.sh
```

### Post-Installation

After running the installer, you may need to:

1. **Source your bash profile** to apply environment changes:
   ```bash
   source ~/.bashrc
   ```

2. **Configure API keys** for the various AI providers:
   - **Anthropic**: https://console.anthropic.com
   - **OpenAI**: https://platform.openai.com/api-keys
   - **Google**: https://aistudio.google.com/apikey
   - **Grok (xAI)**: https://console.x.ai
   - **OpenRouter**: https://openrouter.ai/keys

## n8n Configuration

The script configures n8n with the following environment variables in `~/.bashrc`:

| Variable | Value | Description |
|----------|-------|-------------|
| `N8N_USER_FOLDER` | `$HOME/n8n` | User data folder |
| `N8N_SECURE_COOKIE` | `false` | Disable secure cookies (dev mode) |
| `N8N_DIAGNOSTICS_ENABLED` | `false` | Disable diagnostics |
| `N8N_VERSION_NOTIFICATIONS_ENABLED` | `false` | Disable version notifications |
| `N8N_TEMPLATES_ENABLED` | `false` | Disable templates |
| `GENERIC_TIMEZONE` | `Europe/Zurich` | Default timezone |
| `NODE_FUNCTION_ALLOW_BUILTIN` | `*` | Allow all Node.js built-in modules |

n8n is started automatically in the background on port 5678.

## Commented/Disabled Installations

The following tools are commented out in the script due to known issues:

| Tool | Issue |
|------|-------|
| **NotebookLM CLI** | Requires browser (Chromium) |
| **Openhands CLI** | Build failure with `func-timeout==4.3.5` |
| **Eigent Multi-Agent** | Poor safety; deprecated dependencies |
| **Warp CLI** | Requires API key configuration |

## Known Issues

### Windsurf
- Installed with `--nodeps` flag due to missing `libxkbfile.so.1` dependency
- X11 is required for the web daemon but may be missing on headless systems
- Uses a sandbox directory at `$HOME/sandbox`

### Grok CLI
- Built from source; may require `npm audit --force` to resolve security warnings

## File Locations

| Component | Location |
|-----------|----------|
| CLI binaries | `/usr/local/bin/` |
| n8n user data | `$HOME/n8n` |
| Windsurf sandbox | `$HOME/sandbox` |
| Cloud Foundry repo | `/etc/yum.repos.d/cloudfoundry-cli.repo` |

## Firewall Configuration

The script opens port 5678 for n8n:
```bash
iptables -A INPUT -p tcp --dport 5678 -j ACCEPT
iptables-save >/etc/systemd/scripts/ip4save
```

## Uninstallation

To uninstall individual tools:

```bash
# npm-based tools
npm uninstall -g @openai/codex
npm uninstall -g @google/gemini-cli
npm uninstall -g @anthropic-ai/claude-code
npm uninstall -g @github/copilot
npm uninstall -g @kilocode/cli
npm uninstall -g cline
npm uninstall -g n8n

# Binary tools
rm /usr/local/bin/snyk
rm /usr/local/bin/droid
rm /usr/local/bin/coderabbit
rm /usr/local/bin/cursor-agent
rm /usr/local/bin/amp
rm /usr/local/bin/opencode

# Grok CLI
rm -rf ~/grok-cli
npm unlink grok

# Cloud Foundry
yum remove cf8-cli
rm /etc/yum.repos.d/cloudfoundry-cli.repo

# Windsurf
rpm -e windsurf
```


