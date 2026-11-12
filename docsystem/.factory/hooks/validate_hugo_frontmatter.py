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
import string


REQUIRED_FIELDS = {'title', 'date', 'author', 'tags', 'categories', 'summary'}
BLOG_DIR_PATTERN = '**/content/blog/**/*.md'

# Characters accepted in FACTORY_PROJECT_DIR.
_PATH_CHARS = string.ascii_letters + string.digits + '/._-+@,=~ '


def project_dir_from_env():
    """Return FACTORY_PROJECT_DIR (default: cwd) as a normalised absolute path.

    The value is rebuilt from _PATH_CHARS; any other character stops the
    hook with a message instead of being silently dropped.
    """
    raw = os.path.abspath(os.environ.get('FACTORY_PROJECT_DIR') or os.getcwd())
    out = []
    for ch in raw:
        for allowed in _PATH_CHARS:
            if ch == allowed:
                out.append(allowed)
                break
        else:
            print(f'validate_hugo_frontmatter: unsupported character in '
                  f'FACTORY_PROJECT_DIR {raw!r}', file=sys.stderr)
            sys.exit(1)
    return ''.join(out)


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

    project_dir = project_dir_from_env()
    blog_dir = os.path.join(project_dir, 'content', 'blog')
    if not os.path.isdir(blog_dir):
        sys.exit(0)
    blog_root = os.path.realpath(blog_dir)

    issues = []
    for md_path in globmod.glob(os.path.join(blog_dir, '**', '*.md'),
                                recursive=True):
        # Only posts inside the blog tree: a symlink pointing elsewhere is
        # not read.
        if not os.path.realpath(md_path).startswith(blog_root + os.sep):
            continue
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
