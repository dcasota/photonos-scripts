# Shell Prompt Plugin (Feature)

## Overview

The Shell Prompt Plugin removes shell prompts from code blocks to make commands copyable. This is an optional feature that modifies code block formatting.

**Feature ID:** 1  
**Requires LLM:** No  
**Version:** 1.0.0

## Features

- Remove common shell prompts
- Preserve command content
- Add language hints to code blocks

## Usage

```bash
# Enable shell prompt removal (feature 1)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --feature 1
```

## What It Removes

| Prompt | Example |
|--------|---------|
| `$` | `$ command` → `command` |
| `>` | `> command` → `command` |
| `%` | `% command` → `command` |
| `~` | `~ command` → `command` |
| `❯` | `❯ command` → `command` |
| `➜` | `➜ command` → `command` |
| `root@host#` | `root@host# command` → `command` |
| `user@host$` | `user@host$ command` → `command` |

## Example

### Before

```bash
$ git clone https://github.com/vmware/photon.git
$ cd photon
$ sudo make iso
```

### After

```console
git clone https://github.com/vmware/photon.git
cd photon
sudo make iso
```

## Why This is a Feature

This is classified as a feature (not a fix) because:

1. Some documentation intentionally shows prompts
2. Prompts can indicate user vs root context
3. Removal changes the documentation style
4. Users should opt-in to this change

## Log File

```
/var/log/photonos-docs-lecturer-shell_prompt.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [shell_prompt] Detected: Shell prompt detected: $ prompt
2025-12-11 10:00:01 - INFO - [shell_prompt] Fixed: Removed 5 shell prompts from code blocks
```
