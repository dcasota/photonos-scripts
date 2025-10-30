#!/bin/bash

# Installer script for various coding AI agents
cd $HOME
tdnf install -y curl wget

echo Installing SnykCLI ...
# https://docs.snyk.io/developer-tools/snyk-cli/install-or-update-the-snyk-cli
curl --compressed https://downloads.snyk.io/cli/stable/snyk-linux -o snyk
chmod +x ./snyk
mv ./snyk /usr/local/bin/
echo Installation finished. Start SnykCLI with 'snyk'.
read -p "Press a key to continue ..."

echo Installing FactoryAI Droid CLI ...
# https://docs.factory.ai/cli/getting-started/overview
curl -fsSL https://app.factory.ai/cli | sh
echo 'export PATH=/root/.local/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
echo Installation finished. Start droid with '.local/bin/droid'.
read -p "Press a key to continue ..."

echo Installing OpenAI Codex CLI ...
# https://developers.openai.com/codex/cli/
npm install -g @openai/codex
echo Installation finished. Start Codex CLI with 'codex'.
read -p "Press a key to continue ..."

echo Installing Grok-CLI ...
# https://github.com/superagent-ai/grok-cli
git clone https://github.com/superagent-ai/grok-cli
cd grok-cli
npm install
npm run build
npm link
npm audit --force
cd ..
echo Installation finished. Start Grok CLI with 'grok'.
read -p "Press a key to continue ..."

echo Installing Coderabbit CLI ...
# https://www.coderabbit.ai/cli
tdnf install -y unzip
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
echo Installation finished. Start Coderabbit CLI with 'coderabbit'.
read -p "Press a key to continue ..."

echo Installing Google Gemini CLI ...
# https://github.com/google-gemini/gemini-cli
npm install -g @google/gemini-cli
echo Installation finished. Start Gemini CLI with 'gemini'.
read -p "Press a key to continue ..."

echo Installing Anthropic Claude Code ...
# https://github.com/anthropics/claude-code
rm -rf /usr/lib/node_modules/@anthropic-ai/claude-code
npm install -g @anthropic-ai/claude-code
echo Installation finished. Start Claude Code with 'claude'.
read -p "Press a key to continue ..."

echo Installing Microsoft Copilot CLI ...
# https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli
npm install -g @github/copilot
echo Installation finished. Start Copilot CLI with 'copilot'.
read -p "Press a key to continue ..."

echo Installing Cursor CLI ...
# https://cursor.com/cli
curl https://cursor.com/install -fsS | bash
echo Installation finished. Start Cursor CLI with '.local/bin/cursor-agent'.
read -p "Press a key to continue ..."

echo Installing Ampcode CLI ...
# https://ampcode.com/manual
curl -fsSL https://ampcode.com/install.sh | bash
echo Installation finished. Start Ampcode CLI with '.local/bin/amp'.

echo Installing OpenCode CLI ...
# https://opencode.ai/
# https://martinfowler.com/articles/build-own-coding-agent.html#TheWaveOfCliCodingAgents
curl -fsSL https://opencode.ai/install | bash
echo Installation finished. Start OpenCode CLI with '.opencode/bin/opencode'.
read -p "Press a key to continue ..."

echo Installing AllHands CLI ...
# https://docs.all-hands.dev/usage/how-to/cli-mode
# ISSUE: _hashlib.UnsupportedDigestmodError: [digital envelope routines] unsupported
uv cache clean
rm -r "$(uv python dir)"
rm -r "$(uv tool dir)"
rm ~/.local/bin/uv ~/.local/bin/uvx
wget -qO- https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
echo 'eval "$(uv generate-shell-completion bash)"' >> ~/.bashrc
uvx --python 3.12 --from openhands-ai openhands
echo Installation finished.
read -p "Press a key to continue ..."

echo Installing Eigent Multi-Agent ...
# https://www.eigent.ai/
# ISSUE: ValueError: [digital envelope routines] unsupported
git clone https://github.com/eigent-ai/eigent.git
cd eigent
npm install
npm run dev
echo Installation finished.
read -p "Press a key to continue ..."


# Common Terminal UI
# https://github.com/sst/opentui

# Research Paper to AI agents with MCP
# https://github.com/jmiao24/Paper2Agent

echo Installing n8n workflow tool ... 
# https://docs.n8n.io/
npm install n8n -g
iptables -A INPUT -p tcp --dport 5678 -j ACCEPT
iptables-save >/etc/systemd/scripts/ip4save
# File to modify
BASHRC="$HOME/.bashrc"
# List of lines to add if not present
declare -a lines=(
    'export N8N_USER_FOLDER=$HOME/n8n'
    'export N8N_SECURE_COOKIE=false'
    'export N8N_DIAGNOSTICS_ENABLED=false'
    'export N8N_VERSION_NOTIFICATIONS_ENABLED=false'
    'export N8N_TEMPLATES_ENABLED=false'
    'export EXTERNAL_FRONTEND_HOOKS_URLS='
    'export N8N_DIAGNOSTICS_CONFIG_FRONTEND='
    'export N8N_DIAGNOSTICS_CONFIG_BACKEND='
    'export GENERIC_TIMEZONE=Europe/Zurich'
    'export NODE_FUNCTION_ALLOW_BUILTIN=*'
)
# Loop through each line and add if not already present
for line in "${lines[@]}"; do
    if ! grep -Fxq "$line" "$BASHRC"; then
        echo "$line" >> "$BASHRC"
        echo "Added to .bashrc: $line"
    else
        echo "Already present in .bashrc: $line"
    fi
done
# Apply the exports immediately in the current shell
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
echo Installation finished. Start n8n workflow tool with n8n start.
read -p "Press a key to continue ..."

echo Installing Microsoft Cloudfoundry CLI ...
# https://github.com/cloudfoundry/cli/wiki/V8-CLI-Installation-Guide
# ...first configure the Cloud Foundry Foundation package repository
wget -O /etc/yum.repos.d/cloudfoundry-cli.repo https://packages.cloudfoundry.org/fedora/cloudfoundry-cli.repo
# ...then, install the cf CLI (which will also download and add the public key to your system)
yum install -y cf8-cli
cf add-plugin-repo CF-Community https://plugins.cloudfoundry.org
cf install-plugin multiapps -f
cf repo-plugins
echo Installation finished.
read -p "Press a key to continue ..."

echo Installing Windsurf ...
# https://windsurf.com/download/editor?os=linux
rpm --import https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/yum/RPM-GPG-KEY-windsurf
echo -e "[windsurf]
name=Windsurf Repository
baseurl=https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/yum/repo/
enabled=1
autorefresh=1
gpgcheck=1
gpgkey=https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/yum/RPM-GPG-KEY-windsurf" | sudo tee /etc/yum.repos.d/windsurf.repo > /dev/null
# ---
# ISSUE: 1. nothing provides libxkbfile.so.1()(64bit) needed by windsurf-1.12.12-1759154290.el8.x86_64
tdnf install -y libxkbcommon
git clone git clone https://git.launchpad.net/ubuntu/+source/libxkbfile
cd libxkbfile
tdnf install -y build-essential m4 util-macros libx11-devel
./configure
chmod a+x ./autogen.sh
./autogen.sh
make
make install
# ---
yum install -y windsurf
echo Installation finished. 
