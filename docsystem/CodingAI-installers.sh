#!/bin/bash

# Installer script for various coding AI agents

# install prerequisites
cd $HOME
tdnf install -y curl git nodejs tar
curl -LsSf https://astral.sh/uv/install.sh | sh
chmod a+x .local/bin/uv
mv .local/bin/uv /usr/local/bin
chmod a+x .local/bin/uvx
mv .local/bin/uvx /usr/local/bin

# echo Configure AI Providers ...
# TODO: your provider’s website to get an API key:
# Ollama: sign-in for Cloud-LLMs
# Anthropic: console.anthropic.com
# Grok: console.x.ai
# OpenRouter: openrouter.ai/keys
# OpenAI: platform.openai.com/api-keys
# Google: aistudio.google.com/apikey
# echo "Installation finished."

# echo Configure NotebookLM CLI ...
# https://github.com/tmc/nlm
# tdnf install -y go build-essential
# TODO browser needed (chromium?)
# go install github.com/tmc/nlm/cmd/nlm@latest


echo Installing SnykCLI ...
# https://docs.snyk.io/developer-tools/snyk-cli/install-or-update-the-snyk-cli
curl --compressed https://downloads.snyk.io/cli/stable/snyk-linux -o snyk
chmod +x ./snyk
mv ./snyk /usr/local/bin/
echo "Installation finished. Start SnykCLI with 'snyk'."

echo Installing FactoryAI Droid CLI ...
# https://docs.factory.ai/guides/building/droid-exec-tutorial
# Install Bun
curl -fsSL https://bun.sh/install | bash
# https://docs.factory.ai/cli/getting-started/overview
uv cache clean
curl -fsSL https://app.factory.ai/cli | sh
chmod a+x .local/bin/droid
mv .local/bin/droid /usr/local/bin
echo "Installation finished. Start FactoryAI Droid CLI with 'droid'."

echo Installing OpenAI Codex CLI ...
# https://developers.openai.com/codex/cli/
npm install -g @openai/codex
echo "Installation finished. Start Codex CLI with 'codex'."

echo Installing Grok-CLI ...
# https://github.com/superagent-ai/grok-cli
git clone https://github.com/superagent-ai/grok-cli
cd grok-cli
npm install
npm run build
npm link
npm audit --force
cd ..
echo "Installation finished. Start Grok CLI with 'grok'."

echo Installing Coderabbit CLI ...
# https://www.coderabbit.ai/cli
tdnf install -y unzip
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
mv .local/bin/coderabbit /usr/local/bin
echo "Installation finished. Start Coderabbit CLI with 'coderabbit --cwd'."

echo Installing Google Gemini CLI ...
tdnf install -y nodejs
# https://github.com/google-gemini/gemini-cli
npm install -g @google/gemini-cli
echo "Installation finished. Start Gemini CLI with 'gemini'."

echo Installing Anthropic Claude Code ...
# https://github.com/anthropics/claude-code
rm -rf /usr/lib/node_modules/@anthropic-ai/claude-code
npm install -g @anthropic-ai/claude-code
echo "Installation finished. Start Claude Code with 'claude'."

echo Installing Microsoft Copilot CLI ...
# https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli
npm install -g @github/copilot
echo "Installation finished. Start Copilot CLI with 'copilot'."

echo Installing Cursor CLI ...
# https://cursor.com/cli
tdnf install -y tar
curl -fsSL https://cursor.com/install | bash
chmod a+x .local/bin/cursor-agent
mv .local/bin/cursor-agent /usr/local/bin
echo "Installation finished. Start Cursor CLI with 'cursor-agent'."

echo Installing Ampcode CLI ...
# https://ampcode.com/manual
curl -fsSL https://ampcode.com/install.sh | bash
chmod a+x .local/bin/amp
mv .local/bin/amp /usr/local/bin
echo "Installation finished. Start Ampcode CLI with 'amp'."

echo Installing OpenCode CLI ...
# https://opencode.ai/
# https://martinfowler.com/articles/build-own-coding-agent.html#TheWaveOfCliCodingAgents
curl -fsSL https://opencode.ai/install | bash
chmod a+x .opencode/bin/opencode
mv .opencode/bin/opencode /usr/local/bin
echo "Installation finished. Start OpenCode CLI with 'opencode'."

