To create a self-hosted copy of https://vmware.github.io/photon, you can use `installer.sh` in this repository.
1. Create a vm with 8gb ram, 2vcpu, 20gb disk.
2. copy installer.sh to the vm
3. run
   ```
   chmod a+x ./installer.sh
   ./installer.sh
   ```

### CodingAI installer
Install locally the following CodingAI tools:
FactoryAI Droid CLI, OpenAI Codex CLI, Grok-CLI, Coderabbit CLI, Google Gemini CLI, Anthropic Claude Code, Microsoft Copilot CLI, Cursor CLI, Ampcode CLI,  OpenCode CLI, AllHands CLI, Eigent Multi-Agent.
It also installs a n8n Workflow instance, Microsoft Cloudfoundry CLI and Windsurf.
1. copy CodingAI-installer.sh to the vm
2. run
   ```
   chmod a+x ./CodingAI-installer.sh
   ./CodingAI-installer.sh
   ```

### Ollama installer
Install Ollama locally with open-source models: llama3.1, qwen2.5, mistral, gemma2, ph3
1. run
   ```
   chmod a+x ./Ollama-installer.sh
   ./Ollama-installer.sh
   ```

### Sound configuration
Installs and configures, lobogg, lame, libvorbis, flac, libmad, mpg123, sox, portaudio, sonic, pcaudiolib, and mbrola with various voices for espeak-ng.
1. run
   ```
   chmod a+x ./configuresound.sh
   ./configuresound.sh
   ```
