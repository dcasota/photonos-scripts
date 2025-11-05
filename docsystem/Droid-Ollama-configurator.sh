#!/bin/bash

# Script to configure FactoryAI Droid CLI to use all installed Ollama LLMs.
# Assumes:
# - Ollama is installed and models are pulled (use `ollama list` to check).
# - Droid CLI is installed.

# Set defaults
CONFIG_FILE="$HOME/.factory/config.json"
BASE_URL="http://localhost:11434/v1"
API_KEY="placeholder"  # Any non-empty value
PROVIDER="generic-chat-completion-api"
DEFAULT_MAX_TOKENS=8192  # Fallback if num_ctx not found in modelfile

tdnf install -y jq

# Test Ollama API
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "Ollama API is accessible."
else
    echo "Error: Ollama API not responding. Ensure server is running."
    exit 1
fi

# Get list of installed models (skip header, take NAME column)
MODELS=$(ollama list | tail -n +2 | awk '{print $1}')

if [ -z "$MODELS" ]; then
    echo "No Ollama models installed. Pull some first (e.g., ollama pull llama3)."
    exit 1
fi

# Create or initialize config.json if not exists
mkdir -p "$HOME/.factory"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating new config file: $CONFIG_FILE"
    echo '{"custom_models": []}' > "$CONFIG_FILE"
fi

# Function to get max_tokens from modelfile (parse num_ctx if present)
get_max_tokens() {
    local model=$1
    local modelfile=$(ollama show "$model" --modelfile 2>/dev/null)
    local num_ctx=$(echo "$modelfile" | grep -i '^PARAMETER num_ctx' | awk '{print $3}')
    if [ -n "$num_ctx" ]; then
        echo "$num_ctx"
    else
        echo "$DEFAULT_MAX_TOKENS"
    fi
}

# Loop over models and add if not already in config
for MODEL_NAME in $MODELS; do
    # Generate display name (e.g., "Ollama llama3:latest")
    MODEL_DISPLAY_NAME="Ollama ${MODEL_NAME}"
    
    # Get model-specific max_tokens
    MAX_TOKENS=$(get_max_tokens "$MODEL_NAME")
    
    # Check if model already exists in config (by model name)
    if jq --arg model "$MODEL_NAME" '.custom_models[] | select(.model == $model)' "$CONFIG_FILE" | grep -q .; then
        echo "Skipping $MODEL_NAME: Already in config."
        continue
    fi
    
    # Add to custom_models array
    jq --arg mdn "$MODEL_DISPLAY_NAME" \
       --arg model "$MODEL_NAME" \
       --arg url "$BASE_URL" \
       --arg key "$API_KEY" \
       --arg prov "$PROVIDER" \
       --argjson mt "$MAX_TOKENS" \
       '.custom_models += [{"model_display_name": $mdn, "model": $model, "base_url": $url, "api_key": $key, "provider": $prov, "max_tokens": $mt}]' \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo "Added $MODEL_NAME to config with max_tokens=$MAX_TOKENS."
done

echo "Config updated. All installed Ollama models added to $CONFIG_FILE."

# Check if MCP filesystem is already configured
if droid mcp list | grep -q "filesystem"; then
    echo "MCP filesystem already configured, skipping addition."
else
    # Configure Droid CLI with MCP access to local filesystem
    droid mcp add filesystem npx @modelcontextprotocol/server-filesystem /
fi

# Run Droid CLI
echo "For the onboarding go to https://factory.ai/. Be prepared with an email address and a mobile phone number."
echo "Start Droid CLI with 'droid'. Use /model to select an Ollama model."