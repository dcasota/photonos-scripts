import re
import xml.etree.ElementTree as ET

def extract_urls_from_log(log_file, output_file):
    urls = set()
    with open(log_file, 'r') as f:
        for line in f:
            match = re.search(r'^--\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}--\s+(https://[^\s]+)', line)
            if match:
                urls.add(match.group(1))
    
    # Create XML sitemap
    root = ET.Element('urlset', xmlns='http://www.sitemaps.org/schemas/sitemap/0.9')
    for url in sorted(urls):
        url_elem = ET.SubElement(root, 'url')
        loc_elem = ET.SubElement(url_elem, 'loc')
        loc_elem.text = url
    
    tree = ET.ElementTree(root)
    tree.write(output_file, encoding='utf-8', xml_declaration=True)
    print(f"Extracted {len(urls)} URLs to {output_file}")

extract_urls_from_log('report-2025-11-23_13-30-36.log', 'local_sitemap.xml')
extract_urls_from_log('report-2025-11-23_13-29-10.log', 'prod_sitemap.xml')
