# Apply Fixes Module

**Version:** 1.1.0

## Description

Provides functionality to apply detected fixes to local markdown files.
Handles file discovery, content modification, and change tracking.

## Key Class

### FixApplicator

```python
class FixApplicator:
    def __init__(self, lecturer: DocumentationLecturer)
    def map_url_to_local_path(self, page_url: str, webpage_text: str = None) -> Optional[str]
    def apply_fixes(self, page_url: str, issues: Dict[str, List], webpage_text: str = None)
    def calculate_content_similarity(self, text1: str, text2: str) -> float
    def extract_title_from_markdown(self, file_path: str) -> Optional[str]
    def normalize_slug(self, text: str) -> str
```

## File Discovery

Maps web URLs to local filesystem paths using multiple strategies:

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

### Title-Based Matching (New in 1.1.0)

When URL slug doesn't match filename, matches by frontmatter title:

```python
# URL slug: building-ova-image
# File: build-ova.md (title: "Building OVA image")

file_title = self.extract_title_from_markdown(file_path)
title_slug = self.normalize_slug(file_title)  # "building-ova-image"
if title_slug == url_slug:
    # Title match found - preferred over content similarity
```

### Content-Based Matching (Fallback)

For complex URL-to-file mappings, uses content similarity as fallback:

```python
similarity = self.calculate_content_similarity(web_content, file_content)
if similarity > 0.3:
    # Content match candidate
```

## Fix Application

### Process Flow

1. Find local file for URL (title-based > content-based matching)
2. Read current content
3. Apply deterministic fixes (emails, URLs, spelling, hardcoded replaces)
4. Apply LLM-based fixes if enabled (grammar, markdown, indentation)
5. Revert relative path changes if FIX_ID 13 not enabled
6. Write modified content
7. Track changes for reporting

### Plugin Integration

```python
for plugin_name, plugin_issues in issues.items():
    plugin = self.lecturer.plugin_manager.get_plugin(plugin_name)
    if plugin and plugin.FIX_ID in enabled_fixes:
        result = plugin.fix(content, plugin_issues)
        if result.success:
            content = result.modified_content
```

### Relative Path Handling (FIX_ID 13)

The module can revert relative path modifications made by external tools:

```python
# If FIX_ID 13 (relative-paths) is NOT enabled:
# Reverts changes like ../images/ -> ../../images/
if 'relative_path_issues' not in self.lecturer.enabled_fix_keys:
    content = self._revert_relative_path_changes(content, original)
```

## Usage

```python
from .apply_fixes import FixApplicator

applicator = FixApplicator(lecturer_instance)

# Find local file with title-based matching
local_path = applicator.map_url_to_local_path(web_url, webpage_text)

# Apply fixes
applicator.apply_fixes(web_url, detected_issues, webpage_text)
```

## Changes History

### Version 1.1.0
- Added title-based file matching using frontmatter title extraction
- Added `extract_title_from_markdown()` method to parse YAML frontmatter
- Added `normalize_slug()` method to convert titles to URL slugs
- Improved `find_matching_file_by_content()` to prefer title matches over content similarity
- Fixed interference issues where similar files (build-ova.md, build-cloud-images.md) were incorrectly matched due to content similarity scoring
- Added FIX_ID 13 (relative-paths) support for reverting relative path modifications

### Version 1.0.0
- Initial release with URL-to-path mapping
- Case-insensitive directory matching
- Content-based file matching
- Plugin fix integration
