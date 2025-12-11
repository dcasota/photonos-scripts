#!/usr/bin/env python3
"""
LLM Client Module for Photon OS Documentation Lecturer

Provides LLM API interactions for grammar fixing, markdown correction,
translation, and other text processing tasks.

Supports:
- Google Gemini API
- xAI (Grok) API

Version: 1.0.0
"""

from __future__ import annotations

import logging
import re
from typing import Dict, List, Tuple, TYPE_CHECKING

# Lazy imports for LLM libraries
HAS_GEMINI = False
genai = None

def _load_gemini():
    """Lazy load Google Generative AI library."""
    global HAS_GEMINI, genai
    if genai is None:
        try:
            import google.generativeai as _genai
            genai = _genai
            HAS_GEMINI = True
        except ImportError:
            HAS_GEMINI = False
    return HAS_GEMINI

# Import requests for xAI API
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

__version__ = "1.0.0"


class LLMClient:
    """Client for LLM API interactions (Gemini or xAI)."""
    
    # Pattern to match markdown links: [text](url)
    MARKDOWN_LINK_PATTERN = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
    
    # Pattern to match inline URLs (http/https)
    INLINE_URL_PATTERN = re.compile(r'(?<![(\[])(https?://[^\s<>"\')\]]+)')
    
    # Pattern to match relative paths that look like documentation links
    RELATIVE_PATH_PATTERN = re.compile(
        r'('
        r'\(\s*\.{1,2}/[\w./-]+/?\s*\)'  # Paths in parentheses: (./path/) or (../path/)
        r'|'
        r'\.{1,2}/[\w./-]+/?'  # Paths starting with ./ or ../
        r'|'
        r'[\w-]+(?:/[\w-]+)+(?:\.md)?/?'  # Paths like dir/subdir/page
        r')'
    )
    
    def __init__(self, provider: str, api_key: str, language: str = "en"):
        self.provider = provider.lower()
        self.api_key = api_key
        self.language = language
        self.model = None
        
        if self.provider == "gemini":
            if not _load_gemini():
                raise ImportError("google-generativeai library required for Gemini. Install with: pip install google-generativeai")
            genai.configure(api_key=self.api_key)
            self.model = genai.GenerativeModel('gemini-2.5-flash')
        elif self.provider == "xai":
            if not HAS_REQUESTS:
                raise ImportError("requests library required for xAI. Install with: pip install requests")
            self.xai_endpoint = "https://api.x.ai/v1/chat/completions"
            self.xai_model = "grok-4"
        else:
            raise ValueError(f"Unsupported LLM provider: {provider}")
    
    def _protect_urls(self, text: str) -> Tuple[str, Dict[str, str]]:
        """Replace URLs with placeholders to protect them from LLM modification.
        
        LLMs sometimes modify URLs despite explicit instructions not to do so.
        This method replaces all URLs with unique placeholders before sending
        to the LLM, allowing us to restore the original URLs afterwards.
        
        Protects:
        - Markdown links: [text](url)
        - Standalone http/https URLs
        - Relative paths (e.g., ../path/to/page, dir/subdir/page.md)
        
        Args:
            text: Original text containing URLs
            
        Returns:
            Tuple of (protected_text, url_map) where url_map maps placeholders to original URLs
        """
        url_map = {}
        counter = [0]
        
        def replace_markdown_link(match):
            link_text = match.group(1)
            url = match.group(2)
            placeholder = f"__URL_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = url
            counter[0] += 1
            return f"[{link_text}]({placeholder})"
        
        def replace_inline_url(match):
            url = match.group(1)
            placeholder = f"__URL_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = url
            counter[0] += 1
            return placeholder
        
        def replace_relative_path(match):
            path = match.group(1)
            if '__URL_PLACEHOLDER_' in path or path.startswith('```'):
                return match.group(0)
            placeholder = f"__PATH_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = path
            counter[0] += 1
            return placeholder
        
        protected = self.MARKDOWN_LINK_PATTERN.sub(replace_markdown_link, text)
        protected = self.INLINE_URL_PATTERN.sub(replace_inline_url, protected)
        protected = self.RELATIVE_PATH_PATTERN.sub(replace_relative_path, protected)
        
        return protected, url_map
    
    def _restore_urls(self, text: str, url_map: Dict[str, str]) -> str:
        """Restore original URLs from placeholders."""
        result = text
        for placeholder, original_url in url_map.items():
            result = result.replace(placeholder, original_url)
        return result
    
    def _generate_with_url_protection(self, prompt: str, text_to_protect: str) -> str:
        """Generate LLM response with URL protection and post-processing.
        
        Protects URLs in the input text before sending to LLM, then restores
        them in the output. This prevents LLMs from accidentally modifying
        URLs (e.g., removing .md extensions).
        
        Also cleans the LLM response to remove prompt leakage and artifacts.
        """
        protected_text, url_map = self._protect_urls(text_to_protect)
        full_prompt = prompt.replace("{text}", protected_text)
        response = self._generate(full_prompt)
        
        if not response:
            return ""
        
        cleaned_response = self._clean_llm_response(response, text_to_protect)
        return self._restore_urls(cleaned_response, url_map)
    
    def translate(self, text: str, target_language: str) -> str:
        """Translate text to target language using LLM.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        prompt_template = f"""Translate the following text to {target_language}.

