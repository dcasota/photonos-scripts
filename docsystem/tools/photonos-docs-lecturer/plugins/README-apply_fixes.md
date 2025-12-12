# Apply Fixes Module

**Version:** 1.0.0

## Description

Provides functionality to apply detected fixes to local markdown files.
Handles file discovery, content modification, and change tracking.

## Key Class

### FixApplicator

```python
class FixApplicator:
    def __init__(self, lecturer: DocumentationLecturer)
    def find_local_file(self, url: str) -> Optional[str]
    def apply_fixes_to_file(self, file_path: str, issues: Dict) -> bool
    def calculate_content_similarity(self, text1: str, text2: str) -> float
```

## File Discovery

Maps web URLs to local filesystem paths:

### URL to Path Mapping

```python
# Web URL
https://127.0.0.1/docs-v3/admin-guide/packages/

# Local path (Hugo content structure)
/var/www/photon-site/content/en/docs-v3/admin-guide/packages/_index.md
```

### Case-Insensitive Matching

Hugo normalizes URLs to lowercase, but filesystem may have mixed case:

```python
path = self.find_directory_case_insensitive(
    parent_dir,
    'command-line-interfaces'  # URL: lowercase
)
# Finds: Command-Line-Interfaces/  # Actual: mixed case
```

### Content-Based Matching

For complex URL-to-file mappings, uses content similarity:

```python
similarity = self.calculate_content_similarity(web_content, file_content)
if similarity > 0.7:
    # Match found
```

## Fix Application

### Process Flow

1. Find local file for URL
2. Read current content
3. Apply plugin fixes (grammar, spelling, URLs, etc.)
4. Apply LLM-based fixes if enabled
5. Write modified content
6. Track changes for reporting

### Plugin Integration

```python
for plugin_name, plugin_issues in issues.items():
    plugin = self.lecturer.plugin_manager.get_plugin(plugin_name)
    if plugin and plugin.FIX_ID in enabled_fixes:
        result = plugin.fix(content, plugin_issues)
        if result.success:
            content = result.modified_content
```

## Usage

```python
from .apply_fixes import FixApplicator

applicator = FixApplicator(lecturer_instance)

# Find local file
local_path = applicator.find_local_file(web_url)

# Apply fixes
success = applicator.apply_fixes_to_file(local_path, detected_issues)
```
