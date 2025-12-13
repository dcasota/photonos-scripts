# LLM Client Module

**Version:** 1.0.0

## Description

Provides LLM API interactions for grammar fixing, markdown correction,
translation, and other text processing tasks. Supports multiple LLM providers.

## Supported Providers

| Provider | Model | API Endpoint |
|----------|-------|--------------|
| xAI | grok-4-0709 | https://api.x.ai/v1/chat/completions |
| Google | gemini-2.5-flash | Google Generative AI |

## Key Class

### LLMClient

```python
class LLMClient:
    def __init__(self, provider: str, api_key: str, language: str = "en")
    def fix_backticks(self, text: str, issues: Optional[List[Dict]] = None) -> str
    def fix_grammar(self, text: str, issues: List[Dict]) -> str
    def fix_markdown(self, text: str, artifacts: List[str]) -> str
    def fix_indentation(self, text: str, issues: List[Dict]) -> str
    def translate(self, text: str, target_language: str) -> str
```

## Fix Pipeline Order

The `fix_backticks()` method (FIX_ID 8) should be called **first** in the fix pipeline:

1. **fix_backticks** (FIX_ID 8) - Correct all backtick issues (unified LLM-based fix)
2. fix_grammar (FIX_ID 9) - Fix grammar issues
3. fix_markdown (FIX_ID 10) - Fix markdown artifacts
4. fix_indentation (FIX_ID 11) - Fix indentation issues
5. translate - Translate to target language

The unified backtick fix handles:
- Missing spaces around backticks
- Spaces inside backticks
- Missing/mismatched backticks
- Malformed code blocks
- URLs in backticks (removes backticks)
- Triple backticks used as inline code (converts to single)

This ensures proper code formatting before other checks and translation run.

## URL Protection

LLMs sometimes modify URLs despite instructions. The client uses placeholder
protection to preserve URLs:

```python
# Before sending to LLM
protected, url_map = self._protect_urls(text)
# URLs replaced with __URL_PLACEHOLDER_N__

# After LLM response
result = self._restore_urls(response, url_map)
# Original URLs restored
```

Protected elements:
- Markdown links: `[text](url)`
- Inline URLs: `https://...`
- Relative paths: `../path/to/file`

## Response Cleaning

The `_clean_llm_response()` method removes common LLM artifacts:
- Prompt leakage ("Return only the corrected text...")
- Added commentary and notes
- Explanatory preambles
- Escaped underscores in technical terms

## Configuration

Environment variables:
- `XAI_API_KEY` - xAI API key
- `GEMINI_API_KEY` - Google Gemini API key

Timeout: 300 seconds (configurable for large documents)

## Usage

```python
from .llm_client import LLMClient

client = LLMClient(provider='xai', api_key=os.environ['XAI_API_KEY'])

# Fix grammar
fixed = client.fix_grammar(content, grammar_issues)

# Translate
translated = client.translate(content, 'German')
```

## Error Handling

API failures are logged and return empty string:

```python
try:
    response = requests.post(endpoint, json=payload, timeout=300)
    response.raise_for_status()
except Exception as e:
    logging.error(f"xAI API call failed: {e}")
    return ""
```
