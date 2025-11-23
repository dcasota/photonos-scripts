#!/usr/bin/env python3
"""
Orphaned Directory Detection Script
Identifies directories in Hugo public output that lack proper index pages
and cause 301 redirect loops or serve directory listings instead of content.

Usage: python3 detect-orphaned-directories.py <public_dir> [--format=json|text]
Example: python3 detect-orphaned-directories.py /var/www/photon-site/public
"""

import os
import sys
import json
from pathlib import Path
from typing import List, Dict, Set

def find_orphaned_directories(public_dir: str) -> Dict[str, List[Dict]]:
    """
    Scan Hugo public directory for orphaned directories.
    
    Orphaned directories are:
    1. Directories without index.html
    2. Directories containing only images/assets (no HTML content)
    3. Directories that would cause 301 redirects when accessed
    
    Returns dict with categorized orphaned directories.
    """
    orphaned = {
        'missing_index': [],
        'image_only': [],
        'empty': []
    }
    
    public_path = Path(public_dir)
    
    if not public_path.exists():
        print(f"Error: Directory {public_dir} does not exist", file=sys.stderr)
        return orphaned
    
    # Walk through all directories
    for root, dirs, files in os.walk(public_path):
        rel_path = os.path.relpath(root, public_path)
        
        # Skip root and special directories
        if rel_path == '.' or rel_path.startswith('.git'):
            continue
        
        # Check if directory has index.html
        has_index = 'index.html' in files
        has_html = any(f.endswith('.html') for f in files)
        has_images = any(f.endswith(('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp')) for f in files)
        has_assets = any(f.endswith(('.css', '.js', '.woff', '.woff2', '.ttf')) for f in files)
        
        # URL path for this directory
        url_path = '/' + rel_path.replace('\\', '/')
        
        # Empty directory
        if not files and not dirs:
            orphaned['empty'].append({
                'path': root,
                'url': url_path,
                'reason': 'Empty directory with no files or subdirectories'
            })
        
        # Directory without index.html
        elif not has_index and (has_images or has_assets or files):
            if has_images and not has_html:
                orphaned['image_only'].append({
                    'path': root,
                    'url': url_path,
                    'reason': f'Contains {len([f for f in files if f.endswith((".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"))])} images but no index.html',
                    'file_count': len(files)
                })
            elif not has_html:
                orphaned['missing_index'].append({
                    'path': root,
                    'url': url_path,
                    'reason': 'Contains files but no index.html or HTML content',
                    'file_count': len(files),
                    'sample_files': files[:5]
                })
    
    return orphaned

def generate_fix_suggestions(orphaned: Dict[str, List[Dict]]) -> List[str]:
    """Generate actionable fix suggestions for orphaned directories."""
    suggestions = []
    
    # Image-only directories
    if orphaned['image_only']:
        suggestions.append("# Fix 56: Move image-only directories to static/images or create index pages")
        suggestions.append("# Image directories should be in static/ not in content/")
        for item in orphaned['image_only'][:3]:  # Show first 3 examples
            suggestions.append(f"# - {item['url']} ({item['reason']})")
    
    # Missing index pages
    if orphaned['missing_index']:
        suggestions.append("\n# Fix 57: Create index pages for directories with content but no index.html")
        for item in orphaned['missing_index'][:3]:
            suggestions.append(f"# - {item['url']}")
    
    # Empty directories
    if orphaned['empty']:
        suggestions.append("\n# Fix 58: Remove empty directories from source")
        for item in orphaned['empty'][:3]:
            suggestions.append(f"# - {item['url']}")
    
    return suggestions

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 detect-orphaned-directories.py <public_dir> [--format=json|text]")
        sys.exit(1)
    
    public_dir = sys.argv[1]
    output_format = 'text'
    
    if len(sys.argv) > 2 and sys.argv[2].startswith('--format='):
        output_format = sys.argv[2].split('=')[1]
    
    print(f"Scanning {public_dir} for orphaned directories...", file=sys.stderr)
    orphaned = find_orphaned_directories(public_dir)
    
    total = sum(len(v) for v in orphaned.values())
    
    if output_format == 'json':
        result = {
            'total_orphaned': total,
            'categories': orphaned
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"\n{'='*70}")
        print(f"Orphaned Directory Detection Report")
        print(f"{'='*70}\n")
        
        print(f"Total orphaned directories found: {total}\n")
        
        if orphaned['image_only']:
            print(f"Image-only directories (no index.html): {len(orphaned['image_only'])}")
            for item in orphaned['image_only'][:10]:
                print(f"  - {item['url']}")
                print(f"    Reason: {item['reason']}")
            if len(orphaned['image_only']) > 10:
                print(f"    ... and {len(orphaned['image_only']) - 10} more")
            print()
        
        if orphaned['missing_index']:
            print(f"Directories missing index.html: {len(orphaned['missing_index'])}")
            for item in orphaned['missing_index'][:10]:
                print(f"  - {item['url']}")
                print(f"    Reason: {item['reason']}")
            if len(orphaned['missing_index']) > 10:
                print(f"    ... and {len(orphaned['missing_index']) - 10} more")
            print()
        
        if orphaned['empty']:
            print(f"Empty directories: {len(orphaned['empty'])}")
            for item in orphaned['empty'][:10]:
                print(f"  - {item['url']}")
            if len(orphaned['empty']) > 10:
                print(f"    ... and {len(orphaned['empty']) - 10} more")
            print()
        
        # Generate fix suggestions
        suggestions = generate_fix_suggestions(orphaned)
        if suggestions:
            print(f"\n{'='*70}")
            print("Fix Suggestions for installer-weblinkfixes.sh:")
            print(f"{'='*70}\n")
            for suggestion in suggestions:
                print(suggestion)
    
    # Exit with error code if orphaned directories found
    sys.exit(0 if total == 0 else 1)

if __name__ == '__main__':
    main()
