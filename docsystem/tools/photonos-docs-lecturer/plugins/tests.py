#!/usr/bin/env python3
"""
Unit Tests for Photon OS Documentation Lecturer

This module contains all unit tests for the documentation lecturer tool,
including tests for URL validation, fix parsing, pattern matching, and
various fix functions.

Usage:
    python3 tests.py
    
    Or from the main tool:
    python3 photonos-docs-lecturer.py test
"""

import os
import sys
import unittest
import tempfile
import shutil

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run_tests():
    """Run unit tests."""
    # Lazy import to avoid circular dependencies and allow standalone execution
    from photonos_docs_lecturer import (
        DocumentationLecturer,
        LLMClient,
        validate_url,
        validate_parallel,
        check_and_import_dependencies,
    )
    import argparse
    
    # Ensure dependencies are loaded
    check_and_import_dependencies()
    from bs4 import BeautifulSoup
    
    class TestDocumentationLecturer(unittest.TestCase):
        def test_validate_url(self):
            self.assertEqual(validate_url("https://example.com"), "https://example.com")
            self.assertEqual(validate_url("example.com"), "https://example.com")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_url("")
        
        def test_validate_parallel(self):
            self.assertEqual(validate_parallel("5"), 5)
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("0")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("25")
        
        def test_parse_fix_spec(self):
            """Test --fix parameter parsing."""
            parse = DocumentationLecturer.parse_fix_spec
            
            # Test single fix ID
            result = parse("1")
            self.assertEqual(result, {1})
            
            # Test multiple single fix IDs
            result = parse("1,2,3")
            self.assertEqual(result, {1, 2, 3})
            
            # Test range (use valid IDs within current FIX_TYPES)
            result = parse("5-8")
            self.assertEqual(result, {5, 6, 7, 8})
            
            # Test mixed single and range
            result = parse("1,3,5-7")
            self.assertEqual(result, {1, 3, 5, 6, 7})
            
            # Test 'all' keyword
            result = parse("all")
            self.assertEqual(result, set(DocumentationLecturer.FIX_TYPES.keys()))
            
            # Test None/empty returns all
            result = parse(None)
            self.assertEqual(result, set(DocumentationLecturer.FIX_TYPES.keys()))
            
            # Test with spaces
            result = parse("1, 2, 3")
            self.assertEqual(result, {1, 2, 3})
            
            # Test invalid fix ID
            with self.assertRaises(ValueError):
                parse("99")
            
            # Test invalid range (start > end)
            with self.assertRaises(ValueError):
                parse("9-5")
            
            # Test invalid format
            with self.assertRaises(ValueError):
                parse("abc")
        
        def test_parse_feature_spec(self):
            """Test --feature parameter parsing."""
            parse = DocumentationLecturer.parse_feature_spec
            
            # Test single feature ID
            result = parse("1")
            self.assertEqual(result, {1})
            
            # Test multiple feature IDs
            result = parse("1,2")
            self.assertEqual(result, {1, 2})
            
            # Test range
            result = parse("1-2")
            self.assertEqual(result, {1, 2})
            
            # Test 'all' keyword
            result = parse("all")
            self.assertEqual(result, set(DocumentationLecturer.FEATURE_TYPES.keys()))
            
            # Test None/empty returns all
            result = parse(None)
            self.assertEqual(result, set(DocumentationLecturer.FEATURE_TYPES.keys()))
            
            # Test invalid feature ID
            with self.assertRaises(ValueError):
                parse("99")
            
            # Test invalid format
            with self.assertRaises(ValueError):
                parse("abc")
        
        def test_markdown_patterns(self):
            patterns = DocumentationLecturer.MARKDOWN_PATTERNS
            test_text = "## Header\n* bullet\n[link](url)"
            for pattern in patterns[:3]:
                self.assertTrue(pattern.search(test_text))
        
        def test_missing_space_before_backtick(self):
            pattern = DocumentationLecturer.MISSING_SPACE_BEFORE_BACKTICK
            # Should match: word immediately followed by backtick code
            self.assertTrue(pattern.search("Clone`the`"))
            self.assertTrue(pattern.search("Run`command`"))
            # Should not match: proper spacing
            self.assertIsNone(pattern.search("Clone `the`"))
            self.assertIsNone(pattern.search("Run `command`"))
            # Should not match: inline code with space inside (invalid markdown)
            self.assertIsNone(pattern.search("Clone` the`"))
            # Critical bug fix test: should NOT match across multiple inline code blocks
            # In "The `top` tool and command`ps`", the pattern should only match "d`ps`"
            # and NOT match "p` tool and command`" (which would corrupt `top`)
            test_multi = "The `top` tool and command`ps` here"
            matches = pattern.findall(test_multi)
            self.assertEqual(len(matches), 1, "Should find exactly one match")
            self.assertEqual(matches[0], ('d', '`ps`'), "Should match 'd`ps`' not spanning across `top`")
        
        def test_missing_space_after_backtick(self):
            pattern = DocumentationLecturer.MISSING_SPACE_AFTER_BACKTICK
            # Should match: backtick code immediately followed by word
            self.assertTrue(pattern.search("`command`and"))
            self.assertTrue(pattern.search("`code`text"))
            # Should not match: proper spacing
            self.assertIsNone(pattern.search("`command` and"))
            self.assertIsNone(pattern.search("`code` text"))
            # Should not match: inline code with space inside (invalid markdown)
            self.assertIsNone(pattern.search("` command`and"))
            # Critical bug fix test: should NOT match across multiple inline code blocks
            test_multi = "Use `cmd1`and `cmd2` here"
            matches = pattern.findall(test_multi)
            self.assertEqual(len(matches), 1, "Should find exactly one match")
            self.assertEqual(matches[0], ('`cmd1`', 'a'), "Should match '`cmd1`a' not spanning blocks")
        
        def test_shell_prompt_patterns(self):
            patterns = DocumentationLecturer.SHELL_PROMPT_PATTERNS
            # Test "$ command" pattern (first pattern)
            # Pattern groups: (1) leading whitespace, (2) prompt, (3) command
            dollar_pattern = patterns[0]
            match = dollar_pattern.match("$ ls -la")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")  # no leading whitespace
            self.assertEqual(match.group(2), "$ ")
            self.assertEqual(match.group(3), "ls -la")
            
            # Test with indentation (tabs before $)
            match = dollar_pattern.match("\t$ tar -zxvf file.tar.gz")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "\t")  # leading tab
            self.assertEqual(match.group(2), "$ ")
            self.assertEqual(match.group(3), "tar -zxvf file.tar.gz")
            
            # Note: "# command" pattern was removed - # in code blocks are comments, not prompts
            # Verify that "# comment" lines are NOT matched by any pattern
            for pattern in patterns:
                self.assertIsNone(pattern.match("# This is a comment"))
            
            # Test "❯ command" pattern (fancy prompt like starship/powerline)
            fancy_pattern = patterns[4]  # index adjusted after removing # pattern
            match = fancy_pattern.match("❯ sudo wg show")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")
            self.assertEqual(match.group(2), "❯ ")
            self.assertEqual(match.group(3), "sudo wg show")
            
            # Test without space after ❯
            match = fancy_pattern.match("❯wg genkey")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")
            self.assertEqual(match.group(2), "❯")
            self.assertEqual(match.group(3), "wg genkey")
            
            # Test "➜  command" pattern (Oh My Zsh robbyrussell theme)
            omz_pattern = patterns[5]  # index adjusted
            match = omz_pattern.match("➜  git status")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")
            self.assertEqual(match.group(2), "➜  ")
            self.assertEqual(match.group(3), "git status")
            
            # Should not match lines without prompts
            self.assertIsNone(dollar_pattern.match("ls -la"))
            self.assertIsNone(dollar_pattern.match("echo hello"))
        
        def test_strip_code_from_text(self):
            # Create a minimal mock args object for testing
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test removal of fenced code blocks
            text_with_code_block = "This is text ```python\nprint('hello')\n``` and more text"
            result = lecturer._strip_code_from_text(text_with_code_block)
            self.assertNotIn("print", result)
            self.assertIn("This is text", result)
            self.assertIn("and more text", result)
            
            # Test removal of inline code
            text_with_inline = "Run the `ls -la` command to list files"
            result = lecturer._strip_code_from_text(text_with_inline)
            self.assertNotIn("ls -la", result)
            self.assertIn("Run the", result)
            self.assertIn("command to list files", result)
            
            # Test mixed content
            text_mixed = "Use `export VAR=value` and ```bash\necho $VAR\n``` to set variables"
            result = lecturer._strip_code_from_text(text_mixed)
            self.assertNotIn("export", result)
            self.assertNotIn("echo", result)
            self.assertIn("Use", result)
            self.assertIn("to set variables", result)
            
            lecturer.cleanup()
        
        def test_deprecated_vmware_url_pattern(self):
            pattern = DocumentationLecturer.DEPRECATED_VMWARE_URL
            # Should match deprecated VMware package URLs
            self.assertIsNotNone(pattern.match("https://packages.vmware.com/photon/"))
            self.assertIsNotNone(pattern.match("https://packages.vmware.com/photon/4.0/"))
            self.assertIsNotNone(pattern.match("http://packages.vmware.com/tools/"))
            # Should not match other URLs
            self.assertIsNone(pattern.match("https://vmware.com/"))
            self.assertIsNone(pattern.match("https://packages.broadcom.com/"))
        
        def test_vmware_spelling_pattern(self):
            pattern = DocumentationLecturer.VMWARE_SPELLING_PATTERN
            # Should match incorrect spellings
            self.assertIsNotNone(pattern.search("vmware"))
            self.assertIsNotNone(pattern.search("Vmware"))
            self.assertIsNotNone(pattern.search("VMWare"))
            self.assertIsNotNone(pattern.search("VMWARE"))
            self.assertIsNotNone(pattern.search("VmWare"))
            # Should NOT match correct spelling
            self.assertIsNone(pattern.search("VMware"))
            self.assertIsNone(pattern.search("Use VMware products"))
        
        def test_markdown_header_no_space_pattern(self):
            pattern = DocumentationLecturer.MARKDOWN_HEADER_NO_SPACE
            # Should match headers without space
            match = pattern.search("####Install Google cloud SDK")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "####")
            self.assertEqual(match.group(2), "Install Google cloud SDK")
            
            match = pattern.search("###Subtitle without space")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "###")
            
            match = pattern.search("##Section")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "##")
            
            # Should NOT match headers with proper space
            self.assertIsNone(pattern.search("#### Install with space"))
            self.assertIsNone(pattern.search("### Proper subtitle"))
            self.assertIsNone(pattern.search("## Correct section"))
        
        def test_fix_markdown_header_spacing(self):
            """Test markdown header spacing fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test basic fix
            content = "####Install Google cloud SDK"
            fixed = lecturer._fix_markdown_header_spacing(content)
            self.assertEqual(fixed, "#### Install Google cloud SDK")
            
            # Test multiple headers
            content = """### GCE

