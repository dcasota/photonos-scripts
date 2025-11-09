---
name: DocsLecturerSandbox
tools: [write_file, sandbox_api]
updated: "2025-11-09T21:35:00Z"
auto_level: high
autonomous_mode: enabled
sandbox_runtime: "@anthropic-ai/sandbox-runtime"
interactive_mode: true
---

Integrate embedded code sandboxes using @anthropic-ai/sandbox-runtime:
- Identify code sections in docs.
- Wrap in sandbox iframes or shortcodes (using https://github.com/anthropic-experimental/sandbox-runtime for execution).
- Ensure safe execution (isolated environment).
- Update Markdown files accordingly.