CRITICAL RULES - VIOLATIONS WILL CAUSE ERRORS:
1. Preserve ALL markdown formatting exactly as-is (headings, lists, code blocks, inline code)
2. Do NOT modify any URLs or placeholders (text like __URL_PLACEHOLDER_N__)
3. Do NOT translate or change any relative paths like ../../images/ or ../images/
4. Do NOT translate or change paths in markdown links [text](path) - keep the path exactly as-is
5. Do NOT translate content inside code blocks (```) or inline code (`)
6. Do NOT translate technical terms, product names, or command names (e.g., VMware, GitHub, Photon OS)
7. Do NOT add, remove, or reorder list items
8. Do NOT add any explanations, notes, or commentary to your response
9. Only translate the natural language text outside of code and technical terms
10. NEVER add ANY text that wasn't in the original - no parenthetical notes like "(note: ...)" or "(this is ...)"
11. NEVER add observations, thoughts, or meta-commentary about the content

Text to translate:
{{text}}

Output ONLY the translated text. Do NOT add any preamble, explanation, notes, or commentary."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def fix_grammar(self, text: str, issues: List[Dict]) -> str:
        """Fix grammar issues in text using LLM.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        issue_desc = "\n".join([f"- {i['message']}: {i.get('suggestion', 'No suggestion')}" for i in issues[:10]])
        prompt_template = f"""You are a grammar correction assistant. Fix ONLY the specific grammar issues listed below.

ABSOLUTE RESTRICTIONS (violating ANY of these will break the system):