The tar file can be uploaded to Google's cloud storage.

####Install Google cloud SDK on host machine

Some content here.

###Another section"""
            fixed = lecturer._fix_markdown_header_spacing(content)
            self.assertIn("#### Install Google cloud SDK on host machine", fixed)
            self.assertIn("### Another section", fixed)
            self.assertNotIn("####Install", fixed)
            self.assertNotIn("###Another", fixed)
            
            # Test that properly spaced headers are not modified
            content = "### Proper Header\n\n#### Another Header"
            fixed = lecturer._fix_markdown_header_spacing(content)
            self.assertEqual(content, fixed)
            
            lecturer.cleanup()
        
        def test_fix_html_comments(self):
            """Test HTML comment removal while preserving inner content."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test single-line comment
            content = "Some text\n\n<!-- Azure - A vhd file -->\n\nMore text"
            fixed = lecturer._fix_html_comments(content)
            self.assertIn("Azure - A vhd file", fixed)
            self.assertNotIn("<!--", fixed)
            self.assertNotIn("-->", fixed)
            
            # Test multi-line comment
            content = """Some text

<!-- ###How to build Photon bosh-stemcell

Please follow the link to build Photon bosh-stemcell
-->

More text"""
            fixed = lecturer._fix_html_comments(content)
            self.assertIn("###How to build Photon bosh-stemcell", fixed)
            self.assertIn("Please follow the link to build Photon bosh-stemcell", fixed)
            self.assertNotIn("<!--", fixed)
            self.assertNotIn("-->", fixed)
            
            # Test that code blocks are NOT modified
            content = """Some text

