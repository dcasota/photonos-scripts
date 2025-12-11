# Backtick Errors Plugin

## Overview

The Backtick Errors Plugin detects and fixes spaces inside inline code backticks and handles unclosed inline code.

**Plugin ID:** 5  
**Requires LLM:** No  
**Version:** 1.0.0

## Features

- Remove space after opening backtick
- Remove space before closing backtick
- Fix spaces on both sides
- Close unclosed inline backticks

## Usage

```bash
# Apply backtick error fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 5
```

## What It Detects and Fixes

### Space After Opening Backtick

```markdown
# Wrong
Use ` command` to run

# Fixed
Use `command` to run
```

### Space Before Closing Backtick

```markdown
# Wrong
Use `command ` to run

# Fixed
Use `command` to run
```

### Spaces on Both Sides

```markdown
# Wrong
Use ` command ` to run

# Fixed
Use `command` to run
```

### Unclosed Inline Backticks

```markdown
# Wrong
Use `$HOME/path.

# Fixed
Use `$HOME/path`.
```

## Log File

```
/var/log/photonos-docs-lecturer-backtick_errors.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [backtick_errors] Fixed: Removed 3 spaces after opening backticks
2025-12-11 10:00:00 - INFO - [backtick_errors] Fixed: Closed 1 unclosed inline backticks
```

## Related Plugins

- **Formatting Plugin (ID 4):** Handles spaces around backticks
- **Malformed Code Block Plugin (ID 12):** Handles code block structure
