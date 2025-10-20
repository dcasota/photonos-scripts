To create a self-hosted copy of https://vmware.github.io/photon, you can use `installer.sh` in this repository.
1. Create a vm with 8gb ram, 2vcpu, 20gb disk.
2. copy installer.sh (and all other scripts to the vm
3. run
   ```
   chmod a+x ./*.sh
   ./installer.sh
   ```

### Docs-Inspector
The script installs docs-inspector daemon. It crawls the local web server and protocols as json files any sort of broken links, markdown issues and english grammar issues.
1. run
   ```
   ./docsinspector.sh
   ```

### CodingAI installer
Install locally the following CodingAI tools:
FactoryAI Droid CLI, OpenAI Codex CLI, Grok-CLI, Coderabbit CLI, Google Gemini CLI, Anthropic Claude Code, Microsoft Copilot CLI, Cursor CLI, Ampcode CLI,  OpenCode CLI, AllHands CLI, Eigent Multi-Agent.
It also installs a n8n Workflow instance, Microsoft Cloudfoundry CLI and Windsurf.
1. run
   ```
   ./CodingAI-installer.sh
   ```

### Ollama installer
Install Ollama locally with open-source models: llama3.1, qwen2.5, mistral, gemma2, ph3
1. run
   ```
   ./Ollama-installer.sh
   ```

### Sound configuration
Installs and configures, lobogg, lame, libvorbis, flac, libmad, mpg123, sox, portaudio, sonic, pcaudiolib, and mbrola with various voices for espeak-ng.
1. run
   ```
   ./configuresound.sh
   ```

### Migrate to Docusaurus
Migrates the Photon OS website to docusaurus.
1. run
   ```
   ./migrate2docusaurus.sh
   ```