```html
<!-- This is a code example comment -->
<div>Content</div>
```

More text"""
            fixed = lecturer._fix_html_comments(content)
            self.assertIn("<!-- This is a code example comment -->", fixed)
            
            lecturer.cleanup()
        
        def test_mixed_command_output_detection(self):
            """Test detection of mixed command and output in code blocks."""
            # Create a minimal mock args object for testing
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test case 1: Mixed command with config output (should detect)
            html_mixed = '''
            <pre>sudo cat /etc/photon-mgmt/mgmt.toml
[System]
LogLevel="info"
UseAuthentication="false"

[Network]
ListenUnixSocket="true"</pre>
            '''
            soup = BeautifulSoup(html_mixed, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertGreater(len(issues), 0, "Should detect mixed command and output")
            self.assertEqual(issues[0]['type'], 'mixed_command_output')
            
            # Test case 2: Command only (should NOT detect)
            html_command_only = '''
            <pre>sudo systemctl restart nginx</pre>
            '''
            soup = BeautifulSoup(html_command_only, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertEqual(len(issues), 0, "Should not flag command-only code blocks")
            
            # Test case 3: Output only (should NOT detect)
            html_output_only = '''
            <pre>[System]
LogLevel="info"
UseAuthentication="false"</pre>
            '''
            soup = BeautifulSoup(html_output_only, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertEqual(len(issues), 0, "Should not flag output-only code blocks")
            
            # Test case 4: ls command with output (should detect)
            html_ls_output = '''
            <pre>ls -la /var/log
total 1234
drwxr-xr-x  2 root root 4096 Nov 30 10:00 .
drwxr-xr-x 14 root root 4096 Nov 30 10:00 ..
-rw-r--r--  1 root root 1234 Nov 30 10:00 syslog</pre>
            '''
            soup = BeautifulSoup(html_ls_output, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertGreater(len(issues), 0, "Should detect ls command with output")
            
            lecturer.cleanup()
        
        def test_llm_url_protection(self):
            """Test URL protection mechanism for LLM calls.
            
            Bug fix: LLMs sometimes modify URLs despite explicit instructions,
            such as removing .md extensions from GitHub links. The URL protection
            mechanism replaces URLs with placeholders before LLM calls and restores
            them afterwards.
            """
            # Test the LLMClient URL protection directly (without actual LLM calls)
            # Create a mock LLMClient to test _protect_urls and _restore_urls
            
            # Test _protect_urls
            text = """The GCE-ready version of Photon OS is licensed as described in the Photon OS [LICENSE guide](https://github.com/vmware/photon/blob/master/LICENSE.md).

See also [documentation](https://docs.example.com/guide.html) and visit https://example.com/path/file.pdf for more info."""
            
            protected, url_map = LLMClient._protect_urls(LLMClient, text)
            
            # Check that URLs are replaced with placeholders
            self.assertNotIn("https://github.com/vmware/photon/blob/master/LICENSE.md", protected)
            self.assertNotIn("https://docs.example.com/guide.html", protected)
            self.assertNotIn("https://example.com/path/file.pdf", protected)
            
            # Check that placeholders are present
            self.assertIn("__URL_PLACEHOLDER_0__", protected)
            self.assertIn("__URL_PLACEHOLDER_1__", protected)
            self.assertIn("__URL_PLACEHOLDER_2__", protected)
            
            # Check that link text is preserved
            self.assertIn("[LICENSE guide]", protected)
            self.assertIn("[documentation]", protected)
            
            # Check url_map contains the original URLs
            self.assertEqual(len(url_map), 3)
            self.assertIn("https://github.com/vmware/photon/blob/master/LICENSE.md", url_map.values())
            self.assertIn("https://docs.example.com/guide.html", url_map.values())
            self.assertIn("https://example.com/path/file.pdf", url_map.values())
            
            # Test _restore_urls
            restored = LLMClient._restore_urls(LLMClient, protected, url_map)
            
            # Check that original URLs are restored
            self.assertIn("https://github.com/vmware/photon/blob/master/LICENSE.md", restored)
            self.assertIn("https://docs.example.com/guide.html", restored)
            self.assertIn("https://example.com/path/file.pdf", restored)
            
            # Check that the full markdown links are intact
            self.assertIn("[LICENSE guide](https://github.com/vmware/photon/blob/master/LICENSE.md)", restored)
            self.assertIn("[documentation](https://docs.example.com/guide.html)", restored)
            
            # Check that placeholders are removed
            self.assertNotIn("__URL_PLACEHOLDER_", restored)
            
            # The restored text should match the original
            self.assertEqual(text, restored)
        
        def test_llm_prompt_leakage_cleaning(self):
            """Test that prompt leakage is properly cleaned from LLM responses.
            
            Bug fix: LLMs sometimes include prompt instructions in their output,
            such as "Output the corrected markdown directly without any preamble or explanation."
            The _clean_llm_response method should remove these artifacts.
            """
            # Create a mock LLMClient instance to test _clean_llm_response
            class MockLLMClient:
                def _remove_llm_added_lines(self, response, original_text):
                    return LLMClient._remove_llm_added_lines(self, response, original_text)
                def _fix_escaped_underscores(self, response, original_text):
                    return LLMClient._fix_escaped_underscores(self, response, original_text)
                def _fix_markdown_link_formatting(self, response, original_text):
                    return LLMClient._fix_markdown_link_formatting(self, response, original_text)
                def _fix_domain_capitalization(self, response, original_text):
                    return LLMClient._fix_domain_capitalization(self, response, original_text)
            
            mock_client = MockLLMClient()
            
            original_text = """# Test Content

Some markdown content here.

| Name | Value |
|------|-------|
| test | 123   |"""
            
            # Test case 1: Prompt instruction at end of response
            response_with_leakage = original_text + "\n\nOutput the corrected markdown directly without any preamble or explanation."
            cleaned = LLMClient._clean_llm_response(mock_client, response_with_leakage, original_text)
            self.assertNotIn("Output the corrected markdown", cleaned)
            self.assertIn("# Test Content", cleaned)
            self.assertIn("| test | 123   |", cleaned)
            
            # Test case 2: "Return only" instruction at end
            response_with_leakage = original_text + "\n\nReturn only the corrected text."
            cleaned = LLMClient._clean_llm_response(mock_client, response_with_leakage, original_text)
            self.assertNotIn("Return only", cleaned)
            
            # Test case 3: "without any preamble" fragment
            response_with_leakage = original_text + "\n\nwithout any preamble or explanation."
            cleaned = LLMClient._clean_llm_response(mock_client, response_with_leakage, original_text)
            self.assertNotIn("without any preamble", cleaned)
            
            # Test case 4: Clean response should pass through unchanged
            clean_response = original_text
            cleaned = LLMClient._clean_llm_response(mock_client, clean_response, original_text)
            self.assertEqual(cleaned, original_text)
        
        def test_llm_relative_path_protection(self):
            """Test relative path protection mechanism for LLM calls.
            
            Relative paths like 'troubleshooting-guide/solutions-to-common-problems/page'
            should be protected from LLM modification.
            """
            # Test text with relative paths
            text = """For more information, see troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh.

Also check ../administration-guide/security-policy/default-firewall-settings for firewall configuration.

The file is located at ./path/to/file.md in the repository."""
            
            protected, url_map = LLMClient._protect_urls(LLMClient, text)
            
            # Check that relative paths are replaced with placeholders
            self.assertNotIn("troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh", protected)
            self.assertNotIn("../administration-guide/security-policy/default-firewall-settings", protected)
            self.assertNotIn("./path/to/file.md", protected)
            
            # Check that placeholders are present
            self.assertIn("__PATH_PLACEHOLDER_", protected)
            
            # Check url_map contains the original paths
            self.assertIn("troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh", url_map.values())
            self.assertIn("../administration-guide/security-policy/default-firewall-settings", url_map.values())
            self.assertIn("./path/to/file.md", url_map.values())
            
            # Test _restore_urls
            restored = LLMClient._restore_urls(LLMClient, protected, url_map)
            
            # Check that original paths are restored
            self.assertIn("troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh", restored)
            self.assertIn("../administration-guide/security-policy/default-firewall-settings", restored)
            self.assertIn("./path/to/file.md", restored)
            
            # Check that placeholders are removed
            self.assertNotIn("__PATH_PLACEHOLDER_", restored)
            
            # The restored text should match the original
            self.assertEqual(text, restored)
        
        def test_fix_vmware_spelling(self):
            """Test VMware spelling fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test basic fixes
            content = "Install vmware tools and Vmware Workstation"
            fixed = lecturer._fix_vmware_spelling(content)
            self.assertEqual(fixed, "Install VMware tools and VMware Workstation")
            
            # Test that code blocks are preserved
            content = "Use `vmware` command and vmware products"
            fixed = lecturer._fix_vmware_spelling(content)
            self.assertIn("`vmware`", fixed)  # Code should be unchanged
            self.assertIn("VMware products", fixed)  # Text should be fixed
            
            lecturer.cleanup()
        
        def test_fix_deprecated_urls(self):
            """Test deprecated URL fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test URL replacement
            content = "Download from https://packages.vmware.com/photon/5.0/"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("packages.broadcom.com", fixed)
            self.assertIn("/photon/5.0/", fixed)  # Path should be preserved
            self.assertNotIn("packages.vmware.com", fixed)
            
            # Test bosh-stemcell URL replacement (old repo moved to bosh-linux-stemcell-builder)
            content = "Please follow the link to [build](https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md) Photon bosh-stemcell"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("https://github.com/cloudfoundry/bosh-linux-stemcell-builder", fixed)
            self.assertNotIn("blob/develop/bosh-stemcell/README.md", fixed)
            
            # Test deprecated VDDK URL replacement (developercenter.vmware.com) with full link text update
            content = "[VDDK 6.0](https://developercenter.vmware.com/web/sdk/60/vddk)"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertEqual(fixed, "[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)")
            self.assertNotIn("developercenter.vmware.com", fixed)
            self.assertNotIn("VDDK 6.0", fixed)
            
            # Test deprecated VDDK URL replacement (my.vmware.com)
            content = "[VDDK](https://my.vmware.com/web/vmware/downloads/details?downloadGroup=VDDK670&productId=742)"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7", fixed)
            self.assertNotIn("my.vmware.com", fixed)
            
            # Test deprecated OVFTOOL URL replacement
            content = "[OVFTOOL](https://my.vmware.com/group/vmware/details?downloadGroup=OVFTOOL410&productId=491)"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest", fixed)
            self.assertNotIn("my.vmware.com/group/vmware/details", fixed)
            
            lecturer.cleanup()
        
        def test_fix_broken_email_addresses(self):
            """Test broken email address fix function.
            
            Bug fix: Email addresses in console output may be broken with whitespace
            when long lines are wrapped, e.g., "linux-packages@vmware.     com"
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test basic broken email fix
            content = "Summary     : gpg(VMware, Inc. -- Linux Packaging Key -- <linux-packages@vmware.                        com>)"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertIn("linux-packages@vmware.com", fixed)
            self.assertNotIn("vmware.                        com", fixed)
            
            # Test multiple whitespace patterns
            content = "Contact: user@example.   org for support"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertIn("user@example.org", fixed)
            self.assertNotIn("example.   org", fixed)
            
            # Test with newline in domain
            content = "Email: admin@company.\nnet"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertIn("admin@company.net", fixed)
            
            # Test that normal emails are not modified
            content = "Contact linux-packages@vmware.com for help"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertEqual(content, fixed)  # Should be unchanged
            
            lecturer.cleanup()
        
        def test_vmware_spelling_excludes_broken_emails(self):
            """Test that VMware spelling check excludes broken email addresses.
            
            The 'vmware' in 'linux-packages@vmware.     com' should NOT be flagged
            as a spelling issue because it's part of an email domain.
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Broken email - vmware should NOT be flagged
            content = "Summary: gpg(VMware, Inc. -- <linux-packages@vmware.                        com>)"
            issues = lecturer._check_vmware_spelling("https://test.com", content)
            # Should have 0 issues - the vmware in the broken email should be excluded
            self.assertEqual(len(issues), 0, 
                "vmware in broken email 'linux-packages@vmware.     com' should not be flagged")
            
            # Normal email - vmware should NOT be flagged
            content = "Contact linux-packages@vmware.com for support"
            issues = lecturer._check_vmware_spelling("https://test.com", content)
            self.assertEqual(len(issues), 0, 
                "vmware in normal email should not be flagged")
            
            # Regular text with incorrect spelling - SHOULD be flagged
            content = "Install vmware tools on the system"
            issues = lecturer._check_vmware_spelling("https://test.com", content)
            self.assertGreater(len(issues), 0, 
                "vmware in regular text should be flagged")
            
            lecturer.cleanup()
        
        def test_fix_backtick_spacing(self):
            """Test backtick spacing fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test missing space before backtick
            content = "Run the command`ls`"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "Run the command `ls`")
            
            # Test missing space after backtick
            content = "`command`and then"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "`command` and then")
            
            # Test that properly spaced inline code is not modified
            content = "The `top` tool monitors system resources"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "The `top` tool monitors system resources")
            
            # Critical bug fix test: multiple inline codes on same line
            # Should only fix the actual issue, not corrupt other inline codes
            content = "The `top` tool and command`ps` here"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "The `top` tool and command `ps` here")
            self.assertIn("`top`", fixed, "The `top` inline code should remain unchanged")
            self.assertNotIn("` top `", fixed, "Should not add spaces inside `top`")
            self.assertNotIn("`top `", fixed, "Should not add trailing space inside `top`")
            
            # Test multiline content - should not match across lines
            content = "First `code` line\nSecond`code2` line"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "First `code` line\nSecond `code2` line")
            
            # Test URL in backticks - backticks should be removed entirely
            # URLs should not be wrapped in inline code backticks
            content = "See`https://github.com/vmware/photon/tree/master/SPECS`for details"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "See https://github.com/vmware/photon/tree/master/SPECS for details")
            self.assertNotIn("`", fixed, "Backticks should be removed from URLs")
            
            # Test URL with only missing space before
            content = "Visit`https://example.com/path`"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "Visit https://example.com/path")
            
            # Test URL with only missing space after
            content = "`https://example.com/path`here"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "https://example.com/path here")
            
            # Test stray backtick typo fix (backtick should become space)
            # "Clone`the" should become "Clone the" when there's no closing backtick
            content = "3.  Clone`the Photon project:"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "3.  Clone the Photon project:")
            
            # Stray backtick should NOT affect valid inline code
            content = "Run `command` and Clone`the project"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertIn("`command`", fixed, "Valid inline code should be preserved")
            self.assertIn("Clone the project", fixed, "Stray backtick should be replaced with space")
            
            # Test stray backtick before punctuation (LLM artifact)
            # "network ID`." should become "network ID."
            content = "associate the network with a network ID`. "
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "associate the network with a network ID. ")
            
            # Test stray backtick before various punctuation marks
            content = "word`, and word`; also word`!"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "word, and word; also word!")
            
            # Stray backtick before punct should NOT affect valid inline code
            content = "Use `command`, and also `another`."
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "Use `command`, and also `another`.")
            self.assertIn("`command`", fixed, "Valid inline code before comma should be preserved")
            self.assertIn("`another`", fixed, "Valid inline code before period should be preserved")
            
            # Edge case: stray backtick after valid inline code
            content = "`cmd` output`."
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "`cmd` output.")
            
            lecturer.cleanup()
        
        def test_fix_fenced_inline_code(self):
            """Test conversion of fenced code blocks back to inline code when part of a sentence.
            
            Bug fix: LLMs sometimes convert inline code like `cloud-init` to fenced code blocks
            like ```bash\ncloud-init\n``` when fixing markdown. This is wrong when the code
            is part of a sentence. This fix converts such patterns back to inline code.
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test: fenced code block at start of sentence should become inline code
            content = "```bash\ncloud-init\n``` is a multi-distribution package."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "`cloud-init` is a multi-distribution package.")
            
            # Test: fenced code block with "turned" continuation
            content = "The ```bash\nec2 datasource\n``` turned on by default."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "The `ec2 datasource` turned on by default.")
            
            # Test: fenced code block without language specifier
            content = "```\nnocloud\n``` data source is used."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "`nocloud` data source is used.")
            
            # Test: fenced code block ending with punctuation (period)
            content = "The hostname is set to ```bash\ntesthost\n```."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "The hostname is set to `testhost`.")
            
            # Test: actual multi-line code block should NOT be converted
            content = "```bash\necho hello\necho world\n```"
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertIn("```bash", fixed, "Multi-line code block should remain fenced")
            self.assertIn("echo hello", fixed)
            
            # Test: fenced code block without sentence continuation should NOT be converted
            content = "```bash\ncloud-init\n```\n\nSome other paragraph."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertIn("```bash", fixed, "Standalone fenced block should remain fenced")
            
            lecturer.cleanup()
        
        def test_fix_triple_backtick_inline(self):
            """Test conversion of triple backticks used as inline code to single backticks.
            
            Bug fix: Source markdown sometimes uses ```term``` instead of `term` for inline code.
            This should be converted to single backticks.
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test: triple backticks on same line should become single backticks
            content = "```cloud-init``` is a multi-distribution package."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "`cloud-init` is a multi-distribution package.")
            
            # Test: multiple instances of triple backtick inline
            content = "The ```ec2``` datasource and ```nocloud``` are both supported."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "The `ec2` datasource and `nocloud` are both supported.")
            
            # Test: triple backticks with hyphenated term
            content = "Use ```ec2-datasource``` for Amazon."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "Use `ec2-datasource` for Amazon.")
            
            # Test: triple backticks with two words
            content = "Has ```ec2 datasource``` turned on."
            fixed = lecturer._fix_malformed_code_blocks(content)
            self.assertEqual(fixed, "Has `ec2 datasource` turned on.")
            
            lecturer.cleanup()
        
        def test_fix_escaped_underscores(self):
            """Test restoration of incorrectly escaped underscores in LLM responses.
            
            Bug fix: LLMs sometimes escape underscores in technical identifiers
            like disable_ec2_metadata -> disable\\_ec2\\_metadata. This is wrong.
            """
            # Test the _fix_escaped_underscores method directly via LLMClient
            original_text = """Module Frequency Info
