#!/bin/bash

# Usage: sudo ./installer.sh <install_directory>
# All-in-one reinstallable installer for self-hosting the Photon OS documentation web app on Photon OS.
# Uses fixed versions: Hugo v0.149.0 (latest), repo latest commit on photon-hugo branch.
# Assumes Photon OS (uses tdnf for packages).
# Includes all components: clones repo from GitHub, installs Hugo binary, builds site, sets up Nginx.
# Designed to be idempotent/reinstallable: checks for existing installations and updates/resets as needed.
# Requires root for tdnf and Nginx.
# Extended to allow access via VM's DHCP IP: opens port 80 in iptables firewall and makes Nginx listen on all interfaces.
# Fixes: Initializes submodules for themes, sets baseURL to "/" for self-hosting at root, fixes deprecated configs.
# Added: Installs nodejs and runs npm install for Docsy theme dependencies (PostCSS, etc.).
# Integrated: Replaces deprecated .Site.IsServer with hugo.IsServer in templates to fix build errors.
# Added: Nginx config test before restart; makes site dir readable.
# Added: Sets up self-signed HTTPS with openssl; redirects HTTP to HTTPS; opens port 443.
# Fixes: Adds googleAnalytics to config.toml; removes GA check from conditions to avoid evaluation errors.
# Fixes: Sets safe.directory for Git to avoid dubious ownership errors; ensures nginx ownership before Git ops.
# Fixes: Sets permissions on /var/www and checks SELinux to resolve Nginx 404 (Permission denied) errors.
# Fixes: Sets uglyURLs=false in config.toml to ensure subpaths like /docs-v5/ work correctly.
# Added: Cleans up /var/log/nginx/error.log, /var/log/nginx/photon-site-error.log, and hugo_build.log before installation.
# Fixes: Moves languages.en.description to [languages.en.params] for Hugo v0.129.0+ compatibility.
# Fixes: Patches render-link.html to skip urls.Parse and use safeURL directly to avoid parse errors.
# Added: Dynamically retrieves DHCP IP from local system for self-signed cert and output instructions.
# Added: Ensures subdirectories blog, docs-v3, docs-v4, docs-v5 are generated in public/.
# Added: Dynamically fetches latest COMMIT_HASH from photon-hugo branch for repo checkout.
# Fixes: Removes /etc/nginx/html/* to prevent Nginx welcome screen.
# Fixes: Runs npm audit fix after npm install; removes maxdepth from subpath list.
# Fixes: Corrects sed expression for URL cleanup to handle parentheses around URLs; ensures single [permalinks] section to fix config error.
# For subpath hosting (e.g., /photon-site): Rerun with modified baseURL and Nginx location/alias as per comments.
# Note: Self-signed cert will cause browser warnings; for production, use cert.
# Fix: Checks out branch instead of hash to avoid detached HEAD, ensuring proper Git info for Hugo.
# Added: Overrides page-meta-lastmod.html with site-wide last change for consistent footer.
# Fix: Patches head.html to use modern Google Analytics internal template instead of deprecated async version.
# Added: Patch docs-v* _index.md to use docs layout for sidebar on main pages.
# Fix: Updated patching to remove existing layout and insert new layout: docs after opening frontmatter to avoid duplication in content.
# Modification: Extract commit details from HEAD after checkout and add to config.toml as params. Update template to use these params for footer instead of GitInfo to ensure consistent and correct display matching the branch.
# Fix: Add params only if not already present to avoid duplicate key errors in TOML.
# Added: Patch docs-v* _index.md to set type: docs for sidebar and menu on main pages.
# Fix: Updated patching to remove existing type and insert new type: docs after opening frontmatter to avoid duplication.
# Fix: Use correct i18n key 'post_last_mod' in page-meta-lastmod.html for proper translation.
# Fix: Use '%-d' in git date format to remove zero-padding on day.
# Fix: Add space after "modified" in footer via i18n translation.
# Added: Flatten redundant nested docs-vX subdirs to fix double path URLs (e.g., /docs-v5/docs-v5/).
# Added: Clean up duplicated permalinks from existing content.
# Fix: Use :sections in permalink config to handle hierarchy without duplicates; remove frontmatter permalink setting; fix internal links.
# Added: Override render-image.html to disable lazy loading for printview image display fix.
# Updated: Modified render-image.html to use root-relative absolute paths for images to fix wrong relative paths in printview.
# Added: Patch quick-start-links _index.md to fix orphaned links with correct absolute paths for all versions (v3, v4, v5).
# Fix: Replaced Slack logo and link with Broadcom in footer by modifying config.toml params.links.user and patching templates to handle image URLs in icon fields.
# Fix: Updated to use local Broadcom logo and change name to "Broadcom Community".
# Fix: Removed indentation in added TOML sections to fix unmarshal error in config.toml validation.

