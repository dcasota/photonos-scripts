# Tests Plugin

**Version:** 2.0.0  
**Type:** Unit Tests  
**Requires LLM:** No

## Description

Comprehensive unit tests for the Photon OS Documentation Lecturer tool.
Tests cover URL validation, fix parsing, pattern matching, and all fix functions.

## Test Categories

### Validation Tests
- `test_validate_url` - URL format validation
- `test_validate_parallel` - Parallel worker count validation
- `test_parse_fix_spec` - Fix specification parsing (--fix parameter)
- `test_parse_feature_spec` - Feature specification parsing (--feature parameter)

### Pattern Tests
- `test_markdown_patterns` - Markdown artifact detection patterns
- `test_missing_space_before_backtick` - Backtick spacing pattern (before)
- `test_missing_space_after_backtick` - Backtick spacing pattern (after)
- `test_shell_prompt_patterns` - Shell prompt detection patterns
- `test_deprecated_vmware_url_pattern` - Deprecated URL patterns
- `test_vmware_spelling_pattern` - VMware spelling detection
- `test_markdown_header_no_space_pattern` - Header spacing detection

### Fix Function Tests
- `test_fix_markdown_header_spacing` - Header spacing fixes
- `test_fix_html_comments` - HTML comment removal
- `test_fix_vmware_spelling` - VMware spelling correction
- `test_fix_deprecated_urls` - Deprecated URL replacement
- `test_fix_broken_email_addresses` - Broken email fixes
- `test_fix_backtick_spacing` - Backtick spacing fixes
- `test_fix_fenced_inline_code` - Fenced to inline code conversion
- `test_fix_triple_backtick_inline` - Triple backtick inline fixes
- `test_fix_escaped_underscores` - Escaped underscore restoration
- `test_fix_shell_prompts_in_markdown` - Shell prompt removal
- `test_fix_heading_hierarchy_preserves_first_heading` - Heading hierarchy fixes

### LLM Tests
- `test_llm_url_protection` - URL protection mechanism
- `test_llm_prompt_leakage_cleaning` - Prompt leakage removal
- `test_llm_relative_path_protection` - Relative path protection

### Integration Tests
- `test_strip_code_from_text` - Code block stripping for grammar check
- `test_mixed_command_output_detection` - Mixed command/output detection
- `test_vmware_spelling_excludes_broken_emails` - Email exclusion
- `test_analyze_heading_hierarchy_ignores_first_heading` - Hierarchy analysis
- `test_case_insensitive_directory_matching` - Path matching
- `test_content_based_file_matching` - Content-based file lookup
- `test_content_similarity_calculation` - Similarity scoring

## Usage

### Standalone Execution

```bash
cd plugins
python3 tests.py
```

### Via Main Tool

```bash
python3 photonos-docs-lecturer.py test
```

## Dependencies

- `unittest` (standard library)
- `tempfile` (standard library)
- `shutil` (standard library)
- Parent module: `photonos-docs-lecturer.py`

## Adding New Tests

1. Add test method to `TestDocumentationLecturer` class
2. Follow naming convention: `test_<functionality>`
3. Use `MockArgs` class for creating lecturer instances
4. Call `lecturer.cleanup()` after each test

Example:

```python
def test_new_feature(self):
    """Test description."""
    class MockArgs:
        command = 'analyze'
        website = 'https://example.com'
        parallel = 1
        language = 'en'
        ref_website = None
        test = False
    
    lecturer = DocumentationLecturer(MockArgs())
    
    # Test assertions
    self.assertEqual(expected, actual)
    
    lecturer.cleanup()
```
