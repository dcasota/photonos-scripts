#!/usr/bin/env python3
"""
PostToolUse hook: validate C syntax after .c/.h file edits.
Runs gcc -fsyntax-only on edited C files and returns errors to the droid.
"""
import json
import sys
import subprocess
import os

try:
    input_data = json.load(sys.stdin)
    file_path = input_data.get('tool_input', {}).get('file_path', '')

    if not file_path.endswith(('.c', '.h')):
        sys.exit(0)

    if not os.path.exists(file_path):
        sys.exit(0)

    project_dir = os.environ.get('FACTORY_PROJECT_DIR', '.')
    src_dir = os.path.join(project_dir, 'src')

    result = subprocess.run(
        ['gcc', '-fsyntax-only', '-Wall', '-Wextra',
         f'-I{src_dir}', '-I/usr/include', file_path],
        capture_output=True, text=True, timeout=10
    )

    if result.returncode != 0:
        print(f"C syntax errors in {file_path}:")
        print(result.stderr)
        sys.exit(1)

except Exception as e:
    print(f"Hook error: {e}", file=sys.stderr)
    sys.exit(0)
