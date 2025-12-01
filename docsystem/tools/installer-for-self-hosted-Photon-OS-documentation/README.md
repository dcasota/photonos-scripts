# installer.sh User Manual

## Overview

`installer.sh` is an all-in-one reinstallable installer for self-hosting the Photon OS documentation website on Photon OS. It clones a forked Photon OS repository, builds a Hugo-based static site, configures Nginx with HTTPS, and applies comprehensive link fixes to ensure documentation quality.

---

## Prerequisites

### Environment Variables (Required)

The following environment variables must be set before running the installer:

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
export GITHUB_USERNAME="your-github-username"
export PHOTON_FORK_REPOSITORY="https://github.com/your-username/photon.git"
```

| Variable | Description |
|----------|-------------|
| `GITHUB_TOKEN` | GitHub Personal Access Token with repo access |
| `GITHUB_USERNAME` | Your GitHub username |
| `PHOTON_FORK_REPOSITORY` | URL of your forked Photon OS repository |

### System Requirements

- Photon OS (tested on 4.0, 5.0)
- Root/sudo access
- Internet connectivity
- Minimum 2GB disk space

---

## Usage

```bash
sudo ./installer.sh
```

The script is **idempotent** - it can be run multiple times safely. It will:
- Update existing installations
- Fetch and merge new changes from the repository
- Rebuild the site with latest fixes

---

## What It Installs

### System Packages

| Package | Purpose |
|---------|---------|
| `git` | Repository management |
| `wget`, `curl` | Download tools |
| `nodejs`, `npm` | Hugo theme dependencies |
| `nginx` | Web server |
| `openssl` | SSL certificate generation |
| `docker` | Container support (optional features) |
| `cronie` | Scheduled tasks |
| `iptables` | Firewall configuration |

### Hugo Static Site Generator

- Installs Hugo Extended v0.152.2 (configurable via `HUGO_VERSION`)
- Downloads from official GitHub releases
- Installs to `/usr/local/bin/hugo`

---

## Directory Structure

```
/var/www/photon-site/          # INSTALL_DIR - Repository clone
    +-- content/               # Markdown source files
    |   +-- en/
    |       +-- docs-v3/
    |       +-- docs-v4/
    |       +-- docs-v5/
    |       +-- blog/
    +-- themes/
    |   +-- photon-theme/      # Hugo theme
    +-- static/                # Static assets
    +-- layouts/               # Template overrides
    +-- config.toml            # Hugo configuration
    +-- public/                # SITE_DIR - Built static files

/etc/nginx/
    +-- nginx.conf             # Main Nginx config
    +-- conf.d/
    |   +-- photon-site.conf   # Site-specific config
    +-- ssl/
        +-- selfsigned.crt     # SSL certificate
        +-- selfsigned.key     # SSL private key

/var/log/
    +-- installer.log          # Installation log
    +-- nginx/
        +-- error.log
        +-- access.log
        +-- photon-site-error.log
        +-- photon-site-access.log