# echo Installing Openhands CLI ...
# https://docs.all-hands.dev/usage/how-to/cli-mode
# ISSUE: Failed to build `func-timeout==4.3.5`
# uv cache clean
# uvx --python 3.12 openhands serve
# echo "Installation finished. Start Openhands CLI with 'openhands'."

echo Installing KiloCode CLI ...
# https://kilocode.ai/docs/cli
npm install -g @kilocode/cli
echo "Installation finished. Start KiloCode CLI with 'kilocode'."

echo Installing Cline CLI ...
# https://docs.cline.bot/
npm install -g cline
echo "Installation finished. Start Cline CLI with 'cline'."


# echo Installing Eigent Multi-Agent ...
# https://www.eigent.ai/
# ISSUE: This cli has poor safety.
# npm warn deprecated inflight@1.0.6: This module is not supported, and leaks memory. Do not use it. Check out lru-cache if you want a good and tested way to coalesce async requests by a key value, which is much more comprehensive and powerful.
# npm warn deprecated lodash.isequal@4.5.0: This package is deprecated. Use require('node:util').isDeepStrictEqual instead.
# npm warn deprecated boolean@3.2.0: Package no longer supported. Contact Support at https://www.npmjs.com/support for more info.
# npm warn deprecated @simplewebauthn/types@11.0.0: Package no longer supported. Contact Support at https://www.npmjs.com/support for more info.
# npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported
# npm warn deprecated rimraf@2.7.1: Rimraf versions prior to v4 are no longer supported
# npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported
# npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported
# npm warn deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported
# npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported
# npm warn deprecated source-map@0.8.0-beta.0: The work that was done in this beta branch won't be included in future versions

# git clone https://github.com/eigent-ai/eigent.git
# cd eigent
# npm install
# npm run dev
# echo Installation finished.
# read -p "Press a key to continue ..."


# Common Terminal UI
# https://github.com/sst/opentui

# Research Paper to AI agents with MCP
# https://github.com/jmiao24/Paper2Agent

echo Installing n8n workflow tool ... 
# https://docs.n8n.io/

PID=$(ps -ef | grep "[/]usr/bin/n8n start" | awk '{print $2}'); [ -n "$PID" ] && kill $PID || echo "No running n8n found."

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
nohup n8n start >/dev/null 2>&1 &
echo "Installation finished. n8n workflow tool has been started in the background."

echo Installing Microsoft Cloudfoundry CLI ...
# https://github.com/cloudfoundry/cli/wiki/V8-CLI-Installation-Guide
# ...first configure the Cloud Foundry Foundation package repository
curl -J -L -O https://packages.cloudfoundry.org/fedora/cloudfoundry-cli.repo
mv ./cloudfoundry-cli.repo /etc/yum.repos.d/cloudfoundry-cli.repo 
# ...then, install the cf CLI (which will also download and add the public key to your system)
yum install -y cf8-cli
cf add-plugin-repo CF-Community https://plugins.cloudfoundry.org
cf install-plugin multiapps -f
cf repo-plugins
echo Installation finished.


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
# tdnf install -y libxkbcommon
# git clone git clone https://git.launchpad.net/ubuntu/+source/libxkbfile
# cd libxkbfile
# tdnf install -y build-essential m4 util-macros libx11-devel
# ./configure
# chmod a+x ./autogen.sh
# ./autogen.sh
# make
# make install
# ---
# yum install -y windsurf
yum install -y windsurf --nodeps --downloadonly
rpm -ivh --nodeps /var/cache/tdnf/windsurf/rpms/Windsurf-*.rpm
rm -f /etc/yum.repos.d/windsurf.repo
mkdir $HOME/sandbox
tdnf install -y atk-devel at-spi2-core-devel cups-devel cairo-devel gtk3-devel mesa-libgbm-devel
windsurf --user-data-dir=$HOME/sandbox
# windsurf is installed, however for the web daemon, x11 is missing.
echo Installation finished. 
