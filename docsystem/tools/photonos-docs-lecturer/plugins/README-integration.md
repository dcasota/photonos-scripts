# Integration Module

**Version:** 2.0.0

## Description

Provides utilities for integrating all plugins with the main documentation
lecturer script. Acts as the central registry and factory for plugins.

## Plugin Registry

### ALL_PLUGINS

Complete list of available plugin classes:

```python
ALL_PLUGINS = [
    FormattingPlugin,
    BacktickErrorsPlugin,
    DeprecatedUrlPlugin,
    SpellingPlugin,
    GrammarPlugin,
    MarkdownPlugin,
    IndentationPlugin,
    HeadingHierarchyPlugin,
    OrphanLinkPlugin,
    OrphanImagePlugin,
    OrphanPagePlugin,
    ImageAlignmentPlugin,
    ShellPromptPlugin,
    MixedCommandOutputPlugin,
]
```

### FIX_PLUGINS

Plugins that support automatic fixes (FIX_ID > 0):

```python
FIX_PLUGINS = [p for p in ALL_PLUGINS if p.FIX_ID > 0]
```

### Mappings

```python
PLUGIN_MAP: Dict[str, Type[BasePlugin]]  # name -> class
FIX_ID_MAP: Dict[int, Type[BasePlugin]]  # fix_id -> class
```

## Factory Function

### create_plugin_manager()

Creates a fully configured PluginManager:

```python
def create_plugin_manager(
    config: Optional[Dict] = None,
    llm_client: Any = None,
    enabled_plugins: Optional[List[str]] = None
) -> PluginManager
```

Example:

```python
manager = create_plugin_manager(
    config={'grammar': {'language': 'en-US'}},
    llm_client=xai_client,
    enabled_plugins=['grammar', 'spelling', 'formatting']
)
```

## Utility Functions

### get_fix_descriptions()

Returns human-readable descriptions for all fix types:

```python
descriptions = get_fix_descriptions()
# {1: 'Grammar fixes', 2: 'Spelling fixes', ...}
```

## Usage

```python
from .integration import create_plugin_manager, ALL_PLUGINS, PLUGIN_MAP

# Create manager with all plugins
manager = create_plugin_manager(llm_client=my_llm)

# Or get specific plugin class
GrammarPlugin = PLUGIN_MAP['grammar']
```