------------------------------------
Name                  |  Frequency
----------------------|-------------
disable_ec2_metadata  | Always
users_groups          | Instance
write_files           | Instance
update_hostname       | Always"""
            
            # Simulate LLM response with escaped underscores
            llm_response = """Module Frequency Info
------------------------------------
Name                  |  Frequency
----------------------|-------------
disable\\_ec2\\_metadata  | Always
users\\_groups          | Instance
write\\_files           | Instance
update_hostname       | Always"""
            
            # Create LLMClient mock to test _fix_escaped_underscores
            class MockLLMClient:
                pass
            
            client = MockLLMClient()
            # Access the method via LLMClient class
            fixed = LLMClient._fix_escaped_underscores(client, llm_response, original_text)
            
            # Verify escaped underscores are restored
            self.assertIn("disable_ec2_metadata", fixed)
            self.assertIn("users_groups", fixed)
            self.assertIn("write_files", fixed)
            self.assertNotIn("disable\\_ec2\\_metadata", fixed)
            self.assertNotIn("users\\_groups", fixed)
            self.assertNotIn("write\\_files", fixed)
        
        def test_fix_shell_prompts_in_markdown(self):
            """Test shell prompt removal from markdown code blocks."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test $ prompt removal
            content = "```bash\n$ ls -la\n$ echo hello\n```"
            fixed = lecturer._fix_shell_prompts_in_markdown(content)
            self.assertIn("ls -la", fixed)
            self.assertIn("echo hello", fixed)
            self.assertNotIn("$ ls", fixed)
            self.assertNotIn("$ echo", fixed)
            
            lecturer.cleanup()
        
        def test_fix_heading_hierarchy_preserves_first_heading(self):
            """Test that _fix_heading_hierarchy does NOT change first heading to H1.
            
            Bug fix: Previously, '## Example' was incorrectly changed to '# Example'
            because the code assumed the first heading must be H1. In Hugo/docs systems,
            the page title (H1) often comes from front matter, so content legitimately
            starts at H2.
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test 1: First heading is H2 - should NOT be changed to H1
            content = "## Example\n\nSome content here.\n\n### Subsection\n\nMore content."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertEqual(fixed, content, "First heading '## Example' should NOT be changed to '# Example'")
            self.assertEqual(len(fixes), 0, "No fixes should be applied")
            
            # Test 2: First heading is H3 - should NOT be changed to H1
            content = "### Deep Start\n\nSome content.\n\n#### Even Deeper\n\nMore content."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertEqual(fixed, content, "First heading '### Deep Start' should NOT be changed")
            self.assertEqual(len(fixes), 0, "No fixes should be applied")
            
            # Test 3: Heading skip after first heading SHOULD be fixed
            # H2 -> H4 is a skip, should become H2 -> H3
            content = "## Example\n\nSome content.\n\n#### Skipped Level\n\nMore content."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertIn("### Skipped Level", fixed, "H4 should be fixed to H3 (heading skip)")
            self.assertNotIn("#### Skipped Level", fixed)
            self.assertEqual(len(fixes), 1, "One fix should be applied for the heading skip")
            
            # Test 4: Multiple heading skips
            content = "## Section\n\n##### Skip Many\n\nContent."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertIn("### Skip Many", fixed, "H5 should be fixed to H3 (next valid level after H2)")
            
            # Test 5: Valid heading progression - no changes needed
            content = "## Section 1\n\n### Subsection 1.1\n\n#### Subsubsection 1.1.1\n\n## Section 2"
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertEqual(fixed, content, "Valid heading progression should not be changed")
            self.assertEqual(len(fixes), 0, "No fixes for valid progression")
            
            lecturer.cleanup()
        
        def test_analyze_heading_hierarchy_ignores_first_heading(self):
            """Test that _analyze_heading_hierarchy does NOT flag first heading as issue."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # First heading is H2 - should NOT be flagged as issue
            content = "## Example\n\nContent.\n\n### Subsection"
            issues = lecturer._analyze_heading_hierarchy(content)
            self.assertEqual(len(issues), 0, "First H2 heading should not be flagged as issue")
            
            # Heading skip should still be detected
            content = "## Example\n\n#### Skipped\n\nContent."
            issues = lecturer._analyze_heading_hierarchy(content)
            self.assertEqual(len(issues), 1, "Heading skip H2 -> H4 should be detected")
            self.assertIn("jumped from H2 to H4", issues[0]['issue'])
            
            lecturer.cleanup()
        
        def test_case_insensitive_directory_matching(self):
            """Test case-insensitive directory/file matching for URL to path mapping."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Create a temporary directory structure mimicking Hugo content
            # with mixed-case directory names
            temp_dir = tempfile.mkdtemp(prefix='test_case_insensitive_')
            try:
                # Create structure: content/en/docs-v4/command-line-reference/command-line-Interfaces/_index.md
                content_dir = os.path.join(temp_dir, 'content', 'en', 'docs-v4', 
                                          'command-line-reference', 'command-line-Interfaces')
                os.makedirs(content_dir, exist_ok=True)
                
                # Create _index.md file
                index_file = os.path.join(content_dir, '_index.md')
                with open(index_file, 'w') as f:
                    f.write('# Command Line Interfaces\n')
                
                # Set up lecturer with temp directory as local_webserver
                lecturer.local_webserver = temp_dir
                lecturer.language = 'en'
                
                # Test case-insensitive matching (URL has lowercase, filesystem has mixed case)
                url = 'https://127.0.0.1/docs-v4/command-line-reference/command-line-interfaces/'
                result = lecturer._map_url_to_local_path(url)
                
                # Should find the file despite case difference
                self.assertIsNotNone(result, 
                    f"Should find file with case-insensitive matching. "
                    f"URL path: command-line-interfaces, Filesystem: command-line-Interfaces")
                self.assertTrue(os.path.isfile(result), f"Result should be a valid file: {result}")
                self.assertTrue(result.endswith('_index.md'), f"Should find _index.md, got: {result}")
                
            finally:
                # Cleanup
                shutil.rmtree(temp_dir, ignore_errors=True)
                lecturer.cleanup()
        
        def test_content_based_file_matching(self):
            """Test content-based file matching when path-based matching fails."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Create a temporary directory structure mimicking Hugo content
            # where URL doesn't match filename (e.g., URL: building-cloud-images, file: build-cloud-images.md)
            temp_dir = tempfile.mkdtemp(prefix='test_content_matching_')
            try:
                # Create structure: content/en/docs-v4/build-other-images/
                content_dir = os.path.join(temp_dir, 'content', 'en', 'docs-v4', 'build-other-images')
                os.makedirs(content_dir, exist_ok=True)
                
                # Create _index.md for the parent directory
                index_file = os.path.join(content_dir, '_index.md')
                with open(index_file, 'w') as f:
                    f.write('# Build Other Images\n\nThis section covers building various image types.\n')
                
                # Create build-cloud-images.md with specific content
                cloud_file = os.path.join(content_dir, 'build-cloud-images.md')
                cloud_content = '''# Building Cloud Images

This guide explains how to build cloud images for AWS, Azure, and GCE.

## Prerequisites

- Photon OS build environment
- Cloud SDK installed
- Sufficient disk space

## Building AMI Images

Run the following command to build an AMI:

```bash
sudo make image IMG_NAME=ami
```

## Building Azure Images

For Azure, use:

```bash
sudo make image IMG_NAME=azure
```
'''
                with open(cloud_file, 'w') as f:
                    f.write(cloud_content)
                
                # Create another file to ensure we pick the right one
                ova_file = os.path.join(content_dir, 'build-ova.md')
                with open(ova_file, 'w') as f:
                    f.write('# Building OVA\n\nThis is about OVA images, virtual machines.\n')
                
                # Set up lecturer with temp directory as local_webserver
                lecturer.local_webserver = temp_dir
                lecturer.language = 'en'
                
                # Simulate webpage content that matches the cloud images file
                webpage_text = '''Building Cloud Images
                
This guide explains how to build cloud images for AWS, Azure, and GCE.

Prerequisites
- Photon OS build environment
- Cloud SDK installed
- Sufficient disk space

Building AMI Images
Run the following command to build an AMI:
sudo make image IMG_NAME=ami

Building Azure Images
For Azure, use:
sudo make image IMG_NAME=azure
'''
                
                # Test content-based matching
                # URL says "building-cloud-images" but file is "build-cloud-images.md"
                url = 'https://127.0.0.1/docs-v4/build-other-images/building-cloud-images/'
                result = lecturer._map_url_to_local_path(url, webpage_text)
                
                # Should find the file via content matching
                self.assertIsNotNone(result, 
                    "Should find file via content-based matching when URL doesn't match filename")
                self.assertTrue(os.path.isfile(result), f"Result should be a valid file: {result}")
                self.assertTrue(result.endswith('build-cloud-images.md'), 
                    f"Should find build-cloud-images.md via content matching, got: {result}")
                
            finally:
                # Cleanup
                shutil.rmtree(temp_dir, ignore_errors=True)
                lecturer.cleanup()
        
        def test_content_similarity_calculation(self):
            """Test the content similarity calculation function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test identical texts
            text1 = "Building cloud images for AWS Azure and GCE"
            text2 = "Building cloud images for AWS Azure and GCE"
            score = lecturer._calculate_content_similarity(text1, text2)
            self.assertEqual(score, 1.0, "Identical texts should have similarity of 1.0")
            
            # Test completely different texts
            text1 = "Building cloud images for AWS"
            text2 = "Installing packages with tdnf"
            score = lecturer._calculate_content_similarity(text1, text2)
            self.assertLess(score, 0.3, "Completely different texts should have low similarity")
            
            # Test partially similar texts
            text1 = "Building cloud images for AWS Azure GCE"
            text2 = "Cloud images for AWS and Azure deployment"
            score = lecturer._calculate_content_similarity(text1, text2)
            self.assertGreater(score, 0.3, "Partially similar texts should have moderate similarity")
            self.assertLess(score, 1.0, "Partially similar texts should not be identical")
            
            # Test empty texts
            score = lecturer._calculate_content_similarity("", "some text")
            self.assertEqual(score, 0.0, "Empty text should have zero similarity")
            
            lecturer.cleanup()
        
        def test_revert_relative_path_changes(self):
            """Test that relative path modifications are reverted when FIX_ID 13 is not enabled.
            
            Bug fix: When running with --fix 1-5 (without FIX_ID 13), relative paths like
            ../../images/foo.png should not be modified to ../images/foo.png.
            The _revert_relative_path_changes function should detect and revert such changes.
            """
            from .apply_fixes import FixApplicator
            
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
                fix = '1-5'  # Not including FIX_ID 13 (relative-paths)
                feature = None
                llm = None
                llm_api_key = None
                local_webserver = None
                gh_pr = False
                repo_cloned = None
            
            lecturer = DocumentationLecturer(MockArgs())
            fix_applicator = FixApplicator(lecturer)
            
            # Original content with ../../ paths
            original = """# Test Document

