#!/bin/bash

# Installer script for variois coding AI agents

echo Installing FactoryAI Droid CLI ...
# https://docs.factory.ai/cli/getting-started/overview
cd $HOME
curl -fsSL https://app.factory.ai/cli | sh
echo Installation finished. Start droid with `.local/bin/droid`.

echo Installing OpenAI Codex CLI ...
# https://developers.openai.com/codex/cli/
npm install -g @openai/codex
echo Installation finished. Start Codex CLI with `codex`.

echo Installing Grok-CLI ...
# https://github.com/superagent-ai/grok-cli
npm install -g @vibe-kit/grok-cli
echo Installation finished. Start Grok CLI with `grok`.

echo Installing Coderabbit CLI ...
# https://www.coderabbit.ai/cli
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
echo Installation finished. Start Coderabbit CLI with `coderabbit`.

echo Installing Google Gemini CLI ...
# https://github.com/google-gemini/gemini-cli
npm install -g @google/gemini-cli
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
echo Installation finished. Start Gemini CLI with `gemini`.

echo Installing Anthropic Claude Code ...
# https://github.com/anthropics/claude-code
npm install -g @anthropic-ai/claude-code
echo Installation finished. Start Claude Code with `claude`.

echo Installing Microsoft Copilot CLI ...
# https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli
cd $HOME
npm install -g @github/copilot
echo Installation finished. Start Copilot CLI with `copilot`.

echo Installing Cursor CLI ...
# https://cursor.com/cli
curl https://cursor.com/install -fsS | bash
echo Installation finished. Start Cursor CLI with `.local/bin/cursor-agent`.

echo Installing Ampcode CLI ...
# https://ampcode.com/manual
curl -fsSL https://ampcode.com/install.sh | bash
echo Installation finished. Start Ampcode CLI with `.local/bin/amp`.

echo Installing OpenCode CLI ...
# https://opencode.ai/
# https://martinfowler.com/articles/build-own-coding-agent.html#TheWaveOfCliCodingAgents
curl -fsSL https://opencode.ai/install | bash
echo Installation finished. Start OpenCode CLI with `.opencode/bin/opencode`.

echo Installing AllHands CLI ...
# https://docs.all-hands.dev/usage/how-to/cli-mode
# ISSUE: _hashlib.UnsupportedDigestmodError: [digital envelope routines] unsupported
wget -qO- https://astral.sh/uv/install.sh | sh
.local/bin/uvx --python 3.12 --from openhands-ai openhands
echo Installation finished.

echo Installing Eigent Multi-Agent ...
# https://www.eigent.ai/
# ISSUE: ValueError: [digital envelope routines] unsupported
git clone https://github.com/eigent-ai/eigent.git
cd eigent
npm install
npm run dev
echo Installation finished.

# Common Terminal UI
# https://github.com/sst/opentui

# Research Paper to AI agents with MCP
# https://github.com/jmiao24/Paper2Agent

echo Installing n8n workflow tool ... 
# https://docs.n8n.io/
npm install n8n -g
iptables -A INPUT -p tcp --dport 5678 -j ACCEPT
export N8N_USER_FOLDER=$HOME/n8n
export N8N_SECURE_COOKIE=false
export N8N_DIAGNOSTICS_ENABLED=false
export N8N_VERSION_NOTIFICATIONS_ENABLED=false
export N8N_TEMPLATES_ENABLED=false
export EXTERNAL_FRONTEND_HOOKS_URLS=
export N8N_DIAGNOSTICS_CONFIG_FRONTEND=
export N8N_DIAGNOSTICS_CONFIG_BACKEND=
export GENERIC_TIMEZONE=Europe/Zurich
export NODE_FUNCTION_ALLOW_BUILTIN=*
echo Installation finished. Start n8n workflow tool with `n8n start`.

echo Installing Microsoft Cloudfoundry CLI ...
# https://github.com/cloudfoundry/cli/wiki/V8-CLI-Installation-Guide
# ...first configure the Cloud Foundry Foundation package repository
wget -O /etc/yum.repos.d/cloudfoundry-cli.repo https://packages.cloudfoundry.org/fedora/cloudfoundry-cli.repo
# ...then, install the cf CLI (which will also download and add the public key to your system)
yum install cf8-cli
cf add-plugin-repo CF-Community https://plugins.cloudfoundry.org
cf install-plugin multiapps -f
cf repo-plugins
echo Installation finished.

echo Installing Windsurf ...
# https://windsurf.com/download/editor?os=linux
# ISSUE: 1. nothing provides libxkbfile.so.1()(64bit) needed by windsurf-1.12.12-1759154290.el8.x86_64
tdnf install -y libxkbcommon
rpm --import https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/yum/RPM-GPG-KEY-windsurf
echo -e "[windsurf]
name=Windsurf Repository
baseurl=https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/yum/repo/
enabled=1
autorefresh=1
gpgcheck=1
gpgkey=https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/yum/RPM-GPG-KEY-windsurf" | sudo tee /etc/yum.repos.d/windsurf.repo > /dev/null
yum install -y windsurf
echo Installation finished. 
