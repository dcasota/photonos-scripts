import json
import yaml
import os
import re

def find_markdown_files(root_dir):
    md_files = []
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if file.endswith(".md"):
                md_files.append(os.path.join(root, file))
    return md_files

def check_markdown_issues(file_path, content):
    issues = []
    lines = content.split('\n')
    # Check header hierarchy (basic)
    last_level = 0
    for i, line in enumerate(lines):
        if line.startswith('#'):
            level = len(line.split(' ')[0])
            if level > last_level + 1:
                issues.append({
                    "severity": "high",
                    "category": "markdown",
                    "description": f"Heading hierarchy violation: H{last_level} followed by H{level}",
                    "location": f"{file_path}:{i+1}",
                    "fix_suggestion": f"Adjust heading level to H{last_level+1}"
                })
            last_level = level
    return issues

def check_security_issues(file_path, content):
    issues = []
    # Simple regex for secrets
    patterns = {
        "private_key": r"BEGIN PRIVATE KEY",
        "aws_key": r"AKIA[0-9A-Z]{16}",
        "generic_token": r"token\s*=\s*['\"][a-zA-Z0-9]{20,}['\"]"
    }
    lines = content.split('\n')
    for i, line in enumerate(lines):
        for key, pattern in patterns.items():
            if re.search(pattern, line):
                issues.append({
                    "severity": "critical",
                    "category": "security",
                    "description": f"Potential secret detected: {key}",
                    "location": f"{file_path}:{i+1}",
                    "fix_suggestion": "Remove or mask the secret"
                })
    return issues

def main():
    plan = {"issues": []}
    
    # Load site-map.json
    try:
        with open("site-map.json", "r") as f:
            sitemap = json.load(f)
            
        # Orphaned pages
        for page in sitemap.get("orphaned_pages", []):
            plan["issues"].append({
                "severity": "critical",
                "category": "orphaned_page",
                "description": "Page exists on production but missing on localhost",
                "location": page,
                "fix_suggestion": "Ensure content is present in local build"
            })
            
        # Broken links
        for link in sitemap.get("broken_links", []):
            plan["issues"].append({
                "severity": "critical",
                "category": "broken_link",
                "description": f"Broken link found: {link['broken_link']}",
                "location": link['referrer'],
                "fix_suggestion": "Fix or remove the link"
            })
            
    except FileNotFoundError:
        print("site-map.json not found, skipping sitemap checks")

    # Scan content files
    content_dir = "/var/www/photon-site/content"
    if os.path.exists(content_dir):
        md_files = find_markdown_files(content_dir)
        for file_path in md_files:
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    content = f.read()
                    
                # Markdown checks
                plan["issues"].extend(check_markdown_issues(file_path, content))
                
                # Security checks
                plan["issues"].extend(check_security_issues(file_path, content))
                
            except Exception as e:
                print(f"Error reading {file_path}: {e}")
    
    # Output plan.md
    with open("plan.md", "w") as f:
        # Manually formatting yaml to match the requested style if needed, or just use yaml.dump
        # The requested style is a list of objects.
        yaml.dump(plan, f, default_flow_style=False, sort_keys=False)
    
    print("plan.md generated")

if __name__ == "__main__":
    main()