![Image 1](../../images/test-image.png)

Some text here.

![Image 2](../../images/another-image.png)

See also [link](../docs/guide.md) for more info.
"""
            
            # Modified content with ../ paths (one level removed)
            modified = """# Test Document

![Image 1](../images/test-image.png)

Some text here.

![Image 2](../images/another-image.png)

See also [link](../docs/guide.md) for more info.
"""
            
            # The revert function should restore the original paths
            result = fix_applicator._revert_relative_path_changes(modified, original)
            
            # Verify paths are reverted
            self.assertIn("../../images/test-image.png", result, 
                "First image path should be reverted to ../../")
            self.assertIn("../../images/another-image.png", result, 
                "Second image path should be reverted to ../../")
            self.assertIn("../docs/guide.md", result, 
                "Unchanged path should remain the same")
            # Check that the single ../ version is NOT present as a standalone path
            # Note: ../images appears as substring of ../../images, so we check the full link
            self.assertNotIn("](../images/test-image.png)", result,
                "Modified path should not remain as standalone link")
            
            # Test that identical content returns unchanged
            result2 = fix_applicator._revert_relative_path_changes(original, original)
            self.assertEqual(result2, original, "Identical content should return unchanged")
            
            # Test case 2: Single dot paths (./) should also be protected
            # This tests the bug fix where ./troubleshooting-guide/... paths were not being reverted
            original_single_dot = """# Firewall Rules