BASE_DIR="/var/www"
INSTALL_DIR="$BASE_DIR/photon-site"
SITE_DIR="$INSTALL_DIR/public"  # Where built static files go
HUGO_VERSION="0.150.0"  # Latest version as of September 10, 2025

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

# Dynamically retrieve latest COMMIT_HASH from photon-hugo branch (for logging)
tdnf install -y git
COMMIT_HASH=$(git ls-remote https://github.com/vmware/photon.git refs/heads/photon-hugo | cut -f 1)
if [ -z "$COMMIT_HASH" ]; then
  echo "Error: Could not fetch latest commit hash from photon-hugo branch."
  exit 1
fi
echo "Using latest commit hash for reference: $COMMIT_HASH"

# Clean up log files before starting
echo "Cleaning up log files..."
truncate -s 0 /var/log/nginx/error.log 2>/dev/null || rm -f /var/log/nginx/error.log
truncate -s 0 /var/log/nginx/photon-site-error.log 2>/dev/null || rm -f /var/log/nginx/photon-site-error.log
rm -f "$INSTALL_DIR/hugo_build.log"
rm -f "$INSTALL_DIR/malformed_urls.log"

# Install dependencies if not present (tdnf skips if installed)
tdnf install -y wget curl nginx tar iptables nodejs openssl

# Ensure /usr/local/bin exists
mkdir -p /usr/local/bin

# Install Hugo if not present or wrong version
if ! command -v hugo &> /dev/null || ! hugo version | grep -q "v${HUGO_VERSION}"; then
  echo "Installing or updating Hugo to v${HUGO_VERSION}"
  wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz
  tar -xvf hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz hugo
  mv hugo /usr/local/bin/
  chmod +x /usr/local/bin/hugo
  rm -f hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz LICENSE README.md
else
  echo "Hugo v${HUGO_VERSION} already installed."
fi

# Ensure parent directory /var/www and $INSTALL_DIR have correct permissions
mkdir -p /var/www
chown -R nginx:nginx /var/www
chmod -R 755 /var/www

# Mark the repository as safe to avoid dubious ownership errors
git config --global --add safe.directory "$INSTALL_DIR"

# Clone repo
if [ -d "$INSTALL_DIR" ]; then
  echo "Deleting existing repo"
  rm -rf "$INSTALL_DIR"
fi
echo "Cloning repo"
git clone --branch photon-hugo --single-branch https://github.com/vmware/photon.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Get the actual commit details after update
COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_ABBREV=$(git log -1 --format=%h)
COMMIT_MESSAGE=$(git log -1 --format=%s)
COMMIT_DATE=$(git log -1 --format=%cd --date=format:'%B %-d, %Y')
echo "Checked out commit: $COMMIT_HASH"
echo "Commit date: $COMMIT_DATE"
echo "Commit message: $COMMIT_MESSAGE"
echo "Abbreviated hash: $COMMIT_ABBREV"

# Initialize submodules (e.g., for Docsy theme)
git submodule update --init --recursive

# Download Broadcom logo locally to static/img
mkdir -p static/img
wget -O static/img/broadcom-logo.png "https://www.broadcom.com/img/broadcom-logo.png"

# Fix redundant nested docs-vX subdirs
for ver in docs-v3 docs-v4 docs-v5; do
  NESTED_DIR="$INSTALL_DIR/content/en/$ver/$ver"
  if [ -d "$NESTED_DIR" ]; then
    echo "Flattening redundant /$ver/$ver/ nested dir..."
    mv "$NESTED_DIR"/* "$INSTALL_DIR/content/en/$ver/" 2>/dev/null || true
    rmdir "$NESTED_DIR" 2>/dev/null || true
    rm -f "$NESTED_DIR/_index.md" 2>/dev/null
  fi
done

# Fix internal links to remove double paths
echo "Fixing internal links to remove double paths..."
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v3/docs-v3/|/docs-v3/|g' {} \;
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v4/docs-v4/|/docs-v4/|g' {} \;
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i 's|/docs-v5/docs-v5/| /docs-v5/|g' {} \;

# Patch docs-v* _index.md to set type: docs for sidebar and menu on main pages
for ver in docs-v3 docs-v4 docs-v5; do
  if [ -f "$INSTALL_DIR/content/en/$ver/_index.md" ]; then
    sed -i '/^type\s*:/d' "$INSTALL_DIR/content/en/$ver/_index.md"
    sed -i '1s/^---$/---\ntype: docs/' "$INSTALL_DIR/content/en/$ver/_index.md"
  fi
done

# Install npm dependencies for theme
if [ -f package.json ]; then
  npm install --legacy-peer-deps
  npm audit fix
fi
if [ -d themes/docsy ] && [ -f themes/docsy/package.json ]; then
  cd themes/docsy
  npm install --legacy-peer-deps
  npm audit fix
  cd ../..
fi

# Fix deprecated disableKinds in config.toml
sed -i 's/[Tt]axonomy[Tt]erm/taxonomy/g' config.toml

# Fix deprecated languages.en.description
if grep -q "^description.*=" config.toml; then
  DESCRIPTION=$(grep "^description.*=" config.toml | sed 's/description *= *"\(.*\)"/\1/')
  sed -i '/^description.*=/d' config.toml
  if ! grep -q "\[languages.en.params\]" config.toml; then
    echo -e "\n[languages.en.params]\ndescription = \"$DESCRIPTION\"" >> config.toml
  else
    sed -i "/\[languages.en.params\]/a description = \"$DESCRIPTION\"" config.toml
  fi
fi

# Remove existing googleAnalytics and uglyURLs
sed -i '/^googleAnalytics/d' config.toml
sed -i '/^uglyURLs/d' config.toml

# Add uglyURLs to config.toml
echo -e "\nuglyURLs = false" >> config.toml

# Fix render-link.html to use safeURL
if [ -f layouts/partials/render-link.html ]; then
  sed -i 's/urls\.Parse \([^ ]*\)/\1 | safeURL/g' layouts/partials/render-link.html
fi

# Remove existing duplicated permalinks
find "$INSTALL_DIR/content/en" -type f -name "*.md" -exec sed -i '/^permalink: \/docs-v[3-5]\/docs-v[3-5]\//d' {} \;

# Ensure single [permalinks] section and set paths using :sections to handle hierarchy without duplicates
if grep -q "\[permalinks\]" config.toml; then
  sed -i '/\[permalinks\]/,/^[\[a-zA-Z]\|^$/d' config.toml
fi
cat >> config.toml <<EOF_PERMALINKS

[permalinks]
blog = "/blog/:year/:month/:day/:slug/"
docs-v3 = "/:sections/:slug/"
docs-v4 = "/:sections/:slug/"
docs-v5 = "/:sections/:slug/"
EOF_PERMALINKS

# Verify no duplicate [permalinks]
if [ $(grep -c "\[permalinks\]" config.toml) -gt 1 ]; then
  echo "Error: Multiple [permalinks] sections found in config.toml."
  exit 1
fi

# Fix URLs in markdown
find content/en -type f -name "*.md" -exec sed -i 's/ (\([^)]*\))/ \1/g' {} \;

# Patch templates for .Site.IsServer
find layouts themes -type f -name "*.html" -exec sed -i 's/\.Site\.IsServer/hugo.IsServer/g' {} \;

# Patch head.html for Google Analytics
if [ -f themes/photon-theme/layouts/partials/head.html ]; then
  sed -i 's/google_analytics_async.html/google_analytics.html/g' themes/photon-theme/layouts/partials/head.html
else
  echo "Warning: themes/photon-theme/layouts/partials/head.html not found. Skipping GA fix."
fi
if [ -f themes/docsy/layouts/partials/head.html ]; then
  sed -i 's/google_analytics_async.html/google_analytics.html/g' themes/docsy/layouts/partials/head.html
fi

# Set up GA4 config
sed -i '/\[services\.googleAnalytics\]/,/^$/d' config.toml
RANDOM_ID=$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 10 | head -n 1)
echo -e "\n[services.googleAnalytics]\nid = \"G-${RANDOM_ID}\"" >> config.toml
echo "Generated placeholder GA4 ID: G-${RANDOM_ID} (replace with real ID for production)"

# Add commit details to config.toml
if ! grep -q "[params]" config.toml; then
  echo -e "\n[params]" >> config.toml
fi
if ! grep -E -q "github_repo\s*=" config.toml; then
  sed -i '/\[params\]/a github_repo = "https://github.com/vmware/photon"' config.toml
fi
if ! grep -E -q "last_commit_date\s*=" config.toml; then
  sed -i '/\[params\]/a last_commit_date = "'"$COMMIT_DATE"'"' config.toml
fi
if ! grep -E -q "last_commit_message\s*=" config.toml; then
  sed -i '/\[params\]/a last_commit_message = "'"$COMMIT_MESSAGE"'"' config.toml
fi
if ! grep -E -q "last_commit_hash\s*=" config.toml; then
  sed -i '/\[params\]/a last_commit_hash = "'"$COMMIT_ABBREV"'"' config.toml
fi
if ! grep -E -q "last_commit_full_hash\s*=" config.toml; then
  sed -i '/\[params\]/a last_commit_full_hash = "'"$COMMIT_HASH"'"' config.toml
fi

# Added: Overrides page-meta-lastmod.html with hardcoded commit info from params for consistent footer matching the branch.
# Modification: Removed div to avoid duplication; added &nbsp; for spacing.
mkdir -p "$INSTALL_DIR/layouts/partials"  # Ensure override dir exists
cat > "$INSTALL_DIR/layouts/partials/page-meta-lastmod.html" <<-'HEREDOC_LASTMOD'
{{- if or (.Params.hide_meta) (eq .Params.show_lastmod false) -}}
{{- else -}}
{{ i18n "post_last_mod" }}&nbsp;{{ .Site.Params.last_commit_date }}: <a href="{{ .Site.Params.github_repo }}/commit/{{ .Site.Params.last_commit_full_hash }}">{{ .Site.Params.last_commit_message }} ({{ .Site.Params.last_commit_hash }})</a>
{{- end -}}
HEREDOC_LASTMOD

# Debug: Verify the generated template
echo "Verifying page-meta-lastmod.html content..."
cat "$INSTALL_DIR/layouts/partials/page-meta-lastmod.html"
if grep -q "^[[:space:]]" "$INSTALL_DIR/layouts/partials/page-meta-lastmod.html"; then
  echo "Warning: Leading whitespace detected in page-meta-lastmod.html."
fi

# Fix: Replace Slack with Broadcom in config.toml
sed -i 's/name = "Slack"/name = "Broadcom Community"/g' config.toml
sed -i 's/url = "https:\/\/vmwarecode.slack.com"/url = "https:\/\/community.broadcom.com\/tanzu\/communities\/tanzucommunityhomeblogs?CommunityKey=a70674e4-ccb6-46a3-ae94-7ecf16c06e24"/g' config.toml
sed -i 's/icon = "fab fa-slack"/icon = "\/img\/broadcom-logo.png"/g' config.toml
sed -i 's/desc = "Join the VMware {code} Slack community!"/desc = "Broadcom Community for Photon OS"/g' config.toml

# Fix: Patch templates to handle image URLs in icon fields for social links
find layouts themes -type f -name "*.html" -exec sed -i 's/<i class="{{ .icon }}"[^>]*>\&nbsp;<\/i>/{{ if or (hasPrefix .icon "http:\/\/") (hasPrefix .icon "https:\/\/") (hasPrefix .icon "\/") }}<img src="{{ .icon }}" alt="{{ .name }}" style="height:1em; width:auto; vertical-align:middle;">\&nbsp;{{ else }}<i class="{{ .icon }}" aria-hidden="true">\&nbsp;<\/i>{{ end }}/g' {} \;

# Added: Override render-image.html to disable lazy loading for printview image display fix.
# Updated: Use root-relative absolute paths for local relative images to fix path issues in printview.
mkdir -p "$INSTALL_DIR/layouts/_default/_markup"
cat > "$INSTALL_DIR/layouts/_default/_markup/render-image.html" <<EOF
{{ \$src := .Destination }}
{{ if or (hasPrefix \$src "http://") (hasPrefix \$src "https://") (hasPrefix \$src "/") }}
  {{ \$src = \$src | safeURL }}
{{ else }}
  {{ \$src = printf "%s%s" .Page.RelPermalink \$src | safeURL }}
{{ end }}
<img src="{{ \$src }}" alt="{{ .Text }}" {{ with .Title }}title="{{ . }}"{{ end }} />
EOF

# Validate config.toml
echo "Validating config.toml..."
/usr/local/bin/hugo config > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: config.toml validation failed. Check $INSTALL_DIR/config.toml."
  /usr/local/bin/hugo config 2>&1 | tee "$INSTALL_DIR/config_validation.log"
  echo "Validation errors logged to $INSTALL_DIR/config_validation.log"
  exit 1
fi

# Clear existing public directory
rm -rf "$SITE_DIR/*"

# Build site with Hugo
echo "Building site with Hugo..."
set -o pipefail
/usr/local/bin/hugo --minify --baseURL "/" --logLevel debug --enableGitInfo -d public 2>&1 | tee hugo_build.log
if [ $? -ne 0 ]; then
  echo "Hugo build failed. Check hugo_build.log."
  exit 1
fi

# Make site dir readable by nginx
mkdir -p "$SITE_DIR"
chown -R nginx:nginx "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

# Check SELinux
if command -v getenforce &> /dev/null && [ "$(getenforce)" = "Enforcing" ]; then
  echo "Warning: SELinux is in Enforcing mode, which may cause permission issues."
  echo "To disable temporarily, run: setenforce 0"
  echo "To disable permanently, edit /etc/selinux/config and set SELINUX=disabled, then reboot."
fi

# Debug permissions
echo "Directory permissions for Nginx:"
ls -ld "$BASE_DIR" "$INSTALL_DIR" "$SITE_DIR"
ls -l "$SITE_DIR/index.html" || echo "index.html not found"

# Check site files
if [ -f "$SITE_DIR/index.html" ]; then
  echo "Build successful: index.html exists."
else
  echo "Error: Build failed - index.html not found in $SITE_DIR. Check hugo_build.log."
  exit 1
fi
echo "Site files present: $(ls -l $SITE_DIR | grep index.html)"

# Verify subdirectories
for subdir in blog docs-v3 docs-v4 docs-v5; do
  if [ -d "$SITE_DIR/$subdir" ] && [ -f "$SITE_DIR/$subdir/index.html" ]; then
    echo "Subpath /$subdir/ found with index.html."
  else
    echo "Warning: Subpath /$subdir/ missing or incomplete. Check $SITE_DIR/$subdir/ and hugo_build.log."
  fi
done

# Added: Patch quick-start-links index.html to fix orphaned links with correct absolute paths for all versions
for ver in docs-v3 docs-v4 docs-v5; do
  QL_FILE="$SITE_DIR/$ver/quick-start-links/index.html"
  if [ -f "$QL_FILE" ]; then
    echo "Patching quick-start-links index.html for $ver to fix orphaned links..."
	sed -i 's|<a href=..\/..\/overview\/>Overview</a>|<a href=..\/overview\/>Overview</a>|g' $QL_FILE
	sed -i 's|<a href=..\/..\/installation-guide\/downloading-photon\/>Downloading Photon OS</a>|<a href=..\/installation-guide\/downloading-photon\/>Downloading Photon OS</a>|g' $QL_FILE
	sed -i 's|<a href=..\/..\/installation-guide\/building-images\/build-iso-from-source\/>Build an ISO from the source code for Photon OS</a>|<a href=..\/installation-guide\/building-images\/build-iso-from-source\/>Build an ISO from the source code for Photon OS</a>|g' $QL_FILE
  fi
done

# Debug content structure
echo "Content structure in content/en/:"
find "$INSTALL_DIR/content/en" -type f -name "_index.md"

# Analyze subpaths
echo "Generated subpaths in public/:"
find "$SITE_DIR" -type d

# Ensure Nginx conf.d directory exists
mkdir -p /etc/nginx/conf.d

# Remove default HTML
rm -rf /etc/nginx/html/* /usr/share/nginx/html/* /var/www/html/*

# Replace nginx.conf
cat > /etc/nginx/nginx.conf <<EOF_NGINX
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
EOF_NGINX

# Set up self-signed cert
mkdir -p /etc/nginx/ssl
if [ -f /etc/nginx/ssl/selfsigned.crt ]; then
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt -subj "/CN=${IP_ADDRESS}"
fi

# Configure Nginx
NGINX_CONF="/etc/nginx/conf.d/photon-site.conf"
echo "Configuring Nginx (overwriting if exists)"
cat > "${NGINX_CONF}" <<EOF_PHOTON
server {
    listen 0.0.0.0:80 default_server;
    server_name _;

    return 301 https://\$host\$request_uri;
}

server {
    listen 0.0.0.0:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    root $SITE_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    error_log /var/log/nginx/photon-site-error.log warn;
    access_log /var/log/nginx/photon-site-access.log main;
}
EOF_PHOTON

# Remove default Nginx configs
rm -f /etc/nginx/conf.d/default.conf /etc/nginx/default.d/*.conf /etc/nginx/sites-enabled/default /etc/nginx/nginx.conf.bak

# List Nginx configs
echo "Nginx configs present:"
ls -l /etc/nginx/ /etc/nginx/conf.d/

# Test and restart Nginx
nginx -t
if [ $? -ne 0 ]; then
  echo "Nginx config test failed."
  exit 1
fi
systemctl restart nginx
if [ $? -ne 0 ]; then
  echo "Nginx restart failed. Check /var/log/nginx/error.log and /var/log/nginx/photon-site-error.log."
  exit 1
fi

# Enable Nginx on boot
systemctl enable nginx

# Open firewall ports
mkdir -p /etc/systemd/scripts
if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT
fi
if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT
fi
iptables-save > /etc/systemd/scripts/ip4save

# Verify build and access
if [ -f "$SITE_DIR/index.html" ]; then
  echo "Build successful: index.html exists."
else
  echo "Error: Build failed - index.html not found in $SITE_DIR. Check hugo_build.log."
  exit 1
fi
for subdir in blog docs-v3 docs-v4 docs-v5; do
  if [ -d "$SITE_DIR/$subdir" ] && [ -f "$SITE_DIR/$subdir/index.html" ]; then
    echo "Subpath /$subdir/ found with index.html."
  else
    echo "Warning: Subpath /$subdir/ missing or incomplete. Check $SITE_DIR/$subdir/ and hugo_build.log."
  fi
done

echo "Installation complete! Access the Photon site at https://${IP_ADDRESS}/ (HTTP redirects to HTTPS)."
