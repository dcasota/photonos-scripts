# migrate2docusaurus.sh User Manual

## Overview

`migrate2docusaurus.sh` is an all-in-one migration script for converting the Photon OS documentation website from Hugo to Docusaurus 3.9.2. It handles content migration, versioning, build configuration, and Nginx deployment with HTTPS support.

## Usage

```bash
sudo ./migrate2docusaurus.sh
```

**Note:** Root privileges are required for package installation, Nginx configuration, and firewall management.

## Features

- **Idempotent execution** - Checks for existing installations and resets as needed
- **Content migration** - Migrates docs, blog, and static assets from Hugo
- **Version management** - Sets up Docusaurus versioning (3.0, 4.0, 5.0)
- **HTTPS deployment** - Self-signed certificate with Nginx reverse proxy
- **Broadcom branding** - Updates logos and footer with corporate branding
- **GA4 placeholder** - Generates random Google Analytics tracking ID

## Prerequisites

The script automatically installs:
- `wget`, `curl`, `git`
- `nodejs`, `npm`
- `nginx`
- `openssl`
- `tar`, `iptables`, `awk`
- `iproute2`

## Directory Structure

| Path | Description |
|------|-------------|
| `/var/www/photon-site-docusaurus` | Docusaurus project directory |
| `/var/www/photon-site-docusaurus/build` | Built static site files |
| `/tmp/photon-hugo` | Temporary Hugo repository clone |
| `/etc/nginx/ssl` | SSL certificate storage |
| `/etc/nginx/conf.d/photon-site.conf` | Nginx site configuration |

## Migration Process

### 1. Environment Setup
- Detects DHCP IP address automatically
- Installs required system dependencies
- Cleans up previous log files

### 2. Content Cloning
- Clones `photon-hugo` branch from `https://github.com/vmware/photon.git`
- Extracts commit information for footer display
- Downloads Broadcom logo

### 3. Docusaurus Project Creation
- Creates new Docusaurus 3.9.2 project
- Installs npm dependencies with retry logic (3 attempts)
- Installs `prism-react-renderer@2.3.1` for syntax highlighting
- Installs `@docusaurus/plugin-google-gtag` for analytics

### 4. Content Migration

#### Static Assets
- Copies all static files from Hugo
- Consolidates images to `/static/img/`

#### Blog Posts
- Migrates blog content from `content/en/blog/`
- Fixes frontmatter date formatting
- Adds missing dates (defaults to `2020-01-01`)

#### Documentation
- Migrates versioned docs in sequence:
  - Version 3.0 from `content/en/docs-v3/`
  - Version 4.0 from `content/en/docs-v4/`
  - Version 5.0 from `content/en/docs-v5/`
- Creates Docusaurus version snapshots

#### Pages
- Migrates home page from `_index.md`
- Copies other top-level markdown pages

### 5. Content Fixes

The script applies extensive content transformations:

| Fix Type | Description |
|----------|-------------|
| Link paths | Converts `/docs-v[3-5]/` to `/docs/` |
| Image paths | Normalizes various image path formats to `/img/` |
| Hugo frontmatter | Removes `type: docs` and `permalink:` |
| HTML tags | Replaces `<br>` with newlines |
| Hugo shortcodes | Converts `highlight` to fenced code blocks |
| HTML comments | Converts to MDX comments `{/* */}` |
| Special characters | Escapes `<`, `>`, `&`, `{`, `}` |
| Code blocks | Adds `text` language to bare code blocks |

### 6. Configuration Generation

Generates `docusaurus.config.js` with:
- Site metadata (title, tagline, favicon)
- Navbar with Home, Blog, Docs, version dropdown, GitHub link
- Footer with community links, privacy policy, commit info
- Prism syntax highlighting (GitHub light, Dracula dark themes)
- Version configuration for docs

### 7. Build & Deploy

- Builds static site with `npm run build`
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
- **HTTPS**: `https://<IP_ADDRESS>:8443/`
- **HTTP**: `http://<IP_ADDRESS>:8080/` (redirects to HTTPS)

## Log Files

| File | Description |
|------|-------------|
| `/var/www/photon-site-docusaurus/build.log` | Docusaurus build output |
| `/var/www/photon-site-docusaurus/npm_install.log` | npm installation output |
| `/var/log/nginx/error.log` | Nginx error log |
| `/var/log/nginx/photon-site-error.log` | Site-specific error log |
| `/var/log/nginx/photon-site-access.log` | Site access log |

## Troubleshooting

### Build Failures

```bash
# Check build log
cat /var/www/photon-site-docusaurus/build.log

# Check npm install log
cat /var/www/photon-site-docusaurus/npm_install.log

# Verify prism-react-renderer
ls -la /var/www/photon-site-docusaurus/node_modules/prism-react-renderer
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

### Change Docusaurus Version

Edit the `DOCUSAURUS_VERSION` variable:
```bash
DOCUSAURUS_VERSION="3.9.2"
```

### Change Installation Directory

Edit `BASE_DIR` and `INSTALL_DIR`:
```bash
BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site-docusaurus"
```

### Update GA4 Tracking ID

Replace the placeholder in `docusaurus.config.js`:
```javascript
trackingID: 'G-XXXXXXXXXX',
```

### Subpath Hosting

For hosting under a subpath:
1. Modify `baseUrl` in `docusaurus.config.js`
2. Update Nginx `location` directive

## Uninstallation

```bash
# Stop Nginx
systemctl stop nginx

# Remove site files
rm -rf /var/www/photon-site-docusaurus

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
```

## Known Limitations

- Blog archive page generation is disabled (`archiveBasePath: null`)
- RSS/Atom feed generation is disabled (`feedOptions: { type: null }`)
- Broken links are ignored during build (`onBrokenLinks: 'ignore'`)
- Self-signed certificates cause browser warnings