Check [Permitting Root Login with SSH](./troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/) for SSH access.

See also [Default Firewall Settings](./administration-guide/security-policy/default-firewall-settings/) for more.
"""
            
            # Modified content with ../ paths (changed by installer-weblinkfixes.sh)
            modified_single_dot = """# Firewall Rules

Check [Permitting Root Login with SSH](../../solutions-to-common-problems/permitting-root-login-with-ssh/) for SSH access.

See also [Default Firewall Settings](../../administration-guide/security-policy/default-firewall-settings/) for more.
"""
            
            # The revert function should restore the original ./ paths
            result3 = fix_applicator._revert_relative_path_changes(modified_single_dot, original_single_dot)
            
            # Verify ./ paths are reverted
            self.assertIn("./troubleshooting-guide/solutions-to-common-problems/permitting-root-login-with-ssh/", result3, 
                "Single dot path should be reverted to ./troubleshooting-guide/...")
            self.assertIn("./administration-guide/security-policy/default-firewall-settings/", result3, 
                "Second single dot path should be reverted to ./administration-guide/...")
            # Verify the modified ../ paths are NOT present
            self.assertNotIn("](../../solutions-to-common-problems/permitting-root-login-with-ssh/)", result3,
                "Modified ../../ path should be reverted to original ./")
            
            lecturer.cleanup()
        
        def test_revert_relative_path_duplicate_link_text(self):
            """Test that duplicate link texts with different paths are handled correctly.
            
            Bug fix: When the same link text appears multiple times with different paths,
            each occurrence should be independently tracked and reverted.
            Example: [Photon OS Admin Guide](./path/) and [Photon OS Admin Guide](../../path/)
            """
            from .apply_fixes import FixApplicator
            
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
                fix = '1-5'  # Not including FIX_ID 13 (relative-paths)
                feature = None
                llm = None
                llm_api_key = None
                local_webserver = None
                gh_pr = False
                repo_cloned = None
            
            lecturer = DocumentationLecturer(MockArgs())
            fix_applicator = FixApplicator(lecturer)
            
            # Original content with TWO links that have same link text but different paths
            # This mimics the troubleshooting-packages.md scenario
            original_duplicate = """# Troubleshooting Packages