```

---

## Installation Workflow

### 1. Package Installation
- Installs system packages via `tdnf`
- Enables Docker, Nginx, and Cron services

### 2. IP Address Detection
- Automatically detects DHCP IP address
- Used for SSL certificate generation and access URL

### 3. Hugo Installation
- Downloads and installs Hugo Extended if not present or wrong version
- Verifies installation with version check

### 4. Repository Clone/Update
- Clones `photon-hugo` branch from your fork
- If already cloned, fetches and merges updates
- Falls back to Docsy theme if `photon-theme` not found

### 5. Submodule and Dependency Installation
- Initializes Git submodules
- Installs npm dependencies for themes

### 6. Web Link Fixes (installer-weblinkfixes.sh)
- Applies 75+ fixes for broken links in markdown files
- Updates branding (VMware â†’ Broadcom)
- Fixes relative path issues
- Removes deprecated configuration

### 7. Site Build (installer-sitebuild.sh)
- Builds static site with Hugo
- Generates self-signed SSL certificate
- Configures Nginx with 200+ redirect rules
- Opens firewall ports 80 and 443

---

## Sub-Scripts

### installer-weblinkfixes.sh

Fixes documentation quality issues:

| Fix Category | Description |
|--------------|-------------|
| **Branding** | Updates VMware â†’ Broadcom logos and links |
| **Relative Links** | Fixes incorrect `./`, `../` path references |
| **Duplicate Paths** | Removes `/docs-v3/docs-v3/` duplications |
| **Image Paths** | Consolidates image references |
| **Hugo Slugs** | Updates links to match Hugo-generated slugs |
| **Deprecated Config** | Fixes GoogleAnalytics, taxonomies, permalinks |
| **Markdown Artifacts** | Fixes malformed markdown syntax |

### installer-sitebuild.sh

Builds and deploys the site:

| Task | Description |
|------|-------------|
| **Hugo Build** | `hugo --minify --baseURL "/" -d public` |
| **SSL Setup** | Generates self-signed certificate |
| **Nginx Config** | Creates site configuration with redirects |
| **Firewall** | Opens ports 80 and 443 |

---

## Nginx Configuration

### HTTPS with Self-Signed Certificate

- HTTP (port 80) redirects to HTTPS (port 443)
- Self-signed certificate valid for 365 days
- Certificate CN matches detected IP address

### Redirect Rules

The Nginx configuration includes 200+ redirect rules for:

| Category | Example |
|----------|---------|
| **Typo Fixes** | `/downloading-photon/` -> `/downloading-photon-os/` |
| **Missing Prefixes** | `/overview/` -> `/docs-v5/overview/` |
| **Short Paths** | `/kickstart-support-in-photon-os/` -> `/docs-v5/user-guide/kickstart-support-in-photon-os/` |
| **Printview Fixes** | `/printview/docs-v5/...` -> `/docs-v5/...` |
| **Image Consolidation** | `/docs-v5/.../images/x.png` -> `/docs-v5/images/x.png` |
| **Double Slashes** | `/path//to/` -> `/path/to/` |
| **Legacy HTML** | `/assets/files/html/3.0/...` -> Modern paths |

---

## Post-Installation

### Access the Site

```
https://<IP_ADDRESS>/
```

The IP address is displayed at the end of installation.

### Verify Installation

```bash
# Check Nginx status
systemctl status nginx

# Check site files
ls -la /var/www/photon-site/public/

# Check logs
tail -f /var/log/nginx/photon-site-error.log
```

### Update Site Content

Re-run the installer to pull latest changes:

```bash
sudo ./installer.sh
```

---

## Configuration

### Hugo Version

Edit `installer.sh` to change Hugo version:

```bash
export HUGO_VERSION="0.152.2"
```

### Site Directories

```bash
export BASE_DIR="/var/www"
export INSTALL_DIR="$BASE_DIR/photon-site"
export SITE_DIR="$INSTALL_DIR/public"
```

---

## Troubleshooting

### Hugo Build Fails

```bash
# Check Hugo logs
cat /var/www/photon-site/hugo_build.log

# Verify Hugo installation
hugo version

# Test build manually
cd /var/www/photon-site
hugo --minify --logLevel debug
```

### Nginx Fails to Start

```bash
# Test configuration
nginx -t

# Check error log
cat /var/log/nginx/error.log

# Verify SSL certificates
ls -la /etc/nginx/ssl/
```

### Certificate Issues

Regenerate SSL certificate:

```bash
rm /etc/nginx/ssl/selfsigned.*
./installer.sh
```

### Missing Environment Variables

```
GITHUB_TOKEN is not set.
```

Ensure all required variables are exported before running:

```bash
export GITHUB_TOKEN="your_token"
export GITHUB_USERNAME="your_username"
export PHOTON_FORK_REPOSITORY="https://github.com/you/photon.git"
```

---

## Log Files

| File | Purpose |
|------|---------|
| `/var/log/installer.log` | Main installation log |
| `/var/www/photon-site/hugo_build.log` | Hugo build output |
| `/var/log/nginx/error.log` | Nginx global errors |
| `/var/log/nginx/photon-site-error.log` | Site-specific errors |
| `/var/log/nginx/photon-site-access.log` | Access log |

---

## Security Notes

- **Self-signed certificates**: Browser will show security warning
- **GITHUB_TOKEN**: Stored in repository URL during clone (consider security implications)
- **Firewall**: Only ports 80 and 443 are opened
- **File permissions**: Site files owned by `nginx:nginx` with 755 permissions

---

## Related Scripts

| Script | Purpose |
|--------|---------|
| `installer-weblinkfixes.sh` | Markdown link fixes |
| `installer-sitebuild.sh` | Hugo build and Nginx config |
| `installer-consolebackend.sh` | Console backend (optional) |
| `installer-searchbackend.sh` | Search backend (optional) |
| `installer-ghinterconnection.sh` | GitHub integration (optional) |
| `weblinkchecker.sh` | Verify links after build |
| `photonos-docs-lecturer.py` | Documentation quality analysis |
