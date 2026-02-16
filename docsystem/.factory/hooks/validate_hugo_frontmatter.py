#!/usr/bin/env python3
"""
PostToolUse hook: validate Hugo front matter in blog posts.

Reads the PostToolUse JSON from stdin. If the executed command produced
or modified files under content/blog/, checks that each .md file has
valid YAML front matter with the required fields.

Exit codes:
  0 - pass (no issues or not a relevant command)
  2 - block with feedback (missing required fields)
"""

import json
import sys
import os
import re
import glob as globmod


REQUIRED_FIELDS = {'title', 'date', 'author', 'tags', 'categories', 'summary'}
BLOG_DIR_PATTERN = '**/content/blog/**/*.md'


def extract_front_matter(text):
    """Extract YAML front matter from a markdown string."""
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if not match:
        return None
    fm = {}
    for line in match.group(1).split('\n'):
        if ':' in line:
            key = line.split(':', 1)[0].strip()
            fm[key] = True
    return fm


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    tool_name = data.get('tool_name', '')
    if tool_name not in ('Execute', 'Create', 'Edit'):
        sys.exit(0)

    project_dir = os.environ.get('FACTORY_PROJECT_DIR', os.getcwd())
    blog_dir = os.path.join(project_dir, 'content', 'blog')
    if not os.path.isdir(blog_dir):
        sys.exit(0)

    issues = []
    for md_path in globmod.glob(os.path.join(blog_dir, '**', '*.md'),
                                recursive=True):
        try:
            with open(md_path, 'r', encoding='utf-8') as f:
                content = f.read(2048)
        except OSError:
            continue

        fm = extract_front_matter(content)
        if fm is None:
            issues.append(f'{md_path}: missing front matter block')
            continue
        missing = REQUIRED_FIELDS - set(fm.keys())
        if missing:
            issues.append(f'{md_path}: missing fields: {", ".join(sorted(missing))}')

    if issues:
        output = {
            'decision': 'block',
            'reason': 'Hugo front matter validation failed:\n' + '\n'.join(issues),
        }
        print(json.dumps(output))
        sys.exit(2)

    sys.exit(0)


if __name__ == '__main__':
    main()
