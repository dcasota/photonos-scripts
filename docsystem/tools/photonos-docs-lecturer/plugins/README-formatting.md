# Formatting Plugin

## Overview

The Formatting Plugin handles backtick spacing issues and other formatting fixes. It adds missing spaces around inline code backticks and removes backticks from URLs.

**Plugin ID:** 4  
**Requires LLM:** No  
**Version:** 1.0.0

## Features

- Add missing spaces before backticks
- Add missing spaces after backticks
- Remove backticks from URLs
- Fix stray backtick typos

## Usage

```bash
# Apply formatting fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --fix 4
```

## What It Detects and Fixes

### Missing Space Before Backtick

```markdown
# Wrong
Clone`the repository`

# Fixed
Clone `the repository`
```

### Missing Space After Backtick

```markdown
# Wrong
Run `command`now

# Fixed
Run `command` now
```

### URLs in Backticks

```markdown
# Wrong
Visit `https://example.com`

# Fixed
Visit https://example.com
```

### Stray Backtick Typos

```markdown
# Wrong
Clone`the project

# Fixed
Clone the project
```

## Log File

```
/var/log/photonos-docs-lecturer-formatting.log
```

## Example Output

```
2025-12-11 10:00:00 - INFO - [formatting] Fixed: Added 5 spaces before backticks
2025-12-11 10:00:00 - INFO - [formatting] Fixed: Removed backticks from 2 URLs
```

## Related Plugins

- **Backtick Errors Plugin (ID 5):** Handles spaces inside backticks
- **Markdown Plugin (ID 10):** Handles markdown artifacts
