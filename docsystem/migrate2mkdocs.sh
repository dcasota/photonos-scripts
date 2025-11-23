#!/bin/bash

# Usage: sudo ./migrate2mkdocs.sh
# All-in-one migration script for moving the Photon OS documentation web app from Hugo to MkDocs on Photon OS.
# Assumes Photon OS (uses tdnf for packages).
# Idempotent: Checks for existing installations and updates/resets as needed.
# Requires root for tdnf, Nginx, and firewall.
# Enforces website on port 8080 (HTTP) and 8443 (HTTPS) via Nginx; opens ports 8080/8443 in iptables.
# Migrates content, sets up versioning by building separate subdirs for older versions, configures nav/footer, builds site, sets up Nginx with HTTPS.
# Fixes: Handles Broadcom branding, commit info in footer, GA4 placeholder.
# Note: Self-signed cert will cause browser warnings; replace with real cert for production.
# For subpath hosting, modify docs_url in mkdocs.yml and Nginx alias.

BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site-mkdocs"
SITE_DIR="$INSTALL_DIR/site"  # Where built static files go
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
tdnf install -y wget curl nginx tar iptables openssl git awk python3 python3-pip

# Install MkDocs and Material theme
pip3 install mkdocs mkdocs-material

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

# Download Broadcom logo if not in img
mkdir -p "$TMP_REPO/docs/img"
if [ ! -f "$TMP_REPO/docs/img/broadcom-logo.png" ]; then
  wget -O "$TMP_REPO/docs/img/broadcom-logo.png" "https://www.broadcom.com/img/broadcom-logo.png"
fi

# Create or reset MkDocs project
if [ -d "$INSTALL_DIR" ]; then
  echo "Deleting existing MkDocs project"
  rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
mkdocs new .

# Function to fix markdown files
fix_markdown() {
  local dir=$1
  find "$dir" -type f -name "*.md" -exec sed -i 's/downloading-photon\.md/downloading-photon-os.md/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/upgrading-the-kernel-version-requires-grub-changes-for-aws-and-gce-images.md/\/docs\/upgrading-the-kernel-version-requires-grub-changes-for-aws-and-gce-images/ig' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../../../images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../../images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|./images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|/docs/images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../../../docs/images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../../docs/images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|./installation-guide/images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|installation-guide/images|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|installation-gui/img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|do/img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|/do/img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../../../do/img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|../../img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|\./\/img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|\.\./\.\./\.\./\/img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|//img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's|.././img|/img|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/<br \/>/\n/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/<br\/>/\n/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/<br>/\n/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/<br >/\n/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/{{\s*<\s*highlight\s*\(\w+\)\s*>}}/``` \1/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/{{\s*<\s*/highlight\s*>}}/``` /g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/{{<\s*/endhighlight\s*>}} /```/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/{{<[^>]*>}}//g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i '/<!doctype/dI' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/<!\--/{/* /g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/-->/ */}/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/<!---/{/* /g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/--->/ */}/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i -r 's/<([a-zA-Z0-9_-]+)/\&lt;\1/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i -r 's/([a-zA-Z0-9_-]+)>/\1\&gt;/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i -r 's|</([a-zA-Z0-9_-]+)>|\&lt;/\1\&gt;|g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i -r 's/<([^a-zA-Z0-9_-])/\&lt;\1/g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/&/\&amp;/g' {} \;
  find "$dir" -type f -name "*.md" -exec awk -i inplace 'BEGIN { in_code = 0 } /^```/ { in_code = !in_code; print; next } { if (in_code == 0) { gsub(/\{/, "\\{"); gsub(/\}/, "\\}") } print }' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i '/^```$/s/^```$/```text/' {} \;
  # Add language to XML code block in adding-a-new-repository.md
  for file in $(find "$dir" -name "adding-a-new-repository.md"); do
    if [ -f "$file" ]; then
      sed -i '/cat metalink/{n; s/```/```xml/}' "$file"
    fi
  done
  # Specific fix for here-doc in adding-a-new-repository.md
  for file in $(find "$dir" -name "adding-a-new-repository.md"); do
    if [ -f "$file" ]; then
      sed -i '/cat > \/etc\/yum.repos.d\/apps.repo << "EOF"/i ```bash' "$file"
      sed -i '/EOF/a ```' "$file"
    fi
  done
  # Remove Hugo-specific frontmatter
  find "$dir" -type f -name "*.md" -exec sed -i 's/type: .*//g' {} \;
  find "$dir" -type f -name "*.md" -exec sed -i 's/permalink: .*//g' {} \;
}

# Migrate static assets (images)
mkdir -p docs/img
cp -r "$TMP_REPO/static/"* docs/img/ 2>/dev/null || true
find "$TMP_REPO" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.svg" -o -name "*.gif" \) -exec cp --no-clobber {} docs/img/ \;

# Migrate home
if [ -f "$TMP_REPO/content/en/_index.md" ]; then
  cp "$TMP_REPO/content/en/_index.md" docs/index.md
else
  echo "# Photon OS" > docs/index.md
  echo "Welcome to Photon OS documentation." >> docs/index.md
fi

