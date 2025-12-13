# Grammar Plugin

**Version:** 2.1.0  
**FIX_ID:** 9  
**Requires LLM:** Yes

## Description

Detects and fixes grammar and spelling issues using LanguageTool for detection
and LLM for complex fixes.

## Issues Detected

- Spelling errors (detected but NOT auto-fixed - see below)
- Grammar mistakes
- Punctuation issues
- Subject-verb agreement
- Article usage (a/an/the)

## LLM-Based Fixing

All grammar and spelling issues are sent to the LLM (xAI Grok 4) for intelligent
fixing. The LLM understands technical context and preserves technical terms.

**Detection Filtering (before sending to LLM):**
- Hyphenated terms (e.g., `cloud-init`) are skipped during detection
- camelCase/PascalCase terms (e.g., `NetworkManager`) are skipped
- Underscored terms (e.g., `cloud_init`) are skipped

## Code Block Protection

Grammar checking is performed on content with code blocks stripped:

```python
safe_content = strip_code_blocks(content)
matches = language_tool.check(safe_content)
```

Fixes use `protect_code_blocks()` to ensure code blocks are preserved:

```python
protected, blocks = protect_code_blocks(content)
result = llm_fix(protected)
final = restore_code_blocks(result, blocks)
```

## LLM Prompt

The LLM is given explicit rules:
1. Output ONLY the corrected text
2. Preserve all formatting
3. Do NOT modify code blocks
4. Do NOT escape underscores
5. Lines starting with 4+ spaces are code

## Dependencies

- `language-tool-python` for detection
- LLM client (xAI/Gemini) for fixes

## Configuration

```python
config = {
    'language': 'en-US',
    'max_issues': 20  # Limit issues per LLM call
}
```
