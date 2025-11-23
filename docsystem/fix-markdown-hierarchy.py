#!/usr/bin/env python3
"""
Markdown Heading Hierarchy Fix Script
Automatically fixes heading hierarchy violations in markdown files.

Common issues:
- H0 followed by H2 (should be H1 followed by H2)
- Skipping heading levels (H1 -> H3 instead of H1 -> H2)
- Incorrect heading levels (H8, H15, etc. that are malformed)

Usage: python3 fix-markdown-hierarchy.py <content_dir> [--dry-run] [--report-only]
Example: python3 fix-markdown-hierarchy.py /var/www/photon-site/content/en --dry-run
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Tuple

def detect_heading_level(line: str) -> int:
    """
    Detect markdown heading level from line.
    Returns 0 if not a heading.
    """
    # ATX-style headings (# ## ###)
    match = re.match(r'^(#{1,6})\s+', line)
    if match:
        return len(match.group(1))
    
    # Setext-style headings (underline with = or -)
    # Not implemented yet - ATX is primary format
    
    return 0

def analyze_heading_hierarchy(content: str) -> List[Dict]:
    """
    Analyze markdown content for heading hierarchy violations.
    
    Returns list of issues found.
    """
    lines = content.split('\n')
    issues = []
    prev_level = 0
    
    for line_num, line in enumerate(lines, 1):
        level = detect_heading_level(line)
        
        if level > 0:
            # Check for hierarchy violations
            if prev_level == 0 and level > 1:
                # First heading is not H1
                issues.append({
                    'line': line_num,
                    'current_level': level,
                    'prev_level': prev_level,
                    'issue': f'First heading is H{level}, should be H1',
                    'suggestion': 1,
                    'content': line.strip()
                })
            elif level - prev_level > 1:
                # Skipped heading levels
                issues.append({
                    'line': line_num,
                    'current_level': level,
                    'prev_level': prev_level,
                    'issue': f'Heading jumped from H{prev_level} to H{level}',
                    'suggestion': prev_level + 1,
                    'content': line.strip()
                })
            
            prev_level = level
    
    return issues

def fix_heading_hierarchy(content: str, conservative: bool = True) -> Tuple[str, List[Dict]]:
    """
    Fix heading hierarchy in markdown content.
    
    Conservative mode: Only fix first heading and obvious skips
    Aggressive mode: Normalize entire hierarchy
    
    Returns (fixed_content, list_of_fixes_applied)
    """
    lines = content.split('\n')
    fixes_applied = []
    prev_level = 0
    
    for i, line in enumerate(lines):
        level = detect_heading_level(line)
        
        if level > 0:
            new_level = level
            fix_reason = None
            
            # Fix first heading if not H1
            if prev_level == 0 and level > 1:
                new_level = 1
                fix_reason = f'First heading: H{level} -> H1'
            
            # Fix heading level skips
            elif level - prev_level > 1:
                new_level = prev_level + 1
                fix_reason = f'Heading skip: H{prev_level} -> H{level} becomes H{prev_level} -> H{new_level}'
            
            if new_level != level and fix_reason:
                # Replace heading
                old_line = line
                new_line = re.sub(r'^#{1,6}', '#' * new_level, line)
                lines[i] = new_line
                
                fixes_applied.append({
                    'line': i + 1,
                    'old_level': level,
                    'new_level': new_level,
                    'reason': fix_reason,
                    'old_content': old_line.strip(),
                    'new_content': new_line.strip()
                })
                
                prev_level = new_level
            else:
                prev_level = level
    
    return '\n'.join(lines), fixes_applied

def process_file(file_path: str, dry_run: bool = False) -> Dict:
    """
    Process a single markdown file.
    
    Returns dict with file info and fixes applied.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return {
            'file': file_path,
            'error': str(e),
            'fixes': []
        }
    
    # Analyze issues
    issues = analyze_heading_hierarchy(content)
    
    if not issues:
        return {
            'file': file_path,
            'issues': 0,
            'fixes': []
        }
    
    # Apply fixes
    fixed_content, fixes = fix_heading_hierarchy(content)
    
    # Write back if not dry run
    if not dry_run and fixes:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(fixed_content)
        except Exception as e:
            return {
                'file': file_path,
                'error': f'Failed to write: {e}',
                'fixes': fixes
            }
    
    return {
        'file': file_path,
        'issues': len(issues),
        'fixes': fixes
    }

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fix-markdown-hierarchy.py <content_dir> [--dry-run] [--report-only]")
        sys.exit(1)
    
    content_dir = sys.argv[1]
    dry_run = '--dry-run' in sys.argv
    report_only = '--report-only' in sys.argv
    
    if report_only:
        dry_run = True
    
    print(f"Scanning {content_dir} for markdown files...", file=sys.stderr)
    
    # Find all markdown files
    md_files = []
    for root, dirs, files in os.walk(content_dir):
        for file in files:
            if file.endswith('.md'):
                md_files.append(os.path.join(root, file))
    
    print(f"Found {len(md_files)} markdown files", file=sys.stderr)
    
    if dry_run:
        print(f"{'DRY RUN MODE - No files will be modified':^70}", file=sys.stderr)
    
    print(f"\n{'='*70}")
    print(f"Markdown Heading Hierarchy Fix Report")
    print(f"{'='*70}\n")
    
    total_files_with_issues = 0
    total_fixes = 0
    
    for md_file in md_files:
        result = process_file(md_file, dry_run=dry_run)
        
        if 'error' in result:
            print(f"ERROR: {result['file']}")
            print(f"  {result['error']}\n")
            continue
        
        if result['issues'] > 0:
            total_files_with_issues += 1
            
            if result['fixes']:
                total_fixes += len(result['fixes'])
                rel_path = os.path.relpath(result['file'], content_dir)
                print(f"File: {rel_path}")
                print(f"  Issues found: {result['issues']}")
                print(f"  Fixes applied: {len(result['fixes'])}")
                
                for fix in result['fixes'][:3]:  # Show first 3 fixes per file
                    print(f"    Line {fix['line']}: {fix['reason']}")
                
                if len(result['fixes']) > 3:
                    print(f"    ... and {len(result['fixes']) - 3} more fixes")
                print()
    
    print(f"{'='*70}")
    print(f"Summary:")
    print(f"  Files scanned: {len(md_files)}")
    print(f"  Files with issues: {total_files_with_issues}")
    print(f"  Total fixes {'applied' if not dry_run else 'suggested'}: {total_fixes}")
    print(f"{'='*70}\n")
    
    if dry_run and total_fixes > 0:
        print("Run without --dry-run to apply fixes")
    
    sys.exit(0)

if __name__ == '__main__':
    main()
