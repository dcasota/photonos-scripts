#!/bin/bash

# Installer script for Ollama with specific version, top 5 LLMs, and dynamic config generation

# Usage: ./install_ollama.sh [ollama_version] [config_file_path]
# Default version: v0.12.9
# Default config path: ./ollama_config.json

OLLAMA_VERSION=${1:-v0.12.11}
CONFIG_FILE=${2:-./ollama_config.json}

# Top 5 popular Ollama models (based on 2025 popularity from sources)
# for 8GB VRAM
# Model id, name, context_window, default_max_tokens
MODELS=(
  "embeddinggemma:300m|embeddinggemma 300m|2048|2048"  
)
# MODELS=(
#   "llama3.1:8b|Llama 3.1 8B|128000|8192"
#   "qwen2.5:7b|Qwen 2.5 7B|131072|8192"
#   "mistral:7b|Mistral 7B|32768|4096"
#   "gemma3:4b|Gemma 4 4B|8192|4096"
#   "embeddinggemma:300m|embeddinggemma 300m|2048|2048"  
#   "phi3:3.8b|Phi 3 Mini 3.8B|128000|4096"
# )

echo "Installing Ollama version $OLLAMA_VERSION..."

# Install Ollama with specific version
OLLAMA_VERSION=$OLLAMA_VERSION curl -fsSL https://ollama.com/install.sh | sh

# Check if Ollama is running; start with context if not
if ! pgrep -f "ollama serve" > /dev/null; then
    echo "Starting Ollama server with 32K context..."
    OLLAMA_CONTEXT_LENGTH=32000 ollama serve &
fi

# Wait for Ollama API to become available (up to 30 seconds)
echo "Waiting for Ollama API to start..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "Ollama API is accessible."
        break
    fi
    sleep 1
done

# If still not responding after wait, exit with error
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "Error: Ollama API not responding after waiting. Ensure server is running."
    exit 1
fi

# Pull the models
for model_entry in "${MODELS[@]}"; do
  model_id=$(echo "$model_entry" | cut -d'|' -f1)
  echo "Pulling model: $model_id"
  ollama pull "$model_id"
done

# Dynamically generate the config JSON
echo "Generating configuration file at $CONFIG_FILE..."

# Start JSON
cat << EOF > "$CONFIG_FILE"
{
  "providers": {
    "ollama": {
      "name": "Ollama",
      "base_url": "http://localhost:11434/v1/",
      "type": "openai",
      "models": [
EOF

# Add models to array
first=true
for model_entry in "${MODELS[@]}"; do
  if [ "$first" = false ]; then
    echo "," >> "$CONFIG_FILE"
  fi
  model_id=$(echo "$model_entry" | cut -d'|' -f1)
  model_name=$(echo "$model_entry" | cut -d'|' -f2)
  context_window=$(echo "$model_entry" | cut -d'|' -f3)
  default_max_tokens=$(echo "$model_entry" | cut -d'|' -f4)
  
  cat << EOF >> "$CONFIG_FILE"
        {
          "name": "$model_name",
          "id": "$model_id",
          "context_window": $context_window,
          "default_max_tokens": $default_max_tokens
        }
EOF
  first=false
done

# Close JSON
cat << EOF >> "$CONFIG_FILE"
      ]
    }
  }
}
EOF

echo "Installation and configuration complete!"

echo "Config file generated: $CONFIG_FILE"
