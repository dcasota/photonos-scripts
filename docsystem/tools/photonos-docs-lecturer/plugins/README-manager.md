# Plugin Manager Module

**Version:** 2.0.0

## Description

Handles plugin lifecycle management including discovery, registration,
configuration, and coordinated execution of all documentation analysis plugins.

## Key Class

### PluginManager

Central coordinator for all plugins:

```python
class PluginManager:
    def __init__(self, config: Optional[Dict] = None)
    def set_llm_client(self, client: Any)
    def register(self, plugin_class: Type[BasePlugin], config: Optional[Dict] = None)
    def get_plugin(self, name: str) -> Optional[BasePlugin]
    def detect_all(self, content: str, url: str, **kwargs) -> Dict[str, List[Issue]]
    def fix_all(self, content: str, issues: Dict, enabled_fixes: List[str], **kwargs) -> FixResult
```

## Features

### Plugin Registration

Plugins are registered with optional per-plugin configuration:

```python
manager = PluginManager(global_config)
manager.register(GrammarPlugin, {'language': 'en-US'})
manager.register(SpellingPlugin)
```

### LLM Client Injection

LLM client is automatically propagated to plugins that need it:

```python
manager.set_llm_client(llm_client)
# All plugins with REQUIRES_LLM=True receive the client
```

### Batch Detection

Run all registered plugins on content:

```python
all_issues = manager.detect_all(content, url)
# Returns: {'grammar': [...], 'spelling': [...], ...}
```

### Batch Fixing

Apply fixes from multiple plugins:

```python
result = manager.fix_all(
    content,
    issues,
    enabled_fixes=['grammar', 'spelling']
)
```

## Error Handling

Plugin failures are logged but don't stop other plugins:

```python
for name, plugin in self.plugins.items():
    try:
        issues = plugin.detect(content, url)
    except Exception as e:
        self.logger.error(f"Plugin {name} failed: {e}")
        # Continue with other plugins
```

## Usage

```python
from .manager import PluginManager
from .grammar import GrammarPlugin
from .spelling import SpellingPlugin

manager = PluginManager()
manager.register(GrammarPlugin)
manager.register(SpellingPlugin)

issues = manager.detect_all(markdown_content, page_url)
result = manager.fix_all(markdown_content, issues)
```
