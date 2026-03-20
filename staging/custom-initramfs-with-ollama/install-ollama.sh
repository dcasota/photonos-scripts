#!/bin/bash

# Script to integrate Ollama + TinyLlama into initramfs on Photon OS
# Run as root
# Note: In WSL, the custom initramfs won't be used for booting, as WSL has its own initramfs.
# This script uses --install and --include to add files directly, bypassing custom module issues.

set -e

# Step 1: Install Ollama if not present
if ! command -v ollama &> /dev/null; then
    echo "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama already installed."
fi

# Step 2: Pull TinyLlama model
echo "Pulling TinyLlama model..."
ollama pull tinyllama

# Step 3: Create a temporary run script file
RUN_SCRIPT="/tmp/run_ollama.sh"
cat << EOF > "$RUN_SCRIPT"
#!/bin/sh

# Set environment for Ollama
export OLLAMA_HOME=/root/.ollama
export OLLAMA_MODELS=/root/.ollama/models

# Example: Run a simple inference and output to console
echo "Running Ollama TinyLlama from initramfs..." > /dev/console
/bin/ollama run tinyllama "Hello from initramfs on Photon OS!" > /dev/console

# Add your custom logic here (e.g., AI-based boot decisions)
# For background server: /bin/ollama serve & (but no network in initramfs)
EOF

chmod +x "$RUN_SCRIPT"

# Step 4: Regenerate initramfs with Dracut, using --install and --include
echo "Regenerating initramfs..."
KERNEL_VERSION=$(uname -r)

# Base dracut command
DRACUT_CMD="dracut -f --kver $KERNEL_VERSION"

# Add Ollama binary and auto-deps
DRACUT_CMD="$DRACUT_CMD --install /usr/local/bin/ollama"

# Include model files (recursive include for directories)
# Note: --include copies the source to the target path in initramfs
DRACUT_CMD="$DRACUT_CMD --include $HOME/.ollama /root/.ollama"

# Include the run script in pre-mount hook directory
DRACUT_CMD="$DRACUT_CMD --include $RUN_SCRIPT /lib/dracut/hooks/pre-mount/99-run-ollama.sh"

# Detect if running on WSL and add --no-kernel
if grep -q "microsoft" /proc/version; then
    echo "Detected WSL environment; using --no-kernel switch."
    DRACUT_CMD="$DRACUT_CMD --no-kernel"
else
    echo "Non-WSL environment detected."
fi

# Execute the dracut command
eval $DRACUT_CMD

# Clean up temp file
rm -f "$RUN_SCRIPT"

# Step 5: Update boot loader if needed (Photon OS uses GRUB or systemd-boot; adjust accordingly)
# For GRUB:
if command -v grub-mkconfig &> /dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "Integration complete. Reboot to test (watch console for output)."
echo "If boot fails, restore backup initramfs and reboot."
echo "Note: In WSL, this custom initramfs may not be active during 'boot'. Test Ollama normally with 'ollama run tinyllama'."