For more information, see the [Photon OS Administration Guide](./administration-guide/).

Some intermediate content here with other details.

For more commands see the [Photon OS Administration Guide](../../administration-guide/).

End of document.
"""
            
            # Modified content where installer.sh changed the SECOND path to match the first
            # Both paths now show ./administration-guide/ but only the second should be reverted
            modified_duplicate = """# Troubleshooting Packages

For more information, see the [Photon OS Administration Guide](./administration-guide/).

Some intermediate content here with other details.

For more commands see the [Photon OS Administration Guide](./administration-guide/).

End of document.
"""
            
            # The revert function should restore only the second path
            result4 = fix_applicator._revert_relative_path_changes(modified_duplicate, original_duplicate)
            
            # Count occurrences
            import re
            single_dot_count = len(re.findall(r'\]\(\./administration-guide/\)', result4))
            double_dot_count = len(re.findall(r'\]\(\.\./\.\./administration-guide/\)', result4))
            
            # First link should remain ./administration-guide/
            self.assertEqual(single_dot_count, 1, 
                "First link should remain with ./ path")
            
            # Second link should be reverted to ../../administration-guide/
            self.assertEqual(double_dot_count, 1, 
                "Second link should be reverted to ../../ path")
            
            # Verify exact text appears
            self.assertIn("For more information, see the [Photon OS Administration Guide](./administration-guide/)", result4,
                "First occurrence should have single-dot path")
            self.assertIn("For more commands see the [Photon OS Administration Guide](../../administration-guide/)", result4,
                "Second occurrence should have double-dot path")
            
            lecturer.cleanup()
    
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestDocumentationLecturer)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(run_tests())
