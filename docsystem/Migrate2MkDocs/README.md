# migrate2mkdocs.sh User Manual

## Overview

`migrate2mkdocs.sh` is an all-in-one migration script for converting the Photon OS documentation website from Hugo to MkDocs with the Material theme. It handles content migration, multi-version builds, and Nginx deployment with HTTPS support.

## Usage

```bash
sudo ./migrate2mkdocs.sh
```

**Note:** Root privileges are required for package installation, Nginx configuration, and firewall management.

## Features

- **Idempotent execution** - Checks for existing installations and resets as needed
- **Content migration** - Migrates docs, blog, and static assets from Hugo
- **Multi-version support** - Builds separate sites for versions 3.0, 4.0, and 5.0 (latest)
- **Material theme** - Modern, responsive design with light/dark mode support
- **HTTPS deployment** - Self-signed certificate with Nginx reverse proxy
- **Broadcom branding** - Updates logos and footer with corporate branding
- **GA4 placeholder** - Generates random Google Analytics tracking ID

## Prerequisites

The script automatically installs:
- `wget`, `curl`, `git`
- `python3`, `python3-pip`
- `mkdocs`, `mkdocs-material`
- `nginx`
- `openssl`
- `tar`, `iptables`, `awk`
- `iproute2`

## Directory Structure

| Path | Description |
|------|-------------|
| `/var/www/photon-site-mkdocs` | MkDocs project directory |
| `/var/www/photon-site-mkdocs/site` | Built static site files |
| `/var/www/photon-site-mkdocs/site/3.0` | Version 3.0 documentation |
| `/var/www/photon-site-mkdocs/site/4.0` | Version 4.0 documentation |
| `/var/www/photon-site-mkdocs/docs` | Source markdown files |
| `/tmp/photon-hugo` | Temporary Hugo repository clone |
| `/etc/nginx/ssl` | SSL certificate storage |

## Migration Process

### 1. Environment Setup
- Detects DHCP IP address automatically
- Installs required system dependencies
- Installs MkDocs and Material theme via pip
- Cleans up previous log files

### 2. Content Cloning
- Clones `photon-hugo` branch from `https://github.com/vmware/photon.git`
- Extracts commit information for footer display
- Downloads Broadcom logo

### 3. MkDocs Project Creation
- Creates new MkDocs project using `mkdocs new`
- Removes existing project if present

### 4. Content Migration

#### Static Assets
- Copies all static files from Hugo to `docs/img/`
- Consolidates images (PNG, JPG, SVG, GIF)

#### Home Page
- Migrates from `_index.md` or creates default landing page

#### Blog Posts
- Migrates blog content from `content/en/blog/`
- Fixes frontmatter date formatting
- Adds missing dates (defaults to `2020-01-01`)

#### Documentation
- Latest version (5.0): `docs/docs/`
- Older versions built as separate sites:
  - Version 3.0: `site/3.0/`
  - Version 4.0: `site/4.0/`

### 5. Content Fixes

The `fix_markdown()` function applies transformations:

| Fix Type | Description |
|----------|-------------|
| Link paths | Converts `/docs-v[3-5]/` to `/docs/` |
| Image paths | Normalizes various image path formats to `/img/` |
| Hugo frontmatter | Removes `type:` and `permalink:` |
| HTML tags | Replaces `<br>` variants with newlines |
| Hugo shortcodes | Converts `highlight` to fenced code blocks |
| HTML comments | Converts to MDX-style comments |
| Special characters | Escapes `<`, `>`, `&`, `{`, `}` |
| Code blocks | Adds `text` language to bare code blocks |
| File naming | Renames `_index.md` to `index.md` |

### 6. Configuration Generation

Generates `mkdocs.yml` with:

```yaml
site_name: Photon OS
theme:
  name: material
  logo: img/broadcom-logo.png
  palette:
    - scheme: default  # Light mode
    - scheme: slate    # Dark mode
nav:
  - Home: index.md
  - Blog: blog/
  - Docs: docs/
  - 3.0: /3.0/
  - 4.0: /4.0/
plugins:
  - search
markdown_extensions:
  - tables
  - admonition
  - codehilite
  - pymdownx.superfences
  # ... and more
```

### 7. Multi-Version Build

Each version is built separately:

1. **Main site (5.0)**: `mkdocs build`
2. **Version 4.0**: Built to `site/4.0/`
3. **Version 3.0**: Built to `site/3.0/`

### 8. Nginx Deployment

