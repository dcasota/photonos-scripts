# Base Plugin Module

**Version:** 2.0.0

## Description

Provides the foundation classes and utilities for all documentation analysis plugins.
This module defines the core abstractions that all plugins must implement.

## Key Classes

### Issue

Dataclass representing a detected documentation issue:

```python
@dataclass
class Issue:
    category: str       # Issue type (e.g., 'grammar', 'formatting')
    location: str       # URL or file path
    description: str    # Human-readable description
    suggestion: str     # Recommended fix
    context: str        # Surrounding text for context
    severity: str       # 'low', 'medium', 'high'
    line_number: int    # Line number in document
    metadata: Dict      # Additional plugin-specific data
```

### FixResult

Dataclass for fix operation results:

```python
@dataclass
class FixResult:
    success: bool
    modified_content: Optional[str]
    changes_made: List[str]
    error: Optional[str]
```

### BasePlugin

Abstract base class that all plugins must extend:

```python
class BasePlugin(ABC):
    PLUGIN_NAME: str      # Unique identifier
    PLUGIN_VERSION: str   # Semantic version
    FIX_ID: int          # Fix type ID (0 = no auto-fix)
    REQUIRES_LLM: bool   # Whether plugin needs LLM client
    
    @abstractmethod
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult
```

## Code Block Protection

Critical utilities to protect code blocks during analysis and fixes:

### strip_code_blocks(text)

Removes all code blocks for analysis (prevents false positives):
- Fenced code blocks (``` or ~~~)
- Inline code (`...`)
- Indented code blocks (4+ spaces)

### protect_code_blocks(text)

Replaces code blocks with placeholders before applying fixes:

```python
protected, blocks = protect_code_blocks(content)
# Apply fixes to 'protected'
result = restore_code_blocks(fixed, blocks)
```

### restore_code_blocks(text, blocks)

Restores original code blocks from placeholders after fixes.

## Usage

All plugins inherit from BasePlugin:

```python
from .base import BasePlugin, Issue, FixResult

class MyPlugin(BasePlugin):
    PLUGIN_NAME = "my_plugin"
    PLUGIN_VERSION = "1.0.0"
    FIX_ID = 10
    REQUIRES_LLM = False
    
    def detect(self, content, url, **kwargs):
        # Return list of Issue objects
        pass
```
