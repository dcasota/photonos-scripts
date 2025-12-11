# Grammar Plugin

## Overview

The Grammar Plugin detects and fixes grammar and spelling issues in documentation using LanguageTool for detection and LLM (Large Language Model) for intelligent fixing.

**Plugin ID:** 9  
**Requires LLM:** Yes  
**Version:** 1.0.0

## Features

- Grammar error detection via LanguageTool
- Spelling mistake identification
- Context-aware fixing with LLM
- Automatic exclusion of code blocks

## Usage

### Enable Grammar Fixes

```bash
# Apply grammar fixes (requires LLM)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 9 \
  --llm xai --XAI_API_KEY your_key
```

### Combine with Other Fixes

```bash
# Apply grammar and VMware spelling fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 2,9 \
  --llm gemini --GEMINI_API_KEY your_key
```

## What It Detects

- **Spelling mistakes:** Misspelled words
- **Grammar errors:** Subject-verb agreement, tense issues
- **Punctuation errors:** Incorrect comma usage, missing periods
- **Style issues:** Passive voice (when configured)

## What It Preserves

The plugin automatically excludes from checking:

- Content inside code blocks (```)
- Inline code (`code`)
- Indented code (4+ spaces)
- URLs and paths
- Product names (Photon OS, VMware, etc.)
- Technical identifiers

## Configuration

The plugin uses the following defaults:

| Option | Default | Description |
|--------|---------|-------------|
| language | en-EN | Language for grammar checking |

## Log File

Plugin logs are written to:
```
/var/log/photonos-docs-lecturer-grammar.log
```

## Dependencies

- Java >= 17 (for LanguageTool)
- language-tool-python package
- LLM provider (Gemini or xAI) with API key

## Example Output

```
2025-12-11 10:00:00 - INFO - [grammar] Detected: grammar - The verb 'is' doesn't seem to agree...
2025-12-11 10:00:01 - INFO - [grammar] Fixed: Applied grammar fixes for 3 issues
```

## Troubleshooting

### LanguageTool fails to initialize

```bash
# Install Java
sudo tdnf install openjdk21
```

### LLM fixes not applied

Ensure you provide a valid API key:
```bash
--llm xai --XAI_API_KEY your_actual_key
```

### Too many false positives

Grammar checking automatically skips certain rule categories known to produce false positives in technical documentation. If you encounter issues, review the log file for details.
