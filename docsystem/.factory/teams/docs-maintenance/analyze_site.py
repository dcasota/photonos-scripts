import xml.etree.ElementTree as ET
import csv
import json
import os
import sys
from urllib.parse import urlparse

def parse_sitemap(file_path):
    urls = set()
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        # Namespace handling
        ns = {'sm': 'http://www.sitemaps.org/schemas/sitemap/0.9'}
        for url in root.findall('sm:url', ns):
            loc = url.find('sm:loc', ns)
            if loc is not None and loc.text:
                urls.add(loc.text.strip())
    except Exception as e:
        print(f"Error parsing {file_path}: {e}")
    return urls

def normalize_url(url):
    # Remove protocol and domain to compare paths
    parsed = urlparse(url)
    path = parsed.path
    if not path.endswith('/'):
        path += '/'
    return path

def analyze():
    prod_urls = parse_sitemap('prod_sitemap.xml')
    local_urls = parse_sitemap('local_sitemap.xml')
    
    print(f"Prod URLs: {len(prod_urls)}")
    print(f"Local URLs: {len(local_urls)}")

    # Create normalized sets for comparison
    prod_paths = {normalize_url(u) for u in prod_urls}
    local_paths = {normalize_url(u) for u in local_urls}
    
    orphaned_paths = prod_paths - local_paths
    
    # Map back to full URLs (just taking one example for each path)
    orphaned_pages = []
    for path in orphaned_paths:
        # Find the original URL that matches this path
        for u in prod_urls:
            if normalize_url(u) == path:
                orphaned_pages.append(u)
                break
    
    # Parse broken links from CSV
    broken_links = []
    report_csv = None
    # Find the latest report csv
    files = [f for f in os.listdir('.') if f.startswith('report-') and f.endswith('.csv')]
    if files:
        report_csv = sorted(files)[-1]
        print(f"Using report CSV: {report_csv}")
        try:
            with open(report_csv, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    broken_links.append({
                        "referrer": row.get('referring_page'),
                        "broken_link": row.get('broken_link')
                    })
        except Exception as e:
            print(f"Error parsing CSV: {e}")

    output = {
        "production_urls": list(prod_urls),
        "localhost_urls": list(local_urls),
        "orphaned_pages": orphaned_pages,
        "broken_links": broken_links,
        "sitemap_coverage": "100%" if not orphaned_pages else f"{len(local_paths)/len(prod_paths):.2%}",
        "audit_report": os.path.abspath(report_csv) if report_csv else "None"
    }
    
    with open('site-map.json', 'w') as f:
        json.dump(output, f, indent=2)
        
    print("site-map.json generated")

if __name__ == "__main__":
    analyze()
