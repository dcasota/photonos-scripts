# custom-initramfs-with-ollama

Experimental script to integrate [Ollama](https://ollama.com/) and the [TinyLlama](https://huggingface.co/TinyLlama) model directly into a Photon OS initramfs, enabling AI inference during the early boot phase.

## Overview

`install-ollama.sh` automates the process of embedding Ollama and a pre-pulled TinyLlama model into a custom initramfs image using [Dracut](https://github.com/dracut-ng/dracut-ng). This enables running local LLM inference before the root filesystem is mounted -- a proof-of-concept for AI-assisted boot decisions, diagnostics, or appliance initialization on Photon OS.

## How It Works

The script performs five steps:

1. **Install Ollama** -- Downloads and installs Ollama via the official install script (`curl -fsSL https://ollama.com/install.sh | sh`) if not already present.
2. **Pull TinyLlama model** -- Fetches the TinyLlama model (~637 MB) into `$HOME/.ollama/models/` using `ollama pull tinyllama`.
3. **Create a run script** -- Generates `/tmp/run_ollama.sh`, a shell script that runs a TinyLlama inference and writes output to `/dev/console`. This script is placed in the Dracut `pre-mount` hook directory inside the initramfs.
4. **Regenerate initramfs with Dracut** -- Rebuilds the initramfs for the current kernel, injecting:
   - The Ollama binary (`/usr/local/bin/ollama`) with automatic library dependency resolution via `--install`
   - The entire `$HOME/.ollama` directory (model weights, manifests, config) via `--include`
   - The run script as a Dracut pre-mount hook (`/lib/dracut/hooks/pre-mount/99-run-ollama.sh`)
   - Automatic WSL detection: adds `--no-kernel` when running under WSL, since WSL manages its own initramfs
5. **Update boot loader** -- Regenerates the GRUB configuration if `grub-mkconfig` is available.

## Usage

### Prerequisites

- Photon OS with root access
- Internet connectivity (for downloading Ollama and the TinyLlama model)
- Dracut (included in Photon OS by default)
- Sufficient disk space (~1 GB for the model plus initramfs overhead)

### Running the Script

```bash
chmod +x install-ollama.sh
sudo ./install-ollama.sh
```

After completion, reboot the system to test the custom initramfs. The TinyLlama inference output will appear on the system console during the pre-mount boot phase.

### WSL Considerations

The script automatically detects WSL environments via `/proc/version` and adjusts accordingly:
- In WSL, the `--no-kernel` flag is passed to Dracut since WSL uses its own kernel and initramfs for booting.
- The custom initramfs will **not** be active during WSL "boot". To test Ollama in WSL, run it normally: `ollama run tinyllama`.

## Customization

The generated run script (`99-run-ollama.sh`) can be adapted for various use cases:

- **AI-based boot decisions** -- Run diagnostic prompts and branch boot logic based on inference results.
- **Appliance initialization** -- Generate configuration or validate system state before mounting root.
- **Background server** -- Start `ollama serve` in the background (note: networking is typically unavailable in initramfs).

To customize, modify the heredoc block in `install-ollama.sh` that generates the `RUN_SCRIPT` content, or replace it entirely with your own Dracut hook logic.

## Limitations

- **Initramfs size** -- Embedding a ~637 MB model significantly increases the initramfs. This may cause issues on systems with limited `/boot` partition space or slow storage.
- **No networking** -- Standard initramfs environments have no network stack, so Ollama cannot download models or serve API requests at this stage.
- **CPU-only inference** -- GPU drivers are not loaded during initramfs, so inference runs on CPU only and will be slow.
- **Boot recovery** -- If the enlarged initramfs causes boot failures, restore the backup initramfs from a recovery environment.

## File Reference

| File | Description |
|------|-------------|
| `install-ollama.sh` | Main script that installs Ollama, pulls TinyLlama, and rebuilds the initramfs |

## Related

- [Ollama](https://ollama.com/) -- Run large language models locally
- [TinyLlama](https://huggingface.co/TinyLlama) -- Compact 1.1B parameter language model
- [Dracut](https://github.com/dracut-ng/dracut-ng) -- Initramfs generation tool used by Photon OS
- [Photon OS](https://vmware.github.io/photon/) -- VMware's minimal Linux container host
