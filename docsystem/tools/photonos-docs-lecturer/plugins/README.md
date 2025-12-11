# Photon OS Documentation Lecturer - Plugin System

Version: 2.0.0

## Overview

This plugin system provides modular detection and fixing of documentation issues.
All plugins are designed with a critical safety feature: **fenced code blocks are NEVER modified**.

## Architecture

### Core Components

- **base.py** - Base classes and code block protection utilities
- **manager.py** - Plugin lifecycle management and execution coordination
- **integration.py** - Integration utilities for the main script

### Code Block Protection

Every plugin uses the following pattern to protect code blocks:

```python
from .base import protect_code_blocks, restore_code_blocks

def fix(self, content, issues, **kwargs):
    # 1. Protect code blocks FIRST
    protected_content, code_blocks = protect_code_blocks(content)
    
    # 2. Apply fixes to protected content (code blocks are placeholders)
    result = apply_fixes(protected_content)
    
    # 3. Restore code blocks UNCHANGED
    final_content = restore_code_blocks(result, code_blocks)
    
    return final_content
```

## Available Plugins

### Automatic Fix Plugins (FIX_ID > 0)

| Plugin | FIX_ID | Description |
|--------|--------|-------------|
| grammar | 1 | Grammar and spelling fixes (LLM-assisted) |
| markdown | 2 | Markdown formatting fixes |
| indentation | 3 | List and content indentation |
| formatting | 4 | Backtick spacing fixes |
| backtick_errors | 5 | Spaces inside backticks |
| deprecated_url | 13 | Deprecated URL replacement |
| spelling | 14 | VMware/Photon spelling fixes |

### Detection-Only Plugins (FIX_ID = 0)

| Plugin | Description |
|--------|-------------|
| heading_hierarchy | Heading level violations |
| orphan_link | Broken hyperlinks |
| orphan_image | Missing images |
| orphan_page | Unreferenced pages |
| image_alignment | Image positioning issues |
| shell_prompt | Shell prompts in code blocks |
| mixed_command_output | Commands mixed with output |

## Usage

### From Main Script

```python
from plugins.integration import create_plugin_manager, parse_fix_range

# Create manager with all plugins
manager = create_plugin_manager(llm_client=my_llm_client)

# Detect issues
issues = manager.detect_all(content, url)

# Apply fixes
result = manager.fix_all(content, issues, enabled_fixes=['formatting', 'spelling'])
```

### Selecting Fixes

```python
from plugins.integration import parse_fix_range, get_plugins_for_fixes

# Parse "1-5" to get fix IDs
fix_ids = parse_fix_range("1-5")  # [1, 2, 3, 4, 5]

# Get plugin names for those fix IDs
plugins = get_plugins_for_fixes(fix_ids)  # ['grammar', 'markdown', ...]
```

## Creating a New Plugin

1. Create a new file in the plugins directory
2. Inherit from `BasePlugin`, `PatternBasedPlugin`, or `LLMAssistedPlugin`
3. Implement `detect()` and `fix()` methods
4. **Always use `protect_code_blocks()` in fix methods**

```python
from .base import PatternBasedPlugin, Issue, FixResult, protect_code_blocks, restore_code_blocks

class MyPlugin(PatternBasedPlugin):
    PLUGIN_NAME = "my_plugin"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "My custom plugin"
    REQUIRES_LLM = False
    FIX_ID = 15  # Use next available ID
    
    def detect(self, content, url, **kwargs):
        # Use strip_code_blocks() before pattern matching
        safe_content = strip_code_blocks(content)
        # ... detection logic
        
    def fix(self, content, issues, **kwargs):
        # ALWAYS protect code blocks
        protected, blocks = protect_code_blocks(content)
        # ... fix logic on protected content
        return restore_code_blocks(result, blocks)
```

## Testing

```bash
# Run the tool with plugin detection
python3 photonos-docs-lecturer.py analyze --website https://example.com/docs

# Run with specific fixes
python3 photonos-docs-lecturer.py run --website https://example.com/docs --fix 1-5
```

## Safety Guarantees

1. **Code blocks are NEVER modified** - Protected by `protect_code_blocks()`
2. **Inline code is preserved** - Detection excludes inline code spans
3. **LLM responses are validated** - Content length, structure, and code blocks verified
4. **All changes are reversible** - Git integration allows easy rollback
