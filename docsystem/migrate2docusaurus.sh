#!/bin/bash

# Usage: sudo ./migrator.sh
# All-in-one migration script for moving the Photon OS documentation web app from Hugo to Docusaurus 3.9.2 on Photon OS.
# Assumes Photon OS (uses tdnf for packages).
# Idempotent: Checks for existing installations and updates/resets as needed.
# Requires root for tdnf, Nginx, and firewall.
# Enforces website on port 8080 (HTTP) and 8443 (HTTPS) via Nginx; opens ports 8080/8443 in iptables.
# Migrates content, sets up versioning, configures navbar/footer, builds site, sets up Nginx with HTTPS.
# Fixes: Handles Broadcom branding, commit info in footer, GA4 placeholder.
# Note: Self-signed cert will cause browser warnings; replace with real cert for production.
# For subpath hosting, modify baseUrl in docusaurus.config.js and Nginx alias.

BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site-docusaurus"
SITE_DIR="$INSTALL_DIR/build"  # Where built static files go
DOCUSAURUS_VERSION="3.9.2"
TMP_REPO="/tmp/photon-hugo"

# Dynamically retrieve DHCP IP address
tdnf install -y iproute2
IP_ADDRESS=$(ip addr show | grep -oP 'inet \K[\d.]+(?=/)' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS=$(hostname -I | awk '{print $1}' | grep -v '127.0.0.1')
fi
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS="localhost"
  echo "Warning: Could not detect DHCP IP. Using 'localhost' for certificate. Set IP manually if needed."
fi
echo "Detected IP address: $IP_ADDRESS"

# Install dependencies if not present
tdnf install -y wget curl nginx tar iptables nodejs openssl git

# Clean up log files before starting
echo "Cleaning up log files..."
truncate -s 0 /var/log/nginx/error.log 2>/dev/null || rm -f /var/log/nginx/error.log
truncate -s 0 /var/log/nginx/photon-site-error.log 2>/dev/null || rm -f /var/log/nginx/photon-site-error.log
rm -f "$INSTALL_DIR/build.log"

# Clone repo to tmp for content migration
if [ -d "$TMP_REPO" ]; then
  rm -rf "$TMP_REPO"
fi
echo "Cloning repo for content migration"
git clone --branch photon-hugo --single-branch https://github.com/vmware/photon.git "$TMP_REPO"
cd "$TMP_REPO"

# Get commit details
COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_ABBREV=$(git log -1 --format=%h)
COMMIT_MESSAGE=$(git log -1 --format=%s)
COMMIT_DATE=$(git log -1 --format=%cd --date=format:'%B %-d, %Y')
echo "Checked out commit: $COMMIT_HASH"
echo "Commit date: $COMMIT_DATE"
echo "Commit message: $COMMIT_MESSAGE"
echo "Abbreviated hash: $COMMIT_ABBREV"

# Download Broadcom logo if not in static
mkdir -p "$TMP_REPO/static/img"
if [ ! -f "$TMP_REPO/static/img/broadcom-logo.png" ]; then
  wget -O "$TMP_REPO/static/img/broadcom-logo.png" "https://www.broadcom.com/img/broadcom-logo.png"
fi

# Create or reset Docusaurus project
if [ -d "$INSTALL_DIR" ]; then
  echo "Deleting existing Docusaurus project"
  rm -rf "$INSTALL_DIR"
fi
echo "Creating Docusaurus project v${DOCUSAURUS_VERSION}"
npx create-docusaurus@${DOCUSAURUS_VERSION} "$INSTALL_DIR" classic --javascript --skip-install
cd "$INSTALL_DIR"
npm install

# Migrate static assets
rm -rf static/*
cp -r "$TMP_REPO/static/"* static/ 2>/dev/null || true

# Migrate blog
rm -rf blog/*
mkdir -p blog
cp -r "$TMP_REPO/content/en/blog/"* blog/ 2>/dev/null || true
# Fix blog frontmatter dates if needed (assume compatible; add sed if issues arise)
find blog -type f -name "*.md" -exec sed -i 's/date: \([0-9-]\+\)/date: "\1"/g' {} \;

# Migrate docs with versioning (oldest first)
rm -rf docs/*
mkdir -p docs
# Version 3.0
cp -r "$TMP_REPO/content/en/docs-v3/"* docs/ 2>/dev/null || true
npx docusaurus docs:version 3.0
# Version 4.0
rm -rf docs/*
cp -r "$TMP_REPO/content/en/docs-v4/"* docs/ 2>/dev/null || true
npx docusaurus docs:version 4.0
# Current (v5 unversioned)
rm -rf docs/*
cp -r "$TMP_REPO/content/en/docs-v5/"* docs/ 2>/dev/null || true

# Migrate home and other top-level pages
mkdir -p src/pages
if [ -f "$TMP_REPO/content/en/_index.md" ]; then
  cp "$TMP_REPO/content/en/_index.md" src/pages/index.md
else
  echo "No home _index.md found; using default Docusaurus landing page."
fi
# Copy other potential pages (e.g., features.md, contribute.md)
find "$TMP_REPO/content/en" -maxdepth 1 -type f -name "*.md" -not -name "_index.md" -exec cp {} src/pages/ \;

# Fix links and frontmatter across all content
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's|/docs-v[3-5]/|/docs/|g' {} \;  # Adjust versioned links
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/type: docs//g' {} \;  # Remove Hugo-specific
find blog docs src/pages versioned_docs -type f -name "*.md*" -exec sed -i 's/permalink: .*//g' {} \;  # Remove permalinks

# Configure docusaurus.config.js
RANDOM_ID=$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 10 | head -n 1)
cat > docusaurus.config.js <<EOF
/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Photon OS',
  tagline: 'A VMware By Broadcom backed Project',
  favicon: 'img/favicon.ico',
  url: 'https://${IP_ADDRESS}:8443',
  baseUrl: '/',
  organizationName: 'vmware',
  projectName: 'photon',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  i18n: { defaultLocale: 'en', locales: ['en'] },
  presets: [
    ['classic', {
      docs: {
        sidebarPath: './sidebars.js',
        routeBasePath: '/',
        versions: { current: { label: '5.0' }, '4.0': { label: '4.0' }, '3.0': { label: '3.0' } },
        lastVersion: 'current',
      },
      blog: { showReadingTime: true, path: 'blog' },
      theme: { customCss: './src/css/custom.css' },
    }],
  ],
  themeConfig: {
    image: 'img/broadcom-logo.png',
    navbar: {
      title: 'Photon OS',
      logo: { alt: 'Broadcom Logo', src: 'img/broadcom-logo.png' },
      items: [
        { to: '/', label: 'Home', position: 'left' },
        { to: '/blog', label: 'Blog', position: 'left' },
        { to: '/docs/features', label: 'Features', position: 'left' },
        { to: '/docs/contribute', label: 'Contribute', position: 'left' },
        { type: 'docSidebar', sidebarId: 'default', position: 'left', label: 'Docs' },
        { type: 'docsVersionDropdown', position: 'right' },
        { href: 'https://github.com/vmware/photon', label: 'GitHub', position: 'right' },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        { title: 'Community', items: [{ label: 'Broadcom Community', href: 'https://community.broadcom.com/tanzu/communities/tanzucommunityhomeblogs?CommunityKey=a70674e4-ccb6-46a3-ae94-7ecf16c06e24' }] },
        { title: 'More', items: [{ label: 'GitHub', href: 'https://github.com/vmware/photon' }, { label: 'Privacy Policy', href: 'https://www.broadcom.com/company/legal/privacy' }] },
      ],
      copyright: \`Last modified ${COMMIT_DATE}: <a href="https://github.com/vmware/photon/commit/${COMMIT_HASH}">${COMMIT_MESSAGE} (${COMMIT_ABBREV})</a> | A VMware By Broadcom backed Project\`,
    },
    prism: { theme: require('prism-react-renderer/themes/github'), darkTheme: require('prism-react-renderer/themes/dracula') },
    colorMode: { defaultMode: 'light' },
    docs: { versionPersistence: 'localStorage' },
    googleAnalytics: { trackingID: 'G-${RANDOM_ID}', anonymizeIP: true },
  },
};
module.exports = config;
EOF
echo "Generated placeholder GA4 ID: G-${RANDOM_ID} (replace with real ID for production)"

# Build site
echo "Building site with Docusaurus..."
npm run build > build.log 2>&1
if [ $? -ne 0 ]; then
  echo "Build failed. Check $INSTALL_DIR/build.log."
  exit 1
fi

# Set permissions
chown -R nginx:nginx "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# Verify build
if [ -f "$SITE_DIR/index.html" ]; then
  echo "Build successful: index.html exists."
else
  echo "Error: Build failed - index.html not found."
  exit 1
fi
for subdir in blog docs; do
  if [ -d "$SITE_DIR/$subdir" ]; then
    echo "Subpath /$subdir/ found."
  else
    echo "Warning: Subpath /$subdir/ missing."
  fi
done

# Set up self-signed cert
mkdir -p /etc/nginx/ssl
if [ ! -f /etc/nginx/ssl/selfsigned.crt ] || [ ! -f /etc/nginx/ssl/selfsigned.key ]; then
  echo "Generating self-signed certificate for ${IP_ADDRESS}..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt -subj "/CN=${IP_ADDRESS}"
  chmod 600 /etc/nginx/ssl/selfsigned.*
  chown nginx:nginx /etc/nginx/ssl/selfsigned.*
fi

# Configure Nginx
mkdir -p /etc/nginx/conf.d
rm -rf /etc/nginx/html/* /usr/share/nginx/html/* /var/www/html/*
cat > /etc/nginx/nginx.conf <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;

    include /etc/nginx/conf.d/*.conf;
}
EOF

NGINX_CONF="/etc/nginx/conf.d/photon-site.conf"
cat > "${NGINX_CONF}" <<EOF
server {
    listen 0.0.0.0:8080 default_server;
    server_name _;

    return 301 https://\$host:8443\$request_uri;
}

server {
    listen 0.0.0.0:8443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    root $SITE_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    error_log /var/log/nginx/photon-site-error.log warn;
    access_log /var/log/nginx/photon-site-access.log main;
}
EOF

rm -f /etc/nginx/conf.d/default.conf

# Test and restart Nginx
nginx -t
if [ $? -ne 0 ]; then
  echo "Nginx config test failed."
  exit 1
fi
systemctl restart nginx
systemctl enable nginx

# Open firewall ports and clean up old rules
iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
if ! iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
fi
if ! iptables -C INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
fi
iptables-save > /etc/systemd/scripts/ip4save

echo "Migration complete! Access the Photon site at https://${IP_ADDRESS}:8443/ (HTTP on 8080 redirects to HTTPS)."
