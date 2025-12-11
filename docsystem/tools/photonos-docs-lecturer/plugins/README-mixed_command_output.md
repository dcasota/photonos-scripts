# Mixed Command Output Plugin (Feature)

## Overview

The Mixed Command Output Plugin detects and separates code blocks that mix commands with their output. Requires LLM for intelligent separation.

**Feature ID:** 2  
**Requires LLM:** Yes  
**Version:** 1.0.0

## Features

- Detect mixed command/output blocks
- Intelligent separation with LLM
- Preserve all content

## Usage

```bash
# Enable mixed command/output separation (feature 2)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --feature 2 \
  --llm xai --XAI_API_KEY your_key
```

## What It Detects

Code blocks that contain both:
1. Commands (lines with prompts or command syntax)
2. Output (results of those commands)

## Example

### Before

```bash
$ ls -la /etc/
total 1368
drwxr-xr-x  80 root root 4096 Dec 10 10:00 .
drwxr-xr-x  18 root root 4096 Dec  1 00:00 ..
-rw-r--r--   1 root root 3040 Dec 10 10:00 passwd
```

### After

```bash
ls -la /etc/
```

Output:
```
total 1368
drwxr-xr-x  80 root root 4096 Dec 10 10:00 .
drwxr-xr-x  18 root root 4096 Dec  1 00:00 ..
-rw-r--r--   1 root root 3040 Dec 10 10:00 passwd
```

## Why This is a Feature

This is classified as a feature because:

1. Changes documentation structure significantly
2. May affect how users understand examples
3. Requires careful LLM judgment
4. Users should opt-in to this change

## Command Indicators

The plugin looks for these patterns to identify commands:
- Shell prompts (`$`, `#`, `>`, `%`)
- Root prompts (`root@host#`)
- User prompts (`user@host$`)
- Common commands (`sudo`, `tdnf`, `git`, `cd`, `ls`, etc.)

## Log File

```
/var/log/photonos-docs-lecturer-mixed_command_output.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [mixed_command_output] Detected: Code block contains mixed commands and output
2025-12-11 10:00:05 - INFO - [mixed_command_output] Fixed: Separated command/output block
```
