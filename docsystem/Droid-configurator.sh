#!/bin/bash

# Script to configure FactoryAI Droid CLI to use all installed Ollama LLMs.
# Assumes:
# - Ollama is installed, running, and models are pulled.
# - Droid CLI is installed.

# Set defaults
CONFIG_FILE="$HOME/.factory/config.json"
BASE_URL="http://localhost:11434/v1/"
PROVIDER="generic-chat-completion-api"

# API Keys
echo "API Keys:"
read -p "Enter your XAI_API_KEY (press enter to skip): " xai_key

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

# Function to get context_length from Ollama API
get_max_tokens() {
    local model=$1
    local info=$(curl -s http://localhost:11434/api/show -d "{\"name\": \"$model\"}")
    local ctx=$(echo "$info" | jq '.details.context_length // 2048')
    echo "$ctx"
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
       --arg key "" \
       --arg prov "$PROVIDER" \
       --argjson mt "$MAX_TOKENS" \
       '.custom_models += [{"model_display_name": $mdn, "model": $model, "base_url": $url, "api_key": $key, "provider": $prov, "max_tokens": $mt}]' \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo "Added $MODEL_NAME to config with max_tokens=$MAX_TOKENS."
done

# Add Grok
if [ -n "$xai_key" ]; then
    GROK_MODEL="grok-code-fast-1"
    GROK_DISPLAY_NAME="Grok Code Fast 1"
    GROK_BASE_URL="https://api.x.ai/v1/"
    GROK_PROVIDER="generic-chat-completion-api"
    GROK_MAX_TOKENS=256000
    
    # Remove existing entry if it exists (to apply updates)
    jq --arg model "$GROK_MODEL" '.custom_models = [.custom_models[] | select(.model != $model)]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    echo "Removed any existing $GROK_MODEL entry to apply updates."
    
    # Add the updated entry
    jq --arg mdn "$GROK_DISPLAY_NAME" \
       --arg model "$GROK_MODEL" \
       --arg url "$GROK_BASE_URL" \
       --arg key "$xai_key" \
       --arg prov "$GROK_PROVIDER" \
       --argjson mt "$GROK_MAX_TOKENS" \
       '.custom_models += [{"model_display_name": $mdn, "model": $model, "base_url": $url, "api_key": $key, "provider": $prov, "max_tokens": $mt}]' \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        
    echo "Added/Updated $GROK_MODEL to config with max_tokens=$GROK_MAX_TOKENS."
fi

echo "Config updated. All installed Ollama models added to $CONFIG_FILE."

# Configure Droid CLI with MCP access to local filesystem if not already configured
add_output=$(droid mcp add filesystem "npx @modelcontextprotocol/server-filesystem /" 2>&1)
if [ $? -eq 0 ]; then
    echo "$add_output"
else
    if echo "$add_output" | grep -q "already exists"; then
        echo "MCP filesystem already configured, skipping addition."
    else
        echo "$add_output"
        exit 1
    fi
fi

# Run Droid CLI
echo "For the onboarding go to https://factory.ai/. Be prepared with an email address and a mobile phone number."
echo "Start Droid CLI with 'droid'. Use /model to select an Ollama model."
