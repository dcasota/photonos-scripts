# Ollama-installer.sh User Manual

## Overview

`Ollama-installer.sh` is an installer script for setting up Ollama with a specific version, pre-configured LLM models, and automatic configuration file generation on Photon OS.

## Usage

```bash
./Ollama-installer.sh [ollama_version] [config_file_path]
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ollama_version` | `v0.12.11` | Ollama version to install |
| `config_file_path` | `./ollama_config.json` | Path for generated config file |

### Examples

```bash
# Install with defaults (v0.12.11, ./ollama_config.json)
./Ollama-installer.sh

# Install specific version
./Ollama-installer.sh v0.12.10

# Install with custom config path
./Ollama-installer.sh v0.12.11 /etc/ollama/config.json
```

## What Gets Installed

### Ollama Server

- Downloaded and installed via official install script
- Automatically started with 32K context length (`OLLAMA_CONTEXT_LENGTH=32000`)
- API accessible at `http://localhost:11434`

### Pre-configured Models

The script installs the following model by default (optimized for 8GB VRAM):

| Model ID | Name | Context Window | Max Tokens |
|----------|------|----------------|------------|
| `embeddinggemma:300m` | embeddinggemma 300m | 2,048 | 2,048 |

### Additional Models (Commented Out)

The script includes commented configurations for larger models:

| Model ID | Name | Context Window | Max Tokens |
|----------|------|----------------|------------|
| `llama3.1:8b` | Llama 3.1 8B | 128,000 | 8,192 |
| `qwen2.5:7b` | Qwen 2.5 7B | 131,072 | 8,192 |
| `mistral:7b` | Mistral 7B | 32,768 | 4,096 |
| `gemma3:4b` | Gemma 4 4B | 8,192 | 4,096 |
| `phi3:3.8b` | Phi 3 Mini 3.8B | 128,000 | 4,096 |

To enable additional models, edit the `MODELS` array in the script.

## Generated Configuration File

The script generates a JSON configuration file compatible with OpenAI-style API clients:

```json
{
  "providers": {
    "ollama": {
      "name": "Ollama",
      "base_url": "http://localhost:11434/v1/",
      "type": "openai",
      "models": [
        {
          "name": "embeddinggemma 300m",
          "id": "embeddinggemma:300m",
          "context_window": 2048,
          "default_max_tokens": 2048
        }
      ]
    }
  }
}
```

## Installation Process

1. **Version Setup** - Configures specified Ollama version
2. **Ollama Installation** - Downloads and installs via official script
3. **Server Start** - Starts Ollama server with 32K context if not running
4. **API Wait** - Waits up to 30 seconds for API availability
5. **Model Pull** - Downloads configured models from Ollama registry
6. **Config Generation** - Creates JSON configuration file

## API Endpoints

After installation, the following endpoints are available:

| Endpoint | Description |
|----------|-------------|
| `http://localhost:11434/api/tags` | List available models |
| `http://localhost:11434/v1/` | OpenAI-compatible API base URL |
| `http://localhost:11434/api/generate` | Native Ollama generation API |
| `http://localhost:11434/api/chat` | Native Ollama chat API |

## Customizing Models

To add or change models, edit the `MODELS` array in the script:

```bash
MODELS=(
  "model_id|Model Name|context_window|max_tokens"
)
```

### Model Entry Format

Each entry uses pipe-delimited fields:
1. **Model ID** - Ollama model identifier (e.g., `llama3.1:8b`)
2. **Model Name** - Human-readable name
3. **Context Window** - Maximum context length in tokens
4. **Default Max Tokens** - Default generation length

## Environment Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `OLLAMA_VERSION` | User-specified or default | Version to install |
| `OLLAMA_CONTEXT_LENGTH` | `32000` | Server context length |

## Troubleshooting

### API Not Responding

If the script exits with "Ollama API not responding":

```bash
# Check if Ollama is running
pgrep -f "ollama serve"

# Manually start Ollama
OLLAMA_CONTEXT_LENGTH=32000 ollama serve &

# Test API
curl http://localhost:11434/api/tags
```

### Model Pull Failures

```bash
# Retry pulling a specific model
ollama pull embeddinggemma:300m

# Check available disk space
df -h
```

### Check Installed Models

```bash
ollama list
```

## Uninstallation

```bash
# Stop Ollama server
pkill -f "ollama serve"

# Remove Ollama binary
sudo rm /usr/local/bin/ollama

# Remove models and data
rm -rf ~/.ollama

# Remove config file
rm ./ollama_config.json
```

## System Requirements

- **Minimum VRAM**: 8GB (for default embedding model)
- **Recommended VRAM**: 16GB+ (for 7B/8B models)
- **Disk Space**: Varies by model (300MB to 8GB per model)
- **Network**: Internet access for model downloads
