# Shell Prompt Plugin

**Version:** 2.0.0  
**FIX_ID:** 0 (Detection Only)  
**Requires LLM:** No

## Description

Detects shell prompts in code blocks that might hinder copy-paste.

## Issues Detected

1. **$ prompt** - `$ command`
2. **# prompt** - `# command` (root)
3. **User prompts** - `root@host:~#`
4. **Bracketed prompts** - `[user@host dir]$`

## Why Detection Only

Shell prompts are often intentional:
- Show interactive sessions
- Indicate root vs user commands
- Document expected workflow

Removal is a stylistic choice requiring human judgment.

## Example

```bash
$ docker ps
CONTAINER ID   IMAGE   ...

# systemctl start nginx
```

The `$` and `#` prompts help readers understand context.

## Configuration

No configuration required.