- Sets file ownership to `nginx:nginx`
- Generates self-signed SSL certificate
- Configures Nginx reverse proxy
- Opens firewall ports 8080 and 8443

## Network Configuration

| Port | Protocol | Purpose |
|------|----------|---------|
| 8080 | HTTP | Redirects to HTTPS |
| 8443 | HTTPS | Main site access |

## Access URLs

After successful migration:

| URL | Content |
|-----|---------|
| `https://<IP>:8443/` | Home page |
| `https://<IP>:8443/docs/` | Latest documentation (5.0) |
| `https://<IP>:8443/blog/` | Blog posts |
| `https://<IP>:8443/3.0/` | Version 3.0 documentation |
| `https://<IP>:8443/4.0/` | Version 4.0 documentation |

## Log Files

| File | Description |
|------|-------------|
| `/var/www/photon-site-mkdocs/build.log` | MkDocs build output |
| `/var/log/nginx/error.log` | Nginx error log |
| `/var/log/nginx/photon-site-error.log` | Site-specific error log |
| `/var/log/nginx/photon-site-access.log` | Site access log |

## MkDocs Extensions

The configuration enables these Markdown extensions:

| Extension | Purpose |
|-----------|---------|
| `tables` | Markdown tables support |
| `attr_list` | Add attributes to elements |
| `md_in_html` | Markdown inside HTML blocks |
| `admonition` | Note/warning/tip blocks |
| `codehilite` | Syntax highlighting |
| `pymdownx.superfences` | Advanced code blocks |
| `pymdownx.details` | Collapsible sections |
| `pymdownx.tabbed` | Tabbed content |
| `pymdownx.tasklist` | Task lists |
| `def_list` | Definition lists |

## Troubleshooting

### Build Failures

```bash
# Check build log
cat /var/www/photon-site-mkdocs/build.log

# Rebuild manually
cd /var/www/photon-site-mkdocs
mkdocs build
```

### Nginx Issues

```bash
# Test configuration
nginx -t

# Check status
systemctl status nginx

# View error logs
tail -f /var/log/nginx/photon-site-error.log
```

### MkDocs Not Found

```bash
# Reinstall MkDocs
pip3 install --upgrade mkdocs mkdocs-material

# Verify installation
mkdocs --version
```

### Certificate Warnings

The self-signed certificate will trigger browser warnings. For production:
- Replace `/etc/nginx/ssl/selfsigned.crt` with a valid certificate
- Replace `/etc/nginx/ssl/selfsigned.key` with the corresponding key

### IP Detection Failure

If IP detection fails, manually set in the script:
```bash
IP_ADDRESS="your.ip.address"
```

## Customization

### Change Installation Directory

Edit `BASE_DIR` and `INSTALL_DIR`:
```bash
BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site-mkdocs"
```

### Update GA4 Tracking ID

Replace the placeholder in `mkdocs.yml`:
```yaml
extra_javascript:
  - https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX
```

And update `overrides/javascripts/config.js`.

### Add New Version

To add a new documentation version:

```bash
# In the version build loop, add:
for ver_info in "3.0 docs-v3 3" "4.0 docs-v4 4" "6.0 docs-v6 6"; do
```

### Change Theme Colors

Edit `mkdocs.yml`:
```yaml
theme:
  palette:
    primary: blue  # Change primary color
    accent: blue   # Change accent color
```

## Comparison: MkDocs vs Docusaurus

| Feature | MkDocs | Docusaurus |
|---------|--------|------------|
| Language | Python | JavaScript/Node.js |
| Theme | Material | Classic |
| Versioning | Separate builds | Built-in |
| Build speed | Faster | Slower |
| Extensibility | Python plugins | React components |

## Uninstallation

```bash
# Stop Nginx
systemctl stop nginx

# Remove site files
rm -rf /var/www/photon-site-mkdocs

# Remove Nginx config
rm -f /etc/nginx/conf.d/photon-site.conf

# Remove certificates
rm -rf /etc/nginx/ssl

# Close firewall ports
iptables -D INPUT -p tcp --dport 8080 -j ACCEPT
iptables -D INPUT -p tcp --dport 8443 -j ACCEPT
iptables-save > /etc/systemd/scripts/ip4save

# Clean up temp files
rm -rf /tmp/photon-hugo

# Optionally uninstall MkDocs
pip3 uninstall mkdocs mkdocs-material
```

## Known Limitations

- Older versions (3.0, 4.0) are built as separate static sites, not integrated versioning
- Blog functionality is basic compared to dedicated blog platforms
- Self-signed certificates cause browser warnings