# Migrate blog
mkdir -p docs/blog
cp -r "$TMP_REPO/content/en/blog/"* docs/blog/ 2>/dev/null || true
# Fix blog frontmatter dates if needed
find docs/blog -type f -name "*.md" -exec sed -i 's/date: \([0-9-]\+\(T[0-9:+-]\+\)\?\)/date: "\1"/g' {} \;
# Ensure all blog posts have a date; derive from filename if missing
for file in $(find docs/blog -type f -name "*.md"); do
  if ! grep -q '^date:' "$file"; then
    base=$(basename "$file" .md)
    date_str=$(echo "$base" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
    [ -z "$date_str" ] && date_str="2020-01-01"
    sed -i "1i ---\ndate: \"${date_str}\"\n---\n" "$file"
  fi
done

# Migrate latest docs (5.0)
mkdir -p docs/docs
cp -r "$TMP_REPO/content/en/docs-v5/"* docs/docs/ 2>/dev/null || true

# Rename all _index.md to index.md
find docs -name "_index.md" -exec sh -c 'mv "$0" "${0%_index.md}index.md"' {} \;

# Fix links for main (latest)
find docs -type f -name "*.md" -exec sed -i 's|/docs-v[3-5]/|/docs/|g' {} \;

# Apply fixes to main content
fix_markdown docs

# Configure mkdocs.yml for main site
RANDOM_ID=$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 10 | head -n 1)
cat > mkdocs.yml <<EOF
site_name: Photon OS
site_url: https://${IP_ADDRESS}:8443/
site_description: A VMware By Broadcom backed Project
repo_url: https://github.com/vmware/photon
theme:
  name: material
  logo: img/broadcom-logo.png
  favicon: img/favicon.ico
  palette:
    - media: "(prefers-color-scheme: light)"
      scheme: default
      primary: indigo
      accent: indigo
    - media: "(prefers-color-scheme: dark)"
      scheme: slate
      primary: indigo
      accent: indigo
nav:
  - Home: index.md
  - Blog: blog/
  - Docs: docs/
  - 3.0: /3.0/
  - 4.0: /4.0/
extra:
  copyright: 'Last modified ${COMMIT_DATE}: <a href="https://github.com/vmware/photon/commit/${COMMIT_HASH}">${COMMIT_MESSAGE} (${COMMIT_ABBREV})</a> | A VMware By Broadcom backed Project'
plugins:
  - search
markdown_extensions:
  - tables
  - attr_list
  - md_in_html
  - admonition
  - codehilite
  - pymdownx.superfences
  - pymdownx.details
  - pymdownx.tabbed
  - pymdownx.tasklist
  - def_list
extra_javascript:
  - https://www.googletagmanager.com/gtag/js?id=G-${RANDOM_ID}
  - javascripts/config.js
EOF
echo "Generated placeholder GA4 ID: G-${RANDOM_ID} (replace with real ID for production)"

# Add GA script
mkdir -p overrides/javascripts
cat > overrides/javascripts/config.js <<EOF
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());
gtag('config', 'G-${RANDOM_ID}');
EOF

# Build main site
echo "Building main site with MkDocs..."
mkdocs build > build.log 2>&1
if [ $? -ne 0 ]; then
  echo "Build failed. Check $INSTALL_DIR/build.log."
  exit 1
fi

# Build older versions
for ver_info in "3.0 docs-v3 3" "4.0 docs-v4 4"; do
  set $ver_info
  ver=$1
  hugodir=$2
  alias_num=$3
  echo "Building version $ver..."
  rm -rf docs_temp
  mkdir docs_temp
  mkdir -p docs_temp/img
  cp -r docs/img/* docs_temp/img/
  cp -r "$TMP_REPO/content/en/$hugodir/"* docs_temp/ 2>/dev/null || true
  find docs_temp -name "_index.md" -exec sh -c 'mv "$0" "${0%_index.md}index.md"' {} \;
  find docs_temp -type f -name "*.md" -exec sed -i "s|/docs-v${alias_num}/|/|g" {} \;
  fix_markdown docs_temp
  cat > mkdocs_temp.yml <<EOF
site_name: Photon OS $ver
site_url: https://${IP_ADDRESS}:8443/$ver/
theme:
  name: material
  logo: img/broadcom-logo.png
  favicon: img/favicon.ico
  palette:
    - media: "(prefers-color-scheme: light)"
      scheme: default
      primary: indigo
      accent: indigo
    - media: "(prefers-color-scheme: dark)"
      scheme: slate
      primary: indigo
      accent: indigo
nav:
  - Main Site: /
  - Docs $ver: /
extra:
  copyright: 'Photon OS $ver Documentation | A VMware By Broadcom backed Project'
plugins:
  - search
markdown_extensions:
  - tables
  - attr_list
  - md_in_html
  - admonition
  - codehilite
  - pymdownx.superfences
  - pymdownx.details
  - pymdownx.tabbed
  - pymdownx.tasklist
  - def_list
EOF
  mkdocs build --config-file mkdocs_temp.yml --site-dir site/$ver
  rm mkdocs_temp.yml
  rm -rf docs_temp
done

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
for subdir in blog docs 3.0 4.0; do
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
        try_files \$uri \$uri/index.html =404;
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