1. NEVER MODIFY THESE - copy them EXACTLY as they appear:
   - URLs (anything starting with http:// or https://)
   - Markdown link text that contains URLs: [https://github.com/...](url) - keep the text EXACTLY as-is
   - Domain names: github.com, gitlab.com, bitbucket.org - NEVER capitalize these
   - Placeholders like __URL_PLACEHOLDER_N__ or __PATH_PLACEHOLDER_N__
   - Content inside backticks (inline code): `command`
   - Content inside triple backticks (code blocks): ```code```
   - Lines starting with tab or 4+ spaces (these are code/output, NOT prose)
   - Technical identifiers with underscores: disable_ec2_metadata, users_groups

2. PRESERVE STRUCTURE - do not change:
   - Line breaks - each line must remain on its own line
   - Indentation - preserve all leading spaces/tabs exactly
   - Markdown formatting: #, ##, *, -, |, etc.
   - List numbering and ordering

3. ONLY FIX - these specific grammar issues:
{issue_desc}

4. NEVER ADD:
   - Backticks around ANY text (do not wrap words in backticks that weren't already in backticks)
   - Explanations, notes, or commentary
   - Text that wasn't in the original
   - Parenthetical remarks like (note: ...) or (this is ...)

5. NEVER CHANGE:
   - Capitalization of domain names (github.com stays github.com, NOT GitHub.com)
   - URL paths (Downloading-Photon-OS stays exactly as-is)
   - Technical terms even if they look misspelled

Text to fix:
{{text}}

Return ONLY the corrected text with no additional output."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def fix_markdown(self, text: str, artifacts: List[str]) -> str:
        """Fix markdown rendering artifacts.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        artifacts_str = ', '.join(artifacts[:5]) if artifacts else 'general markdown issues'
        prompt_template = f"""You are a markdown syntax correction assistant. Fix ONLY markdown rendering issues.

Issues detected: {artifacts_str}

ABSOLUTE RESTRICTIONS (violating ANY of these will break the system):

1. NEVER MODIFY THESE - copy them EXACTLY as they appear:
   - URLs (anything starting with http:// or https://)
   - Markdown link text that contains URLs: [https://github.com/...](url) - keep EXACTLY as-is
   - Domain names: github.com, gitlab.com - NEVER capitalize these
   - Placeholders like __URL_PLACEHOLDER_N__ or __PATH_PLACEHOLDER_N__
   - Lines starting with tab or 4+ spaces (these are code/output)
   - Technical identifiers with underscores: disable_ec2_metadata

2. PRESERVE STRUCTURE:
   - Line breaks - each line must remain on its own line
   - Indentation - preserve all leading spaces/tabs exactly
   - List numbering and ordering

3. MARKDOWN FIXES ALLOWED:
   - Convert ```term``` to `term` when used inline within a sentence
   - Fix unclosed code blocks
   - Fix malformed link syntax

4. NEVER ADD:
   - Backticks around ANY text (do not wrap words in backticks that weren't already in backticks)
   - Language specifiers to inline code
   - Explanations, notes, or commentary
   - Spaces inside markdown link brackets: [text] not [ text ]

5. NEVER CHANGE:
   - Capitalization of domain names (github.com stays lowercase)
   - URL paths or query strings
   - Content meaning

Text to fix:
{{text}}

Return ONLY the corrected markdown with no additional output."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def fix_indentation(self, text: str, issues: List[Dict]) -> str:
        """Fix indentation issues in markdown lists and code blocks.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        issue_desc = "\n".join([f"- {i.get('context', i.get('type', 'unknown'))}" for i in issues[:10]])
        prompt_template = f"""You are an indentation correction assistant. Fix ONLY indentation/alignment issues.

Issues detected:
{issue_desc}

ABSOLUTE RESTRICTIONS (violating ANY of these will break the system):

1. NEVER MODIFY THESE - copy them EXACTLY as they appear:
   - URLs and placeholders (__URL_PLACEHOLDER_N__)
   - Content inside backticks
   - Domain names (github.com stays lowercase)
   - All words and text content

2. ONLY ADJUST:
   - Leading whitespace (spaces/tabs at start of lines)
   - Alignment of list items and nested content

3. INDENTATION FIXES ALLOWED:
   - Align list items properly
   - Indent code blocks inside lists (4 spaces)
   - Fix inconsistent indentation
   - Align nested content under parent items

4. NEVER:
   - Change any words or text content
   - Add backticks around ANY text
   - Add or remove list items
   - Add explanations or commentary
   - Capitalize domain names

Text to fix:
{{text}}

Return ONLY the corrected markdown with no additional output."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def _clean_llm_response(self, response: str, original_text: str) -> str:
        """Clean LLM response by removing prompt leakage and validating output.
        
        This method addresses several common LLM issues:
        1. Prompt leakage: LLM sometimes includes prompt instructions in output
        2. Artifacts: Phrases like "Return only the corrected text" appearing in output
        3. Content additions: LLM adding explanatory text not in original
        4. Content alteration: LLM changing meaning of original content
        """
        if not response:
            return ""
        
        prompt_leakage_patterns = [
            r'^Return only the corrected text\.?\s*',
            r'^Return only the corrected markdown text\.?\s*',
            r'^Return only the translated text\.?\s*',
            r'^Return only the fixed markdown content\.?\s*',
            r'Return only the corrected text\.?\s*$',
            r'Return only the corrected markdown text\.?\s*$',
            r'Return only the translated text\.?\s*$',
            r'Return only the fixed markdown content\.?\s*$',
            r'^Output the (?:corrected|fixed|translated) (?:text|markdown|content).*?(?:explanation|preamble)\.?\s*',
            r'Output the (?:corrected|fixed|translated) (?:text|markdown|content).*?(?:explanation|preamble)\.?\s*$',
            r'\n+Output the (?:corrected|fixed|translated) (?:text|markdown|content).*?(?:explanation|preamble)\.?\s*$',
            r'\n*Output the corrected markdown directly without any preamble or explanation\.?\s*$',
            r'^Output the corrected markdown directly without any preamble or explanation\.?\s*\n*',
            r'^Artifacts found:.*?\n',
            r'\nArtifacts found:.*$',
            r'^Issues found:.*?\n(?:- .*\n)*',
            r'\nIssues found:.*$',
            r'^Here is the (?:corrected|fixed|translated) text:\s*\n?',
            r'^Here\'s the (?:corrected|fixed|translated) text:\s*\n?',
            r'^\*\*(?:Corrected|Fixed|Translated) (?:Text|Markdown)\*\*:?\s*\n?',
            r'^IMPORTANT RULES:.*?(?=\n\n|\n[A-Z#`])',
            r'\n*No explanations\.?\s*$',
            r'\n*no explanations\.?\s*$',
            r'(?:\n\s*)+[Ww]ithout any (?:preamble|explanation|commentary)\.?\s*$',
            r'(?:\n\s*)+without any preamble or explanation\.?\s*$',
            r'\(wait,\s*[^)]+\)',
            r'\(note:\s*[^)]+\)',
            r'\(Note:\s*[^)]+\)',
            r'\(I\'ll\s+[^)]+\)',
            r'\(I\s+will\s+[^)]+\)',
            r'\([Nn]ote\s+that\s+[^)]+\)',
            r'\([Ss]ee\s+[^)]+\)',
            r'\(this\s+is\s+[^)]+\)',
            r'\(keep\s+as\s+is[^)]*\)',
            r'\(keeping\s+[^)]+\)',
            r'\(duplicate[^)]*\)',
            r'\(original[^)]*\)',
            r'\(unchanged[^)]*\)',
            r'\(skipping[^)]*\)',
            r'\(already[^)]*\)',
            r'\n+or\s+explanation\.\s*$',
            r'^\s*or\s+explanation\.\s*$',
            r'\s*\([^)]*(?:duplicate|original|keep\s*as\s*is|I\'ll|I\s+will|note|wait|this\s+is|skipping|unchanged|already)[^)]*\)\s*',
            r'^\s*(?:Note|Wait|I\'ll|I\s+will|This\s+is|Keeping|Skipping)[^|\n]*$',
            r'\n*Output ONLY the corrected text\.?\s*Do NOT add any preamble,? explanation,? notes,? or commentary\.?\s*$',
            r'\n*Output ONLY the corrected markdown\.?\s*Do NOT add any preamble,? explanation,? notes,? or commentary\.?\s*$',
            r'\n*Output ONLY the (?:corrected|fixed|translated) (?:text|markdown|content)\.?[^\n]*(?:preamble|explanation|commentary)[^\n]*$',
        ]
        
        cleaned = response
        
        for pattern in prompt_leakage_patterns:
            cleaned = re.sub(pattern, '', cleaned, flags=re.MULTILINE | re.IGNORECASE | re.DOTALL)
        
        cleaned = cleaned.strip()
        
        if len(cleaned) < len(original_text) * 0.5:
            logging.warning("LLM response too short compared to original, using original text")
            return original_text
        
        if len(cleaned) > len(original_text) * 2:
            logging.warning("LLM response much longer than original, may contain explanations")
            lines = cleaned.split('\n')
            content_lines = []
            skip_mode = False
            for line in lines:
                if re.match(r'^(?:Explanation|Note|Changes made|Here\'s what|I (?:have )?(?:fixed|corrected)|The following):', line, re.IGNORECASE):
                    skip_mode = True
                    continue
                if skip_mode and line.strip() == '':
                    skip_mode = False
                    continue
                if not skip_mode:
                    content_lines.append(line)
            cleaned = '\n'.join(content_lines).strip()
        
        # Preserve YAML front matter - if original starts with ---, response must too
        if original_text.strip().startswith('---'):
            if not cleaned.strip().startswith('---'):
                logging.warning("LLM removed YAML front matter, using original text")
                return original_text
        
        cleaned = self._remove_llm_added_lines(cleaned, original_text)
        cleaned = self._fix_escaped_underscores(cleaned, original_text)
        cleaned = self._fix_llm_added_backticks(cleaned, original_text)
        cleaned = self._fix_markdown_link_formatting(cleaned, original_text)
        cleaned = self._fix_domain_capitalization(cleaned, original_text)
        
        return cleaned
    
    def _fix_escaped_underscores(self, response: str, original_text: str) -> str:
        """Fix incorrectly escaped underscores in technical identifiers.
        
        LLMs sometimes escape underscores (e.g., disable_ec2_metadata becomes disable\\_ec2\\_metadata).
        """
        if not response or not original_text:
            return response
        
        escaped_pattern = re.compile(r'\\(_)')
        escaped_identifier_pattern = re.compile(r'\b(\w+(?:\\_\w+)+)\b')
        
        def restore_underscore(match):
            escaped_identifier = match.group(1)
            original_identifier = escaped_identifier.replace('\\_', '_')
            if original_identifier in original_text:
                return original_identifier
            else:
                return escaped_identifier
        
        result = escaped_identifier_pattern.sub(restore_underscore, response)
        
        def restore_standalone_underscore(match):
            full_match = match.group(0)
            start = max(0, match.start() - 20)
            end = min(len(result), match.end() + 20)
            context = result[start:end]
            
            word_match = re.search(r'(\w+)\\_(\w+)', context)
            if word_match:
                potential_word = f"{word_match.group(1)}_{word_match.group(2)}"
                if potential_word in original_text:
                    return '_'
            return full_match
        
        result = escaped_pattern.sub(restore_standalone_underscore, result)
        
        return result
    
    def _fix_llm_added_backticks(self, response: str, original_text: str) -> str:
        """Remove backticks that the LLM incorrectly added around words.
        
        LLMs sometimes add backticks around technical terms like systemd, Kubernetes, etc.
        even when instructed not to. This function detects and removes such additions.
        
        Also fixes spaces inside backticks (e.g., `systemd ` -> systemd).
        """
        if not response or not original_text:
            return response
        
        result = response
        
        # Pattern to find inline code: `word` or ` word` or `word ` or ` word `
        inline_code_pattern = re.compile(r'`\s*([^`\n]+?)\s*`')
        
        def check_and_fix_backticks(match):
            full_match = match.group(0)
            content = match.group(1).strip()
            
            # If this exact backtick pattern exists in original, keep it
            if full_match in original_text:
                return full_match
            
            # If the content (without backticks) was already in backticks in original, keep backticks
            proper_backtick = f'`{content}`'
            if proper_backtick in original_text:
                return proper_backtick
            
            # If the content appears without backticks in original, remove backticks
            # Check if the word appears as plain text (not in backticks) in original
            # Use word boundary check to avoid false matches
            plain_pattern = re.compile(r'(?<!`)\b' + re.escape(content) + r'\b(?!`)')
            if plain_pattern.search(original_text):
                logging.warning(f"Removing LLM-added backticks around: {content}")
                return content
            
            # If content has spaces inside (malformed), and original had proper backticks, fix it
            if ' ' in match.group(0).strip('`'):
                if proper_backtick in original_text:
                    return proper_backtick
            
            # Default: keep as-is if we can't determine
            return full_match
        
        result = inline_code_pattern.sub(check_and_fix_backticks, result)
        
        return result
    
    def _remove_llm_added_lines(self, response: str, original_text: str) -> str:
        """Remove lines that appear to be LLM-added commentary.
        
        CRITICAL: LLM must NEVER add ANY text that wasn't in the original.
        """
        if not response or not original_text:
            return response
        
        original_words = set(re.findall(r'\b[a-zA-Z]{4,}\b', original_text.lower()))
        
        commentary_indicators = [
            r'^\s*\(.*\)\s*$',
            r'wait,?\s+this',
            r'i\'ll\s+keep',
            r'keeping\s+as\s+is',
            r'this\s+is\s+a\s+duplicate',
            r'note\s*:',
            r'or\s+explanation\.',
            r'^\s*$',
        ]
        
        lines = response.split('\n')
        result_lines = []
        
        for line in lines:
            line_lower = line.lower().strip()
            
            if not line_lower:
                result_lines.append(line)
                continue
            
            is_commentary = False
            for pattern in commentary_indicators:
                if re.search(pattern, line_lower):
                    if not re.search(pattern, original_text.lower()):
                        is_commentary = True
                        logging.warning(f"Removing LLM-added commentary: {line[:80]}...")
                        break
            
            if is_commentary:
                continue
            
            line_words = set(re.findall(r'\b[a-zA-Z]{4,}\b', line_lower))
            if line_words:
                overlap = line_words & original_words
                overlap_ratio = len(overlap) / len(line_words) if line_words else 0
                
                if overlap_ratio < 0.2 and not line.strip().startswith(('```', '`', '#', '-', '*', '|')):
                    if re.match(r'^\s*[A-Z].*[.!?]\s*$', line) or re.match(r'^\s*\(.*\)\s*$', line):
                        logging.warning(f"Removing likely LLM-added line (low overlap): {line[:80]}...")
                        continue
            
            result_lines.append(line)
        
        return '\n'.join(result_lines)
    
    def _fix_markdown_link_formatting(self, response: str, original_text: str) -> str:
        """Fix markdown link text formatting issues caused by LLM.
        
        LLMs sometimes add spaces after [ in markdown links when the link text
        starts with a backtick.
        """
        if not response:
            return response
        
        space_after_bracket_pattern = re.compile(r'\[\s+(`[^`]+`[^\]]*)\]\(([^)]+)\)')
        
        def fix_link(match):
            link_text = match.group(1)
            url = match.group(2)
            return f'[{link_text}]({url})'
        
        result = space_after_bracket_pattern.sub(fix_link, response)
        
        space_before_bracket_pattern = re.compile(r'\[([^\]]*`[^`]+`)\s+\]\(([^)]+)\)')
        result = space_before_bracket_pattern.sub(r'[\1](\2)', result)
        
        return result
    
    def _fix_domain_capitalization(self, response: str, original_text: str) -> str:
        """Fix incorrect domain capitalization in link text caused by LLM.
        
        LLMs sometimes capitalize domain names like github.com to GitHub.com
        in link text, which is incorrect.
        """
        if not response or not original_text:
            return response
        
        domain_corrections = {
            'GitHub.com': 'github.com',
            'GitLab.com': 'gitlab.com',
            'BitBucket.org': 'bitbucket.org',
            'SourceForge.net': 'sourceforge.net',
        }
        
        result = response
        
        for incorrect, correct in domain_corrections.items():
            if incorrect in result or incorrect.lower() != incorrect and re.search(re.escape(incorrect), result, re.IGNORECASE):
                link_text_pattern = re.compile(
                    r'\[([^\]]*?)' + re.escape(incorrect) + r'([^\]]*?)\](\([^)]+\))',
                    re.IGNORECASE
                )
                result = link_text_pattern.sub(
                    lambda m: f'[{m.group(1)}{correct}{m.group(2)}]{m.group(3)}',
                    result
                )
                
                standalone_pattern = re.compile(
                    r'(?<!\()' + re.escape(incorrect) + r'(/[\w./-]*)',
                    re.IGNORECASE
                )
                result = standalone_pattern.sub(correct + r'\1', result)
                
                result = re.sub(
                    r'(?<!\()' + re.escape(incorrect) + r'(?![^[]*\])',
                    correct,
                    result,
                    flags=re.IGNORECASE
                )
        
        return result
    
    def _generate(self, prompt: str) -> str:
        """Generate response from LLM."""
        try:
            if self.provider == "gemini":
                response = self.model.generate_content(prompt)
                return response.text
            elif self.provider == "xai":
                return self._xai_generate(prompt)
        except Exception as e:
            logging.error(f"LLM generation failed: {e}")
            return ""
    
    def _xai_generate(self, prompt: str) -> str:
        """Generate response using xAI API (OpenAI-compatible)."""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": self.xai_model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 131072
        }
        try:
            response = requests.post(self.xai_endpoint, headers=headers, json=payload, timeout=60)
            response.raise_for_status()
            data = response.json()
            return data.get("choices", [{}])[0].get("message", {}).get("content", "")
        except Exception as e:
            logging.error(f"xAI API call failed: {e}")
            return ""
